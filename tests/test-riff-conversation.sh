#!/bin/bash
# test-riff-conversation.sh - Guard Story 27's riff: the game.
# The skill is a game box: a rules-card lid plus four panels, written for BOTH
# readers (user and Claude). These assertions pin the locked card literals, the
# kept when_to_use triggering layer (byte-identical from Story 25 - it is
# field-validated), the two mechanical residues (notebook seeding, bank-your-riff),
# and the absence of every removed mechanism, so a future edit that respecs the
# game as rules fails the suite.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

RIFF="$PLUGIN_ROOT/commands/craft-riff.md"
RIFF_CONTENT="$(cat "$RIFF")"
# Body = everything from the H1 down. The locked when_to_use legitimately names
# AskUserQuestion (as a prohibition); the body must not carry the string at all.
BODY="$(sed -n '/^# RIFF$/,$p' "$RIFF")"

# --- Chunk 1: the game box ---

begin_test "frontmatter ships the approved description verbatim"
assert_contains_literal "description present character-for-character" 'description: "Riff on an idea together - a two-player conversation in small beats, one concept at a time, until it'"'"'s ready to build. Bare invocation opens from the oldest open notebook idea."' "$RIFF_CONTENT"

begin_test "frontmatter keeps the Story 25 when_to_use triggers and anti-triggers"
assert_contains_literal "explicit trigger vocabulary present" '"riff on this", "can we riff", "help me think' "$RIFF_CONTENT"
assert_contains_literal "work-through vocabulary present" '"let'"'"'s work through this"' "$RIFF_CONTENT"
assert_contains_literal "one-question-at-a-time is a first-class trigger" '"one question at a time" - or invokes /craft:riff' "$RIFF_CONTENT"
assert_contains_literal "self-catch names the sender's own imminent turn" 'when you are about to send' "$RIFF_CONTENT"
assert_contains_literal "trigger is overload, not question count" 'a wall of options or analysis counts the same' "$RIFF_CONTENT"
assert_contains_literal "questions ship as written" 'ship it as written' "$RIFF_CONTENT"
assert_contains_literal "self-catch offer line present" "let me know if you'd rather riff" "$RIFF_CONTENT"
assert_contains_literal "per-wall decline semantics present" 'Decline or silence = drop it for this wall' "$RIFF_CONTENT"
assert_contains_literal "anti-triggers present" 'Not for: fact-shaped question runs (those stay AUQ)' "$RIFF_CONTENT"
assert_contains_literal "value-question runs carved out" 'value questions with the direction already implied' "$RIFF_CONTENT"

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

begin_test "the lid opens the box"
assert_contains_literal "two players, equals" '**Players: 2. Equals.**' "$BODY"
assert_contains_literal "one idea too hot to hold alone" 'one idea too hot to hold alone' "$BODY"
assert_contains_literal "superpowers and keyboard" 'You have the superpowers. Your partner has the keyboard.' "$BODY"
assert_contains_literal "heat transfers into the players" 'the potato cools, you heat up' "$BODY"
assert_contains_literal "the catch is shown before the toss" 'Show the catch' "$BODY"
assert_contains_literal "settled stays settled" "what's settled stays settled" "$BODY"
assert_contains_literal "the stack fires the superpower" 'hands in. **SUPERPOWER.**' "$BODY"
assert_contains_literal "legacy line closes the lid" 'This is a legacy game. It remembers how you play.' "$BODY"
LID_LINE="$(grep -n 'You have the superpowers' "$RIFF" | head -1 | cut -d: -f1)"
PANEL_LINE="$(grep -n '^## When to play' "$RIFF" | head -1 | cut -d: -f1)"
assert_eq "lid precedes the panels" "yes" "$([ -n "$LID_LINE" ] && [ -n "$PANEL_LINE" ] && [ "$LID_LINE" -lt "$PANEL_LINE" ] && echo yes || echo no)"

begin_test "hogging and dropping are both losses"
assert_contains_literal "the wall is hogging" 'a wall of text is thirty blind guesses nobody aimed' "$BODY"
assert_contains_literal "drop loses for both" 'Drop it and you both lose' "$BODY"
assert_contains_literal "pushback belongs in the game" 'Push back when you see the ghoul' "$BODY"

