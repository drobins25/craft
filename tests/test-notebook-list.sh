#!/bin/bash
# test-notebook-list.sh — Behavior tests for notebook-list.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$SCRIPT_DIR/../hooks/scripts/notebook-list.sh"
CAP="$SCRIPT_DIR/../hooks/scripts/notebook-capture.sh"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Expected: $2"; [ -n "${3:-}" ] && echo "    Got:      $3"; return 0; }

fresh_root() {
  ROOT=$(mktemp -d)
  export CRAFT_PROJECT_ROOT="$ROOT"
}

echo "=== test-notebook-list.sh ==="
echo ""

echo "-- Test: AC12 empty notebook produces no records --"
fresh_root
OUT=$(bash "$LIST")
[ -z "$OUT" ] && pass "empty output for no entries" || fail "empty output for no entries" "(empty)" "$OUT"
rm -rf "$ROOT"

echo "-- Test: AC4 list groups ideas and todos with correct fields --"
fresh_root
bash "$CAP" idea "first idea text" > /dev/null
bash "$CAP" todo "first todo text" > /dev/null
OUT=$(bash "$LIST")
echo "$OUT" | grep -q "^TYPE=idea$" && pass "has TYPE=idea record" || fail "has TYPE=idea record"
echo "$OUT" | grep -q "^TYPE=todo$" && pass "has TYPE=todo record" || fail "has TYPE=todo record"
echo "$OUT" | grep -q "^N=1$" && pass "has N=1 numbering" || fail "has N=1 numbering"
echo "$OUT" | grep -q "^DATE=" && pass "has DATE field" || fail "has DATE field"
echo "$OUT" | grep -q "^SLUG=" && pass "has SLUG field" || fail "has SLUG field"
echo "$OUT" | grep -q "^PREVIEW=first idea text$" && pass "preview captures first body line" || fail "preview captures first body line"
rm -rf "$ROOT"

echo "-- Test: AC19 TAGS= field rendered with parsed tags --"
fresh_root
bash "$CAP" idea "compounding kb #architecture #knowledge" > /dev/null
OUT=$(bash "$LIST")
echo "$OUT" | grep -q "^TAGS=architecture;knowledge$" && pass "TAGS= field with semicolon separator" || fail "TAGS= field" "TAGS=architecture;knowledge" "$(echo "$OUT" | grep '^TAGS=')"

bash "$CAP" idea "no tags here" > /dev/null
OUT=$(bash "$LIST")
TAG_LINES=$(echo "$OUT" | grep "^TAGS=" || true)
echo "$TAG_LINES" | grep -qx "TAGS=" && pass "empty TAGS= line for tagless entry" || fail "empty TAGS= line"
rm -rf "$ROOT"

echo "-- Test: AC9 graduated ideas skipped from open list --"
fresh_root
OUT_FILE=$(bash "$CAP" idea "will graduate later")
python3 -c "
import re, sys
p = sys.argv[1]
c = open(p).read()
c = re.sub(r'^status: open\$', 'status: graduated\ngraduated_to: foo-bar-story', c, flags=re.MULTILINE)
open(p, 'w').write(c)
" "$OUT_FILE"
bash "$CAP" idea "still open idea" > /dev/null
OUT=$(bash "$LIST")
echo "$OUT" | grep -q "will graduate later" && fail "graduated idea hidden from list" "graduated idea not in output" "found in output" || pass "graduated idea hidden from list"
echo "$OUT" | grep -q "still open idea" && pass "open idea visible" || fail "open idea visible"
rm -rf "$ROOT"

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"; echo "Passed: $PASS_COUNT"; echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
