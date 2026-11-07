#!/bin/bash
# test-create-cycle.sh — Tests for create-cycle.sh
# Validates cycle creation: directory structure, numbering, yaml content, state file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/minimal.sh"

CREATE_CYCLE_SCRIPT="$SCRIPTS_DIR/create-cycle.sh"

# --- Tests ---

echo "=== test-create-cycle.sh ==="
echo ""

# Test 1: Creates directory structure with cycle.yaml + .state + stories/
begin_test "Creates directory with cycle.yaml, .state, stories/"

TEST_DIR=$(create_minimal_craft)
trap cleanup_test_dir EXIT

set +e
RESULT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "auth" "Authentication" "Login flow" "$TEST_DIR" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"

# Should create 1-auth/ directory
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-auth"
assert_dir_exists "cycle directory created" "$CYCLE_DIR"
assert_file_exists "cycle.yaml exists" "$CYCLE_DIR/cycle.yaml"
assert_file_exists ".state exists" "$CYCLE_DIR/.state"
assert_dir_exists "stories/ directory exists" "$CYCLE_DIR/stories"

# Output should be the cycle dir path
assert_contains "output is cycle dir" "1-auth" "$RESULT"

cleanup_test_dir
echo ""

# Test 2: Auto-numbering — second cycle gets prefix 2-
begin_test "Auto-numbering — second cycle gets prefix 2-"

TEST_DIR=$(create_minimal_craft)

# Create first cycle
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "auth" "Auth" "Login" "$TEST_DIR" >/dev/null 2>&1

# Create second cycle
set +e
RESULT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "dashboard" "Dashboard" "UI" "$TEST_DIR" 2>/dev/null)
set -e

assert_dir_exists "cycle 1-auth exists" "$TEST_DIR/.craft/cycles/1-auth"
assert_dir_exists "cycle 2-dashboard exists" "$TEST_DIR/.craft/cycles/2-dashboard"

cleanup_test_dir
echo ""

# Test 3: cycle.yaml content — title, status, created
begin_test "cycle.yaml has correct content"

TEST_DIR=$(create_minimal_craft)

CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "auth" "Authentication Flow" "Login and signup" "$TEST_DIR" >/dev/null 2>&1

CYCLE_YAML="$TEST_DIR/.craft/cycles/1-auth/cycle.yaml"
assert_file_exists "cycle.yaml exists" "$CYCLE_YAML"

# Check key fields
assert_file_contains "has title" "title:" "$CYCLE_YAML"
assert_file_contains "has status: planning" "status: planning" "$CYCLE_YAML"
assert_file_contains "has created date" "created:" "$CYCLE_YAML"

cleanup_test_dir
echo ""

# Test 4: .state file content — CYCLE_NAME, CYCLE_STATUS
begin_test ".state has correct initial values"

TEST_DIR=$(create_minimal_craft)

CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "auth" "Auth" "Login" "$TEST_DIR" >/dev/null 2>&1

STATE_FILE="$TEST_DIR/.craft/cycles/1-auth/.state"
assert_file_exists ".state exists" "$STATE_FILE"

source "$STATE_FILE"
assert_eq "CYCLE_NAME is auth" "auth" "$CYCLE_NAME"
assert_eq "CYCLE_STATUS is planning" "planning" "$CYCLE_STATUS"
assert_eq "CURRENT_STORY is empty" "" "$CURRENT_STORY"
assert_eq "CURRENT_CHUNK is 0" "0" "$CURRENT_CHUNK"

cleanup_test_dir
echo ""

# Test 5: No .craft/ directory — exits 1
begin_test "No .craft/ — exits 1"

TEST_DIR=$(mktemp -d)

set +e
RESULT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "auth" "Auth" "Login" "$TEST_DIR" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 1 without .craft/" "1" "$EXIT_CODE"

rm -rf "$TEST_DIR"
echo ""

# Test 6: No cycle name — exits 1
begin_test "No cycle name — exits 1"

TEST_DIR=$(create_minimal_craft)

set +e
RESULT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 1 with no name" "1" "$EXIT_CODE"

cleanup_test_dir
echo ""

# Test 7: Creates learnings file if missing
begin_test "Creates .learnings.yaml if missing"

TEST_DIR=$(create_minimal_craft)

CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "auth" "Auth" "Login" "$TEST_DIR" >/dev/null 2>&1

assert_file_exists ".learnings.yaml created" "$TEST_DIR/.craft/.learnings.yaml"

cleanup_test_dir
echo ""

