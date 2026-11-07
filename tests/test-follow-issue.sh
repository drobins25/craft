#!/bin/bash
# test-follow-issue.sh - Tests for follow-issue.py
# The check gives every planning entry point one verdict about whether a cycle
# still matches its tracker issue; keep and update are the only writes the
# user's answer can cause, and they touch only their own cycle.yaml lines and
# the README marks, never an issue copy.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

FOLLOW="$SCRIPTS_DIR/follow-issue.py"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FIRST=dro-21-issue-2026-10-31T1840Z.md

# cycle <name> [tool-cell] -> CYCLE_DIR with one issue copy; STAGED is a copy of it
cycle() {
  CYCLE_DIR="$WORK/$1/7-intake"
  mkdir -p "$CYCLE_DIR/context"
  cat > "$CYCLE_DIR/cycle.yaml" <<'FIX'
name: intake
title: "Intake"
status: planning
created: 2026-10-31
updated: 2026-10-31
target: Hand the story over
focus: Handoff
source_concept:
source_issue: 'DRO-21'
authorized_stage: 'build'
go_author: 'Darin'
go_date: '2026-10-31T18:40:00.000Z'

goals:
  - Make the handoff invisible
notes: keep this line
FIX
  cat > "$CYCLE_DIR/context/$FIRST" <<'FIX'
# DRO-21: Hand the story over

Source: https://linear.app/x/issue/DRO-21
Status at retrieval: In Progress (copied for reference; never a permission)

Make the handoff invisible.
Second line.
FIX
  cat > "$CYCLE_DIR/context/README.md" <<FIX
# DRO-21 context

| File | What | Retrieved | Tool |
|---|---|---|---|
| $FIRST | Issue title, status and description | 2026-10-31T18:40:12Z | ${2:-linear} |
FIX
  CTX="$CYCLE_DIR/context"
  YAML="$CYCLE_DIR/cycle.yaml"
  STAGED="$WORK/$1-staged.md"
  cp "$CTX/$FIRST" "$STAGED"
  cp "$YAML" "$WORK/$1-yaml.before"
  cp "$CTX/README.md" "$WORK/$1-readme.before"
  BEFORE_YAML="$WORK/$1-yaml.before"
  BEFORE_README="$WORK/$1-readme.before"
}

# run <args...> -> stdout in $OUT, exit code in $CODE, stderr in $ERR
run() {
  set +e
  OUT=$(python3 "$FOLLOW" "$@" 2>"$WORK/stderr")
  CODE=$?
  set -e
  ERR=$(cat "$WORK/stderr")
}

field() {
  printf '%s\n' "$OUT" | sed -n "s/^$1=//p"
}

lines() {
  printf '%s\n' "$OUT" | wc -l | tr -d ' '
}

# edit_staged <sed-expr> -> the staged issue with its text edited
edit_staged() {
  sed -i.bak "$1" "$STAGED"
  rm -f "$STAGED.bak"
}

# sums <dir> -> cksum of every issue copy
sums() {
  (cd "$1" && for f in $(ls | grep -- '-issue-'); do cksum "$f"; done)
}

echo "=== test-follow-issue.sh ==="
echo ""

begin_test "freeform cycle is none"
cycle none
grep -v '^source_issue\|^authorized_stage\|^go_author\|^go_date' "$BEFORE_YAML" > "$YAML"
cp "$YAML" "$WORK/none-free.yaml"
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "exits 0" "0" "$CODE"
assert_eq "ten lines" "10" "$(lines)"
assert_eq "verdict none" "none" "$(field verdict)"
assert_eq "cycle number empty" "" "$(field cycle)"
assert_eq "key empty" "" "$(field key)"
assert_eq "say empty" "" "$(field say)"
assert_eq "yaml untouched" "" "$(diff "$WORK/none-free.yaml" "$YAML")"
assert_eq "readme untouched" "" "$(diff "$BEFORE_README" "$CTX/README.md")"
assert_eq "no copy written" "1" "$(ls "$CTX" | grep -c -- '-issue-')"

begin_test "unchanged issue is current and silent"
cycle same
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "exits 0" "0" "$CODE"
assert_eq "ten lines" "10" "$(lines)"
assert_eq "verdict" "current" "$(field verdict)"
assert_eq "key" "DRO-21" "$(field key)"
assert_eq "cycle number" "7" "$(field cycle)"
assert_eq "say empty" "" "$(field say)"
assert_eq "yaml byte-identical" "" "$(cmp "$BEFORE_YAML" "$YAML" 2>&1)"
assert_eq "readme byte-identical" "" "$(cmp "$BEFORE_README" "$CTX/README.md" 2>&1)"
assert_eq "no new file" "2" "$(ls "$CTX" | wc -l | tr -d ' ')"

