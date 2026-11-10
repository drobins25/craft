#!/bin/bash
# test-review-scripts.sh - Behavior tests for review-capture.sh and review-graduate.sh.
#
# Capture owns the record grammar (flags + stdin body); graduate is the only
# thing that edits a record afterward, and only a finding's graduated_to: line
# (plus the dismissed: line on a dismissal).
# Usage: bash tests/test-review-scripts.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

CAPTURE="$SCRIPTS_DIR/review-capture.sh"
GRADUATE="$SCRIPTS_DIR/review-graduate.sh"
TODAY=$(date +%Y-%m-%d)
TMP_ROOTS=()

fresh_root() {
  ROOT=$(mktemp -d)
  TMP_ROOTS+=("$ROOT")
  export CRAFT_PROJECT_ROOT="$ROOT"
}

cleanup_roots() {
  local r
  for r in "${TMP_ROOTS[@]:-}"; do [ -n "$r" ] && rm -rf "$r"; done
  return 0
}
trap cleanup_roots EXIT

# run_capture <body> [flags...] - sets OUT, ERR, RC. Default flags describe a
# branch run; pass flags to append (a repeated flag: the last one wins).
BASE_FLAGS=(--mode=branch --strategy=standard --reviewed=feature-x
  --ref=abc1234..def5678 --focus=correctness,security --files=3 --lines=40
  --reviewer=pr-reviewer-expert --gates=none --craft-version=9.9.9)

run_capture() {
  local body="$1"; shift
  local errf; errf=$(mktemp)
  RC=0
  OUT=$(printf '%s' "$body" | bash "$CAPTURE" "${BASE_FLAGS[@]}" "$@" --stdin 2>"$errf") || RC=$?
  ERR=$(cat "$errf"); rm -f "$errf"
}

# run_capture_only <body> [flags...] - exactly the flags given (no defaults)
run_capture_only() {
  local body="$1"; shift
  local errf; errf=$(mktemp)
  RC=0
  OUT=$(printf '%s' "$body" | bash "$CAPTURE" "$@" --stdin 2>"$errf") || RC=$?
  ERR=$(cat "$errf"); rm -f "$errf"
}

run_graduate() {
  local errf; errf=$(mktemp)
  RC=0
  OUT=$(bash "$GRADUATE" "$@" 2>"$errf") || RC=$?
  ERR=$(cat "$errf"); rm -f "$errf"
}

CLEAN_BODY=$'## Verified\n\n- Checked the auth path handles expired tokens\n\n## Findings\n\nNone.\n'

TWO_BODY=$'## Verified\n\n- Read the migration end to end\n\n## Findings\n\n### 1. (logic): Off by one in the pager\n\n**Symptom.** Last page empty\n**Expected.** Items shown\n**Actual.** Nothing shown\n**Consequences.** Users miss data\n**Reproduce.** Open page 3\n**Evidence.** pager.py:12\n**Fix.**\n\n```diff\n- end = start + size - 1\n+ end = start + size\n```\n\n### 2. (doc-drift): README names the old flag\n\n**Symptom.** README stale\n**Fix.** Update the flag name\n'

# --- capture ---

begin_test "clean run writes outcome clean with Verified and Findings None"
fresh_root
run_capture "$CLEAN_BODY"
assert_eq "exit 0" "0" "$RC"
REC=$(printf '%s\n' "$OUT" | tail -1)
assert_eq "path is under .craft/reviews and date-slugged" "$ROOT/.craft/reviews/$TODAY-branch-feature-x.md" "$REC"
assert_file_exists "record exists" "$REC"
KEYS=$(awk '/^---$/{n++; next} n==1{sub(/:.*/,""); printf "%s ", $0}' "$REC")
assert_eq "key order" "type created captured_at mode strategy reviewed ref focus files lines craft_version reviewer gates findings outcome " "$KEYS"
assert_file_contains "outcome clean" "^outcome: clean$" "$REC"
assert_file_contains "findings 0" "^findings: 0$" "$REC"
assert_file_not_contains "no issues line" "^issues:" "$REC"
assert_file_not_contains "no suggestions line" "^suggestions:" "$REC"
assert_file_not_contains "no patterns line" "^patterns:" "$REC"
assert_file_contains "craft version override" "^craft_version: 9.9.9$" "$REC"
assert_file_contains "created is today" "^created: $TODAY$" "$REC"
assert_file_not_contains "no status key" "^status:" "$REC"
assert_file_not_contains "no verdict key" "^verdict:" "$REC"
assert_file_contains "Verified section kept" "^## Verified$" "$REC"
assert_eq "Findings None." "None." "$(awk '/^## Findings$/{f=1; next} f && NF{print; exit}' "$REC")"

