#!/bin/bash
# test-tracker-intake-wiring.sh - Literal wiring checks for starting a cycle from a tracker issue

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

DESIGN="$PLUGIN_ROOT/commands/craft-cycle-design.md"
INTAKE="$PLUGIN_ROOT/commands/references/tracker-intake.md"
INDEX="$PLUGIN_ROOT/reference/orchestration-index.min"

echo "=== test-tracker-intake-wiring.sh ==="
echo ""

# has_literal <file> <literal> - exit 0 when the file holds the literal
has_literal() { [ -f "$1" ] && grep -qF -- "$2" "$1"; }

assert_literal() {
  local desc="$1" file="$2" needle="$3"
  if has_literal "$file" "$needle"; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"; echo "    expected literal: '$needle'"; FAIL=$((FAIL + 1))
  fi
}

begin_test "Phase Dispatch reads tracker-intake.md before Step 1"
DISPATCH=$(sed -n '/^## Phase Dispatch/,/^## Philosophy/p' "$DESIGN")
assert_contains_literal "Read path inside Phase Dispatch" \
  '→ Read `${CLAUDE_PLUGIN_ROOT}/commands/references/tracker-intake.md` and run it before Step 1.' "$DISPATCH"
assert_contains_literal "bare key pattern named" '^[A-Z][A-Z0-9]*-[0-9]+$' "$DISPATCH"
assert_literal "description routes tracker keys" "$DESIGN" \
  'Given a tracker issue key or URL (\"pick up DRO-21\"), starts the cycle from that issue, its comments and its newest Go.'
echo ""

begin_test "intake pins every exact line"
assert_literal "hold follow-up" "$INTAKE" '`Nothing new starts on <KEY> until a newer Go.`'
assert_literal "no tools line" "$INTAKE" "I can't reach <KEY> from here; paste the issue or connect your tracker."
assert_literal "paste stage line" "$INTAKE" 'Stage: plan, because I read <KEY> from your paste, not from the tracker.'
assert_literal "contradiction pattern" "$INTAKE" "the newest Go says <stage>, and the Go wins."
assert_literal "copy line" "$INTAKE" "Copied <KEY>, <N> comments, into this cycle's context."
assert_literal "copy line, one comment" "$INTAKE" "1 comment"
assert_literal "paste copy line" "$INTAKE" "Copied your paste of <KEY> into this cycle's context."
assert_literal "status at retrieval" "$INTAKE" "Status at retrieval: <status> (copied for reference; never a permission)"
assert_literal "status never authority" "$INTAKE" "never authority"
for h in Detect Read Stage Copy "Into Step 1" "After the cycle exists" "Story citations" "Stages in Craft" "No tracker tools"; do
  assert_literal "section: $h" "$INTAKE" "## $h"
done
echo ""

begin_test "one create-cycle invocation with nine args"
assert_eq "invocation count" "1" "$(grep -c 'cycle_dir=\$(' "$DESIGN")"
INVOKE=$(grep 'cycle_dir=\$(' "$DESIGN")
assert_contains_literal "carries the source-issue arg" '"[source-issue]" "[authorized-stage]" "[go-author]" "[go-date]"' "$INVOKE"
assert_literal "gate names the tracker issue" "$DESIGN" 'and tracker issue <KEY> at stage <stage> (<N> comments copied)'
echo ""

begin_test "intake names the resolver and the staging folder"
assert_literal "resolver" "$INTAKE" 'resolve-go.py'
assert_literal "staging folder" "$INTAKE" '.craft/.intake/'
assert_literal "context folder" "$INTAKE" '/context/'
echo ""

begin_test "index row present and under budget"
assert_literal "routing row" "$INDEX" 'tracker issue key or URL to start work ("pick up DRO-21")|cycle-design with the key (Phase Dispatch reads tracker-intake.md; stage line first)'
BYTES=$(wc -c < "$INDEX" | tr -d ' ')
if [ "$BYTES" -lt 5632 ]; then
  echo "  PASS: index is $BYTES bytes (< 5632)"; PASS=$((PASS + 1))
else
  echo "  FAIL: index is $BYTES bytes"; FAIL=$((FAIL + 1))
