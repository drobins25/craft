#!/bin/bash
# test-research-inline.sh - Guard the shared research reference.
# /craft:research's discover flow lives in commands/references/research-inline.md so the
# alignment check, plan-chunks and the standalone command run one mechanism inline.
# The reference holds the machinery, the two-readings test and the story landing; the
# standalone command keeps its dashboard, browse, resume, deeper and crystallize steps
# and its closing "What next?" question.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

REF="$PLUGIN_ROOT/commands/references/research-inline.md"
CMD="$PLUGIN_ROOT/commands/craft-research.md"
SYNTH="$PLUGIN_ROOT/agents/research-synthesizer.md"

begin_test "shared reference exists and states it is read inline"
assert_file_exists "research-inline.md exists" "$REF"
REF_TEXT="$(cat "$REF" 2>/dev/null)"
assert_contains_literal "never run through the Skill tool" "never through the Skill tool" "$REF_TEXT"

begin_test "discover machinery moved, not dropped"
assert_contains_literal "researcher dispatch" 'craft:researcher' "$REF_TEXT"
assert_contains_literal "synthesizer spawn" 'craft:research-synthesizer' "$REF_TEXT"
assert_contains_literal "partial failure retry" 'PARTIAL_FAILURE' "$REF_TEXT"
assert_contains_literal "folder stub staleness" 'stale_after' "$REF_TEXT"
assert_contains_literal "branch template path" 'research-branch-template.md' "$REF_TEXT"

begin_test "step headings in order"
prev=0
for h in '## Step 1: Draft the Question and Branches' '## Step 2: The Two-Readings Test' \
  '## Step 3: Create the Research Folder' '## Step 4: Dispatch Researchers' \
  '## Step 5: Collect and Build the Manifest' '## Step 6: Spawn the Synthesizer' \
  '## Step 7: Present Results' '## Step 8: Land on the Story' '## Return'; do
  line="$(grep -nF -- "$h" "$REF" 2>/dev/null | head -1 | cut -d: -f1)"
  if [ -n "$line" ] && [ "$line" -gt "$prev" ]; then
    echo "  PASS: heading in order: $h"; PASS=$((PASS + 1)); prev="$line"
  else
    echo "  FAIL: heading missing or out of order: $h"; FAIL=$((FAIL + 1))
  fi
done

begin_test "two-readings test and both outcomes present"
assert_contains_literal "test question" 'Would a different reading of the ask produce a different set of branches?' "$REF_TEXT"
assert_contains_literal "disclosure line" 'Researching: <question>. Branches: <a>, <b>, <c>.' "$REF_TEXT"
assert_contains_literal "card reference named" 'question-card.md' "$REF_TEXT"
assert_contains_literal "proposed marker" '(proposed)' "$REF_TEXT"

begin_test "landing defines run line and anchors"
assert_contains_literal "run line template" '_Research run <YYYY-MM-DD>, <DOOR> door:' "$REF_TEXT"
assert_contains_literal "convergence anchor" '"Convergence Points"' "$REF_TEXT"
assert_contains_literal "open questions anchor" '"Open Questions"' "$REF_TEXT"
assert_contains_literal "findings anchor" '"Findings"' "$REF_TEXT"
assert_contains_literal "section absent state" 'Section absent' "$REF_TEXT"
assert_contains_literal "absent-section fallback precedes Investigation" 'before `## Investigation`' "$REF_TEXT"
assert_contains_literal "comment-only state" 'only the template comment' "$REF_TEXT"
assert_contains_literal "section with entries state" 'Section with entries' "$REF_TEXT"

begin_test "What next stays standalone"
assert_file_contains "command keeps the closing question" 'What next?' "$CMD"
assert_file_not_contains "reference never asks What next" 'What next?' "$REF"

begin_test "standalone command reads the reference"
assert_contains_literal "command Reads the shared reference" '${CLAUDE_PLUGIN_ROOT}/commands/references/research-inline.md' "$(cat "$CMD")"
STEP2="$(sed -n '/^### Step 2: Discover/,/^### Step 3/p' "$CMD")"
assert_not_contains "Step 2 carries no researcher dispatch" 'craft:researcher' "$STEP2"
assert_not_contains "Step 2 carries no synthesizer prompt" 'craft:research-synthesizer' "$STEP2"
assert_contains_literal "Step 2 routes the exhaustive flag" '--exhaustive' "$STEP2"
assert_contains_literal "deep runs elaborate every branch unasked" 'Run Step 3 on every ranked branch' "$STEP2"
STEP3_OPEN="$(sed -n '/^### Step 3:/,/^For each selected branch/p' "$CMD")"
assert_contains_literal "Step 3 opening names both entrances" 'or on every ranked branch under' "$STEP3_OPEN"
assert_contains_literal "reference leaves deep and exhaustive to the command" 'never reach this file' "$REF_TEXT"

begin_test "standalone steps survive and stale step numbers are gone"
for h in '### Step 1: Research Dashboard' '### Step 1b:' '### Step 1c:' '### Step 2: Discover (Phase 1)' '### Step 3:' '### Step 4:' '### Step 6:'; do
  assert_contains_literal "heading kept: $h" "$h" "$(cat "$CMD")"
done
assert_file_not_contains "Step 2.2 retired" 'Step 2\.2' "$CMD"
assert_file_not_contains "Step 2.4 retired" 'Step 2\.4' "$CMD"
assert_file_not_contains "Step 2.5 retired" 'Step 2\.5' "$CMD"
assert_file_not_contains "synthesizer no longer cites Step 2.4" 'Step 2\.4' "$SYNTH"
assert_file_contains "synthesizer names the shared reference" 'research-inline.md Step 6' "$SYNTH"

begin_test "deeper decompose runs the two-readings test"
STEP42="$(sed -n '/^#### 4.2:/,/^#### 4.3:/p' "$CMD")"
assert_contains_literal "4.2 runs the shared Step 2" 'research-inline.md' "$STEP42"
assert_contains "4.2 names Step 2" 'Step 2' "$STEP42"
assert_contains_literal "4.2 answers the reading before spawning" 'answered before anything is spawned' "$STEP42"

begin_test "no em dashes in the new reference"
# Build the em dash from its bytes so this file does not carry one itself.
EM_DASH="$(printf '\xe2\x80\x94')"
assert_file_not_contains "no em dash" "$EM_DASH" "$REF"

finish_tests
