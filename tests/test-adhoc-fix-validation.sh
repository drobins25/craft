#!/bin/bash
# test-adhoc-fix-validation.sh - Verify the adhoc fix flow makes a newly added
# check prove itself against the broken version before it counts as validation.
#
# A fix with no implementer has no tests-first rule, so Step 5 of fix.md must
# ask for it: run the added test or structural check before the edit and see it
# fail on exactly the bug, run it after and see it pass, record both runs. A
# check that never ran against the broken version has proven nothing.
#
# Assertions are SECTION-SCOPED (fence-aware awk between ## headings): the
# bullet must live inside Step 5, directly above the All fixes bullet. A
# file-wide grep would pass if a later edit moved it elsewhere. The control
# assertion proves the section lookup itself works, so a red on the bullet
# assertions can only mean the bullet is missing or misplaced.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

# Working-tree file - guards THIS repo's edits, not the installed plugin copy
FIX_MD="$SCRIPT_DIR/../skills/adhoc/references/fix.md"

BULLET='- **A fix that adds a test or a structural check**: Before applying the edit (or against a copy without it), run the new check and confirm it fails on exactly the bug and nothing else. After the edit, run it again and confirm it passes. Record both runs in the Validation section - a check never run against the broken version has not proven anything. This never asks a fix to add a check it would not otherwise have.'
ALL_FIXES='- **All fixes**:'
# assert_contains_literal passes the needle to grep without "--", so a needle
# starting with "- " is read as an option; the contains-checks drop the marker
# and the adjacency check below compares the whole line, marker included
BULLET_BODY="${BULLET#- }"
ALL_FIXES_BODY="${ALL_FIXES#- }"

