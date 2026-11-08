#!/bin/bash
# test-ci-annotate-check.sh - Tests for scripts/ci/annotate-check.sh
#
# The skip paths run on any machine. The Chrome-dependent assertions run only
# when a Chrome binary is present; on a browser-less machine they pass as
# SKIPs, because the harness itself skips legibly. On GitHub they run only in
# the annotate-browser job (CRAFT_CI_LIVE=1), which also sets
# CRAFT_CI_REQUIRE_BROWSER, so a missing browser fails there instead of skipping.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="$ROOT/scripts/ci/annotate-check.sh"
PROBE="$ROOT/scripts/ci/annotate-probe.mjs"
# The number of asserts the probe makes; the harness keeps its own copy in ASSERT_COUNT.
ASSERT_COUNT=18

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Detail: $2"; return 0; }

echo "=== test-ci-annotate-check.sh ==="
echo ""

tmp_path_from() { echo "$1" | grep -o 'annotate fixture root: .*' | sed 's/^annotate fixture root: //' | head -1; }

# Test 1: no Chrome found - exits 0 with a SKIP line naming what it looked for
set +e
OUT=$(env -u CRAFT_CI_REQUIRE_BROWSER CRAFT_CI_CHROME=/nonexistent-chrome-for-test bash "$HARNESS" 2>&1)
RC=$?
set -e
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SKIP: no Chrome binary found"; then
  pass "no Chrome present: exits 0 with a SKIP line naming what it looked for"
else
  fail "Chrome SKIP path wrong" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

# Test 1b: a required run with no Chrome fails loudly instead of skipping
set +e
OUT=$(CRAFT_CI_REQUIRE_BROWSER=1 CRAFT_CI_CHROME=/nonexistent-chrome-for-test bash "$HARNESS" 2>&1)
RC=$?
set -e
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q "^FAIL: no Chrome binary found" && ! echo "$OUT" | grep -q "^SKIP"; then
  pass "CRAFT_CI_REQUIRE_BROWSER=1 and no Chrome: exits 1 with a FAIL line"
else
  fail "required-browser Chrome path wrong" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

# Test 2: no node found - exits 0 with a SKIP line (needs a Chrome to get past
# the first skip, so a stand-in executable is enough: the node skip comes first)
STANDIN="$(mktemp)"
chmod +x "$STANDIN"
set +e
OUT=$(env -u CRAFT_CI_REQUIRE_BROWSER CRAFT_CI_CHROME="$STANDIN" CRAFT_CI_NODE=/nonexistent-node-for-test bash "$HARNESS" 2>&1)
RC=$?
set -e
set +e
OUT_REQ=$(CRAFT_CI_REQUIRE_BROWSER=1 CRAFT_CI_CHROME="$STANDIN" CRAFT_CI_NODE=/nonexistent-node-for-test bash "$HARNESS" 2>&1)
RC_REQ=$?
set -e
rm -f "$STANDIN"
if [ "$RC_REQ" -eq 1 ] && echo "$OUT_REQ" | grep -q "^FAIL: no node binary found"; then
  pass "CRAFT_CI_REQUIRE_BROWSER=1 and no node: exits 1 with a FAIL line"
else
  fail "required-browser node path wrong" "rc=$RC_REQ out: $(echo "$OUT_REQ" | tr '\n' ' ')"
fi
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^SKIP: no node binary found"; then
  pass "no node present: exits 0 with a SKIP line naming what it looked for"
else
  fail "node SKIP path wrong" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
fi

# The probe runs the page in real time: it never calls a frame callback itself
# and never runs under an artificial clock.
if [ -f "$PROBE" ] && ! grep -q 'virtual-time' "$PROBE" "$HARNESS" \
  && ! grep -q 'Emulation.setVirtualTimePolicy' "$PROBE" \
  && ! grep -q 'file://' "$HARNESS" && grep -q 'ThreadingHTTPServer(("127.0.0.1"' "$HARNESS"; then
  pass "the probe uses no virtual time and the fixture site is served over http"
else
  fail "probe uses virtual time or the fixture site is not served over http" "probe: $PROBE"
fi

# The harness and the probe agree on how many asserts exist, and the two new ones are present.
HARNESS_COUNT="$(sed -n 's/^ASSERT_COUNT=\([0-9]*\)$/\1/p' "$HARNESS" | head -1)"
if [ "$HARNESS_COUNT" = "$ASSERT_COUNT" ]; then
  pass "the harness expects $ASSERT_COUNT asserts from one ASSERT_COUNT line"
else
  fail "the harness ASSERT_COUNT disagrees with this test" "harness: '$HARNESS_COUNT' test: $ASSERT_COUNT"
fi
if grep -q "await step(14," "$PROBE" && grep -q "await step(15," "$PROBE" && grep -q "await step(16," "$PROBE"; then
  pass "the probe makes asserts 14, 15 and 16"
else
  fail "the probe is missing assert 14, 15 or 16"
