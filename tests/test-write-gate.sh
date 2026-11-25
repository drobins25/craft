#!/bin/bash
# test-write-gate.sh - Tests for hooks/scripts/write-gate.sh
# The shared script that opens, closes and reports one session's write gate file
# (.craft/.gate/<CLAUDE_CODE_SESSION_ID>).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
# Failing commands are expected here (the script exits 1 on purpose); every
# result is captured and asserted by the test that provoked it.
set +e

WG="$SCRIPTS_DIR/write-gate.sh"
ID="craft-test-session"
ERR_FILE=$(mktemp)
TMP_DIRS=""
READER=""
trap '[ -n "$READER" ] && kill "$READER" 2>/dev/null; rm -f "$ERR_FILE"; for d in $TMP_DIRS; do rm -rf "$d"; done' EXIT
trap 'exit 143' INT TERM HUP

NOT_OPENED="write-gate: CLAUDE_CODE_SESSION_ID is empty or not a session id - the gate was not opened"
NOTHING_CLOSED="write-gate: CLAUDE_CODE_SESSION_ID is empty or not a session id - nothing closed"

# run_as <id|-> <args...>: runs the script as that session ("-" leaves the id
# unset) with CRAFT_PROJECT_ROOT cleared, and sets OUT, ERR and RC.
run_as() {
  local id="$1"
  shift
  if [ "$id" = "-" ]; then
    OUT=$(env -u CLAUDE_CODE_SESSION_ID -u CRAFT_PROJECT_ROOT -u PROJECT_ROOT bash "$WG" "$@" 2>"$ERR_FILE")
  else
    OUT=$(env -u CRAFT_PROJECT_ROOT -u PROJECT_ROOT CLAUDE_CODE_SESSION_ID="$id" bash "$WG" "$@" 2>"$ERR_FILE")
  fi
  RC=$?
  ERR=$(cat "$ERR_FILE")
}

# g <verb args...>: this test's session against the current fixture $R.
g() { run_as "$ID" --root "$R" "$@"; }

# newproj: a set-up Craft project in a temp folder, canonical path in $R.
newproj() {
  R=$(mktemp -d)
  TMP_DIRS="$TMP_DIRS $R"
  R=$(cd "$R" && pwd -P)
  mkdir -p "$R/.craft/cycles/1-c/stories" "$R/.craft/sessions"
  printf 'ACTIVE_CYCLE=""\n' > "$R/.craft/.global-state"
}

# mkstory <name>: creates a story file in $R and prints its canonical path.
mkstory() {
  local f="$R/.craft/cycles/1-c/stories/$1.md"
  printf -- '---\nname: %s\n---\n' "$1" > "$f"
  printf '%s\n' "$f"
}

# mkwf <name>: creates a workflow session folder in $R and prints its path.
mkwf() {
  mkdir -p "$R/.craft/sessions/$1"
  printf '%s\n' "$R/.craft/sessions/$1"
}

gf() { printf '%s\n' "$R/.craft/.gate/${1:-$ID}"; }

# lines <id>: the gate file's lines joined with " / " ("" when there is no file).
lines() {
  local f
  f=$(gf "${1:-}")
  [ -f "$f" ] || { printf ''; return; }
  tr '\n' '|' < "$f" | sed 's/|$//; s/|/ \/ /g'
}

snap() { cp "$(gf "${1:-}")" "$R/.snap"; }
same_as_snap() { cmp -s "$(gf "${1:-}")" "$R/.snap" && echo same || echo changed; }

echo "=== test-write-gate.sh ==="
echo ""

begin_test "the script exists and is executable"
assert_file_exists "write-gate.sh exists" "$WG"
if [ -x "$WG" ]; then X=yes; else X=no; fi
assert_eq "write-gate.sh is executable" "yes" "$X"
echo ""

begin_test "open story writes .craft/.gate/<id> holding the story's canonical path and prints opened <path>"
newproj
S=$(mkstory s1)
g open story "$S"
assert_exit_code "exit 0" "0" "$RC"
assert_eq "prints opened <path>" "opened $S" "$OUT"
assert_eq "gate file holds the path" "$S" "$(lines)"
assert_eq "file ends in a newline" "1" "$(wc -l < "$(gf)" | tr -d ' ')"
echo ""

