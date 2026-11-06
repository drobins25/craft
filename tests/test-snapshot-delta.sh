#!/bin/bash
# test-snapshot-delta.sh - Tests for snapshot-delta.py
# A refresh must copy only what changed since the last copy: comments created
# after the newest copied one (numbering continues), the issue text only when
# it changed outside its status line. Earlier copies are never touched.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

DELTA="$SCRIPTS_DIR/snapshot-delta.py"
RESOLVER="$SCRIPTS_DIR/resolve-go.py"
CREATE_CYCLE="$SCRIPTS_DIR/create-cycle.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# project <name> -> a temp project with .craft, and one DRO-21 cycle with a two-comment copy
project() {
  local root="$WORK/$1"
  mkdir -p "$root/.craft"
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE" intake "Intake" "TBD" "$root" "" \
    "DRO-21" "build" "Darin" "2026-10-31T18:40:00.000Z" >/dev/null 2>&1
  CYCLE="$root/.craft/cycles/1-intake"
  CTX="$CYCLE/context"
  mkdir -p "$CTX"
  cat > "$CTX/dro-21-comments-2026-10-31T1840Z.md" <<'FIX'
# DRO-21 comments, oldest first

## Comment 1 - Darin Drobinski - 2026-10-31T10:00:00.000Z

First thought.

## Comment 2 - Wright - 2026-10-31T11:00:00.000Z

## Go - build (Darin, October 31, 2026)

Scope: everything.
FIX
  cat > "$CTX/dro-21-issue-2026-10-31T1840Z.md" <<'FIX'
# DRO-21: Hand the story over

Source: https://linear.app/x/issue/DRO-21
Status at retrieval: In Progress (copied for reference; never a permission)

Make the handoff invisible.
FIX
  cat > "$CTX/README.md" <<'FIX'
# DRO-21 context: verbatim tracker snapshot

Source: https://linear.app/x/issue/DRO-21

| File | What | Retrieved | Tool |
|---|---|---|---|
| dro-21-issue-2026-10-31T1840Z.md | Issue title, status and description | 2026-10-31T18:40:12Z | linear |
| dro-21-comments-2026-10-31T1840Z.md | Every comment, oldest first | 2026-10-31T18:40:12Z | linear |
FIX
  STAGED="$WORK/$1-staged"
  mkdir -p "$STAGED"
  cp "$CTX/dro-21-issue-2026-10-31T1840Z.md" "$STAGED/issue.md"
  cat "$CTX/dro-21-comments-2026-10-31T1840Z.md" > "$STAGED/comments.md"
  cat >> "$STAGED/comments.md" <<'FIX'

## Comment 3 - Darin Drobinski - 2026-11-02T09:00:00.000Z

Retry limit: b.
FIX
}

# run <args...> -> stdout in $OUT, exit code in $CODE, stderr in $WORK/stderr
run() {
  set +e
  OUT=$(python3 "$DELTA" "$@" 2>"$WORK/stderr")
  CODE=$?
  set -e
}

field() {
  printf '%s\n' "$OUT" | sed -n "s/^$1=//p"
}

# sums <dir> -> cksum of every file but README, sorted by name
sums() {
  (cd "$1" && for f in $(ls | grep -v '^README.md$'); do cksum "$f"; done)
}

echo "=== test-snapshot-delta.sh ==="
echo ""

begin_test "story 3 seam: create-cycle args and resolve-go output are what refresh reads"
project seam
assert_eq "source_issue line" "1" "$(grep -c "^source_issue: 'DRO-21'$" "$CYCLE/cycle.yaml")"
assert_eq "authorized_stage line" "1" "$(grep -c "^authorized_stage: 'build'$" "$CYCLE/cycle.yaml")"
OUT=$(python3 "$RESOLVER" "$CTX/dro-21-comments-2026-10-31T1840Z.md" DRO-21)
assert_eq "resolver prints six lines" "6" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
assert_eq "resolver found the Go" "found" "$(field go)"

