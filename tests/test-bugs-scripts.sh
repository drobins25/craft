#!/bin/bash
# test-bugs-scripts.sh - Behavior tests for the bugs scripts (list, capture, close).
#
# The list script runs inside a slash-command shell injection: a non-zero
# exit aborts the whole invocation and stderr is merged into the prompt, so
# the summary mode must exit 0 and stay silent on stderr for every input.
# Usage: bash tests/test-bugs-scripts.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

LIST="$SCRIPTS_DIR/bugs-list.sh"
CAPTURE="$SCRIPTS_DIR/bugs-capture.sh"
CLOSE="$SCRIPTS_DIR/bugs-close.sh"
HIT="$SCRIPTS_DIR/bugs-hit.sh"
TODAY=$(date +%Y-%m-%d)
TMP_ROOTS=()

fresh_root() {
  ROOT=$(mktemp -d)
  TMP_ROOTS+=("$ROOT")
  export CRAFT_PROJECT_ROOT="$ROOT"
  mkdir -p "$ROOT/.craft/bugs/closed"
}

cleanup_roots() {
  local r
  for r in "${TMP_ROOTS[@]:-}"; do [ -n "$r" ] && rm -rf "$r"; done
  return 0
}
trap cleanup_roots EXIT

# write_record <path> <captured_at> <found_during> <symptom> [blocks-line] [status]
write_record() {
  local path="$1" cap="$2" fd="$3" symptom="$4" blocks="${5:-}" status="${6:-open}"
  {
    echo "---"
    echo "type: bug"
    echo "created: ${cap%%T*}"
    [ -n "$cap" ] && echo "captured_at: $cap"
    echo "status: $status"
    echo "verdict:"
    echo "found_during: $fd"
    echo "layer: code"
    echo "hits: 1"
    echo "---"
    echo ""
    echo "$symptom"
    if [ -n "$blocks" ]; then
      echo ""
      echo "## Blocks my next step"
      echo ""
      echo "$blocks"
    fi
  } > "$path"
}

# run_list <args...> - sets OUT, ERR, RC (stderr captured separately)
run_list() {
  local errf
  errf=$(mktemp)
  OUT=$(bash "$LIST" "$@" 2>"$errf") && RC=0 || RC=$?
  ERR=$(cat "$errf")
  rm -f "$errf"
}

echo "=== test-bugs-scripts.sh ==="
echo ""

begin_test "summary on a missing folder"
ROOT=$(mktemp -d); TMP_ROOTS+=("$ROOT"); export CRAFT_PROJECT_ROOT="$ROOT"
run_list --summary
assert_eq "stdout" "Bugs: 0 open" "$OUT"
assert_eq "stderr empty" "" "$ERR"
assert_eq "rc" "0" "$RC"

begin_test "summary on an empty folder and an empty closed/"
fresh_root
run_list --summary
assert_eq "stdout" "Bugs: 0 open" "$OUT"
assert_eq "stderr empty" "" "$ERR"
assert_eq "rc" "0" "$RC"

begin_test "summary from a non-git cwd with no CRAFT_PROJECT_ROOT"
NOGIT=$(mktemp -d); TMP_ROOTS+=("$NOGIT")
OUT=$(cd "$NOGIT" && env -u CRAFT_PROJECT_ROOT bash "$LIST" --summary 2>"$NOGIT/err") && RC=0 || RC=$?
assert_eq "rc" "0" "$RC"
assert_eq "stdout" "Bugs: 0 open" "$OUT"
assert_eq "stderr empty" "" "$(cat "$NOGIT/err")"

begin_test "template, README, undated, binary, and unfenced files are skipped"
fresh_root
B="$ROOT/.craft/bugs"
printf -- '---\ntype: bug\nstatus: open\n---\n\n<Symptom in one line>\n' > "$B/_TEMPLATE.md"
printf -- '# Bugs\n\n```yaml\ntype: bug\n```\n' > "$B/README.md"
printf -- '---\ntype: bug\n---\n\nundated\n' > "$B/notes.md"
printf '\xff\xfe\x00\x80binary' > "$B/2026-09-01-binary.md"
printf 'no frontmatter here\n' > "$B/2026-09-02-plain.md"
printf -- '---\ntype: note\n---\n\nwrong type\n' > "$B/2026-09-03-wrong-type.md"
write_record "$B/2026-09-04-real.md" "2026-09-04T10:00:00Z" "conversation" "Real bug"
run_list --summary
assert_eq "one open" "Bugs: 1 open
- Real bug - found during: conversation" "$OUT"
assert_eq "stderr empty" "" "$ERR"
assert_eq "rc" "0" "$RC"

begin_test "an old-shape record with status: confirmed in the root room counts as open"
fresh_root
B="$ROOT/.craft/bugs"
printf -- '---\ntype: bug\ncreated: 2026-09-11\nstatus: confirmed\nverdict: ruled\nseverity: high\nfound_by: manual review (colons: ok)\n---\n\nOld shape symptom\n' > "$B/2026-09-11-old-shape.md"
run_list
assert_contains "STATUS=open" "^STATUS=open$" "$OUT"
assert_contains "VERDICT=ruled kept" "^VERDICT=ruled$" "$OUT"
run_list --summary
assert_eq "summary" "Bugs: 1 open
- Old shape symptom - found during: manual review (colons: ok)" "$OUT"
assert_eq "rc" "0" "$RC"

begin_test "newest first by captured_at, blocks marker on yes"
fresh_root
B="$ROOT/.craft/bugs"
write_record "$B/2026-10-01-earlier.md" "2026-10-01T10:00:00Z" "run A" "Earlier bug" "No - can work around"
write_record "$B/2026-10-01-later.md" "2026-10-01T11:00:00Z" "run B" "Later bug" "Yes - can't finish run"
write_record "$B/2026-09-30-oldest.md" "2026-09-30T09:00:00Z" "run C" "Oldest bug" "yes"
run_list --summary
assert_eq "ordered with marker" "Bugs: 3 open
- Later bug - found during: run B [blocks my next step]
- Earlier bug - found during: run A
- Oldest bug - found during: run C [blocks my next step]" "$OUT"

begin_test "ties fall back to created, then filename"
fresh_root
B="$ROOT/.craft/bugs"
printf -- '---\ntype: bug\ncreated: 2026-09-01\n---\n\nAlpha\n' > "$B/2026-09-01-a.md"
printf -- '---\ntype: bug\ncreated: 2026-09-01\n---\n\nBeta\n' > "$B/2026-09-01-b.md"
printf -- '---\ntype: bug\ncreated: 2026-09-02\n---\n\nGamma\n' > "$B/2026-09-02-c.md"
run_list --summary
assert_eq "created then filename desc" "Bugs: 3 open
- Gamma
- Beta
- Alpha" "$OUT"

