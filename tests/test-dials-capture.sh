#!/bin/bash
# test-dials-capture.sh — Behavior tests for dials-capture.sh
# Usage: bash tests/test-dials-capture.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../hooks/scripts/dials-capture.sh"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Expected: $2"; [ -n "${3:-}" ] && echo "    Got:      $3"; }

fresh_root() {
  ROOT=$(mktemp -d)
  export CRAFT_PROJECT_ROOT="$ROOT"
}

# A valid capture with every required flag; extra args extend/override.
capture() {
  bash "$SCRIPT" "$1" --surface=filter-row --kind=spacing --scope=magnitude \
    --offered="a,b,c" --chose=c --passed="a,b" --outcome=nothing "${@:2}"
}

echo "=== test-dials-capture.sh ==="
echo ""

echo "-- Test: kind validation enforces the tweak-vocabulary join key --"
fresh_root
if bash "$SCRIPT" "gap test" --surface=filter-row --kind=layout --scope=magnitude --outcome=nothing 2>/dev/null; then
  fail "kind=layout rejected" "exit 1" "exit 0"
else
  pass "kind=layout rejected"
fi
if [ -d "$ROOT/.craft/dials" ]; then
  fail "no file written on invalid kind" "no .craft/dials directory" "directory exists"
else
  pass "no file written on invalid kind"
fi
for k in icon copy spacing size color motion content; do
  OUT=$(bash "$SCRIPT" "kind $k" --surface=filter-row --kind="$k" --scope=magnitude --outcome=nothing)
  [ -f "$OUT" ] && pass "kind=$k accepted" || fail "kind=$k accepted"
done
rm -rf "$ROOT"

echo "-- Test: scope and outcome validation --"
fresh_root
if bash "$SCRIPT" "scope test" --surface=filter-row --kind=spacing --scope=vibes --outcome=nothing 2>/dev/null; then
  fail "scope=vibes rejected" "exit 1" "exit 0"
else
  pass "scope=vibes rejected"
fi
if bash "$SCRIPT" "outcome test" --surface=filter-row --kind=spacing --scope=magnitude --outcome=maybe 2>/dev/null; then
  fail "outcome=maybe rejected" "exit 1" "exit 0"
else
  pass "outcome=maybe rejected"
fi
rm -rf "$ROOT"

echo "-- Test: all eleven frontmatter keys present, in order, on a minimal record --"
fresh_root
OUT=$(capture "filter row spacing")
KEYS_EXPECTED="source slug created surface kind scope offered chose passed outcome graduated_to"
KEYS_ACTUAL=$(awk '/^---$/{c++; next} c==1{sub(/:.*/,""); print}' "$OUT" | tr '\n' ' ' | sed 's/ $//')
if [ "$KEYS_ACTUAL" = "$KEYS_EXPECTED" ]; then
  pass "eleven keys present in contract order"
else
  fail "eleven keys present in contract order" "$KEYS_EXPECTED" "$KEYS_ACTUAL"
fi
grep -q "^graduated_to:[[:space:]]*$" "$OUT" && pass "unsupplied graduated_to writes empty key, not omitted line" || fail "unsupplied graduated_to writes empty key" "graduated_to: (empty)" "$(grep '^graduated_to:' "$OUT" || echo 'line missing')"
rm -rf "$ROOT"

echo "-- Test: record is born closed - no lifecycle fields --"
fresh_root
OUT=$(capture "born closed check")
STATUS_COUNT=$(grep -c '^status:' "$OUT" || true)
ATTEMPTS_COUNT=$(grep -c '^attempts:' "$OUT" || true)
[ "$STATUS_COUNT" -eq 0 ] && pass "no status: field" || fail "no status: field" "0" "$STATUS_COUNT"
[ "$ATTEMPTS_COUNT" -eq 0 ] && pass "no attempts: field" || fail "no attempts: field" "0" "$ATTEMPTS_COUNT"
rm -rf "$ROOT"

echo "-- Test: source defaults to dial --"
fresh_root
OUT=$(capture "source default check")
grep -q "^source: dial$" "$OUT" && pass "source defaults to dial" || fail "source defaults to dial" "source: dial" "$(grep '^source:' "$OUT")"
rm -rf "$ROOT"

echo "-- Test: slug collision appends -2 --"
fresh_root
OUT1=$(capture "duplicate dial")
OUT2=$(capture "duplicate dial")
if [ "$OUT1" != "$OUT2" ]; then pass "collision produces different file"; else fail "collision produces different file"; fi
case "$OUT2" in *duplicate-dial-2.md) pass "collision suffix -2";; *) fail "collision suffix -2" "*duplicate-dial-2.md" "$OUT2";; esac
rm -rf "$ROOT"

echo "-- Test: reaction body is verbatim --"
fresh_root
OUT=$(capture "reaction check" --reaction="C, but a little looser - that one breathes")
LAST_LINE=$(tail -1 "$OUT")
if [ "$LAST_LINE" = "C, but a little looser - that one breathes" ]; then
  pass "reaction is last body line, verbatim"
else
  fail "reaction is last body line, verbatim" "C, but a little looser - that one breathes" "$LAST_LINE"
fi
rm -rf "$ROOT"

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