begin_test "status, source and type differences are still current"
cycle hdr
sed -i.bak -e 's|^Status at retrieval:.*|Status at retrieval: Done|' -e 's|^Source:.*|Source: https://other/DRO-21|' "$STAGED"
rm -f "$STAGED.bak"
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "verdict" "current" "$(field verdict)"
assert_eq "no new file" "2" "$(ls "$CTX" | wc -l | tr -d ' ')"

begin_test "edited issue writes a copy, the record and the card fields"
cycle edit
edit_staged 's|^# DRO-21: Hand the story over|# DRO-21: Hand the story over, fast|;s|^Second line\.|Second line, rewritten.|'
sed -i.bak 's|^Status at retrieval:.*|&\nType: Story|' "$STAGED"
rm -f "$STAGED.bak"
run check "$CYCLE_DIR" --issue "$STAGED" --tool "linear MCP" --now 2026-11-02T10:15:30Z
NEW="$CTX/dro-21-issue-2026-11-02T1015Z.md"
assert_eq "exits 0" "0" "$CODE"
assert_eq "ten lines" "10" "$(lines)"
assert_eq "verdict" "changed" "$(field verdict)"
assert_eq "key" "DRO-21" "$(field key)"
assert_eq "cycle" "7" "$(field cycle)"
assert_eq "old title" "Hand the story over" "$(field old_title)"
assert_eq "new title" "Hand the story over, fast" "$(field new_title)"
assert_eq "changed lines" "1" "$(field changed_lines)"
assert_eq "first changed" "Second line, rewritten." "$(field first_changed)"
assert_eq "as of" "Nov 2" "$(field as_of)"
assert_eq "issue type" "Story" "$(field issue_type)"
assert_eq "say empty" "" "$(field say)"
assert_eq "copy is the staged text" "" "$(cmp "$STAGED" "$NEW" 2>&1)"
assert_eq "readme row" "| dro-21-issue-2026-11-02T1015Z.md | Issue text changed since 2026-10-31T1840Z | 2026-11-02T10:15:30Z | linear MCP |" "$(tail -1 "$CTX/README.md")"
assert_eq "record line" "1" "$(grep -c "^issue_changed: '2026-11-02T1015Z'$" "$YAML")"
assert_eq "record sits after the tracker keys" "go_date: '2026-10-31T18:40:00.000Z'" "$(grep -B1 '^issue_changed' "$YAML" | head -1)"
assert_eq "only the record was added" "1" "$(diff "$BEFORE_YAML" "$YAML" | grep -c '^[<>]')"

begin_test "a second check on the same text is still changed and writes nothing more"
cp "$YAML" "$WORK/edit-yaml.after"
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:16:30Z
assert_eq "verdict" "changed" "$(field verdict)"
assert_eq "no third copy" "2" "$(ls "$CTX" | grep -c -- '-issue-')"
assert_eq "yaml unchanged" "" "$(cmp "$WORK/edit-yaml.after" "$YAML" 2>&1)"

begin_test "title-only change"
cycle title
edit_staged 's|^# DRO-21: Hand the story over|# DRO-21: A new name|'
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "verdict" "changed" "$(field verdict)"
assert_eq "new title" "A new name" "$(field new_title)"
assert_eq "no changed lines" "0" "$(field changed_lines)"
assert_eq "no first changed" "" "$(field first_changed)"

begin_test "a removed line reports its first removed line"
cycle gone
edit_staged '/^Second line\./d'
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "changed lines" "1" "$(field changed_lines)"
assert_eq "first changed" "Second line." "$(field first_changed)"

begin_test "unreadable without a record writes nothing"
cycle unread
for reason in no-tools read-failed not-found; do
  run check "$CYCLE_DIR" --unreadable "$reason" --now 2026-11-02T10:15:30Z
  assert_eq "$reason exits 0" "0" "$CODE"
  assert_eq "$reason ten lines" "10" "$(lines)"
  assert_eq "$reason verdict" "unreadable" "$(field verdict)"
