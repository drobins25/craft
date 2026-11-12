#!/bin/bash
# test-planning-stage.sh - planning-stage.sh writes, rewrites and clears a story's
# planning_stage frontmatter field, and update-story-status.sh clears it on the way
# to ready, active or complete.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/.."
STAGE="$REPO/hooks/scripts/planning-stage.sh"
UPDATE="$REPO/hooks/scripts/update-story-status.sh"
STDOUT_FIXTURE="$SCRIPT_DIR/fixtures/planning-stage-stdout.ts"

PASS_COUNT=0; FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Expected: $2"; [ -n "${3:-}" ] && echo "    Got:      $3"; return 0; }
check_eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

sum() { cksum < "$1"; }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/.craft/cycles/1-c/stories"
STORIES="$ROOT/.craft/cycles/1-c/stories"
printf 'ACTIVE_CYCLE="1-c"\n' > "$ROOT/.craft/.global-state"
printf 'CURRENT_STORY=""\n' > "$ROOT/.craft/cycles/1-c/.state"

# A fresh story whose body carries a decoy planning_stage line and a --- rule.
make_story() {
  cat > "$1" <<'STORY'
---
name: t
title: "T"
status: planning
updated: 2026-02-14
chunks_total: 0
---

# Story: T

planning_stage: x

---

after the rule
STORY
}

count_field() { grep -c '^planning_stage:' "$1" || true; }
front() { awk 'NR==1&&/^---$/{b=1;next} b&&/^---$/{exit} b{print}' "$1"; }

echo "=== test-planning-stage.sh ==="

S="$STORIES/1-t.md"
make_story "$S"
BODY_BEFORE="$(sed -n '/^# Story: T/,$p' "$S")"
UPDATED_BEFORE="$(grep '^updated:' "$S")"
GS_BEFORE="$(sum "$ROOT/.craft/.global-state")"; ST_BEFORE="$(sum "$ROOT/.craft/cycles/1-c/.state")"

echo "Test: writes the stage after status"
OUT="$(bash "$STAGE" "$S" planner)"; RC=$?
check_eq "exits 0" "0" "$RC"
check_eq "stdout ends with the set line" "Planning stage set to planner: $S" "$(printf '%s\n' "$OUT" | tail -1)"
check_eq "stage line follows status" "status: planning
planning_stage: planner" "$(front "$S" | grep -A1 '^status:')"
check_eq "body decoy untouched after write" "$BODY_BEFORE" "$(sed -n '/^# Story: T/,$p' "$S")"

echo "Test: rewrites in place"
OUT="$(bash "$STAGE" "$S" plan-check)"
check_eq "one frontmatter stage line" "1" "$(front "$S" | grep -c '^planning_stage:' || true)"
check_eq "value is plan-check" "planning_stage: plan-check" "$(front "$S" | grep '^planning_stage:')"
check_eq "body decoy untouched after rewrite" "$BODY_BEFORE" "$(sed -n '/^# Story: T/,$p' "$S")"

echo "Test: clears the field"
OUT="$(bash "$STAGE" "$S" clear)"
check_eq "stdout ends with the cleared line" "Planning stage cleared: $S" "$(printf '%s\n' "$OUT" | tail -1)"
check_eq "no stage line in frontmatter" "0" "$(front "$S" | grep -c '^planning_stage:' || true)"
check_eq "body decoy untouched after clear" "$BODY_BEFORE" "$(sed -n '/^# Story: T/,$p' "$S")"
check_eq "updated line untouched" "$UPDATED_BEFORE" "$(grep '^updated:' "$S")"

echo "Test: clear without a field is a no-op"
BEFORE="$(sum "$S")"
bash "$STAGE" "$S" clear >/dev/null; RC=$?
check_eq "exits 0" "0" "$RC"
check_eq "bytes unchanged" "$BEFORE" "$(sum "$S")"

