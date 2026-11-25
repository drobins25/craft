#!/bin/bash
# test-start-story.sh — Tests for start-story.sh
# Validates story activation: status transition, global/cycle state updates

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"
source "$SCRIPT_DIR/fixtures/with-cycle.sh"

START_SCRIPT="$SCRIPTS_DIR/start-story.sh"

# --- Tests ---

echo "=== test-start-story.sh ==="
echo ""

# Test 1: Happy path — ready story becomes active, state updated
begin_test "Happy path — ready story transitions to active"

TEST_DIR=$(create_craft_with_story "test-cycle" "login-form" "Login Form" "3" "ready")
trap cleanup_test_dir EXIT
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-login-form.md"
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"

# Reset state so start-story sets it fresh
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
EOF
cat > "$CYCLE_DIR/.state" << 'EOF'
CYCLE_NAME="test-cycle"
CYCLE_STATUS="active"
CURRENT_STORY=""
CURRENT_CHUNK="0"
TOTAL_CHUNKS="0"
LAST_VALIDATION=""
LAST_CHECKPOINT=""
EOF

set +e
RESULT=$(cd "$TEST_DIR" && bash "$START_SCRIPT" "$STORY_FILE" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"

# Story frontmatter should now say status: active
STATUS=$(grep "^status:" "$STORY_FILE" | sed 's/status: *//')
assert_eq "story status is active" "active" "$STATUS"

# Global state should have CURRENT_STORY set
source "$TEST_DIR/.craft/.global-state"
assert_eq "global CURRENT_STORY set" "1-login-form" "$CURRENT_STORY"

# Cycle state should have CURRENT_STORY, CURRENT_CHUNK=1, TOTAL_CHUNKS=3
source "$CYCLE_DIR/.state"
assert_eq "cycle CURRENT_STORY set" "1-login-form" "$CURRENT_STORY"
assert_eq "cycle CURRENT_CHUNK is 1" "1" "$CURRENT_CHUNK"
assert_eq "cycle TOTAL_CHUNKS is 3" "3" "$TOTAL_CHUNKS"

cleanup_test_dir
echo ""

# Test 2: The session's gate file holds the story's canonical path
begin_test "Writes this session's gate file holding the story's canonical path"

TEST_DIR=$(create_craft_with_story "test-cycle" "signup" "Signup" "2" "ready")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-signup.md"
CANON_STORY="$(cd "$(dirname "$STORY_FILE")" && pwd -P)/1-signup.md"

set +e
(cd "$TEST_DIR" && bash "$START_SCRIPT" "$STORY_FILE" 2>/dev/null)
set -e

assert_file_exists "gate file for the session" "$TEST_DIR/.craft/.gate/craft-test-session"
assert_eq "gate file holds the story path" "$CANON_STORY" "$(cat "$TEST_DIR/.craft/.gate/craft-test-session")"
assert_file_not_contains "no shared write flag in the state file" "CRAFT_WRITE_ENABLED" "$TEST_DIR/.craft/.global-state"

cleanup_test_dir
echo ""

# Test 2b: An unusable session id stops the start before anything changes
begin_test "No session id - stops with the gate message and changes nothing"

TEST_DIR=$(create_craft_with_story "test-cycle" "signup" "Signup" "2" "ready")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-signup.md"
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"
STATE_BEFORE=$(cat "$CYCLE_DIR/.state")
GLOBAL_BEFORE=$(cat "$TEST_DIR/.craft/.global-state")

set +e
ERR=$(cd "$TEST_DIR" && env -u CLAUDE_CODE_SESSION_ID bash "$START_SCRIPT" "$STORY_FILE" 2>&1 >/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 1" "1" "$EXIT_CODE"
assert_contains "names the gate script's message" "write-gate: CLAUDE_CODE_SESSION_ID is empty or not a session id - the gate was not opened" "$ERR"
assert_eq "story stays ready" "ready" "$(grep '^status:' "$STORY_FILE" | sed 's/status: *//')"
assert_eq "cycle state unchanged" "$STATE_BEFORE" "$(cat "$CYCLE_DIR/.state")"
assert_eq "global state unchanged" "$GLOBAL_BEFORE" "$(cat "$TEST_DIR/.craft/.global-state")"
assert_dir_not_exists "no gate folder" "$TEST_DIR/.craft/.gate"

cleanup_test_dir
echo ""

# Test 2c: A failure after the id check leaves no gate file and keeps a held gate
begin_test "Later failure leaves no gate file and a held gate as it was"

TEST_DIR=$(create_craft_with_story "test-cycle" "signup" "Signup" "2" "ready")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-signup.md"
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"
rm -f "$CYCLE_DIR/.state"
mkdir "$CYCLE_DIR/.state"

set +e
(cd "$TEST_DIR" && bash "$START_SCRIPT" "$STORY_FILE" >/dev/null 2>&1)
EXIT_CODE=$?
set -e
assert_not_eq "start fails when the cycle state cannot be written" "0" "$EXIT_CODE"
assert_file_not_exists "no gate file" "$TEST_DIR/.craft/.gate/craft-test-session"

mkdir -p "$TEST_DIR/.craft/.gate"
printf 'workflow /some/session\n' > "$TEST_DIR/.craft/.gate/craft-test-session"
HELD_BEFORE=$(cat "$TEST_DIR/.craft/.gate/craft-test-session")
set +e
(cd "$TEST_DIR" && bash "$START_SCRIPT" "$STORY_FILE" >/dev/null 2>&1)
set -e
assert_eq "held gate is byte-identical" "$HELD_BEFORE" "$(cat "$TEST_DIR/.craft/.gate/craft-test-session")"

cleanup_test_dir
echo ""

# Test 2d: Starting over a fix's gate keeps the fix on line 2; completing gives it back
begin_test "Start over an adhoc gate keeps it on line 2; the write hook allows after each step"

TEST_DIR=$(create_craft_with_story "test-cycle" "signup" "Signup" "2" "ready")
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-signup.md"
mkdir -p "$TEST_DIR/.craft/.gate"
printf 'adhoc %s/.craft/fixes/fix-x.md\n' "$TEST_DIR" > "$TEST_DIR/.craft/.gate/craft-test-session"

hook_allows() {
  local json out
  json="{\"session_id\":\"${1:-craft-test-session}\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_DIR/src/app.ts\"},\"cwd\":\"$TEST_DIR\"}"
  out=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && python3 "$SCRIPTS_DIR/check-write-permission.py" <<< "$json" 2>/dev/null || true)
  case "$out" in *deny*) echo denied ;; *) echo allowed ;; esac
}

