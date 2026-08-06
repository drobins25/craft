#!/bin/bash
# test-riff-conversation.sh - Guard Story 25's single-mode conversational riff.
# The skill is a main-loop conversation: one plain-prose question per turn,
# never-naked questions, a receipt beat, bare invocation seeded from the oldest
# open notebook idea, and no dispatch machinery (no Agent tool, no SendMessage,
# no AUQ, no shared-reference Reads). These assertions pin the locked
# frontmatter, the spine and its corollaries, and the absence of every removed
# mechanism, so a future edit that resurrects the router fails the suite.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

RIFF="$PLUGIN_ROOT/commands/craft-riff.md"
RIFF_CONTENT="$(cat "$RIFF")"
# Body = everything from the H1 down. The locked when_to_use legitimately names
# AskUserQuestion (as a prohibition); the body must not carry the string at all.
BODY="$(sed -n '/^# Riff$/,$p' "$RIFF")"

# --- Chunk 1: the rewritten skill ---

begin_test "frontmatter ships the locked description verbatim"
assert_contains_literal "locked description present character-for-character" 'description: "Calibrate thinking one question at a time - a main-loop conversation, one plain-prose question per turn, until the direction lands. Bare invocation opens from the oldest open notebook idea."' "$RIFF_CONTENT"

begin_test "frontmatter ships the locked when_to_use triggers and anti-triggers"
assert_contains_literal "explicit trigger vocabulary present" '"riff on this", "can we riff", "help me think' "$RIFF_CONTENT"
assert_contains_literal "one-question-at-a-time is a first-class trigger" '"one question at a time" - or invokes /craft:riff' "$RIFF_CONTENT"
assert_contains_literal "self-catch offer line present" "say the word if you'd rather break it down and riff" "$RIFF_CONTENT"
assert_contains_literal "per-wall decline semantics present" 'Decline or silence = drop it for this wall' "$RIFF_CONTENT"
assert_contains_literal "anti-triggers present" 'Not for: fact-shaped question runs (those stay AUQ)' "$RIFF_CONTENT"

begin_test "registration keys survive"
assert_file_contains "name key intact" '^name: riff$' "$RIFF"
assert_file_contains "argument-hint intact" '^argument-hint:' "$RIFF"

begin_test "no agent dispatch, SendMessage, AUQ, or shared-reference Read remains"
assert_file_not_contains "no Agent tool dispatch" 'Agent tool' "$RIFF"
assert_file_not_contains "no subagent_type" 'subagent_type' "$RIFF"
assert_file_not_contains "no SendMessage continuation" 'SendMessage' "$RIFF"
assert_not_contains "no AskUserQuestion in the body" 'AskUserQuestion' "$BODY"
assert_file_not_contains "no calibration-loop Read" 'calibration-loop.md' "$RIFF"
assert_file_not_contains "no hunch-settling Read" 'hunch-settling.md' "$RIFF"

begin_test "the spine leads the body"
assert_contains_literal "spine statement present" "you hold one thing at a time - and it's always the decision" "$BODY"
assert_contains_literal "partner carries everything else" 'I carry everything else' "$BODY"
SPINE_LINE="$(grep -n 'you hold one thing at a time' "$RIFF" | head -1 | cut -d: -f1)"
COROLLARY_LINE="$(grep -n 'One question per turn' "$RIFF" | head -1 | cut -d: -f1)"
assert_eq "spine precedes the corollaries" "yes" "$([ -n "$SPINE_LINE" ] && [ -n "$COROLLARY_LINE" ] && [ "$SPINE_LINE" -lt "$COROLLARY_LINE" ] && echo yes || echo no)"
assert_contains_literal "editor guard follows the spine" "ask which one is carrying it - don't add a rule that isn't a consequence of the spine" "$BODY"

begin_test "one-question discipline names its prohibitions"
assert_contains_literal "exactly one question, then wait" 'Ask exactly one question, in plain prose, then stop and wait' "$BODY"
assert_contains_literal "numbered lists prohibited" 'Never a numbered question list' "$BODY"
assert_contains_literal "a-few-things-I'm-wondering prohibited" 'never "a few things I'"'"'m wondering"' "$BODY"
assert_contains_literal "AUQ substitute prohibited" 'never an AUQ chip as a substitute' "$BODY"

