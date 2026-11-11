---
name: review
description: "PR review skill - invokes pr-reviewer-expert agent against branch diff, story commits, or full project audit. Every run on your own work leaves a record in .craft/reviews/, clean or not, and every finding gets a proposed door; a review of someone else's PR leaves nothing in your project."
---

# Review

Run a PR-style code review using the crystallized pr-reviewer-expert agent. Three approaches based on what you want reviewed.

## Modes

| Mode | Trigger | What gets reviewed |
|------|---------|-------------------|
| **Branch** (default) | `/craft:review` | Everything this branch's pull request would contain, committed or not |
| **Story** | `/craft:review story [name]` | Commits from a specific story |
| **Project** | `/craft:review project [path]` | Full codebase or subsystem audit (no diffs) |

Optional focus flag: `--focus security|consistency|performance|correctness` (default: correctness + security)

Optional review strategy: `--maze` enables perpendicular maze review (architect generates questions, runner answers them). Without `--maze`, uses the existing single-agent generalist review.

## Flow

### Step 1: Determine Mode and Scope

**Parse args to determine review scope:**

- No args or `branch` → **Branch mode**
- `story` or `story <name>` → **Story mode**
- `project` or `project <path>` → **Project mode**

When the user says what to review in their own words, such as a PR link, a folder or "whatever would be in the PR", review exactly that, record it under the mode it fits, and tell the user in one line what you resolved it to. This matters because the user knows what they want reviewed, and the arguments above are shortcuts, not limits.

Extract `--focus` flag if present. Default focus is `correctness,security`.

**Whose code:** when the user asked to review a contribution that is not this project's own work (another author's PR, a fork, an upstream change), this is an **outside review**. Say so once, as the review starts, and run Steps 2 through 6 the same way, except that Step 5b is skipped and nothing is written under `.craft/`. Step 6 shows the same message without any `Proposed:` line, `On go:` block or `**Question:** Go?`, and ends after the last finding; the findings are the user's to carry to the PR. The user's words decide this; never infer it from commit authors. An outside review keeps every file it works with, the fetched diff, any batches and the reviewer reports, in your session's scratchpad directory, or a temp directory outside the project when there is none. It saves the close-out message there too, and names that file's full path in one line after the message. This matters because the project must end the review exactly as it started, and the findings are the user's to carry to the PR, so they need a home that outlives the terminal.

### Step 2: Gather Context

**Always pre-load these files, and put each one whole in the agent prompt, because the reviewer, not you, decides which parts bear on the diff:**

1. `.craft/design/locked.md` - locked decisions the reviewer must respect
2. `.craft/project.md` - stack, patterns, conventions
3. `.craft/quality.yaml` - quality gates

### Step 3: Gather Diff / Scope

**Branch mode:** review what this branch's pull request would contain: every change between the branch it will merge into and the working tree, committed or not, new files included, without staging anything. Find that base branch from the repository itself, or use the one the user names. Before the reviewer runs, tell the user in one line what you compared, how many files that covers and which of them are uncommitted. This matters because the developer reads the review as a review of their PR, and a change left out of the diff is a change nobody reviewed.

If nothing differs from the base, say so in one line naming the base, and stop there. No reviewer ran, so this exit writes no record.

**If diff exceeds ~500 lines**, split by directory or subsystem. Run the agent multiple times with scoped diffs rather than one massive prompt. Each batch reviewer gets the Step 4a prompt unchanged except for its diff; never limit which files its findings may land in, because only findings reach the developer reading the close-out. Tell the user:

> "Large diff ([N] lines across [M] files). I'll review in batches by directory to keep findings sharp."

**Story mode:**

If no story name provided, check `.craft/.global-state` for CURRENT_STORY. If none active, use AskUserQuestion to pick from completed/active stories in the current cycle.

```bash
# Read story file to find associated commits
# Look for commits that reference the story name
git log --oneline --all --grep="[story-name]"

# If no story-tagged commits found, ask user for commit range
```

Get cumulative diff across those commits. Also read the story file itself so the agent knows intent.

