#!/bin/bash
# test-review-wiring.sh - Pins the prose seams that carry a review's back-link
# into the records its findings graduate to.
#
# The vocabulary drift check only greps for the word "review", which fix.md and
# tweak.md already contain, so it cannot prove the template line exists. These
# pins read the templates and the capture flags block directly.
# It also pins the review command, its close-out reference and the reviewer's
# report shape, and proves the reference's worked example survives the scripts.
# Usage: bash tests/test-review-wiring.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

FIX="$PLUGIN_ROOT/skills/adhoc/references/fix.md"
TWEAK="$PLUGIN_ROOT/skills/adhoc/references/tweak.md"
BUGS_RECORD="$PLUGIN_ROOT/commands/references/bugs-record.md"
REVIEW_CMD="$PLUGIN_ROOT/commands/craft-review.md"
REVIEW_REF="$PLUGIN_ROOT/commands/references/review-record.md"
REVIEWER="$PLUGIN_ROOT/agents/pr-reviewer-expert.md"
ADHOC_SKILL="$PLUGIN_ROOT/skills/adhoc/SKILL.md"
BUGS_CMD="$PLUGIN_ROOT/commands/craft-bugs.md"
NOTEBOOK_CMD="$PLUGIN_ROOT/commands/craft-notebook.md"
TMP_ROOTS=()

cleanup_roots() {
  local r
  for r in "${TMP_ROOTS[@]:-}"; do [ -n "$r" ] && rm -rf "$r"; done
  return 0
}
trap cleanup_roots EXIT

# fenced_block <info-string> <file> - body of the first fence with that info string
fenced_block() {
  awk -v info="$1" '
    $0 == "```" info {inside=1; next}
    inside && $0 == "```" {exit}
    inside {print}
  ' "$2"
}

begin_test "fix template carries review"
assert_contains "review line in the record template" "^review:" "$(fenced_block markdown "$FIX")"

begin_test "tweak template carries review"
assert_contains "review line in the record template" "^review:" "$(fenced_block markdown "$TWEAK")"

