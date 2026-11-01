#!/bin/bash
# test-go-run-wiring.sh - Literal wiring checks for a Go run: the brief in tracker intake and the
# shared rule in go-run.md. Sections are sliced by heading so a stray match elsewhere in a file
# cannot satisfy an assertion.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

GORUN="$PLUGIN_ROOT/commands/references/go-run.md"
INTAKE="$PLUGIN_ROOT/commands/references/tracker-intake.md"

echo "=== test-go-run-wiring.sh ==="
echo ""

# has_literal <file> <literal> - exit 0 when the file holds the literal
has_literal() { [ -f "$1" ] && grep -qF -- "$2" "$1"; }

assert_literal() {
  local desc="$1" file="$2" needle="$3"
  if has_literal "$file" "$needle"; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"; echo "    expected literal: '$needle' in $(basename "$file")"; FAIL=$((FAIL + 1))
  fi
}

begin_test "go-run sections in order"
assert_file_exists "go-run.md exists" "$GORUN"
EXPECTED=$'## When a run is a Go run\n## Answering a prompt\n## What still stops\n## Product forks\n## Known prompts\n## Planning\n## At the stage ceiling\n## After compaction'
assert_eq "eight headings, in order" "$EXPECTED" "$(grep '^## ' "$GORUN" || true)"
echo ""

begin_test "brief and rule copy is exact"
assert_literal "autonomy line" "$INTAKE" "I'll answer Craft's own prompts and stop only for product forks."
assert_literal "questions line" "$INTAKE" "Questions go to: here"
assert_literal "unreadable run rules line" "$INTAKE" "I couldn't read the run rules in <KEY>'s newest Go, so I'll bring Craft's prompts to you."
assert_literal "fork stop line" "$GORUN" "This one is a product fork, so it's yours."
assert_literal "needs-your-yes stop line" "$GORUN" "This one needs your yes: <what it would change, in a few words>."
assert_literal "no clear answer line" "$GORUN" "This one has no clear answer from the Go, so it's yours."
assert_literal "re-derive line" "$GORUN" "The copied Go for <KEY> doesn't say to answer Craft's prompts anymore, so I'll bring them to you."
assert_literal "plan ceiling line" "$GORUN" "Stage for <KEY> is plan, so I stop after planning: <R> of <N> stories ready."
assert_literal "build ceiling line" "$GORUN" "Stage for <KEY> is build, so I stop here: every story is built and nothing is pushed."
assert_literal "build and PR ceiling line" "$GORUN" "Stage for <KEY> is build and open the PR: every story is built, and Craft doesn't open PRs, so the PR is the next step outside Craft."
assert_literal "picker log line" "$GORUN" "Answered '<header, else question text>' with '<label>' (recommended)."
assert_literal "card log line" "$GORUN" "Answered '<card question>' with 'a. <option title>' (recommended)."
assert_literal "free text log line" "$GORUN" "Answered '<question>' with '<answer>' (drafted from <KEY>)."
echo ""

