#!/bin/bash
# test-muse-gets-seen.sh - Guard Story 6's and Story 20's locked strings across the spec files.
# Doc-level assertions that the muse-visibility edits are specced as locked: the
# prose-then-widget turn presentation rule, the horizon line, the hard-rule annotations,
# the briefing surfacing beats ("Muse's take:" / "Alchemist's take:"), the mockup
# muse path (Story 20: one path, two doors - the reference file, the renamed warm
# option, the design-empty automatic fork, muse_session semantics), and the Phase 0.5
# Emotional Core sell. Adjacent stories edit these same shared files; a paraphrased
# rule, a resurrected silent-fold, or a resurrected (Recommended) marker should fail
# the suite, not slip through review.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

MUSE="$PLUGIN_ROOT/commands/references/muse-inline.md"

# --- Chunk 1: turn presentation rule (prose leads, widget collects) ---
begin_test "muse leads with prose, widget collects the answer"
assert_file_exists "muse-inline.md exists" "$MUSE"
assert_file_contains "turn presentation rule block present" '### Turn presentation' "$MUSE"
assert_file_contains "prose leads in the message body" 'prose in the message body' "$MUSE"
assert_file_contains "widget only captures the answer" 'only captures the answer' "$MUSE"

begin_test "tight-prose and restate-in-question sub-rules present"
assert_file_contains "tight prose sub-rule" 'Keep the prose tight' "$MUSE"
assert_file_contains "restate-in-question sub-rule" 'restates the one essential idea' "$MUSE"

begin_test "AUQ question field never carries the turn's content"
assert_file_contains "question-field prohibition" 'NEVER carries the turn'"'"'s full content' "$MUSE"
assert_file_contains "pipe-separated walls named as the failure" 'no pipe-separated field dumps' "$MUSE"
assert_file_contains "synthesis turn called out" "special force to Step 6" "$MUSE"

# --- Chunk 1: horizon line (one core-derived non-committal image) ---
begin_test "horizon line is one core-derived non-committal image"
assert_file_contains "horizon line beat present" '### The horizon line' "$MUSE"
assert_file_contains "exactly one forward image" 'ONE forward image' "$MUSE"
assert_file_contains "never a list" 'never a list' "$MUSE"
assert_file_contains "derived from the locked core" 'Derived from the locked Killer Moment or Share Trigger' "$MUSE"
assert_file_contains "explicitly not a commitment" 'not a commitment' "$MUSE"
assert_file_contains "notebook offer is ignorable prose" 'one ignorable prose line' "$MUSE"

begin_test "horizon line adds no new AUQ turn"
assert_file_contains "no new AUQ or header in the beat" 'No AskUserQuestion, no new turn `header:`' "$MUSE"
assert_file_contains "turn-cap rule annotated as wrap-not-5th-turn" 'part of the wrap, not a 5th turn' "$MUSE"

# --- Chunk 1: hard rules intact, annotations only ---
begin_test "no-brainstorming redirect survives verbatim"
assert_file_contains "redirect literal intact" 'Save those for cycle planning' "$MUSE"
assert_file_contains "sanctioned-exception note on the rule" 'an image, not a mode' "$MUSE"

begin_test "4-turn cap rule text intact"
assert_file_contains "cap rule literal intact" 'Cap at 4 turns total' "$MUSE"
assert_file_contains "wrap-and-lock literal intact" 'Wrap and lock at turn 4' "$MUSE"

SPARK="$PLUGIN_ROOT/skills/creative-spark/SKILL.md"

# --- Chunk 2: creative-spark surfaces the returning briefings ---
begin_test "creative-spark surfaces the muse briefing verbatim"
assert_file_exists "creative-spark SKILL.md exists" "$SPARK"
assert_file_contains "muse take quoted to the user" "Muse's take:" "$SPARK"
assert_file_contains "verbatim lines, not summary" 'Quote 2-3 verbatim lines' "$SPARK"

begin_test "Full Workshop surfaces the alchemist briefing verbatim"
assert_file_contains "alchemist take quoted to the user" "Alchemist's take:" "$SPARK"
assert_file_contains "both surfaced when both return" 'both briefings surfaced when both return' "$SPARK"

begin_test "surfacing is prose, not a new widget"
assert_file_contains "no new AUQ at the surfacing beat" 'adds no AskUserQuestion' "$SPARK"
assert_file_contains "brief enrichment still feeds Step 2" 'Store the agent briefing(s) as `ENRICHED_BRIEF`' "$SPARK"

MOCKUP="$PLUGIN_ROOT/commands/references/mockup-inline.md"
MUSE_PATH="$PLUGIN_ROOT/commands/references/mockup-muse-path.md"

# --- Story 20: the muse path reference exists and the funnel links it ---
begin_test "muse path reference exists and the funnel routes both doors into it"
assert_file_exists "mockup-inline.md exists" "$MOCKUP"
assert_file_exists "mockup-muse-path.md exists" "$MUSE_PATH"
assert_file_contains "funnel links the reference by plugin-root path" 'CLAUDE_PLUGIN_ROOT}/commands/references/mockup-muse-path.md' "$MOCKUP"

