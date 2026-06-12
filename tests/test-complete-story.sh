#!/bin/bash
# test-complete-story.sh — Tests for complete-story.sh
# Validates story completion: status transition, state cleanup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"

COMPLETE_STORY_SCRIPT="$SCRIPTS_DIR/complete-story.sh"

# --- Tests ---

echo "=== test-complete-story.sh ==="
echo ""

# Test 1: Happy path — active story becomes complete, state cleared
begin_test "Happy path — story status set to complete"

TEST_DIR=$(create_craft_with_story "test-cycle" "login-form" "Login Form" "3" "active")
trap cleanup_test_dir EXIT
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-login-form.md"
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"

set +e
RESULT=$(cd "$TEST_DIR" && bash "$COMPLETE_STORY_SCRIPT" "$STORY_FILE" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"

# Story status should be complete
STATUS=$(grep "^status:" "$STORY_FILE" | sed 's/status: *//')
assert_eq "story status is complete" "complete" "$STATUS"

cleanup_test_dir
echo ""

# Test 2: Clears CURRENT_STORY from global state
begin_test "Clears CURRENT_STORY from global state"

TEST_DIR=$(create_craft_with_story "test-cycle" "login-form" "Login Form" "3" "active")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-login-form.md"

set +e
(cd "$TEST_DIR" && bash "$COMPLETE_STORY_SCRIPT" "$STORY_FILE" 2>/dev/null)
set -e

source "$TEST_DIR/.craft/.global-state"
assert_eq "global CURRENT_STORY cleared" "" "$CURRENT_STORY"

cleanup_test_dir
echo ""

# Test 3: Clears cycle state — CURRENT_STORY, CURRENT_CHUNK, TOTAL_CHUNKS
begin_test "Clears cycle state — story, chunk, total"

TEST_DIR=$(create_craft_with_story "test-cycle" "login-form" "Login Form" "3" "active")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-login-form.md"
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"

set +e
(cd "$TEST_DIR" && bash "$COMPLETE_STORY_SCRIPT" "$STORY_FILE" 2>/dev/null)
set -e

source "$CYCLE_DIR/.state"
assert_eq "cycle CURRENT_STORY cleared" "" "$CURRENT_STORY"
assert_eq "cycle CURRENT_CHUNK reset to 0" "0" "$CURRENT_CHUNK"
assert_eq "cycle TOTAL_CHUNKS reset to 0" "0" "$TOTAL_CHUNKS"

cleanup_test_dir
echo ""

# Test 4: Clears CRAFT_WRITE_ENABLED
begin_test "Clears CRAFT_WRITE_ENABLED from global state"

TEST_DIR=$(create_craft_with_story "test-cycle" "login-form" "Login Form" "3" "active")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-login-form.md"

# Set CRAFT_WRITE_ENABLED first
echo 'CRAFT_WRITE_ENABLED="true"' >> "$TEST_DIR/.craft/.global-state"

set +e
(cd "$TEST_DIR" && bash "$COMPLETE_STORY_SCRIPT" "$STORY_FILE" 2>/dev/null)
set -e

source "$TEST_DIR/.craft/.global-state"
assert_eq "CRAFT_WRITE_ENABLED cleared" "" "$CRAFT_WRITE_ENABLED"

cleanup_test_dir
echo ""

# Test 5: Missing file — exits 1
begin_test "Missing file — exits 1"

TEST_DIR=$(mktemp -d)

set +e
RESULT=$(cd "$TEST_DIR" && bash "$COMPLETE_STORY_SCRIPT" "$TEST_DIR/nonexistent.md" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 1 for missing file" "1" "$EXIT_CODE"

rm -rf "$TEST_DIR"
echo ""

# Test 6: No arguments — exits 1
begin_test "No arguments — exits 1"

set +e
RESULT=$(bash "$COMPLETE_STORY_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 1 with no args" "1" "$EXIT_CODE"
echo ""

# --- Manifest staging tests (commit custody) ---

# Test 7: Manifest staging — only manifest paths staged, untracked untouched, manifest consumed
begin_test "Manifest staging — stages only manifest paths, leaves untracked untouched"

TEST_DIR=$(create_craft_with_story "test-cycle" "login-form" "Login Form" "3" "active")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-login-form.md"
git_init_repo "$TEST_DIR"

echo "tracked change" >> "$TEST_DIR/f1.txt"
echo "SECRET=hunter2" > "$TEST_DIR/secret.env"
printf 'story: 1-login-form\nf1.txt\n' > "$TEST_DIR/.craft/.commit-manifest"

set +e
(cd "$TEST_DIR" && bash "$COMPLETE_STORY_SCRIPT" "$STORY_FILE" >/dev/null 2>&1)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
COMMIT_COUNT=$(cd "$TEST_DIR" && git log --oneline | wc -l | tr -d ' ')
assert_eq "story commit created" "2" "$COMMIT_COUNT"
COMMITTED=$(cd "$TEST_DIR" && git show --name-only --format= HEAD)
assert_contains "commit contains f1.txt" "f1.txt" "$COMMITTED"
if echo "$COMMITTED" | grep -q "secret.env"; then
  echo "  FAIL: secret.env was swept into the commit"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: secret.env not in commit"
  PASS=$((PASS + 1))
fi
UNTRACKED=$(cd "$TEST_DIR" && git status --porcelain secret.env)
assert_contains "secret.env still untracked" "?? secret.env" "$UNTRACKED"
if [ -f "$TEST_DIR/.craft/.commit-manifest" ]; then
  echo "  FAIL: manifest not deleted after read (commit path)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: manifest deleted after read (commit path)"
  PASS=$((PASS + 1))
fi

cleanup_test_dir
echo ""

# Test 8: Gitignored manifest entry — skipped with warning, commit proceeds
begin_test "Gitignored manifest entry — skip-and-warn, commit proceeds"

TEST_DIR=$(create_craft_with_story "test-cycle" "login-form" "Login Form" "3" "active")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-login-form.md"
echo ".craft/" > "$TEST_DIR/.gitignore"
git_init_repo "$TEST_DIR"

echo "feature" > "$TEST_DIR/f1.txt"
echo "learnings: []" > "$TEST_DIR/.craft/.learnings.yaml"
printf 'story: 1-login-form\nf1.txt\n.craft/.learnings.yaml\n' > "$TEST_DIR/.craft/.commit-manifest"

set +e
STDERR_OUT=$(cd "$TEST_DIR" && bash "$COMPLETE_STORY_SCRIPT" "$STORY_FILE" 2>&1 >/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "warns about gitignored entry" "skipping gitignored manifest entry" "$STDERR_OUT"
COMMIT_COUNT=$(cd "$TEST_DIR" && git log --oneline | wc -l | tr -d ' ')
assert_eq "commit still created" "2" "$COMMIT_COUNT"
COMMITTED=$(cd "$TEST_DIR" && git show --name-only --format= HEAD)
assert_contains "commit contains f1.txt" "f1.txt" "$COMMITTED"

cleanup_test_dir
echo ""

# Test 9: Non-gitignore add failure — aborts commit, clears state, exits non-zero
begin_test "Non-gitignore add failure — aborts commit, state cleared, exit non-zero"

TEST_DIR=$(create_craft_with_story "test-cycle" "login-form" "Login Form" "3" "active")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-login-form.md"
git_init_repo "$TEST_DIR"

echo "feature" > "$TEST_DIR/f1.txt"
printf 'story: 1-login-form\nf1.txt\ndoes-not-exist.txt\n' > "$TEST_DIR/.craft/.commit-manifest"

set +e
STDERR_OUT=$(cd "$TEST_DIR" && bash "$COMPLETE_STORY_SCRIPT" "$STORY_FILE" 2>&1 >/dev/null)
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" != "0" ]; then
  echo "  PASS: exits non-zero on add failure"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected non-zero exit, got 0"
  FAIL=$((FAIL + 1))
fi
assert_contains "stderr names the failing entry" "failed to stage manifest entry" "$STDERR_OUT"
COMMIT_COUNT=$(cd "$TEST_DIR" && git log --oneline | wc -l | tr -d ' ')
assert_eq "no commit created" "1" "$COMMIT_COUNT"
source "$TEST_DIR/.craft/.global-state"
assert_eq "global CURRENT_STORY still cleared (no stranded state)" "" "$CURRENT_STORY"

cleanup_test_dir
echo ""

# Test 10: Malformed manifest (comma body line) — treated as absent
begin_test "Malformed manifest (unsplit comma line) — treated as absent"

TEST_DIR=$(create_craft_with_story "test-cycle" "login-form" "Login Form" "3" "active")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-login-form.md"
git_init_repo "$TEST_DIR"

printf 'story: 1-login-form\nsrc/a.ts,src/b.ts,tests/c.sh\n' > "$TEST_DIR/.craft/.commit-manifest"

set +e
STDOUT_OUT=$(cd "$TEST_DIR" && bash "$COMPLETE_STORY_SCRIPT" "$STORY_FILE" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "logs malformed manifest" "malformed manifest, no commit made" "$STDOUT_OUT"
COMMIT_COUNT=$(cd "$TEST_DIR" && git log --oneline | wc -l | tr -d ' ')
assert_eq "no commit created" "1" "$COMMIT_COUNT"
source "$TEST_DIR/.craft/.global-state"
assert_eq "global CURRENT_STORY cleared" "" "$CURRENT_STORY"
if [ -f "$TEST_DIR/.craft/.commit-manifest" ]; then
  echo "  FAIL: manifest not deleted after read (malformed path)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: manifest deleted after read (malformed path)"
  PASS=$((PASS + 1))
fi

cleanup_test_dir
echo ""

# Test 11: Story-identity mismatch — loud abort, no stranded state, manifest consumed
begin_test "Story-identity mismatch — aborts non-zero without stranding state"

TEST_DIR=$(create_craft_with_story "test-cycle" "login-form" "Login Form" "3" "active")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-login-form.md"
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"
git_init_repo "$TEST_DIR"

echo "feature" > "$TEST_DIR/f1.txt"
printf 'story: other-story\nf1.txt\n' > "$TEST_DIR/.craft/.commit-manifest"

set +e
STDERR_OUT=$(cd "$TEST_DIR" && bash "$COMPLETE_STORY_SCRIPT" "$STORY_FILE" 2>&1 >/dev/null)
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" != "0" ]; then
  echo "  PASS: exits non-zero on identity mismatch"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected non-zero exit, got 0"
  FAIL=$((FAIL + 1))
fi
assert_contains "stderr names both stories" "other-story" "$STDERR_OUT"
COMMIT_COUNT=$(cd "$TEST_DIR" && git log --oneline | wc -l | tr -d ' ')
assert_eq "no commit created" "1" "$COMMIT_COUNT"
source "$TEST_DIR/.craft/.global-state"
assert_eq "global CURRENT_STORY cleared (no stranded state)" "" "$CURRENT_STORY"
source "$CYCLE_DIR/.state"
assert_eq "cycle CURRENT_STORY cleared (no stranded state)" "" "$CURRENT_STORY"
if [ -f "$TEST_DIR/.craft/.commit-manifest" ]; then
  echo "  FAIL: manifest not deleted after read (abort path)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: manifest deleted after read (abort path)"
  PASS=$((PASS + 1))
fi

cleanup_test_dir
echo ""

# Test 12: Absent manifest — no commit, no sweep, state cleared, exit 0
begin_test "Absent manifest — no commit made, no sweep, exits 0"

TEST_DIR=$(create_craft_with_story "test-cycle" "login-form" "Login Form" "3" "active")
STORY_FILE="$TEST_DIR/.craft/cycles/1-test-cycle/stories/1-login-form.md"
git_init_repo "$TEST_DIR"

echo "SECRET=hunter2" > "$TEST_DIR/secret.env"

set +e
STDOUT_OUT=$(cd "$TEST_DIR" && bash "$COMPLETE_STORY_SCRIPT" "$STORY_FILE" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "logs no-manifest" "no manifest found, no commit made" "$STDOUT_OUT"
COMMIT_COUNT=$(cd "$TEST_DIR" && git log --oneline | wc -l | tr -d ' ')
assert_eq "no commit created" "1" "$COMMIT_COUNT"
UNTRACKED=$(cd "$TEST_DIR" && git status --porcelain secret.env)
assert_contains "untracked secret never swept" "?? secret.env" "$UNTRACKED"
source "$TEST_DIR/.craft/.global-state"
assert_eq "global CURRENT_STORY cleared" "" "$CURRENT_STORY"

cleanup_test_dir
echo ""

# --- Summary ---
finish_tests