fi
if grep -q "await step(17," "$PROBE" && grep -q "await step(18," "$PROBE" \
  && grep -q 'host-resolver-rules=MAP external.test 127.0.0.1' "$PROBE"; then
  pass "the probe makes asserts 17 and 18, the second through a host-resolver map"
else
  fail "the probe is missing assert 17 or 18 or the host-resolver map"
fi
if grep -q 'CRAFT_ANNOTATE_BOUNDARY_DIR="\$TMP/' "$HARNESS"; then
  pass "the harness keeps the boundary folder inside its temp root"
else
  fail "the harness does not set CRAFT_ANNOTATE_BOUNDARY_DIR inside its temp root"
fi
if grep -q 'md:flex w-1/2' "$HARNESS" && grep -q '<p class="lede">' "$HARNESS"; then
  pass "the fixture carries the utility-class section directly in a classless body"
else
  fail "the fixture section for assert 14 is missing"
fi
if grep -q "token" "$PROBE"; then
  pass "the probe reads the session token for its own listener reads"
else
  fail "the probe never reads the session token"
fi
# A cold CI runner can take more than 10s to start Chrome; the probe waits 30s for its port.
if grep -q 'const PORT_WAIT_POLLS = 300;' "$PROBE" && grep -q 'i < PORT_WAIT_POLLS' "$PROBE"; then
  pass "the probe waits 30s for Chrome's debugging port"
else
  fail "the probe gives Chrome less than 30s to open its debugging port" "probe: $PROBE"
fi

# Tests 4-: the live assertions, when a Chrome is available. Discovery mirrors
# the harness's own order.
have_chrome=0
if [ -n "${CRAFT_CI_CHROME:-}" ] && [ -x "${CRAFT_CI_CHROME:-}" ]; then
  have_chrome=1
else
  for c in google-chrome google-chrome-stable chromium chromium-browser; do
    command -v "$c" > /dev/null 2>&1 && have_chrome=1 && break
  done
  [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ] && have_chrome=1
fi

# On GitHub the live run belongs to the annotate-browser job alone, never to
# the suite group this file lands in.
if [ -n "${GITHUB_ACTIONS:-}" ] && [ "${CRAFT_CI_LIVE:-}" != "1" ]; then
  pass "with Chrome: the live run (SKIPPED - the annotate-browser job runs it)"
elif { [ "$have_chrome" -eq 1 ] && command -v node > /dev/null 2>&1; } \
  || [ "${CRAFT_CI_REQUIRE_BROWSER:-}" = "1" ]; then
  set +e
  OUT=$(bash "$HARNESS" 2>&1)
  RC=$?
  set -e
  if echo "$OUT" | grep -q '^SKIP:'; then
    pass "with Chrome: the harness skipped legibly (SKIPPED - $(echo "$OUT" | grep '^SKIP:' | head -1))"
    pass "with Chrome: the run's temp root and processes (SKIPPED)"
  else
    if [ "$RC" -eq 0 ]; then
      pass "with Chrome: the harness exits 0"
    else
      fail "the harness failed" "rc=$RC out: $(echo "$OUT" | tr '\n' ' ')"
    fi
    FIRST="$(echo "$OUT" | grep -o '^assert [0-9]* [A-Z]*' | head -1)"
    if [ "$FIRST" = "assert 1 OK" ]; then
      pass "with Chrome: assertion 1 is reported first and passes"
    else
      fail "assertion 1 is not first or did not pass" "first: '$FIRST'"
    fi
    MISSING=""
    for n in $(seq 1 "$ASSERT_COUNT"); do
      echo "$OUT" | grep -q "^assert $n OK: " || MISSING="$MISSING $n"
    done
    if [ -z "$MISSING" ]; then
      pass "with Chrome: assertions 1-$ASSERT_COUNT each report OK"
    else
      fail "assertions not OK:$MISSING" "out: $(echo "$OUT" | tr '\n' ' ')"
    fi
    TMP_USED="$(tmp_path_from "$OUT")"
    if [ -n "$TMP_USED" ] && [ ! -e "$TMP_USED" ]; then
      pass "the run's temp root is removed"
    else
      fail "temp root left behind or not reported" "path: '$TMP_USED'"
    fi
    # Anything the run started carries its root in its command line.
    if [ -n "$TMP_USED" ] && ! ps -ax -o command= | grep -F -- "$TMP_USED" | grep -v grep > /dev/null; then
      pass "no listener, watch, server or Chrome from the run is alive"
    else
      fail "a process from the run is still alive" "$(ps -ax -o pid=,command= | grep -F -- "$TMP_USED" | grep -v grep | head -3)"
    fi
  fi
else
  pass "with Chrome: assertion 1 first (SKIPPED - no Chrome or node on this machine)"
  pass "with Chrome: assertions 1-$ASSERT_COUNT report OK (SKIPPED - no Chrome or node on this machine)"
  pass "with Chrome: temp root removed (SKIPPED - no Chrome or node on this machine)"
  pass "with Chrome: no process left alive (SKIPPED - no Chrome or node on this machine)"
fi

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