begin_test "only new blocks, numbering continues"
project only
before=$(sums "$CTX")
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "exits 0" "0" "$CODE"
assert_eq "five lines" "5" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
assert_eq "one new comment" "1" "$(field new_comments)"
assert_eq "comments file path" "$CTX/dro-21-comments-2026-11-02T1015Z.md" "$(field comments_file)"
assert_eq "no issue file" "" "$(field issue_file)"
assert_eq "stamp" "2026-11-02T1015Z" "$(field stamp)"
assert_eq "say" "Refreshed DRO-21: 1 new comment since Oct 31." "$(field say)"
NEW="$CTX/dro-21-comments-2026-11-02T1015Z.md"
assert_eq "one block" "1" "$(grep -c '^## Comment ' "$NEW")"
assert_eq "numbered 3" "1" "$(grep -c '^## Comment 3 - Darin Drobinski - 2026-11-02T09:00:00.000Z$' "$NEW")"
assert_eq "preamble" "# DRO-21 comments added since 2026-10-31T1840Z, oldest first" "$(head -1 "$NEW")"
assert_file_contains "body copied" "Retry limit: b." "$NEW"
assert_eq "old blocks not repeated" "0" "$(grep -c 'First thought' "$NEW")"

begin_test "earlier copies untouched"
after_old=$(sums "$CTX" | grep -v '1015Z')
assert_eq "every pre-existing file is byte-identical" "$before" "$after_old"
assert_eq "exactly one file was added" "1" "$(ls "$CTX" | grep -c '1015Z')"

begin_test "README gets one row per written file"
assert_eq "one row added" "5" "$(grep -c '^|' "$CTX/README.md")"
assert_eq "row text" "| dro-21-comments-2026-11-02T1015Z.md | Comments added since 2026-10-31T1840Z: 1 | 2026-11-02T10:15:30Z | linear |" "$(tail -1 "$CTX/README.md")"
assert_eq "old rows intact" "1" "$(grep -c '^| dro-21-issue-2026-10-31T1840Z.md | Issue title, status and description | 2026-10-31T18:40:12Z | linear |$' "$CTX/README.md")"

begin_test "a second refresh continues numbering from the delta and says the delta's date"
cat >> "$STAGED/comments.md" <<'FIX'

## Reply 4 - Wright - 2026-11-03T09:00:00.000Z

Thanks.
FIX
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-11-03T12:00:00Z
assert_eq "one new" "1" "$(field new_comments)"
assert_eq "say names the newest earlier stamp" "Refreshed DRO-21: 1 new comment since Nov 2." "$(field say)"
assert_eq "kind kept, number 4" "1" "$(grep -c '^## Reply 4 - Wright - 2026-11-03T09:00:00.000Z$' "$CTX/dro-21-comments-2026-11-03T1200Z.md")"
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-11-03T12:00:10Z
assert_eq "same fetch again: nothing new" "0" "$(field new_comments)"

begin_test "stamp bumps past same minute"
project bump
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-10-31T18:40:30Z
assert_eq "stamp one minute on" "2026-10-31T1841Z" "$(field stamp)"
assert_file_exists "file written under the bumped stamp" "$CTX/dro-21-comments-2026-10-31T1841Z.md"
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-10-31T18:20:00Z
assert_eq "a clock behind the files still moves forward" "0" "$(field new_comments)"
cat >> "$STAGED/comments.md" <<'FIX'

## Comment 4 - Darin Drobinski - 2026-11-04T09:00:00.000Z

Later.
FIX
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-10-31T18:20:00Z
assert_eq "bumps past the newest stamp, not just one" "2026-10-31T1842Z" "$(field stamp)"
assert_eq "C-collation puts it last" "dro-21-comments-2026-10-31T1842Z.md" "$(LC_ALL=C ls "$CTX" | grep comments | tail -1)"

