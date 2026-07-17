#!/bin/bash
# test-mockup-preflight.sh - Guard Story 18's locked strings in the mockup funnel spec.
# Doc-level assertions that the first-run pre-flight beat is specced as locked: the
# Setup AUQ copy verbatim, the beat's position (after the cold-start determination,
# before the mkdir anchor), the amended taste-AUQ invariant, the never-escalate and
# scoped no-guess rules, the self-elimination property with its one deliberate
# exception (Init-first exits before the record), and the survival of the
# load-bearing guards (no-default-palette, (Recommended) marker, substeps-never-
# tasks). The Scope AUQ was REMOVED at owner review 2026-07-17 (it minimalized the
# first-run wow) - a negative below guards against its return. Adjacent stories edit
# this same shared file; a paraphrased rule or re-voiced copy should fail the suite.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

MOCKUP="$PLUGIN_ROOT/commands/references/mockup-inline.md"

# The pre-flight beat, extracted for scoped assertions ("guess" legitimately appears
# elsewhere in mockup-inline.md - "second-guessed" in the settle gate and "guesses"
# in Step 6 - and the no-guess RULE statement itself sits above the beat heading,
# outside this slice by design).
BEAT_BLOCK="$(sed -n '/Pre-flight (first mockup only)/,/mkdir -p/p' "$MOCKUP")"

# --- Position: the beat sits between the cold-start determination and the mkdir ---
begin_test "pre-flight beat sits after the cold-start determination and before the mkdir"
assert_file_exists "mockup-inline.md exists" "$MOCKUP"
DET_LINE="$(grep -n 'Cold (no root resolves)' "$MOCKUP" | head -1 | cut -d: -f1)"
BEAT_LINE="$(grep -n 'Pre-flight (first mockup only)' "$MOCKUP" | head -1 | cut -d: -f1)"
MKDIR_LINE="$(grep -n 'mkdir -p' "$MOCKUP" | head -1 | cut -d: -f1)"
POSITION="wrong"
if [ -n "$DET_LINE" ] && [ -n "$BEAT_LINE" ] && [ -n "$MKDIR_LINE" ] \
  && [ "$BEAT_LINE" -gt "$DET_LINE" ] && [ "$BEAT_LINE" -lt "$MKDIR_LINE" ]; then
  POSITION="between"
fi
assert_eq "beat heading between determination and mkdir anchor" "between" "$POSITION"

# --- Setup AUQ transcribed verbatim ---
begin_test "Setup AUQ transcribed verbatim"
assert_file_contains "Setup question line verbatim" 'This mockup can grow from what'"'"'s already on disk, or from what you'"'"'re actually chasing right now. Bring inspiration in first, or just go from your existing code.' "$MOCKUP"
assert_file_contains "Setup header present" 'header: "Setup"' "$MOCKUP"
assert_file_contains "Init first label present with Recommended marker" 'label: "Init first (Recommended)"' "$MOCKUP"
assert_file_contains "Init first description verbatim" 'The full session - pull colors from one site, type from another, riff until it'"'"'s right. The mockup grows out of that.' "$MOCKUP"
assert_file_contains "Go from disk label present" 'label: "Go from what'"'"'s on disk"' "$MOCKUP"
assert_file_contains "Go from disk description verbatim" 'Reads your actual code, no reference brought in. Fast, and still real - just working from what you'"'"'ve already made, not what you'"'"'re chasing next.' "$MOCKUP"

# --- Init first reuses the zero-visual-files rules ---
begin_test "Init first reuses the zero-visual-files rules"
assert_contains "funnel stops" 'the funnel STOPS here' "$BEAT_BLOCK"
assert_contains "no confirmation AUQ" 'no confirmation AskUserQuestion' "$BEAT_BLOCK"
assert_contains "no auto-resume" 'no auto-resume' "$BEAT_BLOCK"
assert_contains "notebook capture after init exists" 'captured to the notebook AFTER init exists' "$BEAT_BLOCK"