# Test 8: Title includes cycle number prefix
begin_test "Title includes cycle number prefix (Cycle NN: Title)"

TEST_DIR=$(create_minimal_craft)

CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "auth" "Authentication Flow" "Login" "$TEST_DIR" >/dev/null 2>&1

CYCLE_YAML="$TEST_DIR/.craft/cycles/1-auth/cycle.yaml"
TITLE_LINE=$(grep "^title:" "$CYCLE_YAML")

if echo "$TITLE_LINE" | grep -q "Cycle 01:"; then
  echo "  PASS: title has cycle number prefix"
  PASS=$((PASS + 1))
else
  echo "  FAIL: title missing cycle number prefix"
  echo "    expected: Cycle 01: Authentication Flow"
  echo "    actual:   $TITLE_LINE"
  FAIL=$((FAIL + 1))
fi

cleanup_test_dir
echo ""

# Test 9: Title is quoted in YAML (colon-safe)
begin_test "Title is quoted in YAML (colon in 'Cycle NN:' requires quotes)"

TEST_DIR=$(create_minimal_craft)

CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "auth" "Auth" "Login" "$TEST_DIR" >/dev/null 2>&1

CYCLE_YAML="$TEST_DIR/.craft/cycles/1-auth/cycle.yaml"
TITLE_LINE=$(grep "^title:" "$CYCLE_YAML")

if echo "$TITLE_LINE" | grep -qE "^title: '.*'\$"; then
  echo "  PASS: title is quoted"
  PASS=$((PASS + 1))
else
  echo "  FAIL: title is NOT single-quoted - colon will break YAML parsing"
  echo "    actual: $TITLE_LINE"
  FAIL=$((FAIL + 1))
fi

cleanup_test_dir
echo ""

# Test 10: Goals array has no null/empty entries
begin_test "Goals array has no null/empty entries"

TEST_DIR=$(create_minimal_craft)

CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "auth" "Auth" "Login" "$TEST_DIR" >/dev/null 2>&1

CYCLE_YAML="$TEST_DIR/.craft/cycles/1-auth/cycle.yaml"

# Check for bare "- " lines (empty list entries that parse as null)
EMPTY_ENTRIES=$(grep -n "^  - $" "$CYCLE_YAML" 2>/dev/null || true)
if [ -z "$EMPTY_ENTRIES" ]; then
  echo "  PASS: no empty list entries"
  PASS=$((PASS + 1))
else
  echo "  FAIL: found empty list entries (parse as null, break Zod validation)"
  echo "    lines: $EMPTY_ENTRIES"
  FAIL=$((FAIL + 1))
fi

cleanup_test_dir
echo ""

# Test 11: Auto-numbering carries into title
begin_test "Second cycle title has Cycle 02 prefix"

TEST_DIR=$(create_minimal_craft)

CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "auth" "Auth" "Login" "$TEST_DIR" >/dev/null 2>&1
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "dashboard" "Dashboard" "UI" "$TEST_DIR" >/dev/null 2>&1

CYCLE_YAML="$TEST_DIR/.craft/cycles/2-dashboard/cycle.yaml"
TITLE_LINE=$(grep "^title:" "$CYCLE_YAML")

if echo "$TITLE_LINE" | grep -q "Cycle 02:"; then
  echo "  PASS: second cycle title has Cycle 02 prefix"
  PASS=$((PASS + 1))
else
  echo "  FAIL: second cycle title has wrong prefix"
  echo "    expected: Cycle 02: Dashboard"
  echo "    actual:   $TITLE_LINE"
  FAIL=$((FAIL + 1))
fi

cleanup_test_dir
echo ""

# --- Tracker source (args 6-9) ---

TRACKER_TS="2026-10-31T23:40:12.000Z"
FIXTURE="$SCRIPT_DIR/fixtures/cycle-yaml-freeform.expected"

# run_create <args...> sets TC_EXIT, TC_OUT against a fresh TEST_DIR
run_create() {
  set +e
  TC_OUT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" "$@" 2>&1)
  TC_EXIT=$?
  set -e
}

