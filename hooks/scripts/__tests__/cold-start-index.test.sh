#!/bin/bash
# cold-start-index.test.sh — Behavioral tests for the inject hook's cold path
#
# Usage: bash hooks/scripts/__tests__/cold-start-index.test.sh
#
# Runs the real inject-craft-context.sh in temp dirs covering three states:
# cold (no .craft/), bare .craft/ (dirs but no state files), and warm
# (.global-state present). Asserts the cold-start index is emitted only for
# the two cold states and the warm path is unaffected.

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$(dirname "$TESTS_DIR")/inject-craft-context.sh"

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

# Run the hook from inside a directory with a scrubbed craft environment,
# capturing stdout. Exit status is stored in HOOK_EXIT.
HOOK_EXIT=0
run_hook_in() {
  local dir="$1"
  local out
  set +e
  out=$(cd "$dir" && env -u CRAFT_PROJECT_ROOT -u PROJECT_ROOT -u CRAFT_PROJECT_NAME -u CRAFT_MULTI_PROJECT bash "$HOOK" 2>/dev/null)
  HOOK_EXIT=$?
  set -e
  echo "$out"
}

# ── Test 1: Cold repo (no .craft/) emits the cold index ───────────

echo ""
echo "Test 1: Cold repo (no .craft/) emits the cold index"

COLD_DIR=$(mktemp -d)
output=$(run_hook_in "$COLD_DIR")

assert_contains "$output" "v1|craft-cold-start-index" "Cold index header present"
if [ "$HOOK_EXIT" -eq 0 ]; then
  pass "Hook exits 0 on the cold path"
else
  fail "Hook exits 0 on the cold path" "0" "$HOOK_EXIT"
fi

# ── Test 2: Cold repo does NOT emit the full orchestration index ──

echo ""
echo "Test 2: Cold repo does not emit the full orchestration index"

assert_not_contains "$output" "v1|craft-orchestration-index" "Full index absent on cold path"

# ── Test 3: Cold index carries the init-routing rule ──────────────

echo ""
echo "Test 3: Cold index carries the init-routing rule"

assert_contains "$output" "offer /craft:init FIRST" "Story-shaped work routes to init first"
assert_contains "$output" "never auto-run /craft:init" "Init is offered, never auto-run"

rm -rf "$COLD_DIR"

# ── Test 4: Bare .craft/ (no state files) still emits cold index ──

echo ""
echo "Test 4: Bare .craft/ (cold capture shape) still emits the cold index"

BARE_DIR=$(mktemp -d)
mkdir -p "$BARE_DIR/.craft/notebook/todos"
output=$(run_hook_in "$BARE_DIR")

assert_contains "$output" "v1|craft-cold-start-index" "Cold index survives a bare .craft/"
assert_not_contains "$output" "v1|craft-orchestration-index" "Full index still absent with bare .craft/"

rm -rf "$BARE_DIR"

# ── Test 5: Warm repo emits the orchestration index, not cold ─────

echo ""
echo "Test 5: Warm repo (.global-state present) is unchanged"

WARM_DIR=$(mktemp -d)
mkdir -p "$WARM_DIR/.craft"
cat > "$WARM_DIR/.craft/.global-state" << 'STATE'
LAST_ACTIVITY="2026-01-01T00:00:00Z"
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
STATE
output=$(run_hook_in "$WARM_DIR")

assert_contains "$output" "v1|craft-orchestration-index" "Warm path emits the full index"
assert_not_contains "$output" "v1|craft-cold-start-index" "Cold index absent on warm path"
assert_contains "$output" "[Craft plugin root:" "Warm path still emits the plugin-root line"
if [ "$HOOK_EXIT" -eq 0 ]; then
  pass "Hook exits 0 on the warm path"
else
  fail "Hook exits 0 on the warm path" "0" "$HOOK_EXIT"
fi

rm -rf "$WARM_DIR"

# ── Summary ──────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $TOTAL total"
echo "════════════════════════════════════════"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

exit 0
