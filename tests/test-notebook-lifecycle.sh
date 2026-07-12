#!/bin/bash
# test-notebook-lifecycle.sh — Behavior tests for notebook-graduate-mark.sh and notebook-done.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAP="$SCRIPT_DIR/../hooks/scripts/notebook-capture.sh"
GRAD="$SCRIPT_DIR/../hooks/scripts/notebook-graduate-mark.sh"
DONE="$SCRIPT_DIR/../hooks/scripts/notebook-done.sh"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Expected: $2"; [ -n "${3:-}" ] && echo "    Got:      $3"; }

fresh_root() {
  ROOT=$(mktemp -d)
  export CRAFT_PROJECT_ROOT="$ROOT"
}

echo "=== test-notebook-lifecycle.sh ==="
echo ""

echo "-- Test: AC5 graduate-mark flags idea in place (no move) --"
fresh_root
IDEA=$(bash "$CAP" idea "compounding kb for decisions")
OUT=$(bash "$GRAD" "$IDEA" "compounding-kb-decisions")
[ "$OUT" = "$IDEA" ] && pass "file path unchanged (no move)" || fail "file path unchanged" "$IDEA" "$OUT"
[ -f "$IDEA" ] && pass "file still exists at original path" || fail "file still exists at original path"
grep -q "^status: graduated$" "$IDEA" && pass "status flipped to graduated" || fail "status flipped to graduated"
grep -q "^graduated_to: compounding-kb-decisions$" "$IDEA" && pass "graduated_to set" || fail "graduated_to set"
tail -1 "$IDEA" | grep -q "^compounding kb for decisions$" && pass "body preserved verbatim" || fail "body preserved verbatim"
rm -rf "$ROOT"

echo "-- Test: graduate-mark rejects non-idea file --"
fresh_root
TODO=$(bash "$CAP" todo "not an idea")
if bash "$GRAD" "$TODO" "some-slug" 2>/dev/null; then
  fail "rejects non-idea file" "non-zero exit" "exit 0"
else
  pass "rejects non-idea file"
fi
rm -rf "$ROOT"

echo "-- Test: AC6 done moves to done/ and updates frontmatter --"
fresh_root
TODO=$(bash "$CAP" todo "rename verifier error wording")
ORIG_DIR=$(dirname "$TODO")
ORIG_BASE=$(basename "$TODO")
OUT=$(bash "$DONE" "$TODO")
[ ! -f "$TODO" ] && pass "original file removed" || fail "original file removed"
[ -f "$OUT" ] && pass "destination file exists" || fail "destination file exists"
case "$OUT" in
  */todos/done/*) pass "destination in todos/done/";;
  *) fail "destination in todos/done/" "*/todos/done/*" "$OUT";;
esac
[ "$(basename "$OUT")" = "$ORIG_BASE" ] && pass "basename preserved" || fail "basename preserved"
grep -q "^status: done$" "$OUT" && pass "status flipped to done" || fail "status flipped to done"
grep -q "^done_at: " "$OUT" && pass "done_at field set" || fail "done_at field set"
rm -rf "$ROOT"

echo "-- Test: done rejects non-todo file --"
fresh_root
IDEA=$(bash "$CAP" idea "not a todo")
if bash "$DONE" "$IDEA" 2>/dev/null; then
  fail "rejects non-todo file"
else
  pass "rejects non-todo file"
fi
rm -rf "$ROOT"

echo "-- Test: two-arg done writes graduated_to alongside done_at --"
fresh_root
TODO=$(bash "$CAP" todo "build the ecosystem closing beat")
OUT=$(bash "$DONE" "$TODO" "demo-story")
grep -q "^status: done$" "$OUT" && pass "status flipped to done" || fail "status flipped to done"
grep -q "^done_at: " "$OUT" && pass "done_at field set" || fail "done_at field set"
grep -q "^graduated_to: demo-story$" "$OUT" && pass "graduated_to set to ref" || fail "graduated_to set to ref"
case "$OUT" in
  */todos/done/*) pass "destination in todos/done/";;
  *) fail "destination in todos/done/" "*/todos/done/*" "$OUT";;
esac
rm -rf "$ROOT"

echo "-- Test: single-arg done writes no graduated_to --"
fresh_root
TODO=$(bash "$CAP" todo "close without a destination")
OUT=$(bash "$DONE" "$TODO")
grep -q "^done_at: " "$OUT" && pass "done_at field set" || fail "done_at field set"
if grep -q "^graduated_to:" "$OUT"; then
  fail "no graduated_to on bare close" "absent" "present"
else
  pass "no graduated_to on bare close"
fi
rm -rf "$ROOT"

echo "-- Test: tolerant status - hand-edited non-open status still closes cleanly --"
fresh_root
TODO=$(bash "$CAP" todo "hand-edited straggler")
python3 -c "
import sys, re
p = sys.argv[1]
c = open(p).read()
open(p, 'w').write(re.sub(r'^status: open$', 'status: graduated', c, count=1, flags=re.MULTILINE))
" "$TODO"
OUT=$(bash "$DONE" "$TODO")
grep -q "^status: done$" "$OUT" && pass "non-open status normalized to done" || fail "non-open status normalized to done"
grep -q "^done_at: " "$OUT" && pass "done_at inserted despite hand-edit" || fail "done_at inserted despite hand-edit"
rm -rf "$ROOT"

echo "-- Test: tolerant status - hand-set status:done + stray completed field --"
fresh_root
TODO=$(bash "$CAP" todo "hand-closed with improvised frontmatter")
python3 -c "
import sys, re
p = sys.argv[1]
c = open(p).read()
c = re.sub(r'^status: open$', 'status: done\ncompleted: 2026-07-01', c, count=1, flags=re.MULTILINE)
open(p, 'w').write(c)
" "$TODO"
if OUT=$(bash "$DONE" "$TODO"); then
  pass "exits 0 on hand-set done + stray completed field"
else
  fail "exits 0 on hand-set done + stray completed field"
fi
grep -q "^done_at: " "$OUT" && pass "done_at inserted alongside stray completed" || fail "done_at inserted alongside stray completed"
[ -f "$OUT" ] && pass "file moved to done/" || fail "file moved to done/"
rm -rf "$ROOT"

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"; echo "Passed: $PASS_COUNT"; echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