# Prints a ## section's body (heading to next ## heading or EOF).
# Fence-aware: a "## " line inside a ``` code block is content, not a boundary.
section() {
  awk -v h="$1" '
    /^```/ { fence = !fence }
    $0 ~ "^## " h { found = 1; next }
    /^## / { if (found && !fence) exit }
    found
  ' "$2"
}

echo "=== test-adhoc-fix-validation.sh ==="
echo ""

STEP5="$(section "Step 5: Validate the Symptom" "$FIX_MD")"
# '|| true' keeps set -e from aborting on an empty match, which would be a
# red that proves nothing
ABOVE_ALL_FIXES="$(echo "$STEP5" | grep -B1 -F -- "$ALL_FIXES" | head -1 || true)"

begin_test "Step 5 section is found (control)"
assert_contains_literal \
  "Step 5 contains the All fixes bullet" \
  "$ALL_FIXES_BODY" \
  "$STEP5"

echo ""

begin_test "Step 5 carries the fails-first bullet verbatim"
assert_contains_literal \
  "Step 5 contains the full fails-first bullet" \
  "$BULLET_BODY" \
  "$STEP5"

echo ""

begin_test "the fails-first bullet sits directly above All fixes"
assert_eq \
  "line preceding All fixes is the fails-first bullet" \
  "$BULLET" \
  "$ABOVE_ALL_FIXES"

echo ""

# --- Mechanism gate: the record quotes the line that stops the bug before the
# evidence check runs. Pinned by POSITION, not presence: a Mechanism section
# moved below Confidence Check, or the gate sentences moved after the claims
# list, would leave a presence grep green while the gate is defeated.
# Line numbers come from grep -n over the whole file so the order is explicit.

MECH_HEADING='## Mechanism'
MECH_BODY='[The changed line - added or removed - quoted verbatim with file:line, and one clause saying how that change stops the symptom.]'
GATE_FIRST='Fill Mechanism first. If no line can be quoted, escalate.'
GATE_DEFER='A quoted line that only points at another file is not the mechanism - quote the line it points at.'
CLAIMS='List every claim this fix depends on'
CLAIM_SCOPE='every place the flow can end, including inside any command or skill it hands off to'
EVIDENCE='Beside each, put the tool result from this session that shows it'

# first line number of a literal, or 0 when absent
ln_of() { local n; n="$(grep -n -F -- "$1" "$FIX_MD" | head -1 | cut -d: -f1 || true)"; echo "${n:-0}"; }

STEP1="$(section "Step 1: Create the Fix File" "$FIX_MD")"
STEP3="$(section "Step 3: Confidence Check" "$FIX_MD")"

begin_test "Step 1 template carries the Mechanism section with its body"
assert_contains_literal \
  "Step 1 contains the Mechanism heading" \
  "$MECH_HEADING" \
  "$STEP1"
assert_contains_literal \
  "Step 1 contains the Mechanism body" \
  "$MECH_BODY" \
  "$STEP1"

echo ""

begin_test "Mechanism sits between Solution and Confidence Check in the template"
L_SOLUTION="$(ln_of '## Solution')"
L_MECH="$(ln_of "$MECH_HEADING")"
L_CONF="$(ln_of '## Confidence Check')"
assert_eq \
  "Solution < Mechanism < Confidence Check by line number" \
  "yes" \
  "$( [ "$L_SOLUTION" -gt 0 ] && [ "$L_MECH" -gt "$L_SOLUTION" ] && [ "$L_CONF" -gt "$L_MECH" ] && echo yes || echo "no (solution=$L_SOLUTION mechanism=$L_MECH confidence=$L_CONF)")"

echo ""

begin_test "Step 3 carries both gate sentences verbatim"
assert_contains_literal \
  "Step 3 contains the fill-first sentence" \
  "$GATE_FIRST" \
  "$STEP3"
assert_contains_literal \
  "Step 3 contains the no-deference sentence" \
  "$GATE_DEFER" \
  "$STEP3"

echo ""

begin_test "both gate sentences come before the claims list"
L_FIRST="$(ln_of "$GATE_FIRST")"
L_DEFER="$(ln_of "$GATE_DEFER")"
L_CLAIMS="$(ln_of "$CLAIMS")"
assert_eq \
  "gate sentences < claims list by line number" \
  "yes" \
  "$( [ "$L_FIRST" -gt 0 ] && [ "$L_DEFER" -gt 0 ] && [ "$L_CLAIMS" -gt "$L_FIRST" ] && [ "$L_CLAIMS" -gt "$L_DEFER" ] && echo yes || echo "no (first=$L_FIRST defer=$L_DEFER claims=$L_CLAIMS)")"

echo ""

# --- Evidence check: Step 3 asks for each claim's tool result, not a
# self-graded certainty. The claim scope names where untraced claims hid
# (what clears a value, who calls it, every place the flow ends, including
# inside a command it hands off to).

begin_test "Step 3 is an evidence check, not a certainty question"
assert_contains_literal "Step 3 asks for every claim" "$CLAIMS" "$STEP3"
assert_contains_literal "Step 3 names the claim scope" "$CLAIM_SCOPE" "$STEP3"
assert_contains_literal "Step 3 asks for a tool result per claim" "$EVIDENCE" "$STEP3"
assert_contains_literal "Step 3 continues only when every claim holds" "**If every claim holds**" "$STEP3"
assert_contains_literal "Step 3 escalates on a contradicted claim" "**If a result contradicts a claim**" "$STEP3"
assert_not_contains "Step 3 no longer asks for 100% certainty" "100% certain" "$STEP3"
assert_contains_literal "template asks for the claim table" "claim | evidence | holds" "$STEP1"
assert_not_contains "template no longer asks for 100% certainty" "100% certain" "$STEP1"

echo ""

# --- planned_test: the record names the planned case that should have caught
# a post-story defect, or none. Pinned in Step 1 (template line + the none
# rule) and in the Step 8 summary, so the field cannot drop out of either.

STEP8="$(section "Step 8: Close" "$FIX_MD")"

begin_test "Step 1 carries the planned_test field and its none rule"
assert_contains_literal \
  "Step 1 template names planned_test" \
  "planned_test: [for a defect found after source_story completed" \
  "$STEP1"
assert_contains_literal \
  "Step 1 states the none rule" \
  "When no planned case covers that behavior, write \`none\`." \
  "$STEP1"
assert_contains_literal \
  "Step 8 summary reports the planned test" \
  "Planned test: [" \
  "$STEP8"

echo ""

finish_tests "test-adhoc-fix-validation.sh"
