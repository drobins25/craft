#!/bin/bash
# test-go-brief.sh - Tests for go-brief.py
# Validates the prompts verdict (last phrase wins), the brief lines, both modes
# (a Go file, a tracker cycle directory) and the record create-cycle.sh writes.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/minimal.sh"

BRIEF="$SCRIPTS_DIR/go-brief.py"
RESOLVER="$SCRIPTS_DIR/resolve-go.py"
CREATE_CYCLE_SCRIPT="$SCRIPTS_DIR/create-cycle.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; cleanup_test_dir' EXIT

ANSWER='Workflow prompts: answer them yourself.'
BRING='Workflow prompts: bring them to me.'
AUTONOMY="I'll answer Craft's own prompts and stop only for product forks."

# brief <path> -> stdout in $OUT, exit code in $CODE
brief() {
  set +e
  OUT=$(python3 "$BRIEF" "$@" 2>"$WORK/stderr")
  CODE=$?
  set -e
}

# field <name> -> value of a key=value line in $OUT
field() {
  printf '%s\n' "$OUT" | sed -n "s/^$1=//p"
}

# write_go <file> <stage> <rules-line> <extra lines...> - a Go body, LF endings
write_go() {
  local file="$1" stage="$2" rules="$3"
  shift 3
  {
    printf '## Go - %s (Wright, May 20, 2026)\n\n' "$stage"
    printf 'Stage: %s\nScope: Ship the settings page\nQuestions: none\n' "$stage"
    printf '%s\n' "$rules"
    for line in "$@"; do printf '%s\n' "$line"; done
  } > "$file"
}

RULES_UPDATED='Run rules: last updated May 14, 2026 (from your Team run rules)'

echo "=== test-go-brief.sh ==="
echo ""

begin_test "story 3 landed as planned"
for f in hooks/scripts/resolve-go.py hooks/scripts/cycle-stage.sh commands/references/tracker-intake.md; do
  assert_file_exists "$f" "$PLUGIN_ROOT/$f"
done
assert_file_contains "intake has ## Stage" "^## Stage" "$PLUGIN_ROOT/commands/references/tracker-intake.md"
assert_file_contains "intake has ## Copy" "^## Copy" "$PLUGIN_ROOT/commands/references/tracker-intake.md"
TEST_DIR=$(create_minimal_craft)
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" auth "Auth" "Login" "$TEST_DIR" "planning/a.md" DRO-21 build "O'Neil" "2026-10-31T18:40:00.000Z" >/dev/null 2>&1
YAML="$TEST_DIR/.craft/cycles/1-auth/cycle.yaml"
assert_eq "record lines follow source_concept" \
  "source_concept source_issue authorized_stage go_author go_date" \
  "$(grep -A4 '^source_concept:' "$YAML" | sed 's/:.*//' | tr '\n' ' ' | sed 's/ $//')"
assert_file_contains "author is single-quoted with '' doubling" "^go_author: 'O''Neil'$" "$YAML"
cleanup_test_dir; echo ""

begin_test "answer only"
write_go "$WORK/go.md" build "$RULES_UPDATED" "$ANSWER"
brief "$WORK/go.md"
assert_eq "exits 0" "0" "$CODE"
assert_eq "five keys in order" "prompts scope_line rules_line questions_line answer_line" \
  "$(printf '%s\n' "$OUT" | sed 's/=.*//' | tr '\n' ' ' | sed 's/ $//')"
assert_eq "prompts" "answer" "$(field prompts)"
assert_eq "answer_line verbatim" "$AUTONOMY" "$(field answer_line)"
assert_eq "questions_line" "Questions go to: here" "$(field questions_line)"
echo ""

begin_test "bring only"
write_go "$WORK/go.md" build "$RULES_UPDATED" "$BRING"
brief "$WORK/go.md"
assert_eq "prompts" "bring" "$(field prompts)"
assert_eq "answer_line empty" "" "$(field answer_line)"
echo ""

