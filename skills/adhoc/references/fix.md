# Adhoc Fix Flow (reference - read inline by the craft:adhoc shell)

This is the FIX flavor: something is broken, there is a symptom, and you can see the root cause. You investigate, reason about the root cause, confirm your confidence, make the edit, and verify the symptom is gone. The shell has already classified the request and opened the write gate - this file owns the fix record, the confidence gate, the edits, validation, and the todo-satisfaction beat. Hand back to the shell for the commit and gate close.

The fix file you create in `.craft/fixes/` is permanent record. A month from now, these files across all projects reveal patterns - what keeps breaking, which story types produce bugs, where the pipeline has gaps. Write them with that future reader in mind.

## Step 1: Create the Fix File

Create `.craft/fixes/` if it doesn't exist (`mkdir -p "${CRAFT_PROJECT_ROOT:-.}/.craft/fixes"`), then write the fix file to `.craft/fixes/[descriptive-name].md`, the same name its `name:` line carries, with this structure:

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
**Change:** [what to change, and WHY this addresses the root cause]
**Files:**
- [path] - [create, modify or delete: the set you will edit]
**Seen by others:** [only when your change alters what the code writes, returns or prints; otherwise delete this line. One line per reader (readers with an identical extraction line and the same two outputs may share one), each named as file:line and each run on the old and on the new written output: file:line - today it shows [the output you ran], after the edit it shows [the output you ran] - same | cured | changed. cured: this reader's own output on the symptom's input was wrong before and is right now, which includes a Same construct elsewhere hit that joined the fix. changed: anything else, including a reader whose file was invalid before but whose own output was right, a result you think is better, and a reader you could not run.]
**Left alone:** [what you noticed while reading that has a different cause than the Root Cause, one line each, or "nothing"]
**Run:**
- [command] - [what it shows: the symptom is gone, or this project's tests and type check pass; or "no project test or type check found"]
**Differs from approved:** [only when a specific fix was approved and this one differs, including any file added: what changed and why it still resolves the same problem; otherwise delete this line]

## Mechanism
[The changed line - added or removed - quoted verbatim with file:line, and one clause saying how that change stops the symptom.]
**Same construct elsewhere:** [search the project root for the distinctive part of that line (the name, call or pattern the bug turns on). For every other hit that does the same thing to the same kind of input: file:line - the symptom's input reshaped so this hit reads the part that went wrong, run, and what it returned - wrong | right. A hit you only read is not right, because the evidence is the run. A hit marked wrong is the same defect in another place and joins Files, even when a reader prints its value, because correcting a wrong result is the cure and not a decision. "none" when no other hit does the same thing.]

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

Before writing the Root Cause section, actually look at the problem. Read the relevant code, then read around it: the callers of the code you will change, the shared code it relies on, the code that reads what your change writes or returns (a file's content, a record, a printed line), and any sibling feature in this project that solves the same problem (say so if none exists). Search from the project root, because a reader can live in any folder. The lines you were pointed at show where the symptom appeared, which is not always where the cause lives, and a fix proposed from them alone often changes once the callers and readers are read.

In Investigation, give each one as file:line and what it does with the value you are changing; callers and readers that use it the same way can share one line. A search hit that shows only a name has not told you that. If it's a visual issue, use the browser (screenshot, inspect elements) - if the shell already took a classification screenshot, that IS your symptom evidence; don't re-take it. If it's a build issue, read the error output.

## Step 3: Confidence Check

After writing the Root Cause and Solution sections, check the evidence before you edit.

Fill Mechanism first. If no line can be quoted, escalate. Mechanism includes its Same construct elsewhere line.
A quoted line that only points at another file is not the mechanism - quote the line it points at.

List every claim this fix depends on: about the code you change, and about what it relies on (what sets or clears a value it reads, who calls it, who reads what it writes, and every place the flow can end, including inside any command or skill it hands off to). Beside each, put the tool result from this session that shows it. A claim about what code does with an input is shown by running that code on that input: the command and its output. A file:line shows what the code says, which is enough for a name, a caller or a line that exists. A claim with no tool result gets one now.

Write the list in the Confidence Check section as `claim | evidence | holds`. You're about to edit code, and a claim you never checked is where a confident fix goes wrong.

**If a Seen by others row says changed** and does not go on to say "decided:", a reader that works today would show something else after your edit, so what it should show is a decision, not a side effect of the fix. The same goes for a new look or wording the fix has to pick that nothing in the surrounding code decides, such as the color of something that would otherwise match its background. The fix waits for the decision, and the row stays in Seen by others. Stop before editing, with what people see today, what each way would show, and your pick. A subagent running this flow returns them as its decision block; the shell decides as `references/fix-handoff.md` H-3 says.

**If every claim holds** and no decision is waiting - continue to Step 4.

**If a result contradicts a claim**, or the Root Cause you wrote is a different cause than the one the fix was approved or classified for - this is more complex than an adhoc fix, because a real adhoc fix runs straight from symptom to root cause to solution. Escalate:

1. Update the fix file status to `escalated`
2. Tell the user: "This is more complex than an adhoc fix - [explain why]. Want me to create a story for it?"
3. Stop. Do not edit code. Hand back to the shell to close the gate.

## Step 4: Apply the Fix

Before the first edit, the fix file on disk holds Symptom through Confidence Check, so a reader can see what you meant to change if an edit goes wrong. Send that write on its own and edit only after it has succeeded. Make your edits directly using Edit/Write tools; there is no implementer agent.

Update the fix file: set `status: applied`, update `files_changed` and `lines_changed`.

## Step 5: Validate the Symptom

This is not "run the build and see if it passes." You must verify the **original symptom** is resolved.

- **Visual fixes** (alignment, style, typography, broken-interaction): You must use Chrome DevTools MCP to navigate to the affected page, take a screenshot, and visually confirm the fix. "Tests pass" is not validation for UI issues - the whole point is what the user sees. Before the screenshot, clear any leftover craft:dial injection (via `evaluate_script`: remove `craft-dial-style`, `craft-dial-panel`, every `[data-craft-dial-injected]` node, and delete `documentElement.dataset.craftDial`, see `commands/references/dial-inject.md`). Then clear leftover annotate changes: run `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/annotate-run.sh" review-clear` - a printed `() => { ... }` line goes to `evaluate_script` verbatim, `OPEN <id> <subject>` lines mean leave the page as found and name each open run, and a failing command means skip and say so (see `commands/references/annotate-overlay.md`, "Clearing leftovers before a review"). Record the outcome in the fix's Validation. After the first browser call, run `node "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/devtools-launch.cjs" notice`; a printed line is said to the user verbatim, nothing printed means nothing said.
- **Build/type/lint errors**: Run the specific check that was failing and confirm it passes.
- **Infrastructure** (chain breaks, state issues): Trace the flow and confirm the safety net exists.
- **A fix that adds a test or a structural check**: Before applying the edit (or against a copy without it), run the new check and confirm it fails on exactly the bug and nothing else. After the edit, run it again and confirm it passes. Record both runs in the Validation section - a check never run against the broken version has not proven anything. This never asks a fix to add a check it would not otherwise have.
- **All fixes**: Run `python3 ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/check-craft-vocab.py --scan <files you changed>` and resolve any reported citation before recording validation, so the record cites only terms craft defines.

Run every command on the Solution's Run list and quote each command with its result. Write what you checked and what you observed in the Validation section.

If validation fails - the symptom persists or a new problem appeared - update the fix file with what happened and reassess. A new problem that is a look or wording to pick, as Step 3 describes, is that decision: stop for it with your edits in place. You might need to escalate to a story at this point.

If validation passes: update `status: validated`. Hand back to the shell for the commit (Step 5 there), then return here for lesson capture.

## Step 6: Lesson

A subagent running this flow puts the draft in its report and asks nothing; the caller asks.

After validation passes, decide whether this fix carries a lesson for this project. A lesson names the step in this project's code, plans or way of working that would have caught the problem before it needed a fix, and the rule that changes that step next time, both tied to evidence in this record's Investigation and Confidence Check. The rule pass reads every fix record in full, so a lesson earns its question only by naming a step and a rule it would otherwise have to infer.

- **Cannot name both:** write nothing and ask nothing; the close-out's Lesson line reads "none".
- **An earlier fix in this thread recorded the same cause:** write `## Lesson` with one line, `See <that record's name>.`, and ask nothing.
- **Otherwise:** draft it and ask one **AskUserQuestion** with the draft in the question text. Question: "Lesson from this fix: [what went wrong] -> [rule]. Record it?", header "Lesson", options "Yes, record it" (write the lesson as drafted), "Correct it" (the user's words rewrite the draft; show it once and write on their yes), "No lesson" (record nothing).

On yes, write `## Lesson` to the fix file with three lines: **What went wrong:** (the step that missed it, not the code bug), **Rule:** (what that step does differently next time), **Applies to:** (comma-separated contexts where this rule matters).

## Step 7: Todo Satisfaction

The caller runs this step. A subagent skips it, because it reads the user's notebook and may need their consent to close a todo.

Run the shared detection from the shell's `## Todo Satisfaction Detection` section (SKILL.md): one `notebook-list.sh todos` call, a semantic match of this fix's symptom/root cause against the open todos, named-referent discipline by arity. The mechanism, discipline, close-call shape, and receipt semantics all live there - this step owns only the fix-path consent surface.

- **No match:** stamp `satisfied_todo: none-matched` in the fix record frontmatter and continue to Step 8. No surface, no friction.
- **Match found** (after disambiguation if multiple): fixes have no acceptance gate to ride, so consent is a match-triggered AskUserQuestion - it fires ONLY when a match exists. Question: "This fix satisfies the open todo '[todo-slug]' - close it?", header "Todo", options "Yes, close it" (mark the todo done with graduated_to pointing at this fix record) and "No, leave it open" (the todo isn't fully satisfied by this fix).

**On yes:** run the shell's close call - `notebook-done.sh "<todo-file>" "<record-name>"` with this record's `name:` as the ref - then stamp `satisfied_todo: <todo-slug>`.
**On no:** stamp `satisfied_todo: none-matched`. The todo stays open.

## Step 8: Close

When the record reads `status: validated` and this fix was started from a bug record in `.craft/bugs/`, close that bug first, whether or not the fix is committed. Started from means the request pointed at that record: its file, its slug or its line in the open pile. A bug that only looks like the one this fix cured stays open, because this close asks no one. Ask nothing. A subagent skips it, because its caller closes the bug after checking the report. A caller following `fix-handoff.md` skips it too, because H-5 already ran it, and a second run on a record that has moved can close another open bug with a similar name.

Read the bug record first: one that gives its layer as `judgment` stays open, because only the user's eye on the result closes that kind, and the summary says it is fixed and theirs to close. Otherwise run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/bugs-close.sh" "<the bug record's path>" --status=fixed --fixed-by="fix record <the record's name>"
```

`already closed` means nothing is left to do; any other refusal leaves the bug open and goes in the summary.

Output this summary. A subagent sends its report instead.

```
## Adhoc Fix: [name]
Category: [category]
Files: [N] changed, [N] lines
Root cause: [one sentence]
Validation: [what was checked, result]
Planned test: ["<name>" from the source story / none / no source story]
Lesson: [one sentence, or "none"]
Todo: [closed <todo-slug> / none matched]
Bug: [closed <bug title> / fixed, yours to close / none]
```

Then hand back to the shell to close the gate (Step 6 there).
