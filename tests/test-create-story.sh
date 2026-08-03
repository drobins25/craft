#!/bin/bash
# test-create-story.sh — Tests for create-story.sh
# Validates story creation from templates with proper frontmatter
#
# REGRESSION (story 8): test 1 MUST FAIL against current codebase

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-cycle.sh"

# --- Tests ---

echo "=== test-create-story.sh ==="
echo ""

# ---- REGRESSION TEST (Story 8) ----
# create-story.sh uses raw sed substitution without quoting the title.
# A title with a colon produces invalid YAML: title: Fix: broken thing
begin_test "REGRESSION: create-story.sh quotes title with colon"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
trap cleanup_test_dir EXIT
cd "$TEST_DIR"

# Set CLAUDE_PLUGIN_ROOT so create-story.sh finds templates
RESULT=$(CRAFT_PROJECT_ROOT="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPTS_DIR/create-story.sh" "fix-auth" "Fix: broken authentication")

# The file should exist
assert_file_exists "story file created" "$RESULT"

# The title MUST be quoted to be valid YAML (colon in value)
TITLE_LINE=$(grep "^title:" "$RESULT" | head -1)
if echo "$TITLE_LINE" | grep -qE '^title: ".*"$' || echo "$TITLE_LINE" | grep -qE "^title: '.*'$"; then
  echo "  PASS: title with colon is quoted"
  PASS=$((PASS + 1))
else
  echo "  FAIL: title with colon is NOT quoted — invalid YAML"
  echo "    actual:   $TITLE_LINE"
  echo "    expected: title: \"Fix: broken authentication\""
  FAIL=$((FAIL + 1))
fi

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# Test 2: Happy path — backlog story creation
begin_test "Happy path — backlog story creates file with frontmatter"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
cd "$TEST_DIR"
mkdir -p .craft/backlog

RESULT=$(CRAFT_PROJECT_ROOT="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPTS_DIR/create-story.sh" "login-form" "Login Form")

assert_file_exists "story file created" "$RESULT"
assert_contains "file is in backlog" "backlog" "$RESULT"

# Check frontmatter fields
assert_yaml_field "name field" "name" "login-form" "$RESULT"
assert_yaml_field "status field" "status" "backlog" "$RESULT"
assert_yaml_field_exists "priority field exists" "priority" "$RESULT"
assert_yaml_field_exists "created field exists" "created" "$RESULT"

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# Test 3: Story creation with cycle assignment
begin_test "Cycle story — file lands in stories/ with correct number"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
cd "$TEST_DIR"

RESULT=$(CRAFT_PROJECT_ROOT="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPTS_DIR/create-story.sh" "signup-form" "Signup Form" --cycle=test-cycle)

assert_file_exists "story file created" "$RESULT"
assert_contains "file is in cycle stories dir" "stories/" "$RESULT"
assert_contains "file has story number prefix" "1-signup-form.md" "$RESULT"

# Check cycle-specific frontmatter fields
assert_yaml_field_exists "cycle field exists" "cycle" "$RESULT"
assert_yaml_field_exists "story_number field exists" "story_number" "$RESULT"

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# ---- ADDITIONAL BUG: sed treats & as matched pattern ----
# create-story.sh uses raw sed: sed "s|{{STORY_TITLE}}|${STORY_TITLE}|g"
# The & in the replacement string means "the matched text", so
# "Fix Layout & Spacing" → "Fix Layout {{STORY_TITLE}} Spacing" (corrupted)
begin_test "BUG: create-story.sh corrupts title with ampersand"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
cd "$TEST_DIR"
mkdir -p .craft/backlog

RESULT=$(CRAFT_PROJECT_ROOT="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPTS_DIR/create-story.sh" "ui-polish" "Fix Layout & Spacing")
assert_file_exists "story with ampersand created" "$RESULT"

# The title should contain the actual text, not the corrupted version
CONTENT=$(cat "$RESULT")
assert_contains_literal "title contains ampersand text" "Fix Layout & Spacing" "$CONTENT"

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# ---- REGRESSION TEST (Story 9): Relative .craft path ----
# create-story.sh line 56: story_file=".craft/backlog/${STORY_NAME}.md"
# This is relative to CWD. When CWD ≠ project root and CRAFT_PROJECT_ROOT is set,
# the story should be created at CRAFT_PROJECT_ROOT/.craft/backlog/, not CWD/.craft/backlog/.
begin_test "REGRESSION: create-story uses CRAFT_PROJECT_ROOT for backlog path"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
mkdir -p "$TEST_DIR/.craft/backlog"

# Create a subdirectory WITHOUT .craft/
mkdir -p "$TEST_DIR/src/features"

