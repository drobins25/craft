#!/bin/bash
# test-question-cards.sh - Guard the question card reference.
# Questions that take judgment are asked on a typed-reply card, not a widget.
# commands/references/question-card.md teaches the card by its shape, the rules
# around it and four tagged examples; this test pins the literals a model reads
# to write cards in that shape.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

REF="$PLUGIN_ROOT/commands/references/question-card.md"

begin_test "card anatomy literals present"
assert_file_exists "question-card.md exists" "$REF"
REF_TEXT="$(cat "$REF" 2>/dev/null)"
assert_contains_literal "header literal" '**Question 1 of 4:**' "$REF_TEXT"
assert_contains_literal "Today paragraph" '**Today.**' "$REF_TEXT"
assert_contains_literal "proposed marker" '(proposed)' "$REF_TEXT"
assert_contains_literal "pick line" 'My pick is' "$REF_TEXT"
assert_contains_literal "question line" '**Question:** Go with' "$REF_TEXT"
assert_contains_literal "why line" '**Why:**' "$REF_TEXT"

begin_test "reference names its job"
assert_file_exists "question-card.md exists" "$REF"
assert_contains_literal "a card is for a question that takes judgment" 'for a question the user has to think about' "$REF_TEXT"

begin_test "around-the-card literals present"
assert_file_exists "question-card.md exists" "$REF"
assert_contains_literal "settled list heading" 'Settled without asking - say which to reopen' "$REF_TEXT"
assert_contains_literal "read-back opener" 'Ruled (' "$REF_TEXT"
assert_contains_literal "read-back after the write" 'In the story.' "$REF_TEXT"
assert_contains_literal "read-back for a no-op answer" 'kept as planned' "$REF_TEXT"
assert_contains_literal "unchecked claims are marked" 'unverified' "$REF_TEXT"

begin_test "four tagged examples"
assert_file_exists "question-card.md exists" "$REF"
OPENERS="$(grep -c '^<example>$' "$REF" 2>/dev/null || true)"
WRAPPERS="$(grep -c '^<examples>$' "$REF" 2>/dev/null || true)"
assert_eq "four example openers on their own lines" "4" "$OPENERS"
assert_eq "one examples wrapper" "1" "$WRAPPERS"

begin_test "fenced lines under 68 columns"
assert_file_exists "question-card.md exists" "$REF"
# Toggle on three-backtick lines and report the longest line inside a fence.
LONGEST="$(awk '/^```/ { infence = !infence; next } infence { if (length($0) > max) max = length($0) } END { print max + 0 }' "$REF" 2>/dev/null)"
FENCED="$(awk '/^```/ { infence = !infence; next } infence { n++ } END { print n + 0 }' "$REF" 2>/dev/null)"
if [ "${FENCED:-0}" -gt 0 ] && [ "${LONGEST:-999}" -lt 68 ]; then
  echo "  PASS: longest fenced line is $LONGEST columns"; PASS=$((PASS + 1))
else
  echo "  FAIL: fenced lines: $FENCED, longest: $LONGEST (need some, all under 68)"; FAIL=$((FAIL + 1))
fi

begin_test "no widget syntax in the reference"
assert_file_exists "question-card.md exists" "$REF"
assert_eq "no AskUserQuestion" "0" "$(grep -cF 'AskUserQuestion' "$REF" 2>/dev/null || true)"
assert_eq "no question: line" "0" "$(grep -cF 'question: "' "$REF" 2>/dev/null || true)"
assert_eq "no header: line" "0" "$(grep -cF 'header: "' "$REF" 2>/dev/null || true)"

begin_test "no em dash"
assert_file_exists "question-card.md exists" "$REF"
# Build the em dash from its bytes so this file does not carry one itself.
EM_DASH="$(printf '\xe2\x80\x94')"
assert_eq "no em dash" "0" "$(grep -cF "$EM_DASH" "$REF" 2>/dev/null || true)"

