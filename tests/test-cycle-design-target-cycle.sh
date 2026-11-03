#!/bin/bash
# test-cycle-design-target-cycle.sh - Designing a cycle reads and writes the
# cycle being designed (PLANNING_CYCLE), never whichever cycle is active.
#
# Pins three spots: default-mode's planning-source check, the planning
# protocol's cycle-design auto-resolve, and the protocol's story placement.
# /craft:story-new still places stories by the active cycle.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

DESIGN="$PLUGIN_ROOT/commands/craft-cycle-design.md"
DEFAULT_MODE="$PLUGIN_ROOT/commands/references/cycle-design/default-mode.md"
DETAILING="$PLUGIN_ROOT/commands/references/cycle-design/detailing-mode.md"
PROTOCOL="$PLUGIN_ROOT/commands/references/story-from-planning.md"

echo "=== test-cycle-design-target-cycle.sh ==="
echo ""

begin_test "cycle-design records the cycle it is designing"
assert_contains_literal "Step 1 sets PLANNING_CYCLE to the new cycle" \
  'update-global-state.sh PLANNING_CYCLE "$(basename $cycle_dir)"' "$(cat "$DESIGN")"
assert_contains_literal "detailing mode sets PLANNING_CYCLE" \
  'update-global-state.sh PLANNING_CYCLE "[arg]"' "$(cat "$DETAILING")"
echo ""

begin_test "default mode checks the planning source of the cycle being designed"
CHECK=$(sed -n '/^\*\*Before doing per-story work in Step 3 or Step 3-Fast\*\*/,/^If `source_concept` is `\[\]`/p' "$DEFAULT_MODE")
assert_not_eq "check section found" "" "$CHECK"
assert_contains_literal "reads PLANNING_CYCLE" 'grep "^PLANNING_CYCLE="' "$CHECK"
assert_contains_literal "opens that cycle's cycle.yaml" 'cycles/${PLANNING_CYCLE}/cycle.yaml' "$CHECK"
assert_contains_literal "strips the stored quotes" "tr -d '\"'" "$CHECK"
assert_not_contains "never reads ACTIVE_CYCLE" 'ACTIVE_CYCLE' "$CHECK"
echo ""

begin_test "planning protocol auto-resolves from the cycle being designed"
RESOLVE=$(sed -n '/^\*\*Cycle-design invocation - auto-resolve/,/^\*\*Story-new invocation/p' "$PROTOCOL")
assert_not_eq "auto-resolve section found" "" "$RESOLVE"
assert_contains_literal "reads PLANNING_CYCLE first" 'TARGET_CYCLE=$(grep "^PLANNING_CYCLE="' "$RESOLVE"
assert_contains_literal "falls back to ACTIVE_CYCLE only when empty" '[ -n "$TARGET_CYCLE" ] || TARGET_CYCLE=$(grep "^ACTIVE_CYCLE="' "$RESOLVE"
assert_contains_literal "opens the target cycle's cycle.yaml" 'cycles/${TARGET_CYCLE}/cycle.yaml' "$RESOLVE"
assert_not_contains "no direct active-cycle cycle.yaml read" 'cycles/\${ACTIVE_CYCLE}/cycle.yaml' "$RESOLVE"
echo ""

begin_test "planning protocol places a cycle-design story in the cycle being designed"
PLACE=$(sed -n '/^### Placement logic/,/^### Frontmatter construction/p' "$PROTOCOL")
assert_not_eq "placement section found" "" "$PLACE"
assert_contains_literal "reads PLANNING_CYCLE" 'PLANNING_CYCLE=$(grep "^PLANNING_CYCLE="' "$PLACE"
assert_contains_literal "cycle-design story goes to the planning cycle" 'cycles/$PLANNING_CYCLE/stories/' "$PLACE"
assert_contains_literal "story-new keeps the active cycle" 'cycles/$ACTIVE_CYCLE/stories/' "$PLACE"
assert_contains_literal "no cycle still means backlog" '.craft/backlog/' "$PLACE"
PLAN_LINE=$(printf '%s\n' "$PLACE" | grep -nF 'cycles/$PLANNING_CYCLE/stories/' | head -1 | cut -d: -f1 || true)
ACTIVE_LINE=$(printf '%s\n' "$PLACE" | grep -nF 'cycles/$ACTIVE_CYCLE/stories/' | head -1 | cut -d: -f1 || true)
if [ -n "$PLAN_LINE" ] && [ -n "$ACTIVE_LINE" ] && [ "$PLAN_LINE" -lt "$ACTIVE_LINE" ]; then
  echo "  PASS: the planning cycle is checked before the active cycle"; PASS=$((PASS + 1))
else
  echo "  FAIL: the planning cycle is checked before the active cycle"
  echo "    planning line: '${PLAN_LINE}', active line: '${ACTIVE_LINE}'"; FAIL=$((FAIL + 1))
fi
echo ""

finish_tests
