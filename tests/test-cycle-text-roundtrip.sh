#!/bin/bash
# test-cycle-text-roundtrip.sh - Ticket text survives the whole path: a ticket
# with an awkward title and target becomes a cycle (create-cycle.sh --values),
# a rewritten awkward ticket updates it (follow-issue.py check, then update
# --values), and after each write every reader prints the text exactly - the
# shell hooks, the stop hook's JSON, get-latest-cycle, the dashboard, and a
# strict YAML reader.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
# Run from a throwaway folder: a script that misreads its arguments and falls back
# to the current folder must never write into the real project.
cd "$(mktemp -d)"
source "$SCRIPT_DIR/fixtures/minimal.sh"

CREATE="$SCRIPTS_DIR/create-cycle.sh"
FOLLOW="$SCRIPTS_DIR/follow-issue.py"
DASH_ROOT="$SCRIPT_DIR/../scripts/dashboard"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BT='`'
FIRST=dro-21-issue-2026-10-31T1840Z.md

# Pairs of (first ticket, rewritten ticket) text: each row is one flow.
# T1/G1 create the cycle; T2/G2/F2 and two goals rewrite it.
T1=(
  "Login fails: \"Remember me\" box ignored #SSO, it's [odd] \\ ${BT}x${BT} \$(touch pwned)"
  'null'
  "'"
  "''"
)
G1=(
  "Users say \"it's broken\": # not a comment, - not a list, | not a block"
  '42'
  '"'
  '~'
)
T2=(
  "Logout loops: 'Sign out' => \"Sign in\" #2, 100% of the time \\n"
  '2026-11-06'
  "'quoted'"
  '[x]'
)
G2=(
  "Expect: {a: b}, 'single' and \"double\" together # end"
  'true'
  "it's"
  '&anchor'
)
F2=(
  "Focus on the redirect: 1st \"hop\" only"
  '- lead'
  "'"
  '*alias'
)
GOALS2A=(
  "Fix the loop: don't \"redirect\" twice"
  "Keep the #SSO session"
)
GOALS2B=(
  "'"
  "a: b"
)

strict_json() {
  python3 -c 'import json,sys,yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1], encoding="utf-8")), default=str))' "$1"
}
strict_get() { # strict_get <file> <key>
  strict_json "$1" | python3 -c 'import json,sys; sys.stdout.write(str(json.load(sys.stdin)[sys.argv[1]]))' "$2"
}
strict_goals() { # one goal per line
  strict_json "$1" | python3 -c 'import json,sys; sys.stdout.write("\n".join(json.load(sys.stdin)["goals"]))'
}
dash_get() { # dash_get <file> <key>
  python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from src import frontmatter
fields = frontmatter.parse_mapping(open(sys.argv[2], encoding="utf-8").read().split("\n"))
sys.stdout.write(fields[sys.argv[3]])
' "$DASH_ROOT" "$1" "$2"
}
json_message() { printf '%s' "$1" | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["systemMessage"])'; }
stop_marker_for() {
  local id
  id=$(echo "$1" | md5sum 2>/dev/null | cut -c1-8)
  [ -n "$id" ] || id=$(echo "$1" | md5 2>/dev/null | cut -c1-8)
  printf '%s' "$id"
}

has_line() { printf '%s\n' "$1" | grep -Fxq -- "$2"; }
check_line() { # check_line <desc> <output> <line>
  if has_line "$2" "$3"; then
    echo "  PASS: $1"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $1"; echo "    wanted line: '$3'"; echo "    output: '$2'"; FAIL=$((FAIL + 1))
  fi
}
check_text() { # check_text <desc> <output> <text>
  case "$2" in
    *"$3"*) echo "  PASS: $1"; PASS=$((PASS + 1)) ;;
    *) echo "  FAIL: $1"; echo "    wanted text: '$3'"; echo "    output: '$2'"; FAIL=$((FAIL + 1)) ;;
  esac
}

# set_state <project> <cycle-dir-name> <active|planning>
set_state() {
  local p="$1" c="$2" mode="$3"
  printf 'CYCLE_STATUS="%s"\nCURRENT_STORY=""\nCURRENT_CHUNK="0"\nTOTAL_CHUNKS="0"\n' "$mode" > "$p/.craft/cycles/$c/.state"
  if [ "$mode" = planning ]; then
    printf 'ACTIVE_CYCLE=""\nPLANNING_CYCLE="%s"\nCURRENT_STORY=""\n' "$c" > "$p/.craft/.global-state"
  else
    printf 'ACTIVE_CYCLE="%s"\nPLANNING_CYCLE=""\nCURRENT_STORY=""\n' "$c" > "$p/.craft/.global-state"
  fi
}

