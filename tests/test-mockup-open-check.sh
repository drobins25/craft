#!/bin/bash
# test-mockup-open-check.sh - A mockup left open by an earlier session never blocks
# a new one. Only the mockup this conversation is running keeps the new one waiting,
# because its pin listener, browser tab and round tasks cannot be shared.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

SHELL_FILE="$PLUGIN_ROOT/commands/craft-mockup.md"
FUNNEL="$PLUGIN_ROOT/commands/references/mockup-inline.md"
TREE="$PLUGIN_ROOT/docs/decision-tree.md"

STEP2=$(awk '/^### Step 2:/{on=1} /^### Step 3:/{on=0} on' "$SHELL_FILE")

begin_test "the project-wide decline is gone"
assert_not_contains "no one-at-a-time rule" "$STEP2" "One mockup session at a time"
assert_not_contains "no blanket decline" "$STEP2" "DECLINE the new invocation"
assert_file_not_contains "funnel no longer names the single-session guard" "single-session guard" "$FUNNEL"
assert_file_not_contains "decision tree no longer declines on any converging record" "Decline - point at the open record" "$TREE"

begin_test "a mockup left by an earlier session is named, then the new one starts"
assert_contains_literal "left-open mockups never block" "A mockup left open by an earlier session never blocks a new one" "$STEP2"
assert_contains_literal "newest first, with a count of the rest" ", and <m> more" "$STEP2"
assert_contains_literal "continues to the funnel" "then continue to Step 3" "$STEP2"
assert_contains_literal "resume re-anchors from the record" "the funnel's Recovery" "$STEP2"

begin_test "the mockup this conversation is running still keeps a new one waiting"
assert_contains_literal "this-conversation case named" "the mockup this conversation is running" "$STEP2"
assert_contains_literal "offers a fresh session" "start the new mockup in a fresh session" "$STEP2"

begin_test "the check finds the project folder before init"
assert_contains_literal "cold root resolved first" "craft_before_init_root" "$STEP2"

begin_test "funnel and decision tree describe the same check"
assert_file_contains "funnel names the open-mockup check" "run the open-mockup check" "$FUNNEL"
assert_file_contains "decision tree asks about this conversation" "Mockup open in<br/>this conversation?" "$TREE"

finish_tests