begin_test "No tracker args = byte-identical cycle.yaml"
TEST_DIR=$(create_minimal_craft)
sed "s/{{DATE}}/$(date +%Y-%m-%d)/g" "$FIXTURE" > "$TEST_DIR/expected.yaml"
run_create auth "Authentication" "Login flow" "$TEST_DIR" >/dev/null
cmp -s "$TEST_DIR/expected.yaml" "$TEST_DIR/.craft/cycles/1-auth/cycle.yaml" && R=same || R=differs
assert_eq "5 args matches fixture" "same" "$R"
rm -rf "$TEST_DIR/.craft/cycles/1-auth"
run_create auth "Authentication" "Login flow" "$TEST_DIR" "" "" "" "" "" >/dev/null
cmp -s "$TEST_DIR/expected.yaml" "$TEST_DIR/.craft/cycles/1-auth/cycle.yaml" && R=same || R=differs
assert_eq "9 args with empty 6th matches fixture" "same" "$R"
cleanup_test_dir
echo ""

begin_test "Tracker args write four quoted lines after source_concept"
TEST_DIR=$(create_minimal_craft)
run_create auth "Authentication" "Login flow" "$TEST_DIR" "" "DRO-21" "build and open the PR" "Darin O'Neil" "$TRACKER_TS" >/dev/null
Y="$TEST_DIR/.craft/cycles/1-auth/cycle.yaml"
assert_eq "exits 0" "0" "$TC_EXIT"
EXPECTED_BLOCK="source_concept: []
source_issue: 'DRO-21'
authorized_stage: 'build and open the PR'
go_author: 'Darin O''Neil'
go_date: '$TRACKER_TS'
"
ACTUAL_BLOCK=$(grep -A4 '^source_concept:' "$Y"; echo x)
assert_eq "lines in order right after source_concept" "${EXPECTED_BLOCK}x" "$ACTUAL_BLOCK"
assert_eq "goals still present" "1" "$(grep -c '^goals:' "$Y")"
cleanup_test_dir
echo ""

begin_test "Plan stage may carry empty author and date"
TEST_DIR=$(create_minimal_craft)
run_create auth "Authentication" "Login flow" "$TEST_DIR" "" "DRO-21" "plan" "" "" >/dev/null
Y="$TEST_DIR/.craft/cycles/1-auth/cycle.yaml"
assert_eq "exits 0" "0" "$TC_EXIT"
assert_file_contains "empty author is ''" "go_author: ''" "$Y"
assert_file_contains "empty date is ''" "go_date: ''" "$Y"
cleanup_test_dir
echo ""

begin_test "Issue alone records source_issue only"
TEST_DIR=$(create_minimal_craft)
run_create auth "Authentication" "Login flow" "$TEST_DIR" "" "DRO-21" "" "" "" >/dev/null
Y="$TEST_DIR/.craft/cycles/1-auth/cycle.yaml"
assert_eq "exits 0" "0" "$TC_EXIT"
EXPECTED_BLOCK="source_concept: []
source_issue: 'DRO-21'

"
ACTUAL_BLOCK=$(grep -A2 '^source_concept:' "$Y"; echo x)
assert_eq "only source_issue follows source_concept" "${EXPECTED_BLOCK}x" "$ACTUAL_BLOCK"
assert_eq "no stage key" "0" "$(grep -c '^authorized_stage:' "$Y")"
assert_eq "no author key" "0" "$(grep -c '^go_author:' "$Y")"
assert_eq "no date key" "0" "$(grep -c '^go_date:' "$Y")"
cleanup_test_dir
echo ""

begin_test "Lifecycle seds leave the tracker keys alone"
TEST_DIR=$(create_minimal_craft)
run_create auth "Authentication" "Login flow" "$TEST_DIR" "" "DRO-21" "build" "Darin" "$TRACKER_TS" >/dev/null
Y="$TEST_DIR/.craft/cycles/1-auth/cycle.yaml"
BEFORE=$(grep -E '^(source_issue|authorized_stage|go_author|go_date):' "$Y")
sed -i.bak "s/^status:.*/status: active/" "$Y" && rm -f "$Y.bak"
sed -i.bak "s/^updated:.*/updated: 2030-01-01/" "$Y" && rm -f "$Y.bak"
AFTER=$(grep -E '^(source_issue|authorized_stage|go_author|go_date):' "$Y")
assert_eq "four lines unchanged" "$BEFORE" "$AFTER"
cleanup_test_dir
echo ""

reject_tracker() {
  local label="$1" issue="$2" stage="$3" author="$4" date="$5"
  begin_test "$label"
  TEST_DIR=$(create_minimal_craft)
  run_create auth "Authentication" "Login flow" "$TEST_DIR" "" "$issue" "$stage" "$author" "$date" >/dev/null
  assert_eq "exits 1" "1" "$TC_EXIT"
  assert_contains "prints an Error line" "Error:" "$TC_OUT"
  assert_eq "no cycle dir created" "0" "$(ls -d "$TEST_DIR"/.craft/cycles/*/ 2>/dev/null | wc -l | tr -d ' ')"
  cleanup_test_dir
  echo ""
}

