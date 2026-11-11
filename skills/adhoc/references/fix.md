# Adhoc Fix Flow (reference - read inline by the craft:adhoc shell)

This is the FIX flavor: something is broken, there is a symptom, and you can see the root cause. You investigate, reason about the root cause, confirm your confidence, make the edit, and verify the symptom is gone. The shell has already classified the request, opened the write gate, and created the close-obligation tasks - this file owns the fix record, the confidence gate, the edits, validation, and the todo-satisfaction beat. Hand back to the shell for the commit and gate close.

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
source_story: [story that introduced the bug, if known - e.g. riff-the-game]
source_cycle: [cycle name, if known]
planned_test: [for a defect found after source_story completed - the planned test case in that story that should have caught it, quoted as the plan names it, or none; blank when there is no source story]
review: [name of the review record this fix came from, e.g. 2026-10-18-branch-feature-x - empty when not from a review]
files_changed: 0
lines_changed: 0
trigger: [how the problem was discovered]
satisfied_todo: [stamped by the todo-satisfaction beat - <todo-slug> or none-matched]
---

## Symptom
[What you observed - be specific. "Font weights look wrong in OG image" not "OG image broken"]

## Investigation
[What you actually checked - files read, endpoints hit, browser inspected]

## Root Cause
[Why it's broken. This must be structural, not a guess. "The loadGoogleFont regex captures only the first src:url match, so weight 400 is used for all font entries" - not "something is wrong with the fonts"]

## Solution
[What to change, which files, and WHY this addresses the root cause]

## Mechanism
[The changed line - added or removed - quoted verbatim with file:line, and one clause saying how that change stops the symptom.]

## Confidence Check
claim | evidence | holds
[One row per claim the fix depends on, each with the tool result that shows it - see Step 3]

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

**`planned_test`** (filled at record creation, one line, no question asked): when `source_story` names a story and the defect was found after that story completed - a review finding, a bug from the pile, an analyze finding, something the user hit - open the story file and read every chunk's `**Test cases:**` list. Write the one planned case whose name covers the behavior that broke, quoted exactly as the plan names it. When no planned case covers that behavior, write `none`. Leave it blank only when there is no source story. Judge by the behavior, not the file: a case that touches the same file but pins a different behavior is not a match. Over a cycle, the `none` count is the planner's miss rate, read straight from the records.

**`review`**: when the handoff brief names a review record, set `review:` to that record's name. This flow never opens or edits the review record - the review's close-out fills the finding's line once this record lands.

## Step 2: Investigate

Before writing the Root Cause section, actually look at the problem. Read the relevant code. If it's a visual issue, use the browser (screenshot, inspect elements) - if the shell already took a classification screenshot, that IS your symptom evidence; don't re-take it. If it's a build issue, read the error output. Don't guess based on the symptom description alone.

Update the Investigation section with what you checked.

## Step 3: Confidence Check

After writing the Root Cause and Solution sections, check the evidence before you edit.

Fill Mechanism first. If no line can be quoted, escalate.
A quoted line that only points at another file is not the mechanism - quote the line it points at.

List every claim this fix depends on: about the code you change, and about what it relies on (what sets or clears a value it reads, who calls it, and every place the flow can end, including inside any command or skill it hands off to). Beside each, put the tool result from this session that shows it: the command and its output, or the file:line you read. A claim with no tool result gets one now.

Write the list in the Confidence Check section as `claim | evidence | holds`. This is the moment that matters - you're about to edit code, and a claim you never checked is where a confident fix goes wrong.

**If every claim holds** - continue to Step 4.

**If a result contradicts a claim**, or your thinking evolved significantly during investigation (you started with one theory and ended up somewhere different) - this is more complex than an adhoc fix. Escalate:

1. Update the fix file status to `escalated`
2. Tell the user: "This is more complex than an adhoc fix - [explain why]. Want me to create a story for it?"
3. Stop. Do not edit code. Hand back to the shell to close the gate.

The evolution check is important: if your understanding of the problem changed substantially between Symptom and Solution, that's a signal there's hidden complexity. A real adhoc fix has a straight line from symptom to root cause to solution.

## Step 4: Apply the Fix

Make your edits directly using Edit/Write tools. You are the fixer - no implementer agent. (The shell already opened the write gate; its soft scope check applies while you edit.)

Update the fix file: set `status: applied`, update `files_changed` and `lines_changed`.

## Step 5: Validate the Symptom

This is not "run the build and see if it passes." You must verify the **original symptom** is resolved.

- **Visual fixes** (alignment, style, typography, broken-interaction): You must use Chrome DevTools MCP to navigate to the affected page, take a screenshot, and visually confirm the fix. "Tests pass" is not validation for UI issues - the whole point is what the user sees. Before the screenshot, clear any leftover craft:dial injection (via `evaluate_script`: remove `craft-dial-style`, `craft-dial-panel`, every `[data-craft-dial-injected]` node, and delete `documentElement.dataset.craftDial` - idempotent on a clean page, see `commands/references/dial-inject.md`). Then clear leftover annotate changes: run `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/annotate-run.sh" review-clear` - a printed `() => { ... }` line goes to `evaluate_script` verbatim, `OPEN <id> <subject>` lines mean leave the page as found and name each open run, and a failing command means skip and say so (see `commands/references/annotate-overlay.md`, "Clearing leftovers before a review"). Record the outcome in the fix's Validation. After the first browser call, run `node "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/devtools-launch.cjs" notice`; a printed line is said to the user verbatim, nothing printed means nothing said. Use `take_screenshot`, `evaluate_script`, or `take_snapshot` to verify.
- **Build/type/lint errors**: Run the specific check that was failing and confirm it passes.
- **Infrastructure** (chain breaks, state issues): Trace the flow and confirm the safety net exists.
- **A fix that adds a test or a structural check**: Before applying the edit (or against a copy without it), run the new check and confirm it fails on exactly the bug and nothing else. After the edit, run it again and confirm it passes. Record both runs in the Validation section - a check never run against the broken version has not proven anything. This never asks a fix to add a check it would not otherwise have.
- **All fixes**: Run `python3 ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/check-craft-vocab.py --scan <files you changed>` and resolve any reported citation before recording validation.

Write what you checked and what you observed in the Validation section.

If validation fails - the symptom persists or a new problem appeared - update the fix file with what happened and reassess. You might need to escalate to a story at this point.

If validation passes: update `status: validated`. Hand back to the shell for the commit (Step 5 there), then return here for lesson capture.

## Step 6: Lesson

After validation passes, decide whether this fix carries a lesson for this project. A lesson names the step in this project's code, plans or way of working that would have caught the problem before it needed a fix, and the rule that changes that step next time, both tied to evidence already in this record's Investigation and Confidence Check. This matters because the rule pass reads every fix record in full, so a lesson earns its question only by naming a step and a rule the rule pass would otherwise have to infer.

When you can name both, and no earlier fix in this thread recorded the same cause, draft the lesson and show it in one question, with the draft in the question text:

Use **AskUserQuestion**:
```
question: "Lesson from this fix: [what went wrong] -> [rule]. Record it?"
header: "Lesson"
options:
  - label: "Yes, record it"
    description: "Write the lesson as drafted"
  - label: "Correct it"
    description: "Say it in your own words; the draft is rewritten from them"
  - label: "No lesson"
    description: "Record nothing"
```

**If "Yes":** write the `## Lesson` section to the fix file:

```markdown
## Lesson
**What went wrong:** [the step that missed it, not the code bug]
**Rule:** [what that step does differently next time]
**Applies to:** [comma-separated contexts where this rule matters]
```

**If "Correct it":** rewrite the three fields from the user's words, show them once, and write on their yes.

**If "No lesson":** write nothing. Continue to Step 7.

When an earlier fix in this thread already recorded this cause, write `## Lesson` with one line, `See <that record's name>.`, and ask nothing.

When you cannot name both the step and the rule, write nothing and ask nothing; the close-out's Lesson line reads "none". Continue to Step 7.

## Step 7: Todo Satisfaction

Run the shared detection from the shell's `## Todo Satisfaction Detection` section (SKILL.md): one `notebook-list.sh todos` call, a semantic match of this fix's symptom/root cause against the open todos, named-referent discipline by arity. The mechanism, discipline, close-call shape, and receipt semantics all live there - this step owns only the fix-path consent surface.

- **No match:** stamp `satisfied_todo: none-matched` in the fix record frontmatter and continue to Step 8. No surface, no friction.
- **Match found** (after disambiguation if multiple): fixes have no acceptance gate to ride, so consent is a match-triggered AskUserQuestion - it fires ONLY when a match exists:

```
question: "This fix satisfies the open todo '[todo-slug]' - close it?"
header: "Todo"
options:
  - label: "Yes, close it"
    description: "Mark the todo done with graduated_to pointing at this fix record."
  - label: "No, leave it open"
    description: "The todo isn't fully satisfied by this fix."
```

**On yes:** run the shell's close call - `notebook-done.sh "<todo-file>" "<record-name>"` with this record's `name:` as the ref - then stamp `satisfied_todo: <todo-slug>`.
**On no:** stamp `satisfied_todo: none-matched`. The todo stays open.

## Step 8: Close

Output a summary:

```
## Adhoc Fix: [name]
Category: [category]
Files: [N] changed, [N] lines
Root cause: [one sentence]
Validation: [what was checked, result]
Planned test: ["<name>" from the source story / none / no source story]
Lesson: [one sentence, or "none"]
Todo: [closed <todo-slug> / none matched]
```

Then hand back to the shell to close the gate (Step 6 there).