begin_test "known prompts exist in their source files"
DESIGN="$PLUGIN_ROOT/commands/craft-cycle-design.md"
DEFAULT="$PLUGIN_ROOT/commands/references/cycle-design/default-mode.md"
SKILL="$PLUGIN_ROOT/skills/plan-chunks/SKILL.md"
BATCH="$PLUGIN_ROOT/skills/plan-chunks/references/batch-triage.md"
ALIGN="$PLUGIN_ROOT/commands/references/alignment-check.md"
SPARK="$PLUGIN_ROOT/commands/references/content-spark-inline.md"
assert_literal "Confirm cycle header" "$DESIGN" 'header: "Confirm cycle"'
assert_literal "Confirm and proceed" "$DESIGN" 'label: "Confirm and proceed"'
assert_literal "Depth header" "$DESIGN" 'header: "Depth"'
assert_literal "Add stories now" "$DESIGN" 'label: "Add stories now"'
assert_literal "Stories header" "$DEFAULT" 'header: "Stories"'
assert_literal "Save these sparks" "$DEFAULT" 'label: "Save these sparks"'
assert_literal "Review header" "$DEFAULT" 'header: "Review"'
assert_literal "Yes, finalize the cycle" "$DEFAULT" 'label: "Yes, finalize the cycle"'
assert_literal "Design header" "$DEFAULT" 'header: "Design"'
assert_literal "Skip for now" "$DEFAULT" 'label: "Skip for now"'
assert_literal "Next step header" "$DEFAULT" 'header: "Next step"'
assert_literal "Plan all [N] stories" "$DEFAULT" 'label: "Plan all [N] stories"'
assert_literal "Plan a story now" "$DEFAULT" 'label: "Plan a story now"'
assert_literal "Prerequisite header" "$SKILL" 'header: "Prerequisite"'
assert_literal "Run content-spark first" "$SKILL" 'Run content-spark first (Recommended)'
assert_literal "Skip - I know what I want" "$SKILL" 'Skip - I know what I want'
assert_literal "Re-plan with the failure list" "$SKILL" 'Re-plan with the failure list'
assert_literal "Yes, mark ready" "$SKILL" 'label: "Yes, mark ready"'
assert_literal "Yes, implement now" "$SKILL" 'label: "Yes, implement now"'
assert_literal "Come back later (S-6)" "$SKILL" 'label: "Come back later"'
assert_literal "Approve" "$BATCH" 'label: "Approve"'
assert_literal "Approve all" "$BATCH" 'label: "Approve all"'
assert_literal "Start implementing" "$BATCH" 'label: "Start implementing"'
assert_literal "Done for now (BT-7)" "$BATCH" 'label: "Done for now"'
assert_literal "Run the alignment check first" "$ALIGN" 'Run the alignment check first'
assert_literal "Content header" "$SPARK" 'header: "Content"'
assert_literal "Keep it" "$SPARK" 'label: "Keep it"'
assert_literal "Yes, that's right" "$SPARK" "label: \"Yes, that's right\""
echo ""

begin_test "every known prompt label is named in go-run.md"
KNOWN="$(sed -n '/^## Known prompts/,/^## Planning/p' "$GORUN")"
for label in "Confirm and proceed" "Add stories now" "Save these sparks" "Yes, finalize the cycle" "Skip for now" \
  "Plan all [N] stories" "Plan a story now" "Run content-spark first (Recommended)" "Skip - I know what I want" \
  "Keep it" "Yes, that's right" "Run the alignment check first" "Re-plan with the failure list" "Yes, mark ready" \
  "Approve all" "Yes, implement now" "Come back later" "Start implementing" "Done for now"; do
  assert_contains_literal "row: $label" "$label" "$KNOWN"
done
assert_contains_literal "row: Approve" '`Approve`' "$KNOWN"
echo ""

begin_test "the brief and go-run.md load only on answer"
BRIEF="$(sed -n '/^## The brief/,/^## Copy/p' "$INTAKE")"
assert_contains_literal "section exists" '## The brief' "$BRIEF"
assert_contains_literal "names go-brief.py" 'go-brief.py' "$BRIEF"
assert_contains_literal "ties the brief lines to answer" 'Only on `prompts=answer`' "$BRIEF"
assert_contains_literal "bring and none print nothing" 'On `bring` or `none`, print nothing' "$BRIEF"
assert_contains_literal "go-run.md read on answer" 'Read `${CLAUDE_PLUGIN_ROOT}/commands/references/go-run.md`' "$BRIEF"
assert_contains_literal "go-run.md never read otherwise" 'On `bring` or `none`, go-run.md is never read.' "$BRIEF"
assert_contains_literal "stage line never repeated" 'never repeated' "$BRIEF"
STAGE_AT="$(grep -n '^## Stage' "$INTAKE" | head -1 | cut -d: -f1)"
BRIEF_AT="$(grep -n '^## The brief' "$INTAKE" | head -1 | cut -d: -f1)"
COPY_AT="$(grep -n '^## Copy' "$INTAKE" | head -1 | cut -d: -f1)"
assert_eq "brief sits between Stage and Copy" "yes" "$([ "$STAGE_AT" -lt "$BRIEF_AT" ] && [ "$BRIEF_AT" -lt "$COPY_AT" ] && echo yes || echo no)"
echo ""

