#!/bin/bash
# test-run-mode-reset.sh - Autonomous mode ends with the run that set it.
#
# /craft:story-implement-auto marks RUN_MODE="autonomous" so compaction
# recovery can resume it. Nothing used to clear it, so every later attended
# session took the unattended branches. Pins both resets:
#   - session-start clears a leftover RUN_MODE when no story holds it, and
#     keeps it while a story is in progress (a live run);
#   - implement-auto sets it only once a run will start, and turns it off at
#     every exit, after any cycle-complete call returns.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/minimal.sh"

SESSION_SCRIPT="$SCRIPTS_DIR/session-start.sh"
AUTO="$PLUGIN_ROOT/commands/craft-story-implement-auto.md"

echo "=== test-run-mode-reset.sh ==="
echo ""

read_state_key() {
  local key="$1" root="$2"
  grep "^${key}=" "$root/.craft/.global-state" 2>/dev/null | sed "s/${key}=\"\(.*\)\"/\1/"
}

# run_session <test-dir> - run session-start.sh from the fixture, print its exit code
run_session() {
  local dir="$1" env_file rc
  env_file=$(mktemp)
  set +e
  (cd "$dir" && unset PROJECT_ROOT && unset CRAFT_PROJECT_ROOT && unset CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$env_file" && bash "$SESSION_SCRIPT" >/dev/null 2>&1)
  rc=$?
  set -e
  rm -f "$env_file"
  echo "$rc"
}

begin_test "a leftover autonomous mode with no story in progress is cleared at session start"
TEST_DIR=$(create_minimal_craft)
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
RUN_MODE="autonomous"
LAST_ACTIVITY=""
CRAFT_WRITE_ENABLED=""
CURRENT_WORKFLOW_SESSION=""
EOF
RC=$(run_session "$TEST_DIR")
assert_eq "exits 0" "0" "$RC"
assert_eq "run mode cleared" "" "$(read_state_key RUN_MODE "$TEST_DIR")"
assert_eq "key kept, value empty" "1" "$(grep -c '^RUN_MODE=""$' "$TEST_DIR/.craft/.global-state" || true)"
cleanup_test_dir
echo ""

begin_test "autonomous mode survives while a story is in progress"
TEST_DIR=$(create_minimal_craft)
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test"
CURRENT_STORY="some-story"
PLANNING_CYCLE=""
RUN_MODE="autonomous"
LAST_ACTIVITY=""
CRAFT_WRITE_ENABLED="true"
CURRENT_WORKFLOW_SESSION=""
EOF
RC=$(run_session "$TEST_DIR")
assert_eq "exits 0" "0" "$RC"
assert_eq "run mode preserved with story in progress" "autonomous" "$(read_state_key RUN_MODE "$TEST_DIR")"
cleanup_test_dir
echo ""

begin_test "autonomous mode survives a live run's gap between stories (recent activity)"
TEST_DIR=$(create_minimal_craft)
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$TEST_DIR/.craft/.global-state" << EOF
ACTIVE_CYCLE="1-test"
CURRENT_STORY=""
PLANNING_CYCLE=""
RUN_MODE="autonomous"
LAST_ACTIVITY="$NOW_TS"
CRAFT_WRITE_ENABLED=""
CURRENT_WORKFLOW_SESSION=""
EOF
RC=$(run_session "$TEST_DIR")
assert_eq "exits 0" "0" "$RC"
assert_eq "run mode preserved with recent activity" "autonomous" "$(read_state_key RUN_MODE "$TEST_DIR")"
cleanup_test_dir
echo ""

begin_test "autonomous mode with no story and old activity is cleared"
TEST_DIR=$(create_minimal_craft)
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
RUN_MODE="autonomous"
LAST_ACTIVITY="2020-01-01T00:00:00Z"
CRAFT_WRITE_ENABLED=""
CURRENT_WORKFLOW_SESSION=""
EOF
RC=$(run_session "$TEST_DIR")
assert_eq "exits 0" "0" "$RC"
assert_eq "run mode cleared after two idle hours" "" "$(read_state_key RUN_MODE "$TEST_DIR")"
cleanup_test_dir
echo ""

begin_test "implement-auto stamps activity where it sets autonomous mode"
MODE_BLOCK=$(grep -n -A3 -B3 'update-global-state.sh RUN_MODE "autonomous"' "$AUTO" || true)
assert_contains_literal "refreshes LAST_ACTIVITY beside the mode" 'update-global-state.sh LAST_ACTIVITY NOW' "$MODE_BLOCK"
echo ""

begin_test "a state file with no RUN_MODE key never gains one"
TEST_DIR=$(create_minimal_craft)
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
LAST_ACTIVITY=""
EOF
RC=$(run_session "$TEST_DIR")
assert_eq "exits 0" "0" "$RC"
assert_eq "no RUN_MODE key added" "0" "$(grep -c '^RUN_MODE=' "$TEST_DIR/.craft/.global-state" || true)"
cleanup_test_dir
echo ""

begin_test "implement-auto sets autonomous mode only once a run will start"
SET_LINE=$(grep -nF 'update-global-state.sh RUN_MODE "autonomous"' "$AUTO" | head -1 | cut -d: -f1 || true)
NOCYCLE_LINE=$(grep -nF '| No `ACTIVE_CYCLE` |' "$AUTO" | head -1 | cut -d: -f1 || true)
if [ -n "$SET_LINE" ] && [ -n "$NOCYCLE_LINE" ] && [ "$NOCYCLE_LINE" -lt "$SET_LINE" ]; then
  echo "  PASS: the no-active-cycle exit comes before autonomous mode is set"; PASS=$((PASS + 1))
else
  echo "  FAIL: the no-active-cycle exit comes before autonomous mode is set"
  echo "    no-cycle row line: '${NOCYCLE_LINE}', set line: '${SET_LINE}'"; FAIL=$((FAIL + 1))
fi
echo ""

begin_test "implement-auto turns autonomous mode off at every exit"
RUN_END=$(sed -n '/^## Final Report/,$p' "$AUTO")
assert_not_eq "Final Report section found" "" "$RUN_END"
assert_contains_literal "clears RUN_MODE" 'update-global-state.sh RUN_MODE ""' "$RUN_END"
assert_contains_literal "covers every exit" 'Every exit from this command' "$RUN_END"
assert_contains_literal "runs after cycle-complete returns" 'after it returns' "$RUN_END"
echo ""

finish_tests
