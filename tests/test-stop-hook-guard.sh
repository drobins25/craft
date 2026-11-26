#!/bin/bash
# test-stop-hook-guard.sh — Tests for stop-hook-guard.sh
# Validates Stop hook: marker file logic + active story warning

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"

STOP_HOOK_SCRIPT="$SCRIPTS_DIR/stop-hook-guard.sh"

# Session id for a test dir, matching stop-hook-guard.sh:19's computation for
# the same input (echo keeps the trailing newline the hook's hash includes).
# Linux-tool-first with an empty-check fallback: a piped `md5` before `||` can
# never reach the fallback (a pipeline's exit status is its last command's),
# which silently broke this file on GNU userland.
session_id_for_dir() {
  local id
  id=$(echo "$1" | md5sum 2>/dev/null | cut -c1-8)
  if [ -z "$id" ]; then
    id=$(echo "$1" | md5 2>/dev/null | cut -c1-8)
  fi
  printf '%s' "$id"
}

# --- Tests ---

echo "=== test-stop-hook-guard.sh ==="
echo ""

# Test 1: No active story — exits 0 quietly (creates marker)
begin_test "No active story — exits 0 (creates marker)"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")
trap cleanup_test_dir EXIT

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY=""
EOF

# Clean up any existing marker for this test dir
SESSION_ID=$(session_id_for_dir "$TEST_DIR")
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"

cleanup_test_dir
echo ""

# Test 2: Active story — warns about persisting
begin_test "Active story — warns about persisting"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY="test-story"
EOF

# Zero CURRENT_CHUNK so the guard reaches the Layer 2 persistence path this test asserts
# (the fixture's CURRENT_CHUNK="1" triggers the Layer 1 mid-implementation block instead)
sed -i.bak 's/^CURRENT_CHUNK=.*/CURRENT_CHUNK="0"/' "$TEST_DIR/.craft/cycles/1-test-cycle/.state"
rm -f "$TEST_DIR/.craft/cycles/1-test-cycle/.state.bak"

# Clean marker to ensure this is "first time"
SESSION_ID=$(session_id_for_dir "$TEST_DIR")
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "warns about active story" "test-story" "$RESULT"
assert_contains "mentions continue" "continue" "$RESULT"

cleanup_test_dir
echo ""

# Test 3: stop_hook_active=true — exits 0 immediately (loop prevention)
begin_test "stop_hook_active=true — exits 0 immediately"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY="test-story"
EOF

JSON='{"stop_hook_active": true}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0 immediately" "0" "$EXIT_CODE"
# Should NOT warn when stop_hook_active is true
assert_not_contains "no warning when stop_hook_active" "test-story" "$RESULT"

cleanup_test_dir
echo ""

# Test 4: Recent marker — allows stop without warning
begin_test "Recent marker — allows stop (already warned)"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")

cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY="test-story"
EOF

# Zero CURRENT_CHUNK so the guard reaches the Layer 2 marker-suppression path this test asserts
sed -i.bak 's/^CURRENT_CHUNK=.*/CURRENT_CHUNK="0"/' "$TEST_DIR/.craft/cycles/1-test-cycle/.state"
rm -f "$TEST_DIR/.craft/cycles/1-test-cycle/.state.bak"

# Create a recent marker
SESSION_ID=$(session_id_for_dir "$TEST_DIR")
touch "/tmp/craft-stop-suggested-${SESSION_ID}"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
# Should NOT warn again — marker is recent
assert_eq "no output (already warned)" "" "$RESULT"

# Clean up marker
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"

cleanup_test_dir
echo ""

# Test 5: No .craft/ — exits 0 quietly
begin_test "No .craft/ — exits 0 quietly"

TEST_DIR=$(mktemp -d)

# Clean marker
SESSION_ID=$(session_id_for_dir "$TEST_DIR")
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && unset PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0 with no .craft/" "0" "$EXIT_CODE"

rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"
rm -rf "$TEST_DIR"
echo ""

# The status line reads this session's own gate file, with the session id taken
# from the hook's stdin JSON.
SESS_A="session-a"
SESS_B="session-b"

# stop_json <session id|-> [extra json fields]
stop_json() {
  if [ "$1" = "-" ]; then
    printf '{"stop_hook_active": false%s}' "${2:-}"
  else
    printf '{"stop_hook_active": false,"session_id":"%s"%s}' "$1" "${2:-}"
  fi
}

