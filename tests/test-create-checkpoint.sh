#!/bin/bash
# test-create-checkpoint.sh — Tests for create-checkpoint.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

# --- Test-specific setup ---

setup_test_project() {
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"

  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # Create .craft structure
  mkdir -p .craft/cycles/10-test-cycle/stories
  mkdir -p .craft/checkpoints

  # Create cycle .state
  cat > .craft/cycles/10-test-cycle/.state << 'EOF'
CYCLE_NAME="test-cycle"
CYCLE_STATUS="active"
CURRENT_STORY="login-form"
CURRENT_CHUNK="2"
TOTAL_CHUNKS="4"
LAST_VALIDATION="2026-02-09T15:28:00Z"
LAST_CHECKPOINT=""
EOF

  # Create story file
  cat > .craft/cycles/10-test-cycle/stories/1-login-form.md << 'EOF'
---
title: Login Form
status: active
chunks_total: 4
chunks_complete: 1
current_chunk: 2
updated: 2026-02-09
---
# Login Form Story
EOF

  # Create global state
  cat > .craft/.global-state << 'EOF'
ACTIVE_CYCLE="10-test-cycle"
CURRENT_STORY="login-form"
LAST_ACTIVITY=""
EOF

  # Initial commit
  git add -A
  git commit -q -m "initial"

  echo "$TEST_DIR"
}

# --- Tests ---

echo "=== test-create-checkpoint.sh ==="
echo ""

# Test 1: Basic creation with modified file
begin_test "Basic creation — modified file produces checkpoint YAML"
TEST_DIR=$(setup_test_project)
trap cleanup_test_dir EXIT
cd "$TEST_DIR"

echo "new content" > src_file.txt
RESULT=$("$SCRIPTS_DIR/create-checkpoint.sh" "login-form" 2 ".craft/cycles/10-test-cycle" "$TEST_DIR")
CHECKPOINT_FILE="$RESULT"

assert_file_exists "checkpoint YAML exists" "$CHECKPOINT_FILE"

# Check git_ref matches HEAD (must run git from the temp dir)
EXPECTED_REF=$(cd "$TEST_DIR" && git rev-parse --short HEAD)
ACTUAL_REF=$(grep "^git_ref:" "$CHECKPOINT_FILE" | sed 's/git_ref: *//' | tr -d '"')
assert_eq "git_ref matches HEAD" "$EXPECTED_REF" "$ACTUAL_REF"

# Check story and chunk values
ACTUAL_STORY=$(grep "^story:" "$CHECKPOINT_FILE" | sed 's/story: *//' | tr -d '"')
assert_eq "story name correct" "1-login-form" "$ACTUAL_STORY"

ACTUAL_CHUNK=$(grep "^chunk:" "$CHECKPOINT_FILE" | sed 's/chunk: *//' | tr -d '"')
assert_eq "chunk number correct" "2" "$ACTUAL_CHUNK"

# Check stdout is the path
assert_contains "stdout is checkpoint path" "login-form-chunk-2.yaml" "$RESULT"

cleanup_test_dir
echo ""

# Test 2: Idempotent — no changes still produces YAML
begin_test "Idempotent — no changes still writes YAML with current HEAD"
TEST_DIR=$(setup_test_project)

RESULT=$("$SCRIPTS_DIR/create-checkpoint.sh" "login-form" 1 ".craft/cycles/10-test-cycle" "$TEST_DIR")
EXIT_CODE=$?

assert_eq "exits 0" "0" "$EXIT_CODE"
CHECKPOINT_FILE="$RESULT"
assert_file_exists "YAML still created" "$CHECKPOINT_FILE"

ACTUAL_REF=$(grep "^git_ref:" "$CHECKPOINT_FILE" | sed 's/git_ref: *//' | tr -d '"')
EXPECTED_REF=$(cd "$TEST_DIR" && git rev-parse --short HEAD)
assert_eq "git_ref matches current HEAD" "$EXPECTED_REF" "$ACTUAL_REF"

cleanup_test_dir
echo ""

# Test 3: Overwrites same story+chunk
begin_test "Overwrites same story+chunk — latest ref wins"
TEST_DIR=$(setup_test_project)

# First run
"$SCRIPTS_DIR/create-checkpoint.sh" "login-form" 2 ".craft/cycles/10-test-cycle" "$TEST_DIR" > /dev/null
FIRST_REF=$(cd "$TEST_DIR" && git rev-parse --short HEAD)

# Make a change and run again
cd "$TEST_DIR"
echo "more changes" > another_file.txt
CHECKPOINT_FILE=$("$SCRIPTS_DIR/create-checkpoint.sh" "login-form" 2 ".craft/cycles/10-test-cycle" "$TEST_DIR")
SECOND_REF=$(cd "$TEST_DIR" && git rev-parse --short HEAD)

ACTUAL_REF=$(grep "^git_ref:" "$CHECKPOINT_FILE" | sed 's/git_ref: *//' | tr -d '"')
assert_eq "latest ref wins" "$SECOND_REF" "$ACTUAL_REF"

# Only one YAML file for this story+chunk
FILE_COUNT=$(ls "$TEST_DIR/.craft/checkpoints/"*"login-form-chunk-2"* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "only one YAML file" "1" "$FILE_COUNT"

cleanup_test_dir
echo ""

# Test 4: State accuracy
begin_test "State accuracy — .state values appear in YAML"
TEST_DIR=$(setup_test_project)
cd "$TEST_DIR"

echo "trigger commit" > trigger.txt
CHECKPOINT_FILE=$("$SCRIPTS_DIR/create-checkpoint.sh" "login-form" 2 ".craft/cycles/10-test-cycle" "$TEST_DIR")

ACTUAL_CYCLE_STATUS=$(grep "^state_CYCLE_STATUS:" "$CHECKPOINT_FILE" | sed 's/state_CYCLE_STATUS: *//' | tr -d '"')
assert_eq "state_CYCLE_STATUS captured" "active" "$ACTUAL_CYCLE_STATUS"

ACTUAL_CURRENT_STORY=$(grep "^state_CURRENT_STORY:" "$CHECKPOINT_FILE" | sed 's/state_CURRENT_STORY: *//' | tr -d '"')
assert_eq "state_CURRENT_STORY captured" "login-form" "$ACTUAL_CURRENT_STORY"

ACTUAL_TOTAL_CHUNKS=$(grep "^state_TOTAL_CHUNKS:" "$CHECKPOINT_FILE" | sed 's/state_TOTAL_CHUNKS: *//' | tr -d '"')
assert_eq "state_TOTAL_CHUNKS captured" "4" "$ACTUAL_TOTAL_CHUNKS"

ACTUAL_STORY_STATUS=$(grep "^story_status:" "$CHECKPOINT_FILE" | sed 's/story_status: *//' | tr -d '"')
assert_eq "story_status captured" "active" "$ACTUAL_STORY_STATUS"

ACTUAL_CYCLE=$(grep "^cycle:" "$CHECKPOINT_FILE" | sed 's/cycle: *//' | tr -d '"')
assert_eq "cycle name captured" "10-test-cycle" "$ACTUAL_CYCLE"

cleanup_test_dir
echo ""

# --- Summary ---
finish_tests