begin_test "nothing new writes nothing"
project quiet
cp "$STAGED/comments.md" "$STAGED/full.md"
head -n 10 "$STAGED/full.md" > "$STAGED/comments.md"
files_before=$(ls "$CTX")
readme_before=$(cksum "$CTX/README.md")
run "$CYCLE" "$STAGED/comments.md" --issue "$STAGED/issue.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "exits 0" "0" "$CODE"
assert_eq "no comments file" "" "$(field comments_file)"
assert_eq "no new comments" "0" "$(field new_comments)"
assert_eq "no issue file" "" "$(field issue_file)"
assert_eq "no stamp" "" "$(field stamp)"
assert_eq "say" "Refreshed DRO-21: nothing new since Oct 31." "$(field say)"
assert_eq "no files added" "$files_before" "$(ls "$CTX")"
assert_eq "README unchanged" "$readme_before" "$(cksum "$CTX/README.md")"

begin_test "status-only change writes no issue file"
sed 's/^Status at retrieval: .*/Status at retrieval: Done (copied for reference; never a permission)/' "$STAGED/issue.md" > "$STAGED/issue-done.md"
run "$CYCLE" "$STAGED/comments.md" --issue "$STAGED/issue-done.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "issue_file empty" "" "$(field issue_file)"
assert_eq "nothing new" "Refreshed DRO-21: nothing new since Oct 31." "$(field say)"

begin_test "description change writes one"
printf 'Also make it fast.\n' >> "$STAGED/issue-done.md"
run "$CYCLE" "$STAGED/comments.md" --issue "$STAGED/issue-done.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "issue file path" "$CTX/dro-21-issue-2026-11-02T1015Z.md" "$(field issue_file)"
assert_eq "stamp used" "2026-11-02T1015Z" "$(field stamp)"
assert_eq "no comments file" "" "$(field comments_file)"
assert_eq "verbatim copy, status line included" "$(cat "$STAGED/issue-done.md")" "$(cat "$CTX/dro-21-issue-2026-11-02T1015Z.md")"
assert_eq "say" "Refreshed DRO-21: 0 new comments since Oct 31, and the issue text changed." "$(field say)"
assert_eq "README row" "| dro-21-issue-2026-11-02T1015Z.md | Issue text changed since 2026-10-31T1840Z | 2026-11-02T10:15:30Z | linear |" "$(tail -1 "$CTX/README.md")"
run "$CYCLE" "$STAGED/comments.md" --issue "$STAGED/issue-done.md" --tool linear --now 2026-11-02T10:20:00Z
assert_eq "compares against the newest copy, so no repeat" "" "$(field issue_file)"

begin_test "comments and issue together"
project both
printf 'Edited.\n' >> "$STAGED/issue.md"
run "$CYCLE" "$STAGED/comments.md" --issue "$STAGED/issue.md" --tool "linear, get_issue" --now 2026-11-02T10:15:30Z
assert_eq "say" "Refreshed DRO-21: 1 new comment since Oct 31, and the issue text changed." "$(field say)"
assert_eq "two rows" "6" "$(grep -c '^|' "$CTX/README.md")"
assert_eq "tool recorded" "2" "$(grep -c '| linear, get_issue |$' "$CTX/README.md")"

begin_test "paste-sourced cycle: first refresh copies everything"
project paste
rm "$CTX/dro-21-comments-2026-10-31T1840Z.md"
sed -i.bak '/comments-2026/d' "$CTX/README.md"
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "all three copied" "3" "$(field new_comments)"
assert_eq "numbered from 1" "1" "$(grep -c '^## Comment 1 - ' "$CTX/dro-21-comments-2026-11-02T1015Z.md")"
assert_eq "say's date from the issue file's stamp" "Refreshed DRO-21: 3 new comments since Oct 31." "$(field say)"

begin_test "equal or unparseable times are new only when the exact header is not copied"
project edge
cat > "$CTX/dro-21-comments-2026-10-31T1900Z.md" <<'FIX'
# DRO-21 comments added since 2026-10-31T1840Z, oldest first

## Comment 3 - Wright - yesterday

Odd one.
FIX
cat > "$STAGED/comments.md" <<'FIX'
# DRO-21 comments, oldest first

