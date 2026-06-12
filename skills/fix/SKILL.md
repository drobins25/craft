---
name: craft:fix
description: "Adhoc fix workflow for small targeted code fixes without the full story ceremony. Use when the orchestrator encounters a bug, misalignment, broken interaction, or post-implementation issue that has a clear root cause and surgical solution. Triggers on: 'fix this', 'this is broken', 'the alignment is off', 'that button doesn't work', 'quick fix', 'adhoc fix', 'patch this', post-story corrections, or any situation where the write gate blocks a small obvious fix. Do NOT use for new features, design exploration, or changes requiring creative spark."
allowed-tools: ["Read", "Edit", "Write", "Glob", "Grep", "Bash"]
---

# Adhoc Fix

You are the orchestrator making a targeted fix. No implementer agent, no chunks, no story ceremony. You investigate, reason about the root cause, confirm your confidence, make the edit, and verify the symptom is gone.

The fix file you create in `.craft/fixes/` is permanent record. A month from now, these files across all projects reveal patterns - what keeps breaking, which story types produce bugs, where the pipeline has gaps. Write them with that future reader in mind.

## Why This Exists

The full story ceremony (story file, chunks, implementer agent, validation loops) is right for features and complex work. But when a page's alignment is off, a button doesn't respond, or a font weight renders wrong - and you can see exactly why - spinning up that machinery wastes time and adds no value. This skill lets you fix and move on, while still tracking the problem for pattern analysis.

## The Flow

### Step 1: Create the Fix File

Create `.craft/fixes/` if it doesn't exist, then write the fix file:

```bash
mkdir -p "${CRAFT_PROJECT_ROOT:-.}/.craft/fixes"
```

Write to `.craft/fixes/[descriptive-name].md` with this structure:

```markdown
---
name: [descriptive-kebab-case-name]
status: proposed
created: [YYYY-MM-DD]
project: [project name]
category: [see categories below]
source_story: [story that introduced the bug, if known]
source_cycle: [cycle name, if known]
files_changed: 0
lines_changed: 0
trigger: [how the problem was discovered]
lesson_scope:
---

## Symptom
[What you observed - be specific. "Font weights look wrong in OG image" not "OG image broken"]

## Investigation
[What you actually checked - files read, endpoints hit, browser inspected]

## Root Cause
[Why it's broken. This must be structural, not a guess. "The loadGoogleFont regex captures only the first src:url match, so weight 400 is used for all font entries" - not "something is wrong with the fonts"]

## Solution
[What to change, which files, and WHY this addresses the root cause]

## Confidence Check
Am I 100% certain this solution resolves the root cause?
[Answer here - see Step 3]

## Validation
[Filled after Step 5]
```

**Categories** (pick the one that best fits):
- `alignment` - layout, spacing, positioning issues
- `broken-interaction` - buttons, links, forms that don't respond correctly
- `misinterpretation` - story intent was implemented differently than intended
- `infrastructure` - build errors, config issues, missing dependencies, chain breaks
- `style` - colors, shadows, borders, visual treatments
- `typography` - font weights, sizes, line-height, tracking

### Step 2: Investigate

Before writing the Root Cause section, actually look at the problem. Read the relevant code. If it's a visual issue, use the browser (screenshot, inspect elements). If it's a build issue, read the error output. Don't guess based on the symptom description alone.

Update the Investigation section with what you checked.

### Step 3: Confidence Check

After writing the Root Cause and Solution sections, pause and ask yourself:

> **Am I 100% certain this solution resolves the root cause?**

Write your answer in the Confidence Check section. This is the moment that matters - you're about to edit code, and this question forces you to evaluate your own reasoning before acting.

**If yes** with clear causal reasoning ("The regex captures one URL, my fix captures per-weight URLs, so each font entry gets the correct weight file") - continue to Step 4.

**If no**, hedging ("should fix it", "I think this will work", "worth trying"), or your thinking evolved significantly during investigation (you started with one theory and ended up somewhere different) - this is more complex than an adhoc fix. Escalate:

1. Update the fix file status to `escalated`
2. Tell the user: "This is more complex than an adhoc fix - [explain why]. Want me to create a story for it?"
3. Stop. Do not edit code.

The evolution check is important: if your understanding of the problem changed substantially between Symptom and Solution, that's a signal there's hidden complexity. A real adhoc fix has a straight line from symptom to root cause to solution.

### Step 4: Apply the Fix

Set the write gate, write a safety marker, make your edits, then clean up:

```bash
# Open the write gate
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh CRAFT_WRITE_ENABLED "true" "${CRAFT_PROJECT_ROOT:-.}"

# Safety marker - session-start.sh clears orphans
echo "$(date -u +%Y-%m-%dT%H:%M:%S)" > "${CRAFT_PROJECT_ROOT:-.}/.craft/.active-fix"
```