begin_test "a long title is cut at a word boundary and marked with an ellipsis"
fresh_root
LONG="A monorepo opened at its top level files bugs and notebook entries into the top-level folder, where no project session ever lists them"
write_record "$ROOT/.craft/bugs/2026-10-01-long.md" "2026-10-01T10:00:00Z" "run" "$LONG"
write_record "$ROOT/.craft/bugs/2026-10-02-short.md" "2026-10-02T10:00:00Z" "run" "Short title stays whole"
run_list --summary
LINE=$(printf '%s\n' "$OUT" | grep '^- A monorepo')
TITLE_SHOWN="${LINE#- }"; TITLE_SHOWN="${TITLE_SHOWN% - found during: run}"
assert_eq "ends with an ellipsis" "yes" "$(case "$TITLE_SHOWN" in (*…) echo yes ;; (*) echo no ;; esac)"
CUT="${TITLE_SHOWN%…}"
assert_eq "cut is a whole-word prefix" "yes" "$(case "$LONG" in ("$CUT "*) echo yes ;; (*) echo no ;; esac)"
assert_contains "short title untouched" "^- Short title stays whole - found during: run$" "$OUT"
run_list
assert_contains "block TITLE uses the same cut" "^TITLE=${CUT}…$" "$OUT"

begin_test "found_by fallback and empty found-during omitted"
fresh_root
B="$ROOT/.craft/bugs"
printf -- '---\ntype: bug\ncreated: 2026-09-05\nfound_by: legacy filer\n---\n\nWith found_by\n' > "$B/2026-09-05-fb.md"
printf -- '---\ntype: bug\ncreated: 2026-09-04\nfound_during:\nfound_by:\n---\n\nNeither field\n' > "$B/2026-09-04-none.md"
run_list --summary
assert_eq "lines" "Bugs: 2 open
- With found_by - found during: legacy filer
- Neither field" "$OUT"

begin_test "block mode key order and --status filter"
fresh_root
B="$ROOT/.craft/bugs"
write_record "$B/2026-10-02-open-one.md" "2026-10-02T10:00:00Z" "conversation" "Open one" "yes"
write_record "$B/closed/2026-09-20-wont.md" "2026-09-20T10:00:00Z" "run X" "Wont one" "" "wont-fix"
write_record "$B/closed/2026-09-21-fixed.md" "2026-09-21T10:00:00Z" "run Y" "Fixed one" "" "fixed"
write_record "$B/closed/2026-09-22-odd.md" "2026-09-22T10:00:00Z" "run Z" "Odd one" "" "confirmed"
run_list
KEYS=$(echo "$OUT" | sed -n '1,/^$/p' | grep -v '^$' | sed 's/=.*//' | tr '\n' ' ')
assert_eq "11 keys in order" "FILE ROOM SLUG DATE TITLE STATUS VERDICT FOUND_DURING LAYER BLOCKS HITS " "$KEYS"
assert_eq "four blocks" "4" "$(echo "$OUT" | grep -c '^FILE=')"
assert_eq "first block is newest" "TITLE=Open one" "$(echo "$OUT" | grep '^TITLE=' | head -1)"
assert_contains "closed status without known word is closed" "^STATUS=closed$" "$OUT"
assert_contains "BLOCKS=yes" "^BLOCKS=yes$" "$OUT"
assert_contains "ROOM=closed" "^ROOM=closed$" "$OUT"
run_list --status=wont-fix
assert_eq "wont-fix filter" "1" "$(echo "$OUT" | grep -c '^FILE=')"
assert_contains "wont-fix title" "^TITLE=Wont one$" "$OUT"
run_list --status=open
assert_eq "open filter" "1" "$(echo "$OUT" | grep -c '^FILE=')"
run_list --status=closed
assert_eq "closed filter" "3" "$(echo "$OUT" | grep -c '^FILE=')"
run_list --bogus-flag --summary
assert_eq "unknown flags ignored" "Bugs: 1 open
- Open one - found during: conversation [blocks my next step]" "$OUT"
assert_eq "rc" "0" "$RC"

begin_test "both rooms: closed wins"
fresh_root
B="$ROOT/.craft/bugs"
write_record "$B/2026-10-01-dup.md" "2026-10-01T10:00:00Z" "run" "Dup open copy"
write_record "$B/closed/2026-10-01-dup.md" "2026-10-01T10:00:00Z" "run" "Dup closed copy" "" "fixed"
run_list --summary
assert_eq "not counted" "Bugs: 0 open" "$OUT"
run_list
assert_eq "one block" "1" "$(echo "$OUT" | grep -c '^FILE=')"
assert_contains "STATUS=fixed from closed copy" "^STATUS=fixed$" "$OUT"
assert_contains "closed copy fields" "^TITLE=Dup closed copy$" "$OUT"

begin_test "missing python3 prints the unavailable header and exits 0"
fresh_root
write_record "$ROOT/.craft/bugs/2026-10-01-x.md" "2026-10-01T10:00:00Z" "run" "X"
NOPY=$(mktemp -d); TMP_ROOTS+=("$NOPY")
for t in bash dirname cat sed grep head ls sort git env; do
  p=$(command -v "$t" 2>/dev/null || true); [ -n "$p" ] && ln -s "$p" "$NOPY/$t"
done
OUT=$(PATH="$NOPY" "$NOPY/bash" "$LIST" --summary 2>"$NOPY/err") && RC=0 || RC=$?
assert_eq "stdout" "Bugs: count unavailable (python3 not found)" "$OUT"
assert_eq "stderr empty" "" "$(cat "$NOPY/err")"
assert_eq "rc" "0" "$RC"

# ── capture and close ───────────────────────────────────────────────

# bare_root - a temp root with no .craft at all (filing works before init)
bare_root() {
  ROOT=$(mktemp -d)
  TMP_ROOTS+=("$ROOT")
  export CRAFT_PROJECT_ROOT="$ROOT"
}

# body_with <symptom> - a complete body whose symptom line is the argument
body_with() {
  printf '%s\n' "$1" '' '## What happened' '' \
    '**Expected.** The record saves.' '**Actual.** Nothing happens on click.' '' \
    '## Consequences' '' 'Users lose their edits.' '' \
    '## Blocks my next step' '' 'no - can work around it' '' \
    '## Reproduce' '' '1. Open the form' '2. Click save' '' \
    '## Notes' '' 'status: this prose line must survive'
}

