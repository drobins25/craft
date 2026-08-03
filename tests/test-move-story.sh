#!/bin/bash
# test-move-story.sh — Tests for move-story.sh
# Validates frontmatter insertion when moving stories between backlog and cycles
#
# REGRESSIONS (story 8): tests 1-2 MUST FAIL against current codebase
# The awk insertion chain in move-story.sh silently fails when the expected
# anchor line is missing, producing unchanged files.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-cycle.sh"

# Helper: create a backlog story WITHOUT status: field
# This exposes the awk anchor failure — move-story.sh inserts cycle:
# after ^status: and story_number: after ^cycle:, but if status: is missing,
# the entire chain silently produces unchanged file.
create_backlog_story_no_status() {
  local dir="$1"
  local name="${2:-test-story}"
  local title="${3:-Test Story}"
  mkdir -p "$dir/.craft/backlog"
  cat > "$dir/.craft/backlog/${name}.md" << EOF
---
name: ${name}
title: "${title}"
priority: medium
created: 2026-02-14
updated: 2026-02-14
chunks_total: 0
chunks_complete: 0
---

# Story: ${title}

## Spark
A test story without status field.
EOF
}

# Helper: create a backlog story WITH full frontmatter (including status:)
create_backlog_story_full() {
  local dir="$1"
  local name="${2:-test-story}"
  local title="${3:-Test Story}"
  mkdir -p "$dir/.craft/backlog"
  cat > "$dir/.craft/backlog/${name}.md" << EOF
---
name: ${name}
title: "${title}"
status: backlog
priority: medium
created: 2026-02-14
updated: 2026-02-14
chunks_total: 0
chunks_complete: 0
---

# Story: ${title}

## Spark
A test story with full frontmatter.

## Notes
This content should be preserved after move.
EOF
}

# --- Tests ---

echo "=== test-move-story.sh ==="
echo ""

# ---- REGRESSION TEST 1 (Story 8) ----
# When a story lacks status: in frontmatter, awk's /^status:/ anchor has no match.
# The cycle: field is never inserted. move-story.sh silently produces unchanged file.
begin_test "REGRESSION: move-story inserts cycle field"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
trap cleanup_test_dir EXIT
create_backlog_story_no_status "$TEST_DIR" "login" "Login Form"
cd "$TEST_DIR"

# Move from backlog to cycle — capture the output path
set +e
MOVED_FILE=$("$SCRIPTS_DIR/move-story.sh" "$TEST_DIR/.craft/backlog/login.md" "test-cycle" 2>/dev/null | tail -1)
MOVE_EXIT=$?
set -e

# The moved file should have cycle: in frontmatter
if [ -n "$MOVED_FILE" ] && [ -f "$MOVED_FILE" ]; then
  assert_yaml_field_exists "cycle: field present in moved file" "cycle" "$MOVED_FILE"
else
  echo "  FAIL: move-story.sh did not produce a valid output file"
  echo "    exit code: $MOVE_EXIT"
  echo "    output: $MOVED_FILE"
  FAIL=$((FAIL + 1))
fi

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# ---- REGRESSION TEST 2 (Story 8) ----
# story_number: insertion depends on cycle: being present (awk anchors on ^cycle:).
# Since cycle: was never inserted (test 1), story_number: is also missing.
begin_test "REGRESSION: move-story inserts story_number field"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
create_backlog_story_no_status "$TEST_DIR" "signup" "Signup Form"
cd "$TEST_DIR"

set +e
MOVED_FILE=$("$SCRIPTS_DIR/move-story.sh" "$TEST_DIR/.craft/backlog/signup.md" "test-cycle" 2>/dev/null | tail -1)
MOVE_EXIT=$?
set -e

if [ -n "$MOVED_FILE" ] && [ -f "$MOVED_FILE" ]; then
  assert_yaml_field_exists "story_number: field present in moved file" "story_number" "$MOVED_FILE"
else
  echo "  FAIL: move-story.sh did not produce a valid output file"
  echo "    exit code: $MOVE_EXIT"
  echo "    output: $MOVED_FILE"
  FAIL=$((FAIL + 1))
fi

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# Test 3: Happy path — full frontmatter story moved to cycle
begin_test "Happy path — move to cycle with full frontmatter"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
create_backlog_story_full "$TEST_DIR" "dashboard" "Dashboard"
cd "$TEST_DIR"

set +e
MOVED_FILE=$("$SCRIPTS_DIR/move-story.sh" "$TEST_DIR/.craft/backlog/dashboard.md" "test-cycle" 2>/dev/null | tail -1)
MOVE_EXIT=$?
set -e

assert_eq "exits 0" "0" "$MOVE_EXIT"

if [ -n "$MOVED_FILE" ] && [ -f "$MOVED_FILE" ]; then
  assert_file_exists "moved file exists" "$MOVED_FILE"
  assert_file_not_exists "original removed" "$TEST_DIR/.craft/backlog/dashboard.md"

  # Check file is in cycle stories directory
  assert_contains "file in cycle stories dir" "stories/" "$MOVED_FILE"

  # Check frontmatter has expected fields
  assert_yaml_field_exists "cycle field present" "cycle" "$MOVED_FILE"
  assert_yaml_field_exists "story_number field present" "story_number" "$MOVED_FILE"
  assert_yaml_field_exists "status field present" "status" "$MOVED_FILE"
  assert_yaml_field_exists "name field present" "name" "$MOVED_FILE"
else
  echo "  FAIL: move-story.sh did not produce a valid output file"
  echo "    exit code: $MOVE_EXIT"
  echo "    output: $MOVED_FILE"
  FAIL=$((FAIL + 1))