## Comment 1 - Darin Drobinski - 2026-10-31T10:00:00.000Z

First thought.

## Comment 2 - Wright - 2026-10-31T11:00:00.000Z

## Go - build (Darin, October 31, 2026)

## Comment 3 - Wright - yesterday

Odd one.

## Comment 4 - Wright - lastweek

Another odd one.

## Comment 5 - Maria - 2026-10-31T11:00:00.000Z

Same second, new author.
FIX
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "two are new" "2" "$(field new_comments)"
NEW="$CTX/dro-21-comments-2026-11-02T1015Z.md"
assert_eq "unseen unparseable time copied, numbered after the max" "1" "$(grep -c '^## Comment 4 - Wright - lastweek$' "$NEW")"
assert_eq "same-second new author copied" "1" "$(grep -c '^## Comment 5 - Maria - ' "$NEW")"
assert_eq "already-copied odd header skipped" "0" "$(grep -c 'yesterday' "$NEW")"

begin_test "older uncopied comment is not copied"
project older
cat >> "$STAGED/comments.md" <<'FIX'

## Comment 4 - Maria - 2026-10-31T09:30:00.000Z

## Go - ship (Maria, October 31, 2026)

Written before the newest copied comment, never copied.
FIX
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "only the later comment is new" "1" "$(field new_comments)"
assert_eq "older block absent from the delta" "0" "$(grep -c 'Maria' "$CTX/dro-21-comments-2026-11-02T1015Z.md")"

begin_test "bodies keep their own ## lines and the tracker's timestamp verbatim"
project body
cat >> "$STAGED/comments.md" <<'FIX'

## Comment 4 - Wright - 2026-11-05T09:00:00+0100

## Go - plan (Wright, November 5, 2026)

Stage: plan
FIX
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-11-05T12:00:00Z
NEW="$CTX/dro-21-comments-2026-11-05T1200Z.md"
assert_eq "both new blocks present" "2" "$(field new_comments)"
assert_eq "offset timestamp verbatim" "1" "$(grep -c '^## Comment 4 - Wright - 2026-11-05T09:00:00+0100$' "$NEW")"
assert_eq "Go heading stays in the body" "1" "$(grep -c '^## Go - plan (Wright, November 5, 2026)$' "$NEW")"
assert_eq "the resolver reads the delta as a comments file" "found" "$(python3 "$RESOLVER" "$NEW" DRO-21 | sed -n 's/^go=//p')"

begin_test "refuses, writing nothing"
project refuse
mv "$CTX/README.md" "$WORK/README.saved"
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "missing README exits 1" "1" "$CODE"
assert_eq "missing README: empty stdout" "" "$OUT"
assert_eq "missing README: one stderr line" "1" "$(wc -l < "$WORK/stderr" | tr -d ' ')"
assert_eq "missing README: no file created" "2" "$(ls "$CTX" | grep -c 'dro-21-')"
printf '# DRO-21 context\n\nno table here\n' > "$CTX/README.md"
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "README without a table exits 1" "1" "$CODE"
assert_eq "README without a table: no file created" "2" "$(ls "$CTX" | grep -c 'dro-21-')"
cp "$WORK/README.saved" "$CTX/README.md"
run "$CYCLE" "$STAGED/nope.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "unreadable comments file exits 1" "1" "$CODE"
run "$CYCLE" "$STAGED/comments.md" --issue "$STAGED/nope.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "unreadable issue file exits 1" "1" "$CODE"
assert_eq "unreadable issue file: no comments file written either" "2" "$(ls "$CTX" | grep -c 'dro-21-')"
run "$WORK/no-such-cycle" "$STAGED/comments.md" --tool linear
assert_eq "no cycle.yaml exits 1" "1" "$CODE"
run "$CYCLE" "$STAGED/comments.md"
assert_eq "no --tool exits 1" "1" "$CODE"
run
assert_eq "no args exits 1" "1" "$CODE"
sed -i.bak "s/^source_issue: .*/source_issue: ''/" "$CYCLE/cycle.yaml"
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "empty source_issue exits 1" "1" "$CODE"
sed -i.bak '/^source_issue:/d' "$CYCLE/cycle.yaml"
run "$CYCLE" "$STAGED/comments.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "no source_issue exits 1" "1" "$CODE"
assert_eq "still nothing created" "2" "$(ls "$CTX" | grep -c 'dro-21-')"



