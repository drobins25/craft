#!/bin/bash
# test-question-answers.sh - Tests for question-answers.py
# Questions Craft posts on the issue are matched to later comments by heading
# and time, never by author or threading. A Go is never an answer.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

QA="$SCRIPTS_DIR/question-answers.py"
CREATE_CYCLE="$SCRIPTS_DIR/create-cycle.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# project <name> -> a temp project with a DRO-21 cycle; sets CYCLE and CTX
project() {
  local root="$WORK/$1"
  mkdir -p "$root/.craft"
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$CREATE_CYCLE" intake "Intake" "TBD" "$root" "" \
    "DRO-21" "build" "Darin" "2026-10-31T18:40:00.000Z" >/dev/null 2>&1
  CYCLE="$root/.craft/cycles/1-intake"
  CTX="$CYCLE/context"
  mkdir -p "$CTX"
}

# question <n> <topic> <timestamp> - a block in Craft's question format
question() {
  printf '## Comment %s - Darin Drobinski - %s\n\n## Question from Claude - %s\n\n`Which way?`\n\n' "$1" "$3" "$2"
}

# comment <n> <author> <timestamp> <body> - a plain block
comment() {
  printf '## Comment %s - %s - %s\n\n%s\n\n' "$1" "$2" "$3" "$4"
}

# run <args...> -> OUT and CODE
run() {
  set +e
  OUT=$(python3 "$QA" "$@" 2>"$WORK/err")
  CODE=$?
  set -e
}

field() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }

echo "=== test-question-answers.sh ==="
echo ""

begin_test "topic named beats newest"
project named
{
  echo "# DRO-21 comments, oldest first"; echo
  question 1 "Retry limit" "2026-11-01T10:00:00.000Z"
  question 2 "Empty state copy" "2026-11-01T11:00:00.000Z"
} > "$CTX/dro-21-comments-2026-11-01T1200Z.md"
{
  echo "# delta"; echo
  comment 3 "Darin Drobinski" "2026-11-02T09:00:00.000Z" "retry limit: b"
} > "$CTX/dro-21-comments-2026-11-02T1000Z.md"
run "$CYCLE"
assert_eq "exits 0" "0" "$CODE"
assert_eq "two questions" "2" "$(field questions)"
assert_eq "one answered" "1" "$(field answered)"
assert_eq "answered line" 'Answered: Retry limit - "retry limit: b" (Darin Drobinski, Nov 2)' "$(field line | sed -n 1p)"
assert_eq "other stays open" 'Still open: Empty state copy (asked Nov 1)' "$(field line | sed -n 2p)"
echo ""

begin_test "newest unanswered when no topic"
project newest
{
  question 1 "Retry limit" "2026-11-01T10:00:00.000Z"
  question 2 "Empty state copy" "2026-11-01T11:00:00.000Z"
  comment 3 "Darin Drobinski" "2026-11-01T12:00:00.000Z" "go with a"
  comment 4 "Darin Drobinski" "2026-11-01T13:00:00.000Z" "and b for the other"
} > "$CTX/dro-21-comments-2026-11-01T1400Z.md"
run "$CYCLE"
assert_eq "both answered" "2" "$(field answered)"
assert_eq "newest question first answered" \
  'Answered: Empty state copy - "go with a" (Darin Drobinski, Nov 1)' "$(field line | sed -n 2p)"
assert_eq "older question takes the next answer" \
  'Answered: Retry limit - "and b for the other" (Darin Drobinski, Nov 1)' "$(field line | sed -n 1p)"
echo ""

begin_test "Go is never an answer"
project go
{
  question 1 "Retry limit" "2026-11-01T10:00:00.000Z"
  comment 2 "Wright" "2026-11-01T12:00:00.000Z" "## Go - build (Darin, November 1, 2026)

Scope: everything."
} > "$CTX/dro-21-comments-2026-11-01T1300Z.md"
run "$CYCLE"
assert_eq "none answered" "0" "$(field answered)"
assert_eq "question stays open" 'Still open: Retry limit (asked Nov 1)' "$(field line)"
echo ""

begin_test "answers before a question answer nothing"
project early
{
  comment 1 "Darin Drobinski" "2026-11-01T09:00:00.000Z" "retry limit is fine"
  question 2 "Retry limit" "2026-11-01T10:00:00.000Z"
} > "$CTX/dro-21-comments-2026-11-01T1300Z.md"
run "$CYCLE"
assert_eq "none answered" "0" "$(field answered)"
echo ""

