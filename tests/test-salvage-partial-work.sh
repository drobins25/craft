#!/bin/bash
# test-salvage-partial-work.sh — Tests for salvage-partial-work.sh
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
  mkdir -p .craft/salvage
  mkdir -p src/components

  # Create global state
  cat > .craft/.global-state << 'EOF'
ACTIVE_CYCLE="10-test-cycle"
CURRENT_STORY="login-form"
LAST_ACTIVITY=""
EOF

  # Create some source files
  echo "original content A" > src/components/LoginForm.tsx
  echo "original content B" > src/auth.ts

  # Initial commit — this is our "checkpoint"
  git add -A
  git commit -q -m "checkpoint"

  CHECKPOINT_REF=$(git rev-parse --short HEAD)
  echo "$TEST_DIR|$CHECKPOINT_REF"
}

# --- Tests ---

echo "=== test-salvage-partial-work.sh ==="
echo ""

# Test 1: Modified files get salvaged
begin_test "Modified files — salvage dir with files + patches + manifest"
SETUP=$(setup_test_project)
TEST_DIR="${SETUP%%|*}"
CHECKPOINT_REF="${SETUP##*|}"
trap cleanup_test_dir EXIT
cd "$TEST_DIR"

# Modify two files after checkpoint
echo "modified content A" > src/components/LoginForm.tsx
echo "modified content B" > src/auth.ts

RESULT=$("$SCRIPTS_DIR/salvage-partial-work.sh" "$CHECKPOINT_REF" "login-form" 2 "$TEST_DIR")

# Check salvage dir exists
assert_dir_exists "salvage directory created" "$RESULT"
assert_file_exists "manifest.yaml exists" "${RESULT}/manifest.yaml"

# Check files were copied
assert_file_exists "LoginForm.tsx copied" "${RESULT}/files/src/components/LoginForm.tsx"
assert_file_exists "auth.ts copied" "${RESULT}/files/src/auth.ts"

# Check patches directory exists
assert_dir_exists "patches directory exists" "${RESULT}/patches"

# Check manifest has correct file count
FILE_COUNT=$(grep "^file_count:" "${RESULT}/manifest.yaml" | sed 's/file_count: *//')
assert_eq "manifest shows 2 files" "2" "$FILE_COUNT"

# Check manifest has story info
MANIFEST_STORY=$(grep "^story:" "${RESULT}/manifest.yaml" | sed 's/story: *//' | tr -d '"')
assert_eq "manifest has story name" "login-form" "$MANIFEST_STORY"

cleanup_test_dir
echo ""

# Test 2: Added files (untracked)
begin_test "Added files — new untracked file in salvage"
SETUP=$(setup_test_project)
TEST_DIR="${SETUP%%|*}"
CHECKPOINT_REF="${SETUP##*|}"
cd "$TEST_DIR"

# Add a new file (untracked)
mkdir -p src/new
echo "brand new file" > src/new/NewComponent.tsx

RESULT=$("$SCRIPTS_DIR/salvage-partial-work.sh" "$CHECKPOINT_REF" "login-form" 2 "$TEST_DIR")

assert_dir_exists "salvage directory created" "$RESULT"
assert_file_exists "new file copied" "${RESULT}/files/src/new/NewComponent.tsx"

# Check manifest shows added
MANIFEST_CONTENT=$(cat "${RESULT}/manifest.yaml")
assert_contains "manifest shows added type" "added" "$MANIFEST_CONTENT"

cleanup_test_dir
echo ""

# Test 3: No changes — nothing to salvage
begin_test "No changes — stdout 'nothing_to_salvage'"
SETUP=$(setup_test_project)
TEST_DIR="${SETUP%%|*}"
CHECKPOINT_REF="${SETUP##*|}"
cd "$TEST_DIR"

# Don't change anything
set +e
RESULT=$("$SCRIPTS_DIR/salvage-partial-work.sh" "$CHECKPOINT_REF" "login-form" 2 "$TEST_DIR")
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_eq "stdout is nothing_to_salvage" "nothing_to_salvage" "$RESULT"

# No salvage directory should be created
SALVAGE_DIRS=$(find "$TEST_DIR/.craft/salvage" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
assert_eq "no salvage directory created" "0" "$SALVAGE_DIRS"

cleanup_test_dir
echo ""

# Test 4: Deleted files
begin_test "Deleted files — manifest shows 'deleted'"
SETUP=$(setup_test_project)
TEST_DIR="${SETUP%%|*}"
CHECKPOINT_REF="${SETUP##*|}"
cd "$TEST_DIR"

# Delete a file
rm src/auth.ts

RESULT=$("$SCRIPTS_DIR/salvage-partial-work.sh" "$CHECKPOINT_REF" "login-form" 2 "$TEST_DIR")

assert_dir_exists "salvage directory created" "$RESULT"

MANIFEST_CONTENT=$(cat "${RESULT}/manifest.yaml")
assert_contains "manifest shows deleted type" "deleted" "$MANIFEST_CONTENT"

# Deleted file should NOT be in files/ (it doesn't exist on disk)
if [ ! -f "${RESULT}/files/src/auth.ts" ]; then
  echo "  PASS: deleted file not in files/"
  PASS=$((PASS + 1))
else
  echo "  FAIL: deleted file should not be in files/"
  FAIL=$((FAIL + 1))
fi

cleanup_test_dir
echo ""

# --- Summary ---
finish_tests
