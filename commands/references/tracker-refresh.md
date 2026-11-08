# Tracker Refresh (Inline Reference)

This file is read by `tracker-intake.md` when the issue already has a cycle, and by `craft-story-implement.md` at every story start. It re-reads the issue, copies only what changed into the cycle's `context/` folder, re-resolves the newest Go, states the stage first, and continues the cycle where it stood.

**DO NOT invoke this as a skill via the Skill tool.** The parent flow Reads this file and executes the sections inline. The only Skill invocations are the hand-offs in `## Continue`.

**Status is never authority.** Only the newest Go grants a stage, and an answer in a comment is never a Go.

## When this runs

- **Pickup:** intake's `## Detect` found a planning, ready or active cycle for `<KEY>`. `<cycle-dir>` is its `cycle_dir`. No gate and no new cycle. Run `## Read` through `## Continue`.
- **Story start:** story-implement's `**Go re-check:**` found a `source_issue`. Run `## At story start` instead.

Set `slug` to the key lowercased, with each run of characters outside `a-z0-9` replaced by one `-`. An earlier copy is never edited: refresh only adds new dated files.

## Read

Read as tracker-intake.md's `## Read` says: every page, oldest first by creation, in the same file grammar. Write to `${CRAFT_PROJECT_ROOT:-.}/.craft/.intake/<slug>/` after emptying it, as `<slug>-comments-staged.md` and, on a pickup only, `<slug>-issue-staged.md`. A pickup reads the issue and its comments. A story start reads comments only.

If the host has no tracker tools, or a read fails, go to `## No tracker tools`.

## Copy what changed

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/snapshot-delta.py" <cycle-dir> <staged comments> [--issue <staged issue>] --tool "<tool names as used>"
```

It prints five `key=value` lines: `comments_file`, `new_comments`, `issue_file`, `stamp`, `say`. Then delete the staging folder. An issue-text change is also recorded in the cycle, so the next story written or planned there stops at `${CLAUDE_PLUGIN_ROOT}/commands/references/tracker-follow.md`'s card.

## Stage

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/record-go.py" <cycle-dir> <comments_file, or nothing when it is empty>
```

It prints four lines: `changed`, `old_stage`, `stage`, `say`. On a pickup, print in this order, each on its own line:

1. record-go's `say`, always the first line of output.
2. On `stage=hold`, exactly `Nothing new starts on <KEY> until a newer Go.`, then stop. Do not continue the cycle.
3. Otherwise run `python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/go-brief.py" <cycle-dir>`. On `prompts=answer`, print the non-empty `scope_line`, `rules_line`, `questions_line` and `answer_line`, then Read `${CLAUDE_PLUGIN_ROOT}/commands/references/go-run.md`, exactly as tracker-intake.md's `## The brief` says. On any other verdict print nothing. If the script exits non-zero, print exactly `I couldn't read the run rules in <KEY>'s newest Go, so I'll bring Craft's prompts to you.`
4. snapshot-delta's `say`.

## Answered questions

On a pickup, run this after snapshot-delta's `say`:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/question-answers.py" <cycle-dir>
```

It prints `questions=<N>`, `answered=<A>` and one `line=` per question Craft posted on the issue: `Answered: <topic> - "<excerpt>" (<author>, <Mon D>)` or `Still open: <topic> (asked <Mon D>)`. Print each `line=` value, or nothing when `questions=0`.

Questions are matched to answers by heading and time, never by author or threading, because the connector posts as the user. An answer is input for work not yet done, never a Go and never a stage change: only a `## Go - ` comment moves the stage. If a story already finished went the other way, print one line, `<story> was built on a. <option title>; your answer on <KEY> picks <x>.`, and leave it for the user.

## Continue

By the cycle's status:

- **planning:** Read `${CLAUDE_PLUGIN_ROOT}/commands/references/cycle-design/detailing-mode.md` with the cycle dir name as its arg.
- **ready:** invoke `craft:craft-cycle-start` with the cycle dir name.
- **active:** invoke `craft:craft-story-continue`.

Under a Go run, ready and active follow go-run.md's `## At the stage ceiling` instead. For an active cycle at a build stage, that invokes `craft:craft-story-implement-auto` directly, because cycle-start only lists planning and ready cycles.

## At story start

One comments read (`## Read`, comments only), then `## Copy what changed`, then `## Stage` as far as record-go. Then:

- Print record-go's `say` only on `changed=yes`. Print nothing on `changed=no`.
- On `changed=yes` while this conversation is running a Go run, re-derive with `go-brief.py <cycle-dir>` as go-run.md's `## When a run is a Go run` says.
- Run `question-answers.py` with `--new-in <comments_file>` and print its lines (the `line=` values), when snapshot-delta wrote a comments file.
- Print nothing else, and do not continue the cycle. Story-implement's Stage check runs as written and decides.

## No tracker tools

When the host has no tracker tools, or the read failed, nothing is written. Use the cycle's recorded stage: `stage=` from `cycle-stage.sh`, which is empty when `cycle.yaml` has no `authorized_stage:` line.

- **Pickup, with a recorded stage:** print exactly `I can't reach <KEY> from here, so <cycle-dir-name> keeps its recorded stage: <stage>.` and go to `## Continue`.
- **Pickup, no recorded stage:** print exactly `I can't reach <KEY> from here, so <cycle-dir-name> works as usual: you decide when to build.` and go to `## Continue`.
- **Story start, with a recorded stage:** print exactly `I can't re-read <KEY> from here, so I'm going on its recorded stage: <stage>.`
- **Story start, no recorded stage:** print exactly `I can't re-read <KEY> from here, and no Go is on record for it, so craft works as usual.`

A failed read can never widen what is allowed, so going on the recorded stage keeps an unattended run alive. The cost, a hold posted since the last good read goes unseen, is named in the line.