begin_test "open with CLAUDE_CODE_SESSION_ID unset exits 1 with the not-opened line and creates nothing"
newproj
S=$(mkstory s1)
run_as - --root "$R" open story "$S"
assert_exit_code "exit 1" "1" "$RC"
assert_eq "stderr line" "$NOT_OPENED" "$ERR"
assert_dir_not_exists "no .craft/.gate" "$R/.craft/.gate"
echo ""

begin_test "open with ids ../x, .gitignore, a/b, empty and a 129-character id exits 1 and writes nothing"
newproj
S=$(mkstory s1)
LONG=$(printf 'a%.0s' $(seq 1 129))
for BAD in "../x" ".gitignore" "a/b" "" "$LONG" "a b" ".hidden"; do
  run_as "$BAD" --root "$R" open story "$S"
  assert_exit_code "exit 1 for '$BAD'" "1" "$RC"
  assert_eq "not-opened line for '$BAD'" "$NOT_OPENED" "$ERR"
done
assert_dir_not_exists "no .craft/.gate created" "$R/.craft/.gate"
assert_file_not_exists "nothing written above the project" "$R/../x"
LONG128=$(printf 'a%.0s' $(seq 1 128))
run_as "$LONG128" --root "$R" open docs
assert_exit_code "a 128-character id is valid" "0" "$RC"
echo ""

begin_test "open in a never-inited folder prints skipped, exits 0 even with no id, and creates no .craft/.gate and no .global-state"
R=$(mktemp -d); TMP_DIRS="$TMP_DIRS $R"; R=$(cd "$R" && pwd -P)
mkdir -p "$R/.craft/mockups/x"
run_as - --root "$R" open docs
assert_exit_code "open exits 0 with no id" "0" "$RC"
assert_eq "open prints skipped" "skipped" "$OUT"
run_as "$ID" --root "$R" open story "$R/none.md"
assert_eq "open story prints skipped" "skipped" "$OUT"
assert_exit_code "open story exits 0" "0" "$RC"
run_as "$ID" --root "$R" close docs
assert_eq "close prints skipped" "skipped" "$OUT"
run_as "$ID" --root "$R" claim story "$R/none.md"
assert_eq "claim prints skipped" "skipped" "$OUT"
run_as "$ID" --root "$R" check story "$R/none.md"
assert_eq "check prints free" "free" "$OUT"
assert_exit_code "check exits 0" "0" "$RC"
run_as - --root "$R" holder
assert_eq "holder prints nothing" "" "$OUT"
assert_exit_code "holder exits 0" "0" "$RC"
run_as - --root "$R" preflight
assert_eq "preflight prints skipped" "skipped" "$OUT"
assert_exit_code "preflight exits 0" "0" "$RC"
assert_dir_not_exists "no .craft/.gate" "$R/.craft/.gate"
assert_file_not_exists "no .global-state" "$R/.craft/.global-state"
echo ""

begin_test "open with project.md and no .global-state opens the gate and creates no .global-state"
R=$(mktemp -d); TMP_DIRS="$TMP_DIRS $R"; R=$(cd "$R" && pwd -P)
mkdir -p "$R/.craft"
echo "# Project" > "$R/.craft/project.md"
g open docs
assert_eq "prints opened docs" "opened docs" "$OUT"
assert_eq "gate file holds docs" "docs" "$(lines)"
assert_file_not_exists "no .global-state created" "$R/.craft/.global-state"
echo ""

