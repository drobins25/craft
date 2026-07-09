# Gate Reconcile Beat

Read-inline reference. Runs at every PASSED validation, after the report is parsed and BEFORE `complete-chunk.sh`. Both validation surfaces (the story-implement loop and the manual validate-chunk skill) Read and run this file inline — NEVER invoke it via the Skill tool.

This beat keeps quality gates honest as the project's stack evolves: when the validator's coverage row shows a toolchain no gate measures, offer once to wire it up. The answer is written with provenance; enforcement follows the written record.

## Guards (check in this order — most runs exit at step 1 or 2)

1. **PASSED reports only.** The validation status is PASSED (or PARTIAL promoted to continue on a non-final chunk). On FAILED, skip this file entirely — never stack an offer on a failure.
2. **Steady state exits silently.** From the parsed report, collect:
   - the `Gates` row value
   - any Warnings with Type `rot-warning`

   If the Gates row is `full coverage` or `coverage unknown (no probe)` AND there are no rot-warnings → nothing to do. Continue to complete-chunk.sh immediately. No output.
3. **Autonomous runs never prompt.** If RUN_MODE=autonomous: no-op the entire beat — record nothing, offer nothing. The uncovered signal stays visible in every validation report's coverage row and surfaces when a human next steps in. (Mirrors the leftover-triage leave-and-report guard.)

## Uncovered signals: the ask-once check

For each uncovered manifest glob named in the Gates row, check the per-signal record:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/gate-signals.sh lookup "<glob>"
```

- Non-empty result (`declined` or `wired`) → that signal is settled. Say nothing about it.
- Empty result → the signal is unrecorded. It goes in the offer.

**The never-re-ask check is this script lookup, not your memory.**

If no uncovered signal is unrecorded → continue to complete-chunk.sh. No output.

## The offer (one ignorable line)

Say ONE plain inline line naming every unrecorded uncovered signal — NOT an AskUserQuestion:

> New since gates were last set: *.csproj — wire it up? Otherwise continuing.

Then continue the flow. This line is ignorable by design:

- **No reaction / topic change:** record nothing (nothing is inferred from silence), run complete-chunk.sh, continue the loop. The line may reappear at the next PASS — one line, zero writes.
- **Decline** ("no", "skip it", "not now"): per declined signal:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/gate-signals.sh record "<glob>" declined
  ```
  A declined signal never asks again until that signal itself changes.
- **Accept** ("yes", "wire it up"): run the setup beat below, then continue.

## The setup beat (on accept only)

You are in the main conversation; the validator stays a cheap judge. For each accepted signal:

1. **Propose from evidence.** Look at what the manifest exposes (solution/project names, Makefile targets, script entries) and propose concrete command(s):

   > Tests for the .NET backend: `dotnet test backend/App.sln` — run it to verify?

   **The proposal is an editable draft, never take-it-or-leave-it.** Accept free text — a user-typed or user-edited command becomes the candidate. You MAY use AskUserQuestion here (an affirmative already opened the beat); its options present the three gate strengths visibly:
   - run/edit the command as a blocking gate
   - keep the command but `blocking: false` (runs every validation, WARNs, never fails a chunk)
   - decline the signal after all (record `declined`)

2. **Verify-run EVERY candidate** — agent-proposed or user-edited, editing never skips verification:
   ```bash
   cd "${CRAFT_PROJECT_ROOT:-.}" && <candidate command>
   ```
   Synchronous, NEVER `run_in_background`. Classify:
   - **Starts and passes** → proceed to write.
   - **Starts but fails** → brownfield reality. Report the pre-existing failure count honestly and offer `blocking: false` with a note, so the gate catches new errors only. On the user's choice, proceed to write.
   - **Cannot start (exit 127)** → report it, offer to edit the command or decline the signal. NEVER write a `verified:` stamp for a command that did not start.

3. **Write with provenance.** Add the gate to `.craft/quality.yaml` under `gates:` — a name that is NOT one of typecheck/lint/build/tests (those stay owned by the built-in checks):
   ```yaml
   tests-dotnet:
     enabled: true
     command: "dotnet test backend/App.sln"
     blocking: false        # 3 pre-existing failures, noted 2026-07-08
     verified: 2026-07-08
   ```
   Then record the signal as settled:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/gate-signals.sh record "<glob>" wired
   ```

The standing escape hatch is untouched by all of this: a user may hand-edit quality.yaml and self-stamp `verified:` — the validator honors any non-empty stamp without ceremony.

## Rot re-fire

If the report carries a `rot-warning` (a verified gate's command exited 127 — command not found), the gate's verification is broken, not failing. Offer once, inline:

> The verified gate for [gate-name] no longer runs — re-verify?

- **Accept:** run the setup beat for that gate — propose the existing command as the editable draft, verify-run the (possibly edited) candidate, refresh `verified:` on success.
- **Decline / no reaction:** leave the gate as written. It keeps reporting rot-warning WARN — visible, never silent, never a chunk failure.

## Exit

However the beat resolves, control returns to the caller's PASSED path: run complete-chunk.sh and continue the loop. This beat never blocks completion and never fires on FAILED.
