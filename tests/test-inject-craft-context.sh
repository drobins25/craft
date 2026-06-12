#!/bin/bash
# test-inject-craft-context.sh — Tests for inject-craft-context.sh
# Validates UserPromptSubmit hook: context string generation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/minimal.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"
source "$SCRIPT_DIR/fixtures/with-cycle.sh"

INJECT_CONTEXT_SCRIPT="$SCRIPTS_DIR/inject-craft-context.sh"

# --- Tests ---

echo "=== test-inject-craft-context.sh ==="
echo ""

# Test 1: Active story — shows cycle + story + chunk
begin_test "Active story — shows cycle, story, chunk"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")
trap cleanup_test_dir EXIT

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY="test-story"
PLANNING_CYCLE=""
EOF

# Create cycle.yaml for title lookup
mkdir -p "$TEST_DIR/.craft/cycles/1-test-cycle"
echo 'title: "Test Cycle"' > "$TEST_DIR/.craft/cycles/1-test-cycle/cycle.yaml"

# Set chunk progress
cat > "$TEST_DIR/.craft/cycles/1-test-cycle/.state" << 'EOF'
CYCLE_NAME="test-cycle"
CYCLE_STATUS="active"
CURRENT_STORY="test-story"
CURRENT_CHUNK="2"
TOTAL_CHUNKS="3"
EOF

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$INJECT_CONTEXT_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "shows cycle name" "Test Cycle" "$RESULT"
assert_contains "shows story name" "test-story" "$RESULT"
assert_contains "shows chunk progress" "2/3" "$RESULT"

cleanup_test_dir
echo ""

# Test 2: Planning cycle — shows planning context
begin_test "Planning cycle — shows planning context"

TEST_DIR=$(create_craft_with_cycle "plan-cycle" "Plan Cycle" "1")

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE="1-plan-cycle"
EOF

echo 'title: "Plan Cycle"' > "$TEST_DIR/.craft/cycles/1-plan-cycle/cycle.yaml"

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$INJECT_CONTEXT_SCRIPT" 2>/dev/null)
set -e

assert_contains "shows PLANNING" "PLANNING" "$RESULT"
assert_contains "shows cycle name" "Plan Cycle" "$RESULT"

cleanup_test_dir
echo ""

# Test 3: No .craft/ — exits 0, no output
begin_test "No .craft/ — exits 0, no output"

TEST_DIR=$(mktemp -d)

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && unset PROJECT_ROOT && bash "$INJECT_CONTEXT_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_eq "no output" "" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 4: Active cycle, no story — shows cycle only
begin_test "Active cycle, no story — shows cycle only"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY=""
PLANNING_CYCLE=""
EOF

echo 'title: "Test Cycle"' > "$TEST_DIR/.craft/cycles/1-test-cycle/cycle.yaml"

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$INJECT_CONTEXT_SCRIPT" 2>/dev/null)
set -e

# Check just the breadcrumb line (first line), not the full output (which includes orchestration index)
BREADCRUMB=$(echo "$RESULT" | head -1)
assert_contains "shows cycle name" "Test Cycle" "$BREADCRUMB"
assert_not_contains "no story shown" "Story" "$BREADCRUMB"

cleanup_test_dir
echo ""

# Test 5: No active cycle, stories in backlog — shows backlog count
begin_test "No active cycle, backlog — shows backlog count"

TEST_DIR=$(create_minimal_craft)
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
EOF

# Create backlog stories
mkdir -p "$TEST_DIR/.craft/backlog"
echo "---" > "$TEST_DIR/.craft/backlog/story-1.md"
echo "---" > "$TEST_DIR/.craft/backlog/story-2.md"

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$INJECT_CONTEXT_SCRIPT" 2>/dev/null)
set -e

assert_contains "shows backlog count" "2" "$RESULT"
assert_contains "mentions backlog" "backlog" "$RESULT"

cleanup_test_dir
echo ""

# Test 6: Always exits 0
begin_test "Always exits 0"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"
# Broken state — no .global-state

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$INJECT_CONTEXT_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0 even with broken state" "0" "$EXIT_CODE"

rm -rf "$TEST_DIR"
echo ""

# Test 7: Orchestration index — present when .craft/ exists
begin_test "Orchestration index — present when .craft/ exists"

TEST_DIR=$(create_craft_with_cycle "idx-cycle" "Index Cycle" "1")

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-idx-cycle"
CURRENT_STORY=""
PLANNING_CYCLE=""
EOF

echo 'title: "Index Cycle"' > "$TEST_DIR/.craft/cycles/1-idx-cycle/cycle.yaml"

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$INJECT_CONTEXT_SCRIPT" 2>/dev/null)
set -e

assert_contains "has routing section" "=ROUTING" "$RESULT"
assert_contains "has rules section" "=RULES" "$RESULT"
assert_contains "has chains section" "=CHAINS" "$RESULT"
assert_contains "has version line" "v1|craft-orchestration-index" "$RESULT"

cleanup_test_dir
echo ""

# Test 8: Orchestration index — absent when no .craft/
begin_test "Orchestration index — absent when no .craft/"

TEST_DIR=$(mktemp -d)

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && unset PROJECT_ROOT && bash "$INJECT_CONTEXT_SCRIPT" 2>/dev/null)
set -e

assert_not_contains "no routing section" "=ROUTING" "$RESULT"
assert_not_contains "no rules section" "=RULES" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 9: Orchestration index file — under 5KB
# Ceiling history: 3584 was set at the initial commit when the index was 3373 bytes.
# Shipped routing (notebook, riff-as-skill, claims-audit) grew it to 4470 bytes of
# load-bearing content; the ceiling was re-evaluated and raised to 5120 (current +
# ~14% headroom). The budget still bounds per-prompt injection cost — the inject
# hook cats the whole file into UserPromptSubmit output on every prompt.
begin_test "Orchestration index file — under 5KB"

INDEX_FILE="$PLUGIN_ROOT/reference/orchestration-index.min"
assert_file_exists "index file exists" "$INDEX_FILE"

FILE_SIZE=$(wc -c < "$INDEX_FILE" | tr -d ' ')
if [ "$FILE_SIZE" -lt 5120 ]; then
  echo "  PASS: file is ${FILE_SIZE} bytes (< 5120)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: file is ${FILE_SIZE} bytes (>= 5120 limit)"
  FAIL=$((FAIL + 1))
fi

echo ""

# Test 10: Orchestration index — all 6 sections present
begin_test "Orchestration index — all 6 sections present"

INDEX_FILE="$PLUGIN_ROOT/reference/orchestration-index.min"

assert_file_contains "has =ROUTING" "=ROUTING" "$INDEX_FILE"
assert_file_contains "has =LOOP" "=LOOP" "$INDEX_FILE"
assert_file_contains "has =CHAINS" "=CHAINS" "$INDEX_FILE"
assert_file_contains "has =RULES" "=RULES" "$INDEX_FILE"
assert_file_contains "has =SCRIPTS" "=SCRIPTS" "$INDEX_FILE"
assert_file_contains "has =STATE" "=STATE" "$INDEX_FILE"

echo ""

# Test 11: Orchestration index — implement loop continuation rule present
begin_test "Orchestration index — implement loop continuation rule"

INDEX_FILE="$PLUGIN_ROOT/reference/orchestration-index.min"

assert_file_contains "has continuation rule" "!stop after chunk/story completes" "$INDEX_FILE"

echo ""

# --- Summary ---
finish_tests
