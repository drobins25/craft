#!/bin/bash
# test-workflow-session-gate.sh - A workflow session's writes pass on the gate of the
# Claude Code session running it, never on an active session.md alone.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"
source "$SCRIPT_DIR/fixtures/with-cycle.sh"

START_WF="$SCRIPTS_DIR/start-workflow-session.sh"
COMPLETE_WF="$SCRIPTS_DIR/complete-workflow-session.sh"
START_STORY="$SCRIPTS_DIR/start-story.sh"
COMPLETE_STORY="$SCRIPTS_DIR/complete-story.sh"
GATE="$SCRIPTS_DIR/write-gate.sh"
HOOK="$SCRIPTS_DIR/check-write-permission.py"
INJECT="$SCRIPTS_DIR/inject-craft-context.sh"

SESSION_A="session-a"
SESSION_B="session-b"

# make_wf_session <project> <state: ready|active>: writes one workflow session folder
make_wf_session() {
  local d="$1/.craft/workflows/wf/sessions/s1"
  mkdir -p "$d"
  cat > "$d/session.md" <<EOF
---
name: Lesson One
workflow: wf
status: $2
current_stage: 1
variables:
  topic: x
---

## Progress

| # | Stage | Status |
| 1 | First | pending |
| 2 | Second | pending |

## Stage 1: First [pending]
- [ ] a
EOF
}

fresh_project() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.craft"
  printf 'ACTIVE_CYCLE=""\nCURRENT_STORY=""\nPLANNING_CYCLE=""\nCURRENT_WORKFLOW_SESSION=""\n' > "$d/.craft/.global-state"
  (cd "$d" && pwd -P)
}

# as <id> <cmd...>: run with only that session id, never the builder's project
as() {
  local id="$1"; shift
  env -u CRAFT_PROJECT_ROOT CLAUDE_CODE_SESSION_ID="$id" "$@"
}

gate_of() { cat "$1/.craft/.gate/$2" 2>/dev/null || echo "<none>"; }

hook_decision() { # <project> <session id>
  local json
  json=$(printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"%s/src/app.ts"},"cwd":"%s"}' "$2" "$1" "$1")
  (cd "$1" && env -u CRAFT_PROJECT_ROOT python3 "$HOOK" <<< "$json" 2>/dev/null) || true
}

echo "=== test-workflow-session-gate.sh ==="
echo ""

begin_test "an active workflow session and no gate file: denied; the twin with the session's gate is allowed"
P=$(fresh_project); make_wf_session "$P" active
assert_contains "no gate file: denied" "deny" "$(hook_decision "$P" $SESSION_A)"
mkdir -p "$P/.craft/.gate"; printf 'workflow %s\n' "$P/.craft/workflows/wf/sessions/s1" > "$P/.craft/.gate/$SESSION_A"
assert_not_contains "with the gate file: allowed" "deny" "$(hook_decision "$P" $SESSION_A)"
assert_contains "another session stays denied" "deny" "$(hook_decision "$P" $SESSION_B)"
rm -rf "$P"; echo ""

begin_test "start-workflow-session writes this session's gate and prints its two lines unchanged"
P=$(fresh_project); make_wf_session "$P" ready
set +e; OUT=$(cd "$P" && as $SESSION_A bash "$START_WF" "$P/.craft/workflows/wf/sessions/s1" 2>&1); RC=$?; set -e
assert_eq "exits 0" "0" "$RC"
assert_eq "its two lines" "Session activated: Lesson One
Starting at Stage 1." "$OUT"
assert_eq "gate names the canonical folder" "workflow $P/.craft/workflows/wf/sessions/s1" "$(gate_of "$P" $SESSION_A)"
assert_not_contains "the hook allows the session's write" "deny" "$(hook_decision "$P" $SESSION_A)"
rm -rf "$P"; echo ""

begin_test "start-workflow-session with no session id exits 1, leaves session.md byte-identical, writes no gate"
P=$(fresh_project); make_wf_session "$P" ready
BEFORE=$(cat "$P/.craft/workflows/wf/sessions/s1/session.md")
set +e; OUT=$(cd "$P" && env -u CRAFT_PROJECT_ROOT -u CLAUDE_CODE_SESSION_ID bash "$START_WF" "$P/.craft/workflows/wf/sessions/s1" 2>&1); RC=$?; set -e
assert_eq "exits 1" "1" "$RC"
assert_contains "names the not-opened line" "write-gate: CLAUDE_CODE_SESSION_ID is empty or not a session id - the gate was not opened" "$OUT"
assert_eq "session.md byte-identical" "$BEFORE" "$(cat "$P/.craft/workflows/wf/sessions/s1/session.md")"
assert_dir_not_exists "no gate folder" "$P/.craft/.gate"
rm -rf "$P"; echo ""

