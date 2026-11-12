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
printf -- '---\nname: n\nstatus: planning\n---\nbody no newline' > "$ROOT/nonl.md"
BEFORE="$(sum "$ROOT/nonl.md")"
OUT="$(bash "$STAGE" "$ROOT/nonl.md" clear)"
check_eq "no final newline: cleared line printed" "Planning stage cleared: $ROOT/nonl.md" "$(printf '%s\n' "$OUT" | tail -1)"
check_eq "no final newline: bytes unchanged" "$BEFORE" "$(sum "$ROOT/nonl.md")"

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
check_eq "no temp files left behind" "0" "$(find "$ROOT" -name '.planning-stage.*' | wc -l | tr -d ' ')"

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

# --- plan-chunks wiring: one lint per flow file ----------------------------------
SKILL="$REPO/skills/plan-chunks/SKILL.md"
AGENT="$REPO/agents/plan-chunks-agent.md"

echo "Test: the plan-chunks skill calls the planning-stage script"
if grep -qF 'hooks/scripts/planning-stage.sh' "$SKILL"; then pass "skill calls planning-stage.sh"; else fail "skill calls planning-stage.sh"; fi

echo "Test: the planner template carries the field"
if grep -q '^planning_stage:' "$AGENT"; then pass "agent template has planning_stage"; else fail "agent template has planning_stage"; fi

echo ""
echo "=== Results (test-planning-stage): $PASS_COUNT passed, $FAIL_COUNT failed ==="
[ "$FAIL_COUNT" -eq 0 ]
