# Adhoc Fix Flow (reference - read inline by the craft:adhoc shell)

This is the FIX flavor: something is broken, there is a symptom, and you can see the root cause. You investigate, reason about the root cause, confirm your confidence, make the edit, and verify the symptom is gone. The shell has already classified the request, opened the write gate, and created the close-obligation tasks - this file owns the fix record, the confidence gate, the edits, and validation. Hand back to the shell for the commit and gate close.

The fix file you create in `.craft/fixes/` is permanent record. A month from now, these files across all projects reveal patterns - what keeps breaking, which story types produce bugs, where the pipeline has gaps. Write them with that future reader in mind.

## Step 1: Create the Fix File

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

## Step 2: Investigate

Before writing the Root Cause section, actually look at the problem. Read the relevant code. If it's a visual issue, use the browser (screenshot, inspect elements). If it's a build issue, read the error output. Don't guess based on the symptom description alone.

Update the Investigation section with what you checked.

## Step 3: Confidence Check

After writing the Root Cause and Solution sections, pause and ask yourself:

> **Am I 100% certain this solution resolves the root cause?**

Write your answer in the Confidence Check section. This is the moment that matters - you're about to edit code, and this question forces you to evaluate your own reasoning before acting.

**If yes** with clear causal reasoning ("The regex captures one URL, my fix captures per-weight URLs, so each font entry gets the correct weight file") - continue to Step 4.

**If no**, hedging ("should fix it", "I think this will work", "worth trying"), or your thinking evolved significantly during investigation (you started with one theory and ended up somewhere different) - this is more complex than an adhoc fix. Escalate:

1. Update the fix file status to `escalated`
2. Tell the user: "This is more complex than an adhoc fix - [explain why]. Want me to create a story for it?"
3. Stop. Do not edit code. Hand back to the shell to close the gate.

The evolution check is important: if your understanding of the problem changed substantially between Symptom and Solution, that's a signal there's hidden complexity. A real adhoc fix has a straight line from symptom to root cause to solution.

## Step 4: Apply the Fix

Make your edits directly using Edit/Write tools. You are the fixer - no implementer agent. (The shell already opened the write gate; its soft scope check applies while you edit.)

Update the fix file: set `status: applied`, update `files_changed` and `lines_changed`.

## Step 5: Validate the Symptom

This is not "run the build and see if it passes." You must verify the **original symptom** is resolved.

- **Visual fixes** (alignment, style, typography, broken-interaction): You must use Chrome DevTools MCP to navigate to the affected page, take a screenshot, and visually confirm the fix. "Tests pass" is not validation for UI issues - the whole point is what the user sees. Use `take_screenshot`, `evaluate_script`, or `take_snapshot` to verify.
- **Build/type/lint errors**: Run the specific check that was failing and confirm it passes.
- **Infrastructure** (chain breaks, state issues): Trace the flow and confirm the safety net exists.

Write what you checked and what you observed in the Validation section.

If validation fails - the symptom persists or a new problem appeared - update the fix file with what happened and reassess. You might need to escalate to a story at this point.

If validation passes: update `status: validated`. Hand back to the shell for the commit (Step 5 there), then return here for lesson capture.

## Step 6: Lesson Capture

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

## Step 7: Close

Output a summary:

```
## Adhoc Fix: [name]
Category: [category]
Files: [N] changed, [N] lines
Root cause: [one sentence]
Validation: [what was checked, result]
Lesson: [one sentence, or "none"]
```

Then hand back to the shell to close the gate (Step 6 there).