begin_test "open then close in a never-inited folder leaves a source edit allowed by the real write hook before, during and after"
R=$(mktemp -d); TMP_DIRS="$TMP_DIRS $R"; R=$(cd "$R" && pwd -P)
mkdir -p "$R/.craft/mockups/x"
echo "a{}" > "$R/app.css"
JSON="{\"tool_name\":\"Edit\",\"session_id\":\"$ID\",\"tool_input\":{\"file_path\":\"$R/app.css\",\"old_string\":\"a\",\"new_string\":\"b\"},\"cwd\":\"$R\"}"
hook() { (cd "$R" && echo "$JSON" | env -u CRAFT_PROJECT_ROOT python3 "$SCRIPTS_DIR/check-write-permission.py"); }
assert_not_contains "edit allowed before" "deny" "$(hook)"
g open adhoc
assert_not_contains "edit allowed during" "deny" "$(hook)"
g close adhoc
assert_not_contains "edit allowed after" "deny" "$(hook)"
assert_file_not_exists "no .global-state" "$R/.craft/.global-state"
echo ""

begin_test "the first open seeds .craft/.gate/.gitignore holding *; a later open leaves a changed .gitignore as it is"
newproj
g open docs
assert_eq ".gitignore holds *" "*" "$(cat "$R/.craft/.gate/.gitignore")"
echo "custom" > "$R/.craft/.gate/.gitignore"
g open reflect
g close reflect
g open docs
assert_eq "changed .gitignore untouched" "custom" "$(cat "$R/.craft/.gate/.gitignore")"
echo ""

begin_test "CRAFT_PROJECT_ROOT naming a monorepo sub-project puts the file under it; --root wins over CRAFT_PROJECT_ROOT"
newproj
TOP="$R"
SUB="$TOP/packages/a"
mkdir -p "$SUB/.craft"
echo "# Project" > "$SUB/.craft/project.md"
(cd "$TOP" && git init -q . >/dev/null 2>&1)
OUT=$(cd "$TOP" && env CRAFT_PROJECT_ROOT="$SUB" CLAUDE_CODE_SESSION_ID="$ID" bash "$WG" open docs 2>"$ERR_FILE")
RC=$?
assert_exit_code "exit 0" "0" "$RC"
assert_eq "prints opened docs" "opened docs" "$OUT"
assert_file_exists "file under the sub-project" "$SUB/.craft/.gate/$ID"
assert_file_not_exists "nothing under the git top level" "$TOP/.craft/.gate/$ID"
OUT=$(cd "$SUB" && env CRAFT_PROJECT_ROOT="$SUB" CLAUDE_CODE_SESSION_ID="$ID" bash "$WG" --root "$TOP" open reflect 2>"$ERR_FILE")
assert_file_exists "--root wins: file under the top level" "$TOP/.craft/.gate/$ID"
assert_eq "top level file holds reflect" "reflect" "$(cat "$TOP/.craft/.gate/$ID")"
assert_eq "sub-project file unchanged" "docs" "$(cat "$SUB/.craft/.gate/$ID")"
echo ""

begin_test "a relative story path run from another folder gives the same canonical line as the absolute path"
newproj
S=$(mkstory s1)
OTHER=$(mktemp -d); TMP_DIRS="$TMP_DIRS $OTHER"
OUT=$(cd "$OTHER" && env -u CRAFT_PROJECT_ROOT CLAUDE_CODE_SESSION_ID="$ID" bash "$WG" --root "$R" open story ".craft/cycles/1-c/stories/s1.md" 2>"$ERR_FILE")
assert_eq "relative path resolves against the root" "opened $S" "$OUT"
LINK=$(mktemp -d); TMP_DIRS="$TMP_DIRS $LINK"
ln -s "$R/.craft/cycles/1-c/stories" "$LINK/st"
g close story "$S"
g open story "$LINK/st/s1.md"
assert_eq "a path through a symlinked folder is canonical" "$S" "$(lines)"
echo ""

begin_test "open adhoc then open adhoc <record> rewrites the line to adhoc <canonical record path>"
newproj
mkdir -p "$R/.craft/fixes"
echo "# fix" > "$R/.craft/fixes/f1.md"
g open adhoc
assert_eq "bare adhoc" "adhoc" "$(lines)"
g open adhoc ".craft/fixes/f1.md"
assert_eq "prints opened" "opened adhoc $R/.craft/fixes/f1.md" "$OUT"
assert_eq "adhoc with record" "adhoc $R/.craft/fixes/f1.md" "$(lines)"
echo ""

