#!/bin/bash
# test-record-go.sh - Tests for record-go.py
# A later read of an issue must re-resolve the newest Go from only the new
# comments, record it in cycle.yaml only when it changed, keep every other
# line byte-identical, and say the stage line by substitution.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
# Run from a throwaway folder: a script that misreads its arguments and falls back
# to the current folder must never write into the real project.
cd "$(mktemp -d)"

RECORD="$SCRIPTS_DIR/record-go.py"
CREATE_CYCLE="$SCRIPTS_DIR/create-cycle.sh"
STAGE="$SCRIPTS_DIR/cycle-stage.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# project <name> [<stage> <author> <date>] -> temp project with a DRO-21 cycle
# (no stage args: the issue had no Go, so only source_issue is recorded)
project() {
  local root="$WORK/$1"
  shift
  mkdir -p "$root/.craft"
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE" intake "Intake" "TBD" "$root" "" \
    "DRO-21" "$@" >/dev/null 2>&1
  CYCLE="$root/.craft/cycles/1-intake"
  CTX="$CYCLE/context"
  mkdir -p "$CTX"
  cat > "$CTX/README.md" <<'FIX'
# DRO-21 context

| File | What | Retrieved | Tool |
|---|---|---|---|
| dro-21-comments-2026-10-31T1840Z.md | Every comment, oldest first | 2026-10-31T18:40:12Z | linear |
FIX
  DELTA="$CTX/dro-21-comments-2026-11-02T1015Z.md"
}

# delta <heading line> [<author>] -> a one-comment delta holding that body first line
delta() {
  cat > "$DELTA" <<FIX
# DRO-21 comments added since 2026-10-31T1840Z, oldest first

## Comment 3 - ${2:-Darin Drobinski} - 2026-11-02T15:00:00.000Z

$1

Scope: everything.
FIX
}

run() {
  set +e
  OUT=$(python3 "$RECORD" "$@" 2>"$WORK/stderr")
  CODE=$?
  set -e
}

field() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }
stage_field() { bash "$STAGE" "$CYCLE" | sed -n "s/^$1=//p"; }

echo "=== test-record-go.sh ==="
echo ""

begin_test "plan to build"
project p2b plan "" ""
delta "## Go - build (Darin, November 2, 2026)"
run "$CYCLE" "$DELTA"
assert_eq "exit 0" "0" "$CODE"
assert_eq "four lines" "4" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
assert_eq "changed" "yes" "$(field changed)"
assert_eq "old_stage" "plan" "$(field old_stage)"
assert_eq "stage" "build" "$(field stage)"
assert_eq "say" "Stage changed: plan to build, per Go from Darin on Nov 2." "$(field say)"
assert_eq "stage recorded" "1" "$(grep -c "^authorized_stage: 'build'$" "$CYCLE/cycle.yaml")"
assert_eq "author recorded" "1" "$(grep -c "^go_author: 'Darin Drobinski'$" "$CYCLE/cycle.yaml")"
assert_eq "date recorded" "1" "$(grep -c "^go_date: '2026-11-02T15:00:00.000Z'$" "$CYCLE/cycle.yaml")"
assert_file_exists "go copy" "$CTX/dro-21-go-2026-11-02T1015Z.md"
assert_eq "go copy is the Go body" "## Go - build (Darin, November 2, 2026)" "$(head -1 "$CTX/dro-21-go-2026-11-02T1015Z.md")"
assert_eq "one README row added" "2" "$(grep -c '^| dro-21-' "$CTX/README.md")"
assert_contains_literal "README Go row" "| dro-21-go-2026-11-02T1015Z.md | Newest Go: comment 3, Darin Drobinski, 2026-11-02T15:00:00.000Z |" "$(cat "$CTX/README.md")"
assert_contains_literal "README row names the resolver" "| resolve-go.py |" "$(cat "$CTX/README.md")"

begin_test "same stage, newer Go"
project same build "Darin Drobinski" "2026-10-31T18:40:00.000Z"
delta "## Go - build (Darin, November 2, 2026)"
run "$CYCLE" "$DELTA"
assert_eq "changed" "yes" "$(field changed)"
assert_eq "say" "Stage unchanged: build, per Go from Darin on Nov 2." "$(field say)"
assert_eq "new date recorded" "1" "$(grep -c "^go_date: '2026-11-02T15:00:00.000Z'$" "$CYCLE/cycle.yaml")"