begin_test "reference carries the register requirement and the build-direct handoff"
assert_file_contains "register requirement verbatim" 'every stance must fuse a CONCRETE, BUILDABLE design direction' "$MUSE_PATH"
assert_file_contains "candidate directions section in the prompt" '## Candidate Directions' "$MUSE_PATH"
assert_file_contains "one-shot muse spawn" 'subagent_type: "craft:muse"' "$MUSE_PATH"
assert_file_contains "muse take quoted in the reference" "Muse's take:" "$MUSE_PATH"
assert_file_contains "directions build one-to-one" 'built one-to-one by the alchemist' "$MUSE_PATH"
assert_file_contains "briefing written before the build" 'BEFORE the build begins' "$MUSE_PATH"
assert_file_contains "budget reading is no-widget" 'the muse path renders NO vibe widget' "$MUSE_PATH"
assert_file_contains "no-ranking line in the prompt" 'the user'"'"'s reaction' "$MUSE_PATH"

begin_test "reference carries the parse-guard checklist and retry handling"
assert_file_contains "count check" 'exactly 3 directions came back' "$MUSE_PATH"
assert_file_contains "trade check never fails" 'no invented trades' "$MUSE_PATH"
assert_file_contains "distinctness check" 'rewording of another' "$MUSE_PATH"
assert_file_contains "brevity never fails a stance" 'Never fail a stance for brevity' "$MUSE_PATH"
assert_file_contains "retry once on dead spawn or failed check" 're-spawn the muse ONCE' "$MUSE_PATH"
assert_file_contains "second failure is a plain disclosure" "The muse isn't answering" "$MUSE_PATH"
assert_file_not_contains "no inferred-directions fallback exists" 'fall back to plain' "$MUSE_PATH"

begin_test "Door 1: warm option renamed, unmarked, widget pick is the only warm entry"
assert_file_contains "option label states the handoff" "Let the muse drive" "$MOCKUP"
assert_file_contains "muse option unmarked and listed last" 'the muse option stays unmarked, listed last' "$MOCKUP"
assert_file_contains "widget pick is the only warm entry" 'The widget pick is the ONLY way into the muse path on a warm project' "$MOCKUP"

begin_test "Door 2: design-empty fork enters the muse path automatically"
assert_file_contains "both-absent condition explicit" 'NEITHER `.craft/design/tokens.yaml` NOR `.craft/design/locked.md`' "$MOCKUP"
assert_file_contains "design-empty door builds direct, no widget" 'its three directions build directly as the Diverge round' "$MOCKUP"
assert_file_contains "reuses step 1 facts, no re-scan" 'do not re-scan' "$MOCKUP"

begin_test "muse_session in schema, guard, and recovery - never a re-anchor target"
assert_file_contains "schema field present" 'muse_session:' "$MOCKUP"
assert_file_contains "never-a-re-anchor-target semantics stated" 'NEVER a re-anchor target' "$MOCKUP"
assert_file_contains "recovery reads it as a no-op" 'recovery reads it as a no-op' "$MOCKUP"

begin_test "the old marker logic and silent enrichment stay dead"
assert_file_not_contains "no (Recommended) muse marker returns" 'Include the muse (Recommended)' "$MOCKUP"
assert_file_not_contains "no marker-position logic returns" 'Position follows the marker' "$MOCKUP"
assert_file_not_contains "Muse's take lives in the reference, not the funnel" "Muse's take:" "$MOCKUP"
assert_file_contains "at-most-three budget prose intact" 'At most three taste AskUserQuestion calls exist' "$MOCKUP"

INIT="$PLUGIN_ROOT/commands/craft-init.md"
WORKSHOP="$PLUGIN_ROOT/docs/creative-workshop.md"
README="$PLUGIN_ROOT/README.md"

# The Phase 0.5 intent AUQ block, extracted for scoped assertions (the Emotional Core
# and muse legitimately appear elsewhere in craft-init.md - Phase 5b).
INTENT_AUQ="$(sed -n '/Want to capture your project intent now?/,/^```$/p' "$INIT")"
YES_OPTION="$(echo "$INTENT_AUQ" | sed -n '/Yes, capture intent/,/label:/p')"

# --- Chunk 4: Phase 0.5 sells the Emotional Core; docs reconciled ---
begin_test "Phase 0.5 Yes option names the Emotional Core"
assert_contains "yes label keeps its marker" 'Yes, capture intent (Recommended)' "$INTENT_AUQ"
assert_contains "yes description names the Emotional Core" 'Emotional Core' "$YES_OPTION"
assert_contains "yes description names what it feeds" 'every cycle you plan later reads it' "$YES_OPTION"

begin_test "muse no longer only in Skip"
assert_contains "yes description names the muse" 'muse' "$YES_OPTION"
assert_contains "skip option survives" 'Skip - just scaffold' "$INTENT_AUQ"

begin_test "creative-workshop.md drops the silent-folding description"
assert_file_contains "step-2 line quotes the muse first" "you see 2-3 verbatim lines of it first" "$WORKSHOP"
assert_file_contains "interrogators section surfaces both briefings" "Muse's take:" "$WORKSHOP"
assert_file_contains "alchemist surfacing named in docs" "Alchemist's take:" "$WORKSHOP"

begin_test "README intent line stays Emotional-Core consistent"
assert_file_contains "README distill line intact" "muse distills them into the project's Emotional Core" "$README"
assert_file_contains "README cycle-reads line intact" 'Every cycle you plan later reads it' "$README"

finish_tests