begin_test "open story over workflow, adhoc <record> or docs keeps the replaced holder on line 2"
newproj
S=$(mkstory s1); W=$(mkwf w1)
g open workflow "$W"
g open story "$S"
assert_eq "prints opened story" "opened $S" "$OUT"
assert_eq "story over workflow" "$S / workflow $W" "$(lines)"
g close story "$S"; g close workflow "$W"
echo "# fix" > "$R/f.md"
g open adhoc "$R/f.md"
g open story "$S"
assert_eq "story over adhoc record" "$S / adhoc $R/f.md" "$(lines)"
g close story "$S"; g close adhoc
g open docs
g open story "$S"
assert_eq "story over docs" "$S / docs" "$(lines)"
echo ""

begin_test "open story S2 over S1 / workflow keeps the workflow; open story S over S alone stays one line; open story S over S / workflow keeps line 2"
newproj
S1=$(mkstory s1); S2=$(mkstory s2); W=$(mkwf w1)
g open workflow "$W"; g open story "$S1"
g open story "$S2"
assert_eq "S2 over S1 / workflow" "$S2 / workflow $W" "$(lines)"
g close story "$S2"; g close workflow "$W"
g open story "$S1"
g open story "$S1"
assert_eq "S over S alone" "$S1" "$(lines)"
g close story "$S1"
g open workflow "$W"; g open story "$S1"; g open story "$S1"
assert_eq "S over S / workflow keeps line 2" "$S1 / workflow $W" "$(lines)"
echo ""

begin_test "open docs over a story, alone or over a second line, prints held <story> and leaves the file byte-identical"
newproj
S=$(mkstory s1); W=$(mkwf w1)
g open story "$S"
snap
g open docs
assert_eq "held over a story alone" "held $S" "$OUT"
assert_eq "byte-identical (alone)" "same" "$(same_as_snap)"
g close story "$S"
g open workflow "$W"; g open story "$S"
snap
g open docs
assert_eq "held over a second line" "held $S" "$OUT"
assert_eq "byte-identical (second line)" "same" "$(same_as_snap)"
echo ""

begin_test "open adhoc <record> over S / adhoc rewrites line 2; open workflow W2 over S / adhoc leaves the file byte-identical"
newproj
S=$(mkstory s1); W2=$(mkwf w2)
echo "# fix" > "$R/f.md"
g open adhoc; g open story "$S"
g open adhoc "$R/f.md"
assert_eq "prints held <S>" "held $S" "$OUT"
assert_eq "line 2 is the record" "$S / adhoc $R/f.md" "$(lines)"
g close story "$S"; g close adhoc
g open adhoc; g open story "$S"
snap
g open workflow "$W2"
assert_eq "workflow over S / adhoc is held" "held $S" "$OUT"
assert_eq "byte-identical" "same" "$(same_as_snap)"
echo ""

begin_test "open workflow over adhoc replaces it; open docs over workflow is held; open reflect while docs holds the gate is held"
newproj
W=$(mkwf w1)
g open adhoc
g open workflow "$W"
assert_eq "workflow replaces adhoc" "opened workflow $W" "$OUT"
assert_eq "file is the workflow" "workflow $W" "$(lines)"
g open docs
assert_eq "docs over workflow is held" "held workflow $W" "$OUT"
assert_eq "file still the workflow" "workflow $W" "$(lines)"
g close workflow "$W"
g open docs
g open reflect
assert_eq "reflect while docs holds is held" "held docs" "$OUT"
assert_eq "file still docs" "docs" "$(lines)"
g open docs
assert_eq "the same name is reopened" "opened docs" "$OUT"
g close docs
g open reflect
g open adhoc
assert_eq "adhoc over a named flow is held" "held reflect" "$OUT"
echo ""

