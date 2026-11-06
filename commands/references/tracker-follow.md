# Tracker Follow (Inline Reference)

This file is read by every flow that writes a story into a cycle or plans one, before it does either, when the cycle's `cycle.yaml` has a non-empty `source_issue`. It re-reads the issue, asks the script whether the issue's title or description changed since the cycle was defined, and turns the answer into a card, a save, or silence.

**DO NOT invoke this as a skill via the Skill tool.** The parent flow Reads this file and executes the sections inline. There are no Skill invocations here.

The reason for all of it: a changed ticket printed as a line is a line the flow can read and carry on past. The script records the change in the cycle, so the flow stops at the card until the user answers it. The calling flow never goes past this file except through `## Continue`.

Set `slug` to the key lowercased, with each run of characters outside `a-z0-9` replaced by one `-`.

## Check

Stage the issue alone, no comments: empty `${CRAFT_PROJECT_ROOT:-.}/.craft/.intake/<slug>/`, then write `${CRAFT_PROJECT_ROOT:-.}/.craft/.intake/<slug>/<slug>-issue-staged.md` from the tracker as tracker-intake.md's `## Read` and `## Stage` say for the issue file. Then run:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/follow-issue.py" check <cycle-dir> --issue <staged> --tool "<tool names as used>"
```

When the host has no tracker tools, or the read fails, or the issue is gone, run it with `--unreadable <reason>` in place of `--issue` and `--tool`, where the reason is `no-tools`, `read-failed` or `not-found`. Then delete the staging folder.

It prints ten `key=value` lines: `verdict`, `key`, `cycle`, `old_title`, `new_title`, `changed_lines`, `first_changed`, `as_of`, `issue_type`, `say`. If it exits non-zero, print its one stderr line and treat the verdict as `unreadable` with reason `read-failed`.

- `verdict=current` or `verdict=none`: go to `## Continue` with nothing printed.
- `verdict=changed`: go to `## The card`.
- `verdict=unreadable`: go to `## Can't read the issue`.

Nothing else in the calling flow runs until one of these routes finishes, and the flow continues only through `## Continue`.

## The card

Render one card in the shape of `${CLAUDE_PLUGIN_ROOT}/commands/references/question-card.md`. `<N>` is `cycle`, `<KEY>` is `key`.

**Question 1 of 1:**

`Update cycle <N> from <KEY>, keep cycle <N> as it is and plan anyway, or stop here?`

The Today paragraph leads with the user's new words:

1. The new title in full: `You rewrote <KEY>: it now reads "<new_title>".`
2. The old title in full: `Cycle <N> was defined from "<old_title>".` When `old_title` is empty, `Cycle <N> was defined from your paste of <KEY>.` When it equals `new_title`, `The title is still "<title>".`
3. `<changed_lines> description lines changed, starting with "<first_changed>".` Omitted when `changed_lines` is 0.
4. `Stories already in cycle <N> stay as they are.`

```
a. Update cycle <N> from <KEY> (proposed)
   You see the cycle's title, target, goals and focus beside
   the new ticket text, and nothing is saved until you say yes.
   Stories already in the cycle are not touched.

b. Keep cycle <N> as it is and plan anyway
   The cycle's title, target and goals stay as they are, and new
   stories cite the new ticket text. I ask again only if <KEY>
   changes again.

c. Stop here
   Nothing is written and nothing is planned. The next time a
   story is written or planned in this cycle, this question comes back.
```

Close per question-card.md: `My pick is a.` and what the user sees, then `**Question:** Go with a?` and a `**Why:**` line that names the fact from Today and rules out both other ways.

Answer a goes to `## Update`, b to `## Keep`, c to `## Stop`. Other words that pick an outcome pick it. Under a Go run (go-run.md in force with `prompts=answer`), the card and the save question are answered per `## Known prompts` in `${CLAUDE_PLUGIN_ROOT}/commands/references/go-run.md`, and a Go run whose rules bring prompts to the user renders the card and waits.

## Update

Read the cycle's current `title`, `target`, `focus` and `goals` from `cycle.yaml`, and the newest issue copy under the cycle's `context/` folder. Draft from the issue's own words, never invented:

- title: the newest copy's title verbatim, as tracker-intake.md's `## Into Step 1` names a cycle;
- target and goals: quoted or lightly condensed from the description, at least one goal;
- focus: one line, drawn from the same words.

Show one diff fence of `-` (current) and `+` (new) pairs, in the order title, target, goals, focus:

```diff
- title: "<current title>"
+ title: "<new title>"
- target: <current target>
+ target: <new target>
- goals: <current goals, one per line>
+ goals: <new goals, one per line>
- focus: <current focus>
+ focus: <new focus>
```

Then exactly these two lines:

`Everything above is rewritten from the new ticket: title, target, goals, focus. Stories already in cycle <N> are not changed.`

`Say yes to save, or tell me what to change.`

A correction redraws only the field the user named, shows the diff fence again and asks the save question again. Run `update` only after a yes:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/follow-issue.py" update <cycle-dir> --title "<title>" --target "<target>" --focus "<focus>" --goal "<goal>" [--goal "<goal>" ...]
```

Print update's `say`, then go to `## Continue`. If it exits non-zero, print its stderr line and stop: the cycle is unchanged and the card returns at the next guarded step.

## Keep

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/follow-issue.py" keep <cycle-dir>
```

Print keep's `say`, then go to `## Continue`. If it exits non-zero, print its stderr line and stop.

## Stop

Print nothing and write nothing. The change stays recorded in the cycle, so the next story written or planned there shows the card again. This ends the flow: the calling flow does not continue.

## Can't read the issue

Print check's `say`, then ask `Plan anyway, or stop here?` as a plain question. Plan anyway goes to `## Continue`. Stop ends the flow, like `## Stop`. Neither runs `keep` or `update`, and nothing is written.

## Continue

When the caller is cycle-design and either the cycle has no stories yet or the route came through `## Update`, first apply tracker-intake.md's `## Bug tickets` (`${CLAUDE_PLUGIN_ROOT}/commands/references/tracker-intake.md`) to the newest issue copy under the cycle's `context/` folder. On every other route, skip it. When the caller is plan-chunks after an update, read the cycle goal again from the cycle's `cycle.yaml` and drop any `CYCLE_GOAL:` arg given before the update, because it holds the old goal. Then return to the calling step.