# cap <args...> - body on stdin; sets OUT, ERR, RC
cap() {
  local errf body
  errf=$(mktemp)
  body=$(cat)
  OUT=$(printf '%s\n' "$body" | bash "$CAPTURE" "$@" 2>"$errf") && RC=0 || RC=$?
  ERR=$(cat "$errf")
  rm -f "$errf"
}

# file_bug <symptom> [extra capture args...] - files a valid bug; sets OUT (path)
file_bug() {
  local symptom="$1"; shift
cap --found-during="conversation" "$@" --stdin < <(  body_with "$symptom")
}

# run_close <args...> - sets OUT, ERR, RC
run_close() {
  local errf
  errf=$(mktemp)
  OUT=$(bash "$CLOSE" "$@" 2>"$errf") && RC=0 || RC=$?
  ERR=$(cat "$errf")
  rm -f "$errf"
}

begin_test "capture refuses each missing required field by name"
bare_root
cap --found-during="conversation" --stdin < <(body_with "Save button does nothing" | grep -v '^Save button')
assert_eq "no symptom: rc" "2" "$RC"
assert_contains "no symptom: named" "^missing required field: symptom line" "$ERR"
cap --found-during="conversation" --stdin < <(body_with "# a heading is not a symptom")
assert_contains "heading-led symptom" "^missing required field: symptom line" "$ERR"
cap --stdin < <(body_with "Symptom")
assert_eq "no found_during: rc" "2" "$RC"
assert_eq "no found_during: stderr" "missing required field: found_during" "$ERR"
cap --found-during="x" --stdin < <(body_with "Symptom" | grep -v 'Expected\.')
assert_eq "no Expected: stderr" "missing required field: Expected" "$ERR"
cap --found-during="x" --stdin < <(body_with "Symptom" | grep -v 'Actual\.')
assert_eq "no Actual: stderr" "missing required field: Actual" "$ERR"
cap --found-during="x" --stdin < <(body_with "Symptom" | grep -v -e '^## Consequences' -e 'lose their edits')
assert_eq "no Consequences: stderr" "missing required field: Consequences" "$ERR"
cap --found-during="x" --stdin < <(body_with "Symptom" | grep -v -e '^## Blocks my next step' -e 'no - can work')
assert_eq "no Blocks: stderr" "missing required field: Blocks my next step" "$ERR"
cap --found-during="x" --stdin < <(body_with "Symptom" | sed 's/^no - can work around it/maybe/')
assert_eq "Blocks not yes/no: stderr" "missing required field: Blocks my next step" "$ERR"
cap --found-during="x" --stdin < <(body_with "Symptom" | grep -v -e '^## Reproduce' -e 'Open the form' -e 'Click save')
assert_eq "no Reproduce: stderr" "missing required field: Reproduce" "$ERR"
assert_eq "rc" "2" "$RC"
assert_dir_not_exists "no .craft created" "$ROOT/.craft"

begin_test "capture reports every missing field, one line each"
bare_root
cap --stdin < <(printf 'Only a symptom\n')
assert_eq "rc" "2" "$RC"
assert_eq "line count" "6" "$(echo "$ERR" | wc -l | tr -d ' ')"
assert_eq "found_during first after symptom" "missing required field: found_during" "$(echo "$ERR" | sed -n '1p')"
assert_dir_not_exists "no .craft created" "$ROOT/.craft"

begin_test "a pointer-only field counts as missing"
bare_root
cap --found-during="x" --stdin < <(body_with "Symptom" | sed 's/^\*\*Actual\.\*\* .*/**Actual.** <Only what was observed.>/')
assert_eq "Actual pointer" "missing required field: Actual" "$ERR"
assert_eq "rc" "2" "$RC"
cap --found-during="<where you were>" --stdin < <(body_with "Symptom")
assert_eq "found_during pointer" "missing required field: found_during" "$ERR"
cap --found-during="x" --stdin < <(body_with "Symptom" | sed 's/^Users lose their edits\./<What this costs>/')
assert_eq "Consequences pointer" "missing required field: Consequences" "$ERR"
assert_dir_not_exists "no .craft created" "$ROOT/.craft"

begin_test "invalid enum flags are refused before anything is written"
bare_root
cap --found-during="x" --layer=vibes --stdin < <(body_with "Symptom")
assert_eq "layer: rc" "2" "$RC"
assert_eq "layer: stderr" "invalid --layer: vibes" "$ERR"
cap --found-during="x" --verdict=guess --stdin < <(body_with "Symptom")
assert_eq "verdict: stderr" "invalid --verdict: guess" "$ERR"
assert_dir_not_exists "no .craft created" "$ROOT/.craft"

begin_test "stdin is required"
bare_root
cap --found-during="x" < <(body_with "Symptom")
assert_eq "rc" "2" "$RC"
assert_contains_literal "named" "--stdin" "$ERR"
assert_dir_not_exists "no .craft created" "$ROOT/.craft"

begin_test "capture writes the frontmatter in order and the body verbatim"
bare_root
body_with "Save button does nothing" > "$ROOT/body.txt"
file_bug "Save button does nothing" --requirement="Saving must persist: always" --layer=code --worked-before="v1 (yes)" --verdict=bug --tags="UI,save"
assert_eq "rc" "0" "$RC"
F="$OUT"
KEYS=$(awk '/^---$/{c++; next} c==1{print}' "$F" | sed 's/:.*//' | tr '\n' ' ')
assert_eq "key order" "type created captured_at status verdict found_during requirement layer worked_before hits fixed_by tags " "$KEYS"
assert_contains "type" "^type: bug$" "$(cat "$F")"
assert_contains "created" "^created: $TODAY$" "$(cat "$F")"
assert_contains "captured_at UTC" "^captured_at: [0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9:]*Z$" "$(cat "$F")"
assert_contains "status" "^status: open$" "$(cat "$F")"
assert_contains "verdict" "^verdict: bug$" "$(cat "$F")"
assert_contains "found_during raw" "^found_during: conversation$" "$(cat "$F")"
assert_contains "requirement raw" "^requirement: Saving must persist: always$" "$(cat "$F")"
assert_contains "worked_before raw" "^worked_before: v1 (yes)$" "$(cat "$F")"
assert_contains "hits" "^hits: 1$" "$(cat "$F")"
assert_contains "fixed_by blank" "^fixed_by:$" "$(cat "$F")"
assert_contains "tags" "^tags: \[ui, save\]$" "$(cat "$F")"
BODY_IN=$(cat "$ROOT/body.txt")
assert_eq "body byte-equal once the Log section is lifted out" "$BODY_IN" "$(awk '/^---$/{c++; next} c>=2{print}' "$F" | sed '1{/^$/d;}' | awk '/^## Log$/{skip=1; next} /^## /{skip=0} !skip{print}')"
assert_contains "Log entry" "^- $TODAY filed$" "$(cat "$F")"
assert_eq "exactly one Log section" "1" "$(grep -c '^## Log$' "$F")"
file_bug "Another symptom"
assert_contains "empty tags" "^tags: \[\]$" "$(cat "$OUT")"
assert_contains "blank layer" "^layer:$" "$(cat "$OUT")"
assert_contains "blank requirement" "^requirement:$" "$(cat "$OUT")"