begin_test "close story over S / workflow leaves exactly workflow <dir> and prints restored; over S alone removes the file and prints closed"
newproj
S=$(mkstory s1); W=$(mkwf w1)
g open workflow "$W"; g open story "$S"
g close story "$S"
assert_eq "prints restored" "restored workflow $W" "$OUT"
assert_eq "exactly one line" "workflow $W" "$(lines)"
assert_eq "one newline" "1" "$(wc -l < "$(gf)" | tr -d ' ')"
g close workflow "$W"
g open story "$S"
g close story "$S"
assert_eq "prints closed" "closed" "$OUT"
assert_file_not_exists "file removed" "$(gf)"
echo ""

begin_test "close workflow over S / workflow leaves exactly S; a later close story removes the file"
newproj
S=$(mkstory s1); W=$(mkwf w1)
g open workflow "$W"; g open story "$S"
g close workflow "$W"
assert_eq "prints closed" "closed" "$OUT"
assert_eq "only the story remains" "$S" "$(lines)"
g close story "$S"
assert_file_not_exists "file removed" "$(gf)"
echo ""

begin_test "close adhoc over S / adhoc <record> drops line 2; close docs over S / workflow prints held and changes nothing; close of another story leaves the file"
newproj
S=$(mkstory s1); S2=$(mkstory s2); W=$(mkwf w1)
echo "# fix" > "$R/f.md"
g open adhoc "$R/f.md"; g open story "$S"
g close adhoc
assert_eq "prints closed" "closed" "$OUT"
assert_eq "only the story remains" "$S" "$(lines)"
g close story "$S"
g open workflow "$W"; g open story "$S"
snap
g close docs
assert_eq "close docs prints held" "held $S" "$OUT"
assert_eq "unchanged" "same" "$(same_as_snap)"
g close story "$S2"
assert_eq "another story prints held" "held $S" "$OUT"
assert_eq "unchanged after another story close" "same" "$(same_as_snap)"
echo ""

begin_test "close adhoc removes both an adhoc and an adhoc <record> line; close with no gate prints not open and exits 0"
newproj
echo "# fix" > "$R/f.md"
g open adhoc
g close adhoc
assert_eq "bare adhoc closed" "closed" "$OUT"
assert_file_not_exists "removed" "$(gf)"
g open adhoc "$R/f.md"
g close adhoc
assert_eq "adhoc record closed" "closed" "$OUT"
assert_file_not_exists "removed" "$(gf)"
g close adhoc
assert_eq "not open" "not open" "$OUT"
assert_exit_code "exit 0" "0" "$RC"
echo ""

begin_test "close with the id unset exits 0, prints the nothing-closed line on stderr, and every file in .craft/.gate stays byte-identical"
newproj
S=$(mkstory s1)
g open story "$S"
run_as other-session --root "$R" open docs
cp -R "$R/.craft/.gate" "$R/.gate-before"
run_as - --root "$R" close story "$S"
assert_exit_code "exit 0" "0" "$RC"
assert_eq "stderr line" "$NOTHING_CLOSED" "$ERR"
assert_eq "gate folder identical" "same" "$(diff -r "$R/.craft/.gate" "$R/.gate-before" >/dev/null 2>&1 && echo same || echo changed)"
run_as "../x" --root "$R" close story "$S"
assert_exit_code "invalid id exit 0" "0" "$RC"
assert_eq "invalid id stderr" "$NOTHING_CLOSED" "$ERR"
echo ""

begin_test "the gate file is never missing during a restore"
newproj
S=$(mkstory s1); W=$(mkwf w1)
g open workflow "$W"
GFILE=$(gf)
BAD="$R/bad.log"
DONE="$R/done.flag"
(
  while [ ! -e "$DONE" ]; do
    L1=$(head -n1 "$GFILE" 2>/dev/null)
    if [ "$L1" != "$S" ] && [ "$L1" != "workflow $W" ]; then
      echo "saw: '$L1'" >> "$BAD"
    fi
  done
) &
READER=$!
I=0
while [ "$I" -lt 200 ]; do
  env -u CRAFT_PROJECT_ROOT CLAUDE_CODE_SESSION_ID="$ID" bash "$WG" --root "$R" open story "$S" >/dev/null 2>&1
  env -u CRAFT_PROJECT_ROOT CLAUDE_CODE_SESSION_ID="$ID" bash "$WG" --root "$R" close story "$S" >/dev/null 2>&1
  I=$((I + 1))