# --- The alignment check asks on cards ---
ALIGN="$PLUGIN_ROOT/commands/references/alignment-check.md"
HANDOFF="$PLUGIN_ROOT/commands/references/agent-finding-handoff.md"
PLAN_SKILL="$PLUGIN_ROOT/skills/plan-chunks/SKILL.md"

begin_test "alignment check carries no widget"
assert_file_exists "alignment-check.md exists" "$ALIGN"
assert_eq "no AskUserQuestion in alignment-check.md" "0" "$(grep -cF 'AskUserQuestion' "$ALIGN" 2>/dev/null || true)"
GATE_SPAN="$(sed -n '/^## Phase 0.45: Alignment Gate/,/^## Phase 0.46/p' "$PLAN_SKILL" 2>/dev/null)"
assert_contains_literal "alignment gate span found in SKILL.md" 'alignment' "$GATE_SPAN"
assert_eq "no AskUserQuestion in the alignment gate span" "0" "$(printf '%s\n' "$GATE_SPAN" | grep -cF 'AskUserQuestion' || true)"

begin_test "alignment check reads the card reference"
assert_file_contains "points at question-card.md" 'question-card.md' "$ALIGN"
assert_file_contains "Step 3 heading names the cards" '### Step 3: Surface Gaps on Question Cards' "$ALIGN"
assert_file_contains "one finding per card, sequenced" 'One finding per card, sequenced' "$ALIGN"

begin_test "answer-time write in the alignment loop"
assert_file_contains "ruling is written when the card is answered" 'at answer time' "$ALIGN"
assert_file_contains "a ruled finding is never asked again" 'never asked again' "$ALIGN"
assert_file_contains "settled list heading in the alignment loop" 'Settled without asking - say which to reopen' "$ALIGN"

begin_test "handoff names the question cards"
assert_file_contains "handoff cites the cards that surface gaps" 'before writing the question cards that surface gaps to the user' "$HANDOFF"

# --- Plan-chunks' single-story questions ask on cards ---
S2_SPAN="$(sed -n '/^### S-2/,/^### S-3/p' "$PLAN_SKILL" 2>/dev/null)"
S3_SPAN="$(sed -n '/^### S-3/,/^### S-4/p' "$PLAN_SKILL" 2>/dev/null)"
FORK_SPAN="$(sed -n '/\*\*Step 0 - PLAN FORK check:\*\*/,/\*\*Step 1 - Validate/p' "$PLAN_SKILL" 2>/dev/null)"
S3_OPEN="$(printf '%s\n' "$S3_SPAN" | sed -n '1,6p')"
S4_SPAN="$(sed -n '/^### S-4/,/^### S-5/p' "$PLAN_SKILL" 2>/dev/null)"

begin_test "S-2 and S-3 carry no widget"
assert_contains_literal "S-2 span found" 'PLAN FORK' "$S2_SPAN"
assert_contains_literal "S-3 span found" 'Interactive Triage' "$S3_SPAN"
assert_eq "no AskUserQuestion in S-2" "0" "$(printf '%s\n' "$S2_SPAN" | grep -cF 'AskUserQuestion' || true)"
assert_eq "no question: line in S-2" "0" "$(printf '%s\n' "$S2_SPAN" | grep -cF 'question: "' || true)"
assert_eq "no AskUserQuestion in S-3" "0" "$(printf '%s\n' "$S3_SPAN" | grep -cF 'AskUserQuestion' || true)"
assert_eq "no question: line in S-3" "0" "$(printf '%s\n' "$S3_SPAN" | grep -cF 'question: "' || true)"

begin_test "fork and triage read the card reference"
assert_contains_literal "fork span reads question-card.md" 'question-card.md' "$FORK_SPAN"
assert_contains_literal "S-3 opening reads question-card.md" 'question-card.md' "$S3_OPEN"

begin_test "settled list replaces S-4 summary blocks"
assert_file_contains "settled list heading in SKILL.md" 'Settled without asking' "$PLAN_SKILL"
assert_contains_literal "S-4 span found" 'Implementation Plan' "$S4_SPAN"
assert_not_contains "no Risks Acknowledged block in S-4" 'Risks Acknowledged' "$S4_SPAN"
assert_not_contains "no Decisions you'd want to know block in S-4" "Decisions you'd want to know" "$S4_SPAN"