begin_test "identical record writes nothing"
project ident build "Darin Drobinski" "2026-11-02T15:00:00.000Z"
delta "## Go - build (Darin, November 2, 2026)"
before=$(cksum < "$CYCLE/cycle.yaml")
run "$CYCLE" "$DELTA"
assert_eq "changed no" "no" "$(field changed)"
assert_eq "cycle.yaml untouched" "$before" "$(cksum < "$CYCLE/cycle.yaml")"
assert_eq "no go copy" "0" "$(ls "$CTX" | grep -c -- '-go-')"
assert_eq "no README row" "1" "$(grep -c '^| dro-21-' "$CTX/README.md")"

begin_test "hold recorded, cycle-stage stops"
project hold build "Darin Drobinski" "2026-10-31T18:40:00.000Z"
delta "## Go - hold (Darin, November 2, 2026)"
run "$CYCLE" "$DELTA"
assert_eq "stage" "hold" "$(field stage)"
assert_eq "say" "Stage changed: build to hold, per Go from Darin on Nov 2." "$(field say)"
assert_eq "stage recorded" "1" "$(grep -c "^authorized_stage: 'hold'$" "$CYCLE/cycle.yaml")"
assert_eq "cycle-stage stops" "no" "$(stage_field implement)"
assert_contains_literal "hold say" "is on hold, per the Go from Darin Drobinski" "$(stage_field say)"

begin_test "no delta keeps record"
project nodelta build "Darin Drobinski" "2026-10-31T18:40:00.000Z"
printf '## Go - build (Darin, October 31, 2026)\n\nScope: x\n' > "$CTX/dro-21-go-2026-10-31T1840Z.md"
before=$(cksum < "$CYCLE/cycle.yaml")
run "$CYCLE"
assert_eq "changed no" "no" "$(field changed)"
assert_eq "old_stage" "build" "$(field old_stage)"
assert_eq "stage" "build" "$(field stage)"
assert_eq "say from the go copy heading" "Stage unchanged: build, per Go from Darin on Oct 31." "$(field say)"
assert_eq "cycle.yaml untouched" "$before" "$(cksum < "$CYCLE/cycle.yaml")"

begin_test "no delta, plan with no author or no copy"
project plain plan "" ""
run "$CYCLE"
assert_eq "say" "Stage unchanged: plan, because DRO-21 has no readable Go." "$(field say)"
project nocopy build "Darin Drobinski" "2026-10-31T18:40:00.000Z"
run "$CYCLE"
assert_eq "no copy gives the no-readable-Go say" "Stage unchanged: plan, because DRO-21 has no readable Go." "$(field say)"

begin_test "delta without a Go keeps record"
project nogo build "Darin Drobinski" "2026-10-31T18:40:00.000Z"
printf '## Go - build (Darin, October 31, 2026)\n\nScope: x\n' > "$CTX/dro-21-go-2026-10-31T1840Z.md"
delta "Just a thought."
before=$(cksum < "$CYCLE/cycle.yaml")
run "$CYCLE" "$DELTA"
assert_eq "changed no" "no" "$(field changed)"
assert_eq "say" "Stage unchanged: build, per Go from Darin on Oct 31." "$(field say)"
assert_eq "cycle.yaml untouched" "$before" "$(cksum < "$CYCLE/cycle.yaml")"

begin_test "unreadable narrows"
project unread build "Darin Drobinski" "2026-10-31T18:40:00.000Z"
delta "## Go - ship (Darin, November 2, 2026)"
run "$CYCLE" "$DELTA"
assert_eq "changed" "yes" "$(field changed)"
assert_eq "stage" "plan" "$(field stage)"
assert_contains_literal "say" "Stage changed: build to plan. The newest Go on DRO-21" "$(field say)"
assert_eq "stage recorded" "1" "$(grep -c "^authorized_stage: 'plan'$" "$CYCLE/cycle.yaml")"
assert_eq "author emptied" "1" "$(grep -c "^go_author: ''$" "$CYCLE/cycle.yaml")"
assert_eq "date emptied" "1" "$(grep -c "^go_date: ''$" "$CYCLE/cycle.yaml")"
assert_eq "no go copy written" "0" "$(ls "$CTX" | grep -c -- '-go-')"
run "$CYCLE" "$DELTA"
assert_eq "second run: unchanged" "no" "$(field changed)"
assert_contains_literal "second run say" "Stage unchanged: plan. The newest Go on DRO-21" "$(field say)"

