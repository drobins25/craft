#!/bin/bash
# test-alignment-gate-gets-seen.sh - Guard story 16's alignment-gate contract.
# The gate's five fixes live as exact strings: the Explore prompt's plain-language
# instruction (Step 1), the objective ask-vs-act filter (Step 2), the gate-time Read
# of the question card reference in place of the deleted batching mandate (Step 3).
# A paraphrase or a resurrected "group related findings" mandate should fail the
# suite, not slip through review. The card's own shape is pinned in
# test-question-cards.sh.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

ALIGN="$PLUGIN_ROOT/commands/references/alignment-check.md"

# --- Step 1: findings arrive in the user's language ---
begin_test "Step 1 instructs plain-language findings at the source"
assert_file_exists "alignment-check.md exists" "$ALIGN"
assert_file_contains "plain-language instruction present" 'plain language the user can read cold' "$ALIGN"

# --- Step 1/4: SendMessage addresses the agentId, never the description ---
begin_test "follow-ups re-spawn seeded - no unreachable message path instructed"
assert_file_contains "description is not an address" 'The description you typed is NOT an address' "$ALIGN"
assert_file_contains "sync spawns expose no address" "does not expose the agent's address" "$ALIGN"
assert_file_contains "seeded re-spawn is the prescribed follow-up" 'Spawn a fresh Explore agent seeded with the original findings' "$ALIGN"
assert_file_contains "never guess at an address" 'Never guess at an address' "$ALIGN"
assert_file_not_contains "unreachable SendMessage template retired" 'the agentId from the spawn result - never the description' "$ALIGN"

# --- Step 2: the objective filter (ask vs act) ---
begin_test "Step 2 is the objective both-true filter"
assert_file_contains "filter heading present" '### Step 2: Filter - What Actually Deserves to Interrupt the User' "$ALIGN"
assert_file_contains "AUQ is not for permission" 'not for permission' "$ALIGN"
assert_file_contains "both-true test present" 'Surface a finding ONLY if BOTH are true' "$ALIGN"
assert_file_contains "decide-and-veto default" 'Decide it and let the user veto later' "$ALIGN"
assert_file_contains "agent-judgment bar named" 'agent-judgment-plus-veto' "$ALIGN"

begin_test "Step 2 removal and collapse rules present"
assert_file_contains "removal test present" 'if I delete this question, is the plan actually worse' "$ALIGN"
assert_file_contains "collapse rule present" 'Collapse before you surface.' "$ALIGN"

begin_test "Step 2 keeps the lean when it does ask"
assert_file_contains "choice-vs-opinion reconciliation" 'the CHOICE is theirs - not that you have no opinion' "$ALIGN"
assert_file_contains "every surfaced fork ends on the lean" 'ends on your lean and the card marks it' "$ALIGN"

# --- Step 3: reads the card reference, one finding at a time ---
begin_test "Step 3 reads the card reference at gate time"
assert_file_contains "card reference Read mandate present" 'question-card.md' "$ALIGN"
assert_file_contains "Self-Contained Test paragraph survives" 'Self-Contained Test' "$ALIGN"

begin_test "Step 3 heading names the cards, matching the agent-finding-handoff cross-reference"
assert_file_contains "Step 3 heading present" '### Step 3: Surface Gaps on Question Cards' "$ALIGN"
assert_file_contains "skip-ahead names the new heading" 'Step 3 (Surface Gaps on Question Cards)' "$ALIGN"

begin_test "batching mandate stays dead"
assert_file_not_contains "group-findings mandate gone" 'Group related findings in a single message' "$ALIGN"
assert_file_not_contains "pepper-the-user framing gone" 'pepper the user' "$ALIGN"
assert_file_contains "one finding per card, sequenced" 'One finding per card, sequenced' "$ALIGN"

begin_test "worked example lives only in the card reference"
assert_file_not_contains "no inline checkout widget in alignment-check" 'Checkout only (Recommended)' "$ALIGN"
assert_file_not_contains "authored escape retired from the gate doc" "et's discuss" "$ALIGN"

finish_tests