fi

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# Test 4: Move from cycle to backlog removes cycle/story_number
begin_test "Move to backlog — removes cycle and story_number fields"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
cd "$TEST_DIR"

# Create a story directly in the cycle with cycle/story_number fields
CYCLE_STORY_DIR="$TEST_DIR/.craft/cycles/1-test-cycle/stories"
cat > "$CYCLE_STORY_DIR/1-settings.md" << 'EOF'
---
name: settings
title: "Settings Page"
status: ready
priority: medium
created: 2026-02-14
updated: 2026-02-14
cycle: test-cycle
story_number: 1
chunks_total: 0
chunks_complete: 0
---

# Story: Settings Page

## Spark
Settings page story.
EOF

set +e
MOVED_FILE=$("$SCRIPTS_DIR/move-story.sh" "$CYCLE_STORY_DIR/1-settings.md" "backlog" 2>/dev/null | tail -1)
MOVE_EXIT=$?
set -e

if [ -n "$MOVED_FILE" ] && [ -f "$MOVED_FILE" ]; then
  assert_file_exists "moved to backlog" "$MOVED_FILE"
  assert_contains "file in backlog dir" "backlog/" "$MOVED_FILE"

  # cycle: and story_number: should be removed when moving to backlog
  MOVED_CONTENT=$(cat "$MOVED_FILE")
  assert_not_contains "cycle: removed" "^cycle:" "$MOVED_CONTENT"
  assert_not_contains "story_number: removed" "^story_number:" "$MOVED_CONTENT"
else
  echo "  FAIL: move-story.sh did not produce a valid output file"
  FAIL=$((FAIL + 1))
fi

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# Test 5: Markdown body content preserved after move
begin_test "Content preserved — markdown body unchanged after move"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
create_backlog_story_full "$TEST_DIR" "preserve" "Preserve Test"
cd "$TEST_DIR"

# Capture original body content (everything after second ---)
ORIGINAL_BODY=$(sed -n '/^---$/,/^---$/!p' "$TEST_DIR/.craft/backlog/preserve.md" | tail -n +1)

set +e
MOVED_FILE=$("$SCRIPTS_DIR/move-story.sh" "$TEST_DIR/.craft/backlog/preserve.md" "test-cycle" 2>/dev/null | tail -1)
set -e

if [ -n "$MOVED_FILE" ] && [ -f "$MOVED_FILE" ]; then
  MOVED_BODY=$(sed -n '/^---$/,/^---$/!p' "$MOVED_FILE" | tail -n +1)
  assert_contains_literal "spark section preserved" "A test story with full frontmatter." "$MOVED_BODY"
  assert_contains_literal "notes section preserved" "This content should be preserved after move." "$MOVED_BODY"
else
  echo "  FAIL: move-story.sh did not produce a valid output file"
  FAIL=$((FAIL + 1))
fi

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# Test 6: Numbering after a gap — next number is max+1, never count+1
# A cycle holding stories 1, 2, 5 (3-4 archived away) has count=3 but max=5.
# count+1 would assign 4; the next story must get 6. Gaps stay gaps.
begin_test "Numbering with gap — assigns max+1, not count+1"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
create_backlog_story_full "$TEST_DIR" "gapped" "Gapped Story"
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

set +e
MOVED_FILE=$("$SCRIPTS_DIR/move-story.sh" "$TEST_DIR/.craft/backlog/gapped.md" "test-cycle" 2>/dev/null | tail -1)
MOVE_EXIT=$?
set -e

if [ -n "$MOVED_FILE" ] && [ -f "$MOVED_FILE" ]; then
  MOVED_BASENAME=$(basename "$MOVED_FILE")
  if [ "$MOVED_BASENAME" = "6-gapped.md" ]; then
    echo "  PASS: gap folder (1,2,5) assigns 6"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: expected 6-gapped.md, got $MOVED_BASENAME (count+1 regression)"
    FAIL=$((FAIL + 1))
  fi
  assert_file_not_exists "no collision with existing story" "$CYCLE_STORY_DIR/4-gapped.md"
else
  echo "  FAIL: move-story.sh did not produce a valid output file"
  echo "    exit code: $MOVE_EXIT"
  FAIL=$((FAIL + 1))
fi

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# Test 7: Zero-padded prefix — "08" must not crash octal arithmetic
# bash $((...)) reads a leading-zero string as octal; a file named 08-*.md
# would abort the script (value too great for base) without the strip guard.
begin_test "Zero-padded prefix — 08 parses as 8, next is 9"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
create_backlog_story_full "$TEST_DIR" "padded" "Padded Story"
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
MOVED_FILE=$("$SCRIPTS_DIR/move-story.sh" "$TEST_DIR/.craft/backlog/padded.md" "test-cycle" 2>/dev/null | tail -1)
MOVE_EXIT=$?
set -e

assert_eq "script exits 0 (no octal crash)" "0" "$MOVE_EXIT"
if [ -n "$MOVED_FILE" ] && [ -f "$MOVED_FILE" ]; then
  MOVED_BASENAME=$(basename "$MOVED_FILE")
  if [ "$MOVED_BASENAME" = "9-padded.md" ]; then
    echo "  PASS: 08 parsed as 8, assigned 9"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: expected 9-padded.md, got $MOVED_BASENAME"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  FAIL: move-story.sh did not produce a valid output file"
  echo "    exit code: $MOVE_EXIT"
  FAIL=$((FAIL + 1))
fi

cd "$SCRIPT_DIR"
cleanup_test_dir
echo ""

# --- Summary ---
finish_tests
