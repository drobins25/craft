#!/bin/bash
# test-cycle-text-readers.sh - Every script that shows a cycle's title reads it
# through the shared read_key, prints it exactly (awkward text and old forms),
# keeps the stop hook's JSON valid, and no script keeps a private title reader

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

TAB=$(printf '\t')
Q="'"
DQ="''"
BT='`'

# The awkward set (bash 3.2: one indexed array, no associative arrays).
AWKWARD=(
  '"' "'" '\' '#' 'x # y' 'a: b' '[x]' 'null' '42' '2026-11-06'
  '$(touch pwned)' "$BT" '~' "a${TAB}b" "''" '|&/' '%s' '- lead' ' lead'
  'Login fails: "Remember me" box ignored #SSO'
)

# has_line <output> <line>: the output holds exactly that line
has_line() {
  printf '%s\n' "$1" | grep -Fxq -- "$2"
}

# has_text <output> <text>: the output holds the text verbatim
has_text() {
  case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac
}

check_line() { # check_line <desc> <output> <line>
  if has_line "$2" "$3"; then
    echo "  PASS: $1"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $1"; echo "    wanted line: '$3'"; echo "    output: '$2'"; FAIL=$((FAIL + 1))
  fi
}

check_text() { # check_text <desc> <output> <text>
  if has_text "$2" "$3"; then
    echo "  PASS: $1"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $1"; echo "    wanted text: '$3'"; echo "    output: '$2'"; FAIL=$((FAIL + 1))
  fi
}

# mk_project <raw title line value> <state>: a project holding cycle 1-c whose
# cycle.yaml carries the raw (already encoded) title; state is the cycle status
# kept in .global-state (planning or active)
mk_project() {
  local raw="$1" mode="$2" p
  p=$(mktemp -d "$TMP/p.XXXXXX")
  mkdir -p "$p/.craft/cycles/1-c/stories"
  printf 'name: c\ntitle: %s\nstatus: %s\n' "$raw" "$mode" > "$p/.craft/cycles/1-c/cycle.yaml"
  printf 'CYCLE_STATUS="%s"\nCURRENT_STORY=""\nCURRENT_CHUNK="0"\nTOTAL_CHUNKS="0"\n' "$mode" > "$p/.craft/cycles/1-c/.state"
  if [ "$mode" = planning ]; then
    printf 'ACTIVE_CYCLE=""\nPLANNING_CYCLE="1-c"\nCURRENT_STORY=""\n' > "$p/.craft/.global-state"
  else
    printf 'ACTIVE_CYCLE="1-c"\nPLANNING_CYCLE=""\nCURRENT_STORY=""\n' > "$p/.craft/.global-state"
  fi
  echo "$p"
}

