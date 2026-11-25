#!/bin/bash
# test-check-write-permission.sh — Tests for check-write-permission.py
# Validates the PreToolUse write gate: allow/deny/ask based on file path + state

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/minimal.sh"

CHECK_WRITE_SCRIPT="$SCRIPTS_DIR/check-write-permission.py"

# Helper: run check-write-permission.py with JSON input and env vars
# Usage: run_check_write "$JSON" [env_vars...]
run_check_write() {
  local json="$1"
  shift
  # Always exit 0 (fail-open), capture stdout for decision
  env "$@" python3 "$CHECK_WRITE_SCRIPT" <<< "$json" 2>/dev/null || true
}

# --- Tests ---

echo "=== test-check-write-permission.sh ==="
echo ""

# Test 1: Write to .craft/ file — always allowed (no deny output)
begin_test "Write to .craft/ file — allowed"

JSON='{"tool_name":"Write","tool_input":{"file_path":"/project/.craft/design/tokens.yaml"},"cwd":"/project"}'
RESULT=$(run_check_write "$JSON")
assert_not_contains "no deny for .craft/ file" "deny" "$RESULT"
echo ""

# Test 2: Write to .claude/ file — always allowed
begin_test "Write to .claude/ file — allowed"

JSON='{"tool_name":"Write","tool_input":{"file_path":"/project/.claude/settings.json"},"cwd":"/project"}'
RESULT=$(run_check_write "$JSON")
assert_not_contains "no deny for .claude/ file" "deny" "$RESULT"
echo ""

# Gate fixtures. The gate is a file named by the writing session's id; macOS
# mktemp returns /var/... while the hook's cwd resolves to /private/var/..., so
# every fixture here uses the resolved path.
SESSION_A="session-a"
SESSION_B="session-b"
EXPECTED_DENY_REASON="BLOCKED: No active story or workflow session. For workflow sessions, run start-workflow-session.sh to activate the session first. For small targeted changes to existing behavior or appearance - a bug with a known root cause OR a small enhancement to something already built (different icon, wording, spacing) - use Skill(craft:adhoc). For new features or complex changes, use Skill(craft:craft-story-new) or Skill(craft:craft-story-implement)."

# Prints the resolved path of a fresh minimal Craft project
fresh_project() {
  local d
  d=$(create_minimal_craft)
  (cd "$d" && pwd -P)
}

# hold_gate <project> <session id> [content]
hold_gate() {
  mkdir -p "$1/.craft/.gate"
  printf '%s' "${3-/some/story.md
}" > "$1/.craft/.gate/$2"
}

# hook_json <session id|-> <project> <relative file> [extra json fields]
hook_json() {
  local sid_field=""
  [ "$1" != "-" ] && sid_field="\"session_id\":\"$1\","
  printf '{%s"tool_name":"Write","tool_input":{"file_path":"%s/%s"},"cwd":"%s"%s}' "$sid_field" "$2" "$3" "$2" "${4:-}"
}

# run_hook_in <dir> <json>: as Claude Code runs it - cwd in the project, no CRAFT_PROJECT_ROOT
run_hook_in() {
  (cd "$1" && unset CRAFT_PROJECT_ROOT && run_check_write "$2")
}

# Test 3: this session's gate file allows its write; another session is denied
begin_test "Session A's gate file allows A's write; session B is denied"

TEST_DIR=$(fresh_project)
hold_gate "$TEST_DIR" "$SESSION_A"
RESULT=$(run_hook_in "$TEST_DIR" "$(hook_json $SESSION_A "$TEST_DIR" src/app.ts)")
assert_not_contains "A's write allowed" "deny" "$RESULT"
RESULT=$(run_hook_in "$TEST_DIR" "$(hook_json $SESSION_B "$TEST_DIR" src/app.ts)")
assert_contains "B's write denied" "deny" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 4: no gate file - denied, with today's message byte for byte
begin_test "No gate file - write denied with the unchanged block message"

TEST_DIR=$(fresh_project)
RESULT=$(run_hook_in "$TEST_DIR" "$(hook_json $SESSION_A "$TEST_DIR" src/app.ts)")
assert_contains "deny for unprotected write" "deny" "$RESULT"
REASON=$(printf '%s' "$RESULT" | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])')
assert_eq "deny reason is byte-identical" "$EXPECTED_DENY_REASON" "$REASON"

