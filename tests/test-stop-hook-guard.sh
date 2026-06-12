#!/bin/bash
# test-stop-hook-guard.sh — Tests for stop-hook-guard.sh
# Validates Stop hook: marker file logic + active story warning

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"

STOP_HOOK_SCRIPT="$SCRIPTS_DIR/stop-hook-guard.sh"

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
SESSION_ID=$(echo "$TEST_DIR" | md5 2>/dev/null | cut -c1-8 || echo "$TEST_DIR" | md5sum 2>/dev/null | cut -c1-8)
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
sed -i '' 's/^CURRENT_CHUNK=.*/CURRENT_CHUNK="0"/' "$TEST_DIR/.craft/cycles/1-test-cycle/.state"

# Clean marker to ensure this is "first time"
SESSION_ID=$(echo "$TEST_DIR" | md5 2>/dev/null | cut -c1-8 || echo "$TEST_DIR" | md5sum 2>/dev/null | cut -c1-8)
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
sed -i '' 's/^CURRENT_CHUNK=.*/CURRENT_CHUNK="0"/' "$TEST_DIR/.craft/cycles/1-test-cycle/.state"

# Create a recent marker
SESSION_ID=$(echo "$TEST_DIR" | md5 2>/dev/null | cut -c1-8 || echo "$TEST_DIR" | md5sum 2>/dev/null | cut -c1-8)
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
SESSION_ID=$(echo "$TEST_DIR" | md5 2>/dev/null | cut -c1-8 || echo "$TEST_DIR" | md5sum 2>/dev/null | cut -c1-8)
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

# --- Summary ---
finish_tests