begin_test "a failure after the id check opens no gate and leaves a held gate byte-identical"
P=$(fresh_project); make_wf_session "$P" ready
mkdir -p "$P/.craft/.gate"; printf 'adhoc /rec/fix.md\n' > "$P/.craft/.gate/$SESSION_A"
mkdir "$P/.craft/workflows/wf/sessions/s1/session.md.tmp"
set +e; (cd "$P" && as $SESSION_A bash "$START_WF" "$P/.craft/workflows/wf/sessions/s1" >/dev/null 2>&1); RC=$?; set -e
assert_not_eq "exits non-zero" "0" "$RC"
assert_eq "held gate unchanged" "adhoc /rec/fix.md" "$(gate_of "$P" $SESSION_A)"
rm -rf "$P"
P=$(fresh_project); make_wf_session "$P" ready
mkdir "$P/.craft/workflows/wf/sessions/s1/session.md.tmp"
set +e; (cd "$P" && as $SESSION_A bash "$START_WF" "$P/.craft/workflows/wf/sessions/s1" >/dev/null 2>&1); RC=$?; set -e
assert_not_eq "exits non-zero with no prior gate" "0" "$RC"
assert_dir_not_exists "no gate folder" "$P/.craft/.gate"
rm -rf "$P"; echo ""

begin_test "the sibling-active refusal still exits 1 and opens no gate"
P=$(fresh_project); make_wf_session "$P" ready
mkdir -p "$P/.craft/workflows/wf/sessions/s0"
sed 's/Lesson One/Lesson Zero/;s/status: ready/status: active/' "$P/.craft/workflows/wf/sessions/s1/session.md" > "$P/.craft/workflows/wf/sessions/s0/session.md"
set +e; (cd "$P" && as $SESSION_A bash "$START_WF" "$P/.craft/workflows/wf/sessions/s1" >/dev/null 2>&1); RC=$?; set -e
assert_eq "exits 1" "1" "$RC"
assert_dir_not_exists "no gate folder" "$P/.craft/.gate"
rm -rf "$P"; echo ""

begin_test "a relative session folder gives the same canonical line as the absolute one"
P=$(fresh_project); make_wf_session "$P" ready
set +e; (cd "$P" && as $SESSION_A bash "$START_WF" ".craft/workflows/wf/sessions/s1" >/dev/null 2>&1); RC=$?; set -e
assert_eq "exits 0" "0" "$RC"
assert_eq "canonical line" "workflow $P/.craft/workflows/wf/sessions/s1" "$(gate_of "$P" $SESSION_A)"
rm -rf "$P"; echo ""

begin_test "a story run inside a workflow: the gate hands back to the workflow and writes never block"
P=$(create_craft_with_story "test-cycle" "login-form" "Login Form" "1" "ready")
P=$(cd "$P" && pwd -P)
make_wf_session "$P" ready
cat > "$P/.craft/.global-state" <<'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY=""
PLANNING_CYCLE=""
CURRENT_WORKFLOW_SESSION=""
LAST_ACTIVITY=""
EOF
cat > "$P/.craft/cycles/1-test-cycle/.state" <<'EOF'
CYCLE_NAME="test-cycle"
CYCLE_STATUS="active"
CURRENT_STORY=""
CURRENT_CHUNK="0"
TOTAL_CHUNKS="0"
LAST_VALIDATION=""
LAST_CHECKPOINT=""
EOF
WF="$P/.craft/workflows/wf/sessions/s1"
STORY="$P/.craft/cycles/1-test-cycle/stories/1-login-form.md"
set +e
(cd "$P" && as $SESSION_A bash "$START_WF" "$WF" >/dev/null 2>&1)
assert_eq "after workflow start" "workflow $WF" "$(gate_of "$P" $SESSION_A)"
assert_not_contains "allowed after workflow start" "deny" "$(hook_decision "$P" $SESSION_A)"
(cd "$P" && as $SESSION_A bash "$START_STORY" "$STORY" >/dev/null 2>&1)
assert_eq "after story start" "$STORY
workflow $WF" "$(gate_of "$P" $SESSION_A)"
assert_not_contains "allowed after story start" "deny" "$(hook_decision "$P" $SESSION_A)"
(cd "$P" && as $SESSION_A bash "$COMPLETE_STORY" "$STORY" >/dev/null 2>&1)
set -e
assert_eq "after story end exactly the workflow line" "workflow $WF" "$(gate_of "$P" $SESSION_A)"
assert_not_contains "allowed after story end" "deny" "$(hook_decision "$P" $SESSION_A)"
rm -rf "$P"; echo ""