done
touch "$DONE"
wait "$READER"
READER=""
if [ -f "$BAD" ]; then BADN=$(wc -l < "$BAD" | tr -d ' '); else BADN=0; fi
assert_eq "reader never saw a missing or odd first line in 200 cycles" "0" "$BADN"
assert_eq "ends with the workflow held" "workflow $W" "$(lines)"
echo ""

begin_test "a blank gate file: open docs overwrites it, close docs removes it, holder prints nothing; a blank line 2 is never restored; a third line is dropped"
newproj
S=$(mkstory s1); W=$(mkwf w1)
mkdir -p "$R/.craft/.gate"
printf '\n' > "$(gf)"
g holder
assert_eq "holder prints nothing" "" "$OUT"
g open docs
assert_eq "open overwrites" "opened docs" "$OUT"
assert_eq "file is docs" "docs" "$(lines)"
printf '\n' > "$(gf)"
g close docs
assert_eq "close removes a blank file" "closed" "$OUT"
assert_file_not_exists "removed" "$(gf)"
printf '%s\n\n' "$S" > "$(gf)"
g close story "$S"
assert_file_not_exists "blank line 2 is not restored" "$(gf)"
printf '%s\nworkflow %s\nthird line\n' "$S" "$W" > "$(gf)"
g open story "$S"
assert_eq "third line gone after rewrite" "$S / workflow $W" "$(lines)"
echo ""

begin_test "holder prints only line 1 of a two-line file"
newproj
S=$(mkstory s1); W=$(mkwf w1)
g open workflow "$W"; g open story "$S"
g holder
assert_eq "line 1 only" "$S" "$OUT"
assert_exit_code "exit 0" "0" "$RC"
echo ""

begin_test "sessions A and B both open; A closes; B's file is byte-identical"
newproj
run_as sess-a --root "$R" open docs
run_as sess-b --root "$R" open reflect
cp "$(gf sess-b)" "$R/.snap"
run_as sess-a --root "$R" close docs
assert_eq "A closed" "closed" "$OUT"
assert_file_not_exists "A's file gone" "$(gf sess-a)"
assert_eq "B's file untouched" "same" "$(same_as_snap sess-b)"
run_as sess-a --root "$R" close reflect
assert_eq "A cannot close B's holder (not open for A)" "not open" "$OUT"
assert_eq "B still holds" "reflect" "$(lines sess-b)"
echo ""

begin_test "claim story: opened when free, mine when this session names it (even if another does too), other when only another does; ten claims leave one line"
newproj
S=$(mkstory s1); W=$(mkwf w1)
g claim story "$S"
assert_eq "free: opens" "opened $S" "$OUT"
assert_eq "file holds the story" "$S" "$(lines)"
for i in 1 2 3 4 5 6 7 8 9 10; do g claim story "$S"; done
assert_eq "claims in a row say mine" "mine" "$OUT"
assert_eq "still one line" "$S" "$(lines)"
run_as sess-b --root "$R" claim story "$S"
assert_eq "B sees A's claim as other" "other" "$OUT"
assert_file_not_exists "B wrote nothing" "$(gf sess-b)"
printf '%s\n' "$S" > "$(gf sess-b)"
g claim story "$S"
assert_eq "mine even when another names it" "mine" "$OUT"
g close story "$S"
printf 'workflow %s\n%s\n' "$W" "$S" > "$(gf)"
g claim story "$S"
assert_eq "mine via line 2" "mine" "$OUT"
echo ""