# --- Init-first exception: exits before the record, re-offer is deliberate ---
begin_test "Init-first exception stated - still-cold return re-offers Setup deliberately"
assert_contains "exit precedes the record" 'This exit happens BEFORE the record is created' "$BEAT_BLOCK"
assert_contains "re-offer is deliberate" 'offered Setup again - deliberately' "$BEAT_BLOCK"
assert_contains "no marker write on the exit" 'No marker is ever written on this exit' "$BEAT_BLOCK"

# --- Scope AUQ stays removed (owner call, 2026-07-17: it minimalized the wow) ---
begin_test "Scope AUQ stays removed"
assert_file_not_contains "no Scope header returns" 'header: "Scope"' "$MOCKUP"
assert_file_not_contains "no Section placeholder returns" '{Section}' "$MOCKUP"

# --- Trigger: Setup cold + first-mockup ---
begin_test "Setup trigger is cold + first-mockup-only"
assert_contains "Setup rides the visual-files-present branch" 'fires on the cold path'"'"'s visual-files-present branch only' "$BEAT_BLOCK"
assert_contains "zero-visual-files branch keeps its hard route" 'keeps its hard route' "$BEAT_BLOCK"

# --- Gate: record glob under the funnel's resolved root ---
begin_test "gate check names the resolved root and the record glob"
assert_contains "record.md glob named" 'holds no `\*/record.md`' "$BEAT_BLOCK"
assert_contains "resolved against the funnel root" 'resolved against the funnel'"'"'s own root' "$BEAT_BLOCK"
assert_contains "never PWD-relative" 'never PWD-relative' "$BEAT_BLOCK"
assert_contains "shell Step 2 idiom excluded" 'never the shell'"'"'s Step 2 idiom' "$BEAT_BLOCK"

# --- Amended invariant ---
begin_test "amended invariant names three taste + one pre-flight AUQ"
assert_file_contains "amended taste count present" 'Exactly three taste AskUserQuestion calls exist' "$MOCKUP"
assert_file_contains "pre-flight allowance present" 'One first-run pre-flight AUQ' "$MOCKUP"
assert_file_contains "retained taste-protection sentence verbatim" 'a widget between the user and their taste kills the funnel' "$MOCKUP"
assert_file_not_contains "old exactly-three literal gone" 'Exactly three AskUserQuestion calls exist' "$MOCKUP"
assert_file_not_contains "old never-add-a-fourth literal gone" 'Never add a fourth' "$MOCKUP"

begin_test "no stale fourth remains"
assert_file_not_contains "Step 6 count reference neutralized" 'never a fourth AskUserQuestion' "$MOCKUP"

# --- Never-escalate + no-guess rules ---
begin_test "never-escalate rule stated as locked constraint"
assert_file_contains "escalation ban distinctive phrase" 'tune this beat to drive init adoption' "$MOCKUP"
assert_file_contains "options stay first-class" 'all options stay first-class permanently' "$MOCKUP"
assert_file_contains "disk option never the lesser" 'never written as the lesser option' "$MOCKUP"

begin_test "no-guess rule stated, and no pre-flight string says guess (scoped)"
assert_file_contains "no-guess rule stated" 'No pre-flight string may contain "guess" or "guessing"' "$MOCKUP"
assert_not_contains "beat slice free of guess" 'guess' "$BEAT_BLOCK"
assert_not_contains "beat slice free of Guess" 'Guess' "$BEAT_BLOCK"

# --- Self-elimination ---
begin_test "self-elimination stated - the run's own record creation deletes the question"
assert_contains "record write is the eraser" 'write below is what deletes it' "$BEAT_BLOCK"
assert_contains "prior mockup silences it" 'a project that has mocked before never sees it' "$BEAT_BLOCK"

# --- Load-bearing guards survive ---
begin_test "load-bearing guards survive"
assert_file_contains "no-default-palette contract intact" 'no default palette ever reaches a brief' "$MOCKUP"
assert_file_contains "(Recommended) marker conditional intact" 'Include the muse (Recommended)' "$MOCKUP"
assert_file_contains "substeps-never-tasks intact" 'Substeps never become tasks' "$MOCKUP"
assert_file_contains "pre-flight named as substep with no rail entry" 'no entry on the task rail' "$MOCKUP"

finish_tests