fi
echo ""

begin_test "no em dash in tracker-intake.md"
if [ -f "$INTAKE" ] && ! grep -q '—' "$INTAKE"; then
  echo "  PASS: hyphen-minus only"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing file or em dash present"; FAIL=$((FAIL + 1))
fi
echo ""

begin_test "3e citation paragraph present after the writers' rule"
DM="$PLUGIN_ROOT/commands/references/cycle-design/default-mode.md"
RULE_LN=$(grep -n 'never scan the store for candidates' "$DM" | head -1 | cut -d: -f1)
CITE_LN=$(grep -n '^\*\*Tracker-sourced cycle:\*\*' "$DM" | head -1 | cut -d: -f1)
NOTE_LN=$(grep -n '^\*\*Note:\*\* Stories are saved' "$DM" | head -1 | cut -d: -f1)
if [ -n "$RULE_LN" ] && [ -n "$CITE_LN" ] && [ -n "$NOTE_LN" ] && [ "$RULE_LN" -lt "$CITE_LN" ] && [ "$CITE_LN" -lt "$NOTE_LN" ]; then
  echo "  PASS: rule ($RULE_LN) < citation ($CITE_LN) < note ($NOTE_LN)"; PASS=$((PASS + 1))
else
  echo "  FAIL: order rule='$RULE_LN' citation='$CITE_LN' note='$NOTE_LN'"; FAIL=$((FAIL + 1))
fi
assert_literal "citation reads the cycle being written into" "$DM" '.craft/cycles/[cycle-name]/cycle.yaml'
assert_literal "intake citations group" "$INTAKE" '**Tracker context (copied from <KEY>):**'
echo ""

IMPL="$PLUGIN_ROOT/commands/craft-story-implement.md"
AUTO="$PLUGIN_ROOT/commands/craft-story-implement-auto.md"

begin_test "Stage check sits between Cycle and Status checks"
CYC_LN=$(grep -n '^\*\*Cycle check:\*\*' "$IMPL" | head -1 | cut -d: -f1)
STG_LN=$(grep -n '^\*\*Stage check:\*\*' "$IMPL" | head -1 | cut -d: -f1)
STA_LN=$(grep -n '^\*\*Status check:\*\*' "$IMPL" | head -1 | cut -d: -f1)
if [ -n "$CYC_LN" ] && [ -n "$STG_LN" ] && [ -n "$STA_LN" ] && [ "$CYC_LN" -lt "$STG_LN" ] && [ "$STG_LN" -lt "$STA_LN" ]; then
  echo "  PASS: cycle ($CYC_LN) < stage ($STG_LN) < status ($STA_LN)"; PASS=$((PASS + 1))
else
  echo "  FAIL: order cycle='$CYC_LN' stage='$STG_LN' status='$STA_LN'"; FAIL=$((FAIL + 1))
fi
echo ""

begin_test "Stage check names cycle-stage.sh and says no question"
STAGE_BLOCK=$(sed -n '/^\*\*Stage check:\*\*/,/^\*\*Status check:\*\*/p' "$IMPL")
assert_contains_literal "runs cycle-stage.sh" 'hooks/scripts/cycle-stage.sh" "${CRAFT_PROJECT_ROOT:-.}/.craft/cycles/[cycle-name]"' "$STAGE_BLOCK"
assert_contains_literal "no question on a stop" 'No AskUserQuestion' "$STAGE_BLOCK"
assert_contains_literal "names how to lift" 'newer Go' "$STAGE_BLOCK"
if printf '%s' "$STAGE_BLOCK" | grep -qE 'claims-auditor|hooks/scripts/complete-story.sh'; then
  echo "  FAIL: stage check names a claims-audit anchor"; FAIL=$((FAIL + 1))
else
  echo "  PASS: no claims-audit anchors in the stage check"; PASS=$((PASS + 1))
fi
echo ""

begin_test "implement-auto ends the run on a stage stop"
assert_literal "stage stop ends the run" "$AUTO" 'A Stage check stop from `craft:story-implement` ends the run'
echo ""

finish_tests
