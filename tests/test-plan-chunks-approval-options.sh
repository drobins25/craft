#!/bin/bash
# test-plan-chunks-approval-options.sh - Guard plan-chunks' single-story approval prompt:
# exactly two forward options (neither recommended), a hand-back rule shared by both
# "start implementing" handlers, the dead edit/explore handlers gone, and a visual gate
# that stays silent for non-UI stories. Blocks are extracted by heading so a stray
# match elsewhere in the file cannot satisfy or break an assertion. Also guards
# cycle-start carrying an already-chosen story through activation without re-asking.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

SKILL="$PLUGIN_ROOT/skills/plan-chunks/SKILL.md"

S4_BLOCK="$(sed -n '/^### S-4: Present Plan for Approval/,/^### S-5/p' "$SKILL")"
S5_BLOCK="$(sed -n '/^### S-5: Finalize Story/,/^### S-6/p' "$SKILL")"
S6_BLOCK="$(sed -n '/^### S-6: Offer Implementation/,/^## Multi-Story Planning/p' "$SKILL")"
NOW_HANDLER="$(sed -n '/^\*\*If "Mark ready and start implementing now":\*\*/,/^### S-6/p' <<< "$S5_BLOCK")"
IMPLEMENT_HANDLER="$(sed -n '/^\*\*If "Yes, implement now":\*\*/,/^\*\*If "Plan another story first":\*\*/p' <<< "$S6_BLOCK")"
BATCH="$PLUGIN_ROOT/skills/plan-chunks/references/batch-triage.md"
BT5_BLOCK="$(sed -n '/^### BT-5: Per-Story Approval/,/^### BT-5: Adjust Feedback/p' "$BATCH")"
P046_BLOCK="$(sed -n '/^## Phase 0.46/,/^## Phase 0.5/p' "$SKILL")"
CRITICAL_BLOCK="$(sed -n '/^### Critical Rules/,/^## Reference Notes/p' "$SKILL")"
BT7_BLOCK="$(sed -n '/^### BT-7: Next Steps/,/^## Cohesion Check Heuristics/p' "$BATCH")"

begin_test "S-4 offers exactly two options, in order, recommending neither"
assert_contains "S-4 block extracted" 'Does this implementation plan look complete?' "$S4_BLOCK"
assert_eq "two labels" "2" "$(echo "$S4_BLOCK" | grep -c 'label:')"
assert_eq "first label" '  - label: "Yes, mark ready"' "$(echo "$S4_BLOCK" | grep 'label:' | sed -n 1p)"
assert_eq "second label" '  - label: "Mark ready and start implementing now"' "$(echo "$S4_BLOCK" | grep 'label:' | sed -n 2p)"
assert_not_contains "nothing marked recommended" '(Recommended)' "$S4_BLOCK"

begin_test "removed approval options and their breadcrumb stay dead"
assert_not_contains "no Explore creatively label" '"Explore creatively"' "$(cat "$SKILL")"
assert_not_contains "no More detail handler" 'More detail on a chunk' "$(cat "$SKILL")"
assert_not_contains "no Adjust the approach handler" 'Adjust the approach' "$(cat "$SKILL")"
assert_not_contains "no orphaned too-big handler" 'This is too big' "$(cat "$SKILL")"
assert_not_contains "no continuation breadcrumb" '\.continuation' "$(cat "$SKILL")"

begin_test "Confirm gate is untouched"
assert_file_contains "Explore creatively first survives" 'Explore creatively first' "$SKILL"
assert_file_contains "Adjust the scope survives" 'Adjust the scope' "$SKILL"

begin_test "new handler marks ready and hands back to a waiting caller"
assert_contains "new handler exists" 'If "Mark ready and start implementing now"' "$S5_BLOCK"
assert_contains "marks the story ready" 'update-story-status.sh' "$NOW_HANDLER"
assert_contains_literal "hand-back trigger" 'a calling flow is waiting to resume' "$S5_BLOCK"
assert_contains_literal "decided from conversation" 'never from the args' "$S5_BLOCK"
assert_contains "names story-implement" 'story-implement' "$NOW_HANDLER"
assert_contains "names cycle-start" 'cycle-start' "$NOW_HANDLER"
assert_contains "direct start invokes story-implement" 'craft:craft-story-implement' "$NOW_HANDLER"
assert_contains "guards against inline implementation" 'DO NOT implement directly' "$NOW_HANDLER"
assert_contains_literal "start-now prompt is skipped" 'S-6 does not run' "$NOW_HANDLER"

begin_test "Yes, mark ready handler and S-6 options unchanged"
assert_contains "mark ready handler survives" 'If "Yes, mark ready":' "$S5_BLOCK"
assert_contains_literal "reconciliation sentence survives" 'Triage answers already landed in the story file at answer time' "$S5_BLOCK"
assert_contains "S-6 question unchanged" 'question: "Story is ready to implement. Start now?"' "$S6_BLOCK"
assert_eq "S-6 keeps three labels" "3" "$(echo "$S6_BLOCK" | grep -c 'label:')"
assert_contains "S-6 implement option" 'label: "Yes, implement now"' "$S6_BLOCK"
assert_contains "S-6 plan-another option" 'label: "Plan another story first"' "$S6_BLOCK"
assert_contains "S-6 later option" 'label: "Come back later"' "$S6_BLOCK"