begin_test "check story prints mine, other or free for the same cases and writes nothing; .gitignore and dot-prefixed temp files are ignored"
newproj
S=$(mkstory s1)
mkdir -p "$R/.craft/.gate"
g check story "$S"
assert_eq "free" "free" "$OUT"
assert_dir_not_exists "check wrote no .gate content" "$R/.craft/.gate/$ID"
printf '%s\n' "$S" > "$R/.craft/.gate/.gitignore"
printf '%s\n' "$S" > "$R/.craft/.gate/.tmp.abc123"
g check story "$S"
assert_eq "dot files ignored" "free" "$OUT"
printf '%s\n' "$S" > "$(gf sess-b)"
g check story "$S"
assert_eq "other" "other" "$OUT"
printf '%s\n' "$S" > "$(gf)"
g check story "$S"
assert_eq "mine" "mine" "$OUT"
assert_eq "check writes nothing" "$S" "$(lines)"
echo ""

begin_test "claim workflow over this session's S / workflow prints mine; check workflow from session B prints other"
newproj
S=$(mkstory s1); W=$(mkwf w1)
g open workflow "$W"; g open story "$S"
g claim workflow "$W"
assert_eq "mine" "mine" "$OUT"
run_as sess-b --root "$R" check workflow "$W"
assert_eq "other for B" "other" "$OUT"
run_as sess-b --root "$R" claim workflow "$W"
assert_eq "claim other for B" "other" "$OUT"
echo ""

begin_test "check workflow finds the same holder with a trailing slash, without one, or through a symlinked path"
newproj
W=$(mkwf w1)
g open workflow "$W"
run_as sess-b --root "$R" check workflow "$W"
assert_eq "no slash" "other" "$OUT"
run_as sess-b --root "$R" check workflow "$W/"
assert_eq "trailing slash" "other" "$OUT"
LINK=$(mktemp -d); TMP_DIRS="$TMP_DIRS $LINK"
ln -s "$R/.craft/sessions" "$LINK/sess"
run_as sess-b --root "$R" check workflow "$LINK/sess/w1"
assert_eq "symlinked parent" "other" "$OUT"
ln -s "$W" "$LINK/direct"
run_as sess-b --root "$R" check workflow "$LINK/direct"
assert_eq "symlink to the folder itself" "other" "$OUT"
g open workflow "$W/"
assert_eq "open with a trailing slash writes the same line" "workflow $W" "$(lines)"
echo ""

begin_test "preflight: unset id exits 1 and creates nothing; a good id prints nothing, exits 0 and creates nothing"
newproj
run_as - --root "$R" preflight
assert_exit_code "exit 1" "1" "$RC"
assert_eq "not-opened line" "$NOT_OPENED" "$ERR"
assert_dir_not_exists "nothing created" "$R/.craft/.gate"
g preflight
assert_exit_code "good id exit 0" "0" "$RC"
assert_eq "prints nothing" "" "$OUT"
assert_dir_not_exists "still nothing created" "$R/.craft/.gate"
echo ""

begin_test "an unreadable gate file: open, close, claim, check and preflight exit 1 with a write-gate line and change nothing"
if [ "$(id -u)" = "0" ]; then
  echo "  SKIP: running as root, mode 000 does not block reads"
else
  newproj
  S=$(mkstory s1)
  mkdir -p "$R/.craft/.gate"
  printf 'docs\n' > "$(gf)"
  chmod 000 "$(gf)"
  for V in "open docs" "close docs" "claim story $S" "check story $S" "preflight" "holder"; do
    g $V
    assert_exit_code "exit 1 for '$V'" "1" "$RC"
    assert_contains "write-gate line for '$V'" "^write-gate: " "$ERR"
  done
  chmod 600 "$(gf)"
  assert_eq "file unchanged" "docs" "$(lines)"
fi
echo ""

begin_test "a story path with spaces and unicode goes in unchanged; a path holding a newline is refused with exit 1"
newproj
SP="$R/.craft/cycles/1-c/stories/my stor\xc3\xa9 \xe2\x9c\x93.md"
SP=$(printf "$SP")
printf 'x\n' > "$SP"
g open story "$SP"
assert_exit_code "exit 0" "0" "$RC"
assert_eq "line unchanged" "$SP" "$(lines)"
g close story "$SP"
NL="$R/.craft/cycles/1-c/stories/a
b.md"
g open story "$NL"
assert_exit_code "newline in story path exit 1" "1" "$RC"
assert_contains "write-gate line" "^write-gate: " "$ERR"
g open adhoc "$NL"
assert_exit_code "newline in record path exit 1" "1" "$RC"
assert_file_not_exists "nothing written" "$(gf)"
echo ""

