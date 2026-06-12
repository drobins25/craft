#!/bin/bash
# test-session-start.sh — Tests for session-start.sh
# Validates session bootstrap resolves correct project root
#
# Key behavior: "nearest wins" — session-start sources find-project-root.sh
# which walks up from CWD and finds the nearest .craft/.global-state.
# In a monorepo with multiple .craft/ dirs, each sub-project owns its own.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-shadow.sh"
source "$SCRIPT_DIR/fixtures/minimal.sh"

SESSION_SCRIPT="$SCRIPTS_DIR/session-start.sh"

# --- Tests ---

echo "=== test-session-start.sh ==="
echo ""

# Test 1: Nearest wins — session-start from child resolves to child
# When CWD is inside a sub-project with its own .craft/, session-start
# should resolve to that sub-project (nearest .craft/).
begin_test "Nearest wins — session-start from child resolves to child"

TEST_DIR=$(create_craft_with_shadow)
trap cleanup_test_dir EXIT
PARENT_DIR="$TEST_DIR/project"
CHILD_DIR="$TEST_DIR/project/apps/web"

# Create a fake CLAUDE_ENV_FILE to capture what session-start persists
ENV_FILE=$(mktemp)

# Run session-start.sh from the child directory
# Nearest wins: should resolve to CHILD, not PARENT
set +e
RESULT=$(cd "$CHILD_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" 2>/dev/null)
SESSION_EXIT=$?
set -e

# Check what CRAFT_PROJECT_ROOT was persisted to the env file
if [ -f "$ENV_FILE" ] && [ -s "$ENV_FILE" ]; then
  PERSISTED_ROOT=$(grep "CRAFT_PROJECT_ROOT=" "$ENV_FILE" | head -1 | sed 's/.*CRAFT_PROJECT_ROOT="//' | sed 's/".*//')

  if [ -z "$PERSISTED_ROOT" ]; then
    echo "  FAIL: CRAFT_PROJECT_ROOT not written to CLAUDE_ENV_FILE"
    echo "    env file contents: $(cat "$ENV_FILE")"
    FAIL=$((FAIL + 1))
  elif [ "$PERSISTED_ROOT" = "$CHILD_DIR" ]; then
    echo "  PASS: session-start resolved to nearest (child) project root"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: session-start did not resolve to nearest .craft/"
    echo "    expected: $CHILD_DIR"
    echo "    actual:   $PERSISTED_ROOT"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  FAIL: CLAUDE_ENV_FILE is empty — session-start may have exited early"
  echo "    exit code: $SESSION_EXIT"
  FAIL=$((FAIL + 1))
fi

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# Test 2: Happy path — single .craft/ resolves correctly
begin_test "Happy path — single .craft/ resolves and persists correctly"

TEST_DIR=$(create_minimal_craft)
ENV_FILE=$(mktemp)

# Add enough state for session-start to produce output
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
EOF

set +e
RESULT=$(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" 2>/dev/null)
SESSION_EXIT=$?
set -e

assert_eq "exits 0" "0" "$SESSION_EXIT"

# Check the env file has CRAFT_PROJECT_ROOT
if [ -f "$ENV_FILE" ] && grep -q "CRAFT_PROJECT_ROOT" "$ENV_FILE"; then
  PERSISTED_ROOT=$(grep "CRAFT_PROJECT_ROOT=" "$ENV_FILE" | head -1 | sed 's/.*CRAFT_PROJECT_ROOT="//' | sed 's/".*//')
  assert_eq "persisted root matches" "$TEST_DIR" "$PERSISTED_ROOT"
else
  echo "  FAIL: CRAFT_PROJECT_ROOT not found in CLAUDE_ENV_FILE"
  FAIL=$((FAIL + 1))
fi

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# Test 3: No .craft/ — exits cleanly without writing env
begin_test "No .craft/ — exits 0 without writing to env file"

TEST_DIR=$(mktemp -d)
ENV_FILE=$(mktemp)

set +e
(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" 2>/dev/null)
SESSION_EXIT=$?
set -e

assert_eq "exits 0" "0" "$SESSION_EXIT"

# CLAUDE_ENV_FILE should be empty (no CRAFT_PROJECT_ROOT to persist)
if [ -s "$ENV_FILE" ] && grep -q "CRAFT_PROJECT_ROOT" "$ENV_FILE"; then
  echo "  FAIL: CRAFT_PROJECT_ROOT written when no .craft/ exists"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: no CRAFT_PROJECT_ROOT written"
  PASS=$((PASS + 1))
fi

rm -f "$ENV_FILE"
rm -rf "$TEST_DIR"
echo ""

# Test 4: Session output includes cycle info when active cycle exists
begin_test "Output includes active cycle context"

TEST_DIR=$(create_minimal_craft)
ENV_FILE=$(mktemp)

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
EOF

# Create the cycle for session-start to report on
mkdir -p "$TEST_DIR/.craft/cycles/1-test-cycle/stories"
cat > "$TEST_DIR/.craft/cycles/1-test-cycle/cycle.yaml" << 'EOF'
title: "Test Cycle"
status: active
EOF
cat > "$TEST_DIR/.craft/cycles/1-test-cycle/.state" << 'EOF'
CYCLE_NAME="test-cycle"
CYCLE_STATUS="active"
CURRENT_STORY=""
CURRENT_CHUNK="0"
TOTAL_CHUNKS="0"
EOF

set +e
RESULT=$(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" 2>/dev/null)
set -e

# Session output should mention the active cycle
assert_contains "output mentions Craft" "Craft:" "$RESULT"
assert_contains "output mentions active cycle" "Test Cycle" "$RESULT"

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# Test 5: Stale commit-manifest from a crashed session is removed
begin_test "Stale .commit-manifest removed at session start"

TEST_DIR=$(create_minimal_craft)
ENV_FILE=$(mktemp)

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
EOF
printf 'story: dead-session-story\nsome/file.txt\n' > "$TEST_DIR/.craft/.commit-manifest"

set +e
(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" >/dev/null 2>&1)
SESSION_EXIT=$?
set -e

assert_eq "exits 0" "0" "$SESSION_EXIT"
if [ -f "$TEST_DIR/.craft/.commit-manifest" ]; then
  echo "  FAIL: stale .commit-manifest survived session start"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: stale .commit-manifest removed"
  PASS=$((PASS + 1))
fi

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# --- Summary ---
finish_tests
