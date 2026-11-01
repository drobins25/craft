#!/bin/bash
# test-cycle-stage.sh - Tests for cycle-stage.sh, the implementation stage reader

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/minimal.sh"

CREATE_CYCLE_SCRIPT="$SCRIPTS_DIR/create-cycle.sh"
STAGE_SCRIPT="$SCRIPTS_DIR/cycle-stage.sh"
TS="2026-10-31T23:40:12.000Z"

echo "=== test-cycle-stage.sh ==="
echo ""

# make_cycle <issue> <stage> <author> <date> - via create-cycle.sh; sets CYCLE
make_cycle() {
  TEST_DIR=$(create_minimal_craft)
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" auth "Auth" "Login" "$TEST_DIR" "" "$@" >/dev/null 2>&1
  CYCLE="$TEST_DIR/.craft/cycles/1-auth"
}

# make_raw_cycle <lines...> - hand-written cycle.yaml with the given extra lines
make_raw_cycle() {
  TEST_DIR=$(create_minimal_craft)
  CYCLE="$TEST_DIR/.craft/cycles/1-auth"
  mkdir -p "$CYCLE"
  { printf 'name: auth\ntitle: "Cycle 01: Auth"\nstatus: planning\nsource_concept: []\n'
    for l in "$@"; do printf '%s\n' "$l"; done
    printf '\ngoals:\n  - TBD\n'; } > "$CYCLE/cycle.yaml"
}

# stage_out <key> - the value of one output line
stage_out() { printf '%s\n' "$OUT" | grep "^$1=" | head -1 | sed "s/^$1=//"; }

run_stage() {
  set +e
  OUT=$(bash "$STAGE_SCRIPT" "$CYCLE" 2>/dev/null)
  EXIT_CODE=$?
  set -e
}

begin_test "No source_issue = yes"
make_cycle
run_stage
assert_eq "exits 0" "0" "$EXIT_CODE"
assert_eq "implement" "yes" "$(stage_out implement)"
assert_eq "say empty" "" "$(stage_out say)"
assert_eq "four lines in order" "implement stage source_issue say" "$(printf '%s\n' "$OUT" | sed 's/=.*//' | tr '\n' ' ' | sed 's/ $//')"
cleanup_test_dir; echo ""

begin_test "Empty source_issue = yes"
make_raw_cycle "source_issue: ''" "authorized_stage: 'plan'"
run_stage
assert_eq "implement" "yes" "$(stage_out implement)"
cleanup_test_dir; echo ""

begin_test "build = yes"
make_cycle "DRO-21" "build" "Darin" "$TS"
run_stage
assert_eq "implement" "yes" "$(stage_out implement)"
assert_eq "stage" "build" "$(stage_out stage)"
assert_eq "source_issue" "DRO-21" "$(stage_out source_issue)"
assert_eq "say empty" "" "$(stage_out say)"
cleanup_test_dir; echo ""

begin_test "build and open the PR = yes"
make_cycle "DRO-21" "build and open the PR" "Darin" "$TS"
run_stage
assert_eq "implement" "yes" "$(stage_out implement)"
assert_eq "stage" "build and open the PR" "$(stage_out stage)"
cleanup_test_dir; echo ""

begin_test "plan with author stops with exact say"
make_cycle "DRO-21" "plan" "Darin Drobinski" "$TS"
run_stage
assert_eq "implement" "no" "$(stage_out implement)"
assert_eq "say" "Stage for DRO-21 is plan, per the Go from Darin Drobinski, so I stop before implementing. Building needs a newer Go on DRO-21 that says build." "$(stage_out say)"
cleanup_test_dir; echo ""

begin_test "plan without author"
make_cycle "DRO-21" "plan" "" ""
run_stage
assert_eq "implement" "no" "$(stage_out implement)"
assert_eq "say" "Stage for DRO-21 is plan because no Go was read from it when this cycle was made, so I stop before implementing. Building needs a Go on DRO-21 that says build." "$(stage_out say)"
cleanup_test_dir; echo ""

begin_test "hold with author"
make_raw_cycle "source_issue: 'DRO-21'" "authorized_stage: 'hold'" "go_author: 'Darin'" "go_date: '$TS'"
run_stage
assert_eq "implement" "no" "$(stage_out implement)"
assert_eq "say" "DRO-21 is on hold, per the Go from Darin, so I'm not starting anything new." "$(stage_out say)"
cleanup_test_dir; echo ""

begin_test "hold without author"
make_raw_cycle "source_issue: 'DRO-21'" "authorized_stage: 'hold'" "go_author: ''" "go_date: ''"
run_stage
assert_eq "say" "DRO-21 is on hold, per its newest Go, so I'm not starting anything new." "$(stage_out say)"
cleanup_test_dir; echo ""

begin_test "missing stage"
make_raw_cycle "source_issue: 'DRO-21'"
run_stage
assert_eq "implement" "no" "$(stage_out implement)"
assert_eq "say" "This cycle names DRO-21 but records no stage I know, so I stop before implementing." "$(stage_out say)"
cleanup_test_dir; echo ""

begin_test "empty stage"
make_raw_cycle "source_issue: 'DRO-21'" "authorized_stage: ''"
run_stage
assert_eq "implement" "no" "$(stage_out implement)"
assert_eq "say" "This cycle names DRO-21 but records no stage I know, so I stop before implementing." "$(stage_out say)"
cleanup_test_dir; echo ""

begin_test "unknown stage"
make_raw_cycle "source_issue: 'DRO-21'" "authorized_stage: 'ship'"
run_stage
assert_eq "implement" "no" "$(stage_out implement)"
assert_eq "stage echoed" "ship" "$(stage_out stage)"
assert_eq "say" "This cycle names DRO-21 but records no stage I know, so I stop before implementing." "$(stage_out say)"
cleanup_test_dir; echo ""

begin_test "Doubled quotes are un-doubled"
make_raw_cycle "source_issue: 'DRO-21'" "authorized_stage: 'plan'" "go_author: 'Darin O''Neil'" "go_date: '$TS'"
run_stage
assert_contains "author un-doubled" "per the Go from Darin O'Neil," "$(stage_out say)"
cleanup_test_dir; echo ""

begin_test "Never writes"
make_cycle "DRO-21" "plan" "Darin" "$TS"
BEFORE=$(find "$CYCLE" -type f -exec cksum {} + | sort)
run_stage
AFTER=$(find "$CYCLE" -type f -exec cksum {} + | sort)
assert_eq "cycle dir unchanged" "$BEFORE" "$AFTER"
cleanup_test_dir; echo ""

begin_test "No cycle.yaml exits 1"
TEST_DIR=$(create_minimal_craft)
CYCLE="$TEST_DIR/.craft/cycles/9-none"
mkdir -p "$CYCLE"
set +e
OUT=$(bash "$STAGE_SCRIPT" "$CYCLE" 2>/dev/null)
EXIT_CODE=$?
set -e
assert_eq "exits 1" "1" "$EXIT_CODE"
assert_eq "nothing on stdout" "" "$OUT"
cleanup_test_dir; echo ""

finish_tests