# run_readers <raw> <expected title>: drive every plain-text reader and assert
run_readers() {
  local raw="$1" t="$2" p out
  # statusline
  p=$(mk_project "$raw" active)
  out=$(echo '{}' | CRAFT_PROJECT_ROOT="$p" bash "$SCRIPTS_DIR/statusline.sh" 2>/dev/null)
  check_text "statusline shows it" "$out" "[$t] "
  # session-start
  out=$(cd "$p" && unset PROJECT_ROOT CRAFT_PROJECT_ROOT CRAFT_MULTI_PROJECT && CLAUDE_ENV_FILE="$p/env" bash "$SCRIPTS_DIR/session-start.sh" 2>/dev/null)
  check_text "session-start shows it" "$out" "Active cycle: $t |"
  # inject-craft-context, active
  out=$(cd "$p" && unset PROJECT_ROOT CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/inject-craft-context.sh" 2>/dev/null)
  check_text "inject-craft-context (active) shows it" "$out" "Cycle '$t'"
  # post-compact-reinject
  out=$(cd "$p" && CRAFT_PROJECT_ROOT="$p" bash "$SCRIPTS_DIR/post-compact-reinject.sh" 2>/dev/null)
  check_line "post-compact-reinject shows it" "$out" "Active cycle: $t"
  # export-progress
  (cd "$p" && CRAFT_PROJECT_ROOT="$p" bash "$SCRIPTS_DIR/export-progress.sh" >/dev/null 2>&1) || true
  out=$(cat "$p"/.craft/.exports/pre-compact-*.md 2>/dev/null)
  check_line "export-progress shows it" "$out" "## Cycle State: $t"
  # get-latest-cycle
  out=$(bash "$SCRIPTS_DIR/get-latest-cycle.sh" "$p" 2>/dev/null)
  check_line "get-latest-cycle prints it verbatim" "$out" "CYCLE_TITLE=$t"
  # complete-cycle (active cycle)
  out=$(bash "$SCRIPTS_DIR/complete-cycle.sh" "$p/.craft/cycles/1-c" 2>/dev/null) || true
  check_line "complete-cycle shows it" "$out" "Cycle completed: $t"
  # inject-craft-context, planning, then start-cycle
  p=$(mk_project "$raw" planning)
  out=$(cd "$p" && unset PROJECT_ROOT CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/inject-craft-context.sh" 2>/dev/null)
  check_text "inject-craft-context (planning) shows it" "$out" "PLANNING cycle '$t'"
  out=$(bash "$SCRIPTS_DIR/start-cycle.sh" "$p/.craft/cycles/1-c" 2>/dev/null) || true
  check_line "start-cycle shows it" "$out" "Cycle started: $t"
}

echo "=== test-cycle-text-readers.sh ==="
echo ""

begin_test "each reader prints the awkward title exactly"
for v in "${AWKWARD[@]}"; do
  t="Cycle 01: $v"
  inner=${t//$Q/$DQ}
  echo " value: $v"
  run_readers "'$inner'" "$t"
done
echo ""

begin_test "old forms print as before (inner double quote now kept)"
run_readers '"Cycle 01: Auth"' 'Cycle 01: Auth'
run_readers 'Self-Improvement' 'Self-Improvement'
run_readers '"Cycle 01: Login fails: "Remember me" box"' 'Cycle 01: Login fails: "Remember me" box'
echo ""

# stop_json <project> <stdin-json>: run the stop hook from the project dir
stop_marker_for() {
  local id
  id=$(echo "$1" | md5sum 2>/dev/null | cut -c1-8)
  [ -n "$id" ] || id=$(echo "$1" | md5 2>/dev/null | cut -c1-8)
  printf '%s' "$id"
}

json_message() { # json_message <json text>: the systemMessage, or fails
  printf '%s' "$1" | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["systemMessage"])'
}

check_stop_json() { # check_stop_json <desc> <output> <expected title>
  local msg rc
  set +e
  msg=$(json_message "$2" 2>/dev/null)
  rc=$?
  set -e
  if [ "$rc" != 0 ]; then
    echo "  FAIL: $1 - not valid JSON"; echo "    output: '$2'"; FAIL=$((FAIL + 1))
  else
    check_text "$1" "$msg" "[$3]"
  fi
}

begin_test "stop-hook output is valid JSON with the exact title"
for v in "${AWKWARD[@]}"; do
  t="Cycle 01: $v"
  inner=${t//$Q/$DQ}
  echo " value: $v"
  p=$(mk_project "'$inner'" active)
  # Layer 2 set-down: a story is current, no chunk in motion
  printf 'ACTIVE_CYCLE="1-c"\nPLANNING_CYCLE=""\nCURRENT_STORY="s"\n' > "$p/.craft/.global-state"
  rm -f "/tmp/craft-stop-suggested-$(stop_marker_for "$(cd "$p" && pwd -P)")"
  out=$(cd "$p" && unset CRAFT_PROJECT_ROOT PROJECT_ROOT && echo '{"stop_hook_active": false}' | bash "$SCRIPTS_DIR/stop-hook-guard.sh" 2>/dev/null) || true
  check_stop_json "layer 2 set-down message" "$out" "$t"
  # Layer 1: a chunk in motion; first stop stamps, the second stop sets down
  printf 'CYCLE_STATUS="active"\nCURRENT_STORY="s"\nCURRENT_CHUNK="1"\nTOTAL_CHUNKS="3"\n' > "$p/.craft/cycles/1-c/.state"
  mark="/tmp/craft-chunk-continue-$(stop_marker_for "$(cd "$p" && pwd -P)")"
  rm -f "$mark"
  out=$(cd "$p" && unset CRAFT_PROJECT_ROOT PROJECT_ROOT && echo '{"stop_hook_active": false}' | bash "$SCRIPTS_DIR/stop-hook-guard.sh" 2>/dev/null) || true
  check_stop_json "layer 1 first stop message" "$out" "$t"
  out=$(cd "$p" && unset CRAFT_PROJECT_ROOT PROJECT_ROOT && echo '{"stop_hook_active": false}' | bash "$SCRIPTS_DIR/stop-hook-guard.sh" 2>/dev/null) || true
  check_stop_json "layer 1 second stop message" "$out" "$t"
  rm -f "$mark"
done
echo ""

begin_test "get-latest-cycle prints an inner-quote title verbatim"
p=$(mk_project "'Cycle 01: Login fails: \"Remember me\" box'" active)
out=$(bash "$SCRIPTS_DIR/get-latest-cycle.sh" "$p" 2>/dev/null)
check_line "CYCLE_TITLE line" "$out" 'CYCLE_TITLE=Cycle 01: Login fails: "Remember me" box'
echo ""

# find_private_readers <dir>: files under dir that name cycle.yaml and grep a
# cycle title, target or focus line themselves, other than the shared helper
find_private_readers() {
  local f
  find "$1" -type f ! -name read-key.sh ! -path '*__pycache__*' | while read -r f; do
    if grep -Iq 'cycle\.yaml' "$f" && grep -Eq '\^(title|target|focus):' "$f"; then
      echo "$f"
    fi
  done
}

begin_test "guard finds no private title reader"
FOUND=$(find_private_readers "$SCRIPTS_DIR")
assert_eq "no file reads a cycle title, target or focus itself" "" "$FOUND"
echo ""

begin_test "guard bites on a seeded copy"
SEED="$TMP/seed"
mkdir -p "$SEED"
cp "$SCRIPTS_DIR"/*.sh "$SEED/"
printf '#!/bin/bash\nt=$(grep "^title:" "$1/cycle.yaml" | sed "s/title: *//")\n' > "$SEED/private-reader.sh"
FOUND=$(find_private_readers "$SEED")
assert_eq "the seeded private reader is reported" "$SEED/private-reader.sh" "$FOUND"
echo ""

begin_test "statusline falls back to the slug when the helper cannot be sourced"
FAKE="$TMP/fake-scripts"
mkdir -p "$FAKE"
cp "$SCRIPTS_DIR/statusline.sh" "$SCRIPTS_DIR/find-workshop.sh" "$FAKE/"
p=$(mk_project "'Cycle 01: X'" active)
set +e
out=$(echo '{}' | CRAFT_PROJECT_ROOT="$p" bash "$FAKE/statusline.sh" 2>/dev/null)
rc=$?
set -e
assert_eq "exits 0" "0" "$rc"
check_text "shows the slug" "$out" "[c] "
echo ""

finish_tests
