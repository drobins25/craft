#!/bin/bash
# test-ci-browser-check.sh — Tests for scripts/ci/browser-check.sh
#
# The Chrome-dependent assertions run only when a Chrome binary is present;
# on a browser-less machine they pass as SKIPs, because the harness itself
# is designed to skip legibly (the CI job is non-blocking by decision). On
# GitHub they run only in the browser job (CRAFT_CI_LIVE=1).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="$ROOT/scripts/ci/browser-check.sh"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Detail: $2"; }

echo "=== test-ci-browser-check.sh ==="
echo ""

tmp_path_from() { echo "$1" | grep -o 'building fixture page in .*' | sed 's/^building fixture page in //' | head -1; }

# Test 1: the fixture build produces dashboard.html, graph.js and a non-empty
# records dir (the pre-Chrome half, runs on any machine)
set +e
OUT=$(bash "$HARNESS" --build-only 2>&1)
RC=$?
set -e
if [ "$RC" -eq 0 ] \
  && echo "$OUT" | grep -q "artifact OK: dashboard.html" \
  && echo "$OUT" | grep -q "artifact OK: graph/graph.js" \
  && echo "$OUT" | grep -q "artifact OK: graph/records/ is non-empty"; then
  pass "fixture build produces dashboard.html, graph.js and a non-empty records dir"
else
  fail "build-only run wrong" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

# Test 2: that build's temp directory is removed after the run
TMP_USED=$(tmp_path_from "$OUT")
if [ -n "$TMP_USED" ] && [ ! -e "$TMP_USED" ]; then
  pass "the temp directory is removed after a run ($TMP_USED)"
else
  fail "temp directory left behind or not reported" "path: '$TMP_USED'"
fi

# Test 3: the harness exits 0 with a SKIP line when no Chrome is found
set +e
OUT=$(CRAFT_CI_CHROME=/nonexistent-chrome-for-test bash "$HARNESS" 2>&1)
RC=$?
set -e
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SKIP: no Chrome binary found"; then
  pass "no Chrome present: exits 0 with a SKIP line naming what it looked for"
else
  fail "SKIP path wrong" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

# The probe lets the page run its own loop in real time: it never calls the
# page's frame callback itself and never runs under an artificial clock, the
# two things that once stacked ~150 render loops and made the old probe
# measure its own artifact.
PROBE="$ROOT/scripts/ci/browser-probe.mjs"
if [ -f "$PROBE" ] && ! grep -q '\.tick(' "$PROBE" && ! grep -q 'virtual-time' "$PROBE" "$HARNESS"; then
  pass "the probe never drives the page's tick and never uses virtual time"
else
  fail "the probe drives tick or uses virtual time" "probe: $PROBE"
fi
# Chrome's helper processes must not outlive the probe and keep writing into the
# profile dir the caller deletes: own process group, group kill, wait for exit.
if grep -q "detached: true" "$PROBE" && grep -q "process.kill(-chrome.pid, 'SIGKILL')" "$PROBE" \
  && grep -q "chrome.once('exit'" "$PROBE"; then
  pass "the probe runs Chrome in its own process group, kills the group, and waits for exit"
else
  fail "the probe does not reap Chrome's whole process group" "probe: $PROBE"
fi
# A cold CI runner can take more than 10s to start Chrome; the probe waits 30s for its port.
if grep -q 'const PORT_WAIT_POLLS = 300;' "$PROBE" && grep -q 'i < PORT_WAIT_POLLS' "$PROBE"; then
  pass "the probe waits 30s for Chrome's debugging port"
else
  fail "the probe gives Chrome less than 30s to open its debugging port" "probe: $PROBE"
fi

# With no node found, the full run exits 0 with a SKIP line, like a missing Chrome
set +e
OUT=$(CRAFT_CI_NODE=/nonexistent-node-for-test bash "$HARNESS" 2>&1)
RC=$?
set -e
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SKIP: no node binary found"; then
  pass "no node present: exits 0 with a SKIP line naming what it looked for"
else
  fail "node SKIP path wrong" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

