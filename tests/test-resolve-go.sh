#!/bin/bash
# test-resolve-go.sh - Tests for resolve-go.py
# Validates newest-Go selection from a copied comments file: ordering by parsed
# tracker time, authority never widening, the stage line, and the verbatim Go body.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

RESOLVER="$SCRIPTS_DIR/resolve-go.py"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# resolve <comments-file> <KEY> [go-file] -> stdout in $OUT, exit code in $CODE
resolve() {
  set +e
  OUT=$(python3 "$RESOLVER" "$@" 2>"$WORK/stderr")
  CODE=$?
  set -e
}

# field <name> -> value of a key=value line in $OUT
field() {
  printf '%s\n' "$OUT" | sed -n "s/^$1=//p"
}

echo "=== test-resolve-go.sh ==="
echo ""

# --- FIRST: an unreadable header can never produce a found Go ---
begin_test "unreadable header yields no Go"
cat > "$WORK/c1.md" <<'FIX'
# DRO-21 comments, oldest first

## comment 1 - Darin - 2026-10-31T10:00:00Z

## Go - build (Darin, October 31, 2026)

Stage: build - code on a branch, with tests and review. No pull request.

## Comment 2 - Darin -

## Go - build (Darin, October 31, 2026)
FIX
resolve "$WORK/c1.md" DRO-21
assert_eq "exits 0" "0" "$CODE"
assert_eq "go=none" "none" "$(field go)"
assert_eq "stage=plan" "plan" "$(field stage)"
assert_eq "no-Go stage line" "No Go found on DRO-21, so this run plans only." "$(field stage_line)"
assert_eq "six lines" "6" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
assert_eq "empty go_comment" "" "$(field go_comment)"

begin_test "no comments file content"
printf '# DRO-21 comments, oldest first\n\nsome preamble\n' > "$WORK/c2.md"
resolve "$WORK/c2.md" DRO-21
assert_eq "go=none" "none" "$(field go)"
printf '' > "$WORK/empty.md"
resolve "$WORK/empty.md" DRO-21
assert_eq "empty file go=none" "none" "$(field go)"

begin_test "stdout line order is fixed"
resolve "$WORK/c2.md" DRO-21
KEYS=$(printf '%s\n' "$OUT" | sed 's/=.*//' | tr '\n' ' ')
assert_eq "key order" "go stage go_author go_date go_comment stage_line " "$KEYS"

begin_test "newest by timestamp, not file order"
cat > "$WORK/c3.md" <<'FIX'
# DRO-21 comments, oldest first

## Comment 1 - Darin Drobinski - 2026-10-31T23:40:12.000Z

## Go - build (Darin, October 31, 2026)

Stage: build

## Comment 2 - Darin Drobinski - 2026-10-30T10:00:00.000Z

## Go - plan (Darin, October 30, 2026)

Stage: plan
FIX
resolve "$WORK/c3.md" DRO-21
assert_eq "go=found" "found" "$(field go)"
assert_eq "stage=build" "build" "$(field stage)"
assert_eq "go_comment=1" "1" "$(field go_comment)"
assert_eq "go_date verbatim" "2026-10-31T23:40:12.000Z" "$(field go_date)"
assert_eq "go_author" "Darin Drobinski" "$(field go_author)"

begin_test "offset forms compare in UTC"
cat > "$WORK/c4.md" <<'FIX'
## Comment 1 - Darin - 2021-03-10T10:05:51.199-0700

## Go - plan (Darin, March 10, 2021)

## Comment 2 - Darin - 2021-03-10T12:00:00Z

## Go - build (Darin, March 10, 2021)
FIX
resolve "$WORK/c4.md" DRO-21
assert_eq "stage=plan (17:05Z beats 12:00Z)" "plan" "$(field stage)"
assert_eq "go_comment=1" "1" "$(field go_comment)"
cat > "$WORK/c4b.md" <<'FIX'
## Comment 1 - Darin - 2021-03-10T10:00:00+05:30

## Go - plan (Darin, March 10, 2021)

## Comment 2 - Darin - 2021-03-10T04:00:00+00:00

## Go - build (Darin, March 10, 2021)
FIX
resolve "$WORK/c4b.md" DRO-21
assert_eq "+HH:MM normalizes (04:30Z beats 04:00Z)" "plan" "$(field stage)"

