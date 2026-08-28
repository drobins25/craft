#!/bin/bash
# test-ci-template-stamp.sh — Tests for scripts/ci/check-template-stamp.sh
# Builds throwaway git repos in a temp dir; never touches the real repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKER="$ROOT/scripts/ci/check-template-stamp.sh"
WATCHED="scripts/dashboard/template/index.html"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Detail: $2"; }

echo "=== test-ci-template-stamp.sh ==="
echo ""

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# git that works on a machine (or CI runner) with no global identity
tgit() {
  git -C "$1" -c user.name=test -c user.email=test@example.invalid "${@:2}"
}

# Build a fresh throwaway repo whose first commit carries a 12-line stub
# template with the given stamp value ("" = no meta line at all).
new_repo() {
  local dir="$1" stamp="$2"
  rm -rf "$dir"
  mkdir -p "$dir/scripts/dashboard/template"
  git -C "$dir" init -q
  write_template "$dir" "$stamp" "original body"
  echo "unrelated" > "$dir/README.md"
  tgit "$dir" add -A
  tgit "$dir" commit -qm "base"
}

write_template() {
  local dir="$1" stamp="$2" body="$3"
  {
    echo '<!DOCTYPE html>'
    echo '<html lang="en">'
    echo '<head>'
    echo '<meta charset="UTF-8">'
    if [ -n "$stamp" ]; then
      echo "<meta name=\"craft-template-version\" content=\"$stamp\">"
    fi
    echo '<title>stub</title>'
    echo '</head>'
    echo '<body>'
    echo "<p>$body</p>"
    echo '</body>'
    echo '</html>'
    echo ''
  } > "$dir/$WATCHED"
}

run_checker() {
  local dir="$1"
  set +e
  OUT=$(cd "$dir" && bash "$CHECKER" --base HEAD~1 --head HEAD 2>&1)
  RC=$?
  set -e
}

# Test 1: a diff that does not touch the template exits 0
R="$WORK/r1"; new_repo "$R" "4"
echo "changed" > "$R/README.md"
tgit "$R" add -A; tgit "$R" commit -qm "unrelated change"
run_checker "$R"
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q "does not touch"; then
  pass "untouched template exits 0 with a not-touched note"
else
  fail "untouched template" "rc=$RC out: $OUT"
fi

# Test 2: a template edit with a bumped stamp exits 0
R="$WORK/r2"; new_repo "$R" "4"
write_template "$R" "5" "new body"
tgit "$R" add -A; tgit "$R" commit -qm "template edit with bump"
run_checker "$R"
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q "4 -> 5"; then
  pass "template edit with a bumped stamp exits 0"
else
  fail "bumped stamp" "rc=$RC out: $OUT"
fi

# Test 3: a whitespace-only template edit with an unchanged stamp exits 1
R="$WORK/r3"; new_repo "$R" "4"
printf '\n' >> "$R/$WATCHED"
tgit "$R" add -A; tgit "$R" commit -qm "whitespace only"
run_checker "$R"
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q "still '4'"; then
  pass "whitespace-only edit with unchanged stamp exits 1 naming the stamp"
else
  fail "whitespace-only edit" "rc=$RC out: $OUT"
fi

# Test 4: a content edit with an unchanged stamp exits 1
R="$WORK/r4"; new_repo "$R" "4"
write_template "$R" "4" "edited body, stamp forgotten"
tgit "$R" add -A; tgit "$R" commit -qm "content edit no bump"
run_checker "$R"
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q "still '4'"; then
  pass "content edit with unchanged stamp exits 1"
else
  fail "content edit no bump" "rc=$RC out: $OUT"
fi

# Test 5: a template added for the first time with a valid stamp exits 0
R="$WORK/r5"
rm -rf "$R"; mkdir -p "$R"
git -C "$R" init -q
echo "start" > "$R/README.md"
tgit "$R" add -A; tgit "$R" commit -qm "no template yet"
mkdir -p "$R/scripts/dashboard/template"
write_template "$R" "1" "first version"
tgit "$R" add -A; tgit "$R" commit -qm "add template"
run_checker "$R"
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q "none -> 1"; then
  pass "newly-added template with a valid stamp exits 0"
else
  fail "newly-added template" "rc=$RC out: $OUT"
fi

# Test 6: a malformed stamp on both sides reads as none and exits 1
R="$WORK/r6"; new_repo "$R" "not-a-number"
write_template "$R" "still-not-a-number" "edited"
tgit "$R" add -A; tgit "$R" commit -qm "malformed both sides"
run_checker "$R"
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q "still 'none'"; then
  pass "malformed stamps degrade to none and exit 1"
else
  fail "malformed stamps" "rc=$RC out: $OUT"
fi

# Test 7: missing --base or --head exits 2 with a usage line
set +e
OUT=$(bash "$CHECKER" --base HEAD 2>&1)
RC=$?
set -e
if [ "$RC" -eq 2 ] && echo "$OUT" | grep -q "usage:"; then
  pass "missing --head exits 2 with a usage line"
else
  fail "missing argument" "rc=$RC out: $OUT"
fi
set +e
OUT=$(bash "$CHECKER" 2>&1)
RC=$?
set -e
if [ "$RC" -eq 2 ] && echo "$OUT" | grep -q "usage:"; then
  pass "no arguments exits 2 with a usage line"
else
  fail "no arguments" "rc=$RC out: $OUT"
fi

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