begin_test "outcomes survive as what happens"
assert_file_contains "keep-as-written outcome" 'keep the plan as the agent wrote it' "$PLAN_SKILL"

begin_test "staying single-story widgets intact"
assert_file_contains "content direction prerequisite" 'question: "This story has no Content Direction yet' "$PLAN_SKILL"
assert_file_contains "content-spark riff offer" 'question: "Want to riff visual options' "$PLAN_SKILL"
assert_file_contains "ready to plan this story" 'question: "Ready to plan this story?"' "$PLAN_SKILL"
assert_contains_literal "ready to plan all stories" 'question: "Ready to plan all [N] stories?"' "$(cat "$PLAN_SKILL")"
assert_file_contains "plan approval" 'question: "Does this implementation plan look complete?"' "$PLAN_SKILL"
assert_file_contains "start now offer" 'question: "Story is ready to implement. Start now?"' "$PLAN_SKILL"

# --- Batch triage asks on cards and lists what it settled ---
BATCH="$PLUGIN_ROOT/skills/plan-chunks/references/batch-triage.md"
BT_ASK_SPAN="$(sed -n '/^### BT-2/,/^### BT-5: Per-Story Approval/p' "$BATCH" 2>/dev/null)"
BT_TIER_SPAN="$(sed -n '/^## Concern Tier Definitions/,/^### Collecting/p' "$BATCH" 2>/dev/null)"
BT_SKILL_SPAN="$(sed -n '/^## Batch Triage/,/^### Critical Rules/p' "$PLAN_SKILL" 2>/dev/null)"
M1B_SPAN="$(sed -n '/Verify "Blocked by: None" declarations/,/^4\. Build the dependency graph/p' "$PLAN_SKILL" 2>/dev/null)"
BT3_SPAN="$(sed -n '/^### BT-3/,/^### The batch settled list/p' "$BATCH" 2>/dev/null)"

begin_test "batch concern questions carry no widget"
assert_contains_literal "BT-2 to BT-5 span found" 'Needs Review' "$BT_ASK_SPAN"
assert_contains_literal "tier table span found" 'Worth noting' "$BT_TIER_SPAN"
assert_contains_literal "SKILL.md Batch Triage span found" 'BT-1' "$BT_SKILL_SPAN"
assert_contains_literal "M-1b step 3 span found" 'blocked by [Y]' "$M1B_SPAN"
for NAME in BT_ASK_SPAN BT_TIER_SPAN BT_SKILL_SPAN M1B_SPAN; do
  assert_eq "no AskUserQuestion in $NAME" "0" "$(printf '%s\n' "${!NAME}" | grep -cF 'AskUserQuestion' || true)"
  assert_eq "no question: line in $NAME" "0" "$(printf '%s\n' "${!NAME}" | grep -cF 'question: "' || true)"
done

SETTLED_SPAN="$(sed -n '/^### The batch settled list/,/^### BT-4/p' "$BATCH" 2>/dev/null)"
begin_test "worth-noting items ask on cards; the settled list holds the rest"
assert_contains_literal "BT-3 span found" 'Worth Noting (per item)' "$BT3_SPAN"
assert_contains_literal "BT-3 keeps the plan as written" 'keeps the plan as the agent wrote it' "$BT3_SPAN"
assert_contains_literal "settled list prints under its heading" 'Settled without asking' "$SETTLED_SPAN"
for NEEDLE in 'AskUserQuestion' 'question: "' 'label:'; do
  assert_eq "BT-3 span holds no $NEEDLE" "0" "$(printf '%s\n' "$BT3_SPAN" | grep -cF -- "$NEEDLE" || true)"
done

begin_test "batch answer-time write covers the cards"
assert_file_contains "write after each answered card" 'after each answered BT-2/BT-3/BT-4 card, apply' "$BATCH"