set +e
(cd "$TEST_DIR" && bash "$START_SCRIPT" "$STORY_FILE" >/dev/null 2>&1)
set -e
assert_eq "line 1 is the story" "$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-signup.md" "$(sed -n 1p "$TEST_DIR/.craft/.gate/craft-test-session")"
assert_eq "line 2 keeps the fix" "adhoc $TEST_DIR/.craft/fixes/fix-x.md" "$(sed -n 2p "$TEST_DIR/.craft/.gate/craft-test-session")"
assert_eq "write allowed while the story builds" "allowed" "$(hook_allows)"
assert_eq "another session is denied while the story builds" "denied" "$(hook_allows craft-other-session)"

set +e
(cd "$TEST_DIR" && bash "$SCRIPTS_DIR/complete-story.sh" "$STORY_FILE" >/dev/null 2>&1)
set -e
assert_eq "the fix holds the gate again" "adhoc $TEST_DIR/.craft/fixes/fix-x.md" "$(cat "$TEST_DIR/.craft/.gate/craft-test-session")"
assert_eq "write allowed after the story ends" "allowed" "$(hook_allows)"
assert_eq "another session is denied after the story ends" "denied" "$(hook_allows craft-other-session)"

cleanup_test_dir
echo ""

# Test 3: Missing file — exits 1
begin_test "Missing file — exits 1"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")

set +e
RESULT=$(cd "$TEST_DIR" && bash "$START_SCRIPT" "$TEST_DIR/.craft/cycles/1-test-cycle/stories/nonexistent.md" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 1 for missing file" "1" "$EXIT_CODE"

cleanup_test_dir
echo ""

# Test 4: No arguments — exits 1
begin_test "No arguments — exits 1 with usage"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")

set +e
RESULT=$(cd "$TEST_DIR" && bash "$START_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 1 with no args" "1" "$EXIT_CODE"

cleanup_test_dir
echo ""

# Test 5: Story with chunks_total=0 — still starts
begin_test "Story with chunks_total=0 — starts with 0 chunks"

TEST_DIR=$(create_craft_with_story "test-cycle" "no-chunks" "No Chunks" "0" "ready")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-no-chunks.md"
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"

set +e
(cd "$TEST_DIR" && bash "$START_SCRIPT" "$STORY_FILE" 2>/dev/null)
set -e

source "$CYCLE_DIR/.state"
assert_eq "TOTAL_CHUNKS is 0" "0" "$TOTAL_CHUNKS"

cleanup_test_dir
echo ""

# --- Summary ---
finish_tests