begin_test "last occurrence wins"
write_go "$WORK/go.md" build "$RULES_UPDATED" "$ANSWER" "For this Go: $BRING"
brief "$WORK/go.md"
assert_eq "answer then bring is bring" "bring" "$(field prompts)"
write_go "$WORK/go.md" build "$RULES_UPDATED" "$BRING" "For this Go: $ANSWER"
brief "$WORK/go.md"
assert_eq "bring then answer is answer" "answer" "$(field prompts)"
write_go "$WORK/go.md" build "$RULES_UPDATED" "Note: $ANSWER and then $BRING mid-line"
brief "$WORK/go.md"
assert_eq "found mid-line, last decides" "bring" "$(field prompts)"
echo ""

begin_test "neither phrase"
write_go "$WORK/go.md" build "$RULES_UPDATED" "Workflow prompts: maybe."
brief "$WORK/go.md"
assert_eq "exits 0" "0" "$CODE"
assert_eq "prompts none" "none" "$(field prompts)"
assert_eq "answer_line empty" "" "$(field answer_line)"
echo ""

begin_test "hold Go"
{ printf '## Go - hold (Wright, May 20, 2026)\n\nStage: hold\nQuestions: none\n%s\n' "$ANSWER"; } > "$WORK/go.md"
brief "$WORK/go.md"
assert_eq "exits 0" "0" "$CODE"
assert_eq "prompts none" "none" "$(field prompts)"
assert_eq "four empty values" "scope_line= rules_line= questions_line= answer_line=" \
  "$(printf '%s\n' "$OUT" | tail -4 | tr '\n' ' ' | sed 's/ $//')"
printf 'Scope: x\n%s\n' "$ANSWER" > "$WORK/go.md"
brief "$WORK/go.md"
assert_eq "text without the Go heading is none" "none" "$(field prompts)"
printf '\n\n## Go - build (Wright, May 20, 2026)\nScope: x\n%s\n' "$ANSWER" > "$WORK/go.md"
brief "$WORK/go.md"
assert_eq "leading blank lines tolerated" "answer" "$(field prompts)"
echo ""

begin_test "rules header forms"
write_go "$WORK/go.md" build "$RULES_UPDATED" "$ANSWER"
brief "$WORK/go.md"
assert_eq "last updated rewritten" "Run rules: Team run rules, last updated May 14, 2026" "$(field rules_line)"
write_go "$WORK/go.md" build "Run rules: none saved" "$ANSWER"
brief "$WORK/go.md"
assert_eq "none saved verbatim" "Run rules: none saved" "$(field rules_line)"
write_go "$WORK/go.md" build "Run rules: could not be read" "$BRING"
brief "$WORK/go.md"
assert_eq "could not be read verbatim" "Run rules: could not be read" "$(field rules_line)"
write_go "$WORK/go.md" build "Run rules: something else entirely" "$ANSWER"
brief "$WORK/go.md"
assert_eq "other text verbatim" "Run rules: something else entirely" "$(field rules_line)"
{ printf '## Go - build (Wright, May 20, 2026)\nScope: x\n%s\n' "$ANSWER"; } > "$WORK/go.md"
brief "$WORK/go.md"
assert_eq "no block" "Run rules: none in this Go" "$(field rules_line)"
echo ""

begin_test "scope line"
write_go "$WORK/go.md" build "$RULES_UPDATED" "$ANSWER"
brief "$WORK/go.md"
assert_eq "verbatim" "Scope: Ship the settings page" "$(field scope_line)"
{ printf '## Go - build (Wright, May 20, 2026)\nScope: narrowed   \t\n%s\n' "$ANSWER"; } > "$WORK/go.md"
brief "$WORK/go.md"
assert_eq "trailing whitespace stripped" "Scope: narrowed" "$(field scope_line)"
{ printf '## Go - build (Wright, May 20, 2026)\nScope:\n%s\n' "$ANSWER"; } > "$WORK/go.md"
brief "$WORK/go.md"
assert_eq "empty scope does not match" "" "$(field scope_line)"
{ printf '## Go - build (Wright, May 20, 2026)\n%s\n' "$ANSWER"; } > "$WORK/go.md"
brief "$WORK/go.md"
assert_eq "absent is empty" "" "$(field scope_line)"
echo ""