reject_tracker "Hold rejected, no dir" "DRO-21" "hold" "Darin" "$TRACKER_TS"
reject_tracker "Build without a Go record rejected" "DRO-21" "build" "" ""
reject_tracker "Build without go_date rejected" "DRO-21" "build and open the PR" "Darin" ""
reject_tracker "Unknown stage rejected" "DRO-21" "ship" "Darin" "$TRACKER_TS"
reject_tracker "Stage without issue rejected" "" "plan" "" ""
reject_tracker "Author without issue rejected" "" "" "Darin" ""
reject_tracker "Author without stage rejected, even with an issue" "DRO-21" "" "Darin" ""
reject_tracker "Date without stage rejected, even with an issue" "DRO-21" "" "" "$TRACKER_TS"
reject_tracker "Newline in issue rejected" "DRO-21
x" "plan" "" ""
reject_tracker "Newline in author rejected" "DRO-21" "plan" "Da
rin" ""

# --- Awkward text and the --values path ---

READ_KEY_SH="$SCRIPTS_DIR/read-key.sh"
DASH_ROOT="$SCRIPT_DIR/../scripts/dashboard"
TAB=$(printf '\t')
BT='`'

strict_get() { # strict_get <file> <key>
  python3 -c '
import sys, yaml
sys.stdout.write(str(yaml.safe_load(open(sys.argv[1], encoding="utf-8"))[sys.argv[2]]))
' "$1" "$2"
}
py_read_key() {
  python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import tracker_comments
sys.stdout.write(tracker_comments.read_key(open(sys.argv[2], encoding="utf-8").read(), sys.argv[3]))
' "$SCRIPTS_DIR" "$1" "$2"
}
sh_read_key() {
  /bin/bash -c 'source "$1"; read_key "$2" "$3"' _ "$READ_KEY_SH" "$1" "$2"
}
dash_get() {
  python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from src import frontmatter
fields = frontmatter.parse_mapping(open(sys.argv[2], encoding="utf-8").read().split("\n"))
sys.stdout.write(fields[sys.argv[3]])
' "$DASH_ROOT" "$1" "$2"
}
# assert_all_readers <label> <yaml> <key> <expected>
assert_all_readers() {
  assert_eq "$1 shell $3" "$4" "$(sh_read_key "$2" "$3")"
  assert_eq "$1 python $3" "$4" "$(py_read_key "$2" "$3")"
  assert_eq "$1 strict $3" "$4" "$(strict_get "$2" "$3")"
  assert_eq "$1 dashboard $3" "$4" "$(dash_get "$2" "$3")"
}

AWKWARD=(
  '"' "'" '\' '#' 'x # y' 'a: b' '[x]' 'null' '42' '2026-11-06'
  '$(touch pwned)' "$BT" '~' "a${TAB}b" "''" '|&/' 'a|b&c\d/e' '%s' '- lead'
)

begin_test "awkward positional title and target survive the template"
TEST_DIR=$(create_minimal_craft)
n=0
for v in "${AWKWARD[@]}"; do
  n=$((n + 1))
  run_create "c$n" "$v" "$v" "$TEST_DIR" >/dev/null
  assert_eq "[$v] exits 0" "0" "$TC_EXIT"
  Y=$(ls -d "$TEST_DIR"/.craft/cycles/${n}-c*/ | head -1)cycle.yaml
  assert_all_readers "[$v]" "$Y" title "Cycle $(printf '%02d' $n): $v"
  assert_all_readers "[$v]" "$Y" target "$v"
  assert_eq "[$v] focus stays TBD" "TBD" "$(sh_read_key "$Y" focus)"