begin_test "Yes, implement now hands back too"
assert_contains "S-6 handler block extracted" 'DO NOT implement directly' "$IMPLEMENT_HANDLER"
assert_contains_literal "S-6 handler applies the hand-back rule" 'a calling flow is waiting to resume' "$IMPLEMENT_HANDLER"
assert_contains "S-6 handler still invokes story-implement for a direct start" 'craft:craft-story-implement' "$IMPLEMENT_HANDLER"

begin_test "non-UI stories pass the visual gate silently"
assert_contains "0.46 block extracted" 'Creative Spark Prerequisite Check' "$P046_BLOCK"
assert_eq "one visual question (the ui branch)" "1" "$(echo "$P046_BLOCK" | grep -c 'question: "Want to riff visual options')"
assert_contains_literal "non-ui continues with no prompt" 'continue to Phase 0.5 with no prompt' "$P046_BLOCK"
assert_not_contains "no non-UI skip option" 'Skip - not a UI story' "$P046_BLOCK"
assert_not_contains "no riff-anyway option" 'Yes, riff anyway' "$P046_BLOCK"
assert_not_contains "no chunk-approval-time promise" 'chunk-approval time' "$P046_BLOCK"
assert_contains_literal "batch skip line no longer promises creative-spark" 'batch planning has no visual-riff step' "$P046_BLOCK"

begin_test "ui visual gate unchanged"
assert_contains_literal "ui riff option" 'Yes, riff with creative-spark (Recommended)' "$P046_BLOCK"
assert_contains_literal "ui skip option" 'Skip - I know what I want' "$P046_BLOCK"

begin_test "batch approval offers Approve, Adjust, Reject"
assert_contains "BT-5 block extracted" 'Approve?' "$BT5_BLOCK"
assert_eq "three labels" "3" "$(echo "$BT5_BLOCK" | grep -c 'label:')"
assert_eq "first label" '  - label: "Approve"' "$(echo "$BT5_BLOCK" | grep 'label:' | sed -n 1p)"
assert_eq "second label" '  - label: "Adjust"' "$(echo "$BT5_BLOCK" | grep 'label:' | sed -n 2p)"
assert_eq "third label" '  - label: "Reject"' "$(echo "$BT5_BLOCK" | grep 'label:' | sed -n 3p)"
assert_not_contains "no Explore in BT-5" 'Explore' "$BT5_BLOCK"

begin_test "batch has no creative re-riff"
assert_not_contains "no creative-spark in batch triage" 'creative-spark' "$(cat "$BATCH")"

begin_test "batch Adjust follow-up intact"
assert_file_contains "Adjust feedback question survives" 'What should change about' "$BATCH"

begin_test "batch summary prose matches"
assert_file_contains "summary names three options" 'Approve/Adjust/Reject' "$SKILL"
assert_not_contains "no Approve/Explore" 'Approve/Explore' "$(cat "$SKILL")"

begin_test "hand-back rule names exactly two waiting flows"
assert_contains_literal "story-new only places the story afterward" 'only places the story afterward' "$S5_BLOCK"
assert_contains_literal "waiting flow carries the choice forward" "carries the user's choice forward" "$S5_BLOCK"
assert_not_contains "no waiting flow starts implementation itself" 'starts implementation itself' "$(cat "$SKILL")"
assert_not_contains "no open-ended waiting-flow definition" 'flow that resumes after planning' "$(cat "$SKILL")"
assert_contains_literal "hand-back looks up the call chain" 'anywhere up the current call chain' "$S5_BLOCK"

begin_test "batch Start implementing applies the hand-back rule"
assert_contains "critical rules block extracted" 'Read story files fresh' "$CRITICAL_BLOCK"
assert_contains_literal "BT-7 rule cites the hand-back rule" 'hand-back rule' "$CRITICAL_BLOCK"
assert_contains_literal "BT-7 rule still invokes story-implement on a direct start" 'craft:craft-story-implement' "$CRITICAL_BLOCK"
assert_contains_literal "BT-7 rule never implements directly" 'never implement directly' "$CRITICAL_BLOCK"

begin_test "batch next-steps hands back to cycle-start"
assert_contains_literal "BT-7 block extracted" 'question: "What'"'"'s next?"' "$BT7_BLOCK"
assert_contains_literal "start description names the hand-back" 'Begin with the first ready story (hands back to cycle-start when it is waiting)' "$BT7_BLOCK"
assert_eq "BT-7 keeps three labels" "3" "$(echo "$BT7_BLOCK" | grep -c 'label:')"
assert_contains_literal "re-plan option survives" 'label: "Re-plan adjusted stories"' "$BT7_BLOCK"
assert_contains_literal "done option survives" 'label: "Done for now"' "$BT7_BLOCK"

