#!/bin/bash
# test-tracker-follow-wiring.sh - Literal wiring checks for following a rewritten tracker issue

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

FOLLOW="$PLUGIN_ROOT/commands/references/tracker-follow.md"
INTAKE="$PLUGIN_ROOT/commands/references/tracker-intake.md"
REFRESH="$PLUGIN_ROOT/commands/references/tracker-refresh.md"
GORUN="$PLUGIN_ROOT/commands/references/go-run.md"
AGENT="$PLUGIN_ROOT/agents/plan-chunks-agent.md"

echo "=== test-tracker-follow-wiring.sh ==="
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

# Text of one "## " section, from its heading to the next "## " heading.
section() { [ -f "$1" ] && awk -v h="## $2" '$0 == h {on=1; next} /^## / {on=0} on' "$1" || true; }

line_of() { [ -f "$1" ] && grep -nxF -- "$2" "$1" | head -1 | cut -d: -f1 || true; }

begin_test "tracker-follow headings in order and no skill invocations"
PREV=0
ORDER_OK=yes
for h in "Check" "The card" "Update" "Keep" "Stop" "Can't read the issue" "Continue"; do
  LN=$(line_of "$FOLLOW" "## $h")
  if [ -z "$LN" ] || [ "$LN" -le "$PREV" ]; then ORDER_OK=no; echo "    out of order or missing: $h"; fi
  [ -n "$LN" ] && PREV=$LN
done
assert_eq "seven headings in order" "yes" "$ORDER_OK"
assert_literal "inline-reference line" "$FOLLOW" "DO NOT invoke this as a skill via the Skill tool"
assert_eq "no craft: skill invocations" "" "$([ -f "$FOLLOW" ] && grep -o 'craft:[a-z-]*' "$FOLLOW" | sort -u || true)"
if [ -f "$FOLLOW" ] && ! grep -q $'\xe2\x80\x94' "$FOLLOW"; then
  echo "  PASS: no em dash"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing file or em dash present"; FAIL=$((FAIL + 1))
fi
echo ""

begin_test "check call and verdict routing pinned"
CHECK="$(section "$FOLLOW" "Check")"
assert_contains_literal "staging file" '${CRAFT_PROJECT_ROOT:-.}/.craft/.intake/<slug>/<slug>-issue-staged.md' "$CHECK"
assert_contains_literal "check call" 'python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/follow-issue.py" check <cycle-dir> --issue <staged> --tool "<tool names as used>"' "$CHECK"
assert_contains_literal "unreadable form" '--unreadable <reason>' "$CHECK"
assert_contains_literal "reasons named" 'no-tools' "$CHECK"
assert_contains_literal "staging folder deleted" 'delete the staging folder' "$CHECK"
assert_contains_literal "current continues silently" '`verdict=current`' "$CHECK"
assert_contains_literal "none continues silently" '`verdict=none`' "$CHECK"
assert_contains_literal "changed goes to the card" '`verdict=changed`' "$CHECK"
assert_contains_literal "unreadable goes to the question" '`verdict=unreadable`' "$CHECK"
assert_contains_literal "only way past is Continue" 'only through `## Continue`' "$CHECK"
echo ""

begin_test "card lines exact"
CARD="$(section "$FOLLOW" "The card")"
assert_contains_literal "header" '**Question 1 of 1:**' "$CARD"
assert_contains_literal "question line" '`Update cycle <N> from <KEY>, keep cycle <N> as it is and plan anyway, or stop here?`' "$CARD"
assert_contains_literal "option a" 'a. Update cycle <N> from <KEY> (proposed)' "$CARD"
assert_contains_literal "option b" 'b. Keep cycle <N> as it is and plan anyway' "$CARD"
assert_contains_literal "option c" 'c. Stop here' "$CARD"
assert_contains_literal "Today leads with the new title" 'new_title' "$CARD"
assert_contains_literal "paste wording" 'your paste of <KEY>' "$CARD"
assert_contains_literal "equal-title wording" 'The title is still "<title>".' "$CARD"
assert_contains_literal "changed lines wording" '<changed_lines> description lines changed, starting with "<first_changed>"' "$CARD"
assert_contains_literal "stories stay as they are" 'Stories already in cycle <N> stay as they are.' "$CARD"
assert_contains_literal "pick line" 'My pick is a.' "$CARD"
assert_contains_literal "Question line" '**Question:** Go with a?' "$CARD"
echo ""