begin_test "only three lines change"
project three build "Someone Else" "2026-10-31T18:40:00.000Z"
cp "$CYCLE/cycle.yaml" "$WORK/before.yaml"
delta "## Go - build and open the PR (Darin, November 2, 2026)"
run "$CYCLE" "$DELTA"
changed_lines=$(diff "$WORK/before.yaml" "$CYCLE/cycle.yaml" | grep -c '^>' || true)
assert_eq "three lines differ" "3" "$changed_lines"
assert_eq "diff touches only the record keys" "0" "$(diff "$WORK/before.yaml" "$CYCLE/cycle.yaml" | grep '^[<>]' | grep -vcE '^[<>] (authorized_stage|go_author|go_date):' || true)"
assert_eq "stage with spaces" "1" "$(grep -c "^authorized_stage: 'build and open the PR'$" "$CYCLE/cycle.yaml")"

begin_test "author with apostrophe round-trips"
project apos build "Darin Drobinski" "2026-10-31T18:40:00.000Z"
delta "## Go - plan (Darin, November 2, 2026)" "Pat O'Brien"
run "$CYCLE" "$DELTA"
assert_eq "stored doubled" "1" "$(grep -c "^go_author: 'Pat O''Brien'$" "$CYCLE/cycle.yaml")"
assert_contains_literal "cycle-stage reads it back" "per the Go from Pat O'Brien" "$(stage_field say)"

begin_test "no-Go record, Go arrives"
project nogoarrives
assert_eq "no stage line to start" "0" "$(grep -c '^authorized_stage:' "$CYCLE/cycle.yaml")"
cp "$CYCLE/cycle.yaml" "$WORK/before.yaml"
delta "## Go - build (Darin, November 2, 2026)"
run "$CYCLE" "$DELTA"
assert_eq "changed" "yes" "$(field changed)"
assert_eq "old_stage empty" "" "$(field old_stage)"
assert_eq "say" "Stage changed: none to build, per Go from Darin on Nov 2." "$(field say)"
assert_eq "three lines inserted" "3" "$(diff "$WORK/before.yaml" "$CYCLE/cycle.yaml" | grep -c '^>' || true)"
assert_eq "nothing removed" "0" "$(diff "$WORK/before.yaml" "$CYCLE/cycle.yaml" | grep -c '^<' || true)"
order=$(grep -n -A3 '^source_issue:' "$CYCLE/cycle.yaml" | sed 's/^[0-9]*[-:]//' | cut -d: -f1 | tr '\n' ' ')
assert_eq "inserted after source_issue in order" "source_issue authorized_stage go_author go_date " "$order"
assert_eq "cycle-stage reads build" "build" "$(stage_field stage)"
assert_eq "cycle-stage lets it implement" "yes" "$(stage_field implement)"

begin_test "no-Go record, unreadable Go arrives"
project nogounread
delta "## Go - ship (Darin, November 2, 2026)"
run "$CYCLE" "$DELTA"
assert_contains_literal "say" "Stage changed: none to plan. The newest Go on DRO-21" "$(field say)"
assert_eq "plan recorded" "1" "$(grep -c "^authorized_stage: 'plan'$" "$CYCLE/cycle.yaml")"
assert_eq "cycle-stage stops" "no" "$(stage_field implement)"

begin_test "no-Go record, no Go in delta"
project nogonone
delta "Just a thought."
before=$(cksum < "$CYCLE/cycle.yaml")
run "$CYCLE" "$DELTA"
assert_eq "changed no" "no" "$(field changed)"
assert_eq "old_stage empty" "" "$(field old_stage)"
assert_eq "say" "No Go on DRO-21, so craft works as usual: you decide when to build." "$(field say)"
assert_eq "cycle.yaml untouched" "$before" "$(cksum < "$CYCLE/cycle.yaml")"
run "$CYCLE"
assert_eq "no delta: same say" "No Go on DRO-21, so craft works as usual: you decide when to build." "$(field say)"

