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

- **No AskUserQuestion calls.** At every decision point in `craft:story-implement`, choose the recommended option automatically. Never wait for user input.
- **Auto-pick stories.** Select the next `status: ready` story in the active cycle, in filename order. No story selection prompt.
- **Chain stories.** After completing a story, pick the next ready one. Continue until no more ready stories or failure.
- **Auto-answer defaults.** Package manager: auto-detect from lockfiles, default to npm. Test infra: set up Vitest if missing. Spark verification: self-check acceptance criteria — only stop on provably unmet (file doesn't exist, test doesn't pass), not subjective judgments.
- **Validation via skill.** Same `craft:validate-chunk` skill invocation as `craft:story-implement`. The skill handles all routing autonomously — no AskUserQuestion calls needed since refine-chunk and test-fix are already non-interactive.

## Startup Sanity Check

First, read `.global-state` and handle stale state from a crashed previous run:

| Condition | Action |
|-----------|--------|
| No `ACTIVE_CYCLE` | "No active cycle." EXIT. |
| `CURRENT_STORY` set, story is `complete` | Stale state — clear CURRENT_STORY, CRAFT_WRITE_ENABLED, cycle state. Proceed to story selection. |
| `CURRENT_STORY` set, story is `active`, all chunks done | Crashed before `complete-story.sh`. Skip to story completion flow. NOTE: the dead session's `.craft/.commit-manifest` is gone (session-start clears it), so if you resume past the manifest-write sub-step (story-implement 7b) without re-writing it, `complete-story.sh` makes NO commit by design ("no manifest found"). Re-run sub-step 7b before Mark Complete, or surface "completion commit skipped (no manifest)" in the final report. |
| `CURRENT_STORY` set, story is `active`, chunks incomplete | Resume from current chunk. Trust story frontmatter (`chunks_complete + 1`) as ground truth. |
| `CRAFT_WRITE_ENABLED` set but no `CURRENT_STORY` | Orphaned flag — clear it. Proceed to story selection. |
| Clean state | Normal start. Proceed to story selection. |

Then, once the table leaves a run to start, mark autonomous mode so compaction recovery knows how to resume:

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
- **REFINE_COUNT >= 4:** Stop the cycle. Log via `append-recovery-log.sh`. Clear CURRENT_STORY and CRAFT_WRITE_ENABLED. Story stays `active` so the next run resumes from the failing chunk. EXIT — do not continue to next story.
- **ALL tests must pass.** Never skip or dismiss test failures. The validate-chunk skill enforces verdicts — do not override them.

## Cycle Stop

On unresolvable failure, the cycle stops. No skipping to the next story — subsequent stories likely depend on the blocked one. A Stage check stop from `craft:story-implement` ends the run, because every story in the cycle shares the cycle's stage, and the final report's `Cycle status:` shows `stopped - <say line>`.

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
Cycle status: [complete | paused | stopped — blocked on [story], chunk [N]: [reason]]
Total tokens: [sum]
```

**Run end.** Every exit from this command - the EXITs in Startup Sanity Check, Failure Handling Override, Cycle Stop and Story Selection Guards, and the end after this report - finishes by turning autonomous mode off, so the next attended work asks its questions again. When the exit invokes `craft:craft-cycle-complete`, run this after it returns, because cycle-complete reads autonomous mode to know nobody is watching:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh RUN_MODE ""
```
