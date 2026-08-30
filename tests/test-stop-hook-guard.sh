#!/bin/bash
# test-stop-hook-guard.sh — Tests for stop-hook-guard.sh
# Validates Stop hook: marker file logic + active story warning

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"

STOP_HOOK_SCRIPT="$SCRIPTS_DIR/stop-hook-guard.sh"

# Session id for a test dir, matching stop-hook-guard.sh:19's computation for
# the same input (echo keeps the trailing newline the hook's hash includes).
# Linux-tool-first with an empty-check fallback: a piped `md5` before `||` can
# never reach the fallback (a pipeline's exit status is its last command's),
# which silently broke this file on GNU userland.
session_id_for_dir() {
  local id
  id=$(echo "$1" | md5sum 2>/dev/null | cut -c1-8)
  if [ -z "$id" ]; then
    id=$(echo "$1" | md5 2>/dev/null | cut -c1-8)
  fi
  printf '%s' "$id"
}

# --- Tests ---

echo "=== test-stop-hook-guard.sh ==="
echo ""

# Test 1: No active story — exits 0 quietly (creates marker)
begin_test "No active story — exits 0 (creates marker)"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")
trap cleanup_test_dir EXIT

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY=""
EOF

# Clean up any existing marker for this test dir
SESSION_ID=$(session_id_for_dir "$TEST_DIR")
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"

cleanup_test_dir
echo ""

# Test 2: Active story — warns about persisting
begin_test "Active story — warns about persisting"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY="test-story"
EOF

# Zero CURRENT_CHUNK so the guard reaches the Layer 2 persistence path this test asserts
# (the fixture's CURRENT_CHUNK="1" triggers the Layer 1 mid-implementation block instead)
sed -i.bak 's/^CURRENT_CHUNK=.*/CURRENT_CHUNK="0"/' "$TEST_DIR/.craft/cycles/1-test-cycle/.state"
rm -f "$TEST_DIR/.craft/cycles/1-test-cycle/.state.bak"

# Clean marker to ensure this is "first time"
SESSION_ID=$(session_id_for_dir "$TEST_DIR")
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "warns about active story" "test-story" "$RESULT"
assert_contains "mentions continue" "continue" "$RESULT"

cleanup_test_dir
echo ""

# Test 3: stop_hook_active=true — exits 0 immediately (loop prevention)
begin_test "stop_hook_active=true — exits 0 immediately"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY="test-story"
EOF

JSON='{"stop_hook_active": true}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0 immediately" "0" "$EXIT_CODE"
# Should NOT warn when stop_hook_active is true
assert_not_contains "no warning when stop_hook_active" "test-story" "$RESULT"

cleanup_test_dir
echo ""

# Test 4: Recent marker — allows stop without warning
begin_test "Recent marker — allows stop (already warned)"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY="test-story"
EOF

# Zero CURRENT_CHUNK so the guard reaches the Layer 2 marker-suppression path this test asserts
sed -i.bak 's/^CURRENT_CHUNK=.*/CURRENT_CHUNK="0"/' "$TEST_DIR/.craft/cycles/1-test-cycle/.state"
rm -f "$TEST_DIR/.craft/cycles/1-test-cycle/.state.bak"

# Create a recent marker
SESSION_ID=$(session_id_for_dir "$TEST_DIR")
touch "/tmp/craft-stop-suggested-${SESSION_ID}"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
# Should NOT warn again — marker is recent
assert_eq "no output (already warned)" "" "$RESULT"

# Clean up marker
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"

cleanup_test_dir
echo ""

# Test 5: No .craft/ — exits 0 quietly
begin_test "No .craft/ — exits 0 quietly"

TEST_DIR=$(mktemp -d)

# Clean marker
SESSION_ID=$(session_id_for_dir "$TEST_DIR")
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && unset PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0 with no .craft/" "0" "$EXIT_CODE"

rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"
rm -rf "$TEST_DIR"
echo ""

# Test 6: Gate open, no story — adhoc rail stamps, bypassing warn-once marker
begin_test "Gate open, no story — adhoc rail stamps every stop"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
CRAFT_WRITE_ENABLED="true"
EOF
touch "$TEST_DIR/.craft/.active-fix"

# Recent marker present — the rail must print anyway
SESSION_ID=$(session_id_for_dir "$TEST_DIR")
touch "/tmp/craft-stop-suggested-${SESSION_ID}"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "rail line prints despite recent marker" "in flight" "$RESULT"
assert_contains "carries the gate flag" "⚠ write gate open" "$RESULT"

rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"
rm -rf "$TEST_DIR"
echo ""

# Test 7: Gate open with a tweak record born in the gate window — flavor word, no slug
begin_test "Gate open — tweak flavor detected from record folder"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft/tweaks"
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
CRAFT_WRITE_ENABLED="true"
EOF
# Marker predates the record so the record is inside the gate window
touch -t 202601010000 "$TEST_DIR/.craft/.active-fix"
echo "x" > "$TEST_DIR/.craft/tweaks/tweak-sample.md"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "names the flavor" "Tweak in flight" "$RESULT"
assert_not_contains "never names the record" "tweak-sample" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 8: Idle story with the gate still open — set-down line carries the warning
begin_test "Idle story, gate open — set-down line warns"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY="test-story"
CRAFT_WRITE_ENABLED="true"
EOF
sed -i.bak 's/^CURRENT_CHUNK=.*/CURRENT_CHUNK="0"/' "$TEST_DIR/.craft/cycles/1-test-cycle/.state"
rm -f "$TEST_DIR/.craft/cycles/1-test-cycle/.state.bak"

SESSION_ID=$(session_id_for_dir "$TEST_DIR")
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "set-down still names the story" "test-story" "$RESULT"
assert_contains "carries the forgotten-gate warning" "⚠ write gate open" "$RESULT"

rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"
cleanup_test_dir
echo ""

# Test 9: Gate closed, no story — stays silent (no rail noise)
begin_test "Gate closed, no story — silent"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
CRAFT_WRITE_ENABLED=""
EOF

SESSION_ID=$(session_id_for_dir "$TEST_DIR")
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_eq "no output with gate closed" "" "$RESULT"

rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"
rm -rf "$TEST_DIR"
echo ""

# Test 10: Gate open, no story, no marker — unclaimed, never "in flight"
begin_test "Gate open with no marker — unclaimed"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
CRAFT_WRITE_ENABLED="true"
EOF

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "names the unclaimed gate" "write gate open · unclaimed" "$RESULT"
assert_not_contains "claims no work" "in flight" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# --- Summary ---
finish_tests
