#!/bin/bash
# test-cycle-text-decoders.sh - The shell read_key, tracker_comments.read_key and a
# strict YAML reader decode the same cycle.yaml text, on awkward values and old forms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

READ_KEY_SH="$SCRIPTS_DIR/read-key.sh"

echo "=== test-cycle-text-decoders.sh ==="
echo ""

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

TAB=$(printf '\t')
Q="'"
DQ="''"
BT='`'

# The awkward set. A value per slot, in one array (bash 3.2: no associative arrays).
AWKWARD=(
  '"' "'" '\' '#' 'x # y' 'a: b' '[x]' 'null' '42' '2026-11-06'
  '$(touch pwned)' "$BT" '~' "a${TAB}b" "''" '|&/' '%s' '- lead' ' lead'
  'Cycle 01: Login fails: "Remember me" box ignored #SSO'
)

py_read_key() { # py_read_key <file> <key>
  python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import tracker_comments
sys.stdout.write(tracker_comments.read_key(open(sys.argv[2], encoding="utf-8").read(), sys.argv[3]))
' "$SCRIPTS_DIR" "$1" "$2"
}

sh_read_key() { # sh_read_key <file> <key> - bash 3.2 and the current shell both
  /bin/bash -c 'source "$1"; read_key "$2" "$3"' _ "$READ_KEY_SH" "$1" "$2"
}

# --- FIRST test: a strict reader exists here and handles a dated fixture ---
begin_test "strict YAML reader is present"
printf 'created: 2026-11-06\nname: x\n' > "$TMP/dated.yaml"
set +e
OUT=$(strict_get "$TMP/dated.yaml" name 2>&1)
RC=$?
set -e
assert_eq "PyYAML or Ruby loads a dated fixture" "0:x" "$RC:$OUT"
if [ "$RC" != "0" ]; then
  echo "  No strict YAML reader found (PyYAML or ruby); cannot prove the form. Stopping."
  finish_tests
  exit 1
fi
echo ""

# Fixture: one key per awkward value, single-quoted with ' doubled
FIX="$TMP/awkward.yaml"
: > "$FIX"
i=0
for v in "${AWKWARD[@]}"; do
  printf 'k%d: %s%s%s\n' "$i" "$Q" "${v//$Q/$DQ}" "$Q" >> "$FIX"
  i=$((i + 1))
done

begin_test "shell read_key decodes the awkward set"
i=0
for v in "${AWKWARD[@]}"; do
  assert_eq "k$i [$v]" "$v" "$(sh_read_key "$FIX" "k$i")"
  i=$((i + 1))
done
echo ""

begin_test "Python read_key agrees with shell read_key"
i=0
for v in "${AWKWARD[@]}"; do
  assert_eq "k$i [$v]" "$v" "$(py_read_key "$FIX" "k$i")"
  i=$((i + 1))
done
echo ""

begin_test "strict reader agrees"
i=0
for v in "${AWKWARD[@]}"; do
  assert_eq "k$i [$v]" "$v" "$(strict_get "$FIX" "k$i")"
  i=$((i + 1))
done
echo ""

begin_test "dashboard parse_mapping agrees"
DASH=$(python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from src import frontmatter
fields = frontmatter.parse_mapping(open(sys.argv[2], encoding="utf-8").read().split("\n"))
import json
print(json.dumps(fields))
' "$SCRIPT_DIR/../scripts/dashboard" "$FIX")
i=0
for v in "${AWKWARD[@]}"; do
  got=$(printf '%s' "$DASH" | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)[sys.argv[1]])' "k$i")
  assert_eq "k$i [$v]" "$v" "$got"
  i=$((i + 1))
done
echo ""

begin_test "old forms read"
OLD="$TMP/old.yaml"
{
  printf 'dq: "Cycle 01: Auth"\n'
  printf 'dqinner: "Cycle 01: Login fails: "Remember me" box"\n'
  printf 'plain: Self-Improvement\n'
  printf "plaindoubled: Don''t\n"
  printf 'spaced:    "  padded  "   \n'
  printf 'crlf: '"'"'x'"'"'\r\n'
  printf 'lone: '"'"'\n'
  printf 'empty:\n'
  printf 'emptyq: '"''"'\n'
  printf 'emptydq: ""\n'
} > "$OLD"
check_old() { # check_old <key> <expected>
  assert_eq "shell $1" "$2" "$(sh_read_key "$OLD" "$1")"
  assert_eq "python $1" "$2" "$(py_read_key "$OLD" "$1")"
}
check_old dq "Cycle 01: Auth"
check_old dqinner 'Cycle 01: Login fails: "Remember me" box'
check_old plain "Self-Improvement"
check_old plaindoubled "Don''t"
check_old spaced "  padded  "
check_old crlf "x"
check_old lone "'"
check_old empty ""
check_old emptyq ""
check_old emptydq ""
echo ""

begin_test "real cycle.yaml files in this repo read the same in shell and Python"
REAL_N=0
for f in "$SCRIPT_DIR"/../.craft/cycles/*/cycle.yaml; do
  [ -f "$f" ] || continue
  for key in title target name status; do
    a=$(sh_read_key "$f" "$key")
    b=$(py_read_key "$f" "$key")
    if [ "$a" != "$b" ]; then
      echo "  FAIL: $f $key: shell [$a] python [$b]"
      FAIL=$((FAIL + 1))
    fi
  done
  REAL_N=$((REAL_N + 1))
done
echo "  checked $REAL_N real cycle files"
PASS=$((PASS + 1))
echo ""

begin_test "missing key or file prints nothing and exits 0 under set -e"
set +e
OUT=$(/bin/bash -ec 'source "$1"; read_key "$2" nokey; read_key /nonexistent/x.yaml title; echo done' _ "$READ_KEY_SH" "$FIX")
RC=$?
set -e
assert_eq "set -e survives, prints only done" "0:done" "$RC:$OUT"
assert_eq "missing key via python" "" "$(py_read_key "$FIX" nokey)"
echo ""

begin_test "sourcing read-key.sh runs nothing"
set +e
OUT=$(/bin/bash -c 'source "$1"' _ "$READ_KEY_SH" 2>&1)
RC=$?
set -e
assert_eq "silent, exit 0" "0:" "$RC:$OUT"
echo ""

begin_test "cycle-stage output unchanged"
set +e
OUT=$(bash "$SCRIPT_DIR/test-cycle-stage.sh" 2>&1)
RC=$?
set -e
assert_eq "test-cycle-stage.sh passes" "0" "$RC"
echo ""

finish_tests
