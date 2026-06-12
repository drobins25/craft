---
name: craft:story-implement-auto
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

First, mark autonomous mode so compaction recovery knows how to resume:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh RUN_MODE "autonomous"
```

Then read `.global-state` and handle stale state from a crashed previous run:

| Condition | Action |
|-----------|--------|
| No `ACTIVE_CYCLE` | "No active cycle." EXIT. |
| `CURRENT_STORY` set, story is `complete` | Stale state — clear CURRENT_STORY, CRAFT_WRITE_ENABLED, cycle state. Proceed to story selection. |
| `CURRENT_STORY` set, story is `active`, all chunks done | Crashed before `complete-story.sh`. Skip to story completion flow. NOTE: the dead session's `.craft/.commit-manifest` is gone (session-start clears it), so if you resume past the manifest-write sub-step (story-implement 7b) without re-writing it, `complete-story.sh` makes NO commit by design ("no manifest found"). Re-run sub-step 7b before Mark Complete, or surface "completion commit skipped (no manifest)" in the final report. |
| `CURRENT_STORY` set, story is `active`, chunks incomplete | Resume from current chunk. Trust story frontmatter (`chunks_complete + 1`) as ground truth. |
| `CRAFT_WRITE_ENABLED` set but no `CURRENT_STORY` | Orphaned flag — clear it. Proceed to story selection. |
| Clean state | Normal start. Proceed to story selection. |

## Failure Handling Override

Replace the interactive failure behavior from `craft:story-implement`:

**REFINE_COUNT restoration:** Before checking escalation thresholds, read `.craft/.chunk-state` to restore `REFINE_COUNT` if it was persisted before compaction. If `.chunk-state` exists and `REFINE_CHUNK` matches the current chunk, use the persisted `REFINE_COUNT`. Otherwise start at 0.

- **REFINE_COUNT >= 2:** Instead of asking the user, salvage partial work (`salvage-partial-work.sh`), rollback to checkpoint, and try a meaningfully different approach. If no different approach is identifiable, stop immediately.
- **REFINE_COUNT >= 4:** Stop the cycle. Log via `append-recovery-log.sh`. Clear CURRENT_STORY and CRAFT_WRITE_ENABLED. Story stays `active` so the next run resumes from the failing chunk. EXIT — do not continue to next story.
- **ALL tests must pass.** Never skip or dismiss test failures. The validate-chunk skill enforces verdicts — do not override them.

## Cycle Stop

On unresolvable failure, the cycle stops. No skipping to the next story — subsequent stories likely depend on the blocked one.

## Story Selection Guards

- No ready stories + all complete: invoke `craft:craft-cycle-complete`. EXIT.
- No ready stories + some in planning: "Cycle paused — [N] stories need planning." EXIT.
- Ready story has `chunks_total: 0`: "Story [name] needs plan-chunks first." EXIT.

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