done
run_create nl "line one
line two" "t1
t2" "$TEST_DIR" >/dev/null
Y=$(ls -d "$TEST_DIR"/.craft/cycles/*-nl/ | head -1)cycle.yaml
assert_all_readers "[newline]" "$Y" title "Cycle $(printf '%02d' $((n + 1))): line one line two"
assert_all_readers "[newline]" "$Y" target "t1 t2"
assert_eq "no ticket text was run as a command" "no" "$([ -e pwned ] && echo yes || echo no)"
cleanup_test_dir
echo ""

begin_test "awkward title and target survive the no-template fallback"
TEST_DIR=$(create_minimal_craft)
EMPTY_PLUGIN=$(mktemp -d)
n=0
for v in "${AWKWARD[@]}"; do
  n=$((n + 1))
  set +e
  CLAUDE_PLUGIN_ROOT="$EMPTY_PLUGIN" bash "$CREATE_CYCLE_SCRIPT" "f$n" "$v" "$v" "$TEST_DIR" >/dev/null 2>&1
  TC_EXIT=$?
  set -e
  assert_eq "[$v] exits 0" "0" "$TC_EXIT"
  Y=$(ls -d "$TEST_DIR"/.craft/cycles/${n}-f*/ | head -1)cycle.yaml
  assert_all_readers "[$v]" "$Y" title "Cycle $(printf '%02d' $n): $v"
  assert_all_readers "[$v]" "$Y" target "$v"
done
rm -rf "$EMPTY_PLUGIN"
cleanup_test_dir
echo ""

begin_test "--values sets title and target with the label"
TEST_DIR=$(create_minimal_craft)
n=0
for v in "${AWKWARD[@]}"; do
  n=$((n + 1))
  printf 'title: %s\ntarget: %s\n' "$v" "$v" > "$TEST_DIR/values.txt"
  run_create --values "$TEST_DIR/values.txt" "v$n" "" "" "$TEST_DIR" >/dev/null
  assert_eq "[$v] exits 0" "0" "$TC_EXIT"
  Y=$(ls -d "$TEST_DIR"/.craft/cycles/${n}-v*/ | head -1)cycle.yaml
  want="$v"
  assert_all_readers "[$v]" "$Y" title "Cycle $(printf '%02d' $n): $want"
  assert_all_readers "[$v]" "$Y" target "$want"
done
cleanup_test_dir
echo ""

begin_test "--values with tracker args keeps the tracker lines and a title-only file keeps the default target"
TEST_DIR=$(create_minimal_craft)
printf 'title: Login fails: "Remember me" ignored\n' > "$TEST_DIR/values.txt"
run_create --values "$TEST_DIR/values.txt" auth "" "" "$TEST_DIR" "" "DRO-21" "plan" "" "" >/dev/null
assert_eq "exits 0" "0" "$TC_EXIT"
Y="$TEST_DIR/.craft/cycles/1-auth/cycle.yaml"
assert_all_readers "" "$Y" title 'Cycle 01: Login fails: "Remember me" ignored'
assert_all_readers "" "$Y" target "TBD"
assert_eq "source_issue present" "DRO-21" "$(sh_read_key "$Y" source_issue)"
cleanup_test_dir
echo ""

begin_test "--values with a non-empty positional title or target refuses, nothing created"
TEST_DIR=$(create_minimal_craft)
printf 'title: T\n' > "$TEST_DIR/values.txt"
run_create --values "$TEST_DIR/values.txt" auth "Title" "" "$TEST_DIR" >/dev/null
assert_eq "title: exits 1" "1" "$TC_EXIT"
assert_contains "title: Error line" "Error:" "$TC_OUT"
run_create --values "$TEST_DIR/values.txt" auth "" "Target" "$TEST_DIR" >/dev/null
assert_eq "target: exits 1" "1" "$TC_EXIT"
assert_eq "no cycle dir created" "0" "$(ls -d "$TEST_DIR"/.craft/cycles/*/ 2>/dev/null | wc -l | tr -d ' ')"
cleanup_test_dir
echo ""

begin_test "a bad values file leaves no directory"
TEST_DIR=$(create_minimal_craft)
printf 'target: only a target\n' > "$TEST_DIR/no-title.txt"
printf 'title T without separator\n' > "$TEST_DIR/bad.txt"
run_create --values "$TEST_DIR/no-title.txt" auth "" "" "$TEST_DIR" >/dev/null
assert_eq "no title: exits 1" "1" "$TC_EXIT"
assert_contains "no title: says why" "no title" "$TC_OUT"
run_create --values "$TEST_DIR/bad.txt" auth "" "" "$TEST_DIR" >/dev/null
assert_eq "malformed: exits 1" "1" "$TC_EXIT"
run_create --values "$TEST_DIR/missing.txt" auth "" "" "$TEST_DIR" >/dev/null
assert_eq "missing file: exits 1" "1" "$TC_EXIT"
assert_eq "no cycle dir created" "0" "$(ls -d "$TEST_DIR"/.craft/cycles/*/ 2>/dev/null | wc -l | tr -d ' ')"
cleanup_test_dir
echo ""

# --- Summary ---
finish_tests