# run_stop <dir> <json>: as Claude Code runs it, cwd in the project, no CRAFT_PROJECT_ROOT
run_stop() {
  (cd "$1" && unset CRAFT_PROJECT_ROOT && printf '%s' "$2" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
}

# hold_gate <dir> <session id> <line 1> [line 2]
hold_gate() {
  mkdir -p "$1/.craft/.gate"
  if [ -n "${4:-}" ]; then
    printf '%s\n%s\n' "$3" "$4" > "$1/.craft/.gate/$2"
  else
    printf '%s\n' "$3" > "$1/.craft/.gate/$2"
  fi
}

# A craft project with no current story
no_story_project() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/.craft"
  cat > "$d/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
EOF
  printf '%s' "$d"
}

# Test 6: Gate open, no story - adhoc rail stamps, bypassing warn-once marker
begin_test "Session A's adhoc gate, no story - rail stamps every stop; session B is silent"

TEST_DIR=$(no_story_project)
hold_gate "$TEST_DIR" "$SESS_A" "adhoc"

# Recent marker present - the rail must print anyway
SESSION_ID=$(session_id_for_dir "$TEST_DIR")
touch "/tmp/craft-stop-suggested-${SESSION_ID}"

set +e
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A)")
EXIT_CODE=$?
set -e
assert_eq "exits 0" "0" "$EXIT_CODE"
assert_eq "rail line prints despite recent marker" "{\"systemMessage\": \"◔ Adhoc in flight · ⚠ write gate open\"}" "$RESULT"

RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_B)")
assert_eq "session B holds no gate and prints nothing" "" "$RESULT"

rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"
rm -rf "$TEST_DIR"
echo ""

# Test 7: the record's folder gives the flavor word, never its name
begin_test "adhoc with a record path - Tweak or Fix word, never the record's name"

TEST_DIR=$(no_story_project)
hold_gate "$TEST_DIR" "$SESS_A" "adhoc $TEST_DIR/.craft/tweaks/tweak-sample.md"
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A)")
assert_contains "names the tweak flavor" "◔ Tweak in flight · ⚠ write gate open" "$RESULT"
assert_not_contains "never names the record" "tweak-sample" "$RESULT"

hold_gate "$TEST_DIR" "$SESS_A" "adhoc $TEST_DIR/.craft/fixes/fix-sample.md"
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A)")
assert_contains "names the fix flavor" "◔ Fix in flight · ⚠ write gate open" "$RESULT"
assert_not_contains "never names the record" "fix-sample" "$RESULT"

hold_gate "$TEST_DIR" "$SESS_A" "adhoc $TEST_DIR/elsewhere/notes.md"
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A)")
assert_contains "other record folder is plain Adhoc" "◔ Adhoc in flight" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 7b: every named holder shows its own word
begin_test "Each gate holder names itself on the rail"

TEST_DIR=$(no_story_project)
for PAIR in "docs|◔ Docs in flight" "rule-pass|◔ Rule pass in flight" "approve|◔ Approval in flight" "reflect|◔ Reflect in flight" "become|◔ Become in flight" "research|◔ Research in flight" "workflow $TEST_DIR/.craft/workflows/w/sessions/s|◔ Workflow in flight"; do
  HOLDER="${PAIR%%|*}"
  WANT="${PAIR##*|}"
  hold_gate "$TEST_DIR" "$SESS_A" "$HOLDER"
  RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A)")
  assert_eq "$HOLDER" "{\"systemMessage\": \"$WANT · ⚠ write gate open\"}" "$RESULT"
done

mkdir -p "$TEST_DIR/stories"
: > "$TEST_DIR/stories/my-story.md"
hold_gate "$TEST_DIR" "$SESS_A" "$TEST_DIR/stories/my-story.md" "workflow $TEST_DIR/.craft/workflows/w/sessions/s"
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A)")
assert_eq "a two-line story gate names the story only" "{\"systemMessage\": \"◔ my-story in flight · ⚠ write gate open\"}" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 7c: a story file name that is hostile to JSON
begin_test "Story file name with a quote and a backslash still prints valid JSON"

TEST_DIR=$(no_story_project)
BS='\'
NASTY="we\"ird${BS}name"
hold_gate "$TEST_DIR" "$SESS_A" "$TEST_DIR/stories/$NASTY.md"
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A)")
MESSAGE=$(printf '%s' "$RESULT" | python3 -c 'import json,sys; sys.stdout.write(json.loads(sys.stdin.read())["systemMessage"])' 2>/dev/null || echo "INVALID JSON")
assert_eq "parses and names the file" "◔ ${NASTY} in flight · ⚠ write gate open" "$MESSAGE"