begin_test "partial record rejected"
project partial build "Darin Drobinski" "2026-10-31T18:40:00.000Z"
sed -e '/^go_date:/d' "$CYCLE/cycle.yaml" > "$WORK/p.yaml" && cp "$WORK/p.yaml" "$CYCLE/cycle.yaml"
delta "## Go - hold (Darin, November 2, 2026)"
before=$(cksum < "$CYCLE/cycle.yaml")
run "$CYCLE" "$DELTA"
assert_eq "exit 1" "1" "$CODE"
assert_eq "no stdout" "" "$OUT"
assert_eq "one stderr line" "1" "$(wc -l < "$WORK/stderr" | tr -d ' ')"
assert_eq "cycle.yaml untouched" "$before" "$(cksum < "$CYCLE/cycle.yaml")"
assert_eq "no go copy" "0" "$(ls "$CTX" | grep -c -- '-go-')"

begin_test "refuses without cycle.yaml, source_issue or a readable delta"
run "$WORK/nowhere"
assert_eq "no cycle.yaml exits 1" "1" "$CODE"
project empty build "Darin Drobinski" "2026-10-31T18:40:00.000Z"
run "$CYCLE" "$WORK/missing.md"
assert_eq "unreadable delta exits 1" "1" "$CODE"
assert_eq "unreadable delta writes no go copy" "0" "$(ls "$CTX" | grep -c -- '-go-')"
sed -e "s/^source_issue: .*/source_issue: ''/" "$CYCLE/cycle.yaml" > "$WORK/e.yaml" && cp "$WORK/e.yaml" "$CYCLE/cycle.yaml"
delta "## Go - hold (Darin, November 2, 2026)"
run "$CYCLE" "$DELTA"
assert_eq "empty source_issue exits 1" "1" "$CODE"
run
assert_eq "no args exits 1" "1" "$CODE"

begin_test "hold from a no-Go record is recorded"
project nogohold
delta "## Go - hold (Darin, November 2, 2026)"
run "$CYCLE" "$DELTA"
assert_eq "say" "Stage changed: none to hold, per Go from Darin on Nov 2." "$(field say)"
assert_eq "cycle-stage stops" "no" "$(stage_field implement)"

begin_test "a failed cycle.yaml write leaves no Go copy behind"
project yamlfail plan "" ""
delta "## Go - build (Darin, November 2, 2026)"
chmod 555 "$CYCLE"
run "$CYCLE" "$DELTA"
chmod 755 "$CYCLE"
assert_eq "exits 1" "1" "$CODE"
assert_eq "no go copy" "0" "$(ls "$CTX" | grep -c -- '-go-')"
assert_eq "no README row" "1" "$(grep -c '^| dro-21-' "$CTX/README.md")"
run "$CYCLE" "$DELTA"
assert_eq "retry exits 0" "0" "$CODE"
assert_eq "retry changed" "yes" "$(field changed)"

begin_test "an identical Go copy left by an earlier run does not block a retry"
project leftover plan "" ""
delta "## Go - build (Darin, November 2, 2026)"
run "$CYCLE" "$DELTA"
cp "$CTX/dro-21-go-2026-11-02T1015Z.md" "$WORK/copy.md"
project leftover2 plan "" ""
delta "## Go - build (Darin, November 2, 2026)"
cp "$WORK/copy.md" "$CTX/dro-21-go-2026-11-02T1015Z.md"
run "$CYCLE" "$DELTA"
assert_eq "exits 0" "0" "$CODE"
assert_eq "changed" "yes" "$(field changed)"
assert_eq "stage recorded" "1" "$(grep -c "^authorized_stage: 'build'$" "$CYCLE/cycle.yaml")"
assert_eq "copy kept as it was" "$(cksum < "$WORK/copy.md")" "$(cksum < "$CTX/dro-21-go-2026-11-02T1015Z.md")"

begin_test "a different file at the Go copy's name is not overwritten"
project clash plan "" ""
delta "## Go - build (Darin, November 2, 2026)"
printf 'someone else\n' > "$CTX/dro-21-go-2026-11-02T1015Z.md"
run "$CYCLE" "$DELTA"
assert_eq "exits 1" "1" "$CODE"
assert_eq "file left alone" "someone else" "$(cat "$CTX/dro-21-go-2026-11-02T1015Z.md")"

echo ""
finish_tests