# Tests 4-6: the three live assertions, when a Chrome is available.
# Discovery mirrors the harness's own order.
have_chrome=0
if [ -n "${CRAFT_CI_CHROME:-}" ] && [ -x "${CRAFT_CI_CHROME:-}" ]; then
  have_chrome=1
else
  for c in google-chrome google-chrome-stable chromium chromium-browser; do
    command -v "$c" > /dev/null 2>&1 && have_chrome=1 && break
  done
  [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ] && have_chrome=1
fi

# On GitHub the live run belongs to the non-blocking browser job alone, never
# to the required suite group this file lands in.
if [ -n "${GITHUB_ACTIONS:-}" ] && [ "${CRAFT_CI_LIVE:-}" != "1" ]; then
  pass "with Chrome: the live run (SKIPPED - the browser job runs it)"
elif [ "$have_chrome" -eq 1 ]; then
  set +e
  OUT=$(bash "$HARNESS" 2>&1)
  RC=$?
  set -e
  if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q "assert 1 OK: CRAFT_GRAPH.nodes loaded"; then
    pass "with Chrome: the page reports a non-zero node count"
  else
    fail "assertion 1 (data loaded) did not pass" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
  fi
  if echo "$OUT" | grep -q "assert 2 OK: GraphInstance.sim consumed all"; then
    pass "with Chrome: the view's node count matches the graph's"
  else
    fail "assertion 2 (view consumed data) did not pass" "out: $(echo "$OUT" | tr '\n' ' ')"
  fi
  if echo "$OUT" | grep -q "assert 3 OK: selection rendered the card"; then
    pass "with Chrome: selecting the first node renders its label in the panel title"
  else
    fail "assertion 3 (card rendered) did not pass" "out: $(echo "$OUT" | tr '\n' ' ')"
  fi
  if echo "$OUT" | grep -q "assert 4 OK: the parse produced real elements" \
    || echo "$OUT" | grep -q "assert 4 SKIP: probed node has no summary"; then
    pass "with Chrome: the parse produced real elements in the panel (or SKIPped legibly)"
  else
    fail "assertion 4 (parse produced elements) did not pass or SKIP" "out: $(echo "$OUT" | tr '\n' ' ')"
  fi
  if echo "$OUT" | grep -q "assert 7 OK: the render loop parked with a node pinned"; then
    pass "with Chrome: the render loop parks after a drag with the node pinned"
  else
    fail "assertion 7 (loop parks after drag) did not pass" "out: $(echo "$OUT" | tr '\n' ' ')"
  fi
  if echo "$OUT" | grep -q "assert 9 OK: every card carries a leader"; then
    pass "with Chrome: every insight card carries a finite leader"
  else
    fail "assertion 9 (finite leaders) did not pass" "out: $(echo "$OUT" | tr '\n' ' ')"
  fi
  if echo "$OUT" | grep -q "assert 10 OK: the page runs one render loop"; then
    pass "with Chrome: the page runs one render loop"
  else
    fail "assertion 10 (one render loop) did not pass" "out: $(echo "$OUT" | tr '\n' ' ')"
  fi
  # And the full run's temp dir is gone too
  TMP_USED=$(tmp_path_from "$OUT")
  if [ -n "$TMP_USED" ] && [ ! -e "$TMP_USED" ]; then
    pass "full run's temp directory is removed"
  else
    fail "full run left its temp directory" "path: '$TMP_USED'"
  fi
else
  pass "with Chrome: node count (SKIPPED - no Chrome on this machine)"
  pass "with Chrome: view/graph count match (SKIPPED - no Chrome on this machine)"
  pass "with Chrome: card renders on selection (SKIPPED - no Chrome on this machine)"
  pass "with Chrome: the parse produced real elements (SKIPPED - no Chrome on this machine)"
  pass "full run temp cleanup (SKIPPED - no Chrome on this machine)"
  pass "loop parks after drag (SKIPPED - no Chrome on this machine)"
  pass "finite leaders (SKIPPED - no Chrome on this machine)"
  pass "one render loop (SKIPPED - no Chrome on this machine)"
fi

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
