#!/bin/bash
# test-tracker-refresh-wiring.sh - Literal wiring checks for refreshing a cycle from its tracker issue

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

INTAKE="$PLUGIN_ROOT/commands/references/tracker-intake.md"
REFRESH="$PLUGIN_ROOT/commands/references/tracker-refresh.md"
IMPL="$PLUGIN_ROOT/commands/craft-story-implement.md"

echo "=== test-tracker-refresh-wiring.sh ==="
echo ""

has_literal() { [ -f "$1" ] && grep -qF -- "$2" "$1"; }

assert_literal() {
  local desc="$1" file="$2" needle="$3"
  if has_literal "$file" "$needle"; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"; echo "    expected literal: '$needle'"; FAIL=$((FAIL + 1))
  fi
}

refute_literal() {
  local desc="$1" file="$2" needle="$3"
  if has_literal "$file" "$needle"; then
    echo "  FAIL: $desc"; echo "    unexpected literal: '$needle'"; FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  fi
}

begin_test "Detect routes a repeat pickup to refresh"
DETECT=$(sed -n '/^## Detect/,/^## Read/p' "$INTAKE")
assert_contains_literal "find-issue-cycle call" \
  'python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/find-issue-cycle.py" <KEY> "${CRAFT_PROJECT_ROOT:-.}"' "$DETECT"
assert_contains_literal "refresh Read path" \
  '${CLAUDE_PLUGIN_ROOT}/commands/references/tracker-refresh.md' "$DETECT"
assert_contains_literal "no gate and no new cycle" "no gate, no new cycle" "$DETECT"
echo ""

begin_test "refresh sections appear in order"
PREV=0
ORDER_OK=yes
for h in "When this runs" "Read" "Copy what changed" "Stage" "Continue" "At story start" "No tracker tools"; do
  LN=$([ -f "$REFRESH" ] && grep -nx "## $h" "$REFRESH" | head -1 | cut -d: -f1 || true)
  if [ -z "$LN" ] || [ "$LN" -le "$PREV" ]; then ORDER_OK=no; echo "    out of order or missing: $h"; fi
  [ -n "$LN" ] && PREV=$LN
done
assert_eq "seven headings in order" "yes" "$ORDER_OK"
assert_eq "no Skill invocations beyond the Continue hand-offs" "" \
  "$([ -f "$REFRESH" ] && grep -o 'craft:[a-z-]*' "$REFRESH" | sort -u | grep -vx -e craft:craft-cycle-start -e craft:craft-story-continue -e craft:craft-story-implement-auto || true)"
if [ -f "$REFRESH" ] && ! grep -q '—' "$REFRESH"; then
  echo "  PASS: no em dash"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing file or em dash present"; FAIL=$((FAIL + 1))
fi
echo ""

begin_test "refresh pins its exact lines"
assert_literal "hold line" "$REFRESH" '`Nothing new starts on <KEY> until a newer Go.`'
assert_literal "pickup no-tools line, recorded stage" "$REFRESH" \
  "I can't reach <KEY> from here, so <cycle-dir-name> keeps its recorded stage: <stage>."
assert_literal "pickup no-tools line, no stage" "$REFRESH" \
  "I can't reach <KEY> from here, so <cycle-dir-name> works as usual: you decide when to build."
assert_literal "story-start no-tools line, recorded stage" "$REFRESH" \
  "I can't re-read <KEY> from here, so I'm going on its recorded stage: <stage>."
assert_literal "story-start no-tools line, no stage" "$REFRESH" \
  "I can't re-read <KEY> from here, and no Go is on record for it, so craft works as usual."
assert_literal "say printed only on a change" "$REFRESH" 'Print record-go'"'"'s `say` only on `changed=yes`'
assert_literal "stage check runs as written" "$REFRESH" "Stage check runs as written"
assert_literal "record-go call" "$REFRESH" 'python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/record-go.py"'
assert_literal "snapshot-delta call" "$REFRESH" 'python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/snapshot-delta.py"'
assert_literal "go-run stage ceiling for a Go run" "$REFRESH" '## At the stage ceiling'
echo ""

begin_test "re-check sits between Cycle check and Stage check"
CYC_LN=$(grep -n '^\*\*Cycle check:\*\*' "$IMPL" | head -1 | cut -d: -f1)
GO_LN=$(grep -n '^\*\*Go re-check:\*\*' "$IMPL" | head -1 | cut -d: -f1)
STG_LN=$(grep -n '^\*\*Stage check:\*\*' "$IMPL" | head -1 | cut -d: -f1)
if [ -n "$CYC_LN" ] && [ -n "$GO_LN" ] && [ -n "$STG_LN" ] && [ "$CYC_LN" -lt "$GO_LN" ] && [ "$GO_LN" -lt "$STG_LN" ]; then
  echo "  PASS: cycle ($CYC_LN) < re-check ($GO_LN) < stage ($STG_LN)"; PASS=$((PASS + 1))
else
  echo "  FAIL: order cycle='$CYC_LN' re-check='$GO_LN' stage='$STG_LN'"; FAIL=$((FAIL + 1))
fi
BLOCK=$([ -n "$GO_LN" ] && [ -n "$STG_LN" ] && sed -n "${GO_LN},$((STG_LN - 1))p" "$IMPL" || true)
assert_contains_literal "reads At story start" '`## At story start`' "$BLOCK"
assert_contains_literal "asks cycle-stage for source_issue" 'hooks/scripts/cycle-stage.sh' "$BLOCK"
assert_contains_literal "keyed on source_issue" 'source_issue=' "$BLOCK"
echo ""

begin_test "story-implement guards intact"
assert_not_contains "no claims-auditor in the block" "claims-auditor" "$BLOCK"
assert_not_contains "no complete-story.sh in the block" "complete-story.sh" "$BLOCK"
assert_eq "no heading line in the block" "0" "$(printf '%s\n' "$BLOCK" | grep -c '^## ' || true)"
echo ""

begin_test "citations cite every copy"
assert_literal "every comments file" "$INTAKE" "every comments file holding a comment this story draws on"
refute_literal "old newest-of-each rule gone" "$INTAKE" "cite the newest of each kind"
echo ""

begin_test "answered questions section"
ANS=$(sed -n '/^## Answered questions/,/^## Continue/p' "$REFRESH")
STG_AT=$(grep -nx '## Stage' "$REFRESH" | head -1 | cut -d: -f1)
ANS_AT=$(grep -nx '## Answered questions' "$REFRESH" | head -1 | cut -d: -f1)
CON_AT=$(grep -nx '## Continue' "$REFRESH" | head -1 | cut -d: -f1)
if [ -n "$STG_AT" ] && [ -n "$ANS_AT" ] && [ -n "$CON_AT" ] && [ "$STG_AT" -lt "$ANS_AT" ] && [ "$ANS_AT" -lt "$CON_AT" ]; then
  echo "  PASS: Answered questions sits between Stage and Continue"; PASS=$((PASS + 1))
else
  echo "  FAIL: Answered questions not between Stage and Continue"; FAIL=$((FAIL + 1))
fi
assert_contains_literal "runs question-answers.py" 'hooks/scripts/question-answers.py' "$ANS"
assert_contains_literal "never a Go or a stage change" "never a Go and never a stage change" "$ANS"
assert_contains_literal "finished story line" '`<story> was built on a. <option title>; your answer on <KEY> picks <x>.`' "$ANS"
START=$(sed -n '/^## At story start/,/^## No tracker tools/p' "$REFRESH")
assert_contains_literal "story start runs it on the delta" 'question-answers.py` with `--new-in <comments_file>` and print its lines' "$START"
echo ""

finish_tests