begin_test "tie goes to later block"
cat > "$WORK/c5.md" <<'FIX'
## Comment 1 - Darin - 2026-10-31T10:00:00Z

## Go - plan (Darin, October 31, 2026)

## Comment 2 - Darin - 2026-10-31T10:00:00.000Z

## Go - hold (Darin, October 31, 2026)
FIX
resolve "$WORK/c5.md" DRO-21
assert_eq "stage=hold" "hold" "$(field stage)"
assert_eq "go_comment=2" "2" "$(field go_comment)"

begin_test "reply and inline Gos ignored"
cat > "$WORK/c6.md" <<'FIX'
## Reply 1 - Darin - 2026-10-31T10:00:00Z

## Go - build (Darin, October 31, 2026)

## Inline 2 - Darin - 2026-10-31T11:00:00Z

## Go - build (Darin, October 31, 2026)
FIX
resolve "$WORK/c6.md" DRO-21
assert_eq "go=none" "none" "$(field go)"
assert_eq "stage=plan" "plan" "$(field stage)"

begin_test "Go not on first line ignored"
cat > "$WORK/c7.md" <<'FIX'
## Comment 1 - Darin - 2026-10-31T10:00:00Z

Some words first.

## Go - build (Darin, October 31, 2026)
FIX
resolve "$WORK/c7.md" DRO-21
assert_eq "go=none" "none" "$(field go)"

begin_test "malformed newest never falls back"
cat > "$WORK/c8.md" <<'FIX'
## Comment 1 - Darin - 2026-10-30T10:00:00Z

## Go - build (Darin, October 30, 2026)

## Comment 2 - Darin - 2026-10-31T10:00:00Z

## Go - ship (Darin, October 31, 2026)
FIX
resolve "$WORK/c8.md" DRO-21
assert_eq "go=unreadable" "unreadable" "$(field go)"
assert_eq "stage=plan" "plan" "$(field stage)"
assert_eq "go_comment=2" "2" "$(field go_comment)"
assert_eq "unreadable stage line" "The newest Go on DRO-21 (comment 2) doesn't follow the Go format, so this run plans only." "$(field stage_line)"

begin_test "unparseable time on the newest Go is unreadable, never a fallback"
cat > "$WORK/c9.md" <<'FIX'
## Comment 1 - Darin - 2026-10-30T10:00:00Z

## Go - build (Darin, October 30, 2026)

## Comment 2 - Darin - yesterday

## Go - hold (Darin, October 31, 2026)

## Comment 3 - Darin - 2026-13-45T10:00:00Z

## Go - hold (Darin, October 31, 2026)
FIX
resolve "$WORK/c9.md" DRO-21
# Comment 2's time is not a time at all and comment 3's is an impossible one:
# neither can be ranked, so neither may be skipped in favor of comment 1.
assert_eq "go=unreadable" "unreadable" "$(field go)"
assert_eq "go_comment=3" "3" "$(field go_comment)"
assert_eq "stage=plan" "plan" "$(field stage)"

begin_test "unparseable time on a lone newer Go is unreadable"
cat > "$WORK/c9b.md" <<'FIX'
## Comment 1 - Darin - 2026-10-30T10:00:00Z

## Go - build (Darin, October 30, 2026)

## Comment 2 - Darin - yesterday

## Go - hold (Darin, October 31, 2026)
FIX
resolve "$WORK/c9b.md" DRO-21
assert_eq "go=unreadable" "unreadable" "$(field go)"
assert_eq "go_comment=2" "2" "$(field go_comment)"

begin_test "unparseable time on a non-Go comment is harmless"
cat > "$WORK/c9c.md" <<'FIX'
## Comment 1 - Darin - 2026-10-30T10:00:00Z

## Go - build (Darin, October 30, 2026)

## Comment 2 - Someone - soon

Just chatting.
FIX
resolve "$WORK/c9c.md" DRO-21
assert_eq "go=found" "found" "$(field go)"
assert_eq "stage=build" "build" "$(field stage)"

begin_test "invalid calendar date is unreadable"
cat > "$WORK/c10.md" <<'FIX'
## Comment 1 - Darin - 2026-10-31T10:00:00Z

## Go - build (Darin, February 30, 2026)
FIX
resolve "$WORK/c10.md" DRO-21
assert_eq "go=unreadable" "unreadable" "$(field go)"

begin_test "en dash Go is unreadable"
cat > "$WORK/c11.md" <<'FIX'
## Comment 1 - Darin - 2026-10-30T10:00:00Z