# readers <label> <project> <cycle-dir-name> <title> <target>: every reader
# prints the title (and the target where it shows one) exactly. Each reader
# runs on a copy of the project so the readers that change state cannot
# disturb the next one.
readers() {
  local label="$1" src="$2" c="$3" t="$4" g="$5" p out msg yaml
  yaml="$src/.craft/cycles/$c/cycle.yaml"

  p=$(mktemp -d "$TMP/copy.XXXXXX"); cp -R "$src/." "$p/"; set_state "$p" "$c" active
  out=$(echo '{}' | CRAFT_PROJECT_ROOT="$p" bash "$SCRIPTS_DIR/statusline.sh" 2>/dev/null)
  check_text "$label statusline" "$out" "[$t] "
  out=$(cd "$p" && unset PROJECT_ROOT CRAFT_PROJECT_ROOT CRAFT_MULTI_PROJECT && CLAUDE_ENV_FILE="$p/env" bash "$SCRIPTS_DIR/session-start.sh" 2>/dev/null)
  check_text "$label session-start" "$out" "Active cycle: $t |"
  out=$(cd "$p" && unset PROJECT_ROOT CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/inject-craft-context.sh" 2>/dev/null)
  check_text "$label inject-craft-context (active)" "$out" "Cycle '$t'"
  out=$(cd "$p" && CRAFT_PROJECT_ROOT="$p" bash "$SCRIPTS_DIR/post-compact-reinject.sh" 2>/dev/null)
  check_line "$label post-compact-reinject" "$out" "Active cycle: $t"
  (cd "$p" && CRAFT_PROJECT_ROOT="$p" bash "$SCRIPTS_DIR/export-progress.sh" >/dev/null 2>&1) || true
  out=$(cat "$p"/.craft/.exports/pre-compact-*.md 2>/dev/null)
  check_line "$label export-progress" "$out" "## Cycle State: $t"
  out=$(bash "$SCRIPTS_DIR/get-latest-cycle.sh" "$p" 2>/dev/null)
  check_line "$label get-latest-cycle" "$out" "CYCLE_TITLE=\"$t\""

  printf 'ACTIVE_CYCLE="%s"\nPLANNING_CYCLE=""\nCURRENT_STORY="s"\n' "$c" > "$p/.craft/.global-state"
  rm -f "/tmp/craft-stop-suggested-$(stop_marker_for "$(cd "$p" && pwd -P)")"
  out=$(cd "$p" && unset CRAFT_PROJECT_ROOT PROJECT_ROOT && echo '{"stop_hook_active": false}' | bash "$SCRIPTS_DIR/stop-hook-guard.sh" 2>/dev/null) || true
  set +e
  msg=$(json_message "$out" 2>/dev/null)
  local rc=$?
  set -e
  if [ "$rc" != 0 ]; then
    echo "  FAIL: $label stop-hook JSON is not valid"; echo "    output: '$out'"; FAIL=$((FAIL + 1))
  else
    check_text "$label stop-hook message" "$msg" "[$t]"
  fi

  out=$(bash "$SCRIPTS_DIR/complete-cycle.sh" "$p/.craft/cycles/$c" 2>/dev/null) || true
  check_line "$label complete-cycle" "$out" "Cycle completed: $t"

  p=$(mktemp -d "$TMP/copy.XXXXXX"); cp -R "$src/." "$p/"; set_state "$p" "$c" planning
  out=$(cd "$p" && unset PROJECT_ROOT CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/inject-craft-context.sh" 2>/dev/null)
  check_text "$label inject-craft-context (planning)" "$out" "PLANNING cycle '$t'"
  out=$(bash "$SCRIPTS_DIR/start-cycle.sh" "$p/.craft/cycles/$c" 2>/dev/null) || true
  check_line "$label start-cycle" "$out" "Cycle started: $t"

  # The dashboard: its cycle node title in the built graph, and its parsed target
  p=$(mktemp -d "$TMP/copy.XXXXXX"); cp -R "$src/." "$p/"
  bash "$DASH_ROOT/dashboard-run.sh" --root "$p" >/dev/null 2>&1 || true
  out=$(python3 - "$p/.craft/graph/graph.js" <<'INNER'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
data = json.loads(text[text.index("{"):text.rindex("}") + 1])
print([n["title"] for n in data["nodes"] if n["type"] == "cycle"][0])
INNER
  )
  assert_eq "$label dashboard graph title" "$t" "$out"
  assert_eq "$label dashboard title" "$t" "$(dash_get "$yaml" title)"
  assert_eq "$label dashboard target" "$g" "$(dash_get "$yaml" target)"

  assert_eq "$label strict title" "$t" "$(strict_get "$yaml" title)"
  assert_eq "$label strict target" "$g" "$(strict_get "$yaml" target)"
}

# add_first_copy <cycle-dir> <title>: the issue copy the cycle was made from
add_first_copy() {
  local d="$1/context"
  mkdir -p "$d"
  printf '# DRO-21: %s\n\nSource: https://linear.app/x/issue/DRO-21\nStatus at retrieval: In Progress (copied for reference; never a permission)\n\nThe body.\n' "$2" > "$d/$FIRST"
  cat > "$d/README.md" <<FIX
# DRO-21 context

| File | What | Retrieved | Tool |
|---|---|---|---|
| $FIRST | Issue title, status and description | 2026-10-31T18:40:12Z | linear |
FIX
}

echo "=== test-cycle-text-roundtrip.sh ==="
echo ""

i=0
while [ "$i" -lt "${#T1[@]}" ]; do
  t1="${T1[$i]}"; g1="${G1[$i]}"; t2="${T2[$i]}"; g2="${G2[$i]}"; f2="${F2[$i]}"
  if [ "$((i % 2))" = 0 ]; then goals2=("${GOALS2A[@]}"); else goals2=("${GOALS2B[@]}"); fi
  P=$(create_minimal_craft)
  echo "--- flow $((i + 1)): $t1"

  begin_test "flow $((i + 1)): create from an awkward ticket"
  printf 'title: %s\ntarget: %s\n' "$t1" "$g1" > "$TMP/create-values.txt"
  set +e
  OUT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE" --values "$TMP/create-values.txt" intake "" "" "$P" "" DRO-21 plan 2>&1)
  RC=$?
  set -e
  assert_eq "create exits 0" "0" "$RC"
  CYC=$(ls "$P/.craft/cycles" | head -1)
  CDIR="$P/.craft/cycles/$CYC"
  NN=$(printf '%s' "$CYC" | sed 's/-.*//')
  LABEL="Cycle $(printf '%02d' "$NN"): "
  assert_eq "strict reader loads the file" "intake" "$(strict_get "$CDIR/cycle.yaml" name)"
  readers "create:" "$P" "$CYC" "${LABEL}${t1}" "$g1"

  begin_test "flow $((i + 1)): follow a rewritten awkward ticket"
  add_first_copy "$CDIR" "$t1"
  printf '# DRO-21: %s\n\nSource: https://linear.app/x/issue/DRO-21\nStatus at retrieval: In Progress (copied for reference; never a permission)\n\nThe body, rewritten.\n' "$t2" > "$TMP/staged.md"
  set +e
  OUT=$(python3 "$FOLLOW" check "$CDIR" --issue "$TMP/staged.md" --tool linear --now 2026-11-02T10:15:30Z 2>&1)
  RC=$?
  set -e
  assert_eq "check exits 0" "0" "$RC"
  check_line "check sees the change" "$OUT" "verdict=changed"
  check_line "check reports the new title" "$OUT" "new_title=$t2"
  : > "$TMP/update-values.txt"
  printf 'target: %s\nfocus: %s\n' "$g2" "$f2" >> "$TMP/update-values.txt"
  for goal in "${goals2[@]}"; do printf 'goal: %s\n' "$goal" >> "$TMP/update-values.txt"; done
  set +e
  OUT=$(python3 "$FOLLOW" update "$CDIR" --values "$TMP/update-values.txt" --now 2026-11-03T08:00:00Z 2>&1)
  RC=$?
  set -e
  assert_eq "update exits 0" "0" "$RC"
  assert_eq "update says it followed" "say=Cycle $NN now follows DRO-21 as of Nov 2." "$OUT"
  readers "update:" "$P" "$CYC" "${LABEL}${t2}" "$g2"
  assert_eq "update: strict focus" "$f2" "$(strict_get "$CDIR/cycle.yaml" focus)"
  assert_eq "update: dashboard focus" "$f2" "$(dash_get "$CDIR/cycle.yaml" focus)"
  assert_eq "update: strict goals" "$(printf '%s\n' "${goals2[@]}")" "$(strict_goals "$CDIR/cycle.yaml")"
  assert_eq "update: the tracker lines stay" "source_issue: 'DRO-21'" "$(grep '^source_issue:' "$CDIR/cycle.yaml")"
  assert_eq "update: the change record is cleared" "0" "$(grep -c '^issue_changed' "$CDIR/cycle.yaml")"
  assert_eq "no ticket text ran as a command" "no" "$([ -e pwned ] || [ -e "$TMP/pwned" ] && echo yes || echo no)"
  rm -rf "$P"
  echo ""
  i=$((i + 1))
done

finish_tests