done
run check "$CYCLE_DIR" --unreadable no-tools
assert_eq "no-tools say" "I can't reach DRO-21 from here, so I can't tell whether cycle 7 still matches it." "$(field say)"
run check "$CYCLE_DIR" --unreadable read-failed
assert_eq "read-failed say" "Reading DRO-21 failed, so I can't tell whether cycle 7 still matches it." "$(field say)"
run check "$CYCLE_DIR" --unreadable not-found
assert_eq "not-found say" "DRO-21 isn't on the tracker anymore, so I can't tell whether cycle 7 still matches it." "$(field say)"
assert_eq "yaml byte-identical" "" "$(cmp "$BEFORE_YAML" "$YAML" 2>&1)"
assert_eq "readme byte-identical" "" "$(cmp "$BEFORE_README" "$CTX/README.md" 2>&1)"

begin_test "unreadable with a record is changed"
cycle unrec
sed -i.bak "s|^go_date:.*|&\nissue_changed: '2026-11-02T1015Z'|" "$YAML"
rm -f "$YAML.bak"
cp "$YAML" "$WORK/unrec-yaml.planted"
cp "$CTX/$FIRST" "$CTX/dro-21-issue-2026-11-02T1015Z.md"
sed -i.bak 's|^Second line\.|Second line, new.|' "$CTX/dro-21-issue-2026-11-02T1015Z.md"
rm -f "$CTX/dro-21-issue-2026-11-02T1015Z.md.bak"
run check "$CYCLE_DIR" --unreadable read-failed
assert_eq "verdict" "changed" "$(field verdict)"
assert_eq "new title" "Hand the story over" "$(field new_title)"
assert_eq "first changed" "Second line, new." "$(field first_changed)"
assert_eq "yaml untouched" "" "$(cmp "$WORK/unrec-yaml.planted" "$YAML" 2>&1)"

begin_test "unreadable on a paste cycle is current"
cycle paste "pasted into the session"
run check "$CYCLE_DIR" --unreadable no-tools
assert_eq "verdict" "current" "$(field verdict)"
assert_eq "say empty" "" "$(field say)"
assert_eq "yaml byte-identical" "" "$(cmp "$BEFORE_YAML" "$YAML" 2>&1)"
assert_eq "readme byte-identical" "" "$(cmp "$BEFORE_README" "$CTX/README.md" 2>&1)"

begin_test "legacy two unmarked copies are changed"
cycle legacy
sed 's|^Second line\.|Second line, v2.|' "$CTX/$FIRST" > "$CTX/dro-21-issue-2026-11-01T0900Z.md"
echo "| dro-21-issue-2026-11-01T0900Z.md | Issue text changed since 2026-10-31T1840Z | 2026-11-01T09:00:00Z | linear |" >> "$CTX/README.md"
cp "$CTX/dro-21-issue-2026-11-01T0900Z.md" "$STAGED"
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "verdict" "changed" "$(field verdict)"
assert_eq "record is the newest copy" "1" "$(grep -c "^issue_changed: '2026-11-01T0900Z'$" "$YAML")"
assert_eq "no copy written" "2" "$(ls "$CTX" | grep -c -- '-issue-')"

begin_test "keep marks, clears, and the next change returns"
cycle keep
edit_staged 's|^Second line\.|Second line, v2.|'
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
SECOND=dro-21-issue-2026-11-02T1015Z.md
before_sums=$(sums "$CTX")
run keep "$CYCLE_DIR"
assert_eq "exits 0" "0" "$CODE"
assert_eq "one line" "1" "$(lines)"
assert_eq "say" "Planning against cycle 7 as it is. I'll ask again only if DRO-21 changes again." "$(field say)"
assert_eq "record removed" "0" "$(grep -c '^issue_changed' "$YAML")"
assert_eq "yaml is back to the original" "" "$(cmp "$BEFORE_YAML" "$YAML" 2>&1)"
assert_eq "first copy superseded" "1" "$(grep -c "^| $FIRST | Issue title, status and description (superseded) |" "$CTX/README.md")"
assert_eq "newest copy current" "1" "$(grep -c "^| $SECOND | Issue text changed since 2026-10-31T1840Z (current) |" "$CTX/README.md")"
assert_eq "copies unchanged" "$before_sums" "$(sums "$CTX")"
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T11:00:00Z
assert_eq "same text is current" "current" "$(field verdict)"
assert_eq "no new copy" "2" "$(ls "$CTX" | grep -c -- '-issue-')"
edit_staged 's|^Second line, v2\.|Second line, v3.|'
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T12:00:00Z
assert_eq "new text is changed again" "changed" "$(field verdict)"
assert_eq "old title" "Hand the story over" "$(field old_title)"
assert_eq "first changed against the kept copy" "Second line, v3." "$(field first_changed)"

