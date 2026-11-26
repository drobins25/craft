#!/bin/bash
# test-legacy-write-gate-cleanup.sh - TEMPORARY, REMOVE ON 2027-01-01.
# Delete this file together with the "TEMPORARY legacy write gate cleanup" block
# in hooks/scripts/update-global-state.sh. Nothing else depends on either.
#
# Craft 2.20.3 and earlier left a CRAFT_WRITE_ENABLED line in .craft/.global-state.
# Setting any other state key must drop that line and change nothing else.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

UPDATE_GLOBAL_STATE_SCRIPT="$SCRIPTS_DIR/update-global-state.sh"

echo "=== test-legacy-write-gate-cleanup.sh ==="
echo ""

begin_test "setting a key drops the old CRAFT_WRITE_ENABLED line and nothing else"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"
printf 'ACTIVE_CYCLE="c"\nCRAFT_WRITE_ENABLED="true"\nCURRENT_STORY=""\nRUN_MODE=""\n' > "$TEST_DIR/.craft/.global-state"

bash "$UPDATE_GLOBAL_STATE_SCRIPT" RUN_MODE "auto" "$TEST_DIR"

WANT=$(printf 'ACTIVE_CYCLE="c"\nCURRENT_STORY=""\nRUN_MODE="auto"')
assert_eq "only the old line is gone and the key is set" "$WANT" "$(cat "$TEST_DIR/.craft/.global-state")"
assert_file_not_exists "no backup file left" "$TEST_DIR/.craft/.global-state.bak"

rm -rf "$TEST_DIR"
echo ""

begin_test "an empty old line is dropped too"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"
printf 'ACTIVE_CYCLE="c"\nCRAFT_WRITE_ENABLED=""\nCURRENT_STORY=""\n' > "$TEST_DIR/.craft/.global-state"

bash "$UPDATE_GLOBAL_STATE_SCRIPT" LAST_ACTIVITY "NOW" "$TEST_DIR"

assert_file_not_contains "the old line is gone" "CRAFT_WRITE_ENABLED" "$TEST_DIR/.craft/.global-state"
assert_file_contains "the other lines stay" 'CURRENT_STORY=""' "$TEST_DIR/.craft/.global-state"

rm -rf "$TEST_DIR"
echo ""

finish_tests