begin_test "capture puts the Log before Notes, or appends inside an existing Log"
bare_root
file_bug "Log placement"
LN=$(grep -n '^## Log$' "$OUT" | cut -d: -f1)
NN=$(grep -n '^## Notes$' "$OUT" | cut -d: -f1)
assert_eq "Log precedes Notes" "yes" "$([ "$LN" -lt "$NN" ] && echo yes || echo no)"
cap --found-during="x" --stdin < <({ body_with "Has own log" | sed '/^## Notes/,$d'; printf '## Log\n\n- 2026-01-01 earlier entry\n'; })
assert_eq "one Log" "1" "$(grep -c '^## Log$' "$OUT")"
assert_eq "entry appended last" "- $TODAY filed" "$(tail -1 "$OUT")"
assert_contains "earlier entry kept" "^- 2026-01-01 earlier entry$" "$(cat "$OUT")"
cap --found-during="x" --stdin < <(body_with "No notes" | sed '/^## Notes/,$d')
assert_eq "appended at end" "- $TODAY filed" "$(tail -1 "$OUT")"

begin_test "slug rule: special chars, 50 cap, untitled"
bare_root
file_bug "It's a TEST!! with @#weird chars"
case "$OUT" in
  *its-a-test-with*|*it-s-a-test-with*) assert_eq "special chars stripped from slug" "ok" "ok" ;;
  *) assert_eq "special chars stripped from slug" "slug without special chars" "$OUT" ;;
esac
assert_contains "date prefix" "/$TODAY-it-s-a-test-with-weird-chars.md$" "$OUT"
file_bug "this is a very long title that should be capped at fifty characters and not exceed it"
BASE=$(basename "$OUT" .md)
SLUG_PART="${BASE#????-??-??-}"
assert_eq "slug capped at 50 or fewer" "yes" "$([ ${#SLUG_PART} -le 50 ] && echo yes || echo no)"
assert_eq "cap falls back to the last hyphen" "this-is-a-very-long-title-that-should-be-capped" "$SLUG_PART"
file_bug '!!! ???'
assert_contains "all-punctuation symptom is untitled" "/$TODAY-untitled.md$" "$OUT"

begin_test "same-day collision -2 then -3"
bare_root
file_bug "duplicate title"; O1="$OUT"
file_bug "duplicate title"; O2="$OUT"
file_bug "duplicate title"; O3="$OUT"
assert_contains "first plain" "/$TODAY-duplicate-title.md$" "$O1"
assert_contains "second -2" "/$TODAY-duplicate-title-2.md$" "$O2"
assert_contains "third -3" "/$TODAY-duplicate-title-3.md$" "$O3"

begin_test "path is the last stdout line and rc 0"
bare_root
file_bug "Path check"
assert_eq "rc" "0" "$RC"
assert_eq "path is absolute and exists" "yes" "$([ "${OUT:0:1}" = "/" ] && [ -f "$(echo "$OUT" | tail -1)" ] && echo yes || echo no)"
assert_eq "stdout is only the path" "1" "$(echo "$OUT" | wc -l | tr -d ' ')"
assert_contains "lands in .craft/bugs" "^$ROOT/.craft/bugs/$TODAY-path-check.md$" "$OUT"

begin_test "capture works before init"
GITROOT=$(mktemp -d); TMP_ROOTS+=("$GITROOT")
git -C "$GITROOT" init -q
mkdir -p "$GITROOT/sub/dir"
errf=$(mktemp)
OUT=$(cd "$GITROOT/sub/dir" && env -u CRAFT_PROJECT_ROOT bash -c 'printf "%s\n" "$1" | bash "$2" --found-during=x --stdin' _ "$(body_with "Cold filing")" "$CAPTURE" 2>"$errf") && RC=0 || RC=$?
rm -f "$errf"
assert_eq "rc" "0" "$RC"
GITTOP=$(cd "$GITROOT" && pwd -P)
assert_eq "file lands at the toplevel" "yes" "$(ls "$GITROOT"/.craft/bugs/"$TODAY"-cold-filing.md >/dev/null 2>&1 && echo yes || echo no)"
assert_eq "none in the subdirectory" "no" "$([ -e "$GITROOT/sub/dir/.craft" ] && echo yes || echo no)"

begin_test "outside git, the local-filing notice appears only when a record is written"
NOGITCAP=$(mktemp -d); TMP_ROOTS+=("$NOGITCAP")
errf=$(mktemp)
(cd "$NOGITCAP" && env -u CRAFT_PROJECT_ROOT bash -c 'printf "%s\n" "only a symptom" | bash "$1" --found-during=x --stdin' _ "$CAPTURE" 2>"$errf") && RC=0 || RC=$?
ERR=$(cat "$errf")
assert_eq "refused rc" "2" "$RC"
assert_not_contains "a refusal announces no filing" "not a git repo" "$ERR"
assert_eq "nothing written" "no" "$([ -e "$NOGITCAP/.craft" ] && echo yes || echo no)"
OUT=$(cd "$NOGITCAP" && env -u CRAFT_PROJECT_ROOT bash -c 'printf "%s\n" "$1" | bash "$2" --found-during=x --stdin' _ "$(body_with "Local filing")" "$CAPTURE" 2>"$errf") && RC=0 || RC=$?
ERR=$(cat "$errf")
rm -f "$errf"
assert_eq "written rc" "0" "$RC"
FILED="$(printf '%s\n' "$OUT" | tail -1)"
assert_eq "record exists" "yes" "$([ -f "$FILED" ] && echo yes || echo no)"
assert_contains "the notice names the written file" "not a git repo - filed to $FILED" "$ERR"

# ── close ──

