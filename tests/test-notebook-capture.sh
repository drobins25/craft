#!/bin/bash
# test-notebook-capture.sh — Behavior tests for notebook-capture.sh
# Usage: bash tests/test-notebook-capture.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../hooks/scripts/notebook-capture.sh"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Expected: $2"; [ -n "${3:-}" ] && echo "    Got:      $3"; return 0; }

fresh_root() {
  ROOT=$(mktemp -d)
  export CRAFT_PROJECT_ROOT="$ROOT"
}

echo "=== test-notebook-capture.sh ==="
echo ""

echo "-- Test: AC1/AC8 idea capture creates folder and file --"
fresh_root
OUT=$(bash "$SCRIPT" idea "compounding kb for decisions")
if [ -f "$OUT" ]; then pass "file exists"; else fail "file exists" "file present" "missing"; fi
if [ -d "$ROOT/.craft/notebook/ideas" ]; then pass "ideas folder created"; else fail "ideas folder created"; fi
grep -q "^type: idea$" "$OUT" && pass "type: idea frontmatter" || fail "type: idea frontmatter"
grep -q "^status: open$" "$OUT" && pass "status: open frontmatter" || fail "status: open frontmatter"
grep -q "^captured_at: " "$OUT" && pass "captured_at present" || fail "captured_at present"
tail -1 "$OUT" | grep -q "^compounding kb for decisions$" && pass "body verbatim" || fail "body verbatim"
rm -rf "$ROOT"

echo "-- Test: AC2 todo capture writes to todos folder --"
fresh_root
OUT=$(bash "$SCRIPT" todo "rename verifier error wording")
case "$OUT" in
  */.craft/notebook/todos/*) pass "todo file in todos folder";;
  *) fail "todo file in todos folder" ".craft/notebook/todos/*" "$OUT";;
esac
grep -q "^type: todo$" "$OUT" && pass "type: todo frontmatter" || fail "type: todo frontmatter"
rm -rf "$ROOT"

echo "-- Test: AC3 slug edge cases --"
fresh_root
OUT=$(bash "$SCRIPT" idea "It's a TEST!! with @#weird chars")
case "$OUT" in
  *its-a-test-with*|*it-s-a-test-with*) pass "special chars stripped from slug";;
  *) fail "special chars stripped from slug" "slug without special chars" "$OUT";;
esac

LONG="this is a very long title that should be capped at fifty characters and not exceed it"
OUT=$(bash "$SCRIPT" idea "$LONG")
BASE=$(basename "$OUT" .md)
SLUG_PART="${BASE#????-??-??-}"
if [ ${#SLUG_PART} -le 50 ]; then pass "slug capped <=50 chars (got ${#SLUG_PART})"; else fail "slug capped <=50 chars" "<=50" "${#SLUG_PART}"; fi

OUT1=$(bash "$SCRIPT" idea "duplicate title")
OUT2=$(bash "$SCRIPT" idea "duplicate title")
if [ "$OUT1" != "$OUT2" ]; then pass "collision produces different file"; else fail "collision produces different file"; fi
case "$OUT2" in *duplicate-title-2.md) pass "collision suffix -2";; *) fail "collision suffix -2" "*duplicate-title-2.md" "$OUT2";; esac
rm -rf "$ROOT"

echo "-- Test: AC18 inline #tag parsing and scrubbing --"
fresh_root
OUT=$(bash "$SCRIPT" idea "compounding kb for decisions #architecture #knowledge")
grep -q "^tags: \[architecture, knowledge\]$" "$OUT" && pass "tags frontmatter has both tags" || fail "tags frontmatter" "tags: [architecture, knowledge]" "$(grep '^tags:' "$OUT")"
LAST_LINE=$(tail -1 "$OUT")
if [ "$LAST_LINE" = "compounding kb for decisions" ]; then pass "body scrubbed of #tags"; else fail "body scrubbed of #tags" "compounding kb for decisions" "$LAST_LINE"; fi
BASE=$(basename "$OUT" .md)
echo "$BASE" | grep -q "architecture" && fail "slug omits tag tokens" "no 'architecture'" "$BASE" || pass "slug omits tag tokens"

OUT=$(bash "$SCRIPT" idea "#weekend-thoughts")
case "$OUT" in *untitled*) pass "tags-only capture uses untitled slug";; *) fail "tags-only capture uses untitled slug" "*untitled*" "$OUT";; esac
grep -q "^tags: \[weekend-thoughts\]$" "$OUT" && pass "tags-only sets tag" || fail "tags-only sets tag"
rm -rf "$ROOT"

echo "-- Test: AC14 body paragraph 2 elaboration --"
fresh_root
OUT=$(bash "$SCRIPT" idea "ambiguous referent" --body-paragraph2="full context: this is about X happening during Y")
BODY=$(awk '/^---$/{c++; next} c==2{print}' "$OUT")
LINE1=$(printf '%s\n' "$BODY" | sed -n '1p')
LINE2=$(printf '%s\n' "$BODY" | sed -n '2p')
LINE3=$(printf '%s\n' "$BODY" | sed -n '3p')
[ "$LINE1" = "ambiguous referent" ] && pass "paragraph 1 verbatim" || fail "paragraph 1 verbatim" "ambiguous referent" "$LINE1"
[ -z "$LINE2" ] && pass "blank line separator" || fail "blank line separator" "(empty)" "$LINE2"
[ "$LINE3" = "full context: this is about X happening during Y" ] && pass "paragraph 2 verbatim" || fail "paragraph 2 verbatim"
rm -rf "$ROOT"

echo "-- Test: extra-tags merge (Claude-driven captures) --"
fresh_root
OUT=$(bash "$SCRIPT" idea "session note" --tags="verifier,cycle-9")
grep -q "^tags: \[verifier, cycle-9\]$" "$OUT" && pass "extra-tags merged" || fail "extra-tags merged" "tags: [verifier, cycle-9]" "$(grep '^tags:' "$OUT")"

OUT=$(bash "$SCRIPT" idea "session note #verifier" --tags="cycle-9,verifier")
grep -q "^tags: \[verifier, cycle-9\]$" "$OUT" && pass "inline+extra deduped" || fail "inline+extra deduped"
rm -rf "$ROOT"

echo "-- Test: todo --review stamps the frontmatter between source and tags --"
fresh_root
OUT=$(bash "$SCRIPT" todo "tidy the reviewer wording #docs" --source="review close-out" --review=2026-10-18-branch-x)
grep -q "^review: 2026-10-18-branch-x$" "$OUT" && pass "review line present" || fail "review line present"
KEYS=$(awk '/^---$/{c++; next} c==1{print}' "$OUT" | sed 's/:.*//' | tr '\n' ' ')
[ "$KEYS" = "type created captured_at status source review tags " ] && pass "review sits after source, before tags" || fail "review key order" "type created captured_at status source review tags " "$KEYS"
tail -1 "$OUT" | grep -q "^tidy the reviewer wording$" && pass "body unchanged" || fail "body unchanged"

echo "-- Test: todo without --review has no review line --"
fresh_root
OUT=$(bash "$SCRIPT" todo "no review here")
grep -q "^review:" "$OUT" && fail "no review line" || pass "no review line"

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