begin_test "update lines exact"
UPDATE="$(section "$FOLLOW" "Update")"
assert_contains_literal "diff fence" '```diff' "$UPDATE"
assert_contains_literal "field order" 'title, target, goals, focus' "$UPDATE"
assert_contains_literal "rewritten line" 'Everything above is rewritten from the new ticket: title, target, goals, focus. Stories already in cycle <N> are not changed.' "$UPDATE"
assert_contains_literal "save line" 'Say yes to save, or tell me what to change.' "$UPDATE"
assert_contains_literal "update call" 'follow-issue.py" update <cycle-dir> --title "<title>" --target "<target>" --focus "<focus>" --goal "<goal>"' "$UPDATE"
assert_contains_literal "update runs only after a yes" 'Run `update` only after a yes' "$UPDATE"
assert_contains_literal "correction redraws one field" 'redraws only the field' "$UPDATE"
assert_contains_literal "prints the say" "update's \`say\`" "$UPDATE"
echo ""

begin_test "keep, stop and can't-read lines exact"
KEEP="$(section "$FOLLOW" "Keep")"
STOP="$(section "$FOLLOW" "Stop")"
CANT="$(section "$FOLLOW" "Can't read the issue")"
assert_contains_literal "keep call" 'follow-issue.py" keep <cycle-dir>' "$KEEP"
assert_contains_literal "keep prints say then continues" "keep's \`say\`" "$KEEP"
assert_contains_literal "stop prints nothing and writes nothing" 'Print nothing and write nothing' "$STOP"
assert_contains_literal "stop ends the flow" 'ends the flow' "$STOP"
assert_contains_literal "can't read prints the say" "check's \`say\`" "$CANT"
assert_contains_literal "can't read question" '`Plan anyway, or stop here?`' "$CANT"
assert_contains_literal "neither runs keep or update" 'Neither runs `keep` or `update`' "$CANT"
echo ""

begin_test "continue carries the bug rule and the goal re-read"
CONT="$(section "$FOLLOW" "Continue")"
assert_contains_literal "bug tickets for cycle-design" '`## Bug tickets`' "$CONT"
assert_contains_literal "bug rule only on a new cycle" 'has no stories yet' "$CONT"
assert_contains_literal "bug rule after an update" 'came through `## Update`' "$CONT"
assert_contains_literal "bug rule skipped otherwise" 'On every other route, skip it.' "$CONT"
assert_contains_literal "intake path" '${CLAUDE_PLUGIN_ROOT}/commands/references/tracker-intake.md' "$CONT"
assert_contains_literal "plan-chunks goal re-read" 'CYCLE_GOAL:' "$CONT"
assert_contains_literal "goal read from cycle.yaml" 'cycle.yaml' "$CONT"
echo ""

begin_test "go run answers the card through go-run.md"
assert_literal "go-run named" "$FOLLOW" '${CLAUDE_PLUGIN_ROOT}/commands/references/go-run.md'
assert_literal "known prompts named" "$FOLLOW" '`## Known prompts`'
if [ -f "$FOLLOW" ] && grep -q '^\*\*Under a Go run' "$FOLLOW"; then
  echo "  FAIL: a line starts with **Under a Go run"; FAIL=$((FAIL + 1))
else
  echo "  PASS: no line starts with **Under a Go run"; PASS=$((PASS + 1))
fi
echo ""

begin_test "no forbidden words on screen"
FORBIDDEN='re-source|stale|superseded|context index'
if [ -f "$FOLLOW" ] && ! grep -qiE "$FORBIDDEN" "$FOLLOW"; then
  echo "  PASS: tracker-follow.md avoids the forbidden words"; PASS=$((PASS + 1))
else
  echo "  FAIL: missing file or a forbidden word in tracker-follow.md"; FAIL=$((FAIL + 1))
fi
CONCERN='This story was written from an earlier version of <KEY>; I planned from <KEY>'"'"'s current text.'
GOROW="$(grep -F 'Update from Claude' "$GORUN" || true)"
if [ -n "$GOROW" ] && ! echo "$GOROW" | grep -qiE "$FORBIDDEN"; then
  echo "  PASS: go-run row avoids the forbidden words"; PASS=$((PASS + 1))
else
  echo "  FAIL: go-run row missing or carries a forbidden word"; FAIL=$((FAIL + 1))
fi
assert_literal "agent concern line" "$AGENT" "$CONCERN"
if echo "$CONCERN" | grep -qiE "$FORBIDDEN"; then
  echo "  FAIL: agent concern carries a forbidden word"; FAIL=$((FAIL + 1))
else
  echo "  PASS: agent concern avoids the forbidden words"; PASS=$((PASS + 1))
fi
echo ""