# values <file> <line>... : write a values file, one line per argument
values() {
  local file="$1"; shift
  printf '%s\n' "$@" > "$file"
}

begin_test "update rewrites only its fields"
cycle upd
edit_staged 's|^# DRO-21: Hand the story over|# DRO-21: Hand it over, quietly|;s|^Second line\.|Second line, rewritten.|'
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
cp "$YAML" "$WORK/upd-yaml.recorded"
before_sums=$(sums "$CTX")
values "$WORK/upd-values.txt" "target: Quiet handoff" "focus: Quiet" \
  "goal: Handoff needs no ceremony" "goal: Second line, rewritten."
run update "$CYCLE_DIR" --values "$WORK/upd-values.txt" --now 2026-11-03T08:00:00Z
assert_eq "exits 0" "0" "$CODE"
assert_eq "one line" "1" "$(lines)"
assert_eq "say" "Cycle 7 now follows DRO-21 as of Nov 2." "$(field say)"
assert_eq "title line comes from the recorded copy" "title: 'Hand it over, quietly'" "$(grep '^title:' "$YAML")"
assert_eq "target line" "target: 'Quiet handoff'" "$(grep '^target:' "$YAML")"
assert_eq "focus line" "focus: 'Quiet'" "$(grep '^focus:' "$YAML")"
assert_eq "updated line" "updated: 2026-11-03" "$(grep '^updated:' "$YAML")"
assert_eq "goals block" "goals:
  - 'Handoff needs no ceremony'
  - 'Second line, rewritten.'
notes: keep this line" "$(sed -n '/^goals:/,$p' "$YAML")"
for keep_line in "name: intake" "status: planning" "created: 2026-10-31" "source_concept:" \
  "source_issue: 'DRO-21'" "authorized_stage: 'build'" "go_author: 'Darin'" \
  "go_date: '2026-10-31T18:40:00.000Z'" "notes: keep this line"; do
  assert_eq "kept: $keep_line" "1" "$(grep -c -x -- "$keep_line" "$YAML")"
done
assert_eq "record removed" "0" "$(grep -c '^issue_changed' "$YAML")"
assert_eq "only expected lines differ" "$(printf '%s\n' \
  '< title: "Intake"' '< updated: 2026-10-31' '< target: Hand the story over' '< focus: Handoff' \
  '< - Make the handoff invisible' \
  "> title: 'Hand it over, quietly'" '> updated: 2026-11-03' "> target: 'Quiet handoff'" "> focus: 'Quiet'" \
  "> - 'Handoff needs no ceremony'" "> - 'Second line, rewritten.'" | sort)" \
  "$(diff "$BEFORE_YAML" "$YAML" | grep '^[<>]' | sed 's/^\([<>]\)  */\1 /' | sort)"
assert_eq "copies unchanged" "$before_sums" "$(sums "$CTX")"
assert_eq "first superseded" "1" "$(grep -c "(superseded) |" "$CTX/README.md")"
assert_eq "newest current" "1" "$(grep -c "(current) |" "$CTX/README.md")"
assert_eq "check now current" "current" "$(python3 "$FOLLOW" check "$CYCLE_DIR" --issue "$STAGED" --tool linear | sed -n 's/^verdict=//p')"

begin_test "update takes the title from the recorded copy and keeps the label"
cycle lab
sed -i.bak "s|^title: .*|title: 'Cycle 07: Intake'|" "$YAML" && rm -f "$YAML.bak"
edit_staged "s|^# DRO-21: Hand the story over|# DRO-21: Login fails: \"Remember me\" ignored #SSO, it's 'odd'|"
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
values "$WORK/lab-values.txt" "target: T" "focus: F" "goal: G"
run update "$CYCLE_DIR" --values "$WORK/lab-values.txt" --now 2026-11-03T08:00:00Z
assert_eq "exits 0" "0" "$CODE"
assert_eq "label kept, title exact" "title: 'Cycle 07: Login fails: \"Remember me\" ignored #SSO, it''s ''odd'''" "$(grep '^title:' "$YAML")"

