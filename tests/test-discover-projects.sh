#!/bin/bash
# test-discover-projects.sh — Tests for discover-projects.sh
# Validates that filesystem scan excludes bare/rogue .craft/ directories
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-shadow.sh"

DISCOVER_SCRIPT="$SCRIPTS_DIR/discover-projects.sh"

# --- Tests ---

echo "=== test-discover-projects.sh ==="
echo ""

# Test 1: Bare .craft/ excluded from filesystem scan
begin_test "Filesystem scan excludes bare .craft/ without project.md or .global-state"

TEST_DIR=$(create_craft_with_rogue_shadow)
PROJECT_DIR="$TEST_DIR/project"

# discover-projects.sh uses git rev-parse, so we need a git repo
(cd "$PROJECT_DIR" && git init --quiet && git config user.email "test@test.com" && git config user.name "Test" && git add -A && git commit -m "init" --quiet) 2>/dev/null

# Run discover-projects.sh from within the git repo
RESULT=$(cd "$PROJECT_DIR" && source "$DISCOVER_SCRIPT" 2>/dev/null && discover_craft_projects)

# Should include parent project (has .global-state + project.md)
assert_contains "includes parent project" "project" "$RESULT"

# Should NOT include apps/web (bare .craft/ — no .global-state, no project.md)
assert_not_contains "excludes rogue apps/web" "apps/web" "$RESULT"

cleanup_test_dir
echo ""

# Test 2: Legitimate sub-project with .global-state IS included
begin_test "Legitimate sub-project with .global-state is included"

TEST_DIR=$(create_craft_with_shadow)
PROJECT_DIR="$TEST_DIR/project"

# Add project.md to parent so it's a proper project
cat > "$PROJECT_DIR/.craft/project.md" << 'EOF'
---
name: parent-project
type: ui
---
# Parent
EOF

# apps/web already has .global-state from create_craft_with_shadow
(cd "$PROJECT_DIR" && git init --quiet && git config user.email "test@test.com" && git config user.name "Test" && git add -A && git commit -m "init" --quiet) 2>/dev/null

RESULT=$(cd "$PROJECT_DIR" && source "$DISCOVER_SCRIPT" 2>/dev/null && discover_craft_projects)

# Should include both — parent AND apps/web (both have .global-state)
assert_contains "includes parent" "master" "$RESULT"
assert_contains "includes legitimate sub-project" "web" "$RESULT"

cleanup_test_dir
echo ""

# --- Summary ---
finish_tests