begin_test "session answer comment matches by topic"
project session
{
  question 1 "Retry limit" "2026-11-01T10:00:00.000Z"
  question 2 "Empty state copy" "2026-11-01T11:00:00.000Z"
  comment 3 "Darin Drobinski" "2026-11-01T12:00:00.000Z" "Answered in the session (Retry limit): a. Three tries."
} > "$CTX/dro-21-comments-2026-11-01T1300Z.md"
run "$CYCLE"
assert_eq "retry limit answered" \
  'Answered: Retry limit - "Answered in the session (Retry limit): a. Three tries." (Darin Drobinski, Nov 1)' \
  "$(field line | sed -n 1p)"
assert_eq "empty state stays open" 'Still open: Empty state copy (asked Nov 1)' "$(field line | sed -n 2p)"
echo ""

begin_test "first answer reported"
project first
{
  question 1 "Retry limit" "2026-11-01T10:00:00.000Z"
  comment 2 "Darin Drobinski" "2026-11-01T11:00:00.000Z" "retry limit: a"
  comment 3 "Darin Drobinski" "2026-11-01T12:00:00.000Z" "retry limit: actually b"
} > "$CTX/dro-21-comments-2026-11-01T1300Z.md"
run "$CYCLE"
assert_eq "one answered" "1" "$(field answered)"
assert_eq "first answer shown" 'Answered: Retry limit - "retry limit: a" (Darin Drobinski, Nov 1)' "$(field line)"
echo ""

begin_test "excerpt: first line, markers stripped, cut at 80"
project excerpt
LONG="> ## $(printf 'word %.0s' $(seq 1 30))"
{
  question 1 "Retry limit" "2026-11-01T10:00:00.000Z"
  comment 2 "Darin Drobinski" "2026-11-01T11:00:00.000Z" "$LONG

second line"
} > "$CTX/dro-21-comments-2026-11-01T1300Z.md"
run "$CYCLE"
EXPECT_EXCERPT="$(printf 'word %.0s' $(seq 1 30) | sed 's/ $//' | cut -c1-80)..."
assert_eq "excerpt trimmed" "Answered: Retry limit - \"$EXPECT_EXCERPT\" (Darin Drobinski, Nov 1)" "$(field line)"
echo ""

begin_test "--new-in filters to the delta"
project delta
{
  question 1 "Retry limit" "2026-11-01T10:00:00.000Z"
  question 2 "Empty state copy" "2026-11-01T11:00:00.000Z"
  comment 3 "Darin Drobinski" "2026-11-01T12:00:00.000Z" "retry limit: a"
} > "$CTX/dro-21-comments-2026-11-01T1300Z.md"
{
  comment 4 "Darin Drobinski" "2026-11-02T09:00:00.000Z" "empty state copy: b"
} > "$CTX/dro-21-comments-2026-11-02T1000Z.md"
run "$CYCLE" --new-in "$CTX/dro-21-comments-2026-11-02T1000Z.md"
assert_eq "only the delta's answer" 'Answered: Empty state copy - "empty state copy: b" (Darin Drobinski, Nov 2)' "$(field line)"
assert_eq "answered counts printed lines" "1" "$(field answered)"
assert_not_contains "no Still open line" "Still open" "$OUT"
echo ""

begin_test "no questions"
project none
comment 1 "Darin Drobinski" "2026-11-01T09:00:00.000Z" "hello" > "$CTX/dro-21-comments-2026-11-01T1300Z.md"
run "$CYCLE"
assert_eq "output is the two counts" "questions=0
answered=0" "$OUT"
project nocopy
run "$CYCLE"
assert_eq "no comments copy at all" "questions=0
answered=0" "$OUT"
echo ""

begin_test "never writes, errors are one line"
project ro
{ question 1 "Retry limit" "2026-11-01T10:00:00.000Z"; } > "$CTX/dro-21-comments-2026-11-01T1300Z.md"
BEFORE=$(cksum "$CTX"/* "$CYCLE/cycle.yaml")
run "$CYCLE" >/dev/null
assert_eq "checksums unchanged" "$BEFORE" "$(cksum "$CTX"/* "$CYCLE/cycle.yaml")"
run "$WORK/missing"
assert_eq "missing cycle exits 1" "1" "$CODE"
assert_eq "nothing on stdout" "" "$OUT"
run
assert_eq "no args exits 1" "1" "$CODE"
echo ""

finish_tests