begin_test "bugs-record flags block names --review"
FLAGS_FENCE=$(awk '
  /^## Frontmatter flags$/ {seen=1; next}
  seen && /^```/ {if (inside) exit; inside=1; next}
  inside {print}
' "$BUGS_RECORD")
assert_contains_literal "flags fence has --review=" "--review=<review record name>" "$FLAGS_FENCE"

# --- Chunk 4: the reviewer, the command, the close-out reference ---

REF_TEXT=""
[ -f "$REVIEW_REF" ] && REF_TEXT=$(cat "$REVIEW_REF")

begin_test "close-out runs adhoc inline, never through the Skill tool"
assert_contains_literal "reference names the adhoc skill file" '${CLAUDE_PLUGIN_ROOT}/skills/adhoc/SKILL.md' "$REF_TEXT"
assert_contains_literal "reference forbids the Skill tool" "never through the Skill tool" "$REF_TEXT"
assert_contains_literal "reference reads the skill inline" "inline" "$REF_TEXT"
assert_contains_literal "one task per pending adhoc run is created first" "one task per pending adhoc run" "$REF_TEXT"

# quote_pair <source file> <sentence> - the sentence sits verbatim in the reference and in its source
quote_pair() {
  local src="$1" sentence="$2"
  assert_contains_literal "reference quotes: $sentence" "$sentence" "$REF_TEXT"
  assert_contains_literal "source still says: $sentence" "$sentence" "$(cat "$src")"
}

begin_test "each door quote appears verbatim in review-record.md and in its source"
quote_pair "$ADHOC_SKILL" "Acts NOW - a defect to file and fix later belongs in /craft:bugs, other deferred work in the notebook. Do NOT use for new features, design exploration, or changes requiring creative spark."
quote_pair "$BUGS_CMD" "File a bug without fixing it, from a person mid-conversation or an agent mid-run."
quote_pair "$BUGS_CMD" "Not for: fixing it now (/craft:adhoc), ideas and todos (/craft:notebook)."
quote_pair "$NOTEBOOK_CMD" "Notebook todos are deferred intent items, not act-now work."
quote_pair "$NOTEBOOK_CMD" "A todo is intent; a bug record carries the reproduce and done-when a fixer needs."
quote_pair "$NOTEBOOK_CMD" "For thoughts that are already story-shape with a clear acceptance shape."
quote_pair "$ADHOC_SKILL" "If the solution adds something that wasn't there before (a new component, a new API endpoint, a new element on the page), it's a story."
for src_path in skills/adhoc/SKILL.md commands/craft-bugs.md commands/craft-notebook.md; do
  assert_contains_literal "reference cites $src_path" "$src_path" "$REF_TEXT"
done

begin_test "worked example round-trips through capture and graduate"
EXAMPLE=$(awk '
  $0 == "~~~review-body" {inside=1; next}
  inside && $0 == "~~~" {exit}
  inside {print}
' "$REVIEW_REF" 2>/dev/null || true)
assert_contains_literal "example fence is present" "## Verified" "$EXAMPLE"
EX_ROOT=$(mktemp -d); TMP_ROOTS+=("$EX_ROOT")
EX_RC=0
EX_OUT=$(printf '%s\n' "$EXAMPLE" | CRAFT_PROJECT_ROOT="$EX_ROOT" bash "$SCRIPTS_DIR/review-capture.sh" \
  --mode=branch --strategy=standard --reviewed=feature-x --ref=abc1234..def5678 \
  --focus=correctness,security --files=3 --lines=40 --reviewer=pr-reviewer-expert \
  --gates=none --craft-version=9.9.9 --stdin 2>/dev/null) || EX_RC=$?
assert_eq "capture accepts the worked example" "0" "$EX_RC"
EX_REC=$(printf '%s\n' "$EX_OUT" | tail -1)
if [ "$EX_RC" = "0" ] && [ -f "$EX_REC" ]; then
  cp "$EX_REC" "$EX_ROOT/before.md"
  GRAD_RC=0
  CRAFT_PROJECT_ROOT="$EX_ROOT" bash "$SCRIPTS_DIR/review-graduate.sh" "$EX_REC" 1 dismissed \
    --by=reviewer --reason="false alarm" >/dev/null 2>&1 || GRAD_RC=$?
  assert_eq "graduate dismisses finding 1" "0" "$GRAD_RC"
  DIFF_OUT=$(diff "$EX_ROOT/before.md" "$EX_REC" || true)
  assert_contains "one line changed and one line added" "^[0-9]*c[0-9]*,[0-9]*$" "$DIFF_OUT"
  assert_contains_literal "the stamped line" "> graduated_to: dismissed" "$DIFF_OUT"
  assert_contains_literal "the inserted line" "> dismissed: reviewer - false alarm" "$DIFF_OUT"
  assert_eq "exactly three diff body lines" "3" "$(printf '%s\n' "$DIFF_OUT" | grep -cE '^[<>]')"
fi

begin_test "Step 5 is the check and Step 5a is gone"
CMD_TEXT=$(cat "$REVIEW_CMD")
assert_contains_literal "Step 5 heading" "### Step 5: Check the Findings" "$CMD_TEXT"
assert_not_contains "no Step 5a" "Step 5a" "$CMD_TEXT"
assert_not_contains "no docs holding file" "review-findings.md" "$CMD_TEXT"
assert_contains_literal "the command names review-capture.sh" "review-capture.sh" "$CMD_TEXT"
assert_contains_literal "the no-commits exit writes no record" "writes no record" "$CMD_TEXT"

begin_test "Step 6 reads the close-out reference and the old menu is gone"
assert_contains_literal "Step 6 reads the reference" "references/review-record.md" "$CMD_TEXT"
assert_not_contains "no Apply fixes option" "Apply fixes" "$CMD_TEXT"
assert_not_contains "no Create stories for issues option" "Create stories for issues" "$CMD_TEXT"
assert_not_contains "no Just informational option" "Just informational" "$CMD_TEXT"

begin_test "the reviewer defines Gates run, Verified and Withdrawn"
REVIEWER_TEXT=$(cat "$REVIEWER")
assert_contains_literal "Gates run line" "Gates run:" "$REVIEWER_TEXT"
assert_contains_literal "Verified list" "## Verified" "$REVIEWER_TEXT"
assert_contains_literal "Withdrawn label" "**Withdrawn.**" "$REVIEWER_TEXT"

begin_test "vocabulary prose check is clean with review-record.md in scope"
VOCAB_RC=0
bash "$PLUGIN_ROOT/tests/test-vocabulary-prose.sh" >/dev/null 2>&1 || VOCAB_RC=$?
assert_eq "test-vocabulary-prose.sh exits 0" "0" "$VOCAB_RC"
assert_contains_literal "review-record.md is in the prose scope" "commands/references/review-record.md" "$(cat "$PLUGIN_ROOT/tests/check-vocabulary-prose-drift.sh")"

finish_tests test-review-wiring