begin_test "Type paragraph sits after the pinned Stage span"
HOLD_AT="$(grep -n '^Then delete the staging folder and stop. No cycle and no stories.' "$INTAKE" | head -1 | cut -d: -f1)"
TYPE_AT="$(grep -n 'right after the Status line' "$INTAKE" | head -1 | cut -d: -f1)"
BRIEF_AT="$(grep -n '^## The brief' "$INTAKE" | head -1 | cut -d: -f1)"
if [ -n "$HOLD_AT" ] && [ -n "$TYPE_AT" ] && [ -n "$BRIEF_AT" ] && [ "$HOLD_AT" -lt "$TYPE_AT" ] && [ "$TYPE_AT" -lt "$BRIEF_AT" ]; then
  echo "  PASS: hold ($HOLD_AT) < Type ($TYPE_AT) < The brief ($BRIEF_AT)"; PASS=$((PASS + 1))
else
  echo "  FAIL: order hold='$HOLD_AT' type='$TYPE_AT' brief='$BRIEF_AT'"; FAIL=$((FAIL + 1))
fi
assert_literal "Type line grammar" "$INTAKE" 'the issue file carries `Type: <type as the tool shows it>`'
READ="$(section "$INTAKE" "Read")"
assert_contains_literal "Read fetches the type" 'type' "$READ"
AFTER="$(section "$INTAKE" "After the cycle exists")"
assert_contains_literal "current mark" '(current)' "$AFTER"
assert_contains_literal "other mark" '(superseded)' "$AFTER"
assert_contains_literal "marks never touch a copy" 'never touch a copy file' "$AFTER"
echo ""

begin_test "Bug tickets section and exact line"
BUG_AT="$(grep -n '^## Bug tickets' "$INTAKE" | head -1 | cut -d: -f1)"
STAGES_AT="$(grep -n '^## Stages in Craft' "$INTAKE" | head -1 | cut -d: -f1)"
CITES_AT="$(grep -n '^## Story citations' "$INTAKE" | head -1 | cut -d: -f1)"
if [ -n "$BUG_AT" ] && [ -n "$STAGES_AT" ] && [ -n "$CITES_AT" ] && [ "$CITES_AT" -lt "$BUG_AT" ] && [ "$BUG_AT" -lt "$STAGES_AT" ]; then
  echo "  PASS: Bug tickets sits before Stages in Craft"; PASS=$((PASS + 1))
else
  echo "  FAIL: order cites='$CITES_AT' bug='$BUG_AT' stages='$STAGES_AT'"; FAIL=$((FAIL + 1))
fi
BUG="$(section "$INTAKE" "Bug tickets")"
assert_contains_literal "exact line" 'This reads as a bug report, not a design. I'"'"'ll treat the ticket as the problem and ask you what the story should do.' "$BUG"
assert_contains_literal "question" '`What should the story do?`' "$BUG"
echo ""

begin_test "refresh records the change in one sentence"
COPY="$(section "$REFRESH" "Copy what changed")"
assert_contains_literal "recorded in the cycle" 'tracker-follow.md' "$COPY"
PREV=0
ORDER_OK=yes
for h in "When this runs" "Read" "Copy what changed" "Stage" "Continue" "At story start" "No tracker tools"; do
  LN=$(line_of "$REFRESH" "## $h")
  if [ -z "$LN" ] || [ "$LN" -le "$PREV" ]; then ORDER_OK=no; fi
  [ -n "$LN" ] && PREV=$LN
done
assert_eq "refresh keeps its seven headings" "yes" "$ORDER_OK"
echo ""

begin_test "go-run rows and the two-exception sentence"
KNOWN="$(section "$GORUN" "Known prompts")"
STOPS="$(section "$GORUN" "What still stops")"
assert_contains_literal "card row" 'Update cycle <N> from <KEY>' "$KNOWN"
assert_contains_literal "log line" "Answered 'Update cycle <N> from <KEY>' with 'a. Update cycle <N> from <KEY>' (recommended)." "$KNOWN"
assert_contains_literal "post heading" '## Update from Claude - cycle <N> follows <KEY>' "$KNOWN"
assert_contains_literal "post gated on the Questions line" 'questions_line=Questions go to: the issue' "$KNOWN"
assert_contains_literal "post carries the unchanged-stories line" 'Stories already in cycle <N> are not changed.' "$KNOWN"
assert_contains_literal "confirmed post line" 'Posted the update to cycle <N> on <KEY>.' "$KNOWN"
assert_contains_literal "unconfirmed post line" "I couldn't post this on <KEY>, so the update is only in this log." "$KNOWN"
assert_contains_literal "plan anyway row" '`Plan anyway, or stop here?`' "$KNOWN"
assert_contains_literal "free-text row" '`What should the story do?`' "$KNOWN"
assert_contains_literal "second exception" 'The cycle-update post named in `## Known prompts` is the second exception' "$STOPS"
assert_contains_literal "first exception kept" "A question posted under ## Product forks is the one exception, because the Go's Questions line already says yes to it." "$STOPS"
HEADINGS="$(grep '^## ' "$GORUN" 2>/dev/null | tr '\n' '|' || true)"
assert_eq "still eight headings" "## When a run is a Go run|## Answering a prompt|## What still stops|## Product forks|## Known prompts|## Planning|## At the stage ceiling|## After compaction|" "$HEADINGS"
echo ""