begin_test "findings stamp a blank graduated_to under every heading, doc-drift included"
fresh_root
run_capture "$TWO_BODY"
assert_eq "exit 0" "0" "$RC"
REC=$(printf '%s\n' "$OUT" | tail -1)
assert_eq "line after heading 1 is blank graduated_to" "graduated_to:" "$(grep -A1 '^### 1\. ' "$REC" | tail -1)"
assert_eq "line after the doc-drift heading is blank graduated_to" "graduated_to:" "$(grep -A1 '^### 2\. ' "$REC" | tail -1)"
assert_file_contains "findings 2" "^findings: 2$" "$REC"
assert_file_not_contains "no docs stamp" "^graduated_to: docs" "$REC"
assert_file_contains "outcome findings" "^outcome: findings$" "$REC"

begin_test "finding body is kept verbatim"
fresh_root
run_capture "$TWO_BODY"
REC=$(printf '%s\n' "$OUT" | tail -1)
BODY_OUT=$(awk '/^## Verified$/{f=1} f' "$REC" | grep -v '^graduated_to:')
BODY_IN=$(printf '%s' "$TWO_BODY")
assert_eq "body round-trips apart from stamps" "$BODY_IN" "$BODY_OUT"
assert_file_contains "diff fence kept" '^+ end = start + size$' "$REC"

begin_test "a heading inside a fenced diff is not a finding"
fresh_root
FENCED=$'## Verified\n\n- Read it\n\n## Findings\n\n### 1. (logic): Real one\n\n**Evidence.**\n\n```diff\n### 2. (logic): quoted not real\ngraduated_to: nope\n```\n'
run_capture "$FENCED"
assert_eq "exit 0" "0" "$RC"
REC=$(printf '%s\n' "$OUT" | tail -1)
assert_file_contains "findings 1" "^findings: 1$" "$REC"
assert_eq "one stamped graduated_to line outside the fence" "1" "$(grep -c '^graduated_to:$' "$REC")"

begin_test "a graduated_to line quoted inside a fenced Evidence block does not refuse"
fresh_root
QUOTED=$'## Verified\n\n- Read it\n\n## Findings\n\n### 1. (consistency): Quoted\n\n**Evidence.**\n\n~~~\ngraduated_to: fix-a\n~~~\n'
run_capture "$QUOTED"
assert_eq "exit 0" "0" "$RC"
REC=$(printf '%s\n' "$OUT" | tail -1)
assert_eq "own stamp under heading" "graduated_to:" "$(grep -A1 '^### 1\. ' "$REC" | tail -1)"

begin_test "craft_version comes from plugin.json without the override"
fresh_root
PLUG=$(mktemp -d); TMP_ROOTS+=("$PLUG")
mkdir -p "$PLUG/.claude-plugin"
printf '{\n  "name": "craft",\n  "version": "1.2.3"\n}\n' > "$PLUG/.claude-plugin/plugin.json"
ERRF=$(mktemp)
RC=0
OUT=$(printf '%s' "$CLEAN_BODY" | CLAUDE_PLUGIN_ROOT="$PLUG" bash "$CAPTURE" --mode=branch --strategy=standard \
  --reviewed=feature-x --ref=abc1234..def5678 --focus=logic --files=3 --lines=40 \
  --reviewer=pr-reviewer-expert --gates=none --stdin 2>"$ERRF") || RC=$?
rm -f "$ERRF"
assert_eq "exit 0" "0" "$RC"
assert_file_contains "version read from plugin.json" "^craft_version: 1.2.3$" "$(printf '%s\n' "$OUT" | tail -1)"

