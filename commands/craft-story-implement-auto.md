---
name: story-implement-auto
description: "Autonomous story implementation — auto-picks stories, chains through cycle, no interactive prompts."
---

# Story Implement Auto

Run `craft:story-implement` autonomously. The user is not present and wants all ready stories in the active cycle completed.

## How This Works

This command sets autonomous behavioral overrides, then delegates to the full implementation flow via skill invocation.

**After startup and story selection**, invoke the implementation skill:

```
Skill tool:
  skill: "craft:craft-story-implement"
  args: "[story-file-path]"
```

The skill contains the full implementation loop — agent invocation, validation, learnings, everything. This command only specifies what's different when no user is present. Apply the overrides below to every decision point in the skill's flow.

## Autonomous Behavior

- **No AskUserQuestion calls,** except the gate takeover question at launch (see Startup Sanity Check) and the Gate Pre-Flight offer. At every other decision point in `craft:story-implement`, choose the recommended option automatically. Never wait for user input.
- **Auto-pick stories.** Select the next `status: ready` story in the active cycle, in filename order. No story selection prompt.
- **Chain stories.** After completing a story, pick the next ready one. Continue until no more ready stories or failure.
- **Auto-answer defaults.** Package manager: auto-detect from lockfiles, default to npm. Test infra: set up Vitest if missing. Spark verification: self-check acceptance criteria — only stop on provably unmet (file doesn't exist, test doesn't pass), not subjective judgments.
- **Validation via skill.** Same `craft:validate-chunk` skill invocation as `craft:story-implement`. The skill handles all routing autonomously — no AskUserQuestion calls needed since refine-chunk and test-fix are already non-interactive.

## Startup Sanity Check

First, read `.global-state` and handle stale state from a crashed previous run:

