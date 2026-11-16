#!/bin/bash
# test-planner-research-request.sh - Guard the planner's outside-world rule and its
# second cord. A load-bearing fact outside the repo is verified with the planner's own
# search; a fact still unsettled after three searches is a claim about a class, which
# comes back as a RESEARCH REQUEST (or, in batch, a Critical Blocker) and never becomes a
# "first test" that captures chosen instances.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

AGENT="$PLUGIN_ROOT/agents/plan-chunks-agent.md"
AGENT_TEXT="$(cat "$AGENT")"

CLASS_TAG='unverifiable class claim - research request raised, never a first test'

begin_test "retired external-validation wording is gone"
assert_not_contains "skip line retired" 'Skip external validation unless the story mentions unfamiliar packages' "$AGENT_TEXT"
assert_not_contains "uncertain-packages line retired" 'For packages, APIs, or integrations you' "$AGENT_TEXT"

begin_test "outside-world rule and three-search tell present"
assert_contains_literal "agent three-search tell" 'three searches' "$AGENT_TEXT"

begin_test "request block carries five fields"
assert_contains_literal "block heading" '## RESEARCH REQUEST' "$AGENT_TEXT"
for f in 'Premise' 'Why load-bearing' 'Without research the plan assumes' 'Question'; do
  assert_contains_literal "field label: $f" "**$f:**" "$(sed -n '/^## RESEARCH REQUEST/,/^```/p' "$AGENT")"
done

begin_test "batch request is a Critical Blocker of type research"
case "$CLASS_TAG" in unverifiable*) echo "  PASS: tag starts with unverifiable"; PASS=$((PASS + 1));; *) echo "  FAIL: tag must start with unverifiable"; FAIL=$((FAIL + 1));; esac

begin_test "removed researcher name stays absent"
bash "$PLUGIN_ROOT/tests/test-plan-researcher-removed.sh" >/dev/null 2>&1 \
  && { echo "  PASS: test-plan-researcher-removed.sh passes"; PASS=$((PASS + 1)); } \
  || { echo "  FAIL: test-plan-researcher-removed.sh fails"; FAIL=$((FAIL + 1)); }

begin_test "no em dash in the new request block"
EM_DASH="$(printf '\xe2\x80\x94')"
assert_not_contains "block has no em dash" "$EM_DASH" "$(sed -n '/^### 2.7b/,/^---/p' "$AGENT")"

SKILL_FILE="$PLUGIN_ROOT/skills/plan-chunks/SKILL.md"
TRIAGE_FILE="$PLUGIN_ROOT/skills/plan-chunks/references/batch-triage.md"
DESIGN_FILE="$PLUGIN_ROOT/DESIGN.md"

begin_test "batch prompt names the request"
assert_file_not_contains "plan-chunks never names craft:research as something to invoke" 'craft:research' "$SKILL_FILE"

TRIAGE_TEXT="$(cat "$TRIAGE_FILE")"

begin_test "every writer of a contract line names the outside-fact receipt"
assert_contains_literal "triage write list names visual-source" '`[visual-source: ...]`' "$TRIAGE_TEXT"

begin_test "DESIGN names the second cord"
DESIGN_TEXT="$(cat "$DESIGN_FILE")"
assert_contains_literal "design names the request" 'RESEARCH REQUEST' "$DESIGN_TEXT"
assert_contains_literal "design names the shared flow" 'research-inline.md' "$DESIGN_TEXT"

finish_tests