begin_test "craft_version falls back to unknown when no plugin.json resolves"
fresh_root
FAKE=$(mktemp -d); TMP_ROOTS+=("$FAKE")
mkdir -p "$FAKE/a/b"
cp "$CAPTURE" "$FAKE/a/b/review-capture.sh"
RC=0
OUT=$(printf '%s' "$CLEAN_BODY" | env -u CLAUDE_PLUGIN_ROOT bash "$FAKE/a/b/review-capture.sh" --mode=branch \
  --strategy=standard --reviewed=feature-x --ref=abc1234..def5678 --focus=logic --files=3 --lines=40 \
  --reviewer=r --gates=none --stdin 2>/dev/null) || RC=$?
assert_eq "exit 0" "0" "$RC"
assert_file_contains "unknown" "^craft_version: unknown$" "$(printf '%s\n' "$OUT" | tail -1)"

begin_test "project mode omits lines and slugs to project"
fresh_root
run_capture_only "$CLEAN_BODY" --mode=project --strategy=maze --reviewed=. --ref=def5678 \
  --focus=consistency --files=12 --reviewer=r --gates=none --craft-version=9.9.9
assert_eq "exit 0" "0" "$RC"
REC=$(printf '%s\n' "$OUT" | tail -1)
assert_eq "file name" "$ROOT/.craft/reviews/$TODAY-project.md" "$REC"
assert_file_not_contains "no lines key" "^lines:" "$REC"
run_capture_only "$CLEAN_BODY" --mode=project --strategy=maze --reviewed=. --ref=def5678 \
  --focus=consistency --files=12 --lines=5 --reviewer=r --gates=none --craft-version=9.9.9
assert_eq "lines with project refuses" "2" "$RC"
assert_contains "names the flag" "invalid lines" "$ERR"

begin_test "same-day second run gets -2"
fresh_root
run_capture "$CLEAN_BODY"
FIRST=$(printf '%s\n' "$OUT" | tail -1)
run_capture "$CLEAN_BODY"
SECOND=$(printf '%s\n' "$OUT" | tail -1)
run_capture "$CLEAN_BODY"
THIRD=$(printf '%s\n' "$OUT" | tail -1)
assert_eq "first" "$ROOT/.craft/reviews/$TODAY-branch-feature-x.md" "$FIRST"
assert_eq "second" "$ROOT/.craft/reviews/$TODAY-branch-feature-x-2.md" "$SECOND"
assert_eq "third" "$ROOT/.craft/reviews/$TODAY-branch-feature-x-3.md" "$THIRD"

