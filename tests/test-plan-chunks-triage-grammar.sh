#!/bin/bash
# test-plan-chunks-triage-grammar.sh - Guard plan-chunks' triage contract.
# The single-story questions (the S-2 PLAN FORK and all five S-3 triage
# questions) ask on question cards and read question-card.md at question time;
# batch BT-2, BT-3 and BT-4 ask on cards too, and the batch settled list holds the
# mention-tier decisions and high-confidence concerns. Answers land in the story file at answer time with a
# truthful read-back; BT-6 demotes to reconciliation; BT-5 "Adjust" re-planning
# binds already-landed decisions. The staying widgets (content-spark
# prerequisite, direction gate, S-4 approval, S-6 offer) do not name the card
# reference - that boundary is asserted with scoped block extraction.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

SKILL="$PLUGIN_ROOT/skills/plan-chunks/SKILL.md"
BATCH="$PLUGIN_ROOT/skills/plan-chunks/references/batch-triage.md"

# --- S-2 Step 0: the PLAN FORK asks on a card ---
FORK_BLOCK="$(sed -n '/\*\*Step 0 - PLAN FORK check:\*\*/,/\*\*Step 1 - Validate/p' "$SKILL")"
S3_OPEN="$(sed -n '/^### S-3/,/^\*\*Answer-time write/p' "$SKILL")"

begin_test "S-2 PLAN FORK reads the card reference"
assert_contains "fork block exists" 'PLAN FORK' "$FORK_BLOCK"
assert_contains "fork reads question-card at question time" 'question-card.md' "$FORK_BLOCK"
assert_contains "fork asks as one card" 'one question card' "$FORK_BLOCK"
assert_not_contains "authored escape retired from the fork" "et's discuss" "$FORK_BLOCK"

# --- S-3: one Read covers all five triage questions ---
begin_test "S-3 opens on the Read of the card reference"
assert_contains "S-3 reads question-card before the first question" 'question-card.md' "$S3_OPEN"
assert_contains "one Read covers Steps 1-5" 'Steps 1-5' "$S3_OPEN"
assert_contains "the card reference owns the shape" 'The reference owns the card' "$S3_OPEN"

begin_test "S-3 answer-time write with truthful receipts"
assert_file_contains "write after each answered question" 'after each answered triage question (Steps 1-5), apply' "$SKILL"
assert_file_contains "read-back follows the reference before the next question" 'read-back the reference gives, before the next question renders' "$SKILL"
assert_file_contains "no-op answers say so" 'kept as planned' "$SKILL"
assert_file_contains "durability motive named" 'survive a session that dies mid-triage' "$SKILL"

begin_test "the bare question stems stay dead"
assert_file_not_contains "design-decision bare stem gone" 'A design decision needs revisiting:' "$SKILL"
assert_file_not_contains "cycle-impact bare stem gone" 'Planning revealed a cycle impact:' "$SKILL"

begin_test "anti-collapse and distinct closers survive in SKILL.md"
assert_file_contains "anti-collapse principle intact" 'the anti-collapse principle' "$SKILL"
assert_file_contains "one question per concern intact" 'each concern gets its own individual question card' "$SKILL"
assert_file_contains "Step 2 medium keeps the plan as written" 'keep the plan as the agent wrote it' "$SKILL"
assert_file_contains "Step 5 keeps one story as an outcome" 'the story stays one story' "$SKILL"

begin_test "S-5 knows answers already landed"
assert_file_contains "mark-ready is reconciliation" 'Triage answers already landed in the story file at answer time' "$SKILL"
assert_file_contains "BT-6 flow row reads as reconcile" 'Reconcile - triage adjustments already landed at answer time' "$SKILL"

# The shortcuts that skip cards test the same items the steps send to a card.
assert_file_contains "single-story fast path lists every card trigger" 'no low- or medium-confidence concern, no design check marked concern or invalid, no Cycle Impact outcome' "$SKILL"
assert_file_contains "BT-1 fast path needs zero worth-noting" 'zero needs-review AND zero worth-noting' "$SKILL"
assert_file_contains "batch-approve needs zero BT-3 items" 'BT-3 had zero worth-noting items' "$BATCH"
assert_file_contains "all-informational edge covers medium" 'no low- or medium-confidence concern' "$BATCH"

# --- Batch triage: BT-2/BT-3/BT-4 ask on cards, the settled list holds the rest ---
BT3_SPAN="$(sed -n '/^### BT-3/,/^### The batch settled list/p' "$BATCH")"
SETTLED_SPAN="$(sed -n '/^### The batch settled list/,/^### BT-4/p' "$BATCH")"

