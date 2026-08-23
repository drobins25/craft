#!/bin/bash
# test-vocabulary-prose.sh - Decision 12's field-axis gate: a reference doc
# that names a link field the definition does not know, or omits a field
# the definition declares for its record type, fails here whether or not a
# maintainer remembers to run check-doc-drift.sh manually. The status half
# of the same gate is a python test (test_vocabulary.py) - it needs
# vocabulary.STATUSES directly; this half reads markdown prose, so it is
# bash. Shared extraction logic lives in check-vocabulary-prose-drift.sh,
# sourced by both this file and check-doc-drift.sh, so the rule is written
# once.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/check-vocabulary-prose-drift.sh"

echo "=== test-vocabulary-prose.sh ==="
echo ""

# --- Test 1: every backticked link field named in a reference doc is
#     known to the definition (direction 1, live doc corpus) ---
begin_test "every link field named in a reference doc is known to the definition for that record type"
D1_FINDINGS=""
KNOWN_FIELDS="$(_vocab_prose_known_fields)"
for doc in "${VOCAB_PROSE_DOCS[@]}"; do
  path="$VOCAB_PROSE_ROOT/$doc"
  [ -f "$path" ] || continue
  found="$(_vocab_prose_check_direction1 "$doc" "$path" "$KNOWN_FIELDS")"
  [ -n "$found" ] && D1_FINDINGS="$D1_FINDINGS
$found"
done
assert_eq "no unregistered field named in any of the four reference docs" "" "$D1_FINDINGS"

# --- Test 2: every field the definition knows for a doc's owned record
#     type is named in that doc (direction 2 - the one that rots) ---
begin_test "every link field the definition knows is named in its reference doc"
D2_FINDINGS=""
for entry in "${VOCAB_PROSE_OWNERS[@]}"; do
  doc="${entry%%|*}"
  path="$VOCAB_PROSE_ROOT/$doc"
  [ -f "$path" ] || continue
  found="$(_vocab_prose_check_direction2 "$doc" "$path" "${entry##*|}")"
  [ -n "$found" ] && D2_FINDINGS="$D2_FINDINGS
$found"
done
assert_eq "no declared field missing from its owning reference doc" "" "$D2_FINDINGS"

# --- Test 3: direction 1 fires on an unknown field, naming the file ---
begin_test "a reference doc naming an unregistered field fails direction 1, naming the file and the field"
TMP_DOC="$(mktemp)"
echo 'Seeded drift: this doc names `made_up_link_field:` for testing.' > "$TMP_DOC"
FINDING="$(_vocab_prose_check_direction1 "seeded-doc.md" "$TMP_DOC" "$(_vocab_prose_known_fields)")"
rm -f "$TMP_DOC"
assert_contains_literal "finding names the seeded doc" "seeded-doc.md" "$FINDING"
assert_contains_literal "finding names the unregistered field" "made_up_link_field" "$FINDING"

# --- Test 4: direction 2 (the reverse - the one that rots) fires when a
#     doc drops a field the definition still declares for its type ---
begin_test "a reference doc missing a declared field fails direction 2, naming the missing field"
TMP_DOC2="$(mktemp)"
echo "nothing relevant here" > "$TMP_DOC2"
FINDING2="$(_vocab_prose_check_direction2 "seeded-doc.md" "$TMP_DOC2" "fix")"
rm -f "$TMP_DOC2"
assert_contains_literal "finding names source_story" "source_story" "$FINDING2"
assert_contains_literal "finding names source_cycle" "source_cycle" "$FINDING2"
assert_contains_literal "finding names satisfied_todo" "satisfied_todo" "$FINDING2"

# --- Test 5: check-doc-drift.sh exits 0 on the clean tree ---
begin_test "check-doc-drift exits 0 on a clean tree"
set +e
CLEAN_OUT="$(bash "$SCRIPT_DIR/../scripts/check-doc-drift.sh" 2>&1)"
CLEAN_RC=$?
set -e
assert_exit_code "clean tree exits 0" "0" "$CLEAN_RC"

# --- Test 6: check-doc-drift.sh exits 1 with a named finding on a seeded
#     drift in a real reference doc, then restores it unconditionally ---
begin_test "check-doc-drift exits 1 with a named finding on a seeded drift"
FIX_DOC="$SCRIPT_DIR/../skills/adhoc/references/fix.md"
BACKUP_DOC="$(mktemp)"
cp "$FIX_DOC" "$BACKUP_DOC"
restore_fix_doc() { cp "$BACKUP_DOC" "$FIX_DOC"; rm -f "$BACKUP_DOC"; }
trap restore_fix_doc EXIT
echo 'Seeded drift: names `made_up_link_field:` for testing.' >> "$FIX_DOC"
set +e
SEEDED_OUT="$(bash "$SCRIPT_DIR/../scripts/check-doc-drift.sh" 2>&1)"
SEEDED_RC=$?
set -e
restore_fix_doc
trap - EXIT
assert_exit_code "seeded drift exits 1" "1" "$SEEDED_RC"
assert_contains_literal "finding names the seeded field" "made_up_link_field" "$SEEDED_OUT"

# --- Test 7: this suite reports through the phrasing run-all.sh scrapes ---
begin_test "the new suite reports through the phrasing run-all.sh scrapes"
# run-all.sh extracts pass/fail counts with `grep -o '[0-9]* passed'` /
# `'[0-9]* failed'` over a test file's whole stdout. Prove finish_tests -
# the same helper this file ends with - produces output that pattern
# actually matches, using synthetic counts rather than self-invoking (which
# would recurse).
SAMPLE_OUT="$(bash -c "source '$SCRIPT_DIR/test_helper.sh'; PASS=3; FAIL=1; finish_tests sample" 2>&1)" || true
SCRAPED_PASS="$(printf '%s' "$SAMPLE_OUT" | grep -o '[0-9]* passed' | tail -1 | grep -o '[0-9]*')"
SCRAPED_FAIL="$(printf '%s' "$SAMPLE_OUT" | grep -o '[0-9]* failed' | tail -1 | grep -o '[0-9]*')"
assert_eq "run-all.sh's pass-count scrape reads finish_tests' output" "3" "$SCRAPED_PASS"
assert_eq "run-all.sh's fail-count scrape reads finish_tests' output" "1" "$SCRAPED_FAIL"

finish_tests "test-vocabulary-prose.sh"
