#!/bin/bash
# test_helper.sh — Shared test infrastructure for Craft plugin tests
#
# Usage: source this at the top of every test file:
#   source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
#
# Provides:
#   - PASS/FAIL counters
#   - Assertion functions (assert_eq, assert_contains, assert_file_exists, etc.)
#   - Test lifecycle (begin_test, finish_tests)
#   - Cleanup helpers
#
# Fixture functions are in tests/fixtures/*.sh — source those separately as needed.

set -e

# --- Paths ---
TEST_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$TEST_HELPER_DIR/../hooks/scripts"
TEMPLATES_DIR="$TEST_HELPER_DIR/../templates"
PLUGIN_ROOT="$TEST_HELPER_DIR/.."

# --- Strict YAML readers ---
# A flat YAML file read by a real parser (PyYAML, else ruby's Psych) and printed as
# JSON, so a test can prove a value round-trips through a strict reader. Returns 127
# when neither parser is installed.

strict_json() {
  local file="$1"
  if python3 -c 'import yaml' 2>/dev/null; then
    python3 -c 'import json,sys,yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1], encoding="utf-8")), default=str))' "$file"
  elif command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -rjson -rdate -e 'puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), permitted_classes: [Date]))' "$file"
  else
    return 127
  fi
}

strict_get() { # strict_get <file> <key>
  strict_json "$1" | python3 -c 'import json,sys; sys.stdout.write(str(json.load(sys.stdin)[sys.argv[1]]))' "$2"
}

# --- Counters ---
PASS=0
FAIL=0
TEST_COUNT=0
CURRENT_TEST=""

# --- Test lifecycle ---

begin_test() {
  local desc="$1"
  TEST_COUNT=$((TEST_COUNT + 1))
  CURRENT_TEST="$desc"
  echo "Test $TEST_COUNT: $desc"
}

# --- Assertions ---

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_eq() {
  local desc="$1" unexpected="$2" actual="$3"
  if [ "$unexpected" != "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    should NOT equal: '$unexpected'"
    FAIL=$((FAIL + 1))
  fi
}

# Regex-based contains (grep -q)
assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected to contain: '$needle'"
    echo "    in: '$(echo "$haystack" | head -5)'"
    FAIL=$((FAIL + 1))
  fi
}

# Literal contains (grep -qF) — no regex interpretation
assert_contains_literal() {
  local desc="$1" needle="$2" haystack="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected to contain (literal): '$needle'"
    echo "    in: '$(echo "$haystack" | head -5)'"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if ! grep -q "$needle" <<< "$haystack"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    should NOT contain: '$needle'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1" file="$2"
  if [ -f "$file" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file not found: $file)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local desc="$1" file="$2"
  if [ ! -e "$file" ] && [ ! -L "$file" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file should not exist: $file)"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_exists() {
  local desc="$1" dir="$2"
  if [ -d "$dir" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (dir not found: $dir)"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_not_exists() {
  local desc="$1" dir="$2"
  if [ ! -d "$dir" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (dir should not exist: $dir)"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_code() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected exit code: $expected"
    echo "    actual exit code:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

# Assert a YAML frontmatter field exists and has expected value
# Reads between first and second --- delimiters
assert_yaml_field() {
  local desc="$1" field="$2" expected="$3" file="$4"
  local actual
  # Extract value from frontmatter (between first two --- lines)
  actual=$(sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep "^${field}:" | head -1 | sed "s/^${field}: *//" | tr -d '"' | tr -d "'")
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    field '$field' expected: '$expected'"
    echo "    actual: '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

# Assert a YAML frontmatter field exists (any value)
assert_yaml_field_exists() {
  local desc="$1" field="$2" file="$3"
  if sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null | grep -q "^${field}:"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (field '$field' not found in frontmatter of $file)"
    FAIL=$((FAIL + 1))
  fi
}

# Assert file content matches a line pattern
assert_file_contains() {
  local desc="$1" pattern="$2" file="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    pattern '$pattern' not found in $file"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_contains() {
  local desc="$1" pattern="$2" file="$3"
  if ! grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    pattern '$pattern' should NOT be in $file"
    FAIL=$((FAIL + 1))
  fi
}

# --- Cleanup ---

cleanup_test_dir() {
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}

# Create a fresh temp directory for a test
create_test_dir() {
  TEST_DIR=$(mktemp -d)
  echo "$TEST_DIR"
}

# --- Summary ---

finish_tests() {
  local test_name="${1:-$(basename "${BASH_SOURCE[1]}" .sh)}"
  echo ""
  echo "=== Results ($test_name): $PASS passed, $FAIL failed ==="
  if [ "$FAIL" -gt 0 ]; then
    exit 1
  fi
}
