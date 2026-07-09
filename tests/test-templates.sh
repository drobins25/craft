#!/bin/bash
# test-templates.sh — Tests for story templates
# Validates templates have correct fields, quoting, and produce valid YAML
#
# REGRESSIONS (story 8): tests 1-2 MUST FAIL against current codebase

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

BACKLOG_TEMPLATE="$TEMPLATES_DIR/story-backlog.md"
FULL_TEMPLATE="$TEMPLATES_DIR/story-full.md"

# --- Tests ---

echo "=== test-templates.sh ==="
echo ""

# ---- REGRESSION TEST 1 (Story 8) ----
# Backlog template is missing current_chunk: field
begin_test "REGRESSION: Backlog template has current_chunk field"

BACKLOG_CONTENT=$(cat "$BACKLOG_TEMPLATE")
FRONTMATTER=$(sed -n '/^---$/,/^---$/p' "$BACKLOG_TEMPLATE")

if echo "$FRONTMATTER" | grep -q "^current_chunk:"; then
  echo "  PASS: current_chunk: found in backlog template frontmatter"
  PASS=$((PASS + 1))
else
  echo "  FAIL: current_chunk: NOT found in backlog template frontmatter"
  echo "    This field is present in story-full.md but missing from story-backlog.md"
  FAIL=$((FAIL + 1))
fi

echo ""

# ---- REGRESSION TEST 2 (Story 8) ----
# Both templates have unquoted title: {{STORY_TITLE}} instead of title: "{{STORY_TITLE}}"
begin_test "REGRESSION: Template titles are quoted"

BACKLOG_TITLE_LINE=$(grep "^title:" "$BACKLOG_TEMPLATE" | head -1)
FULL_TITLE_LINE=$(grep "^title:" "$FULL_TEMPLATE" | head -1)

# Check backlog template title is quoted
if echo "$BACKLOG_TITLE_LINE" | grep -qF 'title: "{{STORY_TITLE}}"'; then
  echo "  PASS: backlog template title is quoted"
  PASS=$((PASS + 1))
else
  echo "  FAIL: backlog template title is NOT quoted"
  echo "    expected: title: \"{{STORY_TITLE}}\""
  echo "    actual:   $BACKLOG_TITLE_LINE"
  FAIL=$((FAIL + 1))
fi

# Check full template title is quoted
if echo "$FULL_TITLE_LINE" | grep -qF 'title: "{{STORY_TITLE}}"'; then
  echo "  PASS: full template title is quoted"
  PASS=$((PASS + 1))
else
  echo "  FAIL: full template title is NOT quoted"
  echo "    expected: title: \"{{STORY_TITLE}}\""
  echo "    actual:   $FULL_TITLE_LINE"
  FAIL=$((FAIL + 1))
fi

echo ""

# Test 3: Backlog template renders valid YAML with clean values
begin_test "Backlog template renders valid YAML with clean values"
TEST_DIR=$(create_test_dir)

# Render template with clean values (no special chars)
sed "s|{{STORY_NAME}}|test-story|g; s|{{STORY_TITLE}}|Test Story|g; s|{{DATE}}|2026-02-14|g; s|{{PRIORITY}}|medium|g; s|{{STORY_DESCRIPTION}}|A test story|g" \
  "$BACKLOG_TEMPLATE" > "$TEST_DIR/rendered.md"

# Extract frontmatter and check it's parseable as YAML-like key:value
RENDERED_FM=$(sed -n '2,/^---$/p' "$TEST_DIR/rendered.md" | grep -v "^---$")

# Each line should be key: value format (no broken YAML)
BROKEN_LINES=$(echo "$RENDERED_FM" | grep -v "^$" | grep -v "^[a-z_]*:" | head -5)
if [ -z "$BROKEN_LINES" ]; then
  echo "  PASS: all frontmatter lines are key: value format"
  PASS=$((PASS + 1))
else
  echo "  FAIL: found non key:value lines in rendered frontmatter"
  echo "    broken: $BROKEN_LINES"
  FAIL=$((FAIL + 1))
fi

cleanup_test_dir
echo ""

# Test 4: Full template renders valid YAML with clean values
begin_test "Full template renders valid YAML with clean values"
TEST_DIR=$(create_test_dir)

sed "s|{{STORY_NAME}}|test-story|g; s|{{STORY_TITLE}}|Test Story|g; s|{{DATE}}|2026-02-14|g; s|{{PRIORITY}}|medium|g; s|{{CYCLE_NAME}}|test-cycle|g; s|{{STORY_NUMBER}}|1|g; s|{{STORY_DESCRIPTION}}|A test story|g" \
  "$FULL_TEMPLATE" > "$TEST_DIR/rendered.md"

RENDERED_FM=$(sed -n '2,/^---$/p' "$TEST_DIR/rendered.md" | grep -v "^---$")
BROKEN_LINES=$(echo "$RENDERED_FM" | grep -v "^$" | grep -v "^[a-z_]*:" | head -5)
if [ -z "$BROKEN_LINES" ]; then
  echo "  PASS: all frontmatter lines are key: value format"
  PASS=$((PASS + 1))
else
  echo "  FAIL: found non key:value lines in rendered frontmatter"
  echo "    broken: $BROKEN_LINES"
  FAIL=$((FAIL + 1))
fi

cleanup_test_dir
echo ""

# Test 5: Template with colon in title produces valid YAML
begin_test "Template with colon in title produces valid YAML"
TEST_DIR=$(create_test_dir)

# Render with a title containing a colon — this is the common case that breaks
sed "s|{{STORY_NAME}}|fix-auth|g; s|{{STORY_TITLE}}|Fix: broken authentication|g; s|{{DATE}}|2026-02-14|g; s|{{PRIORITY}}|high|g; s|{{STORY_DESCRIPTION}}|Fix it|g" \
  "$BACKLOG_TEMPLATE" > "$TEST_DIR/rendered.md"

# The title line should be properly quoted to handle the colon
TITLE_LINE=$(grep "^title:" "$TEST_DIR/rendered.md" | head -1)

# In valid YAML, a value with a colon must be quoted
# Check if the value portion is quoted (title: "Fix: broken authentication")
if echo "$TITLE_LINE" | grep -qE '^title: ".*"$' || echo "$TITLE_LINE" | grep -qE "^title: '.*'$"; then
  echo "  PASS: title with colon is properly quoted"
  PASS=$((PASS + 1))
else
  echo "  FAIL: title with colon is NOT quoted — will break YAML parsing"
  echo "    actual: $TITLE_LINE"
  echo "    expected: title: \"Fix: broken authentication\""
  FAIL=$((FAIL + 1))
fi

cleanup_test_dir
echo ""

# Test 6: quality.yaml template gates carry no command fields
begin_test "quality.yaml template gates carry no command fields"

QUALITY_TEMPLATE="$TEMPLATES_DIR/craft/quality.yaml"

# Extract the gates: block (from "gates:" to the next top-level key), comments stripped
GATES_BLOCK=$(awk '/^gates:/{flag=1; next} /^[a-z_]+:/{flag=0} flag' "$QUALITY_TEMPLATE" | grep -v '^[[:space:]]*#')

if echo "$GATES_BLOCK" | grep -q "command:"; then
  echo "  FAIL: template gates carry a command: field — commands must only enter quality.yaml through the verified path"
  echo "    found: $(echo "$GATES_BLOCK" | grep "command:" | head -3)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: no command: fields in template gates"
  PASS=$((PASS + 1))
fi

echo ""

# --- Summary ---
finish_tests
