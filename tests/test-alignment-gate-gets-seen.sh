#!/bin/bash
# test-alignment-gate-gets-seen.sh - Guard story 16's alignment-gate contract.
# The gate's five fixes live as exact strings: the Explore prompt's plain-language
# instruction (Step 1), the objective ask-vs-act filter (Step 2), the gate-time Read
# of the worked exemplar in place of the deleted batching mandate (Step 3), and the
# exemplar file itself modeling the full gate (lean + (Recommended)-first widget +
# 3-option shape). A paraphrase or a resurrected "group related findings" mandate
# should fail the suite, not slip through review.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

ALIGN="$PLUGIN_ROOT/commands/references/alignment-check.md"
GRAMMAR="$PLUGIN_ROOT/commands/references/auq-grammar.md"

# --- Step 1: findings arrive in the user's language ---
begin_test "Step 1 instructs plain-language findings at the source"
assert_file_exists "alignment-check.md exists" "$ALIGN"
assert_file_contains "plain-language instruction present" 'plain language the user can read cold' "$ALIGN"

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
assert_file_contains "every surfaced fork ends on the lean" 'ends on your lean and marks the recommended option' "$ALIGN"

# --- Step 3: reads the exemplar, one finding at a time ---
begin_test "Step 3 reads the worked exemplar at gate time"
assert_file_contains "exemplar Read mandate present" 'auq-grammar.md' "$ALIGN"
assert_file_contains "mirror matched to the finding kind" 'mirror the worked gate that matches your finding' "$ALIGN"
assert_file_contains "both gate kinds named" 'That file holds two' "$ALIGN"
assert_file_contains "dead end named as a kind" 'a fact that decides itself is a dead end' "$ALIGN"

begin_test "Step 3 heading frozen for the agent-finding-handoff hardcode"
assert_file_contains "Step 3 heading byte-identical" '### Step 3: Surface Gaps via AskUserQuestion' "$ALIGN"
assert_file_contains "Self-Contained Test paragraph survives" 'Self-Contained Test' "$ALIGN"

begin_test "batching mandate stays dead"
assert_file_not_contains "group-findings mandate gone" 'Group related findings in a single message' "$ALIGN"
assert_file_not_contains "pepper-the-user framing gone" 'pepper the user' "$ALIGN"
assert_file_contains "one finding per widget, sequenced" 'One finding per AskUserQuestion, sequenced' "$ALIGN"

begin_test "worked example lives only in the exemplar"
assert_file_not_contains "no inline checkout widget in alignment-check" 'Checkout only (Recommended)' "$ALIGN"
assert_file_contains "checkout widget lives in the exemplar" 'Checkout only (Recommended)' "$GRAMMAR"

# --- The exemplar models the full gate ---
begin_test "exemplar models the dead-end gate"
assert_file_contains "dead-end worked example present" '## The worked dead end' "$GRAMMAR"
assert_file_contains "dead ends decide themselves" 'a dead end decides itself' "$GRAMMAR"
assert_file_contains "story-fate question modeled" 'What should this story become' "$GRAMMAR"

begin_test "exemplar models the full gate shape"
assert_file_exists "auq-grammar.md exists" "$GRAMMAR"
assert_file_contains "shape-not-content rule" 'mirror the shape, not the content' "$GRAMMAR"
assert_file_contains "scenario declared invented" 'invented' "$GRAMMAR"
assert_file_contains "visible prose named as requirement" 'Visible prose' "$GRAMMAR"
assert_file_contains "airy paragraphs modeled" 'Short, airy paragraphs' "$GRAMMAR"
assert_file_contains "opens from the user's intent" 'Opens from the user' "$GRAMMAR"
assert_file_contains "one finding framing" 'Finding 1 of 1' "$GRAMMAR"
assert_file_contains "bold lean modeled" '\*\*My lean:\*\*' "$GRAMMAR"
assert_file_contains "evidence cited once as a coordinate" 'three call sites' "$GRAMMAR"
assert_file_contains "escape option modeled" "Let's discuss" "$GRAMMAR"
assert_file_contains "header chip carries the position counter" 'header: "1 of 1"' "$GRAMMAR"
assert_file_contains "question field stands alone: problem then ask" 'one or two sentences of the problem, then' "$GRAMMAR"
assert_file_contains "prose is enrichment, never load-bearing" 'the prose enriches, it is never load-bearing' "$GRAMMAR"
assert_file_contains "honest runner-up verdicts" 'honest one-line verdict' "$GRAMMAR"

finish_tests