echo "Test: write then clear restores the file byte for byte"
make_story "$ROOT/orig.md"; make_story "$ROOT/ref.md"
bash "$STAGE" "$ROOT/orig.md" triage >/dev/null
bash "$STAGE" "$ROOT/orig.md" clear >/dev/null
check_eq "round trip is identical" "$(sum "$ROOT/ref.md")" "$(sum "$ROOT/orig.md")"

echo "Test: inserts before the closing rule when there is no status line"
printf -- '---\nname: n\n---\n\nbody\n---\n' > "$ROOT/nostatus.md"
bash "$STAGE" "$ROOT/nostatus.md" direction >/dev/null
check_eq "stage sits inside the first block, before its closing rule" "---
name: n
planning_stage: direction
---

body
---" "$(cat "$ROOT/nostatus.md")"

echo "Test: a story with CRLF line endings is set and cleared"
printf -- '---\r\nname: w\r\nstatus: planning\r\n---\r\nbody\r\n' > "$ROOT/crlf.md"
cp "$ROOT/crlf.md" "$ROOT/crlf-ref.md"
set +e; OUT="$(bash "$STAGE" "$ROOT/crlf.md" planner 2>&1)"; RC=$?; set -e
check_eq "CRLF set exits 0" "0" "$RC"
check_eq "CRLF stage line written" "1" "$(grep -c '^planning_stage: planner' "$ROOT/crlf.md" || true)"
set +e; bash "$STAGE" "$ROOT/crlf.md" clear >/dev/null 2>&1; RC=$?; set -e
check_eq "CRLF clear exits 0" "0" "$RC"
check_eq "CRLF round trip is identical" "$(sum "$ROOT/crlf-ref.md")" "$(sum "$ROOT/crlf.md")"

echo "Test: rejects an unknown stage"
BEFORE="$(sum "$S")"
for bad in ready idle ""; do
  set +e; OUT="$(bash "$STAGE" "$S" "$bad" 2>&1)"; RC=$?; set -e
  check_eq "'$bad' exits 1" "1" "$RC"
  check_eq "'$bad' prints an Error line" "Error:" "$(printf '%s\n' "$OUT" | head -1 | cut -c1-6)"
done
check_eq "file unchanged after rejects" "$BEFORE" "$(sum "$S")"

echo "Test: rejects a missing file and a file with no frontmatter"
set +e; bash "$STAGE" "$ROOT/nope.md" planner >/dev/null 2>&1; RC=$?; set -e
check_eq "missing file exits 1" "1" "$RC"
[ ! -e "$ROOT/nope.md" ] && pass "no file created" || fail "no file created"
printf '# no frontmatter\n\nbody\n' > "$ROOT/bare.md"
BEFORE="$(sum "$ROOT/bare.md")"
set +e; bash "$STAGE" "$ROOT/bare.md" planner >/dev/null 2>&1; RC=$?; set -e
check_eq "no frontmatter exits 1" "1" "$RC"
check_eq "no-frontmatter file unchanged" "$BEFORE" "$(sum "$ROOT/bare.md")"
check_eq "no temp files left behind" "0" "$(find "$ROOT" -name '*.tmp*' | wc -l | tr -d ' ')"

echo "Test: relative path resolves from PWD"
OUT="$(cd "$STORIES" && bash "$STAGE" 1-t.md planner)"
check_eq "stdout names the absolute path" "Planning stage set to planner: $STORIES/1-t.md" "$(printf '%s\n' "$OUT" | tail -1)"
bash "$STAGE" "$S" clear >/dev/null

echo "Test: no state file changes"
check_eq ".global-state unchanged" "$GS_BEFORE" "$(sum "$ROOT/.craft/.global-state")"
check_eq "cycle .state unchanged" "$ST_BEFORE" "$(sum "$ROOT/.craft/cycles/1-c/.state")"