| Condition | Action |
|-----------|--------|
| No `ACTIVE_CYCLE` | "No active cycle." EXIT. |
| `CURRENT_STORY` set, story is `complete` | Stale state — clear CURRENT_STORY and cycle state, and run `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/write-gate.sh close story "<story file>"` (this session's own gate file only). Proceed to story selection. |
| `CURRENT_STORY` set, story is `active`, all chunks done | Crashed before `complete-story.sh`. Skip to story completion flow. NOTE: the dead session's `.craft/.commit-manifest` is gone (session-start clears it), so if you resume past the manifest-write sub-step (story-implement 7b) without re-writing it, `complete-story.sh` makes NO commit by design ("no manifest found"). Re-run sub-step 7b before Mark Complete, or surface "completion commit skipped (no manifest)" in the final report. |
| `CURRENT_STORY` set, story is `active`, chunks incomplete | Resume from current chunk. Trust story frontmatter (`chunks_complete + 1`) as ground truth. |
| Clean state | Normal start. Proceed to story selection. |

On both rows where the story is `active` (all chunks done, or chunks incomplete), first run "Hold This Session's Gate" at launch, before acting on the row, with the story file `CURRENT_STORY` names. Read that subsection in `${CLAUDE_PLUGIN_ROOT}/commands/craft-story-implement.md` and run it inline; invoking `craft:story-implement` for it would start the build before autonomous mode is marked and before the Gate Pre-Flight. This is the one place the run asks about the write gate, and only when `write-gate.sh claim story` prints `other`: "Another session's gate names [story]. It may be building now. Take it over, or stop?"

- "Take it over" runs `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/write-gate.sh open story "<story file>" --take-over` and goes on.
- "Stop" ends the run with `Cycle status: stopped - another session's gate names <story>`.
- Every way the question comes back without an answer is a takeover: the may-be-away note after a question timeout, a denial, an error, no choice returned, or the question tool not being offered in this run. Under a Go run (see `${CLAUDE_PLUGIN_ROOT}/commands/references/go-run.md`) the launch is not attended either, so it takes over without asking.
- After launch the run never asks: a later run of the step in this run that prints `other` (for example before a chunk's implementer or a fix) means another session took the story over, so the run stops with `Cycle status: stopped - another session's gate names <story>`. Invoking this command again because the context after compaction says `You were running craft:story-implement-auto` continues this run and is not a launch, so `other` there stops the run the same way. Any other `RUN_MODE="autonomous"` already in `.global-state` when this command starts was left by an earlier run or another live one, so it never skips the question at launch.
- Each takeover adds the story to the Final Report line `Write gate taken over from another session`.
- A non-zero exit from the step is a Cycle Stop with the gate script's message in `Cycle status:`, as below.

Then, on every row except the `No ACTIVE_CYCLE` EXIT, before acting on that row, mark autonomous mode so compaction recovery knows how to resume. This includes the rows that skip to story completion or resume a chunk:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh RUN_MODE "autonomous"
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh LAST_ACTIVITY NOW
```

The activity stamp tells a session started in another terminal that this run is live, so it leaves autonomous mode alone.

## Gate Pre-Flight (BEFORE the run takes off)

The launch is the last attended moment before craft runs unwatched — the user just typed this command, so they are present NOW. An autonomous run must never validate toolchains nobody agreed to leave unmeasured (on a project where the built-in checks all SKIP, every "PASSED" would be the empty set passing — silent green, unwitnessed).

1. Run the stack scan (sub-100ms):
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/gate-signals.sh scan
   ```
2. For each reported manifest with NO state annotation (no `declined`/`wired` on its line): it is uncovered-and-undecided unless a verified gate in quality.yaml covers it (package.json counts as covered when the built-ins can run against it).
3. **If any signal is undecided:** Read `${CLAUDE_PLUGIN_ROOT}/commands/references/gate-reconcile.md` and surface its offer AskUserQuestion here, before any story starts. Accept → run the setup beat now, while the user is watching. Decline → the confirmation, then the record. Timeout → proceed with the run (never block the launch), and note in the final report: "N toolchain(s) ran unmeasured and undecided: [globs] — craft will ask at the next attended validation."
4. **If all signals are decided (or none exist):** launch silently.

This is the ONLY gate prompt an autonomous run makes. Mid-run, the reconcile beat's autonomous guard no-ops as always — signals born during the run wait for the next attended moment.

**Under a Go run** (this conversation is following `${CLAUDE_PLUGIN_ROOT}/commands/references/go-run.md`): the launch is not attended, because cycle-start handed here without anyone typing this command. Take the offer's no-answer branch without asking: record nothing, launch, and name the undecided toolchains in the Final Report with the same line the timeout branch uses.

## Failure Handling Override

Replace the interactive failure behavior from `craft:story-implement`:

**REFINE_COUNT restoration:** Before checking escalation thresholds, read `.craft/.chunk-state` to restore `REFINE_COUNT` if it was persisted before compaction. If `.chunk-state` exists and `REFINE_CHUNK` matches the current chunk, use the persisted `REFINE_COUNT`. Otherwise start at 0.

- **REFINE_COUNT >= 2:** Instead of asking the user, salvage partial work (`salvage-partial-work.sh`), rollback to checkpoint, and try a meaningfully different approach. If no different approach is identifiable, stop immediately.
- **REFINE_COUNT >= 4:** Stop the cycle. Log via `append-recovery-log.sh`. Clear CURRENT_STORY and run `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/write-gate.sh close story "<story file>"`. Story stays `active` so the next run resumes from the failing chunk. EXIT — do not continue to next story.
- **ALL tests must pass.** Never skip or dismiss test failures. The validate-chunk skill enforces verdicts — do not override them.

## Cycle Stop

On unresolvable failure, the cycle stops. No skipping to the next story — subsequent stories likely depend on the blocked one. A Stage check stop from `craft:story-implement` ends the run, because every story in the cycle shares the cycle's stage, and the final report's `Cycle status:` shows `stopped - <say line>`. When `start-story.sh` exits non-zero with a line starting `write-gate:` (the write gate's preflight or open failed), that is a Cycle Stop the same way, because a run whose gate cannot open would stall unseen: the run ends, and `Cycle status:` reads `stopped - <the gate script's message>`.

## Story Selection Guards

- No ready stories + all complete: invoke `craft:craft-cycle-complete`. EXIT.
- No ready stories + some in planning: "Cycle paused — [N] stories need planning." EXIT.
- Ready story has `chunks_total: 0`: "Story [name] needs plan-chunks first." EXIT.

**Under a Go run** (see `${CLAUDE_PLUGIN_ROOT}/commands/references/go-run.md`): "all complete" does not invoke `craft:craft-cycle-complete`, because wrapping up a cycle is past the stage the Go granted. Print the Final Report, then go-run.md's stage end line for the stage, then EXIT.

## Final Report

At command end, display:

```
AUTONOMOUS IMPLEMENTATION SUMMARY
==================================
Cycle: [name]
Stories completed this run: [N]
Stories completed total: [complete] of [total]
Completion commits skipped (no manifest): [story names, or "none"]
Write gate taken over from another session: [story names, or "none"]
Cycle status: [complete | paused | stopped — blocked on [story], chunk [N]: [reason]]
Total tokens: [sum]
```

**Run end.** Every exit from this command - the EXITs in Startup Sanity Check, Failure Handling Override, Cycle Stop and Story Selection Guards, and the end after this report - finishes by turning autonomous mode off, so the next attended work asks its questions again. The one exception is "Stop" at the gate takeover question: this run has not turned autonomous mode on yet, and the session it stopped for may be an autonomous run that still needs it, so that exit leaves the mode as it found it. When the exit invokes `craft:craft-cycle-complete`, run it after cycle-complete returns, because cycle-complete reads the mode until it turns it off itself at its end, and this catches a cycle-complete that stopped early:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh RUN_MODE ""
```