rm -rf "$TEST_DIR"
echo ""

# Test 7d: another session's story is current - a non-story holder keeps its own rail
begin_test "Another session's story is current - B's adhoc rail shows, A's story gate keeps the story line"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY="test-story"
EOF
hold_gate "$TEST_DIR" "$SESS_A" "$TEST_DIR/.craft/cycles/1-test-cycle/stories/test-story.md"
hold_gate "$TEST_DIR" "$SESS_B" "adhoc"
SESSION_ID=$(session_id_for_dir "$TEST_DIR")
RAIL_B="{\"systemMessage\": \"◔ Adhoc in flight · ⚠ write gate open\"}"

for CHUNK in 0 2; do
  sed -i.bak "s/^CURRENT_CHUNK=.*/CURRENT_CHUNK=\"$CHUNK\"/" "$TEST_DIR/.craft/cycles/1-test-cycle/.state"
  rm -f "$TEST_DIR/.craft/cycles/1-test-cycle/.state.bak"
  rm -f "/tmp/craft-stop-suggested-${SESSION_ID}" "/tmp/craft-chunk-continue-${SESSION_ID}"
  RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_B)")
  assert_eq "chunk $CHUNK: B's first stop shows the adhoc rail" "$RAIL_B" "$RESULT"
  RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_B)")
  assert_eq "chunk $CHUNK: B's second stop shows it too" "$RAIL_B" "$RESULT"
  rm -f "/tmp/craft-stop-suggested-${SESSION_ID}" "/tmp/craft-chunk-continue-${SESSION_ID}"
  RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A)")
  assert_contains "chunk $CHUNK: A's story gate still shows the story" "test-story" "$RESULT"
  assert_not_contains "chunk $CHUNK: A's line is not the adhoc rail" "Adhoc in flight" "$RESULT"
done

rm -f "/tmp/craft-stop-suggested-${SESSION_ID}" "/tmp/craft-chunk-continue-${SESSION_ID}"
cleanup_test_dir
echo ""

# Test 8: Idle story - only the session holding a gate gets the warning
begin_test "Idle story - A (holding a gate) warns, B does not"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")
cat > "$TEST_DIR/.craft/.global-state" << 'EOF'
ACTIVE_CYCLE="1-test-cycle"
CURRENT_STORY="test-story"
EOF
hold_gate "$TEST_DIR" "$SESS_A" "/some/story.md"
sed -i.bak 's/^CURRENT_CHUNK=.*/CURRENT_CHUNK="0"/' "$TEST_DIR/.craft/cycles/1-test-cycle/.state"
rm -f "$TEST_DIR/.craft/cycles/1-test-cycle/.state.bak"

SESSION_ID=$(session_id_for_dir "$TEST_DIR")
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A)")
assert_contains "A's set-down line names the story" "test-story" "$RESULT"
assert_contains "A's line carries the forgotten-gate warning" "⚠ write gate open" "$RESULT"

rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_B)")
assert_contains "B's set-down line names the story" "test-story" "$RESULT"
assert_not_contains "B's line has no gate warning" "write gate open" "$RESULT"

rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"
cleanup_test_dir
echo ""

# Test 9: No session id and no story - silent
begin_test "Input with no session_id and no story stays silent"

TEST_DIR=$(no_story_project)
hold_gate "$TEST_DIR" "$SESS_A" "adhoc"
SESSION_ID=$(session_id_for_dir "$TEST_DIR")
rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"

set +e
RESULT=$(run_stop "$TEST_DIR" "$(stop_json -)")
EXIT_CODE=$?
set -e
assert_eq "exits 0" "0" "$EXIT_CODE"
assert_eq "no output without a session id" "" "$RESULT"

rm -f "/tmp/craft-stop-suggested-${SESSION_ID}"
rm -rf "$TEST_DIR"
echo ""

# Test 10: A blank or unrecognized gate file - unclaimed, never "in flight"
begin_test "Blank and hand-written gate files - unclaimed"

TEST_DIR=$(no_story_project)
mkdir -p "$TEST_DIR/.craft/.gate"
: > "$TEST_DIR/.craft/.gate/$SESS_A"
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A)")
assert_contains "blank file names the unclaimed gate" "write gate open · unclaimed" "$RESULT"
assert_not_contains "blank file claims no work" "in flight" "$RESULT"

