#!/bin/bash
# test-go-run-unchanged.sh - the no-Go text at every Go-aware prompt site stays verbatim.
# Each fixture is the exact text of a span as it read before the Go paragraph was
# added; the span must still appear contiguously in its file.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

FIXTURES="$SCRIPT_DIR/fixtures/go-run-unchanged"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== test-go-run-unchanged.sh ==="
echo ""

# contains_verbatim <file> <fixture>: exit 0 when the fixture text is a contiguous substring
contains_verbatim() {
  python3 -I -c '
import sys
text = open(sys.argv[1], encoding="utf-8").read()
span = open(sys.argv[2], encoding="utf-8").read()
sys.exit(0 if span and span in text else 1)
' "$1" "$2"
}

assert_span() {
  local desc="$1" file="$2" fixture="$3"
  if contains_verbatim "$ROOT/$file" "$FIXTURES/$fixture"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    $fixture is not a verbatim span of $file"
    FAIL=$((FAIL + 1))
  fi
}

assert_go_paragraphs() {
  local desc="$1" file="$2" expected="${3:-1}" count
  count=$(grep -c '^\*\*Under a Go run' "$ROOT/$file" || true)
  assert_eq "$desc: $expected Go paragraph(s)" "$expected" "$count"
  local bare
  bare=$(grep '^\*\*Under a Go run' "$ROOT/$file" | grep -vc 'go-run.md' || true)
  assert_eq "$desc: every Go paragraph names go-run.md" "0" "$bare"
}
assert_one_go_paragraph() { assert_go_paragraphs "$1" "$2" 1; }

begin_test "no-Go gate text unchanged"
assert_span "cycle gate span" commands/craft-cycle-design.md cycle-design-gate.txt

begin_test "no-Go plan-chunks text unchanged"
assert_span "Orchestrator Context span" skills/plan-chunks/SKILL.md plan-chunks-orchestrator-context.txt
assert_span "Question Templates span" skills/plan-chunks/references/batch-triage.md batch-triage-question-templates.txt

begin_test "no-Go intake stage text unchanged"
assert_span "Stage section" commands/references/tracker-intake.md tracker-intake-stage.txt

begin_test "no-Go cycle-start and implement-auto text unchanged"
assert_span "cycle-start Step 3 head" commands/craft-cycle-start.md cycle-start-step3-head.txt
assert_span "cycle-start Step 3 tail" commands/craft-cycle-start.md cycle-start-step3-tail.txt
assert_span "implement-auto Gate Pre-Flight" commands/craft-story-implement-auto.md implement-auto-gate-preflight.txt
assert_span "implement-auto Story Selection Guards" commands/craft-story-implement-auto.md implement-auto-selection-guards.txt

begin_test "no-issue spans at the tracker issue check sites unchanged"
assert_span "default-mode Step 2 head" commands/references/cycle-design/default-mode.md default-mode-step2-head.txt
assert_span "detailing-mode Pre-check" commands/references/cycle-design/detailing-mode.md detailing-precheck.txt
assert_span "plan-chunks Gather Launch Context" skills/plan-chunks/SKILL.md plan-chunks-gather-launch-context.txt

begin_test "one Go paragraph per site"
assert_one_go_paragraph "cycle-design" commands/craft-cycle-design.md
assert_one_go_paragraph "plan-chunks SKILL" skills/plan-chunks/SKILL.md
assert_one_go_paragraph "batch-triage" skills/plan-chunks/references/batch-triage.md
assert_one_go_paragraph "cycle-start" commands/craft-cycle-start.md
assert_go_paragraphs "implement-auto" commands/craft-story-implement-auto.md 2

begin_test "fixtures are not vacuous"
for f in "$FIXTURES"/*.txt "$FIXTURES"/*.expected; do
  lines=$(wc -l < "$f" | tr -d ' ')
  if [ "$lines" -ge 3 ]; then echo "  PASS: $(basename "$f") has $lines lines"; PASS=$((PASS + 1))
  else echo "  FAIL: $(basename "$f") too short"; FAIL=$((FAIL + 1)); fi
done

finish_tests
