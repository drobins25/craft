#!/bin/bash
# test-get-latest-cycle.sh - Behavior tests for get-latest-cycle.sh, including
# the --status filter that finds a completed cycle after ACTIVE_CYCLE is cleared.
# Usage: bash tests/test-get-latest-cycle.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

SCRIPT="$SCRIPTS_DIR/get-latest-cycle.sh"
TMP_ROOTS=()

cleanup_roots() {
  local r
  for r in "${TMP_ROOTS[@]:-}"; do [ -n "$r" ] && rm -rf "$r"; done
  return 0
}
trap cleanup_roots EXIT

# add_cycle <root> <folder> <status|-> : status "-" writes a cycle.yaml with no status line
add_cycle() {
  local root="$1" folder="$2" status="$3"
  mkdir -p "$root/.craft/cycles/$folder/stories"
  {
    echo "title: Cycle $folder"
    [ "$status" != "-" ] && echo "status: $status"
  } > "$root/.craft/cycles/$folder/cycle.yaml"
  return 0
}

fresh_root() {
  ROOT=$(mktemp -d)
  TMP_ROOTS+=("$ROOT")
  add_cycle "$ROOT" 1-a complete
  add_cycle "$ROOT" 2-b complete
  add_cycle "$ROOT" 3-c active
  add_cycle "$ROOT" 10-d planning
}

begin_test "unfiltered output unchanged"
fresh_root
OUT=$(bash "$SCRIPT" "$ROOT")
EXPECTED='LATEST_CYCLE=10-d
CYCLE_TITLE=Cycle 10-d
CYCLE_STATUS=planning
STORIES_TOTAL=0
STORIES_READY=0
STORIES_COMPLETE=0
STORIES_PLANNING=0'
assert_eq "full block for highest-numbered cycle" "$EXPECTED" "$OUT"

begin_test "an empty-string root means the current directory, as before the flag"
fresh_root
OUT=$(cd "$ROOT" && bash "$SCRIPT" "")
assert_eq "empty root resolves to cwd" "$EXPECTED" "$OUT"
OUT=$(cd "$ROOT" && bash "$SCRIPT" "" --status=complete)
assert_contains "empty root with the filter still finds the cycle" '^LATEST_CYCLE=2-b$' "$OUT"

begin_test "--status=complete picks 2-b, flag before or after the root"
fresh_root
AFTER=$(bash "$SCRIPT" "$ROOT" --status=complete)
BEFORE=$(bash "$SCRIPT" --status=complete "$ROOT")
assert_contains_literal "flag after root" 'LATEST_CYCLE=2-b' "$AFTER"
assert_contains_literal "status line reflects filter" 'CYCLE_STATUS=complete' "$AFTER"
assert_eq "flag before root gives same output" "$AFTER" "$BEFORE"

begin_test "--status with no match prints empty LATEST_CYCLE and rc 0"
fresh_root
set +e
OUT=$(bash "$SCRIPT" "$ROOT" --status=abandoned)
RC=$?
set -e
assert_eq "output" 'LATEST_CYCLE=' "$OUT"
assert_eq "exit code" "0" "$RC"

begin_test "a cycle.yaml with no status line is skipped, not fatal"
fresh_root
add_cycle "$ROOT" 11-e -
set +e
OUT=$(bash "$SCRIPT" "$ROOT" --status=complete)
RC=$?
set -e
assert_eq "exit code" "0" "$RC"
assert_contains_literal "falls through to 2-b" 'LATEST_CYCLE=2-b' "$OUT"

finish_tests