hold_gate "$TEST_DIR" "$SESS_A" "hand-written"
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A)")
assert_contains "hand-written line names the unclaimed gate" "write gate open · unclaimed" "$RESULT"
assert_not_contains "hand-written line claims no work" "in flight" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 10b: the id comes from the JSON field, not from text the input quotes
begin_test "Quoted session_id inside last_assistant_message does not pick the gate"

TEST_DIR=$(no_story_project)
hold_gate "$TEST_DIR" "$SESS_A" "docs"
QUOTE=',"last_assistant_message":"the hook input said \"session_id\": \"session-a\" earlier"'
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_B "$QUOTE")")
assert_eq "B reads B's (missing) gate and prints nothing" "" "$RESULT"
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A "$QUOTE")")
assert_contains "A still reads A's gate" "◔ Docs in flight" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 10c: an old shared value in the state file opens nothing
begin_test "Leftover CRAFT_WRITE_ENABLED with no gate file prints nothing"

TEST_DIR=$(no_story_project)
echo 'CRAFT_WRITE_ENABLED="true"' >> "$TEST_DIR/.craft/.global-state"
RESULT=$(run_stop "$TEST_DIR" "$(stop_json $SESS_A)")
assert_eq "no rail from the old value" "" "$RESULT"

rm -rf "$TEST_DIR"
echo ""

# Test 10d: monorepo - the gate sits under a sub-project the stop hook's own root does not name
begin_test "Monorepo - a gate opened for sub-project A shows on the status line from the top level"

TOP=$(mktemp -d)
TOP=$(cd "$TOP" && pwd -P)
(
  cd "$TOP"
  git init -q
  git config user.name "Test"
  git config user.email "test@example.com"
  mkdir -p .craft/projects A/.craft B/.craft
  printf 'ACTIVE_CYCLE=""\nCURRENT_STORY=""\n' > .craft/.global-state
  printf 'ACTIVE_CYCLE="c1"\nCURRENT_STORY=""\n' > A/.craft/.global-state
  printf 'ACTIVE_CYCLE="c1"\nCURRENT_STORY=""\n' > B/.craft/.global-state
  printf -- '---\nname: a\npath: A\n---\n' > .craft/projects/a.md
  printf -- '---\nname: b\npath: B\n---\n' > .craft/projects/b.md
)
(unset CRAFT_PROJECT_ROOT; CLAUDE_CODE_SESSION_ID=$SESS_A "$SCRIPTS_DIR/write-gate.sh" --root "$TOP/A" open docs >/dev/null)
RESULT=$(run_stop "$TOP" "$(stop_json $SESS_A)")
assert_contains "A sees its holder" "◔ Docs in flight · ⚠ write gate open" "$RESULT"
RESULT=$(run_stop "$TOP" "$(stop_json $SESS_B)")
assert_eq "B sees nothing" "" "$RESULT"

rm -rf "$TOP"
echo ""

# Test 11: a backslash in a hand-off note still gives a valid JSON message,
# and the note's text reads back exactly
begin_test "Hand-off note with a backslash stays valid JSON"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")
BS='\'
printf 'ACTION: Continue workflow session "dir%sx" from stage 2\nSKILL: craft:workflow-run\n' "$BS" > "$TEST_DIR/.craft/.continuation"

JSON='{"stop_hook_active": false}'
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && echo "$JSON" | bash "$STOP_HOOK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
# Exact comparisons: grep would read the backslash as a pattern character
MESSAGE=$(printf '%s' "$RESULT" | python3 -c 'import json,sys; sys.stdout.write(json.loads(sys.stdin.read())["systemMessage"])' 2>/dev/null || echo "INVALID JSON")
assert_eq "note reads back with its backslash" "Continue workflow session dir${BS}x from stage 2" "${MESSAGE##* · }"
case "$MESSAGE" in *"handing off → craft:workflow-run · "*) SKILL_SHOWN=yes ;; *) SKILL_SHOWN=no ;; esac
assert_eq "skill named" "yes" "$SKILL_SHOWN"
LINE_BREAKS=$(printf '%s' "$RESULT" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["systemMessage"].count("\n"))' 2>/dev/null || echo "INVALID JSON")
assert_eq "no stray line break in the message" "0" "$LINE_BREAKS"

rm -rf "$TEST_DIR"
echo ""

# --- Summary ---
finish_tests
