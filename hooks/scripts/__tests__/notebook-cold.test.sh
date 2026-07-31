#!/bin/bash
# notebook-cold.test.sh — Behavioral tests for cold notebook capture and list
#
# Usage: bash hooks/scripts/__tests__/notebook-cold.test.sh
#
# Runs the real notebook-capture.sh / notebook-list.sh in temp dirs with no
# initialized project, asserting the cold anchor (git toplevel, else PWD,
# never a subdirectory), the loud non-git fallback notice, and that a bare
# cold .craft/ does not arm the write gate against source edits.

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$TESTS_DIR")"
CAPTURE="$SCRIPTS_DIR/notebook-capture.sh"
LIST="$SCRIPTS_DIR/notebook-list.sh"
GATE="$SCRIPTS_DIR/check-write-permission.py"

# ── Helpers ──────────────────────────────────────────────────────

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  TOTAL=$((TOTAL + 1))
  echo "  ✓ $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  TOTAL=$((TOTAL + 1))
  echo "  ✗ $1"
  if [ -n "${2:-}" ]; then
    echo "    Expected: $2"
    echo "    Got:      $3"
  fi
}

assert_contains() {
  local output="$1" expected="$2" label="$3"
  if echo "$output" | grep -qF -- "$expected"; then
    pass "$label"
  else
    fail "$label" "$expected" "(not found in output)"
  fi
}

assert_not_contains() {
  local output="$1" unexpected="$2" label="$3"
  if echo "$output" | grep -qF -- "$unexpected"; then
    fail "$label" "(should not contain)" "$unexpected"
  else
    pass "$label"
  fi
}

# Run a notebook script from inside a directory with a scrubbed craft
# environment, capturing stdout+stderr. Exit status stored in RUN_EXIT.
RUN_EXIT=0
run_cold_in() {
  local dir="$1"
  shift
  local out
  set +e
  out=$(cd "$dir" && env -u CRAFT_PROJECT_ROOT -u PROJECT_ROOT -u CRAFT_PROJECT_NAME -u CRAFT_MULTI_PROJECT "$@" 2>&1)
  RUN_EXIT=$?
  set -e
  echo "$out"
}

# ── Test 1: Cold capture creates the notebook file in a git repo ──

echo ""
echo "Test 1: Cold capture creates the notebook file"

GIT_DIR=$(mktemp -d)
(cd "$GIT_DIR" && git init -q)
output=$(run_cold_in "$GIT_DIR" bash "$CAPTURE" todo "remember the cold thing")

if [ "$RUN_EXIT" -eq 0 ]; then
  pass "Capture exits 0 cold"
else
  fail "Capture exits 0 cold" "0" "$RUN_EXIT (output: $output)"
fi
assert_not_contains "$output" "Could not resolve project root" "No root-resolution error"
if ls "$GIT_DIR/.craft/notebook/todos/"*.md >/dev/null 2>&1; then
  pass "Todo file exists under <root>/.craft/notebook/todos/"
else
  fail "Todo file exists under <root>/.craft/notebook/todos/" "a .md file" "(none found)"
fi

# ── Test 2: Cold capture anchors to git toplevel, not a subdir ────

echo ""
echo "Test 2: Cold capture from a nested subdir anchors to the git toplevel"

mkdir -p "$GIT_DIR/deep/nested/dir"
output=$(run_cold_in "$GIT_DIR/deep/nested/dir" bash "$CAPTURE" idea "an idea from deep down")

if [ -d "$GIT_DIR/deep/nested/dir/.craft" ]; then
  fail "No .craft/ created in the subdirectory" "(no .craft in subdir)" "(one was created)"
else
  pass "No .craft/ created in the subdirectory"
fi
if ls "$GIT_DIR/.craft/notebook/ideas/"*.md >/dev/null 2>&1; then
  pass "Idea landed at the repo-root .craft/notebook/"
else
  fail "Idea landed at the repo-root .craft/notebook/" "a .md file at repo root" "(none found)"
fi

# ── Test 3: Cold list reads back a cold-captured note ─────────────

echo ""
echo "Test 3: Cold list reads back cold-captured entries"

output=$(run_cold_in "$GIT_DIR" bash "$LIST")
assert_contains "$output" "remember-the-cold-thing" "List includes the captured todo's slug"

output=$(run_cold_in "$GIT_DIR/deep/nested/dir" bash "$LIST")
assert_contains "$output" "an-idea-from-deep-down" "List from a subdir resolves the same root"

# ── Test 4: Write gate allows source edits beside a bare cold .craft ──

echo ""
echo "Test 4: Bare cold .craft/ does not arm the write gate"

gate_json="{\"tool_name\": \"Write\", \"tool_input\": {\"file_path\": \"$GIT_DIR/foo.ts\"}, \"cwd\": \"$GIT_DIR\"}"
set +e
gate_out=$(cd "$GIT_DIR" && echo "$gate_json" | env -u CRAFT_PROJECT_ROOT python3 "$GATE" 2>&1)
gate_exit=$?
set -e

if [ "$gate_exit" -eq 0 ]; then
  pass "Gate exits 0"
else
  fail "Gate exits 0" "0" "$gate_exit"
fi
assert_not_contains "$gate_out" '"permissionDecision": "deny"' "Gate does not deny a source write"

rm -rf "$GIT_DIR"

# ── Test 5: Non-git fallback goes to PWD and is announced ─────────

echo ""
echo "Test 5: Outside a git repo, capture falls back to PWD and says so"

NONGIT_DIR=$(mktemp -d)
output=$(run_cold_in "$NONGIT_DIR" bash "$CAPTURE" todo "note with no repo")

if [ "$RUN_EXIT" -eq 0 ]; then
  pass "Capture exits 0 outside a git repo"
else
  fail "Capture exits 0 outside a git repo" "0" "$RUN_EXIT (output: $output)"
fi
if ls "$NONGIT_DIR/.craft/notebook/todos/"*.md >/dev/null 2>&1; then
  pass "Todo file created under PWD/.craft/notebook/"
else
  fail "Todo file created under PWD/.craft/notebook/" "a .md file" "(none found)"
fi
assert_contains "$output" "not a git repo" "Non-git fallback is announced, not silent"

rm -rf "$NONGIT_DIR"

# ── Summary ──────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $TOTAL total"
echo "════════════════════════════════════════"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

exit 0