begin_test "batch cards read the card reference"
assert_file_contains "batch reads question-card before BT-2/BT-4" 'question-card.md' "$BATCH"
assert_file_contains "templates section renamed" '## Question Templates' "$BATCH"
assert_file_not_contains "widget templates heading gone" 'AskUserQuestion Templates' "$BATCH"
assert_file_contains "proposed option marker lives in the reference" '(proposed)' "$PLUGIN_ROOT/commands/references/question-card.md"

begin_test "batch outcomes survive, pure escapes go"
assert_file_not_contains "BT-2 no longer offers Skip for now" 'Skip for now' "$BATCH"
assert_file_not_contains "BT-3 has no Accept as-is" 'Accept as-is' "$BATCH"
assert_file_contains "BT-4 keeps Flag for implementation" 'Flag for implementation' "$BATCH"
assert_file_contains "flag writes a coordination note to both stories" 'writes a coordination note to both stories' "$BATCH"

begin_test "BT-3 worth-noting items ask on cards"
assert_contains "BT-3 section found" 'Worth Noting (per item)' "$BT3_SPAN"
assert_contains "BT-3 keeps the plan as written" 'keeps the plan as the agent wrote it' "$BT3_SPAN"
assert_not_contains "BT-3 holds no option block" 'label:' "$BT3_SPAN"
assert_contains "settled list prints under its heading" 'Settled without asking' "$SETTLED_SPAN"
assert_contains "the user reopens an item by name" 'reopen' "$SETTLED_SPAN"

begin_test "batch answer-time write covers both sides of BT-4"
assert_file_contains "batch write-per-answer present" 'after each answered BT-2/BT-3/BT-4 card, apply' "$BATCH"
assert_file_contains "a reopened settled item is written the same way" 'reopened settled item is written the same way' "$BATCH"
assert_file_contains "batch no-op receipt present" 'kept as planned' "$BATCH"
assert_file_contains "BT-4 writes both story files at answer time" "writes BOTH stories' coordination notes at answer time" "$BATCH"
assert_file_contains "second side never deferred to BT-6" 'never defer the second side to BT-6' "$BATCH"
assert_file_contains "one story file at a time" 'Per-answer writes touch one story file at a time' "$BATCH"

begin_test "BT-6 is reconciliation and Adjust binds landed decisions"
assert_file_contains "BT-6 demoted to reconciliation" 'BT-6 is reconciliation, not first-write' "$BATCH"
assert_file_contains "Adjust re-plan binds landed decisions" 'BINDING constraints' "$BATCH"
assert_file_contains "receipted answers never silently dropped" 'never silently drop a receipted answer' "$BATCH"

# --- The authored escape stays dead everywhere in plan-chunks ---
begin_test "no authored Let's discuss anywhere in plan-chunks"
assert_file_not_contains "escape absent from SKILL.md (any case)" "et's discuss" "$SKILL"
assert_file_not_contains "escape absent from batch-triage.md (any case)" "et's discuss" "$BATCH"

# --- The hard boundary: non-insight AUQ surfaces stay ungated ---
# Each block is extracted by its stable heading (never edited by this story) so the
# negative is scoped - the card reference legitimately appears elsewhere in SKILL.md.
CONTENT_SPARK_BLOCK="$(sed -n '/^## Phase 0.4: Content Spark Prerequisite Check/,/^## Phase 0.45/p' "$SKILL")"
DIRECTION_BLOCK="$(sed -n '/^## Phase 0.5: Direction Confirmation Gate/,/^## Single-Story Planning/p' "$SKILL")"
S4_BLOCK="$(sed -n '/^### S-4: Present Plan for Approval/,/^### S-5/p' "$SKILL")"
S6_BLOCK="$(sed -n '/^### S-6: Offer Implementation/,/^## Multi-Story Planning/p' "$SKILL")"

begin_test "boundary: staying widgets do not name the card reference"
assert_contains "content-spark block extracted" 'Content Direction' "$CONTENT_SPARK_BLOCK"
assert_not_contains "content-spark prerequisite stays ungated" 'question-card' "$CONTENT_SPARK_BLOCK"
assert_contains "direction gate block extracted" 'Ready to plan this story?' "$DIRECTION_BLOCK"
assert_not_contains "direction gate stays ungated" 'question-card' "$DIRECTION_BLOCK"
assert_contains "S-4 block extracted" 'Does this implementation plan look complete?' "$S4_BLOCK"
assert_not_contains "S-4 approval stays ungated" 'question-card' "$S4_BLOCK"
assert_contains "S-6 block extracted" 'Start now?' "$S6_BLOCK"
assert_not_contains "S-6 offer stays ungated" 'question-card' "$S6_BLOCK"

finish_tests