begin_test "no em dash, and the only skill call is cycle-start"
if grep -q $'\xe2\x80\x94' "$GORUN" "$INTAKE"; then
  echo "  FAIL: em dash present"; FAIL=$((FAIL + 1))
else
  echo "  PASS: no em dash"; PASS=$((PASS + 1))
fi
assert_literal "ceiling invokes cycle-start" "$GORUN" 'craft:craft-cycle-start'
NAMED="$(grep -o 'craft:[a-z-]*' "$GORUN" | sort -u | grep -vx -e craft:craft-cycle-start -e craft:craft-story-implement-auto -e craft:craft-cycle-complete -e craft:cycle-design || true)"
assert_eq "only cycle-start, implement-auto, cycle-complete (never invoked) and the cycle-design command are named" "" "$NAMED"
echo ""

begin_test "questions to the issue: rule text pinned"
FORKS=$(sed -n '/^## Product forks/,/^## Known prompts/p' "$GORUN")
STOPS=$(sed -n '/^## What still stops/,/^## Product forks/p' "$GORUN")
assert_contains_literal "blocks: critical blocker" "it is a Critical Blocker" "$FORKS"
assert_contains_literal "blocks: no defensible a" "no option is one Craft would defend as \`a.\`" "$FORKS"
assert_contains_literal "blocks: past scope or stage" "an option goes past the Go's \`Scope:\` or stage" "$FORKS"
assert_contains_literal "blocks: shared write or destructive" "acting on \`a.\` would itself be a shared write or a destructive step" "$FORKS"
assert_contains_literal "every other fork can wait" "Every other fork can wait." "$FORKS"
assert_contains_literal "can-wait closing line" '**If nobody answers:** I go with a and keep working. An answer here is read at the next story start or pickup.' "$FORKS"
assert_contains_literal "blocking closing line" '**If nobody answers:** I stay stopped until you answer, here or in the session.' "$FORKS"
echo ""

begin_test "questions to the issue: gate and shape"
assert_contains_literal "posting gated on the Questions line" 'questions_line=Questions go to: the issue' "$FORKS"
assert_contains_literal "heading form" '## Question from Claude - <topic>' "$FORKS"
assert_contains_literal "three-option cap" "at most three options" "$FORKS"
assert_contains_literal "never a reply" "never an edit, never a reply" "$FORKS"
assert_contains_literal "answer instruction" 'Answer in a new comment: a letter, "yes" for a, or your own words.' "$FORKS"
assert_contains_literal "can-wait session line" "Posted a product fork on <KEY>: <topic>. Going with a. <option title> until you answer there." "$FORKS"
assert_contains_literal "blocking session line" "This one is a product fork, so it's yours. It's posted on <KEY> too, and I'm stopped until you answer." "$FORKS"
assert_contains_literal "session answer comment" "Answered in the session (<topic>): <letter>. <option title>." "$FORKS"
assert_contains_literal "unconfirmed post falls back" "I couldn't post this on <KEY>, so I'm asking here." "$FORKS"
assert_contains_literal "no Go heading in the body" "No line in the body starts with \`## Go\`" "$FORKS"
assert_contains_literal "shared-write bullet carries the exception" "A question posted under ## Product forks is the one exception, because the Go's Questions line already says yes to it." "$STOPS"
assert_not_contains "old 'posts nothing' text gone" "Nothing is posted anywhere" "$FORKS"
echo ""

finish_tests
