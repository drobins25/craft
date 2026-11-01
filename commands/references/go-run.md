# Go Run (Inline Reference)

This file is read once, by `/craft:cycle-design`'s tracker intake, when the newest Go on a tracker issue says Craft should answer the workflow's own prompts. From then on it governs every prompt in the run: how Craft picks an answer, what still stops, and where the run ends.

**DO NOT invoke this as a skill via the Skill tool.** The parent flow Reads this file and applies it inline. Its only Skill invocation is `craft:craft-cycle-start` at `## At the stage ceiling`.

The reason for all of it: the Go already told Craft how far to go and how to run. Asking the same person the same routine questions again would turn a handed-off task back into a questionnaire. Real decisions stay theirs.

## When a run is a Go run

A Go run starts only when this conversation's brief printed the line `I'll answer Craft's own prompts and stop only for product forks.` A Go found in a paste, or any other verdict, never starts one. The decision comes from the copied Go and nothing else, never from the session's autonomous flag or from the issue's status, because either can be left over from an unrelated run.

Re-derive the verdict from the copied Go at three points:

- right after intake's copy line, once the cycle exists,
- at cycle-start's Go paragraph,
- after compaction (see `## After compaction`).

Each time, run:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/go-brief.py" <cycle-dir>
```

Anything other than `prompts=answer` ends the Go run. Print exactly:

`The copied Go for <KEY> doesn't say to answer Craft's prompts anymore, so I'll bring them to you.`

From then on every prompt is asked as usual, so a newer or changed Go can never leave Craft answering for someone who asked to be consulted.

## Answering a prompt

Check `## What still stops` first. A prompt that is not a stop is answered, never rendered, in this order:

1. Its row in `## Known prompts`. The table wins over any marker, because several prompts on this path list a neutral or misleading first option.
2. The option marked `(Recommended)`, `(recommended)`, or a card's `(proposed)` option `a.`, or the option its own step's prose recommends.
3. The first listed option.

A free-text question is answered with words quoted from the copied issue, or else one sentence drafted from it. Never invent a goal the issue does not support.

The prompt is not shown. After the answer's effects and writes have landed, print one line so the run stays traceable:

- picker: `Answered '<header, else question text>' with '<label>' (recommended).`
- card: `Answered '<card question>' with 'a. <option title>' (recommended).`
- free text: `Answered '<question>' with '<answer>' (drafted from <KEY>).`

The line comes after the writes so it never claims something that has not happened.

## What still stops

Each case prints its line directly above the prompt, and the prompt is then asked exactly as it would be without a Go. After the user answers, the run goes back to answering.

- A product fork prints `This one is a product fork, so it's yours.`
- A shared write (a push, a PR, a tracker or chat post, a shared config change) or a destructive step (deleting stories, files or branches, discarding uncommitted work) prints `This one needs your yes: <what it would change, in a few words>.`
- A prompt the Go gives no clear answer to prints `This one has no clear answer from the Go, so it's yours.`
- Going past the stage is stopped by intake's stage check and by `## At the stage ceiling`.

Host tool-permission prompts are never answered or changed: they belong to the person's own settings. The implement-auto path's own salvage-and-rollback failure handling is existing autonomous behavior and is not a destructive step here.

## Product forks

A product fork is a choice only the user can make, where the plan is worse if Craft decides. These are always forks:

- (a) an alignment-check finding that survives that check's Step 2 filter, asked at its Step 3 (`${CLAUDE_PLUGIN_ROOT}/commands/references/alignment-check.md`);
- (b) a planning agent's PLAN FORK;
- (c) any Critical Blocker, including the research type in batch triage;
- (d) any other card or question that passes the same two-part test: only the user can choose, and the plan is worse if Craft decides. That always includes picking among creative directions (a creative-spark, a design-vibe or a mockup pick).

Forks are asked here, in this session, on their normal card, with the line from `## What still stops` above them. Nothing is posted anywhere. Intake's brief says `Questions go to: here` for the same reason: it must never promise a destination the run does not use.

