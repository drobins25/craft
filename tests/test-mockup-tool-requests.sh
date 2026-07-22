#!/bin/bash
# test-mockup-tool-requests.sh - Guard Story 16's locked strings across the spec files.
# Doc-level assertions that the mockup material feature is specced as locked: the
# pinned `Tool request:` marker in BOTH producer (alchemist.md) and consumer
# (mockup-inline.md) - two different authors write the two halves, and a marker
# mismatch would silently no-op the whole feature - plus the distortion principle
# (no allowlist), the pinned fetch sources, orchestrator-owned fetching into the
# mockup's assets/ folder, silent-fetch disclosure, the degrade path, the record's
# `## Materials` schema, and both graduation ramps forwarding the material spec
# (identity, never the inlined bytes). Adjacent stories edit these same shared
# files; a paraphrased rule or a dropped marker should fail the suite, not slip
# through review.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

ALCHEMIST="$PLUGIN_ROOT/agents/alchemist.md"
MOCKUP="$PLUGIN_ROOT/commands/references/mockup-inline.md"
STORY_RAMP="$PLUGIN_ROOT/commands/references/story-from-mockup.md"
TWEAK="$PLUGIN_ROOT/skills/adhoc/references/tweak.md"

# --- Producer: the alchemist's tool-need beliefs ---
begin_test "alchemist reports tool need on the distortion principle"
assert_file_exists "alchemist.md exists" "$ALCHEMIST"
assert_file_contains "distortion-principle clause present" 'I ask for real material when the faked asset would distort the reaction the round exists to collect, and I keep improvising wherever the constraint is doing real work' "$ALCHEMIST"
assert_file_contains "self-containment clarified as page-load" 'Self-contained means zero external requests AT PAGE LOAD' "$ALCHEMIST"
assert_file_contains "alchemist never fetches" 'I never fetch anything myself' "$ALCHEMIST"

begin_test "tool-request marker is pinned in both producer and consumer"
assert_file_contains "marker in alchemist.md (producer)" 'Tool request:' "$ALCHEMIST"
assert_file_exists "mockup-inline.md exists" "$MOCKUP"
assert_file_contains "marker in mockup-inline.md (consumer)" 'Tool request:' "$MOCKUP"

# The tool-need block, extracted for scoped assertions (source names like Lucide
# legitimately appear elsewhere - the orchestrator's pinned-source list - so the
# no-allowlist negative must be scoped to the agent's principle block only).
TOOL_NEED="$(sed -n '/I ask for real material only when faking it/,/Real content, never lorem ipsum/p' "$ALCHEMIST")"

begin_test "ask threshold is a principle, not a list"
assert_contains "per-round judgment stated" 'no list and no standing allowlist' "$TOOL_NEED"
assert_not_contains "no icon-library enumeration in the block" 'Lucide' "$TOOL_NEED"
assert_not_contains "no source enumeration in the block" 'Google Fonts' "$TOOL_NEED"

# --- Consumer: the orchestrator's fetch flow ---
begin_test "sources are pinned - Google Fonts and official icon repos"
assert_file_contains "typeface source pinned" 'Google Fonts for typefaces' "$MOCKUP"
assert_file_contains "icon sources pinned" 'the official Lucide, Phosphor, or Heroicons repositories' "$MOCKUP"
assert_file_contains "no other origin ever" 'No other origin is ever fetched from' "$MOCKUP"

begin_test "the orchestrator fetches into the mockup's assets folder"
assert_file_contains "orchestrator owns the fetch" 'the orchestrator fetches the asset files itself - the alchemist never touches the network' "$MOCKUP"
assert_file_contains "destination is the mockup's assets subdirectory" "mockup folder's \`assets/\` subdirectory" "$MOCKUP"

begin_test "fetch is silent with one-line disclosure, never a widget"
assert_file_contains "no ask of any kind" 'No AskUserQuestion and no conversational ask' "$MOCKUP"
assert_file_contains "disclosure at round presentation" 'Disclose it in one line when the round is presented' "$MOCKUP"
assert_file_contains "logged in the record" 'log one line per fetch in record.md' "$MOCKUP"
assert_file_not_contains "neutralized literal: exactly-three" 'Exactly three AskUserQuestion calls exist' "$MOCKUP"
assert_file_not_contains "neutralized literal: never-add-a-fourth" 'Never add a fourth' "$MOCKUP"
assert_file_not_contains "neutralized literal: never-a-fourth" 'never a fourth AskUserQuestion' "$MOCKUP"

begin_test "degrades to the substitute, never errors"
assert_file_contains "silent degrade stated" 'degrades silently' "$MOCKUP"
assert_file_contains "never an error state" 'never an error state, never a dead round' "$MOCKUP"

begin_test "out-of-scope requests are declined, alchemist improvises"
assert_file_contains "decline line present" 'declined in one plain line and the alchemist improvises' "$MOCKUP"

# --- The record schema ---
begin_test "Materials schema present in record template"
assert_file_contains "Materials section in template" '## Materials' "$MOCKUP"
assert_file_contains "normally empty, one line per fetch" 'orchestrator-fetched material ONLY - normally empty' "$MOCKUP"
assert_file_contains "guard comment names the readers" 'read by the graduation ramps' "$MOCKUP"

# --- Graduation ramps forward the spec, never the bytes ---
begin_test "story ramp forwards the material spec"
assert_file_exists "story-from-mockup.md exists" "$STORY_RAMP"
assert_file_contains "spec-not-bytes rule present" 'Materials port as a spec, never as bytes' "$STORY_RAMP"
assert_file_contains "acquisition resolved at plan-chunks" "acquisition is resolved at the story's own plan-chunks per the project's idiom" "$STORY_RAMP"
assert_file_contains "base64 never ported" 'The mockup'"'"'s inlined base64 is never ported' "$STORY_RAMP"

begin_test "tweak port acquires the material, never the blob"
assert_file_exists "tweak.md exists" "$TWEAK"
assert_file_contains "acquisition is part of the port" 'acquiring that material through the project'"'"'s idiom is part of the port' "$TWEAK"
assert_file_contains "blob never ported as the acquisition" 'never ported as the acquisition' "$TWEAK"

begin_test "tweak handoff forwards the materials spec"
assert_file_contains "Step 6 tweak brief forwards materials" 'the brief forwards the materials spec too' "$MOCKUP"

finish_tests