**Project mode:**

No diff. Instead gather:
- Directory tree of relevant source files
- If a path was specified, scope to that subtree
- The agent will do full file reads during its review

### Step 4: Route - Standard or Maze

Check if `--maze` flag is present. If not, go to **Step 4a (Standard)**. If yes, go to **Step 4b (Maze)**.

---

### Step 4a: Standard Review (no --maze)

**INVOKE the pr-reviewer-expert agent using the Agent tool.**

Build the prompt with:

1. **Mode** - what kind of review this is
2. **Context** - locked.md content, project.md content, quality.yaml content
3. **Diff** - the actual diff (branch/story modes) or file list (project mode)
4. **Changed files** - list of files that changed (branch/story modes)
5. **Commit messages** - so the agent understands intent
6. **Focus** - which lens to prioritize
7. **Story intent** - the story file content (story mode only)

**Prompt structure for the agent:**

```
You are reviewing code for [project name].

PLUGIN_ROOT: ${CLAUDE_PLUGIN_ROOT}
(The agent cannot resolve this variable itself - this line passes the resolved path.)

## Mode: [Branch|Story|Project]

## Focus: [correctness, security, ...]

## Project Context
[locked.md content]
[project.md relevant sections]
[quality.yaml content]

## [Diff / File List]
[the actual diff or file list]

## Changed Files
[list of changed files - read each one fully for surrounding context]

## Commit Messages
[commit log]

## Instructions
- Read each changed file in full (not just the diff) to understand surrounding context
- Check imports/callers of changed functions for cross-file issues
- Respect locked decisions - do not flag patterns that are explicitly locked
- Report every issue you find that could cause wrong results, a crash, lost data, a slowdown or failure under load, a doc that no longer matches the code, or a break of a locked decision you can quote. Include the ones you are unsure of and the ones that need a specific input, timing or state to happen: name that condition and what happens when it occurs, and say in Actual what you could not confirm. Your job here is coverage, not filtering: the orchestrator checks every finding against the project before anyone reads it and drops the ones that are not real, so an issue you leave out is one nobody checks.
- Leave out code style, naming, pedantic nitpicks a senior engineer would not raise, issues a linter will catch, and pre-existing issues. None of them changes whether this change is safe to merge, and each one costs the reader time.
- Categorize each finding: security, logic, performance, consistency, or doc-drift
- doc-drift = stale references in docs/comments, terminology that doesn't match current code, outdated examples, references to renamed/removed symbols
- Lead with the finding. Every finding carries Symptom, Expected (requirement quoted), Actual (observed, or read in code and not run), Consequences, Reproduce from a named starting state, Evidence (raw), and the fix diff with file:line and category
- Focus on: [focus areas]
- Do NOT comment on formatting/style if linters exist
- If the diff is clean and you have no real findings, say so - do not manufacture issues
- Report in this shape: a `Gates run:` line (what you ran on your own initiative and the result, or `none`), a `## Verified` list (one line per check you made and found clean), then `## Findings` with each finding under `### N. (<category>): <title>`, and `**Withdrawn.** <why>` on any finding you raised and then disproved
```

Then skip to **Step 5: Check the Findings**.

---

### Step 4b: Maze Review (--maze)

The maze review splits question-generation from question-answering. The architect decides WHAT to investigate. The runner investigates it. This prevents the infinite-regression problem where fixing 10 issues reveals 10 more.

#### Step 4b.1: Slice the Diff (if needed)

If the diff exceeds ~500 lines, slice it by subsystem/directory, grouping the files Step 3 compared by their top-level directory.

Create one slice per subsystem. Each slice gets its own architect pass. Tell the user:

> "Large diff ([N] lines). Slicing into [M] subsystems for maze review."

For diffs under 500 lines, use the entire diff as a single slice.

#### Step 4b.2: Run the Maze Architect (per slice)

**INVOKE the maze-architect agent using the Agent tool.**

**CRITICAL: The architect must NOT see intent.** Do not include commit messages, PR descriptions, story files, or any explanation of WHY the changes were made. This is the core principle - naive-about-intent question generation produces better review questions.

Build the architect prompt with ONLY:

```
Here is a code diff to analyze. Generate review routes.

