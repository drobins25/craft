#!/bin/bash
# test-lifecycle-integration.sh — Integration tests for full lifecycle sequences
# Validates end-to-end flows: story lifecycle, cycle lifecycle, regression sequences
#
# SAFETY: Every script invocation runs in a subshell with:
#   (cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && ...)
# This prevents find-workshop.sh from escaping the temp dir
# and corrupting the real plugin's .craft/ state.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
# Run from a throwaway folder: a script that misreads its arguments and falls back
# to the current folder must never write into the real project.
cd "$(mktemp -d)"
source "$SCRIPT_DIR/fixtures/minimal.sh"
source "$SCRIPT_DIR/fixtures/with-cycle.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"
source "$SCRIPT_DIR/fixtures/with-shadow.sh"

# --- Tests ---

echo "=== test-lifecycle-integration.sh ==="
echo ""

# Integration 1: Story lifecycle — create → move → start → complete-chunk ×2 → complete-story
begin_test "INTEGRATION: Full story lifecycle"

TEST_DIR=$(create_minimal_craft)
trap cleanup_test_dir EXIT

# Step 1: Create cycle (create-cycle.sh takes explicit project root as 4th arg)
CYCLE_DIR=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPTS_DIR/create-cycle.sh" "auth" "Authentication" "Login flow" "$TEST_DIR" 2>/dev/null)
assert_dir_exists "cycle created" "$CYCLE_DIR"

# Step 2: Create story in backlog
# NOTE: Using "loginform" (no hyphen) because move-story.sh line 52 has a BUG:
#   sed 's/^[0-9]*[a-z]*-//' corrupts names with hyphens (e.g., "login-form" → "form").
#   The regex [a-z]*- greedily eats the first word of non-prefixed backlog stories.
#   BUG TRACKED: move-story.sh story_name extraction corrupts hyphenated names.
mkdir -p "$TEST_DIR/.craft/backlog"
cat > "$TEST_DIR/.craft/backlog/loginform.md" << 'STORY'
---
name: loginform
title: "Login Form"
status: planning
priority: high
created: 2026-01-01
updated: 2026-01-01
chunks_total: 2
chunks_complete: 0
current_chunk: 0
---

# Story: Login Form

## Spark
Build the login form.
STORY

