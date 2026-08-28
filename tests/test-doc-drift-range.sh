#!/bin/bash
# test-doc-drift-range.sh — Tests for check-doc-drift.sh's opt-in --range mode
# (check 9: a feat: commit in the range needs a CHANGELOG.md change).
#
# Range scenarios run in a temp `git clone --local` of this repo with seeded
# commits - the live repo's history is fixed and cannot manufacture a range.
# Assertions are on the FINDING TEXT, not the exit code: other findings can
# legitimately exist in a clone, so an exit-code assertion would be ambiguous.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKER="scripts/check-doc-drift.sh"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Detail: $2"; }

echo "=== test-doc-drift-range.sh ==="
echo ""

FEAT_FINDING="feat commit(s) about to push with no CHANGELOG.md entry"

# Test 1: no-argument invocation still exits 0 on this clean tree
# (the regression guard for the two existing argument-free callers)
set +e
OUT=$(bash "$ROOT/$CHECKER" 2>&1)
RC=$?
set -e
if [ "$RC" -eq 0 ]; then
  pass "no-argument invocation still exits 0 on the live tree"
else
  fail "no-argument invocation regressed" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

CLONE=$(mktemp -d)/clone
cleanup() { rm -rf "$(dirname "$CLONE")"; }
trap cleanup EXIT
git clone --local --quiet "$ROOT" "$CLONE" 2>/dev/null
# The clone checks out committed HEAD - make sure the checker under test is
# the working-tree version, not whatever the last commit carried.
cp "$ROOT/scripts/check-doc-drift.sh" "$CLONE/scripts/check-doc-drift.sh"

cgit() { git -C "$CLONE" -c user.name=test -c user.email=test@example.invalid "$@"; }
run_range() {
  set +e
  OUT=$(cd "$CLONE" && bash "$CHECKER" --range "$1" 2>&1)
  RC=$?
  set -e
}

# Test 2: a feat: commit in the range with no CHANGELOG change produces a
# [changelog] finding naming it
cgit commit --allow-empty -qm "feat: seeded-no-notes"
run_range "HEAD~1..HEAD"
if echo "$OUT" | grep -q "\[changelog\] $FEAT_FINDING" && echo "$OUT" | grep -q "feat: seeded-no-notes"; then
  pass "feat commit with no CHANGELOG change in range produces the [changelog] finding naming it"
else
  fail "feat-without-changelog not caught" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

# Test 3: a feat: commit in the range WITH a CHANGELOG.md change produces no
# such finding
echo "" >> "$CLONE/CHANGELOG.md"
cgit add CHANGELOG.md
cgit commit -qm "feat: seeded-with-notes"
run_range "HEAD~1..HEAD"
if ! echo "$OUT" | grep -q "$FEAT_FINDING"; then
  pass "feat commit with a CHANGELOG change in range produces no feat-changelog finding"
else
  fail "false positive on feat-with-changelog" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

# Test 4: a range containing no feat: commits produces no such finding
cgit commit --allow-empty -qm "chore: seeded-not-a-feature"
run_range "HEAD~1..HEAD"
if ! echo "$OUT" | grep -q "$FEAT_FINDING"; then
  pass "range with no feat commits produces no feat-changelog finding"
else
  fail "false positive on non-feat range" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

# Test 5: an unresolvable --range value exits 2 naming the value
run_range "no-such-ref-xyz..HEAD"
if [ "$RC" -eq 2 ] && echo "$OUT" | grep -q "no-such-ref-xyz..HEAD"; then
  pass "unresolvable --range exits 2 naming the value"
else
  fail "unresolvable range did not exit 2" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

# Test 6: a malformed --range value (no dots) exits 2 naming the value
run_range "just-one-ref"
if [ "$RC" -eq 2 ] && echo "$OUT" | grep -q "just-one-ref"; then
  pass "malformed --range exits 2 naming the value"
else
  fail "malformed range did not exit 2" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