begin_test "a Type line does not make a change"
project typed
sed '/^Status at retrieval:/a\
Type: Bug' "$STAGED/issue.md" > "$STAGED/issue-typed.md"
assert_eq "fixture really has a Type line" "1" "$(grep -c '^Type: Bug$' "$STAGED/issue-typed.md")"
cp "$CYCLE/cycle.yaml" "$WORK/typed-yaml.before"
head -n 10 "$STAGED/comments.md" > "$STAGED/c-short.md"
run "$CYCLE" "$STAGED/c-short.md" --issue "$STAGED/issue-typed.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "exits 0" "0" "$CODE"
assert_eq "issue_file empty" "" "$(field issue_file)"
assert_eq "say" "Refreshed DRO-21: nothing new since Oct 31." "$(field say)"
cmp "$WORK/typed-yaml.before" "$CYCLE/cycle.yaml" && echo "  cycle.yaml unchanged"

begin_test "a Source-only change is no change"
project sourced
sed 's#^Source: .*#Source: https://linear.app/other/issue/DRO-21#' "$STAGED/issue.md" > "$STAGED/issue-src.md"
head -n 10 "$STAGED/comments.md" > "$STAGED/c-short.md"
cp "$CYCLE/cycle.yaml" "$WORK/sourced-yaml.before"
run "$CYCLE" "$STAGED/c-short.md" --issue "$STAGED/issue-src.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "issue_file empty" "" "$(field issue_file)"
assert_eq "say" "Refreshed DRO-21: nothing new since Oct 31." "$(field say)"
cmp "$WORK/sourced-yaml.before" "$CYCLE/cycle.yaml" && echo "  cycle.yaml unchanged"

begin_test "trailing whitespace and outer blank lines are no change"
project spaced
printf '# DRO-21:   Hand the story over  \r\n\r\nSource: https://linear.app/x/issue/DRO-21\r\nStatus at retrieval: Done\r\n\r\n\r\nMake the handoff invisible.   \r\n\r\n\r\n' > "$STAGED/issue-spaced.md"
head -n 10 "$STAGED/comments.md" > "$STAGED/c-short.md"
cp "$CYCLE/cycle.yaml" "$WORK/spaced-yaml.before"
run "$CYCLE" "$STAGED/c-short.md" --issue "$STAGED/issue-spaced.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "issue_file empty" "" "$(field issue_file)"
cmp "$WORK/spaced-yaml.before" "$CYCLE/cycle.yaml" && echo "  cycle.yaml unchanged"

begin_test "description change records the change"
project recorded
printf 'Also make it fast.\n' >> "$STAGED/issue.md"
head -n 10 "$STAGED/comments.md" > "$STAGED/c-short.md"
cp "$CYCLE/cycle.yaml" "$WORK/recorded-yaml.before"
run "$CYCLE" "$STAGED/c-short.md" --issue "$STAGED/issue.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "issue file written" "$CTX/dro-21-issue-2026-11-02T1015Z.md" "$(field issue_file)"
assert_eq "exactly one record line" "1" "$(grep -c "^issue_changed: '2026-11-02T1015Z'$" "$CYCLE/cycle.yaml")"
assert_eq "record sits right after the last tracker key" "go_date" "$(grep -B1 '^issue_changed:' "$CYCLE/cycle.yaml" | head -1 | sed 's/:.*//')"
assert_eq "only the record line was added" "1" "$(diff "$WORK/recorded-yaml.before" "$CYCLE/cycle.yaml" | grep -c '^[<>]')"
assert_eq "say still names the change" "Refreshed DRO-21: 0 new comments since Oct 31, and the issue text changed." "$(field say)"

