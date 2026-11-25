#!/bin/bash
# test-write-gate-agreement.sh - The gate script, the write hook and the status
# line must agree about who holds the gate.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/minimal.sh"

GATE="$SCRIPTS_DIR/write-gate.sh"
HOOK="$SCRIPTS_DIR/check-write-permission.py"
STOP="$SCRIPTS_DIR/stop-hook-guard.sh"

# gate_as <session id> <project> <args...>: run the gate script as one session
gate_as() {
  local sid="$1" root="$2"
  shift 2
  (unset CRAFT_PROJECT_ROOT; CLAUDE_CODE_SESSION_ID="$sid" "$GATE" --root "$root" "$@")
}

# hook_says <session id> <project>: allowed | denied, for a write to src/app.ts
hook_says() {
  local json out
  json="{\"session_id\":\"$1\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$2/src/app.ts\"},\"cwd\":\"$2\"}"
  out=$(cd "$2" && unset CRAFT_PROJECT_ROOT && python3 "$HOOK" <<< "$json" 2>/dev/null || true)
  case "$out" in *deny*) echo denied ;; *) echo allowed ;; esac
}

# stop_says <session id> <project>: what the status line prints for that session
stop_says() {
  (cd "$2" && unset CRAFT_PROJECT_ROOT && printf '{"stop_hook_active": false,"session_id":"%s"}' "$1" | bash "$STOP" 2>/dev/null)
}

echo "=== test-write-gate-agreement.sh ==="
echo ""

begin_test "open docs as A: hook and status line agree; close docs: hook denies A"

TEST_DIR=$(create_minimal_craft)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
SESSION_ID=$(echo "$TEST_DIR" | md5sum 2>/dev/null | cut -c1-8)
[ -n "$SESSION_ID" ] || SESSION_ID=$(echo "$TEST_DIR" | md5 2>/dev/null | cut -c1-8)
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"

assert_eq "before opening, A is denied" "denied" "$(hook_says session-a "$TEST_DIR")"
gate_as session-a "$TEST_DIR" open docs >/dev/null
assert_eq "hook allows A" "allowed" "$(hook_says session-a "$TEST_DIR")"
assert_eq "hook denies B" "denied" "$(hook_says session-b "$TEST_DIR")"
assert_contains "status line names Docs for A" "◔ Docs in flight · ⚠ write gate open" "$(stop_says session-a "$TEST_DIR")"
assert_eq "status line is silent for B" "" "$(stop_says session-b "$TEST_DIR")"

gate_as session-a "$TEST_DIR" close docs >/dev/null
assert_eq "after close, hook denies A" "denied" "$(hook_says session-a "$TEST_DIR")"
assert_eq "after close, status line is silent for A" "" "$(stop_says session-a "$TEST_DIR")"

rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"
rm -rf "$TEST_DIR"
echo ""

begin_test "a crashed session's gate file survives a session start and still allows its writes"

TEST_DIR=$(create_minimal_craft)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
ENV_FILE=$(mktemp)
gate_as session-a "$TEST_DIR" open reflect >/dev/null
BEFORE=$(cat "$TEST_DIR/.craft/.gate/session-a")

set +e
(cd "$TEST_DIR" && unset PROJECT_ROOT CRAFT_PROJECT_ROOT CRAFT_MULTI_PROJECT && export CLAUDE_ENV_FILE="$ENV_FILE" && bash "$SCRIPTS_DIR/session-start.sh" >/dev/null 2>&1)
START_EXIT=$?
set -e

assert_eq "session start exits 0" "0" "$START_EXIT"
assert_eq "gate file untouched" "$BEFORE" "$(cat "$TEST_DIR/.craft/.gate/session-a")"
assert_eq "the resumed session's write is allowed" "allowed" "$(hook_says session-a "$TEST_DIR")"
assert_eq "another session still denied" "denied" "$(hook_says session-b "$TEST_DIR")"

rm -f "$ENV_FILE"
rm -rf "$TEST_DIR"
echo ""

begin_test "after the SessionEnd hook runs for A, the write hook denies A and not B"

TEST_DIR=$(create_minimal_craft)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
gate_as session-a "$TEST_DIR" open reflect >/dev/null
gate_as session-b "$TEST_DIR" open docs >/dev/null
(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && printf '{"session_id":"session-a"}' | bash "$SCRIPTS_DIR/session-end.sh")
assert_eq "A denied after session end" "denied" "$(hook_says session-a "$TEST_DIR")"
assert_eq "B still allowed" "allowed" "$(hook_says session-b "$TEST_DIR")"
assert_eq "gate script reports A not open" "not open" "$(gate_as session-a "$TEST_DIR" close reflect)"
rm -rf "$TEST_DIR"
echo ""

finish_tests
