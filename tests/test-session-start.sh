#!/bin/bash
# test-session-start.sh — Tests for session-start.sh
# Validates session bootstrap resolves correct project root
#
# Key behavior: "nearest wins" — session-start sources find-workshop.sh
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

# Helper: write N loved tweak records into a test project
seed_loved_tweaks() {
  local root="$1" n="$2" i
  mkdir -p "$root/.craft/tweaks"
  for i in $(seq 1 "$n"); do
    printf -- '---\nname: tweak-%s\nstatus: accepted\ncreated: 2026-07-%02d\ntaste: loved\n---\nbody\n' "$i" "$i" > "$root/.craft/tweaks/tweak-$i.md"
  done
}

# Test 6: ripe line appears when enabled and count >= effective threshold (default 3)
begin_test "ripe >=N line appears when enabled and count >= effective threshold"

TEST_DIR=$(create_minimal_craft)
ENV_FILE=$(mktemp)
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
EOF
seed_loved_tweaks "$TEST_DIR" 3

set +e
RESULT=$(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" 2>/dev/null)
set -e

assert_contains "ripe line present at 3 loved records" "Taste: >=" "$RESULT"

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# Test 7: no ripe line when taste_pass_enabled is false
begin_test "no ripe line when taste_pass_enabled is false"

TEST_DIR=$(create_minimal_craft)
ENV_FILE=$(mktemp)
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
EOF
seed_loved_tweaks "$TEST_DIR" 3
printf 'taste_pass_enabled: false\n' > "$TEST_DIR/.craft/settings.yaml"

set +e
RESULT=$(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" 2>/dev/null)
set -e

assert_not_contains "no ripe line when disabled" "Taste: >=" "$RESULT"

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# Test 8: no ripe line when count is below the effective threshold
begin_test "no ripe line when count < effective threshold"

TEST_DIR=$(create_minimal_craft)
ENV_FILE=$(mktemp)
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
EOF
seed_loved_tweaks "$TEST_DIR" 2

set +e
RESULT=$(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" 2>/dev/null)
set -e

assert_not_contains "no ripe line at 2 < 3" "Taste: >=" "$RESULT"

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# Test 9: .taste-pass-state survives a session-start run (durable, off cleanup)
begin_test ".taste-pass-state survives a session-start run"

TEST_DIR=$(create_minimal_craft)
ENV_FILE=$(mktemp)
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
EOF
seed_loved_tweaks "$TEST_DIR" 3
printf 'last_asked: 2026-01-01\nsnooze_offset: 0\n' > "$TEST_DIR/.craft/tweaks/.taste-pass-state"

set +e
(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" >/dev/null 2>&1)
set -e

assert_file_exists ".taste-pass-state not cleaned up" "$TEST_DIR/.craft/tweaks/.taste-pass-state"

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# Test 10: the taste offer never enters the every-prompt routing block
begin_test "taste offer stays out of inject-craft-context.sh (every-prompt block)"

assert_file_not_contains "no taste_pass logic in the routing block" "taste_pass" "$SCRIPTS_DIR/inject-craft-context.sh"
assert_file_not_contains "no ripe line in the routing block" "Taste:" "$SCRIPTS_DIR/inject-craft-context.sh"

echo ""

# Helper: read a key's value back out of a project's .global-state
read_state_key() {
  local key="$1" root="$2"
  grep "^${key}=" "$root/.craft/.global-state" 2>/dev/null | sed "s/${key}=\"\(.*\)\"/\1/"
}

# Test 11: stale write gate with no holders is cleared at session start
begin_test "stale write gate with no holders is cleared at session start"

TEST_DIR=$(create_minimal_craft)
ENV_FILE=$(mktemp)

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
CRAFT_WRITE_ENABLED="true"
CURRENT_WORKFLOW_SESSION=""
EOF

set +e
(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" >/dev/null 2>&1)
SESSION_EXIT=$?
set -e

assert_eq "exits 0" "0" "$SESSION_EXIT"
GATE_VALUE=$(read_state_key CRAFT_WRITE_ENABLED "$TEST_DIR")
assert_eq "stale gate cleared" "" "$GATE_VALUE"

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# Test 12: write gate survives when a story is in progress
begin_test "write gate survives when a story is in progress"

TEST_DIR=$(create_minimal_craft)
ENV_FILE=$(mktemp)

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY="some-story"
PLANNING_CYCLE=""
LAST_ACTIVITY=""
CRAFT_WRITE_ENABLED="true"
CURRENT_WORKFLOW_SESSION=""
EOF

set +e
(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" >/dev/null 2>&1)
SESSION_EXIT=$?
set -e

assert_eq "exits 0" "0" "$SESSION_EXIT"
GATE_VALUE=$(read_state_key CRAFT_WRITE_ENABLED "$TEST_DIR")
assert_eq "gate preserved with story in progress" "true" "$GATE_VALUE"

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# Test 13: write gate survives when a live workflow session holds it
begin_test "write gate survives when a live workflow session holds it"

TEST_DIR=$(create_minimal_craft)
ENV_FILE=$(mktemp)

WF_DIR="$TEST_DIR/.craft/workflows/wf/sessions/s"
mkdir -p "$WF_DIR"
cat > "$WF_DIR/session.md" << 'EOF'
---
status: active
---
EOF

cat > "$TEST_DIR/.craft/.global-state" << EOF
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
CRAFT_WRITE_ENABLED="true"
CURRENT_WORKFLOW_SESSION="$WF_DIR"
EOF

set +e
(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" >/dev/null 2>&1)
SESSION_EXIT=$?
set -e

assert_eq "exits 0" "0" "$SESSION_EXIT"
GATE_VALUE=$(read_state_key CRAFT_WRITE_ENABLED "$TEST_DIR")
assert_eq "gate preserved with live workflow session" "true" "$GATE_VALUE"

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# Test 14: stale workflow session clears both the session key and the gate
begin_test "stale workflow session clears both the session key and the gate"

TEST_DIR=$(create_minimal_craft)
ENV_FILE=$(mktemp)

WF_DIR="$TEST_DIR/.craft/workflows/wf/sessions/s"
mkdir -p "$WF_DIR"
cat > "$WF_DIR/session.md" << 'EOF'
---
status: complete
---
EOF

cat > "$TEST_DIR/.craft/.global-state" << EOF
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
CRAFT_WRITE_ENABLED="true"
CURRENT_WORKFLOW_SESSION="$WF_DIR"
EOF

set +e
(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" >/dev/null 2>&1)
SESSION_EXIT=$?
set -e

assert_eq "exits 0" "0" "$SESSION_EXIT"
WF_VALUE=$(read_state_key CURRENT_WORKFLOW_SESSION "$TEST_DIR")
assert_eq "stale workflow session cleared" "" "$WF_VALUE"
GATE_VALUE=$(read_state_key CRAFT_WRITE_ENABLED "$TEST_DIR")
assert_eq "gate cleared after stale workflow clear" "" "$GATE_VALUE"

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# Test 15: a keyless state file never gains a CRAFT_WRITE_ENABLED key
begin_test "a keyless state file never gains a CRAFT_WRITE_ENABLED key"

TEST_DIR=$(create_minimal_craft)
ENV_FILE=$(mktemp)

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
EOF

set +e
(cd "$TEST_DIR" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SESSION_SCRIPT" >/dev/null 2>&1)
SESSION_EXIT=$?
KEY_COUNT=$(grep -c "^CRAFT_WRITE_ENABLED=" "$TEST_DIR/.craft/.global-state")
set -e

assert_eq "exits 0" "0" "$SESSION_EXIT"
assert_eq "key not appended to a keyless state file" "0" "$KEY_COUNT"

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# --- Summary ---
finish_tests
