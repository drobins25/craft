#!/bin/bash
# test-ci-suite-groups.sh — Guard: scripts/ci/run-suite-group.sh partitions the
# live test-file glob totally (no file uncovered) and exactly (no file in two
# groups). Both sides of every comparison are computed at run time - the glob
# here, the assignment there - so a drift between the runner and the universe
# shows up as a real diff, never a silently-passing assertion.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$ROOT/scripts/ci/run-suite-group.sh"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Detail: $2"; }

echo "=== test-ci-suite-groups.sh ==="
echo ""

# The universe, computed independently of the runner: the exact glob
# tests/run-all.sh iterates.
GLOB=$( (
  cd "$ROOT"
  for f in tests/test-*.sh hooks/scripts/__tests__/*.test.sh; do
    [ -f "$f" ] && echo "$f"
  done
) | sort )

LIST_ALL=$(bash "$RUNNER" --list-all)
ASSIGNED=$(echo "$LIST_ALL" | awk '{print $2}' | sort)

# Test 1: every file in the live glob is assigned to exactly one group
UNASSIGNED=$(comm -23 <(echo "$GLOB") <(echo "$ASSIGNED" | sort -u))
DOUBLED=$(echo "$ASSIGNED" | uniq -d)
EXTRA=$(comm -13 <(echo "$GLOB") <(echo "$ASSIGNED" | sort -u))
if [ -z "$UNASSIGNED" ] && [ -z "$DOUBLED" ] && [ -z "$EXTRA" ]; then
  pass "every file in the live glob is assigned to exactly one group ($(echo "$GLOB" | wc -l | tr -d ' ') files)"
else
  fail "partition is not exact" "unassigned: [$(echo "$UNASSIGNED" | tr '\n' ' ')] doubled: [$(echo "$DOUBLED" | tr '\n' ' ')] not-in-glob: [$(echo "$EXTRA" | tr '\n' ' ')]"
fi

# Test 2: the group list is exactly the five expected names
GROUPS_OUT=$(bash "$RUNNER" --list-groups)
EXPECTED_GROUPS="dashboard
hooks
lifecycle
flows
misc"
if [ "$GROUPS_OUT" = "$EXPECTED_GROUPS" ]; then
  pass "--list-groups prints exactly the five group names"
else
  fail "--list-groups output unexpected" "got: $(echo "$GROUPS_OUT" | tr '\n' ' ')"
fi

# Test 3: the dashboard group is exactly the tests/test-dashboard*.sh glob
DASH_GLOB=$( (cd "$ROOT" && for f in tests/test-dashboard*.sh; do [ -f "$f" ] && echo "$f"; done) | sort )
DASH_LIST=$(bash "$RUNNER" --list dashboard | sort)
if [ "$DASH_LIST" = "$DASH_GLOB" ]; then
  pass "dashboard group holds exactly the dashboard suites"
else
  fail "dashboard group mismatch" "got: $(echo "$DASH_LIST" | tr '\n' ' ')"
fi
if echo "$DASH_LIST" | grep -q '^tests/test-dashboard-template\.sh$' && echo "$DASH_LIST" | grep -q '^tests/test-dashboard\.sh$'; then
  pass "dashboard group names the template and builder suites"
else
  fail "dashboard group missing a known member" "got: $(echo "$DASH_LIST" | tr '\n' ' ')"
fi

# Test 4: the hooks group is exactly the hook-script tests
HOOKS_GLOB=$( (cd "$ROOT" && for f in hooks/scripts/__tests__/*.test.sh; do [ -f "$f" ] && echo "$f"; done) | sort )
HOOKS_LIST=$(bash "$RUNNER" --list hooks | sort)
if [ "$HOOKS_LIST" = "$HOOKS_GLOB" ]; then
  pass "hooks group holds only the hook-script tests ($(echo "$HOOKS_GLOB" | wc -l | tr -d ' ') files)"
else
  fail "hooks group mismatch" "got: $(echo "$HOOKS_LIST" | tr '\n' ' ')"
fi

# Test 5: a group with a failing member exits non-zero and names that file
FIXTURE=$(mktemp -d)
cleanup_fixture() { rm -rf "$FIXTURE"; }
trap cleanup_fixture EXIT
mkdir -p "$FIXTURE/tests"
cat > "$FIXTURE/tests/test-zz-deliberate-fail.sh" <<'EOF'
#!/bin/bash
echo "this fixture test always fails"
exit 3
EOF
set +e
OUT=$(CRAFT_SUITE_ROOT="$FIXTURE" bash "$RUNNER" misc 2>&1)
RC=$?
set -e
if [ "$RC" -eq 3 ] && echo "$OUT" | grep -q "FAIL: tests/test-zz-deliberate-fail.sh (exit 3)"; then
  pass "a failing member stops the group, names the file, and propagates its exit code"
else
  fail "failure path wrong" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi
cleanup_fixture
trap - EXIT

# Test 6: an unknown group name exits 2 with a usage line
set +e
OUT=$(bash "$RUNNER" no-such-group 2>&1)
RC=$?
set -e
if [ "$RC" -eq 2 ] && echo "$OUT" | grep -q "usage:" && echo "$OUT" | grep -q "misc"; then
  pass "unknown group exits 2 with a usage line naming the groups"
else
  fail "unknown-group path wrong" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