begin_test "agent reads current rows"
GUARD_AT="$(grep -n '^\*\*Missing Reference Materials on a planning-sourced story' "$AGENT" | head -1 | cut -d: -f1)"
ROWS_AT="$(grep -n '^\*\*Tracker rows marked current or superseded' "$AGENT" | head -1 | cut -d: -f1)"
NEXT_AT="$(grep -n '^### 1.4 Research Principles' "$AGENT" | head -1 | cut -d: -f1)"
if [ -n "$GUARD_AT" ] && [ -n "$ROWS_AT" ] && [ -n "$NEXT_AT" ] && [ "$GUARD_AT" -lt "$ROWS_AT" ] && [ "$ROWS_AT" -lt "$NEXT_AT" ]; then
  echo "  PASS: paragraph ($ROWS_AT) sits after the planning-sourced guard ($GUARD_AT)"; PASS=$((PASS + 1))
else
  echo "  FAIL: order guard='$GUARD_AT' rows='$ROWS_AT' next='$NEXT_AT'"; FAIL=$((FAIL + 1))
fi
assert_literal "reads the current row" "$AGENT" "read only the \`(current)\` row's issue copy"
assert_literal "citations never edited" "$AGENT" 'never edit the citation lines'
assert_literal "unmarked rows read as cited" "$AGENT" 'Unmarked rows are read as cited.'
echo ""

# Entry points: each guard is one paragraph that precedes the work it protects.
DEFAULT_MODE="$PLUGIN_ROOT/commands/references/cycle-design/default-mode.md"
DETAILING_MODE="$PLUGIN_ROOT/commands/references/cycle-design/detailing-mode.md"
PLAN_SKILL="$PLUGIN_ROOT/skills/plan-chunks/SKILL.md"

# first_line_of <file> <fixed prefix>: line number of the first line starting with the prefix
first_line_of() { [ -f "$1" ] && grep -nF -- "$2" "$1" | grep -F ":$2" | head -1 | cut -d: -f1 || true; }

check_guard() {
  local desc="$1" file="$2" before="$3" guard_ln before_ln para
  guard_ln=$(first_line_of "$file" '**Tracker issue check**')
  before_ln=$(line_of "$file" "$before")
  if [ -n "$guard_ln" ] && [ -n "$before_ln" ] && [ "$guard_ln" -lt "$before_ln" ]; then
    echo "  PASS: $desc guard precedes $before"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc guard (line '${guard_ln:-none}') must precede $before (line '${before_ln:-none}')"; FAIL=$((FAIL + 1))
  fi
  para=$([ -n "$guard_ln" ] && sed -n "${guard_ln}p" "$file" || true)
  assert_contains_literal "$desc names tracker-follow.md" 'commands/references/tracker-follow.md' "$para"
  assert_contains_literal "$desc is conditioned on source_issue" 'source_issue' "$para"
  assert_contains_literal "$desc continues only through Continue" '## Continue' "$para"
  assert_eq "$desc has one guard" "1" "$(grep -c '^\*\*Tracker issue check\*\*' "$file" || true)"
}

begin_test "guards at the entry points"
check_guard "default-mode" "$DEFAULT_MODE" "### Step 2: Story Brainstorm"
check_guard "detailing-mode" "$DETAILING_MODE" "### Step D1: Show Current State"
check_guard "plan-chunks" "$PLAN_SKILL" "### 0.1b Gather Sibling Context (Smart)"
assert_eq "default-mode Go paragraphs unchanged" "0" "$(grep -c '^\*\*Under a Go run' "$DEFAULT_MODE" || true)"
assert_eq "detailing-mode Go paragraphs unchanged" "0" "$(grep -c '^\*\*Under a Go run' "$DETAILING_MODE" || true)"
assert_eq "plan-chunks Go paragraphs unchanged" "1" "$(grep -c '^\*\*Under a Go run' "$PLAN_SKILL" || true)"
echo ""

finish_tests