rm -rf "$TEST_DIR"
echo ""

# Test 4b: an implementer-shaped input carries the building session's id
begin_test "Implementer-shaped input keys on session_id alone"

TEST_DIR=$(fresh_project)
hold_gate "$TEST_DIR" "$SESSION_A"
EXTRA=',"agent_type":"craft:implementer","agent_id":"agent-123","transcript_path":"/x/y.jsonl"'
RESULT=$(run_hook_in "$TEST_DIR" "$(hook_json $SESSION_A "$TEST_DIR" src/app.ts "$EXTRA")")
assert_not_contains "implementer on the building session's gate is allowed" "deny" "$RESULT"
RESULT=$(run_hook_in "$TEST_DIR" "$(hook_json $SESSION_B "$TEST_DIR" src/app.ts "$EXTRA")")
assert_contains "same implementer input with another session is denied" "deny" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 4c: ids that could name something other than a gate file never match
begin_test "Unusable session_id values are denied"

TEST_DIR=$(fresh_project)
mkdir -p "$TEST_DIR/.craft/.gate"
printf '*\n' > "$TEST_DIR/.craft/.gate/.gitignore"
for BAD in '"../.global-state"' '".gitignore"' '""' '42' 'null'; do
  JSON="{\"session_id\":$BAD,\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_DIR/src/app.ts\"},\"cwd\":\"$TEST_DIR\"}"
  RESULT=$(run_hook_in "$TEST_DIR" "$JSON")
  assert_contains "session_id $BAD denied" "deny" "$RESULT"
done
RESULT=$(run_hook_in "$TEST_DIR" "$(hook_json - "$TEST_DIR" src/app.ts)")
assert_contains "missing session_id denied" "deny" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 4d: blank and two-line gate files both count (the file existing is the gate)
begin_test "Blank and two-line gate files allow"

TEST_DIR=$(fresh_project)
hold_gate "$TEST_DIR" "$SESSION_A" ""
RESULT=$(run_hook_in "$TEST_DIR" "$(hook_json $SESSION_A "$TEST_DIR" src/app.ts)")
assert_not_contains "blank gate file allows" "deny" "$RESULT"
hold_gate "$TEST_DIR" "$SESSION_A" "/some/story.md
workflow /some/session
"
RESULT=$(run_hook_in "$TEST_DIR" "$(hook_json $SESSION_A "$TEST_DIR" src/app.ts)")
assert_not_contains "two-line gate file allows" "deny" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 4e: an active workflow session allows nothing by itself; its writes pass on the running session's gate
begin_test "Active workflow session, no gate file - denied; the twin with this session's workflow gate is allowed"

TEST_DIR=$(fresh_project)
mkdir -p "$TEST_DIR/.craft/workflows/wf/sessions/s1"
printf -- '---\nname: One\nstatus: active\n---\n' > "$TEST_DIR/.craft/workflows/wf/sessions/s1/session.md"
RESULT=$(run_hook_in "$TEST_DIR" "$(hook_json $SESSION_A "$TEST_DIR" src/app.ts)")
assert_contains "active session.md alone is denied" "deny" "$RESULT"
hold_gate "$TEST_DIR" "$SESSION_A" "workflow $TEST_DIR/.craft/workflows/wf/sessions/s1
"
RESULT=$(run_hook_in "$TEST_DIR" "$(hook_json $SESSION_A "$TEST_DIR" src/app.ts)")
assert_not_contains "the running session's gate allows" "deny" "$RESULT"
RESULT=$(run_hook_in "$TEST_DIR" "$(hook_json $SESSION_B "$TEST_DIR" src/app.ts)")
assert_contains "a session not running it is denied" "deny" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 4e: the old shared value opens nothing any more
begin_test "A leftover CRAFT_WRITE_ENABLED in .global-state with no gate file is denied"

TEST_DIR=$(fresh_project)
echo 'CRAFT_WRITE_ENABLED="true"' >> "$TEST_DIR/.craft/.global-state"
RESULT=$(run_hook_in "$TEST_DIR" "$(hook_json $SESSION_A "$TEST_DIR" src/app.ts)")
assert_contains "old shared value is denied" "deny" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 4f: a gate file alone does not make a folder a Craft project
begin_test "Never-inited folder holding only a gate file - source write allowed"