# Step 3: Move story to cycle (move-story.sh takes explicit project root as 3rd arg)
(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/move-story.sh" "$TEST_DIR/.craft/backlog/loginform.md" "auth" "$TEST_DIR" >/dev/null 2>&1)
STORY_FILE=$(ls "$CYCLE_DIR/stories/"*loginform*.md 2>/dev/null | head -1)
assert_file_exists "story moved to cycle" "$STORY_FILE"

# Step 4: Start story (derives project root from story path — path is in /tmp/)
(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/start-story.sh" "$STORY_FILE" >/dev/null 2>&1)

# Verify state after start
source "$TEST_DIR/.craft/.global-state"
# start-story.sh uses basename (includes number prefix from move)
assert_eq "CURRENT_STORY is 1-loginform" "1-loginform" "$CURRENT_STORY"

source "$CYCLE_DIR/.state"
assert_eq "CURRENT_CHUNK is 1" "1" "$CURRENT_CHUNK"
assert_eq "TOTAL_CHUNKS is 2" "2" "$TOTAL_CHUNKS"

# Step 5: Complete chunk 1
(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/complete-chunk.sh" "$CYCLE_DIR" >/dev/null 2>&1)

source "$CYCLE_DIR/.state"
assert_eq "CURRENT_CHUNK is 2 after chunk 1" "2" "$CURRENT_CHUNK"

# Step 6: Complete chunk 2 (last chunk)
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/complete-chunk.sh" "$CYCLE_DIR" 2>/dev/null)
assert_contains "signals ALL CHUNKS COMPLETE" "ALL CHUNKS COMPLETE" "$RESULT"

# Step 7: Complete story
(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/complete-story.sh" "$STORY_FILE" >/dev/null 2>&1)

# Verify final state
assert_yaml_field "story status is complete" "status" "complete" "$STORY_FILE"

source "$TEST_DIR/.craft/.global-state"
assert_eq "CURRENT_STORY cleared after story complete" "" "$CURRENT_STORY"

source "$CYCLE_DIR/.state"
assert_eq "CURRENT_CHUNK reset to 0" "0" "$CURRENT_CHUNK"

cleanup_test_dir
echo ""

# Integration 2: Cycle lifecycle — create → start → [story] → complete-cycle
begin_test "INTEGRATION: Full cycle lifecycle"

TEST_DIR=$(create_minimal_craft)

# Create cycle
CYCLE_DIR=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPTS_DIR/create-cycle.sh" "dashboard" "Dashboard" "UI" "$TEST_DIR" 2>/dev/null)

# Start cycle
(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/start-cycle.sh" "$CYCLE_DIR" >/dev/null 2>&1)

source "$TEST_DIR/.craft/.global-state"
assert_eq "ACTIVE_CYCLE set" "1-dashboard" "$ACTIVE_CYCLE"

# Create a story directly in cycle
cat > "$CYCLE_DIR/stories/1-widget.md" << 'STORY'
---
name: widget
title: "Widget Component"
status: active
priority: medium
created: 2026-01-01
updated: 2026-01-01
cycle: dashboard
story_number: 1
chunks_total: 1
chunks_complete: 0
current_chunk: 0
---

# Story: Widget Component

## Spark
Build widget.
STORY

# Start story
(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/start-story.sh" "$CYCLE_DIR/stories/1-widget.md" >/dev/null 2>&1)

# Complete chunk
(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/complete-chunk.sh" "$CYCLE_DIR" >/dev/null 2>&1)

# Complete story
(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/complete-story.sh" "$CYCLE_DIR/stories/1-widget.md" >/dev/null 2>&1)

# Complete cycle
(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/complete-cycle.sh" "$CYCLE_DIR" >/dev/null 2>&1)

source "$TEST_DIR/.craft/.global-state"
assert_eq "ACTIVE_CYCLE cleared after cycle complete" "" "$ACTIVE_CYCLE"

source "$CYCLE_DIR/.state"
assert_eq "CYCLE_STATUS is complete" "complete" "$CYCLE_STATUS"

assert_file_contains "cycle.yaml status is complete" "status: complete" "$CYCLE_DIR/cycle.yaml"

cleanup_test_dir
echo ""

# Integration 3: REGRESSION — create story with colon title → move to cycle
# Tests the frontmatter pipeline for story 8 bugs
begin_test "REGRESSION: Story with colon in title — frontmatter pipeline"

TEST_DIR=$(create_minimal_craft)

# Create cycle
CYCLE_DIR=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPTS_DIR/create-cycle.sh" "test" "Test" "Testing" "$TEST_DIR" 2>/dev/null)

# Ensure backlog dir exists (create-story.sh doesn't create it)
mkdir -p "$TEST_DIR/.craft/backlog"

# Create story with colon in title via create-story.sh
# create-story.sh takes: <name> <title> [--cycle=<cycle>]
# It writes to relative .craft/backlog/ from CWD
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$SCRIPTS_DIR/create-story.sh" "fix-auth" "Fix: Authentication Bug" 2>/dev/null)
set -e

STORY_FILE="$TEST_DIR/.craft/backlog/fix-auth.md"
if [ -f "$STORY_FILE" ]; then
  # Check if title is properly quoted (WILL FAIL — known bug)
  TITLE_LINE=$(grep "^title:" "$STORY_FILE")
  if echo "$TITLE_LINE" | grep -q '^title: ".*"$'; then
    assert_eq "title is quoted" "true" "true"
  else
    assert_eq "REGRESSION: title with colon is NOT quoted" "quoted" "unquoted"
  fi
else
  assert_eq "story file created" "exists" "missing"
fi

cleanup_test_dir
echo ""

# Integration 4: Nearest wins — find-workshop from child resolves to child
# NOTE: create_craft_with_shadow() returns $dir; project lives at $dir/project/
begin_test "INTEGRATION: Nearest wins — find-workshop from child"

TEST_DIR=$(create_craft_with_shadow)

# cd to child directory, run find-workshop
set +e
RESULT=$(cd "$TEST_DIR/project/apps/web" && unset CRAFT_PROJECT_ROOT && source "$SCRIPTS_DIR/find-workshop.sh" 2>/dev/null && echo "$PROJECT_ROOT")
set -e

# Nearest wins: should resolve to child (apps/web has its own .craft/)
if echo "$RESULT" | grep -q "apps/web"; then
  assert_eq "resolves to nearest (child)" "child" "child"
else
  assert_eq "should resolve to child (nearest .craft/)" "child" "parent"
fi

cleanup_test_dir
echo ""

# Integration 5: Nearest wins — session-start from child persists child path
# NOTE: create_craft_with_shadow() returns $dir; project lives at $dir/project/
begin_test "INTEGRATION: Session start from child — persists nearest path"

TEST_DIR=$(create_craft_with_shadow)

# Create a temporary CLAUDE_ENV_FILE
ENV_FILE=$(mktemp)

set +e
(cd "$TEST_DIR/project/apps/web" && unset CRAFT_PROJECT_ROOT && CLAUDE_ENV_FILE="$ENV_FILE" bash "$SCRIPTS_DIR/session-start.sh" 2>/dev/null)
set -e

# Nearest wins: should persist the child path
if [ -f "$ENV_FILE" ]; then
  PERSISTED=$(grep "CRAFT_PROJECT_ROOT" "$ENV_FILE" | sed 's/.*=//' | tr -d '"')
  if echo "$PERSISTED" | grep -q "apps/web"; then
    assert_eq "persists nearest (child) path" "child-path" "child-path"
  else
    assert_eq "should persist child (nearest .craft/) path" "child-path" "parent-path"
  fi
else
  assert_eq "env file created" "exists" "missing"
fi

rm -f "$ENV_FILE"
cleanup_test_dir
echo ""

# --- Summary ---
finish_tests