## Diff
[raw unified diff for this slice - NO commit messages, NO PR description]

## Changed Files
[file paths only - no descriptions]

## Project Context (optional, if available)
[locked.md content - this is about the PROJECT, not the CHANGE]
[project.md stack/patterns section - this is about the PROJECT, not the CHANGE]
```

The architect returns structured YAML:

```yaml
routes:
  - question: "What happens when [scenario]?"
    lens: security|correctness|consistency|concurrency
    entry_point: "path/to/file.ts:NN"
    why: "The diff shows [observation]"
  - ...
maze_size: small|medium|large
summary: "Naive one-line description of what the diff does"
```

If running multiple slices, run architects in parallel (multiple Agent calls in one message).

#### Step 4b.3: Show the Architect's Routes to the User

Before running the runner, show what the architect found:

> **Maze Architect Report**
>
> *Naive reading:* "[summary from architect]"
>
> | # | Question | Lens | Entry Point |
> |---|----------|------|-------------|
> | 1 | Can a user with role=viewer call this delete endpoint? | security | api/reports/route.ts:12 |
> | 2 | Does the error path clean up the temp file? | correctness | lib/upload.ts:45 |
> | 3 | Do all consumers of UserProfile handle the new nullable field? | consistency | types/user.ts:8 |

This gives the user visibility into what the architect thinks the code does (without knowing what it's supposed to do). The naive reading itself is often revealing.

#### Step 4b.4: Run the Runner with Architect's Questions

**INVOKE the pr-reviewer-expert agent using the Agent tool.**

The runner gets FULL context (unlike the architect) - but its mission is answering the architect's questions, not free-roaming.

```
You are reviewing code for [project name].

PLUGIN_ROOT: ${CLAUDE_PLUGIN_ROOT}
(The agent cannot resolve this variable itself - this line passes the resolved path.)

## Mode: Maze Review - Targeted Investigation

## Your Mission
A naive code reviewer (who cannot see commit messages or PR intent) analyzed this diff
and generated the following questions. Your job is to ANSWER each question with evidence
from the codebase. You have full context - use it.

## Questions to Answer
1. [question 1] (lens: [lens], start at: [entry_point])
   Architect's reasoning: [why]
2. [question 2] ...
3. [question 3] ...

## Project Context
[locked.md content]
[project.md relevant sections]
[quality.yaml content]

## Diff
[the actual diff]

## Changed Files
[list of changed files - read each one fully for surrounding context]

## Instructions
- Answer each question with a clear YES (problem found) or NO (code is safe) + evidence
- For each YES: a finding with Symptom, Expected (requirement quoted), Actual (observed, or read in code and not run), Consequences, Reproduce from a named starting state, Evidence (raw), and the fix diff with file:line
- For each NO: briefly explain why the code handles this correctly
- You may also record BREADCRUMB findings - issues you notice along the way that aren't
  part of the architect's questions. List these separately at the end. They are
  side-effects of your investigation, not your mission.
- Report every issue you find that could cause wrong results, a crash, lost data, a slowdown or failure under load, a doc that no longer matches the code, or a break of a locked decision you can quote. Include the ones you are unsure of and the ones that need a specific input, timing or state to happen: name that condition and what happens when it occurs, and say in Actual what you could not confirm. Your job here is coverage, not filtering: the orchestrator checks every finding against the project before anyone reads it and drops the ones that are not real, so an issue you leave out is one nobody checks.
- Leave out code style, naming, pedantic nitpicks a senior engineer would not raise, issues a linter will catch, and pre-existing issues. None of them changes whether this change is safe to merge, and each one costs the reader time.
- Categorize each finding: security, logic, performance, consistency, or doc-drift
- Do NOT free-roam beyond the questions + breadcrumbs. When you've answered all questions, stop.
- Do NOT comment on formatting/style if linters exist
- Report in this shape: a `Gates run:` line (what you ran on your own initiative and the result, or `none`), a `## Verified` list with one line per NO answer (the check you made, in your words), then `## Findings` with one finding per YES or breadcrumb under `### N. (<category>): <title>`, and `**Withdrawn.** <why>` on any finding you raised and then disproved
```

#### Step 4b.5: Cross-Slice Questions (large diffs only)

If there were multiple slices, after all per-slice runners complete, do one final pass.

Collect all architect summaries:

```
Slice A (api/): "Adds a reports endpoint with database query"
Slice B (components/): "New ReportCard component that fetches and displays data"
Slice C (hooks/): "Adds useReport hook with caching"
```

**INVOKE the maze-architect agent one more time** with:

```
Multiple subsystems changed in the same branch. Here are naive summaries of each:

- api/: "Adds a reports endpoint with database query"
- components/: "New ReportCard component that fetches and displays data"
- hooks/: "Adds useReport hook with caching"

Generate cross-cutting questions that span these subsystems.
Focus on contract mismatches, shape disagreements, and assumptions one
subsystem makes about another.

Do NOT repeat questions that would be caught within a single subsystem.
```

Run the runner against any cross-slice questions the same way as Step 4b.4.

### Step 5: Check the Findings

The reviewer's report is a claim, not a result. Check every finding before anyone sees it, and print nothing to the user while you do.

**If the report has no findings** (across every batch, slice and the cross-slice pass), print exactly: "No issues found. Checked for bugs, doc drift and locked decisions." Under it, print the line on the state of the branch and the lines on changes to what a reviewer read, was told or was allowed to do, as the close-out reference's message section describes them. This matters because a clean result is the one the reader trusts without a second look, and a gate nobody ran or a reviewer told less is what could make it wrong. Then continue to Step 5b.

**If findings exist:**

1. Number the findings 1..N once, across every batch, every maze slice and the cross-slice pass, in the order the reports list them, before the check starts. That number belongs to the finding in the record and in the message; nothing renumbers it later. A finding marked `**Withdrawn.**` is checked like the rest.
2. For each finding, in turn:
   - Try to reproduce the symptom. Keep the command you ran and the output you got.
   - Name the path a user of the project takes to reach it.
   - Open what the reviewer's fix changes, and name every other path the symptom can take. When the fix covers one path of several, complete it so it covers all of them.
   - Check whether an earlier finding has the same cause.
3. End each finding on what a user of the product would meet, because its ending decides what the developer reading the close-out does next (fix it, judge it, or let it close), and a finding ended for any other reason hides a real problem behind a correct-sounding one. Take the first of these that fits:
   - **not real** - no user path reaches it, it has the same cause as an earlier finding, or you ran its failure scenario and the symptom did not happen.
   - **reproduced, blocking** - you saw the symptom happen, and the failure scenario is wrong output, a crash, lost data or a failure the product's user sees.
   - **reproduced, non-blocking** - you saw the symptom happen, and the failure scenario is cleanup, efficiency, conventions or doc drift, including a doc a developer follows into an error.
   - **unresolved** - anything else, including a finding you argued away by reading without running it.
   Disproving one consequence of a reproduced finding leaves it reproduced; the message names that consequence with its output.
4. Set blocking or non-blocking by the failure scenario alone, never by whether you ran it. Say "reproduced" about a finding only with its command and output kept beside it. A path you read but did not run is recorded as read, not reproduced.
   A finding whose symptom a user still reaches is real whether or not this branch introduced it; say it predates the branch and route it like any other.
5. A doc-drift finding is checked like any other. Nothing is written to a docs file.
6. In maze mode, run the check over the concatenated findings of every slice and the cross-slice pass, before the record is written.

Keep, for each finding, what the close-out message needs: the failure scenario (the inputs and state, then the wrong output), the command and output, each path read but not run, the complete fix with one `file:line` and its size, and for every not-real finding the reason. The message itself is shaped by `${CLAUDE_PLUGIN_ROOT}/commands/references/review-record.md`.

### Step 5b: Write the Record

Every run that reached a reviewer leaves one record in `.craft/reviews/`, whether or not it found anything. The record is written by `review-capture.sh`.

**Outside review (Step 1):** skip this step. No record is written and nothing is created under `.craft/`.

Make one capture call per `/craft:review` invocation, after every batch, maze slice and the cross-slice pass has returned. Number the findings 1..N in the order Step 5 numbered them across all of them, so the number in the message, the number in the record and the number in the user's answer ("3 bug") are the same number.

Pass the flags to `hooks/scripts/review-capture.sh` from these sources:

- `--ref` is `git rev-parse --short` of the diff's base and of HEAD joined as `<base>..<head>`, with `+uncommitted` after it when the review covered uncommitted changes; in project mode it is HEAD alone.
- `--lines` is insertions plus deletions across the same comparison Step 3 reviewed, new files included (omit it in project mode).
- `--gates` is the result of the reviewer's `Gates run:` line, and `not reported` when the report has none. Never write `none` for an unknown.
- The body is the reviewer's `## Verified` list and `## Findings`. With several reports (batches, slices, the cross-slice pass), concatenate their Verified lists under one `## Verified`, renumber only the `### N.` headings 1..N, and keep every other line as written. Join the `Gates run:` results with `; ` for `--gates`. When the report has no Verified list, write the single line `- None reported - the reviewer's report listed no checks it found clean.` under `## Verified`, never an invented check.