begin_test "cycle-start extraction blocks resolve"
CYCLE_START="$PLUGIN_ROOT/commands/craft-cycle-start.md"
STEP2B_BLOCK="$(sed -n '/^### Step 2b: Handle Unplanned Stories/,/^### Step 3: Activate/p' "$CYCLE_START")"
STEP3_BLOCK="$(sed -n '/^### Step 3: Activate/,/^### Step 4/p' "$CYCLE_START")"
STEP4_BLOCK="$(sed -n '/^### Step 4/,/^## Quick Start/p' "$CYCLE_START")"
ONE_AT_A_TIME="$(sed -n '/^\*\*If "Plan one at a time" or "Plan it now":\*\*/,/^\*\*If "Start with ready stories":\*\*/p' <<< "$STEP2B_BLOCK")"
assert_contains "step 2b block extracted" 'Which story do you want to plan first?' "$STEP2B_BLOCK"
assert_contains "step 3 block extracted" 'start-cycle.sh' "$STEP3_BLOCK"
assert_contains "step 4 block extracted" 'Ready to implement this story?' "$STEP4_BLOCK"
assert_contains "one-at-a-time block extracted" 'Planning before cycle start' "$ONE_AT_A_TIME"

begin_test "cycle-start first-story branch returns to Step 2"
assert_contains_literal "first-story branch has a return" 'Return to Step 2 when the story is planned - or straight to Step 3 (Activate) with that story chosen' "$STEP2B_BLOCK"
assert_eq "one-at-a-time return unchanged" "1" "$(echo "$STEP2B_BLOCK" | grep -cF 'Return to Step 2 when all stories are planned.' || true)"
assert_contains_literal "batch return routes Start implementing to Step 3" 'if the user picked "Start implementing" at the end of batch triage' "$STEP2B_BLOCK"

begin_test "cycle-start Step 3 skips the re-asks for a chosen story"
assert_contains_literal "chosen-story paragraph" '**If a story is already chosen, do not re-ask.**' "$STEP3_BLOCK"
assert_contains_literal "single-story now option" 'Mark ready and start implementing now' "$STEP3_BLOCK"
assert_contains_literal "single-story implement option" 'Yes, implement now' "$STEP3_BLOCK"
assert_contains_literal "batch arrival" 'at the end of batch planning' "$STEP3_BLOCK"
assert_contains_literal "batch story is the lowest-numbered" 'lowest-numbered' "$STEP3_BLOCK"
assert_contains_literal "story-implement arrival returns" 'return to story-implement' "$STEP3_BLOCK"

begin_test "cycle-start now means now"
assert_contains_literal "now-means-now paragraph" '**Now means now:**' "$ONE_AT_A_TIME"
assert_contains_literal "rest stay at planning" 'status: planning' "$ONE_AT_A_TIME"
assert_contains_literal "goes straight to activation" 'go straight to Step 3 (Activate) with that story chosen' "$ONE_AT_A_TIME"

begin_test "plain cycle-start keeps its prompts"
assert_contains_literal "ready-to-start prompt" 'question: "Ready to start?"' "$STEP3_BLOCK"
assert_eq "step 3 keeps two labels" "2" "$(echo "$STEP3_BLOCK" | grep -c 'label:')"
assert_contains_literal "implement prompt" 'question: "Ready to implement this story?"' "$STEP4_BLOCK"
assert_contains_literal "story pick prompt" 'question: "Which story do you want to start?"' "$STEP4_BLOCK"
assert_contains_literal "hand-off skill" 'skill: "craft:craft-story-implement"' "$STEP4_BLOCK"

begin_test "story-implement Step 3 skips its own re-ask for a chosen story"
STORY_IMPLEMENT="$PLUGIN_ROOT/commands/craft-story-implement.md"
SI_STEP3_BLOCK="$(sed -n '/^### Step 3: Review Before Starting/,/^### Step 3a/p' "$STORY_IMPLEMENT")"
assert_contains_literal "step 3 block extracted" 'Start with Chunk 1?' "$SI_STEP3_BLOCK"
assert_contains_literal "chosen-story paragraph" '**If a story is already chosen, do not re-ask.**' "$SI_STEP3_BLOCK"
assert_contains_literal "card counts as chosen" 'picked on the /craft card' "$SI_STEP3_BLOCK"
assert_contains_literal "plan-chunks and cycle-start count as chosen" 'handed here by plan-chunks or cycle-start' "$SI_STEP3_BLOCK"
assert_contains_literal "args count as chosen" 'named in the arguments' "$SI_STEP3_BLOCK"
assert_contains_literal "review becomes a statement" 'as a statement with no question under it' "$SI_STEP3_BLOCK"
assert_contains_literal "goes straight to 3a" 'go straight to Step 3a' "$SI_STEP3_BLOCK"
assert_contains_literal "paragraph precedes the question" '**If a story is already chosen, do not re-ask.**' "$(echo "$SI_STEP3_BLOCK" | sed -n '/Start with Chunk 1?/q;p')"

finish_tests