echo "Test: the real output matches the shared fixture"
SET_LITERAL="$(sed -n "s/^export const SET_LINE = '\(.*\)'$/\1/p" "$STDOUT_FIXTURE")"
CLEARED_LITERAL="$(sed -n "s/^export const CLEARED_LINE = '\(.*\)'$/\1/p" "$STDOUT_FIXTURE")"
FIX="$ROOT/fix.md"; make_story "$FIX"
REAL_SET="$(bash "$STAGE" "$FIX" planner | tail -1)"
REAL_CLEARED="$(bash "$STAGE" "$FIX" clear | tail -1)"
check_eq "set line" "$SET_LITERAL" "$(printf '%s\n' "$REAL_SET" | sed "s|: $FIX\$|: /work/p/.craft/cycles/c/stories/t.md|")"
check_eq "cleared line" "$CLEARED_LITERAL" "$(printf '%s\n' "$REAL_CLEARED" | sed "s|: $FIX\$|: /work/p/.craft/cycles/c/stories/t.md|")"

echo "Test: status flip clears first"
for st in ready active complete; do
  F="$ROOT/flip-$st.md"; make_story "$F"; bash "$STAGE" "$F" triage >/dev/null
  OUT="$(bash "$UPDATE" "$F" "$st")"
  check_eq "$st: no stage field" "0" "$(front "$F" | grep -c '^planning_stage:' || true)"
  check_eq "$st: status set" "status: $st" "$(grep '^status:' "$F")"
  check_eq "$st: final stdout line unchanged" "Story status updated to '$st': $F" "$(printf '%s\n' "$OUT" | tail -1)"
  check_eq "$st: body decoy survives" "$BODY_BEFORE" "$(sed -n '/^# Story: T/,$p' "$F")"
done

echo "Test: other statuses keep the stage"
for st in backlog planning; do
  F="$ROOT/keep-$st.md"; make_story "$F"; bash "$STAGE" "$F" triage >/dev/null
  bash "$UPDATE" "$F" "$st" >/dev/null
  check_eq "$st: stage kept" "planning_stage: triage" "$(front "$F" | grep '^planning_stage:')"
done

# --- plan-chunks skill and planner agent wiring ---------------------------------
SKILL="$REPO/skills/plan-chunks/SKILL.md"
AGENT="$REPO/agents/plan-chunks-agent.md"
CMD='${CLAUDE_PLUGIN_ROOT}/hooks/scripts/planning-stage.sh [story-file]'

# span FROM TO: the lines of SKILL.md from the first FROM heading up to the TO heading.
span() { sed -n "/^$1/,/^$2/p" "$SKILL"; }
# line_of MARKER: the first SKILL.md line containing the literal MARKER.
line_of() { grep -F -- "$1" "$SKILL" | head -1; }

check_in() { # name needle haystack
  if printf '%s\n' "$3" | grep -qF -- "$2"; then pass "$1"; else fail "$1" "contains: $2" "(absent)"; fi
}

echo "Test: each single-flow phase names its stage write"
check_in "0.4 content-check" "$CMD content-check" "$(span '## Phase 0.4' '## Phase 0.45')"
check_in "0.45 alignment-check" "$CMD alignment-check" "$(span '## Phase 0.45' '## Phase 0.46')"
check_in "0.45 batch alignment-check" "$CMD alignment-check" "$(line_of 'Batch mode (`MODE: batch`):** Flag stories')"
check_in "0.46 direction" "$CMD direction" "$(span '## Phase 0.46' '## Phase 0.5')"
check_in "0.5 direction" "$CMD direction" "$(span '## Phase 0.5' '## Single-Story Planning')"
check_in "0.5 batch direction" "$CMD direction" "$(line_of 'Batch mode (`MODE: batch`):** Present all story sparks')"
check_in "S-1 planner" "$CMD planner" "$(span '### S-1' '### S-2')"
check_in "S-2 plan-check" "$CMD plan-check" "$(span '### S-2' '### S-3')"
check_in "S-3 triage" "$CMD triage" "$(span '### S-3' '### S-4')"