begin_test "CRLF Go"
write_go "$WORK/lf.md" build "$RULES_UPDATED" "$ANSWER" "For this Go: $BRING"
sed 's/$/\r/' "$WORK/lf.md" > "$WORK/crlf.md"
brief "$WORK/lf.md"; LF_OUT="$OUT"
brief "$WORK/crlf.md"
assert_eq "same output as LF" "$LF_OUT" "$OUT"
write_go "$WORK/lf.md" plan "$RULES_UPDATED" "$ANSWER"
sed 's/$/\r/' "$WORK/lf.md" > "$WORK/crlf.md"
brief "$WORK/lf.md"; LF_OUT="$OUT"
brief "$WORK/crlf.md"
assert_eq "same output for an answer Go" "$LF_OUT" "$OUT"
echo ""

begin_test "bad args"
brief
assert_eq "zero args exits 1" "1" "$CODE"
assert_eq "zero args stdout empty" "" "$OUT"
assert_contains "zero args names usage" "go-brief" "$(cat "$WORK/stderr")"
brief "$WORK/go.md" "$WORK/go.md"
assert_eq "two args exits 1" "1" "$CODE"
assert_eq "two args stdout empty" "" "$OUT"
brief "$WORK/missing.md"
assert_eq "missing path exits 1" "1" "$CODE"
assert_eq "missing path stdout empty" "" "$OUT"
mkdir -p "$WORK/nocycle"
brief "$WORK/nocycle"
assert_eq "directory without cycle.yaml exits 1" "1" "$CODE"
assert_eq "directory without cycle.yaml stdout empty" "" "$OUT"
printf '\xff\xfe\n' > "$WORK/binary.md"
brief "$WORK/binary.md"
assert_eq "undecodable file exits 1" "1" "$CODE"
assert_eq "undecodable file stdout empty" "" "$OUT"
assert_eq "one stderr line" "1" "$(wc -l < "$WORK/stderr" | tr -d ' ')"
echo ""

# make_cycle <create-cycle args from source-concepts on...> - sets CYCLE
make_cycle() {
  TEST_DIR=$(create_minimal_craft)
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE_SCRIPT" auth "Auth" "Login" "$TEST_DIR" "$@" >/dev/null 2>&1
  CYCLE="$TEST_DIR/.craft/cycles/1-auth"
  mkdir -p "$CYCLE/context"
}

begin_test "dir mode: freeform and no-Go cycles"
make_cycle ""
write_go "$CYCLE/context/dro-21-go-20261031T1840Z.md" build "$RULES_UPDATED" "$ANSWER"
brief "$CYCLE"
assert_eq "freeform exits 0" "0" "$CODE"
assert_eq "freeform none" "none" "$(field prompts)"
cleanup_test_dir
make_cycle "" DRO-21 plan "" ""
write_go "$CYCLE/context/dro-21-go-20261031T1840Z.md" plan "$RULES_UPDATED" "$ANSWER"
brief "$CYCLE"
assert_eq "empty go_author none" "none" "$(field prompts)"
assert_eq "empty go_author leaves brief empty" "scope_line= rules_line= questions_line= answer_line=" \
  "$(printf '%s\n' "$OUT" | tail -4 | tr '\n' ' ' | sed 's/ $//')"
cleanup_test_dir
make_cycle "" DRO-21 build Darin "2026-10-31T18:40:00.000Z"
brief "$CYCLE"
assert_eq "no context go file none" "none" "$(field prompts)"
cleanup_test_dir
make_cycle "" DRO-21 build Darin "2026-10-31T18:40:00.000Z"
write_go "$CYCLE/context/dro-21-go-20261031T1840Z.md" build "$RULES_UPDATED" "$ANSWER"
sed -i.bak "s/^authorized_stage: .*/authorized_stage: 'hold'/" "$CYCLE/cycle.yaml"
brief "$CYCLE"
assert_eq "unknown stage none" "none" "$(field prompts)"
cleanup_test_dir
make_cycle "" DRO-21 build Darin "2026-10-31T18:40:00.000Z"
write_go "$CYCLE/context/other-go-20261031T1840Z.md" build "$RULES_UPDATED" "$ANSWER"
brief "$CYCLE"
assert_eq "another issue's Go is not read" "none" "$(field prompts)"
cleanup_test_dir; echo ""