begin_test "close: fenced edit leaves a body status line byte-identical"
fresh_root
file_bug "Close me"; F="$OUT"
BEFORE_VERDICT=$(grep -n '^verdict:' "$F")
cp "$F" "$ROOT/before.md"
run_close "$F" --status=fixed
assert_eq "rc" "0" "$RC"
CLOSED="$ROOT/.craft/bugs/closed/$(basename "$F")"
assert_file_exists "closed copy" "$CLOSED"
assert_file_not_exists "source removed" "$F"
assert_contains "status set in fence" "^status: fixed$" "$(awk '/^---$/{c++; next} c==1{print}' "$CLOSED")"
assert_contains "body prose line survives" "^status: this prose line must survive$" "$(cat "$CLOSED")"
assert_eq "body status line count unchanged" "1" "$(awk '/^---$/{c++; next} c>=2{print}' "$CLOSED" | grep -c '^status: ')"
assert_eq "verdict line byte-identical with no --verdict" "$(grep '^verdict:' "$ROOT/before.md" | od -c)" "$(grep '^verdict:' "$CLOSED" | od -c)"
assert_eq "title then path on stdout" "TITLE=Close me
$CLOSED" "$OUT"
BODY_BEFORE=$(awk '/^---$/{c++; next} c>=2{print}' "$ROOT/before.md" | awk '/^## Log$/{exit} {print}')
BODY_AFTER=$(awk '/^---$/{c++; next} c>=2{print}' "$CLOSED" | awk '/^## Log$/{exit} {print}')
assert_eq "body before Log untouched" "$BODY_BEFORE" "$BODY_AFTER"

begin_test "close: a given verdict is written; blank verdict line kept otherwise"
fresh_root
file_bug "Verdict kept"; F="$OUT"
run_close "$F" --status=wont-fix --verdict=spec-gap --fixed-by="story 12" --note="intended behavior"
CLOSED="$ROOT/.craft/bugs/closed/$(basename "$F")"
assert_contains "verdict written" "^verdict: spec-gap$" "$(cat "$CLOSED")"
assert_contains "fixed_by written" "^fixed_by: story 12$" "$(cat "$CLOSED")"
assert_contains "Log line with every part" "^- $TODAY closed: wont-fix, verdict spec-gap, fixed by story 12 - intended behavior$" "$(cat "$CLOSED")"
fresh_root
file_bug "No verdict"; F="$OUT"
run_close "$F" --status=wont-fix
CLOSED="$ROOT/.craft/bugs/closed/$(basename "$F")"
assert_contains "blank verdict kept" "^verdict:$" "$(cat "$CLOSED")"
assert_contains "Log line bare" "^- $TODAY closed: wont-fix$" "$(cat "$CLOSED")"

begin_test "close: Log line appended; created when absent on an old record"
fresh_root
file_bug "Has a log"; F="$OUT"
run_close "$F" --status=fixed
CLOSED="$ROOT/.craft/bugs/closed/$(basename "$F")"
assert_eq "one Log" "1" "$(grep -c '^## Log$' "$CLOSED")"
LOGSEC=$(awk '/^## Log$/{f=1; next} /^## /{f=0} f' "$CLOSED" | grep -v '^$')
assert_eq "filed then closed" "- $TODAY filed
- $TODAY closed: fixed" "$LOGSEC"
OLD="$ROOT/.craft/bugs/2026-09-11-old-shape.md"
printf -- '---\ntype: bug\ncreated: 2026-09-11\nstatus: confirmed\nverdict: ruled\nfound_by: manual\n---\n\nOld symptom\n\n## Notes\n\nkept note\n' > "$OLD"
run_close "$OLD" --status=fixed
CLOSED="$ROOT/.craft/bugs/closed/2026-09-11-old-shape.md"
assert_eq "Log created" "1" "$(grep -c '^## Log$' "$CLOSED")"
assert_eq "Log precedes Notes" "yes" "$([ "$(grep -n '^## Log$' "$CLOSED" | cut -d: -f1)" -lt "$(grep -n '^## Notes$' "$CLOSED" | cut -d: -f1)" ] && echo yes || echo no)"
assert_contains "close line" "^- $TODAY closed: fixed$" "$(cat "$CLOSED")"
assert_contains "old status replaced in fence" "^status: fixed$" "$(cat "$CLOSED")"
assert_contains "old verdict untouched" "^verdict: ruled$" "$(cat "$CLOSED")"
printf -- '---\ntype: bug\ncreated: 2026-09-12\n---\n\nNo notes old\n' > "$ROOT/.craft/bugs/2026-09-12-no-notes.md"
run_close 2026-09-12-no-notes --status=wont-fix
CLOSED="$ROOT/.craft/bugs/closed/2026-09-12-no-notes.md"
assert_eq "missing status and verdict keys appended in fence" "type: bug
created: 2026-09-12
status: wont-fix
closed_at: $TODAY" "$(awk '/^---$/{c++; next} c==1{print}' "$CLOSED")"
assert_eq "Log appended at end" "- $TODAY closed: wont-fix" "$(tail -1 "$CLOSED")"

begin_test "close: stamps closed_at"
fresh_root
file_bug "Stamp me"; F="$OUT"
assert_not_contains "absent before" "closed_at" "$(cat "$F")"
run_close "$F" --status=fixed
CLOSED="$ROOT/.craft/bugs/closed/$(basename "$F")"
FM=$(awk '/^---$/{c++; next} c==1{print}' "$CLOSED")
assert_contains "closed_at in the fence" "^closed_at: $TODAY$" "$FM"
assert_eq "closed_at is the last frontmatter key" "closed_at: $TODAY" "$(echo "$FM" | tail -1)"

begin_test "close: resolves a dated slug, with or without .md, and a trailing fragment"
fresh_root
B="$ROOT/.craft/bugs"
write_record "$B/2026-10-01-alpha-widget.md" "2026-10-01T10:00:00Z" "run" "Alpha"
write_record "$B/2026-10-01-beta-gadget.md" "2026-10-01T11:00:00Z" "run" "Beta"
write_record "$B/2026-10-01-gamma-gizmo.md" "2026-10-01T12:00:00Z" "run" "Gamma"
run_close 2026-10-01-alpha-widget --status=fixed
assert_eq "whole slug" "0" "$RC"
run_close 2026-10-01-beta-gadget.md --status=fixed
assert_eq "slug with .md" "0" "$RC"
run_close gizmo --status=wont-fix
assert_eq "fragment" "0" "$RC"
assert_eq "all moved" "3" "$(ls "$B/closed" | wc -l | tr -d ' ')"

begin_test "close: refuses an ambiguous fragment, both records untouched"
fresh_root
B="$ROOT/.craft/bugs"
write_record "$B/2026-10-01-save-button-a.md" "2026-10-01T10:00:00Z" "run" "Save A"
write_record "$B/2026-10-01-save-button-b.md" "2026-10-01T11:00:00Z" "run" "Save B"
SUM_BEFORE=$(cksum "$B"/2026-10-01-save-button-*.md)
run_close save-button --status=fixed
assert_eq "rc" "2" "$RC"
assert_eq "stderr" "ambiguous: 2026-10-01-save-button-a, 2026-10-01-save-button-b" "$ERR"
assert_eq "records byte-identical" "$SUM_BEFORE" "$(cksum "$B"/2026-10-01-save-button-*.md)"
assert_eq "closed/ empty" "0" "$(ls "$B/closed" | wc -l | tr -d ' ')"

