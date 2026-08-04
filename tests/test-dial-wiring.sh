#!/bin/bash
# test-dial-wiring.sh — Doc-grep coverage for /craft:dial wiring
#
# Freezes three contracts:
#   1. Every chrome-devtools browser entry point runs the canonical dial clear
#      (the literal `craft-dial-style` is the fingerprint), and the live sweep
#      fails when a NEW browser-touching file appears that neither carries the
#      clear nor is excluded with a written reason.
#   2. The dial flow files keep their load-bearing rules (timid-candidate rule,
#      degradation rungs, no-AskUserQuestion discipline, injection handles).
#   3. The tweak record template carries dial lineage without disturbing the
#      mockup port path or the Taste Pass counter's input field.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/.."

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Expected: $2"; [ -n "${3:-}" ] && echo "    Got:      $3"; }

# The seven files that must carry the canonical clear, named literally.
CLEAR_CARRIERS=(
  "agents/qa-analyzer.md"
  "agents/ux-analyzer.md"
  "agents/style-analyzer.md"
  "agents/walkthrough-analyzer.md"
  "agents/creative-analyzer.md"
  "skills/browser/SKILL.md"
  "skills/adhoc/references/tweak.md"
)

# Sweep coverage: files the live `grep -rl chrome-devtools` sweep finds that
# must carry the clear (the analyzer agents - their mcpServers frontmatter is
# the machine-readable lowercase marker, so a new browser agent always lands
# in this sweep).
REQUIRED_IN_SWEEP=(
  "agents/qa-analyzer.md"
  "agents/ux-analyzer.md"
  "agents/style-analyzer.md"
  "agents/walkthrough-analyzer.md"
  "agents/creative-analyzer.md"
)

# Sweep hits that deliberately do NOT carry the clear - each with its reason.
# A new hit that is neither required nor excluded fails the sweep until a
# conscious decision puts it in one of these arrays.
EXCLUSIONS=(
  "commands/craft-analyze.md"           # describes analyzer browser access; the analyzers themselves carry the clear
  "commands/craft-init.md"              # drives the browser but always navigates fresh URLs first - the reload wipes any injection
  "commands/references/taste-pass.md"   # prose reference; the actual browsing happens in the tweak flow, which carries the clear
)

echo "=== test-dial-wiring.sh ==="
echo ""

echo "-- Test: clear literal present in all seven browser-touching entry points --"
for f in "${CLEAR_CARRIERS[@]}"; do
  if grep -q "craft-dial-style" "$REPO/$f"; then
    pass "clear named in $f"
  else
    fail "clear named in $f" "literal craft-dial-style present" "absent"
  fi
done

echo "-- Test: live sweep finds no unaccounted browser entry point --"
SWEEP_HITS=$(cd "$REPO" && grep -rl "chrome-devtools" agents/ commands/ skills/ 2>/dev/null | sort)
ACCOUNTED=$(printf '%s\n' "${REQUIRED_IN_SWEEP[@]}" "${EXCLUSIONS[@]}" | sort)
if [ "$SWEEP_HITS" = "$ACCOUNTED" ]; then
  pass "sweep hits equal required-plus-exclusions"
else
  fail "sweep hits equal required-plus-exclusions" "$(echo "$ACCOUNTED" | tr '\n' ' ')" "$(echo "$SWEEP_HITS" | tr '\n' ' ')"
fi
if printf '%s\n' "${REQUIRED_IN_SWEEP[@]}" | grep -q "playwright-browser"; then
  fail "playwright-browser NOT in the required list" "absent - it drives playwright-cli, requiring it would be a false coverage claim" "present"
else
  pass "playwright-browser NOT in the required list"
fi

echo "-- Test: dial-inject.md names all three handles --"
for handle in "craft-dial-style" "craft-dial-panel" "dataset.craftDial"; do
  grep -q "$handle" "$REPO/commands/references/dial-inject.md" && pass "handle $handle named" || fail "handle $handle named"
done

