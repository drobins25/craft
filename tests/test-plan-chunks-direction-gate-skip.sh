#!/bin/bash
# test-plan-chunks-direction-gate-skip.sh - Guard the plan-chunks direction gate's skip
# conditions. When the user's own words already asked to plan (a direct
# /craft:plan-chunks, "plan this", or a yes to an offer to plan), Phase 0.5 must not
# ask "Ready to plan this story?" a second time. The batch gate skips only on the flag. Command
# hand-offs keep the DIRECTION_CONFIRMED flag, and the never-auto-invoke guard stays.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

SKILL="$PLUGIN_ROOT/skills/plan-chunks/SKILL.md"

DIRECTION_BLOCK="$(sed -n '/^## Phase 0.5: Direction Confirmation Gate/,/^## Single-Story Planning/p' "$SKILL")"

begin_test "direction gate skips when the user already asked to plan"
assert_not_contains "user-ask skip covers one story only" 'these stories' "$DIRECTION_BLOCK"

begin_test "batch gate skips only on the flag"
assert_not_contains "batch never borrows the user-ask skip" 'Same skip conditions as above.' "$DIRECTION_BLOCK"

finish_tests