begin_test "a title line in the values file wins"
cycle win
edit_staged 's|^# DRO-21: Hand the story over|# DRO-21: From the ticket|'
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
values "$WORK/win-values.txt" "title: Corrected by the user" "target: T" "focus: F" "goal: G"
run update "$CYCLE_DIR" --values "$WORK/win-values.txt" --now 2026-11-03T08:00:00Z
assert_eq "exits 0" "0" "$CODE"
assert_eq "user's title lands" "title: 'Corrected by the user'" "$(grep '^title:' "$YAML")"

begin_test "update replaces a block focus whole"
cycle blk
python3 - "$YAML" <<'INNER'
import sys
p = sys.argv[1]
t = open(p).read().replace("focus: Handoff\n", "focus: |\n  first\n\n  second\n")
open(p, "w").write(t)
INNER
edit_staged 's|^Second line\.|Second line, v2.|'
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
values "$WORK/blk-values.txt" "target: T" "focus: One line now" "goal: G"
run update "$CYCLE_DIR" --values "$WORK/blk-values.txt" --now 2026-11-03T08:00:00Z
assert_eq "exits 0" "0" "$CODE"
assert_eq "focus is one line" "focus: 'One line now'" "$(grep '^focus:' "$YAML")"
assert_eq "no block leftovers" "0" "$(grep -c '^  first\|^  second' "$YAML")"
assert_eq "the next key follows" "source_concept:" "$(grep -A1 '^focus:' "$YAML" | tail -1)"

begin_test "update refuses bad values files and the old flags"
cycle bad
edit_staged 's|^Second line\.|Second line, v2.|'
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
cp "$YAML" "$WORK/bad-yaml.recorded"
cp "$CTX/README.md" "$WORK/bad-readme.recorded"
refuse() { # refuse <desc> <args...>
  local desc="$1"; shift
  run update "$CYCLE_DIR" "$@"
  assert_eq "$desc: exits 1" "1" "$CODE"
  assert_eq "$desc: prints nothing" "" "$OUT"
  assert_eq "$desc: one stderr line" "1" "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')"
  assert_eq "$desc: yaml untouched" "" "$(cmp "$WORK/bad-yaml.recorded" "$YAML" 2>&1)"
  assert_eq "$desc: readme untouched" "" "$(cmp "$WORK/bad-readme.recorded" "$CTX/README.md" 2>&1)"
}
values "$WORK/v-nofocus.txt" "target: X" "goal: G"
refuse "no focus" --values "$WORK/v-nofocus.txt"
values "$WORK/v-nogoal.txt" "target: X" "focus: F"
refuse "no goal" --values "$WORK/v-nogoal.txt"
values "$WORK/v-notarget.txt" "focus: F" "goal: G"
refuse "no target" --values "$WORK/v-notarget.txt"
values "$WORK/v-empty.txt" "target: X" "focus: F" "goal:   "
refuse "empty goal" --values "$WORK/v-empty.txt"
values "$WORK/v-unknown.txt" "target: X" "focus: F" "goal: G" "colour: red"
refuse "unknown field" --values "$WORK/v-unknown.txt"
values "$WORK/v-good.txt" "target: X" "focus: F" "goal: G"
refuse "missing values file" --values "$WORK/none.txt"
refuse "no --values" --now 2026-11-03T08:00:00Z
refuse "old flags" --title T --target X --focus F --goal G
refuse "old flags beside a values file" --values "$WORK/v-good.txt" --title T
sed -i.bak '/^focus:/d' "$YAML" && rm -f "$YAML.bak"
cp "$YAML" "$WORK/bad-yaml.recorded"
refuse "cycle.yaml without a focus line" --values "$WORK/v-good.txt"

begin_test "update and keep refuse without a record"
cycle norec
run keep "$CYCLE_DIR"
assert_eq "keep exits 1" "1" "$CODE"
assert_eq "keep prints nothing" "" "$OUT"
assert_eq "keep says why on stderr" "1" "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')"
values "$WORK/v-good.txt" "target: X" "focus: F" "goal: G"
run update "$CYCLE_DIR" --values "$WORK/v-good.txt"
assert_eq "update exits 1" "1" "$CODE"
assert_eq "update prints nothing" "" "$OUT"
assert_eq "yaml byte-identical" "" "$(cmp "$BEFORE_YAML" "$YAML" 2>&1)"
assert_eq "readme byte-identical" "" "$(cmp "$BEFORE_README" "$CTX/README.md" 2>&1)"