begin_test "complete-workflow-session removes only this session's gate naming that folder"
P=$(fresh_project); make_wf_session "$P" active
WF="$P/.craft/workflows/wf/sessions/s1"
mkdir -p "$P/.craft/.gate"
printf 'workflow %s\n' "$WF" > "$P/.craft/.gate/$SESSION_A"
printf 'workflow %s\n' "$WF" > "$P/.craft/.gate/$SESSION_B"
set +e; (cd "$P" && as $SESSION_A bash "$COMPLETE_WF" "$WF" >/dev/null 2>&1); RC=$?; set -e
assert_eq "exits 0" "0" "$RC"
assert_eq "A's gate removed" "<none>" "$(gate_of "$P" $SESSION_A)"
assert_eq "B's gate kept" "workflow $WF" "$(gate_of "$P" $SESSION_B)"
rm -rf "$P"

P=$(fresh_project); make_wf_session "$P" active
WF="$P/.craft/workflows/wf/sessions/s1"
mkdir -p "$P/.craft/.gate"
printf '/some/story.md\n' > "$P/.craft/.gate/$SESSION_A"
set +e; (cd "$P" && as $SESSION_A bash "$COMPLETE_WF" "$WF" >/dev/null 2>&1); set -e
assert_eq "a gate naming a story is kept" "/some/story.md" "$(gate_of "$P" $SESSION_A)"
printf '/some/story.md\nworkflow %s\n' "$WF" > "$P/.craft/.gate/$SESSION_A"
set +e; (cd "$P" && as $SESSION_A bash "$COMPLETE_WF" "$WF" >/dev/null 2>&1); set -e
assert_eq "over story / workflow only the story line stays" "/some/story.md" "$(gate_of "$P" $SESSION_A)"
rm -rf "$P"; echo ""

begin_test "claim workflow from B while A holds prints other and writes nothing; after A completes B opens"
P=$(fresh_project); make_wf_session "$P" ready
WF="$P/.craft/workflows/wf/sessions/s1"
(cd "$P" && as $SESSION_A bash "$START_WF" "$WF" >/dev/null 2>&1)
OUT=$(as $SESSION_B bash "$GATE" --root "$P" claim workflow "$WF")
assert_eq "other" "other" "$OUT"
assert_eq "B has no file" "<none>" "$(gate_of "$P" $SESSION_B)"
(cd "$P" && as $SESSION_A bash "$COMPLETE_WF" "$WF" >/dev/null 2>&1)
OUT=$(as $SESSION_B bash "$GATE" --root "$P" claim workflow "$WF")
assert_eq "opened after A's completion" "opened workflow $WF" "$OUT"
rm -rf "$P"; echo ""

begin_test "inject: only the holding session's prompt says writes allowed"
P=$(fresh_project); make_wf_session "$P" active
WF="$P/.craft/workflows/wf/sessions/s1"
printf 'ACTIVE_CYCLE=""\nCURRENT_STORY=""\nPLANNING_CYCLE=""\nCURRENT_WORKFLOW_SESSION="%s"\n' "$WF" > "$P/.craft/.global-state"
mkdir -p "$P/.craft/.gate"; printf 'workflow %s\n' "$WF" > "$P/.craft/.gate/$SESSION_A"
inject() { # <stdin json> [env id]
  set +e
  OUT=$(cd "$P" && printf '%s' "$1" | env -u CRAFT_PROJECT_ROOT CLAUDE_CODE_SESSION_ID="${2-}" bash "$INJECT" 2>/dev/null); RC=$?
  set -e
}
inject "{\"session_id\":\"$SESSION_A\"}" "$SESSION_B"
assert_contains "holder sees writes allowed" "writes allowed (active session)" "$OUT"
inject "{\"session_id\":\"$SESSION_B\"}" "$SESSION_A"
assert_contains "other session still sees the stage line" "stage 1/2" "$OUT"
assert_not_contains "other session has no writes-allowed phrase" "writes allowed" "$OUT"
inject "{\"session_id\":\"../x\"}" "$SESSION_A"
assert_eq "bad id exits 0" "0" "$RC"
assert_not_contains "bad id has no phrase, whatever the environment holds" "writes allowed" "$OUT"
set +e
OUT=$(cd "$P" && env -u CRAFT_PROJECT_ROOT CLAUDE_CODE_SESSION_ID="$SESSION_A" bash "$INJECT" 2>/dev/null </dev/null); RC=$?
set -e
assert_eq "no stdin exits 0" "0" "$RC"
assert_not_contains "no stdin has no phrase" "writes allowed" "$OUT"
assert_contains "no stdin keeps the stage line" "stage 1/2]" "$OUT"
rm -rf "$P"; echo ""

finish_tests