begin_test "batch reads the card reference"
assert_file_contains "batch points at question-card.md" 'question-card.md' "$BATCH"

begin_test "staying batch widgets intact"
assert_file_contains "per-story approval" 'Approve?"' "$BATCH"
assert_file_contains "adjust feedback" 'What should change about' "$BATCH"
assert_file_contains "batch approve all" 'Approve all at once?"' "$BATCH"
assert_file_contains "next steps" 'question: "What'"'"'s next?"' "$BATCH"
assert_file_contains "all stories failed" 'question: "All stories failed to plan' "$BATCH"
assert_contains_literal "no likely files scan" 'question: "Story [name] has no Likely Files scan' "$(cat "$PLAN_SKILL")"
assert_contains_literal "stories failed to plan" 'question: "[F] stories failed to plan. What should we do?"' "$(cat "$PLAN_SKILL")"
assert_contains_literal "missing content direction" 'question: "[N] stories are missing Content Direction' "$(cat "$PLAN_SKILL")"
assert_file_contains "missing dependencies halt" 'Use AskUserQuestion to let the user fill them in or cancel' "$PLAN_SKILL"

begin_test "pure escape gone, outcomes kept"
assert_file_not_contains "no Skip for now in batch triage" 'Skip for now' "$BATCH"
assert_file_not_contains "no Accept as-is in batch triage" 'Accept as-is' "$BATCH"
assert_file_contains "Flag for implementation survives as an outcome" 'Flag for implementation' "$BATCH"

begin_test "reading question asks on a card"
RESEARCH_INLINE="$PLUGIN_ROOT/commands/references/research-inline.md"
assert_file_contains "research-inline points at question-card.md" 'question-card.md' "$RESEARCH_INLINE"
assert_eq "no AskUserQuestion in research-inline.md" "0" "$(grep -cF 'AskUserQuestion' "$RESEARCH_INLINE" || true)"

begin_test "standalone research menus intact"
CRAFT_RESEARCH="$PLUGIN_ROOT/commands/craft-research.md"
assert_contains_literal "topic picker menu" 'question: "You have [N] research topics' "$(cat "$CRAFT_RESEARCH")"
assert_file_contains "what-to-do menu" 'question: "What would you like to do with this research?"' "$CRAFT_RESEARCH"
assert_file_contains "saved menu" 'question: "Research saved. What next?"' "$CRAFT_RESEARCH"
# Section 4.2 runs from its heading to the next heading of the same level or higher.
DECOMPOSE_SPAN="$(awk '/^#### 4\.2:/ { on = 1; print; next } on && /^#{1,4} / { exit } on { print }' "$CRAFT_RESEARCH")"
assert_contains_literal "4.2 span found" 'Decompose for Deeper Discovery' "$DECOMPOSE_SPAN"
assert_eq "no AskUserQuestion in 4.2" "0" "$(printf '%s\n' "$DECOMPOSE_SPAN" | grep -cF 'AskUserQuestion' || true)"

begin_test "old grammar file retired"
# Built from two parts so this file never holds the retired name itself.
RETIRED="auq-""grammar.md"
assert_eq "retired file is gone" "no" "$([ -e "$PLUGIN_ROOT/commands/references/$RETIRED" ] && echo yes || echo no)"
for F in "$PLUGIN_ROOT/commands/references/alignment-check.md" "$RESEARCH_INLINE" "$BATCH" "$PLAN_SKILL" "$CRAFT_RESEARCH"; do
  assert_file_not_contains "$(basename "$F") does not name the retired file" "$RETIRED" "$F"
done

begin_test "index names no widget for concerns"
INDEX_LINE="$(grep -F '!batch concerns' "$PLUGIN_ROOT/reference/orchestration-index.min" || true)"
assert_contains_literal "batch concerns line present" '!batch concerns' "$INDEX_LINE"
assert_eq "batch concerns line names no AskUserQuestion" "0" "$(printf '%s\n' "$INDEX_LINE" | grep -cF 'AskUserQuestion' || true)"

finish_tests
