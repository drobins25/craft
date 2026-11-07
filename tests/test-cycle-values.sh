#!/bin/bash
# test-cycle-values.sh - cycle_values.py writes title, target, focus and goals from a
# plain values file in one single-quoted form, and every reader reads them back exactly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

READ_KEY_SH="$SCRIPTS_DIR/read-key.sh"
WRITER="$SCRIPTS_DIR/cycle_values.py"
DASH_ROOT="$SCRIPT_DIR/../scripts/dashboard"

echo "=== test-cycle-values.sh ==="
echo ""

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

TAB=$(printf '\t')
BT='`'

AWKWARD=(
  '"' "'" '\' '#' 'x # y' 'a: b' '[x]' 'null' '42' '2026-11-06'
  '$(touch pwned)' "$BT" '~' "a${TAB}b" "''" '|&/' '%s' '- lead' ' lead'
  'Login fails: "Remember me" box ignored #SSO'
)
# What each value reads back as: the values file strips surrounding whitespace
EXPECTED=(
  '"' "'" '\' '#' 'x # y' 'a: b' '[x]' 'null' '42' '2026-11-06'
  '$(touch pwned)' "$BT" '~' "a${TAB}b" "''" '|&/' '%s' '- lead' 'lead'
  'Login fails: "Remember me" box ignored #SSO'
)

