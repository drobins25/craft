#!/bin/bash
# test-mockup-hunch-settling.sh - Guard Story 8's locked strings across the spec files.
# Doc-level assertions that the hunch-settling design is specced as locked: the
# executable threshold, the five below-threshold signals, the throw-don't-interrogate
# move, the riff.md canonical pointer, the mockup funnel's silent settle gate, the
# Settled: recording rule, and the guard survivals (DO-NOT-SIMPLIFY + three-AUQ).
# Adjacent stories edit these same shared files; a paraphrased rule or a resurrected
# escalation path should fail the suite, not slip through review.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

REF="$PLUGIN_ROOT/reference/hunch-settling.md"

# --- Chunk 1: the shared technique reference ---
begin_test "hunch-settling reference exists and states the executable threshold"
assert_file_exists "hunch-settling.md exists" "$REF"
assert_file_contains "threshold question stated" 'can I write the one-line alchemist brief using only the user'"'"'s words' "$REF"
assert_file_contains "two-builders test is the concrete check" 'two different builders would' "$REF"
assert_file_contains "target framing present" 'a target (which element or quality)' "$REF"
assert_file_contains "direction framing present" 'a direction (what it changes toward)' "$REF"
assert_file_contains "contrast example in the above-threshold set" 'Contrast "option C but bigger"' "$REF"
assert_file_contains "verdict-vs-attribution psychology present" 'taste fires faster than articulation' "$REF"

begin_test "reference enumerates all six below-threshold signals"
assert_file_contains "signal 1: verdict without target" 'Verdict without target' "$REF"
assert_file_contains "signal 2: attribution hedges" 'Attribution hedges' "$REF"
assert_file_contains "signal 3: conflicting pulls" 'Conflicting pulls' "$REF"
assert_file_contains "signal 4: comparative without dimension" 'Comparative without dimension' "$REF"
assert_file_contains "signal 5: energy drop" 'Energy drop' "$REF"
assert_file_contains "signal 6: unqualified magnitude" 'Unqualified magnitude or addition word' "$REF"

begin_test "reference names the throw move and rejects the two wrong moves"
assert_file_contains "throw move named" 'Throw a concrete interpretation and let them correct it' "$REF"
assert_file_contains "correction beats generation rationale" 'People correct far better than they generate' "$REF"
assert_file_contains "building on a guess rejected" 'Build on a guess' "$REF"
assert_file_contains "interrogation rejected" 'what exactly feels off?' "$REF"

begin_test "throws are grounded in on-screen referents"
assert_file_contains "throw-at-the-screen rule present" 'Throw at the screen, not at concepts' "$REF"
assert_file_contains "one-glance verifiability required" 'verify your interpretation in one glance' "$REF"
assert_file_contains "abstract axis named as the anti-pattern" 'interrogation wearing a throw' "$REF"

begin_test "reference licenses above-threshold reactions to proceed untouched"
assert_file_contains "explicit delegation licensed" 'licensed full blast' "$REF"
assert_file_contains "just-try-something named" 'just try something' "$REF"
assert_file_contains "over-trigger named as the failure mode" 'Over-triggering on clear reactions is the failure mode' "$REF"

begin_test "reference points to agents/riff.md as canonical (GUARD respect)"
assert_file_contains "canonical home pointer" 'agents/riff.md' "$REF"
assert_file_contains "canonical wording present" 'canonical home' "$REF"
assert_file_contains "read-once-per-session guidance present" 'once per session' "$REF"

MOCKUP="$PLUGIN_ROOT/commands/references/mockup-inline.md"

# The settle gate block, extracted for scoped assertions ("full-blast", "silent",
# and "verbatim" legitimately appear elsewhere in mockup-inline.md).
GATE_BLOCK="$(sed -n '/### The settle gate/,/^## Step 3: Diverge/p' "$MOCKUP")"

# --- Chunk 2: the funnel's silent settle gate ---
begin_test "mockup funnel carries the settle gate and reads the reference by env-var path"
assert_file_exists "mockup-inline.md exists" "$MOCKUP"
assert_file_contains "settle gate block heading present" '### The settle gate' "$MOCKUP"
assert_contains "reference read via CLAUDE_PLUGIN_ROOT form" 'CLAUDE_PLUGIN_ROOT}/reference/hunch-settling.md' "$GATE_BLOCK"
assert_contains "read once per session, held" 'ONCE per mockup session' "$GATE_BLOCK"