begin_test "bad input exits 1 with one stderr line and writes nothing"
cycle err
run check "$CYCLE_DIR" --tool linear
assert_eq "no input source" "1" "$CODE"
assert_eq "one stderr line" "1" "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')"
run check "$CYCLE_DIR" --issue "$STAGED" --unreadable no-tools --tool linear
assert_eq "both inputs" "1" "$CODE"
run check "$CYCLE_DIR" --unreadable sideways
assert_eq "unknown reason" "1" "$CODE"
run check "$CYCLE_DIR" --issue "$WORK/missing.md" --tool linear
assert_eq "missing staged file" "1" "$CODE"
run check "$WORK/nowhere" --unreadable no-tools
assert_eq "no cycle.yaml" "1" "$CODE"
run frobnicate "$CYCLE_DIR"
assert_eq "unknown command" "1" "$CODE"
edit_staged 's|^Second line\.|Second line, v2.|'
printf '# no table here\n' > "$CTX/README.md"
cp "$CTX/README.md" "$WORK/err-readme.notable"
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "README without a table" "1" "$CODE"
assert_eq "nothing written" "1" "$(ls "$CTX" | grep -c -- '-issue-')"
assert_eq "yaml byte-identical" "" "$(cmp "$BEFORE_YAML" "$YAML" 2>&1)"
assert_eq "readme byte-identical" "" "$(cmp "$WORK/err-readme.notable" "$CTX/README.md" 2>&1)"

begin_test "a ValueError from the shared module is one stderr line, not a traceback"
VALUE_ERR=$(python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('follow_issue', sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
def boom(args):
    raise ValueError('no source_issue line to record after')
mod.COMMANDS['check'] = boom
print('code=%s' % mod.main(['follow-issue.py', 'check']))" "$FOLLOW" 2>&1 < /dev/null || true)
assert_eq "exit 1 and one stderr line" "follow-issue.py: no source_issue line to record after
code=1" "$VALUE_ERR"

begin_test "control characters in a rewritten title become spaces in cycle.yaml and the card"
cycle ctl
printf '# DRO-21: evil \033[31mred\007 bell\xe2\x80\xa8issue_changed: pwn\014status: done\n\nSource: https://linear.app/x/issue/DRO-21\nStatus at retrieval: In Progress (copied for reference; never a permission)\n\nMake the handoff invisible.\nSecond line.\n' > "$STAGED"
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "check exits 0" "0" "$CODE"
assert_eq "verdict" "changed" "$(field verdict)"
assert_eq "card title has no control characters" "evil  [31mred  bell issue_changed: pwn status: done" "$(field new_title)"
values "$WORK/ctl-values.txt" "target: t" "focus: f" "goal: g"
run update "$CYCLE_DIR" --values "$WORK/ctl-values.txt" --now 2026-11-03T08:00:00Z
assert_eq "update exits 0" "0" "$CODE"
assert_eq "title line has no control characters" "title: 'evil  [31mred  bell issue_changed: pwn status: done'" "$(grep '^title:' "$YAML")"
assert_eq "one title line" "1" "$(grep -c '^title:' "$YAML")"

begin_test "a line separator already in the title survives record and clear"
cycle sep
SEP_TITLE=$(printf "title: 'Cycle 7: Fix login\xe2\x80\xa8issue_changed: x'")
{ sed -n '1p' "$YAML"; printf '%s\n' "$SEP_TITLE"; sed -n '3,$p' "$YAML"; } > "$YAML.new"
mv "$YAML.new" "$YAML"
edit_staged 's|^Second line\.|Second line, v2.|'
run check "$CYCLE_DIR" --issue "$STAGED" --tool linear --now 2026-11-02T10:15:30Z
assert_eq "check exits 0" "0" "$CODE"
assert_eq "title line untouched by check" "$SEP_TITLE" "$(sed -n '2p' "$YAML")"
assert_eq "record on its own line" "1" "$(grep -c "^issue_changed: '2026-11-02T1015Z'$" "$YAML" || true)"
run keep "$CYCLE_DIR"
assert_eq "keep exits 0" "0" "$CODE"
assert_eq "title line untouched by keep" "$SEP_TITLE" "$(sed -n '2p' "$YAML")"
assert_eq "record removed" "0" "$(grep -c '^issue_changed' "$YAML" || true)"

echo ""
finish_tests