Read `${CLAUDE_PLUGIN_ROOT}/commands/references/review-record.md` for the full capture call and the body grammar, then write the record. Note the record's path (the script's last line) and its name (the file name without `.md`) for Step 6.

### Step 6: Close Out

Read `${CLAUDE_PLUGIN_ROOT}/commands/references/review-record.md` and run its close-out: one message with a proposed door for every checked finding, answered with go, and each answer running the door it names. Nothing is created until the user answers, and no path in this command edits project code outside the adhoc flow. A clean run (`outcome: clean`) shows only Step 5's no-findings sentence; the record is its whole close-out. An outside review shows the message in its outside form.

## Quick Commands

```bash
/craft:review                          # Branch review (default, standard mode)
/craft:review --maze                   # Branch review with maze architecture
/craft:review story auth-flow          # Review a specific story's changes
/craft:review story --maze             # Story review with maze architecture
/craft:review project                  # Full project audit (standard only)
/craft:review project src/api          # Audit a subsystem
/craft:review --focus security         # Branch review, security focus
/craft:review --maze --focus security  # Maze review, security focus
```

## Key Principles

1. **Context before opinions** - locked.md and project.md are read before any finding is formed
2. **Signal over noise** - fewer high-quality findings beat a wall of nitpicks
3. **Always include a fix** - every finding has an actionable diff, not just a complaint
4. **Respect the 500-line cap** - large diffs get split by subsystem
5. **Every finding, no severity** - the reviewer reports every issue it finds, sure or not, and attaches no severity; the orchestrator's check drops what is not real and sets blocking or non-blocking
6. **Every run on your own work leaves a record, clean or not** - a clean review that leaves nothing is indistinguishable from no review at all, so the record lists what the reviewer verified as well as what it found. An outside review leaves nothing, so other people's contributions never enter your records.
7. **Every checked finding gets a proposed door** - all of them in one message answered with go, and the review record points at what it became

## Maze Mode Principles

8. **Naive-about-intent** - the architect NEVER sees commit messages, PR descriptions, or story files. It asks "what does this code do?" not "did the developer do what they intended?"
9. **Questions over exploration** - the runner answers specific questions instead of free-roaming. This prevents infinite issue regression (the CodeRabbit problem).
10. **Breadcrumbs are secondary** - findings the runner discovers along the way are recorded but don't change the mission. Each breadcrumb goes through the Step 5 check like any other finding.
11. **Cross-slice awareness** - for large diffs, a meta-architect pass catches contract mismatches between subsystems that per-slice architects can't see.
12. **Convergence by design** - the review ends when all questions are answered. No open-ended "let me look around more."