begin_test "close: an exact slug wins over longer siblings"
fresh_root
B="$ROOT/.craft/bugs"
write_record "$B/2026-10-01-save.md" "2026-10-01T10:00:00Z" "run" "Save"
write_record "$B/2026-10-01-save-2.md" "2026-10-01T11:00:00Z" "run" "Save two"
run_close 2026-10-01-save --status=fixed
assert_eq "rc" "0" "$RC"
assert_file_exists "exact one closed" "$B/closed/2026-10-01-save.md"
assert_file_exists "sibling untouched" "$B/2026-10-01-save-2.md"

begin_test "close: a path or full dated name with no open record is refused, never closes a similar bug"
fresh_root
B="$ROOT/.craft/bugs"
write_record "$B/2026-10-01-save-button.md" "2026-10-01T10:00:00Z" "run" "Save"
write_record "$B/2026-10-01-save-button-2.md" "2026-10-01T11:00:00Z" "run" "Save two"
write_record "$B/2026-10-02-save-button-safari.md" "2026-10-02T11:00:00Z" "run" "Safari"
write_record "$B/closed/2026-09-01-save-button.md" "2026-09-01T10:00:00Z" "run" "Old" "" "fixed"
run_close "$B/2026-10-01-save-button.md" --status=fixed
assert_eq "first close by path rc" "0" "$RC"
SUM_BEFORE=$(cksum "$B"/*.md "$B"/closed/*.md)
run_close "$B/2026-10-01-save-button.md" --status=fixed
assert_eq "path to a gone file: rc" "2" "$RC"
assert_eq "path to a gone file: stderr" "already closed: 2026-10-01-save-button" "$ERR"
run_close 2026-10-01-save-button --status=fixed
assert_eq "gone dated name: rc" "2" "$RC"
run_close "$B/save-button.md" --status=fixed
assert_eq "undated missing path: rc" "2" "$RC"
assert_eq "undated missing path: stderr" "not found: save-button" "$ERR"
run_close 2026-10-02-save-button --status=fixed
assert_eq "dated prefix of another record: rc" "2" "$RC"
assert_eq "dated prefix: stderr" "not found: 2026-10-02-save-button" "$ERR"
assert_eq "nothing else closed" "$SUM_BEFORE" "$(cksum "$B"/*.md "$B"/closed/*.md)"

begin_test "close: destination-first - the closed copy exists even when the source cannot be removed"
fresh_root
file_bug "Order matters"; F="$OUT"
run_close "$F" --status=fixed
assert_file_exists "closed copy" "$ROOT/.craft/bugs/closed/$(basename "$F")"
assert_file_not_exists "root file gone" "$F"
assert_eq "no tmp left behind" "0" "$(ls "$ROOT/.craft/bugs/closed" | grep -c '\.tmp$' || true)"
if [ "$(id -u)" != "0" ]; then
  file_bug "Stuck source"; F="$OUT"
  chmod a-w "$ROOT/.craft/bugs"
  run_close "$F" --status=fixed
  chmod u+w "$ROOT/.craft/bugs"
  assert_eq "rm failure is not success" "yes" "$([ "$RC" != "0" ] && echo yes || echo no)"
  assert_file_exists "closed copy still written" "$ROOT/.craft/bugs/closed/$(basename "$F")"
  assert_file_exists "source still present" "$F"
fi

begin_test "close refuses already-closed, unknown, bad flags"
fresh_root
B="$ROOT/.craft/bugs"
write_record "$B/closed/2026-09-01-done.md" "2026-09-01T10:00:00Z" "run" "Done" "" "fixed"
write_record "$B/2026-09-02-open.md" "2026-09-02T10:00:00Z" "run" "Open"
SUM_BEFORE=$(cksum "$B"/*.md "$B"/closed/*.md)
run_close 2026-09-01-done --status=fixed
assert_eq "closed rc" "2" "$RC"
assert_eq "closed stderr" "already closed: 2026-09-01-done" "$ERR"
run_close "$B/closed/2026-09-01-done.md" --status=fixed
assert_eq "closed by path" "already closed: 2026-09-01-done" "$ERR"
run_close nonexistent-thing --status=fixed
assert_eq "unknown rc" "2" "$RC"
assert_eq "unknown stderr" "not found: nonexistent-thing" "$ERR"
run_close 2026-09-02-open --status=fixed --verdict=guess
assert_eq "bad verdict rc" "2" "$RC"
assert_eq "bad verdict stderr" "invalid --verdict: guess" "$ERR"
run_close 2026-09-02-open --status=confirmed
assert_eq "bad status stderr" "invalid --status: confirmed" "$ERR"
run_close 2026-09-02-open
assert_eq "missing status rc" "2" "$RC"
assert_eq "missing status stderr" "missing --status" "$ERR"
run_close --status=fixed
assert_eq "missing target rc" "2" "$RC"
assert_contains "missing target stderr" "missing target" "$ERR"
assert_eq "nothing changed" "$SUM_BEFORE" "$(cksum "$B"/*.md "$B"/closed/*.md)"

begin_test "close refuses a target that reduces to an empty name"
fresh_root
B="$ROOT/.craft/bugs"
write_record "$B/2026-09-02-only.md" "2026-09-02T10:00:00Z" "run" "The only open bug"
SUM_BEFORE=$(cksum "$B"/*.md)
for t in ".md" "/.md" "some/dir/.md"; do
  run_close "$t" --status=fixed
  assert_eq "rc for '$t'" "2" "$RC"
  assert_contains "stderr for '$t'" "missing target" "$ERR"
done
assert_eq "open record untouched" "$SUM_BEFORE" "$(cksum "$B"/*.md)"
assert_eq "closed/ still empty" "0" "$(find "$B/closed" -type f 2>/dev/null | wc -l | tr -d ' ')"

begin_test "close refuses files that are not bug records, on every route"
fresh_root
B="$ROOT/.craft/bugs"
write_record "$B/2026-09-02-real.md" "2026-09-02T10:00:00Z" "run" "A real bug"
printf -- '---\ntype: bug\nstatus: open\n---\n\n<Symptom in one line>\n' > "$B/_TEMPLATE.md"
printf '# Bugs\n\nPrototype readme.\n' > "$B/README.md"
printf -- '---\ntype: note\nstatus: open\n---\n\nNot a bug.\n' > "$B/2026-09-03-notes.md"
ln -s "$B/2026-09-02-real.md" "$B/2026-09-05-link.md"
SUM_BEFORE=$(cksum "$B"/*.md)
run_close "$B/2026-09-05-link.md" --status=fixed
assert_eq "symlink rc" "2" "$RC"
assert_eq "symlink stderr" "not a bug record: 2026-09-05-link" "$ERR"
assert_eq "symlink is still a link" "yes" "$([ -L "$B/2026-09-05-link.md" ] && echo yes || echo no)"
run_close _TEMPLATE --status=wont-fix
assert_eq "template by name rc" "2" "$RC"
assert_eq "template by name stderr" "not a bug record: _TEMPLATE" "$ERR"
run_close "$B/_TEMPLATE.md" --status=wont-fix
assert_eq "template by path rc" "2" "$RC"
assert_eq "template by path stderr" "not a bug record: _TEMPLATE" "$ERR"
run_close README --status=fixed
assert_eq "readme rc" "2" "$RC"
run_close 2026-09-03-notes --status=fixed
assert_eq "dated non-bug rc" "2" "$RC"
assert_eq "dated non-bug stderr" "not a bug record: 2026-09-03-notes" "$ERR"
assert_eq "nothing changed" "$SUM_BEFORE" "$(cksum "$B"/*.md)"
assert_eq "closed/ still empty" "0" "$(find "$B/closed" -type f 2>/dev/null | wc -l | tr -d ' ')"

begin_test "concurrent same-symptom captures never overwrite each other"
bare_root
N=12
BODY=$(body_with "Save does nothing")
for i in $(seq 1 $N); do
  printf '%s\n' "$BODY" | bash "$CAPTURE" --found-during="conversation" --stdin >/dev/null 2>&1 &
done
wait
COUNT=$(find "$ROOT/.craft/bugs" -maxdepth 1 -name '*-save-does-nothing*.md' | wc -l | tr -d ' ')
assert_eq "one file per capture" "$N" "$COUNT"

begin_test "close refuses a destination that already exists"
fresh_root
B="$ROOT/.craft/bugs"
write_record "$B/2026-09-02-twin.md" "2026-09-02T10:00:00Z" "run" "Twin open"
write_record "$B/closed/2026-09-02-twin.md" "2026-09-02T10:00:00Z" "run" "Twin closed" "" "fixed"
SUM_BEFORE=$(cksum "$B"/*.md "$B"/closed/*.md)
run_close 2026-09-02-twin --status=fixed
assert_eq "rc" "2" "$RC"
assert_eq "stderr" "already in closed/: 2026-09-02-twin" "$ERR"
assert_eq "nothing changed" "$SUM_BEFORE" "$(cksum "$B"/*.md "$B"/closed/*.md)"

begin_test "closed record leaves the open pile and shows in the closed room"
fresh_root
file_bug "Pile check"; F="$OUT"
run_list --summary
assert_eq "open before" "Bugs: 1 open
- Pile check - found during: conversation" "$OUT"
run_close "$F" --status=fixed
run_list --summary
assert_eq "open after" "Bugs: 0 open" "$OUT"
run_list --status=fixed
assert_eq "listed as fixed" "1" "$(echo "$OUT" | grep -c '^STATUS=fixed$')"

begin_test "dashboard: one open and one closed bug become exactly two bug nodes"
fresh_root
B="$ROOT/.craft/bugs"
file_bug "Open one"
file_bug "Closed one"; F2="$OUT"
run_close "$F2" --status=fixed
printf -- '---
type: bug
status: open
---

Template
' > "$B/_TEMPLATE.md"
printf '# Bugs\n\nPrototype readme.\n' > "$B/README.md"
bash "$PLUGIN_ROOT/scripts/dashboard/dashboard-run.sh" --root "$ROOT" >/dev/null 2>&1
GRAPH="$ROOT/.craft/graph/graph.js"
assert_eq "graph written" "yes" "$([ -f "$GRAPH" ] && echo yes || echo no)"
RESULT=$(python3 - "$GRAPH" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
data = json.loads(text[text.index("{"):text.rindex("}") + 1])
nodes = [n for n in data["nodes"] if n["type"] == "bug"]
print(len(nodes), sorted((n["status"], bool(n["found_during"])) for n in nodes))
PY
)
assert_eq "two bug nodes" "2 [('fixed', True), ('open', True)]" "$RESULT"

# ── hit ─────────────────────────────────────────────────────────────

# run_hit <args...> - sets OUT, ERR, RC
run_hit() {
  local errf
  errf=$(mktemp)
  OUT=$(bash "$HIT" "$@" 2>"$errf") && RC=0 || RC=$?
  ERR=$(cat "$errf")
  rm -f "$errf"
}

# fence_of <file> - the lines between the first two --- fences
fence_of() { awk '/^---$/{c++; next} c==1{print}' "$1"; }

begin_test "hit: bumps hits and appends the Log line"
fresh_root
file_bug "Hit me"; F="$OUT"
assert_contains "filed with hits: 1" "^hits: 1$" "$(fence_of "$F")"
run_hit "$F" --where="X"
assert_eq "rc" "0" "$RC"
assert_contains "fence hits: 2" "^hits: 2$" "$(fence_of "$F")"
assert_eq "one hits line in the fence" "1" "$(fence_of "$F" | grep -c '^hits:')"
LOG_LAST=$(awk '/^## Log$/{f=1; next} /^## /{f=0} f && NF{l=$0} END{print l}' "$F")
assert_eq "last Log line" "- $TODAY hit again: X" "$LOG_LAST"
assert_eq "title, hits, then path on stdout" "TITLE=Hit me
HITS=2
$F" "$OUT"
assert_eq "no tmp left behind" "0" "$(ls "$ROOT/.craft/bugs" | grep -c '\.tmp' || true)"

begin_test "hit: twice gives hits: 3 and two hit lines in order"
fresh_root
file_bug "Twice"; F="$OUT"
run_hit "$F" --where="first place"
run_hit "$F" --where="second place"
assert_contains "fence hits: 3" "^hits: 3$" "$(fence_of "$F")"
assert_contains "HITS=3 on stdout" "^HITS=3$" "$OUT"
HIT_LINES=$(grep 'hit again:' "$F")
assert_eq "two hit lines in order" "- $TODAY hit again: first place
- $TODAY hit again: second place" "$HIT_LINES"

begin_test "hit: where is collapsed to one line"
fresh_root
file_bug "Collapse"; F="$OUT"
run_hit "$F" --where="  multi
  line   where  "
assert_eq "rc" "0" "$RC"
assert_contains_literal "one-line entry" "- $TODAY hit again: multi line where" "$(cat "$F")"

begin_test "hit: body hits line untouched"
fresh_root
B="$ROOT/.craft/bugs"
printf -- '---\ntype: bug\ncreated: 2026-09-12\nhits: 1\n---\n\nBody guard\n\nhits: prose stays\n\n## Notes\n\nn\n' > "$B/2026-09-12-body-guard.md"
cp "$B/2026-09-12-body-guard.md" "$ROOT/before.md"
run_hit "$B/2026-09-12-body-guard.md" --where="X"
assert_eq "rc" "0" "$RC"
assert_contains "fence bumped" "^hits: 2$" "$(fence_of "$B/2026-09-12-body-guard.md")"
assert_eq "body hits line byte-identical" "$(grep -n 'hits: prose stays' "$ROOT/before.md" | od -c)" "$(grep -n 'hits: prose stays' "$B/2026-09-12-body-guard.md" | od -c)"
assert_eq "exactly one body hits line" "1" "$(awk '/^---$/{c++; next} c>=2{print}' "$B/2026-09-12-body-guard.md" | grep -c '^hits:')"

begin_test "hit: old record without hits or Log"
fresh_root
B="$ROOT/.craft/bugs"
printf -- '---\ntype: bug\ncreated: 2026-09-12\nstatus: open\n---\n\nNo notes old\n' > "$B/2026-09-12-no-notes.md"
run_hit "$B/2026-09-12-no-notes.md" --where="Y"
assert_eq "rc" "0" "$RC"
assert_contains "fence gains hits: 2" "^hits: 2$" "$(fence_of "$B/2026-09-12-no-notes.md")"
assert_eq "last fence line is hits" "hits: 2" "$(fence_of "$B/2026-09-12-no-notes.md" | tail -1)"
assert_eq "Log created at the end" "## Log

- $TODAY hit again: Y" "$(awk '/^## Log$/{f=1} f' "$B/2026-09-12-no-notes.md")"
printf -- '---\ntype: bug\ncreated: 2026-09-12\nhits: lots\n---\n\nWith notes\n\n## Notes\n\nkept note\n' > "$B/2026-09-12-with-notes.md"
run_hit "$B/2026-09-12-with-notes.md" --where="Z"
assert_contains "non-integer hits counts as 1" "^hits: 2$" "$(fence_of "$B/2026-09-12-with-notes.md")"
assert_eq "Log sits before Notes" "## Log
- $TODAY hit again: Z
## Notes" "$(grep -v '^$' "$B/2026-09-12-with-notes.md" | grep -A2 '^## Log')"
assert_contains "note kept" "^kept note$" "$(cat "$B/2026-09-12-with-notes.md")"

begin_test "hit refuses closed, non-record, missing target, empty --where, unknown flag"
fresh_root
B="$ROOT/.craft/bugs"
file_bug "Open one"; F="$OUT"
write_record "$B/closed/2026-09-01-done.md" "2026-09-01T10:00:00Z" "run" "Done" "" "fixed"
printf '# Bugs\n\nreadme\n' > "$B/README.md"
printf -- '---\ntype: bug\n---\n\nundated\n' > "$B/notes.md"
printf -- '---\ntype: note\n---\n\nwrong type\n' > "$B/2026-09-03-wrong-type.md"
printf 'no fence\n' > "$B/2026-09-04-plain.md"
ln -s "$F" "$B/2026-09-06-link.md"
SUM_BEFORE=$(cksum "$B"/*.md "$B"/closed/*.md)
run_hit "$B/2026-09-06-link.md" --where="X"
assert_eq "symlink rc" "2" "$RC"
assert_eq "symlink stderr" "not an open bug record: 2026-09-06-link" "$ERR"
assert_eq "symlink is still a link" "yes" "$([ -L "$B/2026-09-06-link.md" ] && echo yes || echo no)"
run_hit "$B/closed/2026-09-01-done.md" --where="X"
assert_eq "closed rc" "2" "$RC"
assert_eq "closed stderr" "already closed: 2026-09-01-done" "$ERR"
for bad in README notes 2026-09-03-wrong-type 2026-09-04-plain; do
  run_hit "$B/$bad.md" --where="X"
  assert_eq "$bad rc" "2" "$RC"
  assert_eq "$bad stderr" "not an open bug record: $bad" "$ERR"
done
run_hit "$B/2026-01-01-missing.md" --where="X"
assert_eq "missing rc" "2" "$RC"
run_hit --where="X"
assert_eq "no target rc" "2" "$RC"
run_hit "$F" --where=""
assert_eq "empty where rc" "2" "$RC"
run_hit "$F" --where="   "
assert_eq "blank where rc" "2" "$RC"
run_hit "$F"
assert_eq "absent where rc" "2" "$RC"
run_hit "$F" --where="X" --bogus
assert_eq "unknown flag rc" "2" "$RC"
assert_eq "unknown flag stderr" "unknown flag: --bogus" "$ERR"
mkdir -p "$B/nested"
printf -- '---\ntype: bug\n---\n\nelsewhere\n' > "$ROOT/2026-09-05-elsewhere.md"
printf -- '---\ntype: bug\n---\n\nnested\n' > "$B/nested/2026-09-05-nested.md"
run_hit "$ROOT/2026-09-05-elsewhere.md" --where="X"
assert_eq "outside the bugs dir rc" "2" "$RC"
assert_eq "outside the bugs dir stderr" "not an open bug record: 2026-09-05-elsewhere" "$ERR"
run_hit "$B/nested/2026-09-05-nested.md" --where="X"
assert_eq "nested subdirectory rc" "2" "$RC"
assert_eq "nested subdirectory stderr" "not an open bug record: 2026-09-05-nested" "$ERR"
assert_eq "nothing written" "$SUM_BEFORE" "$(cksum "$B"/*.md "$B"/closed/*.md)"
assert_contains "open record still hits: 1" "^hits: 1$" "$(fence_of "$F")"

begin_test "bug --review writes the back-link right after found_during"
bare_root
file_bug "Review-sourced symptom" --review="2026-10-18-branch-x" --requirement="r" --layer=code --worked-before="v1" --verdict=bug --tags="ui"
assert_eq "rc" "0" "$RC"
KEYS=$(awk '/^---$/{c++; next} c==1{print}' "$OUT" | sed 's/:.*//' | tr '\n' ' ')
assert_eq "key order" "type created captured_at status verdict found_during review requirement layer worked_before hits fixed_by tags " "$KEYS"
assert_contains "review value" "^review: 2026-10-18-branch-x$" "$(cat "$OUT")"

begin_test "bug with an empty --review writes no review line"
bare_root
file_bug "Empty review flag" --review=
assert_eq "rc" "0" "$RC"
assert_eq "no review line" "0" "$(grep -c '^review:' "$OUT")"

finish_tests test-bugs-scripts