# Run from subdirectory with CRAFT_PROJECT_ROOT set to correct root
set +e
RESULT=$(cd "$TEST_DIR/src/features" && export CRAFT_PROJECT_ROOT="$TEST_DIR" && \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPTS_DIR/create-story.sh" "subdir-story" "Story From Subdir" 2>/dev/null)
EXIT_CODE=$?
set -e

# The story should land in the PROJECT ROOT's backlog, not in CWD
if [ -f "$TEST_DIR/.craft/backlog/subdir-story.md" ]; then
  echo "  PASS: story created at project root backlog"
  PASS=$((PASS + 1))
else
  echo "  FAIL: story NOT at project root backlog ($TEST_DIR/.craft/backlog/subdir-story.md)"
  # Check if it accidentally created at CWD
  if [ -f "$TEST_DIR/src/features/.craft/backlog/subdir-story.md" ]; then
    echo "    BUG: story created at CWD/.craft/backlog/ instead of CRAFT_PROJECT_ROOT"
  else
    echo "    BUG: story not created at all (script uses relative '.craft' path, no .craft/ at CWD)"
    echo "    exit code: $EXIT_CODE"
  fi
  FAIL=$((FAIL + 1))
fi

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# ---- REGRESSION TEST (Story 9): Relative .craft path for --cycle ----
# create-story.sh line 43: cycle_dir=$(find .craft/cycles -maxdepth 1 ...)
# Also relative to CWD. Same bug class as the backlog path.
begin_test "REGRESSION: create-story uses CRAFT_PROJECT_ROOT for cycle path"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")

# Create a subdirectory WITHOUT .craft/
mkdir -p "$TEST_DIR/src/features"

# Run from subdirectory with --cycle flag
set +e
RESULT=$(cd "$TEST_DIR/src/features" && export CRAFT_PROJECT_ROOT="$TEST_DIR" && \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPTS_DIR/create-story.sh" "cycle-story" "Cycle Story" --cycle=test-cycle 2>/dev/null)
EXIT_CODE=$?
set -e

# The story should land in the cycle's stories/ at PROJECT ROOT
CYCLE_STORIES=$(ls "$TEST_DIR/.craft/cycles/1-test-cycle/stories/"*cycle-story*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$CYCLE_STORIES" -gt 0 ]; then
  echo "  PASS: story created in cycle at project root"
  PASS=$((PASS + 1))
else
  echo "  FAIL: story NOT in cycle at project root"
  echo "    BUG: script uses 'find .craft/cycles' relative to CWD, ignoring CRAFT_PROJECT_ROOT"
  echo "    exit code: $EXIT_CODE"
  FAIL=$((FAIL + 1))
fi

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# Test: Numbering after a gap — next number is max+1, never count+1
# A cycle holding stories 1, 2, 5 (3-4 archived away) has count=3 but max=5.
# count+1 would assign 4; the new story must get 6. Gaps stay gaps.
begin_test "Numbering with gap — assigns max+1, not count+1"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
cd "$TEST_DIR"

CYCLE_STORY_DIR="$TEST_DIR/.craft/cycles/1-test-cycle/stories"
for n in 1 2 5; do
  cat > "$CYCLE_STORY_DIR/${n}-story-${n}.md" << EOF
---
name: story-${n}
title: "Story ${n}"
status: ready
cycle: test-cycle
story_number: ${n}
---

# Story ${n}
EOF
done

RESULT=$(CRAFT_PROJECT_ROOT="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPTS_DIR/create-story.sh" "gapped-story" "Gapped Story" --cycle=test-cycle)

assert_file_exists "story file created" "$RESULT"
RESULT_BASENAME=$(basename "$RESULT")
if [ "$RESULT_BASENAME" = "6-gapped-story.md" ]; then
  echo "  PASS: gap folder (1,2,5) assigns 6"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected 6-gapped-story.md, got $RESULT_BASENAME (count+1 regression)"
  FAIL=$((FAIL + 1))
fi

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# Test: Zero-padded prefix — "08" must not crash octal arithmetic
# bash $((...)) reads a leading-zero string as octal; a file named 08-*.md
# would abort the script (value too great for base) without the strip guard.
begin_test "Zero-padded prefix — 08 parses as 8, next is 9"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
cd "$TEST_DIR"

CYCLE_STORY_DIR="$TEST_DIR/.craft/cycles/1-test-cycle/stories"
cat > "$CYCLE_STORY_DIR/08-story-8.md" << 'EOF'
---
name: story-8
title: "Story 8"
status: ready
cycle: test-cycle
story_number: 8
---

# Story 8
EOF

set +e
RESULT=$(CRAFT_PROJECT_ROOT="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$SCRIPTS_DIR/create-story.sh" "padded-story" "Padded Story" --cycle=test-cycle)
CREATE_EXIT=$?
set -e

assert_eq "script exits 0 (no octal crash)" "0" "$CREATE_EXIT"
RESULT_BASENAME=$(basename "$RESULT")
if [ "$RESULT_BASENAME" = "9-padded-story.md" ]; then
  echo "  PASS: 08 parsed as 8, assigned 9"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected 9-padded-story.md, got $RESULT_BASENAME"
  FAIL=$((FAIL + 1))
fi

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# --- Summary ---
finish_tests