strict_goals() { # one goal per line
  strict_json "$1" | python3 -c 'import json,sys; sys.stdout.write("\n".join(json.load(sys.stdin)["goals"]))'
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
dash_get() { # dash_get <file> <key>
  python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from src import frontmatter
fields = frontmatter.parse_mapping(open(sys.argv[2], encoding="utf-8").read().split("\n"))
sys.stdout.write(fields[sys.argv[3]])
' "$DASH_ROOT" "$1" "$2"
}
file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

fresh_cycle() { # fresh_cycle <dir> [title-line]
  mkdir -p "$1"
  cat > "$1/cycle.yaml" <<YAML
name: demo
title: ${2:-"'Cycle 07: Old'"}
status: planning
created: 2026-11-06
updated: 2026-11-06
target: Old target
focus: TBD
source_concept: none

goals:
  - TBD

notes: |
  keep me
YAML
}

run_writer() { # run_writer <args...>; sets RC, ERR, OUT
  set +e
  OUT=$(python3 "$WRITER" "$@" 2>"$TMP/err")
  RC=$?
  set -e
  ERR=$(cat "$TMP/err")
}

# --- the rule itself ---
begin_test "quoted doubles each ' and wraps in single quotes"
Q=$(python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import cycle_values
sys.stdout.write(cycle_values.quoted("it'"'"'s") + "|" + cycle_values.quoted(""))
' "$SCRIPTS_DIR")
assert_eq "quoted" "'it''s'|''" "$Q"
echo ""

begin_test "write round-trips the awkward set through every reader"
i=0
for v in "${AWKWARD[@]}"; do
  want="${EXPECTED[$i]}"
  D="$TMP/rt$i"
  fresh_cycle "$D"
  printf 'title: %s\ntarget: %s\nfocus: %s\ngoal: %s\n' "$v" "$v" "$v" "$v" > "$TMP/v$i.txt"
  run_writer write "$D" "$TMP/v$i.txt"
  assert_eq "[$v] write exits 0 silently" "0::" "$RC:$OUT:$ERR"
  Y="$D/cycle.yaml"
  assert_eq "[$v] shell title" "Cycle 07: $want" "$(sh_read_key "$Y" title)"
  assert_eq "[$v] python title" "Cycle 07: $want" "$(py_read_key "$Y" title)"
  assert_eq "[$v] strict title" "Cycle 07: $want" "$(strict_get "$Y" title)"
  assert_eq "[$v] dashboard title" "Cycle 07: $want" "$(dash_get "$Y" title)"
  for key in target focus; do
    assert_eq "[$v] shell $key" "$want" "$(sh_read_key "$Y" $key)"
    assert_eq "[$v] python $key" "$want" "$(py_read_key "$Y" $key)"
    assert_eq "[$v] strict $key" "$want" "$(strict_get "$Y" $key)"
    assert_eq "[$v] dashboard $key" "$want" "$(dash_get "$Y" $key)"
  done
  assert_eq "[$v] strict goals" "$want" "$(strict_goals "$Y")"
  i=$((i + 1))
done
assert_eq "no ticket text was run as a command" "no" "$([ -e pwned ] || [ -e "$TMP/pwned" ] && echo yes || echo no)"
echo ""

begin_test "goals keep their order and each reads back exact"
D="$TMP/goals"
fresh_cycle "$D"
: > "$TMP/goals.txt"
for v in "${AWKWARD[@]}"; do printf 'goal: %s\n' "$v" >> "$TMP/goals.txt"; done
run_writer write "$D" "$TMP/goals.txt"
WANT=$(printf '%s\n' "${EXPECTED[@]}")
assert_eq "write ok" "0" "$RC"
assert_eq "all goals through the strict reader, in order" "$WANT" "$(strict_goals "$D/cycle.yaml")"
assert_eq "the key after goals is untouched" "keep me" "$(strict_get "$D/cycle.yaml" notes | tr -d '\n')"
echo ""

begin_test "quotes in the values file are literal"
D="$TMP/lit"
fresh_cycle "$D"
printf 'title: "x"\ntarget: '"'"'y'"'"'\nfocus: f\ngoal: g\n' > "$TMP/lit.txt"
run_writer write "$D" "$TMP/lit.txt"
assert_eq "title keeps its double quotes" 'Cycle 07: "x"' "$(strict_get "$D/cycle.yaml" title)"
assert_eq "target keeps its single quotes" "'y'" "$(strict_get "$D/cycle.yaml" target)"
echo ""

begin_test "text is everything after the first ': ', CR dropped, whitespace stripped"
D="$TMP/fmt"
fresh_cycle "$D"
printf '\ntitle:    a: b: c   \r\n\r\n\ntarget: t\r\nfocus: f\ngoal: g\n\n' > "$TMP/fmt.txt"
run_writer write "$D" "$TMP/fmt.txt"
assert_eq "title" "Cycle 07: a: b: c" "$(strict_get "$D/cycle.yaml" title)"
assert_eq "target" "t" "$(strict_get "$D/cycle.yaml" target)"
echo ""

begin_test "block value replaced whole"
D="$TMP/block"
mkdir -p "$D"
cat > "$D/cycle.yaml" <<'YAML'
name: demo
title: 'Cycle 07: Old'
target: |
  line one

  line two
focus: |
  a
  b
source_concept: none

goals:
  - one
  - two

notes: |
  keep me
YAML
printf 'target: New target\nfocus: New focus\ngoal: Only goal\n' > "$TMP/block.txt"
run_writer write "$D" "$TMP/block.txt"
cat > "$TMP/block.expected" <<'YAML'
name: demo
title: 'Cycle 07: Old'
target: 'New target'
focus: 'New focus'
source_concept: none

goals:
  - 'Only goal'

notes: |
  keep me
YAML
assert_eq "file is exactly the one-line form" "$(cat "$TMP/block.expected")" "$(cat "$D/cycle.yaml")"
assert_eq "strict reader loads it" "New target" "$(strict_get "$D/cycle.yaml" target)"
echo ""

begin_test "label kept"
check_label() { # check_label <desc> <title line> <values title> <expected>
  local D="$TMP/label$RANDOM"
  fresh_cycle "$D" "$2"
  printf 'title: %s\n' "$3" > "$D/v.txt"
  run_writer write "$D" "$D/v.txt"
  assert_eq "$1" "$4" "$(sh_read_key "$D/cycle.yaml" title)"
}
check_label "single-quoted label" "'Cycle 07: Old'" "New" "Cycle 07: New"
check_label "old double-quoted label" '"Cycle 07: Old"' "New" "Cycle 07: New"
check_label "old plain label" "Cycle 07: Old" "New" "Cycle 07: New"
check_label "multi-digit label" "'Cycle 112: Old'" "New" "Cycle 112: New"
check_label "no label gives bare text" "'Old'" "New" "New"
check_label "text already carrying the label is not doubled" "'Cycle 07: Old'" "Cycle 07: New" "Cycle 07: New"
echo ""

begin_test "only named fields change, line endings and mode kept"
D="$TMP/only"
fresh_cycle "$D"
printf 'title: x\r\n' >/dev/null
cp "$D/cycle.yaml" "$TMP/only.before"
chmod 640 "$D/cycle.yaml"
printf 'title: New\n' > "$TMP/only.txt"
run_writer write "$D" "$TMP/only.txt"
CHANGED=$(diff "$TMP/only.before" "$D/cycle.yaml" | grep -c '^[<>]' || true)
assert_eq "one line replaced (one out, one in)" "2" "$CHANGED"
assert_eq "status line identical" "status: planning" "$(grep '^status:' "$D/cycle.yaml")"
assert_eq "file mode kept" "640" "$(file_mode "$D/cycle.yaml")"
assert_eq "no temp files left" "1" "$(ls -A "$D" | wc -l | tr -d ' ')"
D="$TMP/crlf"
mkdir -p "$D"
printf "name: d\r\ntitle: 'Cycle 01: A'\r\ntarget: t\r\n" > "$D/cycle.yaml"
printf 'title: B\n' > "$TMP/crlf.txt"
run_writer write "$D" "$TMP/crlf.txt"
assert_eq "key line keeps its CRLF" "$(printf "name: d\r\ntitle: 'Cycle 01: B'\r\ntarget: t\r\n")" "$(cat "$D/cycle.yaml")"
echo ""

begin_test "errors write nothing"
check_error() { # check_error <desc> <values content> [yaml-variant]
  local D="$TMP/err$RANDOM"
  fresh_cycle "$D"
  if [ "$3" = "nofocus" ]; then grep -v '^focus:' "$D/cycle.yaml" > "$D/c2" && mv "$D/c2" "$D/cycle.yaml"; fi
  cp "$D/cycle.yaml" "$D/before"
  printf '%s' "$2" > "$D/v.txt"
  run_writer write "$D" "$D/v.txt"
  assert_eq "$1: exit 1" "1" "$RC"
  assert_eq "$1: one stderr line" "1" "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')"
  assert_eq "$1: stderr shape" "cycle_values.py: " "${ERR:0:17}"
  assert_eq "$1: stdout empty" "" "$OUT"
  assert_eq "$1: cycle.yaml untouched" "" "$(diff "$D/before" "$D/cycle.yaml")"
}
check_error "unknown field" $'title: a\ncolour: red\n'
check_error "line without colon-space" $'title: a\ntarget no colon\n'
check_error "colon with no space" $'title:a\n'
check_error "empty text" $'title: a\ntarget:   \n'
check_error "repeated title" $'title: a\ntitle: b\n'
check_error "repeated focus" $'focus: a\nfocus: b\n'
check_error "empty goal" $'goal: \n'
check_error "empty values file" ''
check_error "missing focus line in cycle.yaml" $'title: a\nfocus: b\n' nofocus
run_writer write "$TMP/no-such-dir" "$TMP/lit.txt"
assert_eq "missing cycle dir: exit 1, one line" "1:1" "$RC:$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')"
run_writer write "$TMP/rt0" "$TMP/no-such-values.txt"
assert_eq "missing values file: exit 1" "1" "$RC"
run_writer bogus
assert_eq "unknown command: exit 1" "1" "$RC"
echo ""

begin_test "check --need"
printf 'title: a\ntarget: b\n' > "$TMP/chk.txt"
run_writer check "$TMP/chk.txt" --need title --need target
assert_eq "present fields pass silently" "0::" "$RC:$OUT:$ERR"
run_writer check "$TMP/chk.txt"
assert_eq "no --need passes a good file" "0::" "$RC:$OUT:$ERR"
run_writer check "$TMP/chk.txt" --need title --need focus
assert_eq "absent needed field exits 1 with one line" "1:1" "$RC:$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')"
run_writer check "$TMP/chk.txt" --need goal
assert_eq "goal needs a goal line" "1" "$RC"
run_writer check "$TMP/chk.txt" --need colour
assert_eq "unknown --need exits 1" "1" "$RC"
printf 'title: a\nbogus: x\n' > "$TMP/chkbad.txt"
run_writer check "$TMP/chkbad.txt"
assert_eq "bad file exits 1" "1" "$RC"
run_writer check "$TMP/no-such-values.txt"
assert_eq "missing file exits 1" "1" "$RC"
echo ""

begin_test "a goals list written without indentation is replaced whole"
D="$TMP/flatgoals"
mkdir -p "$D"
printf 'name: demo\ntitle: x\ngoals:\n- first\n-\n- second\nnotes: n\n' > "$D/cycle.yaml"
printf 'goal: NEW\n' > "$TMP/flatgoals.txt"
run_writer write "$D" "$TMP/flatgoals.txt"
assert_eq "flat goals write exits 0" "0" "$RC"
assert_eq "old items gone" "name: demo|title: x|goals:|  - 'NEW'|notes: n" "$(tr '\n' '|' < "$D/cycle.yaml" | sed 's/|$//')"
if strict_json "$D/cycle.yaml" >/dev/null 2>&1 || [ $? -eq 127 ]; then
  assert_eq "strict reader loads flat goals" "loads" "loads"
else
  assert_eq "strict reader loads flat goals" "loads" "refused"
fi
echo ""

begin_test "control characters in a value become spaces"
D="$TMP/ctrl"
mkdir -p "$D"
printf "name: demo\ntitle: 'Cycle 01: old'\ngoals:\n  - TBD\n" > "$D/cycle.yaml"
printf 'title: a\001c Red\033[31m ALERT\302\205end\nfocus: tab\tkept\n' > "$TMP/ctrl.txt"
printf 'focus: TBD\n' >> "$D/cycle.yaml"
run_writer write "$D" "$TMP/ctrl.txt"
assert_eq "control write exits 0" "0" "$RC"
assert_eq "shell reader gets plain text" "Cycle 01: a c Red [31m ALERT end" "$(sh_read_key "$D/cycle.yaml" title)"
assert_eq "tab is kept" "tab${TAB}kept" "$(sh_read_key "$D/cycle.yaml" focus)"
if strict_json "$D/cycle.yaml" >/dev/null 2>&1 || [ $? -eq 127 ]; then
  assert_eq "strict reader loads control text" "loads" "loads"
else
  assert_eq "strict reader loads control text" "loads" "refused"
fi
echo ""

begin_test "cycle-design Step 6b writes focus and goals through the script"
STEP=$(awk '/^\*\*6b\./{f=1} /^\*\*6d\./{f=0} f' "$SCRIPT_DIR/../commands/references/cycle-design/default-mode.md")
case "$STEP" in *'cycle_values.py'*) assert_eq "names the writer" "yes" "yes" ;; *) assert_eq "names the writer" "yes" "no" ;; esac
case "$STEP" in *'s/^focus:'*) assert_eq "no typed focus sed" "absent" "present" ;; *) assert_eq "no typed focus sed" "absent" "absent" ;; esac
echo ""

finish_tests