## Go - build (Darin, October 30, 2026)

## Comment 2 - Darin - 2026-10-31T10:00:00Z

## Go – build (Darin, October 31, 2026)
FIX
resolve "$WORK/c11.md" DRO-21
assert_eq "go=unreadable" "unreadable" "$(field go)"
assert_eq "go_comment=2" "2" "$(field go_comment)"

begin_test "stage line renders heading name and date"
cat > "$WORK/c12.md" <<'FIX'
## Comment 1 - Darin Drobinski - 2026-09-05T02:00:00.000Z

## Go - build and open the PR (Darin, September 4, 2026)

Stage: build and open the PR - everything in build, plus a pull request.
FIX
resolve "$WORK/c12.md" DRO-21
assert_eq "stage line" "Stage: build and open the PR, per Go from Darin on Sep 4." "$(field stage_line)"
assert_eq "go_author is the header author" "Darin Drobinski" "$(field go_author)"
assert_eq "stage" "build and open the PR" "$(field stage)"

begin_test "author is the greedy middle of the header"
cat > "$WORK/c13.md" <<'FIX'
## Comment 4 - Ada - Lovelace - 2026-10-31T10:00:00Z

## Go - plan (Ada, October 1, 2026)
FIX
resolve "$WORK/c13.md" DRO-21
assert_eq "author keeps inner dash" "Ada - Lovelace" "$(field go_author)"
assert_eq "no leading zero on day, abbreviated month" "Stage: plan, per Go from Ada on Oct 1." "$(field stage_line)"

begin_test "Go file is byte-identical"
cat > "$WORK/c14.md" <<'FIX'
# DRO-21 comments, oldest first

## Comment 1 - Someone - 2026-10-29T10:00:00Z

Just a remark.

## Comment 2 - Darin - 2026-10-31T10:00:00Z


## Go - build (Darin, October 31, 2026)

Stage: build - code on a branch, with tests and review. No pull request.

Run rules: last updated May 14, 2026 (from your Team run rules)

These rules shape how the work runs. They never widen the stage above.

## Run rules

- Merging always needs my yes.
Workflow prompts: answer them yourself.


## Reply 3 - Someone - 2026-10-31T11:00:00Z

A reply.
FIX
cat > "$WORK/c14.expected" <<'FIX'
## Go - build (Darin, October 31, 2026)

Stage: build - code on a branch, with tests and review. No pull request.

Run rules: last updated May 14, 2026 (from your Team run rules)

These rules shape how the work runs. They never widen the stage above.

## Run rules

- Merging always needs my yes.
Workflow prompts: answer them yourself.
FIX
resolve "$WORK/c14.md" DRO-21 "$WORK/c14.go"
assert_eq "go=found" "found" "$(field go)"
assert_file_exists "go file written" "$WORK/c14.go"
if cmp -s "$WORK/c14.go" "$WORK/c14.expected"; then
  echo "  PASS: go file matches the comment body byte for byte"
  PASS=$((PASS + 1))
else
  echo "  FAIL: go file differs from the comment body"
  diff "$WORK/c14.expected" "$WORK/c14.go" || true
  FAIL=$((FAIL + 1))
fi

begin_test "Go file not created unless found"
for f in c2 c8 c6; do
  rm -f "$WORK/$f.go"
  resolve "$WORK/$f.md" DRO-21 "$WORK/$f.go"
  assert_file_not_exists "no go file for $f ($(field go))" "$WORK/$f.go"
done

begin_test "bad args exit 1"
resolve "$WORK/nope.md" DRO-21
assert_eq "missing file exits 1" "1" "$CODE"
assert_eq "missing file: empty stdout" "" "$OUT"
assert_eq "missing file: one stderr line" "1" "$(wc -l < "$WORK/stderr" | tr -d ' ')"
resolve "$WORK/c2.md" ""
assert_eq "empty KEY exits 1" "1" "$CODE"
assert_eq "empty KEY: empty stdout" "" "$OUT"
resolve
assert_eq "no args exits 1" "1" "$CODE"
assert_eq "no args: empty stdout" "" "$OUT"
resolve "$WORK/c2.md" DRO-21 "$WORK/x.go" extra
assert_eq "too many args exits 1" "1" "$CODE"
assert_eq "too many args: empty stdout" "" "$OUT"

echo ""
finish_tests
