#!/bin/bash
# test-adhoc-todo-close.sh - Verify adhoc closes the notebook todo it satisfies
#
# Story 9 (cycle 11) wired the adhoc flows to detect and close open notebook
# todos their work satisfies: the shell owns the shared detection mechanism
# (## Todo Satisfaction Detection - notebook-list call, semantic match,
# named-referent arity discipline, notebook-done close call, satisfied_todo
# receipt), fix.md owns the fix-path match-only consent AUQ (Step 7), and
# tweak.md owns the tweak-path wiring (detection at the Fit Check, close
# riding the acceptance ask - one consent, both effects).
#
# Assertions are SECTION-SCOPED (fence-aware awk between ## headings), not
# file-wide: the consent AUQ must live inside fix.md's Step 7, the discipline
# inside the shell section - a file-wide grep would pass even if a future
# edit orphaned the strings elsewhere.
#
# Chunk 2 extends this file with the tweak.md assertions.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

# Working-tree files - guards THIS repo's edits, not the installed plugin copy
SKILL_MD="$SCRIPT_DIR/../skills/adhoc/SKILL.md"
FIX_MD="$SCRIPT_DIR/../skills/adhoc/references/fix.md"
TWEAK_MD="$SCRIPT_DIR/../skills/adhoc/references/tweak.md"

