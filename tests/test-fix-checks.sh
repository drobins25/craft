#!/bin/bash
# test-fix-checks.sh - Evals for hooks/scripts/fix-checks.sh, the checks the
# adhoc fix hand-off runs on a fix before it is committed.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

FIX_CHECKS="$SCRIPT_DIR/../hooks/scripts/fix-checks.sh"

echo "=== test-fix-checks.sh ==="
echo ""

# A repo with one commit, plus the user's own uncommitted work on top.
make_repo() {
  TEST_DIR=$(mktemp -d)
  (
    cd "$TEST_DIR"
    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    mkdir -p src
    echo "one" > src/keep.txt
    echo "two" > src/dirty.txt
    echo "three" > src/gone.txt
    echo "four" > src/data.py
    echo "ignored-out/" > .gitignore
    git add -A
    git commit -qm "init"
    # the user's own uncommitted work, present before any fix starts
    echo "user edit" >> src/dirty.txt
    echo "user note" > scratch-note.txt
  )
  mkdir -p "$TEST_DIR/.craft/fixes"
  REC="$TEST_DIR/.craft/fixes/record.md"
}

# A record with a Files list and nothing else to trip on.
write_record() {
  cat > "$REC" <<EOF
---
name: test-fix
status: ${STATUS_LINE:-validated}
---
## Solution
**Change:** the fix
**Files:**
$1
**Seen by others:**
$2
**Left alone:** nothing
**Run:**
- bash tests/run.sh

## Mechanism
**Same construct elsewhere:** $3
EOF
}

# --- snapshot and changed ---

begin_test "a tree nobody touched since the snapshot lists nothing"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
OUT=$(bash "$FIX_CHECKS" changed "$TEST_DIR" "$SNAP")
assert_eq "no paths, although the tree holds uncommitted work" "" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "lists what changed since the snapshot and leaves the user's earlier work out"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
(
  cd "$TEST_DIR"
  echo "fix" >> src/keep.txt                     # a clean tracked file, edited
  mkdir -p newdir && echo "x" > newdir/file.ts   # a new file in a new folder
  echo "fix too" >> src/dirty.txt                # a file the user had already edited
  rm src/gone.txt                                # a deleted file
  echo "r" > .craft/fixes/record.md
  mkdir -p ignored-out && echo "b" > ignored-out/build.js
)
OUT=$(bash "$FIX_CHECKS" changed "$TEST_DIR" "$SNAP" | sort | tr '\n' ' ')
assert_eq "the four touched paths, by file" "newdir/file.ts src/dirty.txt src/gone.txt src/keep.txt " "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "neither snapshot nor run changes the index or the working tree"
make_repo
write_record "- src/keep.txt - modify" "" "none"
BEFORE=$(cd "$TEST_DIR" && git status --porcelain)
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC" >/dev/null
AFTER=$(cd "$TEST_DIR" && git status --porcelain)
assert_eq "git status reads the same" "$BEFORE" "$AFTER"
assert_eq "nothing staged" "" "$(cd "$TEST_DIR" && git diff --cached --name-only)"
rm -rf "$TEST_DIR"
echo ""

begin_test "a project root below the git root lists paths relative to it"
make_repo
mkdir -p "$TEST_DIR/app/lib"
echo "a" > "$TEST_DIR/app/lib/a.txt"
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR/app")
(
  cd "$TEST_DIR"
  echo "b" >> app/lib/a.txt
  mkdir -p app/.craft/fixes && echo "r" > app/.craft/fixes/record.md
  echo "outside" >> src/keep.txt                 # outside the project root
)
OUT=$(bash "$FIX_CHECKS" changed "$TEST_DIR/app" "$SNAP" | tr '\n' ' ')
assert_eq "only the path inside the project root" "lib/a.txt " "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a repository with no commit yet still snapshots"
TEST_DIR=$(mktemp -d)
(cd "$TEST_DIR" && git init -q . && echo "a" > a.txt)
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
echo "b" > "$TEST_DIR/b.txt"
OUT=$(bash "$FIX_CHECKS" changed "$TEST_DIR" "$SNAP" | tr '\n' ' ')
assert_eq "the file added since" "b.txt " "$OUT"
rm -rf "$TEST_DIR"
echo ""

# --- run: check 3, undeclared paths ---