begin_test "status-only change still writes nothing"
project statusonly
sed 's/^Status at retrieval: .*/Status at retrieval: Done/' "$STAGED/issue.md" > "$STAGED/issue-done.md"
head -n 10 "$STAGED/comments.md" > "$STAGED/c-short.md"
cp "$CYCLE/cycle.yaml" "$WORK/statusonly-yaml.before"
run "$CYCLE" "$STAGED/c-short.md" --issue "$STAGED/issue-done.md" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "issue_file empty" "" "$(field issue_file)"
cmp "$WORK/statusonly-yaml.before" "$CYCLE/cycle.yaml" && echo "  cycle.yaml unchanged"

begin_test "a changed-back issue clears the record"
project changedback
printf "issue_changed: '2026-11-02T1015Z'\n" >> "$CYCLE/cycle.yaml"
OUT=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPTS_DIR')
import tracker_issue
print('stamp=' + tracker_issue.record_change('$CYCLE'))")
assert_eq "returns empty stamp" "stamp=" "$OUT"
assert_eq "record line gone" "0" "$(grep -c '^issue_changed:' "$CYCLE/cycle.yaml")"

begin_test "marks replace earlier marks and leave other rows"
cat > "$WORK/marks-readme.md" <<'FIX'
# DRO-21 context

<!-- a comment -->

| File | What | Retrieved | Tool |
|---|---|---|---|
| dro-21-issue-2026-10-31T1840Z.md | Issue title, status and description | 2026-10-31T18:40:12Z | linear |
| dro-21-comments-2026-10-31T1840Z.md | Every comment, oldest first | 2026-10-31T18:40:12Z | linear |
| dro-21-go-2026-10-31T1840Z.md | Newest Go: comment 2 | 2026-10-31T18:40:12Z | resolve-go.py |
| dro-21-issue-2026-11-02T1015Z.md | Issue text changed since 2026-10-31T1840Z | 2026-11-02T10:15:30Z | linear |

trailing note
FIX
marks() {
  python3 -c "
import sys
sys.path.insert(0, '$SCRIPTS_DIR')
import tracker_issue
text = open('$1').read()
sys.stdout.write(tracker_issue.mark_rows(text, '$2'))"
}
marks "$WORK/marks-readme.md" dro-21-issue-2026-10-31T1840Z.md > "$WORK/marks-1.md"
assert_eq "first copy current" "1" "$(grep -c '^| dro-21-issue-2026-10-31T1840Z.md | Issue title, status and description (current) |' "$WORK/marks-1.md")"
assert_eq "second copy superseded" "1" "$(grep -c 'Issue text changed since 2026-10-31T1840Z (superseded) |' "$WORK/marks-1.md")"
assert_eq "comments row untouched" "1" "$(grep -c '^| dro-21-comments-2026-10-31T1840Z.md | Every comment, oldest first | ' "$WORK/marks-1.md")"
assert_eq "go row untouched" "1" "$(grep -c '^| dro-21-go-2026-10-31T1840Z.md | Newest Go: comment 2 | ' "$WORK/marks-1.md")"
assert_eq "only issue rows carry a mark" "2" "$(grep -c '(current)\|(superseded)' "$WORK/marks-1.md")"
assert_eq "comment and trailing note kept" "2" "$(grep -c -e '^<!-- a comment -->$' -e '^trailing note$' "$WORK/marks-1.md")"
marks "$WORK/marks-1.md" dro-21-issue-2026-11-02T1015Z.md > "$WORK/marks-2.md"
assert_eq "mark moves, no stacking" "2" "$(grep -c '(current)\|(superseded)' "$WORK/marks-2.md")"
assert_eq "second copy now current" "1" "$(grep -c 'Issue text changed since 2026-10-31T1840Z (current) |' "$WORK/marks-2.md")"
assert_eq "first copy now superseded" "1" "$(grep -c 'Issue title, status and description (superseded) |' "$WORK/marks-2.md")"

echo ""
finish_tests