begin_test "slug follows the notebook rule and caps at 50"
fresh_root
run_capture "$CLEAN_BODY" --reviewed="Feature/Add The Very Long Branch Name For Slug Capping Test Here"
REC=$(printf '%s\n' "$OUT" | tail -1)
STEM=$(basename "$REC" .md)
SLUG=${STEM#$TODAY-}
assert_eq "slug capped at the last hyphen" "branch-feature-add-the-very-long-branch-name-for" "$SLUG"

begin_test "refuses missing Verified, empty Verified, bad heading, gap in numbering, pre-stamped graduated_to, missing flag"
fresh_root
run_capture $'## Findings\n\nNone.\n'
assert_eq "no Verified rc" "2" "$RC"
assert_contains "no Verified stderr" "^missing required field: Verified$" "$ERR"
run_capture $'## Verified\n\n\n## Findings\n\nNone.\n'
assert_eq "empty Verified rc" "2" "$RC"
assert_contains "empty Verified stderr" "^missing required field: Verified$" "$ERR"
run_capture $'## Verified\n\n- ok\n\n## Findings\n\n### 1. Bug (logic): wrong word\n'
assert_eq "bad heading rc" "2" "$RC"
assert_contains "bad heading stderr" "^invalid finding heading: ### 1. Bug (logic): wrong word$" "$ERR"
run_capture $'## Verified\n\n- ok\n\n## Findings\n\n### 1. Issue (logic): a\n'
assert_eq "old severity heading rc" "2" "$RC"
assert_contains "old severity heading stderr" "^invalid finding heading: ### 1. Issue (logic): a$" "$ERR"
run_capture $'## Verified\n\n- ok\n\n## Findings\n\n### 1. (typo): wrong category\n'
assert_eq "bad category rc" "2" "$RC"
run_capture $'## Verified\n\n- ok\n\n## Findings\n\n### 2. (logic): starts at two\n'
assert_eq "gap rc" "2" "$RC"
assert_contains "gap stderr" "^invalid finding number: 2 (expected 1)$" "$ERR"
run_capture $'## Verified\n\n- ok\n\n## Findings\n\n### 1. (logic): a\n\n### 1. (logic): b\n'
assert_eq "duplicate number rc" "2" "$RC"
run_capture $'## Verified\n\n- ok\n\n## Findings\n\n### 1. (logic): a\ngraduated_to: fix-a\n'
assert_eq "pre-stamped rc" "2" "$RC"
assert_contains "pre-stamped stderr" "^invalid body: graduated_to line (capture stamps it)$" "$ERR"
run_capture $'## Verified\n\n- ok\n'
assert_eq "no Findings section rc" "2" "$RC"
assert_contains "no Findings stderr" "^missing required field: Findings$" "$ERR"
run_capture_only "$CLEAN_BODY" --mode=branch --strategy=standard --ref=a..b --focus=x --files=1 --lines=1 \
  --reviewer=r --gates=none --craft-version=9.9.9
assert_eq "missing reviewed rc" "2" "$RC"
assert_contains "missing reviewed stderr" "^missing required field: reviewed$" "$ERR"
run_capture "$CLEAN_BODY" --mode=bogus
assert_eq "bad mode rc" "2" "$RC"
assert_contains "bad mode stderr" "^invalid mode: bogus$" "$ERR"
run_capture "$CLEAN_BODY" --files=abc
assert_eq "bad files rc" "2" "$RC"
assert_contains "bad files stderr" "^invalid files: abc$" "$ERR"
run_capture_only "$CLEAN_BODY" --mode=branch --strategy=standard --reviewed=x --ref=a..b --focus=x --files=1 \
  --reviewer=r --gates=none --craft-version=9.9.9
assert_eq "branch without lines rc" "2" "$RC"
assert_contains "missing lines stderr" "^missing required field: lines$" "$ERR"
assert_dir_not_exists "no reviews folder after any refusal" "$ROOT/.craft/reviews"
assert_dir_not_exists "no .craft folder either" "$ROOT/.craft"

# --- graduate ---

mk_two_record() {
  fresh_root
  run_capture "$TWO_BODY"
  REC=$(printf '%s\n' "$OUT" | tail -1)
  NAME=$(basename "$REC" .md)
  mkdir -p "$ROOT/.craft/fixes"
  : > "$ROOT/.craft/fixes/fix-a.md"
  : > "$ROOT/.craft/fixes/fix-b.md"
  COPY=$(mktemp); cp "$REC" "$COPY"
}

# Finding 2 is doc-drift (already docs); use a three-finding record when both need blanks.
THREE_BODY=$'## Verified\n\n- Read it\n\n## Findings\n\n### 1. (logic): One\n\n**Fix.** a\n\n### 2. (consistency): Two\n\n**Fix.** b\n\n### 3. (performance): Three\n\n**Fix.** c\n'

mk_three_record() {
  fresh_root
  run_capture "$THREE_BODY"
  REC=$(printf '%s\n' "$OUT" | tail -1)
  NAME=$(basename "$REC" .md)
  mkdir -p "$ROOT/.craft/fixes" "$ROOT/.craft/bugs/closed" "$ROOT/.craft/cycles/c1/stories"
  : > "$ROOT/.craft/fixes/fix-a.md"
  : > "$ROOT/.craft/fixes/fix-b.md"
  COPY=$(mktemp); cp "$REC" "$COPY"
}

begin_test "graduate fills a finding under the old heading on a record already on disk"
fresh_root
mkdir -p "$ROOT/.craft/reviews" "$ROOT/.craft/fixes"
: > "$ROOT/.craft/fixes/fix-a.md"
REC="$ROOT/.craft/reviews/old.md"
printf '%s\n' '---' 'type: review' 'outcome: findings' '---' '' '## Verified' '' '- v' '' '## Findings' '' '### 1. Issue (logic): x' 'graduated_to:' '' 'body' > "$REC"
COPY=$(mktemp); cp "$REC" "$COPY"
run_graduate "$REC" 1 fix-a
assert_eq "exit 0" "0" "$RC"
assert_file_contains "old-heading finding graduated" "^graduated_to: fix-a$" "$REC"
assert_eq "one line changed" "1" "$(diff "$COPY" "$REC" | grep -c '^>')"
rm -f "$COPY"

begin_test "graduate changes exactly one line"
mk_three_record
run_graduate "$REC" 1 fix-a
assert_eq "exit 0" "0" "$RC"
assert_eq "stdout is the record path" "$REC" "$OUT"
L=$(( $(grep -n '^### 1\. ' "$REC" | cut -d: -f1) + 1 ))
D=$(diff "$COPY" "$REC" || true)
assert_eq "diff is one line swapped under heading 1" "${L}c${L}"$'\n< graduated_to:\n---\n> graduated_to: fix-a' "$D"
rm -f "$COPY"

begin_test "graduate a comma list fills each finding"
mk_three_record
run_graduate "$REC" 1,3 fix-b
assert_eq "exit 0" "0" "$RC"
assert_eq "finding 1 filled" "graduated_to: fix-b" "$(grep -A1 '^### 1\. ' "$REC" | tail -1)"
assert_eq "finding 2 untouched" "graduated_to:" "$(grep -A1 '^### 2\. ' "$REC" | tail -1)"
assert_eq "finding 3 filled" "graduated_to: fix-b" "$(grep -A1 '^### 3\. ' "$REC" | tail -1)"
rm -f "$COPY"

begin_test "comma list is all or nothing"
mk_three_record
run_graduate "$REC" 1 fix-a
cp "$REC" "$COPY"
run_graduate "$REC" 2,1 fix-b
assert_eq "refused rc" "2" "$RC"
assert_eq "file byte-identical" "" "$(cmp "$COPY" "$REC" 2>&1 || true)"
rm -f "$COPY"

begin_test "dismissal inserts exactly one line"
mk_three_record
run_graduate "$REC" 2 dismissed --by=reviewer --reason="false alarm"
assert_eq "exit 0" "0" "$RC"
D=$(diff "$COPY" "$REC" || true)
assert_contains "graduated_to swapped" "^> graduated_to: dismissed$" "$D"
assert_contains "dismissed line added" "^> dismissed: reviewer - false alarm$" "$D"
assert_eq "exactly two added lines (graduated_to swapped, dismissed inserted)" "2" "$(printf '%s\n' "$D" | grep -c '^>')"
assert_eq "dismissed line sits right under graduated_to" "dismissed: reviewer - false alarm" "$(grep -A2 '^### 2\. ' "$REC" | tail -1)"
rm -f "$COPY"

begin_test "graduate resolves each destination folder and a bare record name"
mk_three_record
: > "$ROOT/.craft/bugs/b1.md"
: > "$ROOT/.craft/bugs/closed/b2.md"
: > "$ROOT/.craft/backlog.md" 2>/dev/null || true
: > "$ROOT/.craft/cycles/c1/stories/20-my-story.md"
run_graduate "$NAME" 1 b1
assert_eq "bare name, bug folder rc" "0" "$RC"
assert_eq "bare name edits the same file" "graduated_to: b1" "$(grep -A1 '^### 1\. ' "$REC" | tail -1)"
run_graduate "$NAME" 2 my-story
assert_eq "numbered story matched by suffix rc" "0" "$RC"
mkdir -p "$ROOT/.craft/notebook/todos/done"
: > "$ROOT/.craft/notebook/todos/done/t1.md"
run_graduate "$NAME" 3 t1
assert_eq "done todo rc" "0" "$RC"
rm -f "$COPY"

begin_test "graduate refuses already graduated, unknown number, missing artifact, bad dismissal flags"
mk_three_record
run_graduate "$REC" 1 fix-a
cp "$REC" "$COPY"
check_untouched() {
  assert_eq "$1 rc" "2" "$RC"
  assert_eq "$1 file byte-identical" "" "$(cmp "$COPY" "$REC" 2>&1 || true)"
}
run_graduate "$REC" 1 fix-b
check_untouched "already graduated"
assert_contains "names the finding" "^already graduated: 1$" "$ERR"
run_graduate "$REC" 9 fix-b
check_untouched "unknown number"
assert_contains "names the number" "^unknown finding: 9$" "$ERR"
run_graduate "$REC" 2 nope
check_untouched "missing artifact"
assert_contains "names the value" "^no such artifact: nope$" "$ERR"
run_graduate "$REC" 2 'bad value!'
check_untouched "bad value"
assert_contains "invalid value" "^invalid value: bad value!$" "$ERR"
run_graduate "$REC" 2 dismissed
check_untouched "dismissed without by"
assert_contains "by named" "^missing required field: by$" "$ERR"
assert_contains "reason named" "^missing required field: reason$" "$ERR"
run_graduate "$REC" 2 dismissed --by=reviewer
check_untouched "dismissed without reason"
run_graduate "$REC" 2 dismissed --by=robot --reason=x
check_untouched "dismissed with bad by"
assert_contains "bad by named" "^invalid by: robot$" "$ERR"
run_graduate "$REC" 2 dismissed --by=user --reason=$'two\nlines'
check_untouched "multi-line reason"
run_graduate "$REC" 2 fix-b --by=user
check_untouched "by with a non-dismissed value"
run_graduate "$REC" 2 fix-b --reason=x
check_untouched "reason with a non-dismissed value"
run_graduate "$REC" 2 docs
assert_eq "docs literal is accepted" "0" "$RC"
rm -f "$COPY"

begin_test "graduate leaves the trailing newline state alone"
mk_three_record
printf '%s' "$(cat "$REC")" > "$REC"
cp "$REC" "$COPY"
run_graduate "$REC" 1 fix-a
assert_eq "exit 0" "0" "$RC"
assert_eq "last byte unchanged (no newline added)" "$(tail -c1 "$COPY")" "$(tail -c1 "$REC")"
assert_eq "same size plus value" "$(( $(wc -c < "$COPY") + 6 ))" "$(wc -c < "$REC" | tr -d ' ')"
rm -f "$COPY"

begin_test "graduate ignores a heading-shaped line in Verified (review 2026-10-18 finding 1)"
fresh_root
run_capture $'## Verified\n\n- v\n### 1. (logic): decoy in verified\n\n## Findings\n\n### 1. (logic): real\n\nbody\n'
assert_eq "capture exit 0" "0" "$RC"
REC=$(printf '%s\n' "$OUT" | tail -1)
assert_eq "one stamp, under the real finding only" "1" "$(grep -c '^graduated_to:' "$REC")"
mkdir -p "$ROOT/.craft/fixes"; : > "$ROOT/.craft/fixes/fix-a.md"
run_graduate "$REC" 1 fix-a
assert_eq "graduate exit 0" "0" "$RC"
assert_file_contains "real finding graduated" "^graduated_to: fix-a$" "$REC"
assert_eq "decoy line untouched" "1" "$(grep -c '^### 1. (logic): decoy in verified$' "$REC")"

begin_test "numeric flags refuse a trailing newline (review 2026-10-18 finding 2)"
fresh_root
run_capture "$CLEAN_BODY" --files=$'5\n'
assert_eq "files with newline rc" "2" "$RC"
assert_contains "files with newline stderr" "^invalid files: 5" "$ERR"
run_capture "$CLEAN_BODY" --lines=$'40\n'
assert_eq "lines with newline rc" "2" "$RC"
assert_contains "lines with newline stderr" "^invalid lines: 40" "$ERR"
assert_eq "nothing written on refusal" "no" "$([ -d "$ROOT/.craft/reviews" ] && echo yes || echo no)"
mk_three_record
run_graduate "$REC" $'1\n' fix-a
assert_eq "graduate number with newline rc" "2" "$RC"
assert_contains "graduate number stderr" "^invalid finding number: 1" "$ERR"
assert_eq "record byte-identical on refusal" "" "$(cmp "$COPY" "$REC" 2>&1)"
rm -f "$COPY"

finish_tests test-review-scripts