echo "Test: each batch phase names its stage write"
check_in "M-1 content-check" "$CMD content-check" "$(span '### M-1:' '### M-1b')"
check_in "M-2 planner (teams)" "$CMD planner" "$(span '#### Mode: Agent Teams' '#### Mode: Task Subagents')"
check_in "M-2 planner (subagents)" "$CMD planner" "$(span '#### Mode: Task Subagents' '#### Predecessor Context Handoff')"
check_in "M-3 plan-check" "$CMD plan-check" "$(span '### M-3' '### M-4')"
check_in "Critical Rules triage" "$CMD triage" "$(span '### Critical Rules' '## Reference Notes')"

echo "Test: every named exit names the clear"
CLEAR="$CMD clear"
check_in "0.5 Explore creatively first" "$CLEAR" "$(line_of '**If "Explore creatively first":**')"
check_in "0.5 Adjust the scope" "$CLEAR" "$(line_of '**If "Adjust the scope":**')"
check_in "0.5 Exclude some stories" "$CLEAR" "$(line_of '**If "Exclude some stories":**')"
check_in "S-2 fixes it by hand" "$CLEAR" "$(line_of '**If the user fixes it by hand:**')"
check_in "S-3 blocker stop" "$CLEAR" "$(line_of "If the blocker means the story can't be planned")"
check_in "M-1b hard block cancel" "$CLEAR" "$(line_of '**HARD BLOCK:**')"
check_in "M-1b Cancel batch" "$CLEAR" "$(line_of '**If "Cancel batch":**')"
check_in "M-1b circular dependency" "$CLEAR" "$(line_of '**Circular dependency:**')"
check_in "M-4 Skip them for now" "$CLEAR" "$(line_of 'If "Skip them for now"')"
check_in "M-4 Retry failed stories" "$CLEAR" "$(line_of 'If "Retry failed stories"')"
check_in "M-4 Retry all" "$CLEAR" "$(line_of 'If "Retry all"')"
check_in "BT-5 Reject" "$CLEAR" "$(line_of '- **BT-5: "Reject"**')"
check_in "BT-5 Adjust" "$CLEAR" "$(line_of '- **BT-5: "Adjust"**')"

echo "Test: the ready flip is named as the clear"
check_in "S-5 names the flip" "update-story-status.sh" "$(span '### S-5' '### S-6')"
check_in "S-5 says the flip clears the stage" "also clears the planning stage" "$(span '### S-5' '### S-6')"
check_in "Critical Rules say the flip clears" "also clears the planning stage" "$(span '### Critical Rules' '## Reference Notes')"

echo "Test: R3 rewrites alignment-check and R4 returns to S-1"
FORK="$(sed -n '/^R3\./,/^R4\./p' "$SKILL")"
check_in "R3 alignment-check write" "$CMD alignment-check" "$FORK"
check_in "R4 names the S-1 write" "S-1" "$(line_of 'R4. ')"

echo "Test: the Planning Stage section carries the rules"
check_eq "one section" "1" "$(grep -c '^## Planning Stage$' "$SKILL" || true)"
PS="$(sed -n '/^## Planning Stage$/,/^---$/p' "$SKILL")"
check_in "never edited directly" "Never edit \`planning_stage\` with Edit or Write" "$PS"
check_in "failure runs the clear first" "runs the clear before it is reported" "$PS"
check_in "ready flip clears" "update-story-status.sh" "$PS"
check_in "one call per story in batch" "one call per story" "$PS"
check_eq "section sits after the Go run paragraph" "1" "$(awk '/^\*\*Under a Go run\*\*/{g=NR} /^## Planning Stage$/{p=NR} END{print (g>0 && p>g) ? 1 : 0}' "$SKILL")"
for st in content-check alignment-check direction planner plan-check triage; do
  check_in "section lists $st" "\`$st\`" "$PS"
done

echo "Test: the planner keeps the field"
check_eq "template line after alignment" "alignment: [preserved from original]
planning_stage: [preserved if present]" "$(grep -A1 '^alignment: \[preserved from original\]$' "$AGENT" | head -2)"

echo ""
echo "=== Results (test-planning-stage): $PASS_COUNT passed, $FAIL_COUNT failed ==="
[ "$FAIL_COUNT" -eq 0 ]