Make your edits directly using Edit/Write tools. You are the fixer - no implementer agent.

**Soft scope check:** If you find yourself touching 5+ files, pause and tell the user: "This is touching [N] files - that's getting bigger than a typical fix. Want me to continue or create a story?" Let them decide.

After edits, close the gate:

```bash
# Close the write gate
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh CRAFT_WRITE_ENABLED "" "${CRAFT_PROJECT_ROOT:-.}"

# Remove safety marker
rm -f "${CRAFT_PROJECT_ROOT:-.}/.craft/.active-fix"
```

Update the fix file: set `status: applied`, update `files_changed` and `lines_changed`.

### Step 5: Validate the Symptom

This is not "run the build and see if it passes." You must verify the **original symptom** is resolved.

- **Visual fixes** (alignment, style, typography, broken-interaction): You must use Chrome DevTools MCP to navigate to the affected page, take a screenshot, and visually confirm the fix. "Tests pass" is not validation for UI issues - the whole point is what the user sees. Use `take_screenshot`, `evaluate_script`, or `take_snapshot` to verify.
- **Build/type/lint errors**: Run the specific check that was failing and confirm it passes.
- **Infrastructure** (chain breaks, state issues): Trace the flow and confirm the safety net exists.

Write what you checked and what you observed in the Validation section.

If validation fails - the symptom persists or a new problem appeared - update the fix file with what happened and reassess. You might need to escalate to a story at this point.

If validation passes: update `status: validated`. Continue to Step 5b.

### Step 5b: Commit the Fix

Stage ONLY the files the fix touched - never the whole tree. A fix commit is a receipt of the fix, not a snapshot of whatever else is sitting in the working directory. The staged set comes from the fix file's `files_changed` (updated in Step 4); if that list is empty or stale, fall back to `git diff --name-only HEAD` so the fix's real changes are never silently dropped.

```bash
cd "${CRAFT_PROJECT_ROOT:-.}"

# Stage each file from the fix file's files_changed list
git add -- [path from files_changed] [path from files_changed] ...

# Fallback ONLY if files_changed is empty or 0: stage the tracked changes
# git diff --name-only HEAD | while IFS= read -r f; do git add -- "$f"; done

git diff --cached --quiet || git commit -m "fix: [short description of what was fixed]" --no-verify
```

Do NOT use `git add -A` or `git add .` - either would sweep unrelated untracked files (scratch files, local configs, secrets) into the fix commit.

For example: `fix: cycle card hover delay not respecting transition timing`

If nothing is staged (rare - you just made edits), skip the commit.

### Step 6: Lesson Capture

After validation passes, check if there's a workflow lesson worth capturing. Not every fix has one - pure code bugs (typo, wrong value) usually don't. But when the fix reveals a process gap - something craft or the user could have done differently to prevent the fix entirely - that's a lesson.

Use **AskUserQuestion**:
```
question: "Was there a workflow lesson here - something we should do differently next time?"
header: "Lesson"
options:
  - label: "Yes, let me describe it"
    description: "Capture a process lesson from this fix"
  - label: "No, just a code fix"
    description: "No workflow lesson - skip"
```

**If "No":** Skip to Step 7.

**If "Yes":** The user provides the lesson context. Write a `## Lesson` section to the fix file:

```markdown
## Lesson
**Scope:** craft | project
**What went wrong:** [process/workflow mistake - not the code bug, but why it happened]
**Rule:** [what to do differently next time]
**Applies to:** [comma-separated contexts where this rule matters]
```

**Scope guide:**
- `craft` - the harness, orchestrator, or workflow process caused or missed the issue. Examples: didn't check for uncommitted changes, skipped a validation step, wrote to wrong branch.
- `project` - the codebase or planning had a gap. Examples: missing mobile constraint, schema not updated, pattern copied from wrong context.

Also update the fix file frontmatter: add `lesson_scope: craft` or `lesson_scope: project`.

If the user's description is brief, fill in the structured fields based on what you know from the root cause. Show it to them for confirmation before writing.

### Step 7: Close

Output a summary:

```
## Adhoc Fix: [name]
Category: [category]
Files: [N] changed, [N] lines
Root cause: [one sentence]
Validation: [what was checked, result]
Lesson: [one sentence, or "none"]
```

## Guard Rails

**Active story check:** If CURRENT_STORY is set in `.global-state`, warn: "There's an active story ([name]). Apply this fix within that story's scope, or complete/pause the story first." Do not set CRAFT_WRITE_ENABLED if it's already set by a story - that would create overlapping write sessions.

**No design decisions:** If the fix requires choosing between approaches, exploring visual directions, or creative input - it's a story, not a fix. Escalate.

**No new features:** Fixes correct existing behavior. If the solution adds something that wasn't there before (a new component, a new API endpoint), it's a story.