# Prints a ## section's body (heading to next ## heading or EOF).
# ### subsections stay inside the section - they don't match /^## /.
# Fence-aware: a "## " line inside a ``` code block (e.g. the ## Adhoc Fix
# summary template) is content, not a section boundary.
section() {
  awk -v h="$1" '
    /^```/ { fence = !fence }
    $0 ~ "^## " h { found = 1; next }
    /^## / { if (found && !fence) exit }
    found
  ' "$2"
}

echo "=== test-adhoc-todo-close.sh ==="
echo ""

DETECTION="$(section "Todo Satisfaction Detection" "$SKILL_MD")"
FIX_STEP1="$(section "Step 1: Create the Fix File" "$FIX_MD")"
FIX_STEP7="$(section "Step 7: Todo Satisfaction" "$FIX_MD")"

# Test 1: shell defines the notebook-list detection call
begin_test "shell section runs the notebook-list detection call"

assert_contains_literal \
  "detection section invokes notebook-list.sh todos" \
  "notebook-list.sh todos" \
  "$DETECTION"

echo ""

# Test 2: the match is a semantic judgment, not a string match
begin_test "shell section states the semantic-match heuristic"

assert_contains_literal \
  "match is a semantic content judgment" \
  "semantic content judgment, not a string match" \
  "$DETECTION"

echo ""

# Test 3: three-arity named-referent discipline lives in the shell section
begin_test "shell section carries the three-arity named-referent discipline"

assert_contains_literal \
  "zero-match arity (silent continue)" \
  "Zero matches:" \
  "$DETECTION"

assert_contains_literal \
  "single-match arity (name it)" \
  "Single match:" \
  "$DETECTION"

assert_contains_literal \
  "multi-match arity (disambiguate first)" \
  "Multiple plausible matches:" \
  "$DETECTION"

assert_contains_literal \
  "silent-close prohibition survives" \
  "Never silent-close" \
  "$DETECTION"

echo ""

# Test 4: one todo per record is the stated scope
begin_test "shell section states the one-per-record scope"

assert_contains_literal \
  "one todo per record, by design" \
  "One todo per record, by design" \
  "$DETECTION"

echo ""

# Test 5: the generic-ref close call shape lives in the shell section
begin_test "shell section specifies the notebook-done close call"

assert_contains_literal \
  "close call uses todo-file + record-name" \
  'notebook-done.sh "<todo-file>" "<record-name>"' \
  "$DETECTION"

echo ""

# Test 6: the satisfied_todo receipt is stamped on every run
begin_test "shell section specifies the satisfied_todo receipt"

assert_contains_literal \
  "receipt field is named" \
  "satisfied_todo:" \
  "$DETECTION"

assert_contains_literal \
  "no-close runs stamp none-matched" \
  "none-matched" \
  "$DETECTION"

assert_contains_literal \
  "missing receipt means the beat never fired" \
  "the beat never fired" \
  "$DETECTION"

echo ""

# Test 7: the editors' comment names the detection beat as a shell responsibility
begin_test "shell editors' comment lists the detection beat"

HEAD_COMMENT="$(head -12 "$SKILL_MD")"
assert_contains_literal \
  "editors' comment mentions todo-satisfaction" \
  "todo-satisfaction detection" \
  "$HEAD_COMMENT"

echo ""

# Test 8: fix path fires a match-only AUQ (zero friction on no match)
begin_test "fix path consent AUQ is match-triggered only"

assert_contains_literal \
  "AUQ fires only when a match exists" \
  "fires ONLY when a match exists" \
  "$FIX_STEP7"

assert_contains_literal \
  "no-match path is silent" \
  "No surface, no friction" \
  "$FIX_STEP7"

echo ""

# Test 9: fix path closes via notebook-done and stamps the receipt
begin_test "fix path closes via notebook-done and stamps satisfied_todo"

assert_contains_literal \
  "fix path carries the close call" \
  "notebook-done.sh" \
  "$FIX_STEP7"

assert_contains_literal \
  "accepting answer stamps the todo slug" \
  "satisfied_todo: <todo-slug>" \
  "$FIX_STEP7"

assert_contains_literal \
  "declined/no-match stamps none-matched" \
  "satisfied_todo: none-matched" \
  "$FIX_STEP7"

echo ""

# Test 10: fix record template documents the receipt field
begin_test "fix template documents the satisfied_todo receipt field"

assert_contains_literal \
  "template frontmatter carries satisfied_todo" \
  "satisfied_todo:" \
  "$FIX_STEP1"

echo ""

TWEAK_STEP1="$(section "Step 1: Create the Tweak Record" "$TWEAK_MD")"
TWEAK_STEP2="$(section "Step 2: Fit Check" "$TWEAK_MD")"
TWEAK_STEP3="$(section "Step 3: The Attempt Loop" "$TWEAK_MD")"

# Test 11: tweak detection runs at the Fit Check and persists the match to disk
begin_test "tweak detects at the Fit Check and writes the pending match to the record"

assert_contains_literal \
  "Step 2 runs the detection call" \
  "notebook-list.sh todos" \
  "$TWEAK_STEP2"

assert_contains_literal \
  "pending match is written into the Fit Check section, not memory" \
  "never from conversational memory" \
  "$TWEAK_STEP2"

assert_contains_literal \
  "zero-match stamps the receipt immediately" \
  "satisfied_todo: none-matched" \
  "$TWEAK_STEP2"

echo ""

# Test 12: the acceptance ask names both effects - one consent
begin_test "tweak acceptance ask names both effects (one consent)"

assert_contains_literal \
  "close-out question names both effects when a match is pending" \
  "names BOTH effects" \
  "$TWEAK_STEP3"

assert_contains_literal \
  "no second AUQ for the close" \
  "never add a second AskUserQuestion" \
  "$TWEAK_STEP3"

echo ""

# Test 13: only an accepting answer closes the todo
begin_test "only an accepting answer closes the todo"

assert_contains_literal \
  "non-accepting routes never close" \
  "Only an accepting answer closes the todo" \
  "$TWEAK_STEP3"

echo ""

# Test 14: accepting route closes via notebook-done and stamps the receipt
begin_test "tweak accepting route closes via notebook-done and stamps satisfied_todo"

assert_contains_literal \
  "accepting route carries the close call" \
  "notebook-done.sh" \
  "$TWEAK_STEP3"

assert_contains_literal \
  "accepting route stamps the todo slug" \
  "satisfied_todo: <todo-slug>" \
  "$TWEAK_STEP3"

assert_contains_literal \
  "abandoned tweak stamps none-matched and leaves the todo open" \
  "satisfied_todo: none-matched" \
  "$TWEAK_STEP3"

echo ""

# Test 15: tweak record template documents the receipt field
begin_test "tweak template documents the satisfied_todo receipt field"

assert_contains_literal \
  "template frontmatter carries satisfied_todo" \
  "satisfied_todo:" \
  "$TWEAK_STEP1"

echo ""

# A fix started from a bug record closes that bug. The close is keyed on the
# fix record reading validated, never on the commit, so a fix held for a later
# commit still closes its bug. Two paths carry it: the hand-off (the caller,
# after the fixer's report) and fix.md Step 8 (the caller running the flow
# itself).
HANDOFF_MD="$SCRIPT_DIR/../skills/adhoc/references/fix-handoff.md"
HANDOFF_H5="$(section "H-5" "$HANDOFF_MD")"
FIX_STEP8="$(section "Step 8: Close" "$FIX_MD")"

# Test 16: the hand-off closes the bug the fix was started from
begin_test "hand-off closes the bug a fix was started from, at validated"

assert_contains_literal \
  "hand-off carries the bug close call" \
  'bugs-close.sh" "<the bug record'"'"'s path>" --status=fixed --fixed-by="fix record' \
  "$HANDOFF_H5"

assert_contains_literal \
  "the close is keyed on the record reading validated" \
  'reads `status: validated`' \
  "$HANDOFF_H5"

assert_contains_literal \
  "the close does not wait for the commit" \
  "whether or not the fix is committed" \
  "$HANDOFF_H5"

assert_contains_literal \
  "the close asks nothing" \
  "Ask nothing" \
  "$HANDOFF_H5"

assert_contains_literal \
  "a judgment-layer bug stays open" \
  'gives its layer as `judgment` stays open' \
  "$HANDOFF_H5"

# The no-commit rule sends the reader straight to Close, so the bug close must
# come before the commit bullet or a held fix skips it.
BUG_LN="$(grep -n -F -- '- **Bug:**' <<< "$HANDOFF_H5" | head -1 | cut -d: -f1 || true)"
COMMIT_LN="$(grep -n -F -- '- **Commit:**' <<< "$HANDOFF_H5" | head -1 | cut -d: -f1 || true)"
ORDER="no"
if [ -n "$BUG_LN" ] && [ -n "$COMMIT_LN" ] && [ "$BUG_LN" -lt "$COMMIT_LN" ]; then
  ORDER="yes"
fi
assert_eq "the bug close comes before the commit bullet" "yes" "$ORDER"

echo ""

# Test 17: the inline path closes the bug at Step 8
begin_test "fix flow Step 8 closes the bug a fix was started from"

assert_contains_literal \
  "Step 8 carries the bug close call" \
  'bugs-close.sh" "<the bug record'"'"'s path>" --status=fixed --fixed-by="fix record' \
  "$FIX_STEP8"

assert_contains_literal \
  "Step 8 keys the close on validated" \
  'reads `status: validated`' \
  "$FIX_STEP8"

assert_contains_literal \
  "Step 8 leaves a judgment-layer bug open" \
  'gives its layer as `judgment` stays open' \
  "$FIX_STEP8"

assert_contains_literal \
  "Step 8 marks the close as the caller's" \
  "A subagent skips it" \
  "$FIX_STEP8"

# The hand-off sends its reader through Step 7, which continues here. A second
# close on a record that already moved can close a similar-named open bug, so
# Step 8 tells that reader to skip it.
assert_contains_literal \
  "a hand-off caller does not close the bug a second time" \
  'A caller following `fix-handoff.md` skips it too' \
  "$FIX_STEP8"

assert_contains_literal \
  "Step 8 keys the close on the record's bug line" \
  'its `bug:` line names a bug record' \
  "$FIX_STEP8"

assert_contains_literal \
  "the hand-off keys the close on the record's bug line" \
  'its `bug:` line names a bug record' \
  "$HANDOFF_H5"

assert_contains_literal \
  "the fix record template carries a bug line" \
  "bug: [name of the bug record this fix was started from" \
  "$(cat "$FIX_MD")"

assert_contains_literal \
  "the Smith brief carries BUG:" \
  '- `BUG:` only when the request pointed at a bug record' \
  "$(cat "$HANDOFF_MD")"

assert_contains_literal \
  "the hand-off waits for a pending send-back before closing" \
  "no send-back to Smith is waiting for a reply" \
  "$HANDOFF_H5"

assert_contains_literal \
  "the summary reports the bug" \
  "Bug: [" \
  "$FIX_STEP8"

echo ""

finish_tests
