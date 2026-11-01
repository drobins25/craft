#!/bin/bash
# test-find-issue-cycle.sh - Tests for find-issue-cycle.py
# A repeat pickup must find the one live cycle that already records an issue:
# planning, ready and active count, complete never does, the newest number wins.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

FINDER="$SCRIPTS_DIR/find-issue-cycle.py"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# cycle <root> <dir-name> <status> [<source_issue line>]
cycle() {
  mkdir -p "$1/.craft/cycles/$2"
  {
    echo "name: $2"
    echo "status: $3"
    [ -n "${4:-}" ] && echo "$4"
    echo "source_concept: []"
  } > "$1/.craft/cycles/$2/cycle.yaml"
  return 0
}

# find <args...> -> stdout in $OUT, exit code in $CODE
find_cycle() {
  set +e
  OUT=$(python3 "$FINDER" "$@" 2>"$WORK/stderr")
  CODE=$?
  set -e
}

field() {
  printf '%s\n' "$OUT" | sed -n "s/^$1=//p"
}

echo "=== test-find-issue-cycle.sh ==="
echo ""

begin_test "complete excluded, highest wins"
R="$WORK/r1"
cycle "$R" 1-a complete "source_issue: 'DRO-21'"
cycle "$R" 2-b active "source_issue: 'DRO-21'"
cycle "$R" 3-c planning "source_issue: 'DRO-21'"
find_cycle DRO-21 "$R"
assert_eq "exits 0" "0" "$CODE"
assert_eq "three lines" "3" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
assert_eq "highest live cycle" "$R/.craft/cycles/3-c" "$(field cycle_dir)"
assert_eq "its status" "planning" "$(field status)"
assert_eq "complete one is not counted" "2" "$(field matches)"

begin_test "numbers compare as numbers, not text"
R="$WORK/r2"
cycle "$R" 9-a ready "source_issue: 'DRO-21'"
cycle "$R" 10-b active "source_issue: 'DRO-21'"
find_cycle DRO-21 "$R"
assert_eq "10 beats 9" "$R/.craft/cycles/10-b" "$(field cycle_dir)"
assert_eq "status of the winner" "active" "$(field status)"

begin_test "ready counts"
R="$WORK/r3"
cycle "$R" 1-a ready "source_issue: 'DRO-21'"
find_cycle DRO-21 "$R"
assert_eq "ready cycle found" "ready" "$(field status)"

begin_test "case-insensitive key"
find_cycle dro-21 "$R"
assert_eq "lowercase arg matches" "$R/.craft/cycles/1-a" "$(field cycle_dir)"
find_cycle DRO-21 "$R"
cycle "$WORK/r3b" 1-a planning "source_issue: 'dro-21'"
find_cycle DRO-21 "$WORK/r3b"
assert_eq "lowercase record matches" "$WORK/r3b/.craft/cycles/1-a" "$(field cycle_dir)"

begin_test "another issue, complete-only, freeform and bare keys never match"
R="$WORK/r4"
cycle "$R" 1-a planning "source_issue: 'DRO-22'"
cycle "$R" 2-b complete "source_issue: 'DRO-21'"
cycle "$R" 3-c planning
cycle "$R" 4-d active "source_issue: ''"
find_cycle DRO-21 "$R"
assert_eq "exits 0" "0" "$CODE"
assert_eq "no cycle_dir" "" "$(field cycle_dir)"
assert_eq "no status" "" "$(field status)"
assert_eq "no matches" "0" "$(field matches)"
assert_eq "three lines even when empty" "3" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"

begin_test "an unquoted source_issue still matches,"
R="$WORK/r5"
cycle "$R" 1-a planning "source_issue: DRO-21"
find_cycle DRO-21 "$R"
assert_eq "unquoted value" "$R/.craft/cycles/1-a" "$(field cycle_dir)"

begin_test "no .craft folder gives no match, root defaults to ."
find_cycle DRO-21 "$WORK/nothing-here"
assert_eq "exits 0" "0" "$CODE"
assert_eq "no matches" "0" "$(field matches)"
mkdir -p "$WORK/r6"
cycle "$WORK/r6" 1-a active "source_issue: 'DRO-21'"
OUT=$(cd "$WORK/r6" && python3 "$FINDER" DRO-21)
assert_eq "default root is the current folder" "active" "$(field status)"

begin_test "never writes"
R="$WORK/r7"
cycle "$R" 1-a active "source_issue: 'DRO-21'"
before=$(cksum "$R/.craft/cycles/1-a/cycle.yaml")
find_cycle DRO-21 "$R"
assert_eq "cycle.yaml untouched" "$before" "$(cksum "$R/.craft/cycles/1-a/cycle.yaml")"
assert_eq "no extra files" "1" "$(ls "$R/.craft/cycles/1-a" | wc -l | tr -d ' ')"

begin_test "wrong arg count exits 1"
find_cycle
assert_eq "no args" "1" "$CODE"
assert_eq "no args: empty stdout" "" "$OUT"
find_cycle DRO-21 "$R" extra
assert_eq "too many args" "1" "$CODE"
assert_eq "too many args: empty stdout" "" "$OUT"

echo ""
finish_tests
