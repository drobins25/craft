#!/bin/bash
# test-plan-chunks-triage-grammar.sh - Guard story 17's plan-chunks gate-grammar contract.
# Plan-chunks' insight-bearing questions (the S-2 PLAN FORK, all five S-3 triage
# questions, batch BT-2/BT-3/BT-4) read the worked exemplar (auq-grammar.md) at
# question time; answers land in the story file at answer time with a truthful
# receipt line; BT-6 demotes to reconciliation; BT-5 "Adjust" re-planning binds
# already-landed decisions. The distinct closers survive, and NO non-insight AUQ
# surface (content-spark prerequisite, direction gate, S-4 approval, S-6 offer)
# adopts the grammar - that boundary is asserted with scoped block extraction.
# A paraphrase, a resurrected bare question stem, or a boundary leak should fail
# the suite, not slip through review.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

SKILL="$PLUGIN_ROOT/skills/plan-chunks/SKILL.md"
BATCH="$PLUGIN_ROOT/skills/plan-chunks/references/batch-triage.md"
GRAMMAR="$PLUGIN_ROOT/commands/references/auq-grammar.md"

# --- The exemplar names plan-chunks as a reader ---
begin_test "exemplar intro names plan-chunks as a second reader"
assert_file_exists "auq-grammar.md exists" "$GRAMMAR"
assert_file_contains "plan-chunks named as gate-time reader" "plan-chunks' fork and triage" "$GRAMMAR"
assert_file_contains "alignment check still named first" 'the alignment check at Step 3' "$GRAMMAR"

# --- S-2 Step 0: the PLAN FORK reads the exemplar ---
FORK_BLOCK="$(sed -n '/\*\*Step 0 - PLAN FORK check:\*\*/,/\*\*Step 1 - Validate/p' "$SKILL")"

begin_test "S-2 PLAN FORK reads the exemplar and mirrors the fork gate"
assert_contains "fork block exists" 'PLAN FORK' "$FORK_BLOCK"
assert_contains "fork reads auq-grammar at gate time" 'auq-grammar.md' "$FORK_BLOCK"
assert_contains "recommended branch first, labeled" '(Recommended)' "$FORK_BLOCK"
assert_contains "honest verdict per branch" 'honest one-line verdict' "$FORK_BLOCK"
assert_not_contains "authored escape retired from the fork" "et's discuss" "$FORK_BLOCK"
assert_contains "question field self-contained" 'one or two sentences of the problem' "$FORK_BLOCK"

# --- S-3: one gate-time Read covers all five triage questions ---
begin_test "S-3 opens on the gate-time Read of the exemplar"
assert_file_contains "S-3 reads auq-grammar before constructing questions" 'Before constructing any triage AskUserQuestion (Steps 1-5), Read' "$SKILL"
assert_file_contains "mirror matched to the question kind" 'mirror the worked gate that matches the question' "$SKILL"
assert_file_contains "fork vs dead end named" 'a fact that decides itself is a dead end' "$SKILL"
assert_file_contains "question fields stand alone" 'answerable by someone who saw nothing above it' "$SKILL"
assert_file_contains "grammar governs shape, never outcomes" 'it never changes which outcomes' "$SKILL"

begin_test "S-3 answer-time write with truthful receipts"
assert_file_contains "write after each answered question" 'after each answered triage question (Steps 1-5), apply' "$SKILL"
assert_file_contains "receipt before the next question" 'one truthful receipt line before the next question renders' "$SKILL"
assert_file_contains "no-op answers say so" 'kept as planned' "$SKILL"
assert_file_contains "durability motive named" 'survive a session that dies mid-triage' "$SKILL"

begin_test "the bare question stems stay dead"
assert_file_not_contains "design-decision bare stem gone" 'A design decision needs revisiting:' "$SKILL"
assert_file_not_contains "cycle-impact bare stem gone" 'Planning revealed a cycle impact:' "$SKILL"

begin_test "anti-collapse and distinct closers survive in SKILL.md"
assert_file_contains "anti-collapse principle intact" 'the anti-collapse principle' "$SKILL"
assert_file_contains "one question per concern intact" 'each concern gets its own individual AskUserQuestion' "$SKILL"
assert_file_contains "Step 2 medium keeps Accept as-is" 'Accept as-is' "$SKILL"
assert_file_contains "Step 5 keeps Continue as-is" 'Continue as-is' "$SKILL"

begin_test "S-5 knows answers already landed"
assert_file_contains "mark-ready is reconciliation" 'Triage answers already landed in the story file at answer time' "$SKILL"
assert_file_contains "BT-6 flow row reads as reconcile" 'Reconcile - triage adjustments already landed at answer time' "$SKILL"

# --- Batch triage: BT-2/3/4 read the exemplar, closers survive ---
begin_test "batch templates read the exemplar and mirror the fork gate"
assert_file_contains "batch reads auq-grammar before BT-2/3/4" 'Before constructing any BT-2/BT-3/BT-4 AskUserQuestion, Read' "$BATCH"
assert_file_contains "batch mirror rule present" 'mirror the worked gate that matches the question' "$BATCH"
assert_file_contains "recommendation first in batch templates" '(Recommended)' "$BATCH"
assert_file_contains "grammar never changes outcomes in batch" 'it never changes which outcomes a template offers' "$BATCH"

begin_test "batch distinct closers survive verbatim"
assert_file_contains "BT-2 keeps Skip for now" 'Skip for now' "$BATCH"
assert_file_contains "BT-3 keeps Accept as-is" 'Accept as-is' "$BATCH"
assert_file_contains "BT-4 keeps Flag for implementation" 'Flag for implementation' "$BATCH"

begin_test "batch answer-time write covers both sides of BT-4"
assert_file_contains "batch write-per-answer present" 'after each answered BT-2/BT-3/BT-4 question, apply' "$BATCH"
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
# negative is scoped - auq-grammar.md legitimately appears elsewhere in SKILL.md.
CONTENT_SPARK_BLOCK="$(sed -n '/^## Phase 0.4: Content Spark Prerequisite Check/,/^## Phase 0.45/p' "$SKILL")"
DIRECTION_BLOCK="$(sed -n '/^## Phase 0.5: Direction Confirmation Gate/,/^## Single-Story Planning/p' "$SKILL")"
S4_BLOCK="$(sed -n '/^### S-4: Present Plan for Approval/,/^### S-5/p' "$SKILL")"
S6_BLOCK="$(sed -n '/^### S-6: Offer Implementation/,/^## Multi-Story Planning/p' "$SKILL")"

begin_test "boundary: non-insight AUQ surfaces do not reference the exemplar"
assert_contains "content-spark block extracted" 'Content Direction' "$CONTENT_SPARK_BLOCK"
assert_not_contains "content-spark prerequisite stays ungated" 'auq-grammar' "$CONTENT_SPARK_BLOCK"
assert_contains "direction gate block extracted" 'Ready to plan this story?' "$DIRECTION_BLOCK"
assert_not_contains "direction gate stays ungated" 'auq-grammar' "$DIRECTION_BLOCK"
assert_contains "S-4 block extracted" 'Does this implementation plan look complete?' "$S4_BLOCK"
assert_not_contains "S-4 approval stays ungated" 'auq-grammar' "$S4_BLOCK"
assert_contains "S-6 block extracted" 'Start now?' "$S6_BLOCK"
assert_not_contains "S-6 offer stays ungated" 'auq-grammar' "$S6_BLOCK"

finish_tests