begin_test "dir mode: newest copy wins"
make_cycle "" DRO-21 build Darin "2026-10-31T18:40:00.000Z"
write_go "$CYCLE/context/dro-21-go-20261031T1840Z.md" build "$RULES_UPDATED" "$ANSWER"
write_go "$CYCLE/context/dro-21-go-20261102T0900Z.md" build "$RULES_UPDATED" "$BRING"
brief "$CYCLE"
assert_eq "the 20261102 copy beats 20261031" "bring" "$(field prompts)"
cleanup_test_dir
make_cycle "" DRO-21 build Darin "2026-10-31T18:40:00.000Z"
write_go "$CYCLE/context/dro-21-go-20261031T1840Z.md" build "$RULES_UPDATED" "$BRING"
write_go "$CYCLE/context/dro-21-go-20261102T0900Z.md" build "$RULES_UPDATED" "$ANSWER"
brief "$CYCLE"
assert_eq "and the reverse" "answer" "$(field prompts)"
cleanup_test_dir; echo ""

begin_test "dir mode reads the record create-cycle writes"
make_cycle "" "DRO-21" build "O'Neil" "2026-10-31T18:40:00.000Z"
cat > "$WORK/comments.md" <<'COMMENTS'
# DRO-21 comments, oldest first

## Comment 1 - Wright - 2026-10-31T18:40:00.000Z

## Go - build (Wright, October 31, 2026)

Stage: build
Scope: Ship the settings page
Questions: none
Run rules: last updated May 14, 2026 (from your Team run rules)
Workflow prompts: answer them yourself.
COMMENTS
python3 "$RESOLVER" "$WORK/comments.md" DRO-21 "$WORK/resolved-go.md" >/dev/null
mv "$WORK/resolved-go.md" "$CYCLE/context/dro-21-go-20261031T1840Z.md"
brief "$CYCLE"
assert_eq "exits 0" "0" "$CODE"
assert_eq "prompts answer" "answer" "$(field prompts)"
assert_eq "scope read from the resolver's body" "Scope: Ship the settings page" "$(field scope_line)"
assert_eq "rules rewritten" "Run rules: Team run rules, last updated May 14, 2026" "$(field rules_line)"
cleanup_test_dir
make_cycle "" "DRO/21 x" build Darin "2026-10-31T18:40:00.000Z"
write_go "$CYCLE/context/dro-21-x-go-20261031T1840Z.md" build "$RULES_UPDATED" "$ANSWER"
brief "$CYCLE"
assert_eq "slug collapses non-alphanumeric runs" "answer" "$(field prompts)"
cleanup_test_dir; echo ""

begin_test "questions go to the issue only when the Go says so"
ISSUE_LINE='Questions and decisions: comments on this issue'
write_go "$WORK/go.md" build "$RULES_UPDATED" "$ISSUE_LINE" "$ANSWER"
brief "$WORK/go.md"
assert_eq "issue line gives the issue" "Questions go to: the issue" "$(field questions_line)"
assert_eq "still five lines" "5" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
write_go "$WORK/go.md" build "$RULES_UPDATED" "$ISSUE_LINE.   " "$ANSWER"
brief "$WORK/go.md"
assert_eq "trailing dot and spaces tolerated" "Questions go to: the issue" "$(field questions_line)"
write_go "$WORK/go.md" build "$RULES_UPDATED" "Questions and decisions: in Slack" "$ANSWER"
brief "$WORK/go.md"
assert_eq "elsewhere stays here" "Questions go to: here" "$(field questions_line)"
assert_eq "still five lines" "5" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
write_go "$WORK/go.md" build "$RULES_UPDATED" "Questions and decisions: comments on this issue, and Slack" "$ANSWER"
brief "$WORK/go.md"
assert_eq "a longer line is not the permission" "Questions go to: here" "$(field questions_line)"
write_go "$WORK/go.md" build "$RULES_UPDATED" "I note: Questions and decisions: comments on this issue" "$ANSWER"
brief "$WORK/go.md"
assert_eq "must be the whole line" "Questions go to: here" "$(field questions_line)"
{ printf '## Go - hold (Wright, May 20, 2026)\n\nStage: hold\n%s\n%s\n' "$ISSUE_LINE" "$ANSWER"; } > "$WORK/go.md"
brief "$WORK/go.md"
assert_eq "hold stays empty" "" "$(field questions_line)"
brief "$WORK/missing-nothing.md"
assert_eq "an unreadable path still exits 1" "1" "$CODE"
echo ""

finish_tests
