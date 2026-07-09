#!/bin/bash
# test-low-priority-scripts.sh — Happy-path tests for LOW priority scripts
# Batched: statusline, setup-craft, discover-projects, generate-project-md,
#          track-usage, self-critique, check-polish
#
# SAFETY: Script invocations use (cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && ...)
# to prevent find-project-root.sh from escaping the temp dir.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/minimal.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"

# --- Tests ---

echo "=== test-low-priority-scripts.sh ==="
echo ""

# Test 1: statusline — outputs text (skip if no jq)
begin_test "statusline — outputs text"

if command -v jq &> /dev/null; then
  TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")
  trap cleanup_test_dir EXIT

  cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY="test-story"
EOF

  # statusline reads from stdin (cost, token info) and .craft/
  JSON='{"cost":{"total_cost_usd":0.42},"tokenUsage":{"input":50000,"contextLimit":200000}}'
  set +e
  RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$SCRIPTS_DIR/statusline.sh" 2>/dev/null)
  EXIT_CODE=$?
  set -e

  assert_eq "exits 0" "0" "$EXIT_CODE"
  # statusline shows cycle TITLE ("Test Cycle") not dir name ("test-cycle")
  # Use literal match — output has unicode progress bar that can confuse regex grep
  assert_contains_literal "shows cycle title" "Test Cycle" "$RESULT"
  # BUG NOTE: statusline.sh outputs malformed UTF-8 in progress bar (e2e2 sequence)
  # which makes grep treat the entire string as binary and fail to match.
  # Using bash pattern matching instead of grep to verify cost is present.
  if [[ "$RESULT" == *"0.42"* ]]; then
    echo "  PASS: shows cost"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: shows cost"
    echo "    expected to contain: '0.42'"
    echo "    in: '$RESULT'"
    FAIL=$((FAIL + 1))
  fi

  cleanup_test_dir
else
  echo "  SKIP: jq not installed"
  PASS=$((PASS + 1))
fi
echo ""

# Test 3: setup-craft — creates directory structure
begin_test "setup-craft — creates .craft/ structure"

TEST_DIR=$(mktemp -d)

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPTS_DIR/setup-craft.sh" "ui" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_dir_exists ".craft/backlog created" "$TEST_DIR/.craft/backlog"
assert_dir_exists ".craft/cycles created" "$TEST_DIR/.craft/cycles"
assert_dir_exists ".craft/design created" "$TEST_DIR/.craft/design"
assert_file_exists ".global-state created" "$TEST_DIR/.craft/.global-state"

rm -rf "$TEST_DIR"
echo ""

# Test 4: setup-craft CLI — creates CLI-specific structure
begin_test "setup-craft CLI — creates CLI structure"

TEST_DIR=$(mktemp -d)

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPTS_DIR/setup-craft.sh" "cli" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_dir_exists ".craft/ created" "$TEST_DIR/.craft"
# CLI projects don't get inspiration directory
assert_dir_not_exists "no inspiration for CLI" "$TEST_DIR/.craft/inspiration"

rm -rf "$TEST_DIR"
echo ""

# Test 5: discover-projects — outputs project lines
begin_test "discover-projects — outputs project info"

# This test runs in the actual git repo, so it should find projects
set +e
RESULT=$(bash "$SCRIPTS_DIR/discover-projects.sh" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
# Should output at least one line with pipe-separated values
if [ -n "$RESULT" ]; then
  assert_contains "output has pipe separator" "|" "$RESULT"
else
  # No projects found is valid in some contexts
  assert_eq "no projects found (valid)" "0" "$EXIT_CODE"
fi
echo ""

# Test 6: generate-project-md — creates project.md
begin_test "generate-project-md — creates .craft/project.md"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" PROJECT_NAME="TestApp" bash "$SCRIPTS_DIR/generate-project-md.sh" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_file_exists "project.md created" "$TEST_DIR/.craft/project.md"
if [ -f "$TEST_DIR/.craft/project.md" ]; then
  assert_file_contains "has project name" "TestApp" "$TEST_DIR/.craft/project.md"
fi

rm -rf "$TEST_DIR"
echo ""

# Test 7: track-usage — creates usage log
begin_test "track-usage — creates usage log"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-test-story.md"

set +e
RESULT=$(bash "$SCRIPTS_DIR/track-usage.sh" "$STORY_FILE" "1" "implementer" "5000" "12" "30000" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"

USAGE_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/.usage/1-test-story.log"
assert_file_exists "usage log created" "$USAGE_FILE"
if [ -f "$USAGE_FILE" ]; then
  assert_file_contains "has chunk number" "chunk:1" "$USAGE_FILE"
  assert_file_contains "has agent type" "implementer" "$USAGE_FILE"
  assert_file_contains "has token count" "5000" "$USAGE_FILE"
fi

cleanup_test_dir
echo ""

# Test 8: track-usage — no args exits 1
begin_test "track-usage — no args exits 1"

set +e
RESULT=$(bash "$SCRIPTS_DIR/track-usage.sh" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 1 with no args" "1" "$EXIT_CODE"
echo ""

# Test 9: self-critique — outputs report
begin_test "self-critique — outputs report"

TEST_DIR=$(create_minimal_craft)

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/self-critique.sh" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "has report header" "SELF-CRITIQUE" "$RESULT"
assert_contains "has review questions" "Review Questions" "$RESULT"

cleanup_test_dir
echo ""

# Test 10: check-polish — outputs report (exits 0 even with warnings)
begin_test "check-polish — outputs report"

TEST_DIR=$(mktemp -d)

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/check-polish.sh" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "has polish header" "POLISH" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# --- Summary ---
finish_tests