begin_test "a fix that changed only its declared files finds nothing"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
echo "fix" >> "$TEST_DIR/src/keep.txt"
rm "$TEST_DIR/src/gone.txt"
write_record "- src/keep.txt - modify
- \`src/gone.txt\` - delete" "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_eq "only the closing line" "checks run: 0 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a changed file no Files line names is reported"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
echo "fix" >> "$TEST_DIR/src/keep.txt"
echo "stray" >> "$TEST_DIR/src/dirty.txt"
write_record "- src/keep.txt - modify" "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "names the undeclared file" "3 undeclared path: src/dirty.txt" "$OUT"
assert_contains_literal "counts it" "checks run: 1 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a declared path must stand on its own, not inside a longer name"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
echo "fix" >> "$TEST_DIR/src/data.py"
write_record "- src/metadata.py - modify" "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "data.py inside metadata.py does not count" "3 undeclared path: src/data.py" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a path named outside the Files field does not count as declared"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
echo "fix" >> "$TEST_DIR/src/keep.txt"
echo "fix" >> "$TEST_DIR/src/data.py"
write_record "- src/keep.txt - modify" "" "src/data.py:1 - same call - right"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "named only on the Same construct line" "3 undeclared path: src/data.py" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a Files line may name the path as absolute or with a leading ./"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
echo "fix" >> "$TEST_DIR/src/keep.txt"
echo "fix" >> "$TEST_DIR/src/data.py"
REAL_DIR=$(cd "$TEST_DIR" && pwd -P)
write_record "- $TEST_DIR/src/keep.txt - modify
- ./src/data.py - modify" "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_eq "absolute as given and ./ both count" "checks run: 0 found" "$OUT"
write_record "- $REAL_DIR/src/keep.txt - modify
- \`./src/data.py\` - modify" "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_eq "absolute with symlinks resolved, and ./ in backticks, both count" "checks run: 0 found" "$OUT"
write_record "- /elsewhere/src/keep.txt - modify
- src/data.py - modify" "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "an absolute path in another folder does not count" "3 undeclared path: src/keep.txt" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a declared path must not be read inside a longer name that continues after a dot"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
echo "fix" >> "$TEST_DIR/src/keep.txt"
write_record "- src/keep.txt.bak - modify" "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "keep.txt inside keep.txt.bak does not count" "3 undeclared path: src/keep.txt" "$OUT"
write_record "- src/keep.txt. That is the whole fix." "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_eq "a full stop ending the sentence still counts" "checks run: 0 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a file name with non-ASCII letters is compared as written"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
echo "x" > "$TEST_DIR/src/café.txt"
OUT=$(bash "$FIX_CHECKS" changed "$TEST_DIR" "$SNAP")
assert_eq "printed without octal quoting" "src/café.txt" "$OUT"
write_record "- src/café.txt - create" "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_eq "declared, so nothing found" "checks run: 0 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a working tree git cannot read stops with exit 2, never a silent pass"
if [ "$(id -u)" = "0" ]; then
  echo "  SKIP: running as root, which reads any file"
else
  make_repo
  SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
  write_record "- src/keep.txt - modify" "" "none"
  echo "secret" > "$TEST_DIR/unreadable.txt"
  chmod 000 "$TEST_DIR/unreadable.txt"
  set +e
  bash "$FIX_CHECKS" snapshot "$TEST_DIR" >"$TEST_DIR/out" 2>"$TEST_DIR/err"; CODE=$?
  set -e
  assert_eq "snapshot exits 2" "2" "$CODE"
  assert_eq "snapshot prints no id" "" "$(cat "$TEST_DIR/out")"
  assert_contains_literal "says why" "could not read the working tree" "$(cat "$TEST_DIR/err")"
  set +e
  bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC" >"$TEST_DIR/out" 2>"$TEST_DIR/err"; CODE=$?
  set -e
  assert_eq "run exits 2" "2" "$CODE"
  assert_not_contains "run prints no closing line" "checks run:" "$(cat "$TEST_DIR/out")"
  chmod 600 "$TEST_DIR/unreadable.txt"
  rm -rf "$TEST_DIR"
fi
echo ""

# --- run: check 1, undecided readers ---

begin_test "a reader row whose verdict is changed is reported, in every written form"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- src/keep.txt - modify" "- a.sh:1 - today X, after Y - changed
- b.sh:2 - today X, after Y -> changed.
- c.sh:3 - today X; after Y: CHANGED
- d.sh:4 - today X, after Y - changed (the list is longer now)
- f.sh:6 - today it shows \"state: same\", after it shows \`state: new\` - changed
- h.sh:8 - today it shows \"decided: yes\", after it shows \"no\" - changed" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "plain verdict" "1 undecided reader: - a.sh:1" "$OUT"
assert_contains_literal "arrow and full stop" "1 undecided reader: - b.sh:2" "$OUT"
assert_contains_literal "colon and capitals" "1 undecided reader: - c.sh:3" "$OUT"
assert_contains_literal "verdict with a note after it" "1 undecided reader: - d.sh:4" "$OUT"
assert_contains_literal "verdict after quoted outputs" "1 undecided reader: - f.sh:6" "$OUT"
assert_contains_literal "decided: inside a quoted output is not a decision" "1 undecided reader: - h.sh:8" "$OUT"
assert_contains_literal "six found" "checks run: 6 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a decided, same or cured row, and the word inside a sentence, are not reported"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- src/keep.txt - modify" "- a.sh:1 - today X, after Y - changed - decided: option a, keep the new look
- b.sh:2 - today 0 changed lines, after 1 - cured
- c.sh:3 - today X, after X - same
- d.sh:4 - today X, after X - unchanged
- e.sh:5 - today X, after Y - changed
  decided: option b, on the next line
- g.sh:7 - today it shows \"status: changed\", after it shows \`file: changed\` - same" "none"
echo "**Left alone:** the header changed long ago" >> "$REC"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_eq "only the closing line" "checks run: 0 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "an undecided reader next to a decided one is reported, as indented bullets or as prose"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- src/keep.txt - modify" "
  - a.sh:1 - today X, after Y - changed
  - b.sh:2 - today X, after Y - changed - decided: keep" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "indented bullet a" "1 undecided reader:   - a.sh:1" "$OUT"
assert_not_contains "decided bullet b" "b.sh:2" "$OUT"
assert_contains_literal "one found" "checks run: 1 found" "$OUT"
write_record "- src/keep.txt - modify" " src/a.js:3 - today X, after Y - changed. tests/b.test.js:5 parse these lines - same. lib/c.js:7 - today X, after Y - changed - decided: keep." "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "prose reader a" "src/a.js:3" "$OUT"
assert_not_contains "same reader b" "b.test.js" "$OUT"
assert_not_contains "decided reader c" "lib/c.js" "$OUT"
assert_contains_literal "one found in prose" "checks run: 1 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

# --- run: check 2, hits marked wrong ---

begin_test "a hit marked wrong in a file outside Files is reported, however it is written"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- src/keep.txt - modify" "" "x.py:9 returned []: WRONG
y.py:3 - same call - wrong; joins the fix"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "colon and capitals" "2 wrong hit outside Files: x.py in: **Same construct elsewhere:** x.py:9" "$OUT"
assert_contains_literal "a continuation line" "2 wrong hit outside Files: y.py in: y.py:3" "$OUT"
assert_contains_literal "two found" "checks run: 2 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a hit marked wrong whose file is on a Files line was cured and is not reported"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- src/keep.txt - modify
- \`hooks/scripts/tracker_issue.py\` - modify" "" "tracker_issue.py:63-66 issue_type - returned 'Bug' - wrong (joins fix, same file)
src/keep.txt:4 - same call - wrong; joined"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_eq "a bare file name and a full path both match their Files line" "checks run: 0 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a hit names several files: the one outside Files is reported, a bare name must not match inside another name"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- hooks/scripts/create-cycle.sh - modify
- src/metadata.py - modify" "" "create-cycle.sh:147 and templates/cycle.yaml:2 - same placeholders - wrong. data.py:3 - wrong"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "the template is outside Files" "2 wrong hit outside Files: templates/cycle.yaml in:" "$OUT"
assert_contains_literal "data.py is not metadata.py" "2 wrong hit outside Files: data.py in:" "$OUT"
assert_not_contains "create-cycle.sh is on Files" "outside Files: create-cycle.sh" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a wrong hit's whole path is read, brackets and all"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- app/[id]/page.tsx - modify" "" "app/[slug]/page.tsx:5 - ran, returned bad - wrong"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "the other route is outside Files" "2 wrong hit outside Files: app/[slug]/page.tsx in:" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a hit written over two lines is read as one"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- src/keep.txt - modify" "" "other/z.py:9 - ran with input,
  returned bad - wrong"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "the wrong mark on the next line counts" "2 wrong hit outside Files: other/z.py in:" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a right hit sharing a line with a wrong one is not reported"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- src/keep.txt - modify" "" "src/keep.txt:3 - wrong, joined. lib/b.py:7 - run, right."
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_eq "nothing found" "checks run: 0 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a wrong hit the user ruled on is not reported; an unruled one beside it is"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- src/keep.txt - modify" "" "lib/c.py:4 - wrong - decided: leave it for a story. lib/d.py:2 - wrong"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_not_contains "the ruled hit" "lib/c.py in:" "$OUT"
assert_contains_literal "the other hit" "2 wrong hit outside Files: lib/d.py in:" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a wrong hit written with an absolute path matches its Files line"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- src/keep.txt - modify" "" "$TEST_DIR/src/keep.txt:3 - ran - wrong, joined. /elsewhere/x.py:1 - wrong"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_not_contains "the project file is declared" "src/keep.txt in:" "$OUT"
assert_contains_literal "a file outside the project is reported" "2 wrong hit outside Files: /elsewhere/x.py in:" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a changed file whose name holds a backslash is compared as written"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
printf 'x\n' > "$TEST_DIR/we\\ird.txt"
write_record "- we\\ird.txt - create" "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_eq "declared, so nothing found" "checks run: 0 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "with - for the snapshot, check 3 is skipped and checks 1 and 2 still run"
make_repo
write_record "- src/keep.txt - modify" "- a.sh:1 - today X, after Y - changed" "lib/d.py:2 - wrong"
echo "stray" >> "$TEST_DIR/src/dirty.txt"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" - "$REC")
assert_contains_literal "says check 3 was skipped" "note: check 3 skipped, no snapshot" "$OUT"
assert_contains_literal "check 1 ran" "1 undecided reader: - a.sh:1" "$OUT"
assert_contains_literal "check 2 ran" "2 wrong hit outside Files: lib/d.py" "$OUT"
assert_not_contains "no path compared" "3 undeclared path" "$OUT"
assert_contains_literal "two found" "checks run: 2 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a hit marked wrong that names no file:line cannot be checked and is reported"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- src/keep.txt - modify" "" "the cycle-create script writes the title the same way - wrong"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "reported as unchecked" "2 wrong hit names no file:line:" "$OUT"
rm -rf "$TEST_DIR"
echo ""

begin_test "a hit marked right, or the word inside another word, is not reported"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
write_record "- src/keep.txt - modify" "" "x.py:9 - wrongly named but the same input gives the right result - right"
echo "## Confidence Check" >> "$REC"
echo "- the guess was wrong" >> "$REC"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_eq "only the closing line" "checks run: 0 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

# --- run: check 4, record status ---

begin_test "a record whose status is not validated is reported"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
STATUS_LINE="applied" write_record "- src/keep.txt - modify" "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "names the status" "4 status not validated: applied" "$OUT"
assert_contains_literal "counts it" "checks run: 1 found" "$OUT"
printf '## Solution\n**Files:**\n- src/keep.txt - modify\n' > "$REC"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "a record with no status line is reported too" "4 status not validated: none" "$OUT"
STATUS_LINE='"validated"' write_record "- src/keep.txt - modify" "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_eq "a quoted validated counts" "checks run: 0 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

# --- run: check 5, paths staged outside Files ---

begin_test "a path the user staged that no Files line names is reported; the fix's own staged file is not"
make_repo
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
echo "fix" >> "$TEST_DIR/src/keep.txt"
(cd "$TEST_DIR" && git add scratch-note.txt src/keep.txt)
write_record "- src/keep.txt - modify" "" "none"
OUT=$(bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$REC")
assert_contains_literal "the user's staged note" "5 staged outside Files: scratch-note.txt" "$OUT"
assert_not_contains "the fix's file" "5 staged outside Files: src/keep.txt" "$OUT"
assert_contains_literal "one found" "checks run: 1 found" "$OUT"
rm -rf "$TEST_DIR"
echo ""

# --- bad calls ---

begin_test "bad calls exit 2 and say why"
TEST_DIR=$(mktemp -d)
set +e
bash "$FIX_CHECKS" snapshot "$TEST_DIR" >/dev/null 2>"$TEST_DIR/err"; CODE=$?
set -e
assert_eq "a folder outside a git repository exits 2" "2" "$CODE"
assert_contains_literal "names the reason" "not inside a git repository" "$(cat "$TEST_DIR/err")"
(cd "$TEST_DIR" && git init -q .)
set +e
bash "$FIX_CHECKS" changed "$TEST_DIR" "not-a-snapshot" >/dev/null 2>"$TEST_DIR/err"; CODE=$?
set -e
assert_eq "an unknown snapshot id exits 2" "2" "$CODE"
assert_contains_literal "names the reason" "unknown snapshot id" "$(cat "$TEST_DIR/err")"
SNAP=$(bash "$FIX_CHECKS" snapshot "$TEST_DIR")
set +e
bash "$FIX_CHECKS" run "$TEST_DIR" "$SNAP" "$TEST_DIR/no-such-record.md" >/dev/null 2>"$TEST_DIR/err"; CODE=$?
set -e
assert_eq "a missing record exits 2" "2" "$CODE"
assert_contains_literal "names the reason" "no fix record at" "$(cat "$TEST_DIR/err")"
set +e
bash "$FIX_CHECKS" >/dev/null 2>"$TEST_DIR/err"; CODE=$?
set -e
assert_eq "no arguments exits 2" "2" "$CODE"
rm -rf "$TEST_DIR"
echo ""

# --- Summary ---
finish_tests
