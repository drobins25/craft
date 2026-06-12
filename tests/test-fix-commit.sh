#!/bin/bash
# test-fix-commit.sh — Evals for the fix skill's Step 5b scoped staging
# The fix flow is orchestrator-run prose (skills/fix/SKILL.md), not a script,
# so these tests mirror the documented staging commands against a git fixture
# and assert the staged set. If SKILL.md's commands change shape, update both.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"

echo "=== test-fix-commit.sh ==="
echo ""

# Guard: the skill must not regress to a tree sweep
begin_test "SKILL.md Step 5b no longer documents git add -A"

FIX_SKILL="$SCRIPT_DIR/../skills/fix/SKILL.md"
if grep -q "^git add -A" "$FIX_SKILL"; then
  echo "  FAIL: skills/fix/SKILL.md still documents 'git add -A'"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: no bare 'git add -A' command in fix skill"
  PASS=$((PASS + 1))
fi
if grep -q 'git add -- ' "$FIX_SKILL"; then
  echo "  PASS: scoped 'git add --' staging documented"
  PASS=$((PASS + 1))
else
  echo "  FAIL: scoped 'git add --' staging not found in fix skill"
  FAIL=$((FAIL + 1))
fi
echo ""

# Test: scoped staging includes only touched files
begin_test "Fix staging includes only touched files"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR"
echo "original" > "$TEST_DIR/fixed-file.txt"
git_init_repo "$TEST_DIR"

echo "patched" > "$TEST_DIR/fixed-file.txt"
echo "scratch" > "$TEST_DIR/unrelated-untracked.txt"

# Mirror the documented Step 5b commands: files_changed = [fixed-file.txt]
(
  cd "$TEST_DIR"
  git add -- fixed-file.txt
  git diff --cached --quiet || git commit -q -m "fix: test scoped staging" --no-verify
)

COMMITTED=$(cd "$TEST_DIR" && git show --name-only --format= HEAD)
assert_contains "commit contains touched file" "fixed-file.txt" "$COMMITTED"
if echo "$COMMITTED" | grep -q "unrelated-untracked.txt"; then
  echo "  FAIL: unrelated untracked file swept into fix commit"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: unrelated untracked file not in commit"
  PASS=$((PASS + 1))
fi
UNTRACKED=$(cd "$TEST_DIR" && git status --porcelain unrelated-untracked.txt)
assert_contains "unrelated file still untracked" "?? unrelated-untracked.txt" "$UNTRACKED"

rm -rf "$TEST_DIR"
echo ""

# Test: empty files_changed falls back to git diff --name-only HEAD
begin_test "Empty files_changed falls back to git diff"

TEST_DIR=$(mktemp -d)
echo "original" > "$TEST_DIR/tracked-modified.txt"
git_init_repo "$TEST_DIR"

echo "patched" > "$TEST_DIR/tracked-modified.txt"
echo "scratch" > "$TEST_DIR/unrelated-untracked.txt"

# Mirror the documented fallback: files_changed is empty -> stage tracked changes
(
  cd "$TEST_DIR"
  git diff --name-only HEAD | while IFS= read -r f; do git add -- "$f"; done
  git diff --cached --quiet || git commit -q -m "fix: test diff fallback" --no-verify
)

COMMITTED=$(cd "$TEST_DIR" && git show --name-only --format= HEAD)
assert_contains "fallback staged the tracked change" "tracked-modified.txt" "$COMMITTED"
if echo "$COMMITTED" | grep -q "unrelated-untracked.txt"; then
  echo "  FAIL: fallback swept an untracked file"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: fallback did not sweep untracked files"
  PASS=$((PASS + 1))
fi

rm -rf "$TEST_DIR"
echo ""

# Test: nothing staged means no commit and no error
begin_test "Fix commit skips cleanly when nothing staged"

TEST_DIR=$(mktemp -d)
echo "original" > "$TEST_DIR/file.txt"
git_init_repo "$TEST_DIR"

set +e
(
  cd "$TEST_DIR"
  git diff --cached --quiet || git commit -q -m "fix: should not happen" --no-verify
)
EXIT_CODE=$?
set -e

assert_eq "exits 0 with nothing staged" "0" "$EXIT_CODE"
COMMIT_COUNT=$(cd "$TEST_DIR" && git log --oneline | wc -l | tr -d ' ')
assert_eq "no commit created" "1" "$COMMIT_COUNT"

rm -rf "$TEST_DIR"
echo ""

# --- Summary ---
finish_tests
