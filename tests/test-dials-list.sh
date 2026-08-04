#!/bin/bash
# test-dials-list.sh — Behavior tests for dials-list.sh
# Usage: bash tests/test-dials-list.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$SCRIPT_DIR/../hooks/scripts/dials-list.sh"
CAP="$SCRIPT_DIR/../hooks/scripts/dials-capture.sh"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Expected: $2"; [ -n "${3:-}" ] && echo "    Got:      $3"; }

fresh_root() {
  ROOT=$(mktemp -d)
  export CRAFT_PROJECT_ROOT="$ROOT"
}

echo "=== test-dials-list.sh ==="
echo ""

echo "-- Test: no dials directory is silent and exits 0 --"
fresh_root
set +e
OUT=$(bash "$LIST")
RC=$?
set -e
[ "$RC" -eq 0 ] && pass "exit 0 with no .craft/dials" || fail "exit 0 with no .craft/dials" "0" "$RC"
[ -z "$OUT" ] && pass "empty stdout with no .craft/dials" || fail "empty stdout with no .craft/dials" "(empty)" "$OUT"
rm -rf "$ROOT"

echo "-- Test: list emits SURFACE and KIND for the tweak join --"
fresh_root
bash "$CAP" "filter row spacing" --surface=filter-row --kind=spacing --scope=magnitude \
  --offered="a,b,c" --chose=c --passed="a,b" --outcome=tweak --graduated-to=tweak-filter-row-gap \
  --reaction="C - commit to it" > /dev/null
OUT=$(bash "$LIST")
echo "$OUT" | grep -q "^SURFACE=filter-row$" && pass "SURFACE= emitted with captured value" || fail "SURFACE= emitted" "SURFACE=filter-row" "$(echo "$OUT" | grep '^SURFACE=' || echo missing)"
echo "$OUT" | grep -q "^KIND=spacing$" && pass "KIND= emitted with captured value" || fail "KIND= emitted" "KIND=spacing" "$(echo "$OUT" | grep '^KIND=' || echo missing)"
echo "$OUT" | grep -q "^FILE=" && pass "FILE= present" || fail "FILE= present"
echo "$OUT" | grep -q "^DATE=" && pass "DATE= present" || fail "DATE= present"
echo "$OUT" | grep -q "^SLUG=filter-row-spacing$" && pass "SLUG= present" || fail "SLUG= present" "SLUG=filter-row-spacing" "$(echo "$OUT" | grep '^SLUG=' || echo missing)"
echo "$OUT" | grep -q "^SCOPE=magnitude$" && pass "SCOPE= present" || fail "SCOPE= present"
echo "$OUT" | grep -q "^CHOSE=c$" && pass "CHOSE= present" || fail "CHOSE= present"
echo "$OUT" | grep -q "^OUTCOME=tweak$" && pass "OUTCOME= present" || fail "OUTCOME= present"
echo "$OUT" | grep -q "^PREVIEW=C - commit to it$" && pass "PREVIEW= captures first body line" || fail "PREVIEW=" "PREVIEW=C - commit to it" "$(echo "$OUT" | grep '^PREVIEW=' || echo missing)"
rm -rf "$ROOT"

echo "-- Test: NO status filter - an injected status: open line still lists --"
fresh_root
OUT_FILE=$(bash "$CAP" "keep current session" --surface=settings-toolbar --kind=color --scope=approach \
  --offered="a,b" --chose=none --passed="a,b" --outcome=nothing)
python3 -c "
import re, sys
p = sys.argv[1]
c = open(p).read()
c = re.sub(r'^graduated_to:', 'status: open\ngraduated_to:', c, flags=re.MULTILINE)
open(p, 'w').write(c)
" "$OUT_FILE"
grep -q '^status: open$' "$OUT_FILE" || fail "test setup: status injection landed"
OUT=$(bash "$LIST")
echo "$OUT" | grep -q "^SLUG=keep-current-session$" && pass "record with injected status: open still lists (no lifecycle branch)" || fail "record with injected status still lists" "SLUG=keep-current-session in output" "absent"
rm -rf "$ROOT"

echo "-- Test: --surface filters to matching records only --"
fresh_root
bash "$CAP" "toolbar dial" --surface=settings-toolbar --kind=icon --scope=approach \
  --offered="a,b" --chose=a --passed="b" --outcome=nothing > /dev/null
bash "$CAP" "card dial" --surface=card-grid --kind=spacing --scope=magnitude \
  --offered="a,b" --chose=b --passed="a" --outcome=nothing > /dev/null
OUT=$(bash "$LIST" --surface=settings-toolbar)
echo "$OUT" | grep -q "^SLUG=toolbar-dial$" && pass "matching surface listed" || fail "matching surface listed"
if echo "$OUT" | grep -q "^SLUG=card-dial$"; then
  fail "non-matching surface excluded" "card-dial absent" "present"
else
  pass "non-matching surface excluded"
fi
OUT_ALL=$(bash "$LIST")
COUNT=$(echo "$OUT_ALL" | grep -c "^SLUG=" || true)
[ "$COUNT" -eq 2 ] && pass "unfiltered list shows both records" || fail "unfiltered list shows both records" "2" "$COUNT"
rm -rf "$ROOT"

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