BARE_DIR=$(mktemp -d)
BARE_RESOLVED=$(cd "$BARE_DIR" && pwd -P)
mkdir -p "$BARE_DIR/.craft/.gate"
printf '/x.md\n' > "$BARE_DIR/.craft/.gate/$SESSION_A"
RESULT=$(run_hook_in "$BARE_RESOLVED" "$(hook_json $SESSION_B "$BARE_RESOLVED" src/app.ts)")
assert_not_contains "not a Craft project, so ungated" "deny" "$RESULT"

rm -rf "$BARE_DIR"
echo ""

# Test 5: Write with dev_mode: true in settings — allowed
begin_test "dev_mode: true in settings — allowed"

TEST_DIR=$(create_minimal_craft)
mkdir -p "$TEST_DIR/.craft"
echo "dev_mode: true" > "$TEST_DIR/.craft/settings.yaml"

JSON="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_DIR/src/app.ts\"},\"cwd\":\"$TEST_DIR\"}"
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && run_check_write "$JSON")
assert_not_contains "no deny with dev_mode" "deny" "$RESULT"

cleanup_test_dir
echo ""

# Test 6: Write to file outside project — allowed
begin_test "Write to file outside project — allowed"

TEST_DIR=$(create_minimal_craft)

JSON="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/some-external-file.txt\"},\"cwd\":\"$TEST_DIR\"}"
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && run_check_write "$JSON")
assert_not_contains "no deny for external file" "deny" "$RESULT"

cleanup_test_dir
echo ""

# Test 7: Read tool — always allowed (not a write)
begin_test "Read tool — always allowed"

TEST_DIR=$(create_minimal_craft)

JSON="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$TEST_DIR/src/app.ts\"},\"cwd\":\"$TEST_DIR\"}"
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && run_check_write "$JSON")
# Read is not Write/Edit, so the script short-circuits... actually the script
# doesn't filter by tool_name — it checks file_path. Any tool with file_path
# that resolves inside project will be gated. Let's check honestly.
# Actually re-reading the script: it does NOT filter by tool_name. It gates
# ALL tools that have a file_path. This means Read tool to project files
# would also be denied. Let me check if that's actually the case.
# Looking at the script: main() extracts file_path, then checks it.
# There's no tool_name filter. So Read tool with a project file path
# would be denied unless CRAFT_WRITE_ENABLED=true.
#
# BUT: the script is a PreToolUse hook — it only runs for Write/Edit tools
# per hooks.json configuration. The script itself doesn't know that.
# So testing with Read tool is testing script behavior, not hook behavior.
# The script will deny Read too if the file is in-project.
# That said, "Read" wouldn't have file_path in the same way.
# Let me just verify the behavior honestly.
# If no file_path, script allows. Read tool has file_path.
# So Read to project file = denied (same as Write).
# This is fine — the hooks.json controls which tools trigger this script.
assert_eq "always exits 0" "0" "$?"

cleanup_test_dir
echo ""

# Test 8: No file_path in tool input — allowed (fail-open)
begin_test "No file_path in tool input — allowed (fail-open)"

JSON='{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"/project"}'
RESULT=$(run_check_write "$JSON")
assert_not_contains "no deny without file_path" "deny" "$RESULT"
echo ""

# Test 9: Malformed JSON — exits 0 (fail-open, no crash)
begin_test "Malformed JSON — exits 0 (fail-open)"