begin_test "open story on a missing file exits 1 and writes nothing; .craft/.gate existing as a plain file makes open and preflight exit 1"
newproj
g open story "$R/.craft/cycles/1-c/stories/none.md"
assert_exit_code "exit 1" "1" "$RC"
assert_contains "write-gate line" "^write-gate: " "$ERR"
assert_dir_not_exists "no gate folder" "$R/.craft/.gate"
printf 'oops\n' > "$R/.craft/.gate"
g open docs
assert_exit_code "open exit 1" "1" "$RC"
assert_contains "open write-gate line" "^write-gate: " "$ERR"
g preflight
assert_exit_code "preflight exit 1" "1" "$RC"
assert_eq ".gate still the plain file" "oops" "$(cat "$R/.craft/.gate")"
echo ""

begin_test "unknown verbs and unknown holders exit 1 with a write-gate line and change nothing"
newproj
g frobnicate
assert_exit_code "unknown verb" "1" "$RC"
assert_contains "verb message" "^write-gate: " "$ERR"
g open frobnicate
assert_exit_code "unknown holder" "1" "$RC"
assert_contains "holder message" "^write-gate: " "$ERR"
g open story
assert_exit_code "story with no path" "1" "$RC"
assert_dir_not_exists "nothing created" "$R/.craft/.gate"
echo ""

begin_test "ten parallel opens from one session leave whole lines from the ten holders and no dot-prefixed temp files"
newproj
W=$(mkwf w1)
STORIES=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  STORIES="$STORIES $(mkstory "p$i")"
done
g open workflow "$W"
for S in $STORIES; do
  env -u CRAFT_PROJECT_ROOT CLAUDE_CODE_SESSION_ID="$ID" bash "$WG" --root "$R" open story "$S" >/dev/null 2>&1 &
done
wait
L1=$(head -n1 "$(gf)")
IN_SET=no
for S in $STORIES; do [ "$S" = "$L1" ] && IN_SET=yes; done
assert_eq "line 1 is one of the ten stories" "yes" "$IN_SET"
assert_eq "line 2 is the workflow" "workflow $W" "$(sed -n 2p "$(gf)")"
assert_eq "exactly two lines" "2" "$(wc -l < "$(gf)" | tr -d ' ')"
LEFT=0
for f in "$R/.craft/.gate"/.tmp*; do [ -e "$f" ] && LEFT=$((LEFT + 1)); done
assert_eq "no temp files left" "0" "$LEFT"
echo ""

begin_test "with --root, the script runs under a PATH holding only the stub tools (no python3, no git)"
newproj
S=$(mkstory s1); W=$(mkwf w1)
STUB=$(mktemp -d); TMP_DIRS="$TMP_DIRS $STUB"
for tool in bash sh dirname basename mkdir printf date find rm cp mv cat grep sed ls touch awk head tail sort uniq wc tr mktemp env chmod ln; do
  src=$(command -v "$tool" 2>/dev/null) || continue
  ln -s "$src" "$STUB/$tool" 2>/dev/null || true
done
stub() { OUT=$(env -i PATH="$STUB" CLAUDE_CODE_SESSION_ID="$ID" "$STUB/bash" "$WG" --root "$R" "$@" 2>"$ERR_FILE"); RC=$?; ERR=$(cat "$ERR_FILE"); }
stub open workflow "$W"
assert_exit_code "open exit 0" "0" "$RC"
stub open story "$S"
assert_eq "open story" "opened $S" "$OUT"
stub claim story "$S"
assert_eq "claim" "mine" "$OUT"
stub close story "$S"
assert_eq "restore" "restored workflow $W" "$OUT"
stub preflight
assert_exit_code "preflight exit 0" "0" "$RC"
stub close workflow "$W"
assert_eq "close" "closed" "$OUT"
assert_eq "no stderr" "" "$ERR"
echo ""

finish_tests