begin_test "settle gate is invisible, non-escalating, and records a labeled sub-line"
assert_contains "gate is never announced" 'never announce, name, or explain' "$GATE_BLOCK"
assert_contains "riff agent never spawned in-funnel" 'never spawn the riff agent' "$GATE_BLOCK"
assert_contains "Skill-tool invocation banned in-funnel" 'never invoke a skill via the Skill tool' "$GATE_BLOCK"
assert_contains "unsettleable fallback is park or /craft:riff" 'parking the mockup or riffing separately via /craft:riff' "$GATE_BLOCK"
assert_contains "Settled sub-line recording named" 'Settled: ' "$GATE_BLOCK"
assert_contains "append-never-replace stated" 'append, never replace' "$GATE_BLOCK"

begin_test "executable reactions and Polish micro-injections stay full-blast"
assert_contains "clear reactions proceed full-blast" 'proceed full-blast exactly as today' "$GATE_BLOCK"
assert_contains "clear reactions never second-guessed" 'never settled, slowed, or second-guessed' "$GATE_BLOCK"
assert_contains "micro-injections excluded from the gate" 'Polish micro-injections never classify' "$GATE_BLOCK"

begin_test "all three reaction points route through the gate"
assert_file_contains "Diverge points at the gate" 'passes the settle gate above' "$MOCKUP"
assert_file_contains "Refine points at the gate" 'the settle gate applies here exactly as in Diverge' "$MOCKUP"
assert_file_contains "Polish structural rebrief records verbatim then classifies" 'A structural rebrief starts from a reaction too' "$MOCKUP"

begin_test "mockup-inline load-bearing guards survive"
assert_file_contains "DO-NOT-SIMPLIFY core sentence intact" 'paraphrasing destroys them' "$MOCKUP"
assert_file_contains "sanctioned-exception note on the guard" 'sanctioned exception' "$MOCKUP"
assert_file_contains "taste-protection sentence intact" 'a widget between the user and their taste kills the funnel' "$MOCKUP"
assert_file_contains "amended taste-AUQ budget intact" 'Exactly three taste AskUserQuestion calls exist' "$MOCKUP"
assert_file_contains "refine-never-silently-converges rule intact" 'converging to one is never inferred' "$MOCKUP"
assert_file_contains "refine convergence confirm is conversational" 'One converged take this round, or options again?' "$MOCKUP"
assert_file_contains "recommended muse option leads the list" 'Position follows the marker' "$MOCKUP"

RIFF_SKILL="$PLUGIN_ROOT/commands/craft-riff.md"

begin_test "craft-riff names the second shared reference and keeps its GUARD"
assert_file_contains "hunch-settling named in the skill-vs-agent map" 'reference/hunch-settling.md' "$RIFF_SKILL"
assert_file_contains "distill-not-canonical contract stated" 'agents/riff.md` stays canonical' "$RIFF_SKILL"
assert_file_contains "GUARD block survives" 'must NEVER re-document' "$RIFF_SKILL"

DESIGN="$PLUGIN_ROOT/DESIGN.md"

begin_test "DESIGN reference tree and riff section list both shared technique files"
assert_file_contains "tree lists calibration-loop.md" 'calibration-loop.md' "$DESIGN"
assert_file_contains "tree lists hunch-settling.md" 'hunch-settling.md' "$DESIGN"
assert_file_contains "riff section names the mockup consumer" 'first consumer is the mockup funnel' "$DESIGN"

STORY_FROM_MOCKUP="$PLUGIN_ROOT/commands/references/story-from-mockup.md"

begin_test "story-from-mockup pulls voice from verbatim lines only"
assert_file_contains "verbatim-only voice rule present" 'verbatim reaction lines only' "$STORY_FROM_MOCKUP"
assert_file_contains "Settled lines are context, not voice" 'never quoted as the user'"'"'s words' "$STORY_FROM_MOCKUP"

README_FILE="$PLUGIN_ROOT/README.md"

begin_test "README funnel section carries the settle line"
assert_file_contains "user-facing settle line present" 'riffs the fuzzy reaction into a sharp direction' "$README_FILE"

finish_tests