echo "-- Test: tweak template carries dial lineage without disturbing its neighbors --"
grep -q "^dial: " "$REPO/skills/adhoc/references/tweak.md" && pass "dial: field in tweak template" || fail "dial: field in tweak template"
for field in "^mockup: " "^reapplies: " "^grew_from: " "taste:"; do
  grep -q "$field" "$REPO/skills/adhoc/references/tweak.md" && pass "tweak template still carries ${field#^}" || fail "tweak template still carries ${field#^}"
done

echo "-- Test: dial-inline.md states the load-bearing rules --"
grep -q "Never let every position be timid" "$REPO/commands/references/dial-inline.md" && pass "timid-candidate rule stated verbatim" || fail "timid-candidate rule stated verbatim"
for rung in "(a)" "(b)" "(c)" "(d)" "(e)"; do
  grep -qF -- "**$rung" "$REPO/commands/references/dial-inline.md" && pass "degradation rung $rung named" || fail "degradation rung $rung named"
done

echo "-- Test: AskUserQuestion appears in dial files only under a prohibition, and at least once --"
AUQ_LINES=$(grep -h "AskUserQuestion" "$REPO/commands/craft-dial.md" "$REPO/commands/references/dial-inline.md" || true)
AUQ_COUNT=$(printf '%s\n' "$AUQ_LINES" | grep -c "AskUserQuestion" || true)
if [ "$AUQ_COUNT" -eq 0 ]; then
  fail "prohibition lines exist" "at least one AskUserQuestion prohibition" "zero mentions - the prohibitions vanished"
else
  pass "prohibition lines exist ($AUQ_COUNT)"
  BAD=$(printf '%s\n' "$AUQ_LINES" | grep -iv "never" || true)
  if [ -z "$BAD" ]; then
    pass "every AskUserQuestion mention sits on a prohibition line"
  else
    fail "every AskUserQuestion mention sits on a prohibition line" "all lines contain never/NEVER" "$BAD"
  fi
fi

echo "-- Test: routing index lines, warm and cold --"
ORCH="$REPO/reference/orchestration-index.min"
COLD="$REPO/reference/cold-start-index.min"
DIAL_ROW=$(grep "inline-mention dial offer" "$ORCH" || true)
if [ -n "$DIAL_ROW" ] && printf '%s' "$DIAL_ROW" | grep -q "NOT AskUserQuestion"; then
  pass "orchestration-index has a dial routing line naming the inline-mention discipline"
else
  fail "orchestration-index dial routing line" "row with inline-mention dial offer (NOT AskUserQuestion)" "${DIAL_ROW:-absent}"
fi
MOCKUP_ROW=$(grep "inline-mention mockup offer" "$ORCH" || true)
DIAL_LEN=$(printf '%s' "$DIAL_ROW" | wc -c | tr -d ' ')
MOCKUP_LEN=$(printf '%s' "$MOCKUP_ROW" | wc -c | tr -d ' ')
if [ "$DIAL_LEN" -le "$MOCKUP_LEN" ] && [ "$DIAL_LEN" -gt 0 ]; then
  pass "dial routing line ($DIAL_LEN chars) no longer than the mockup-offer line ($MOCKUP_LEN)"
else
  fail "dial routing line no longer than mockup's" "<= $MOCKUP_LEN chars" "$DIAL_LEN chars"
fi
if grep -q "\.craft/dials" "$ORCH"; then
  fail "no .craft/dials STATE line in orchestration-index" "the corpus has no orchestrator-facing state - the omission is deliberate" "a .craft/dials line exists"
else
  pass "no .craft/dials STATE line in orchestration-index (deliberate omission held)"
fi
grep -q "|/craft:dial - runs cold" "$COLD" && pass "cold-start-index lists dial under WORKS-NOW" || fail "cold-start-index lists dial under WORKS-NOW"
RIFF_COLD='how does craft work / which flow fits|/craft:guide (explains) | /craft:ask (expert consult) | /craft:riff (thinking partner) - all run cold'
grep -qF -- "$RIFF_COLD" "$COLD" && pass "riff cold-start line byte-identical" || fail "riff cold-start line byte-identical" "$RIFF_COLD" "$(grep 'craft:riff' "$COLD" || echo absent)"

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