begin_test "when-to-play covers word, heat, and self-catch"
assert_contains_literal "the word is the invitation" 'The word is the invitation' "$BODY"
assert_contains_literal "hot idea is a potato" "That's a potato. Start passing." "$BODY"
assert_contains_literal "beats measured in concepts, not size" "Don't judge the piece by its size - toss the one you believe in most" "$BODY"
assert_contains_literal "one concept a beat" 'One concept a beat, full strength' "$BODY"
assert_contains_literal "in-body offer line present" 'want to riff through it?' "$BODY"
assert_contains_literal "offer discipline present" 'Never a widget. Never twice in a row.' "$BODY"

begin_test "new tables get the behavior, not the bit"
assert_contains_literal "play it, don't narrate it" "Play the game, don't narrate it" "$BODY"
assert_contains_literal "words are for players who know them" 'save the words for players who know them' "$BODY"

begin_test "when-not-to-play protects the answer path"
assert_contains_literal "answers stay answers" 'Your partner just wants the answer - give the answer' "$BODY"
assert_contains_literal "unwanted game named as a wall" 'A game nobody asked for is a wall with extra steps' "$BODY"

begin_test "bare invocation seeds via the notebook list helper"
assert_contains_literal "helper invocation present" 'notebook-list.sh ideas' "$BODY"
assert_contains_literal "first record block is the seed" 'FIRST emitted record block' "$BODY"
assert_contains_literal "riff never writes idea files" 'never writes' "$BODY"
assert_contains_literal "seeding is bare-only" 'fires ONLY on bare invocation' "$BODY"
assert_contains_literal "empty output is a branch" 'a branch, not an error' "$BODY"
assert_contains_literal "no init push" 'no init push' "$BODY"

begin_test "the story panel teaches by example"
assert_file_contains "story panel present" '^## From a Claude who got called partner$' "$RIFF"
assert_contains_literal "the power belongs to neither seat" 'We defined the game by playing it. The power was the result.' "$BODY"
assert_contains_literal "partner moment recorded" 'somewhere in there one of us said "partner"' "$BODY"

begin_test "the ending is a mutual stack, not a ceremony"
assert_contains_literal "the stack question" '*hands in?*' "$BODY"
assert_contains_literal "asking is not the stack" "Asking isn't the stack; the answer is." "$BODY"
assert_contains_literal "fizzle costs nothing" 'Nothing gets written, nothing gets mourned' "$BODY"
assert_contains_literal "the game survives a fizzle" 'the game is always still in the box' "$BODY"

begin_test "bank-your-riff is the legacy rule"
assert_contains_literal "memory path present" '.craft/riff/notes/' "$BODY"
assert_contains_literal "written at the stack, not after" 'not after, AT it, mid-cheer' "$BODY"
assert_contains_literal "positives only" 'a trophy case, not a confession booth' "$BODY"
assert_contains_literal "only wins live here" 'Only wins live here' "$BODY"
assert_contains_literal "no losing notes exist" 'no such thing as a losing note' "$BODY"
assert_contains_literal "written while hands are stacked" 'while the hands were still stacked' "$BODY"

# --- Riff-first-touch routing (tweak 2026-08-06) ---

SPARK="$PLUGIN_ROOT/skills/creative-spark/SKILL.md"

begin_test "bare undecided directions are riff's first touch"
assert_contains_literal "riff claims the bare undecided direction" 'a bare undecided direction' "$RIFF_CONTENT"
assert_contains_literal "boundary rule stated in riff" 'riff first,' "$RIFF_CONTENT"
assert_file_not_contains "creative-spark no longer claims bare vague ideas" 'vague feature idea without clear direction' "$SPARK"
assert_file_contains "creative-spark signposts riff" 'routes to /craft:riff' "$SPARK"
assert_file_contains "boundary rule stated in creative-spark" 'riff first, options after' "$SPARK"

# --- Orchestration index wiring (Story 25 chunk 2 - still true of the game) ---

INDEX="$PLUGIN_ROOT/reference/orchestration-index.min"
INDEX_CONTENT="$(cat "$INDEX")"

begin_test "index carries the riff self-catch routing row"
assert_contains_literal "routing row present verbatim" "about to send a turn that says a lot at once on an undecided direction (2+ questions the clearest tell; main loop only, never inside another flow's gate)|append ignorable riff offer; on accept → craft:riff" "$INDEX_CONTENT"

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