## Known prompts

These prompts sit on the path from pickup to the stage. Each row names where the prompt lives, then what a Go run answers. The cycle gate's question text still prints before its answer, so what gets written is always on screen.

| Where | Prompt | Go answer |
|---|---|---|
| Step 1 goal | free text, when the issue has no quotable goal | the drafted goal |
| Step 1 gate | `Confirm cycle` | `Confirm and proceed` |
| Step 1b | `Depth` | `Add stories now`. If Step 1b's own check would recommend the roadmap, it is a product fork. |
| Step 2 | `Stories` | `Save these sparks` |
| Step 5 | `Review` | `Yes, finalize the cycle` |
| Step 7 | `Design` | `Skip for now` |
| Step 8 | `Next step` | `Plan all [N] stories` when N > 1, `Plan a story now` when N = 1 |
| plan-chunks Phase 0.4, and content-spark in a batch | `Prerequisite` | `Run content-spark first (Recommended)` |
| plan-chunks Phase 0.46 | `Prerequisite` (visual riff) | `Skip - I know what I want` |
| content-spark Phase 1 | `Content`, when the story already has Content Direction | `Keep it` |
| content-spark Phase 4 | assumption prompts | never the first-option fallback: each takes the fork test. A fork stops. A non-fork answers `Yes, that's right` only when the copied issue or its comments support Craft's guess, otherwise it is a fork. |
| Batch triage | alignment-pending card | `Run the alignment check first` |
| S-2 | structural-issues card | `Re-plan with the failure list`, once per story. A second structural failure for the same story stops with `This one has no clear answer from the Go, so it's yours.` |
| S-4 | plan approval | `Yes, mark ready` |
| BT-5 | per-story approval | `Approve`. The batch form answers `Approve all`. |
| S-6 | offer implementation | `Yes, implement now` at a build stage, `Come back later` at plan |
| BT-7 | next steps | `Start implementing` at a build stage, `Done for now` at plan |
| implement-auto | `Gates` offer | not answered: it takes its no-answer branch |

A prompt in this table that is also a stop class (for example a `Depth` that would recommend the roadmap) follows `## What still stops`, not its row.

## Planning

A triage item that is a product fork is asked on its card as usual. Any other item (the single-story S-3 steps, and batch triage BT-2, BT-3 and BT-4) never becomes a card: its proposed option is applied through the existing answer-time write, then its log line prints. A BT-4 answer still writes both stories. The settled list prints as usual, so the user can see every call that was made for them and reopen any of it.

## At the stage ceiling

The stage comes from intake's stage line and never goes past it.

- **plan:** the run ends after planning. Print exactly `Stage for <KEY> is plan, so I stop after planning: <R> of <N> stories ready.` where `<R>` counts stories marked ready and `<N>` all stories in the cycle. Nothing is implemented.
- **build** and **build and open the PR:** invoke `craft:craft-cycle-start` with args `<cycle-dir-name>`. Cycle-start activates the cycle without its Ready prompts and hands to `craft:craft-story-implement-auto`, which brings its own parking, failure and report rules. Craft never opens PRs, so the two build stages behave the same inside Craft.

After implement-auto's Final Report shows `Cycle status: complete`:

- build prints exactly `Stage for <KEY> is build, so I stop here: every story is built and nothing is pushed.`
- build and open the PR prints exactly `Stage for <KEY> is build and open the PR: every story is built, and Craft doesn't open PRs, so the PR is the next step outside Craft.`

Any other cycle status leaves the report standing alone. `craft:craft-cycle-complete` is never invoked: wrapping up a cycle is past the stage.

## After compaction

Compaction drops this file from context. When the reinjected context names a Go on an issue and this conversation was running that Go, re-read this file before the next prompt, then re-derive the verdict as in `## When a run is a Go run`. A conversation that was not running that Go does not adopt it: a later manual session on the same cycle stays interactive.