begin_test "questions never arrive naked"
assert_contains_literal "what hangs on the answer stated" 'Every question says what hangs on the answer' "$BODY"
assert_contains_literal "earned lean stated" 'my lean: X, because Y' "$BODY"
assert_contains_literal "manufactured recommendation named as the same failure" 'a manufactured recommendation is the same failure as a bare question' "$BODY"

begin_test "pull mode is carved out"
assert_contains_literal "withheld lean carve-out present" 'deliberately hold a formable lean back and ask the real question instead' "$BODY"
assert_contains_literal "withheld lean still carried" 'still yours to carry, never theirs to miss' "$BODY"

begin_test "answers get a receipt"
assert_contains_literal "receipt beat present" 'one short human line before the next question' "$BODY"
assert_contains_literal "wording is free, not a stamp" 'one valid form, never a required stamp' "$BODY"

begin_test "wall is context, not an agenda"
assert_contains_literal "wall named as context" 'the wall of questions that triggered it is context, not a checklist' "$BODY"
assert_contains_literal "open with the unlocking question" 'the one question that most unlocks the direction' "$BODY"
assert_contains_literal "abandoned wall is the partner's to drop" "yours to drop, never the user's to finish" "$BODY"

begin_test "bare invocation seeds via the notebook list helper"
assert_contains_literal "helper invocation present" 'notebook-list.sh ideas' "$BODY"
assert_contains_literal "first record block is the seed" 'FIRST emitted record block' "$BODY"
assert_contains_literal "riff never writes idea files" 'never writes them' "$BODY"
assert_contains_literal "seeding is bare-only" 'fires ONLY on bare invocation' "$BODY"

begin_test "empty notebook is a branch, not an error"
assert_contains_literal "empty output is a branch" 'a branch, not an error' "$BODY"
assert_contains_literal "no init push" 'no init push' "$BODY"

begin_test "session ends without ceremony"
assert_contains_literal "no landing ceremony" 'no landing ceremony' "$BODY"
assert_contains_literal "index grammar is the net" "orchestration index's existing grammar" "$BODY"

begin_test "one inline offer per turn survives"
assert_contains_literal "offer-stacking rule present" 'At most one inline offer per turn' "$BODY"

# --- Chunk 2: the orchestration index wiring ---

INDEX="$PLUGIN_ROOT/reference/orchestration-index.min"
INDEX_CONTENT="$(cat "$INDEX")"

begin_test "index carries the riff self-catch routing row"
assert_contains_literal "routing row present verbatim" "2+ questions in one turn on an undecided direction (main loop only, never inside another flow's gate)|append ignorable riff offer; on accept → craft:riff" "$INDEX_CONTENT"

begin_test "riff row sits inside the offer-row block"
MOCKUP_ROW_LINE="$(grep -n 'craft:mockup, session context seeds the brief' "$INDEX" | head -1 | cut -d: -f1)"
RIFF_ROW_LINE="$(grep -n 'append ignorable riff offer' "$INDEX" | head -1 | cut -d: -f1)"
assert_eq "riff row directly follows the mockup-offer row" "yes" "$([ -n "$MOCKUP_ROW_LINE" ] && [ -n "$RIFF_ROW_LINE" ] && [ "$RIFF_ROW_LINE" -eq $((MOCKUP_ROW_LINE + 1)) ] && echo yes || echo no)"

begin_test "index carries the no-offer-stacking rule"
assert_contains_literal "rules line present" '!stack inline offers—max one per turn' "$INDEX_CONTENT"

begin_test "notebook chains line is gone"
assert_file_not_contains "skill-internal notebook chain removed" 'notebook→capture' "$INDEX"

begin_test "notebook deferral routing survives"
assert_contains_literal "deferral-marker row still present" 'deferral marker in user utterance' "$INDEX_CONTENT"

begin_test "index stays under the injection cap"
INDEX_BYTES="$(wc -c < "$INDEX" | tr -d ' ')"
assert_eq "byte count under 5632" "yes" "$([ "$INDEX_BYTES" -lt 5632 ] && echo yes || echo no)"

finish_tests