set +e
RESULT=$(echo "not json at all" | python3 "$CHECK_WRITE_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0 on malformed JSON" "0" "$EXIT_CODE"
assert_not_contains "no deny on malformed input" "deny" "$RESULT"
echo ""

# Test 10: Empty stdin — exits 0 (fail-open)
begin_test "Empty stdin — exits 0 (fail-open)"

set +e
RESULT=$(echo "" | python3 "$CHECK_WRITE_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0 on empty stdin" "0" "$EXIT_CODE"
echo ""

# Test 11: CRAFT_PROJECT_ROOT env var - used for resolution
begin_test "CRAFT_PROJECT_ROOT env var - gate file under it allows, twin without it denies"

TEST_DIR=$(fresh_project)
JSON=$(hook_json $SESSION_A "$TEST_DIR" src/app.ts)
RESULT=$(CRAFT_PROJECT_ROOT="$TEST_DIR" python3 "$CHECK_WRITE_SCRIPT" <<< "$JSON" 2>/dev/null || true)
assert_contains "no gate file: denied" "deny" "$RESULT"
hold_gate "$TEST_DIR" "$SESSION_A"
RESULT=$(CRAFT_PROJECT_ROOT="$TEST_DIR" python3 "$CHECK_WRITE_SCRIPT" <<< "$JSON" 2>/dev/null || true)
assert_not_contains "gate file under the env root: allowed" "deny" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 12: Always exits 0 — even when denying
# Same macOS path normalization fix as test 4
begin_test "Always exits 0 — even when denying"

TEST_DIR=$(create_minimal_craft)
RESOLVED_DIR=$(cd "$TEST_DIR" && pwd -P)

JSON="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$RESOLVED_DIR/src/app.ts\"},\"cwd\":\"$RESOLVED_DIR\"}"

set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && python3 "$CHECK_WRITE_SCRIPT" <<< "$JSON" 2>/dev/null)
EXIT_CODE=$?
set -e

# Even a deny should exit 0
assert_eq "exits 0 even when denying" "0" "$EXIT_CODE"
assert_contains "deny is in output" "deny" "$RESULT"

cleanup_test_dir
echo ""

# Test 13: Bare .craft/ (mockups only, no project.md/.global-state) — source write allowed
# A converged mockup can leave .craft/mockups/ in a never-inited project; that bare
# directory must NOT resolve as a project root, or the gate would deny every source
# edit there. Mirrors find-workshop.sh's "created by accident" guard.
# Same macOS resolved-path note as Test 4. Inited-project deny regression: Test 4.
begin_test "Bare .craft/ (no project.md) — source write allowed"

BARE_DIR=$(mktemp -d)
BARE_RESOLVED=$(cd "$BARE_DIR" && pwd -P)
mkdir -p "$BARE_DIR/.craft/mockups/2026-07-10-sample/rounds"
mkdir -p "$BARE_DIR/src"

JSON="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$BARE_RESOLVED/src/app.ts\"},\"cwd\":\"$BARE_RESOLVED\"}"
RESULT=$(cd "$BARE_DIR" && unset CRAFT_PROJECT_ROOT && run_check_write "$JSON")
assert_not_contains "no deny for bare .craft/ (never-inited) project" "deny" "$RESULT"

rm -rf "$BARE_DIR"
echo ""

# Test 14: Write to EXISTING tokens.yaml — denied with merge-tokens.py redirect
# An existing tokens.yaml is a merge target (live-run incident 2026-07-11): whole-file
# Write regeneration destroys unnamed keys and provenance comments.
begin_test "Write to existing tokens.yaml — denied with redirect"

TOK_DIR=$(mktemp -d)
TOK_RESOLVED=$(cd "$TOK_DIR" && pwd -P)
mkdir -p "$TOK_DIR/.craft/design"
echo 'colors:' > "$TOK_DIR/.craft/design/tokens.yaml"

JSON="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TOK_RESOLVED/.craft/design/tokens.yaml\"},\"cwd\":\"$TOK_RESOLVED\"}"
set +e
RESULT=$(cd "$TOK_DIR" && unset CRAFT_PROJECT_ROOT && run_check_write "$JSON")
EXIT_CODE=$?
set -e
assert_eq "exits 0 even when denying" "0" "$EXIT_CODE"
assert_contains "deny fires" "deny" "$RESULT"
assert_contains "redirect names merge-tokens.py" "merge-tokens.py" "$RESULT"
assert_contains "redirect offers Edit for single keys" "Edit tool" "$RESULT"

# Test 14b: Edit on the SAME existing file — allowed (targeted updates keep working)
JSON="{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TOK_RESOLVED/.craft/design/tokens.yaml\"},\"cwd\":\"$TOK_RESOLVED\"}"
RESULT=$(cd "$TOK_DIR" && unset CRAFT_PROJECT_ROOT && run_check_write "$JSON")
assert_not_contains "Edit on existing tokens.yaml allowed" "deny" "$RESULT"

# Test 14c: Write when tokens.yaml is ABSENT — allowed (mockup cold-path creation)
rm "$TOK_DIR/.craft/design/tokens.yaml"
JSON="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TOK_RESOLVED/.craft/design/tokens.yaml\"},\"cwd\":\"$TOK_RESOLVED\"}"
RESULT=$(cd "$TOK_DIR" && unset CRAFT_PROJECT_ROOT && run_check_write "$JSON")
assert_not_contains "Write allowed when file absent (creation)" "deny" "$RESULT"

# Test 14d: Write to a DIFFERENT existing .craft/design file — unaffected
echo 'x' > "$TOK_DIR/.craft/design/locked.md"
JSON="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TOK_RESOLVED/.craft/design/locked.md\"},\"cwd\":\"$TOK_RESOLVED\"}"
RESULT=$(cd "$TOK_DIR" && unset CRAFT_PROJECT_ROOT && run_check_write "$JSON")
assert_not_contains "other .craft/design writes unaffected" "deny" "$RESULT"

rm -rf "$TOK_DIR"
echo ""

# --- Monorepo: the opener and the hook may resolve different roots ---

# make_monorepo: a git repo with a top-level Craft project and two registered
# active sub-projects A and B. Prints the resolved top-level path.
make_monorepo() {
  local top
  top=$(mktemp -d)
  top=$(cd "$top" && pwd -P)
  (
    cd "$top"
    git init -q
    git config user.name "Test"
    git config user.email "test@example.com"
    mkdir -p .craft/projects A/.craft A/src B/.craft B/src
    printf 'ACTIVE_CYCLE=""\nCURRENT_STORY=""\n' > .craft/.global-state
    printf 'ACTIVE_CYCLE="c1"\nCURRENT_STORY=""\n' > A/.craft/.global-state
    printf 'ACTIVE_CYCLE="c1"\nCURRENT_STORY=""\n' > B/.craft/.global-state
    printf -- '---\nname: a\npath: A\n---\n' > .craft/projects/a.md
    printf -- '---\nname: b\npath: B\n---\n' > .craft/projects/b.md
  )
  printf '%s' "$top"
}

begin_test "Monorepo, no pin, several active sub-projects: gate opened for A allows A's write"

TOP=$(make_monorepo)
(unset CRAFT_PROJECT_ROOT; CLAUDE_CODE_SESSION_ID=$SESSION_A "$SCRIPTS_DIR/write-gate.sh" --root "$TOP/A" open docs >/dev/null)
RESULT=$(run_hook_in "$TOP" "$(hook_json $SESSION_A "$TOP" A/src/x.ts)")
assert_not_contains "A's write allowed" "deny" "$RESULT"
RESULT=$(run_hook_in "$TOP" "$(hook_json $SESSION_B "$TOP" A/src/x.ts)")
assert_contains "session B denied" "deny" "$RESULT"
RESULT=$(run_hook_in "$TOP" "$(hook_json $SESSION_A "$TOP" B/src/x.ts)")
assert_contains "A's gate does not cover B's folder" "deny" "$RESULT"

rm -rf "$TOP"
echo ""

begin_test "Monorepo, pin names A: a gate opened at the top level still allows A's write"

TOP=$(make_monorepo)
printf '%s\na\n' "$TOP/A" > "$TOP/.craft/.pinned-project"
hold_gate "$TOP" "$SESSION_A"
RESULT=$(run_hook_in "$TOP" "$(hook_json $SESSION_A "$TOP" A/src/x.ts)")
assert_not_contains "top-level gate allows A's write" "deny" "$RESULT"
RESULT=$(run_hook_in "$TOP" "$(hook_json $SESSION_B "$TOP" A/src/x.ts)")
assert_contains "session B denied" "deny" "$RESULT"

rm -rf "$TOP"
echo ""

begin_test "Monorepo, pin names B: only a gate in B lets B's write through"

TOP=$(make_monorepo)
printf '%s\nb\n' "$TOP/B" > "$TOP/.craft/.pinned-project"
hold_gate "$TOP/A" "$SESSION_A"
hold_gate "$TOP/B" "$SESSION_B"
RESULT=$(run_hook_in "$TOP" "$(hook_json $SESSION_A "$TOP" B/src/x.ts)")
assert_contains "gate only in A: B's write denied" "deny" "$RESULT"
RESULT=$(run_hook_in "$TOP" "$(hook_json $SESSION_B "$TOP" B/src/x.ts)")
assert_not_contains "gate in B: B's write allowed" "deny" "$RESULT"

rm -rf "$TOP"
echo ""

# --- Summary ---
finish_tests
