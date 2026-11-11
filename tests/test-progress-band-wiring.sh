#!/bin/bash
# test-progress-band-wiring.sh - wiring coverage for the progress band's hooks module
#
# Freezes the seams CI can check without network or the claude CLI:
#   1. hooks.json names the module beside its seven classic events
#   2. plugin.json names the types contract and the file exists
#   3. the module registers /craft-progress, and only that command
#   4. the engine-written types folder is never tracked
#   5. the module's three files carry no planning citation and no absolute home path
#   6. the module draws the band above the prompt, with props every build from 2.1.287 draws,
#      and reads the project-root setting by a literal name
#   7. the README names the 2.1.287 requirement once and keeps its 2.1+ badge

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/.."
HOOKS_JSON="$REPO/hooks/hooks.json"
PLUGIN_JSON="$REPO/.claude-plugin/plugin.json"
MODULE="$REPO/hooks/register.tsx"
TAKE="$REPO/hooks/take.ts"
DRAW="$REPO/hooks/draw.tsx"
BAND_FILES="$MODULE $TAKE $DRAW"
TYPES="$REPO/types/index.d.ts"
GATE="$REPO/hooks/scripts/check-craft-vocab.py"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Expected: $2"; [ -n "${3:-}" ] && echo "    Got:      $3"; return 0; }

# Prints the 1-based numbers of lines the vocabulary gate's own comment rule flags.
# The rule is loaded from the gate script itself so it can never drift from a copy.
gate_hits() {
  python3 - "$GATE" "$1" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("vocab_gate", sys.argv[1])
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
with open(sys.argv[2], encoding="utf-8") as f:
    for i, line in enumerate(f.read().splitlines(), 1):
        if gate.match_line(line):
            print(i)
PY
}

echo "=== hooks.json keeps seven events and names the module ==="
if jq -e . "$HOOKS_JSON" >/dev/null 2>&1; then pass "hooks.json parses"; else fail "hooks.json parses"; fi
MODULES=$(jq -c '.modules' "$HOOKS_JSON" 2>/dev/null || echo "invalid")
if [ "$MODULES" = '["./register.tsx"]' ]; then pass "modules names ./register.tsx"; else fail "modules names ./register.tsx" '["./register.tsx"]' "$MODULES"; fi
EVENTS=$(jq '.hooks | length' "$HOOKS_JSON" 2>/dev/null || echo "invalid")
if [ "$EVENTS" = "7" ]; then pass "hooks still holds seven events"; else fail "hooks still holds seven events" "7" "$EVENTS"; fi
if [ -f "$MODULE" ]; then pass "hooks/register.tsx exists"; else fail "hooks/register.tsx exists"; fi

echo "=== plugin.json names the types contract and the file exists ==="
TYPES_REF=$(jq -r '.types // empty' "$PLUGIN_JSON" 2>/dev/null || true)
if [ "$TYPES_REF" = "./types/index.d.ts" ]; then pass "plugin.json types points at ./types/index.d.ts"; else fail "plugin.json types points at ./types/index.d.ts" "./types/index.d.ts" "$TYPES_REF"; fi
if [ -f "$TYPES" ] && grep -q 'PluginState' "$TYPES"; then pass "types/index.d.ts exists and declares PluginState"; else fail "types/index.d.ts exists and declares PluginState"; fi
TSCONFIG=$(jq -r '.extends // empty' "$REPO/tsconfig.json" 2>/dev/null || true)
if [ "$TSCONFIG" = "./.claude-plugin/types/tsconfig.json" ]; then pass "tsconfig.json extends the engine-written base"; else fail "tsconfig.json extends the engine-written base" "./.claude-plugin/types/tsconfig.json" "$TSCONFIG"; fi

echo "=== the module registers craft-progress ==="
if [ -f "$MODULE" ] && grep -q "name: 'craft-progress'" "$MODULE" && grep -q "command: 'craft-progress'" "$MODULE"; then
  pass "module registers and handles craft-progress"
else
  fail "module registers and handles craft-progress"
fi
REGISTRATIONS=$(cat $BAND_FILES 2>/dev/null | grep -c "name: '" || true)
if [ "$REGISTRATIONS" -eq 1 ]; then pass "exactly one command is registered"; else fail "exactly one command is registered" "1" "$REGISTRATIONS"; fi
if grep -q "description: \"Show or hide craft's progress band above the prompt\"" "$MODULE"; then pass "craft-progress describes the whole band"; else fail "craft-progress describes the whole band"; fi

echo "=== the engine-written types folder is not tracked ==="
TRACKED=$(git -C "$REPO" ls-files .claude-plugin/types 2>/dev/null || true)
if [ -z "$TRACKED" ]; then pass ".claude-plugin/types is not tracked"; else fail ".claude-plugin/types is not tracked" "no tracked files" "$TRACKED"; fi

echo "=== no planning citation or home path in the module's files ==="
SEED_DIR=$(mktemp -d)
trap 'rm -rf "$SEED_DIR"' EXIT
for f in $BAND_FILES; do
  name=$(basename "$f")
  if [ ! -f "$f" ]; then fail "$name exists"; continue; fi
  HITS=$(gate_hits "$f")
  if [ -z "$HITS" ]; then pass "no comment line in $name trips the vocabulary gate"; else fail "no comment line in $name trips the vocabulary gate" "no flagged lines" "lines: $HITS"; fi
  if grep -nE '/Users/|/home/' "$f" >/dev/null; then fail "no absolute home path in $name" "none" "$(grep -nE '/Users/|/home/' "$f" | head -3)"; else pass "no absolute home path in $name"; fi
done

# Prove the check can fail: a seeded copy with a planning citation must be flagged.
if [ -f "$MODULE" ]; then
  { cat "$MODULE"; echo "// chunk 3 reads the state"; } > "$SEED_DIR/seeded.tsx"
  SEED_HITS=$(gate_hits "$SEED_DIR/seeded.tsx")
  if [ -n "$SEED_HITS" ]; then pass "seeded planning citation is flagged"; else fail "seeded planning citation is flagged" "a flagged line" "none"; fi
fi

echo "=== the module draws the band above the prompt ==="
if [ -f "$MODULE" ] && grep -q "component: 'AbovePrompt'" "$MODULE" && grep -q "on('ui.render'" "$MODULE"; then
  pass "module hooks ui.render for AbovePrompt"
else
  fail "module hooks ui.render for AbovePrompt"
fi
# weight, size, mono and tabular make the whole tree undrawn before Claude Code 2.1.299
if ! grep -nE '\b(weight|size|mono|tabular)=' $BAND_FILES >/dev/null; then
  pass "no weight/size/mono/tabular prop in the module's files"
else
  fail "no weight/size/mono/tabular prop in the module's files" "none" "$(grep -nE '\b(weight|size|mono|tabular)=' $BAND_FILES | head -3)"
fi
if [ -f "$TAKE" ] && grep -q "\$.env.get('CRAFT_PROJECT_ROOT')" "$TAKE"; then
  pass "module reads CRAFT_PROJECT_ROOT as a literal"
else
  fail "module reads CRAFT_PROJECT_ROOT as a literal"
fi
if ! grep -nE '\$\.(fs\.write|store|env\.set)' $BAND_FILES >/dev/null; then
  pass "module writes no file, store key or environment variable"
else
  fail "module writes no file, store key or environment variable"
fi

echo "=== the module splits along the I/O line and loads under the engine ==="
if grep -q "from './take'" "$MODULE" && grep -q "from './draw'" "$MODULE"; then pass "register.tsx imports ./take and ./draw with import declarations"; else fail "register.tsx imports ./take and ./draw with import declarations"; fi
if grep -nE '\bimport\(' $BAND_FILES >/dev/null; then fail "no dynamic import() in the module's files" "none" "$(grep -nE '\bimport\(' $BAND_FILES | head -3)"; else pass "no dynamic import() in the module's files"; fi
if ! grep -nE 'EngineInterface|\$\.' "$REPO/hooks/draw.tsx" >/dev/null; then pass "draw.tsx touches no engine call"; else fail "draw.tsx touches no engine call" "none" "$(grep -nE 'EngineInterface|\$\.' "$REPO/hooks/draw.tsx" | head -3)"; fi
if ! grep -nE '^(let|var) ' "$TAKE" "$DRAW" >/dev/null; then pass "take.ts and draw.tsx hold no module memory"; else fail "take.ts and draw.tsx hold no module memory" "no top-level let or var" "$(grep -nE '^(let|var) ' "$TAKE" "$DRAW" | head -3)"; fi
SHAPES=$(grep -c "shape: 'progress-2'" "$MODULE" || true)
if [ "$SHAPES" -eq 2 ]; then pass "progress and ownPlanning both carry shape 'progress-2'"; else fail "progress and ownPlanning both carry shape 'progress-2'" "2" "$SHAPES"; fi
if ! grep -q "progress-1" $BAND_FILES; then pass "the old shape tag is gone from the module's files"; else fail "the old shape tag is gone from the module's files"; fi
CATCHES=$(grep -c '\.catch((\$, e, next) => next(e))' "$MODULE" || true)
if [ "$CATCHES" -eq 3 ]; then pass "both tool.call hooks and the agent.spawn hook carry the catch guard"; else fail "both tool.call hooks and the agent.spawn hook carry the catch guard" "3" "$CATCHES"; fi
if grep -q "on('tool.call'" "$MODULE" && grep -q "on('agent.spawn'" "$MODULE"; then pass "the module hooks tool.call and agent.spawn"; else fail "the module hooks tool.call and agent.spawn"; fi

echo "=== the look: theme keys, one grammar, no yellow, no hex ==="
for key in "BUILD_BASE = 'green_FOR_SUBAGENTS_ONLY'" "BUILD_SWEEP = 'success'" "PLAN_BASE = 'claudeBlue_FOR_SYSTEM_SPINNER'" "PLAN_SWEEP = 'claudeBlueShimmer_FOR_SYSTEM_SPINNER'"; do
  if grep -qF "$key" "$DRAW"; then pass "draw.tsx holds $key"; else fail "draw.tsx holds $key"; fi
done
if ! grep -nE "'warning'|\"warning\"|'suggestion'|\"suggestion\"" $BAND_FILES >/dev/null; then pass "no warning or suggestion color in the module's files"; else fail "no warning or suggestion color in the module's files" "none" "$(grep -nE "'warning'|\"warning\"|'suggestion'" $BAND_FILES | head -3)"; fi
if ! grep -nE '#[0-9a-fA-F]{3,8}\b' $BAND_FILES >/dev/null; then pass "no hex color in the module's files"; else fail "no hex color in the module's files" "none" "$(grep -nE '#[0-9a-fA-F]{3,8}\b' $BAND_FILES | head -3)"; fi
if ! grep -nE "'active'|\"active\"" "$DRAW" >/dev/null; then pass "draw.tsx never draws the word active"; else fail "draw.tsx never draws the word active"; fi
if grep -q 'paddingLeft={2}' "$DRAW" && grep -q "'✶ '" "$DRAW"; then pass "draw.tsx indents line two and draws the star"; else fail "draw.tsx indents line two and draws the star"; fi
if grep -q 'progress_band_motion' "$TAKE"; then pass "take.ts reads the progress_band_motion setting by its literal name"; else fail "take.ts reads the progress_band_motion setting by its literal name"; fi

echo "=== the planning view's seams ==="
if grep -q "on('tool.call', { tool: 'Bash' }" "$MODULE" && grep -q "includes('planning-stage.sh')" "$MODULE"; then pass "register.tsx wraps Bash calls that name planning-stage.sh"; else fail "register.tsx wraps Bash calls that name planning-stage.sh"; fi
if grep -qF 'Planning stage (set to [a-z-]+|cleared): (' "$TAKE"; then pass "take.ts parses the script's two output lines"; else fail "take.ts parses the script's two output lines"; fi
if grep -q "planning_stage" "$TAKE"; then pass "take.ts reads the planning_stage field"; else fail "take.ts reads the planning_stage field"; fi
# A step is never chosen from the chunk count, the progress counter or the story's status.
STAGE_FN=$(sed -n '/^export function stageOf/,/^}/p' "$TAKE")
if [ -n "$STAGE_FN" ] && ! echo "$STAGE_FN" | grep -qE "chunks_total|chunks_complete|'status'"; then pass "stageOf reads no chunk count and no status"; else fail "stageOf reads no chunk count and no status"; fi
if grep -qF "\$.command.run({ command: 'craft:story-implement' })" "$MODULE"; then pass "the ready row's press runs /craft:story-implement with no story named"; else fail "the ready row's press runs /craft:story-implement with no story named"; fi
if ! grep -nE "story-implement.*args|args:.*story-implement" $BAND_FILES >/dev/null; then pass "no press names a story"; else fail "no press names a story"; fi
if ! grep -nE "plan-band|'◐'|◐" $BAND_FILES >/dev/null; then pass "no plan-band text and no half circle in the module's files"; else fail "no plan-band text and no half circle in the module's files" "none" "$(grep -nE "plan-band|◐" $BAND_FILES | head -3)"; fi
if ! grep -nE '\b(autoFocus|hotkey|action|dimColor|hover|variant)=|<(Input|Select)\b|ui\.focus' $BAND_FILES >/dev/null; then pass "the band draws nothing that keeps focus and the ready control carries no style prop"; else fail "the band draws nothing that keeps focus and the ready control carries no style prop" "none" "$(grep -nE '\b(autoFocus|hotkey|action|dimColor|hover|variant)=|<(Input|Select)\b|ui\.focus' $BAND_FILES | head -3)"; fi
if grep -q "<Button label={READY} plain onPress={onPress}>" "$DRAW"; then pass "the ready control is a plain Button with its label"; else fail "the ready control is a plain Button with its label"; fi
if grep -q "pressLocked" "$MODULE" && grep -q "readSlot" "$MODULE"; then pass "a press is locked and re-reads the story slot"; else fail "a press is locked and re-reads the story slot"; fi

echo "=== the validator agents the band watches exist ==="
if grep -q 'chunk-validator|claims-auditor' "$MODULE"; then pass "register.tsx names both validator agent types"; else fail "register.tsx names both validator agent types"; fi
for agent in chunk-validator claims-auditor; do
  if [ -f "$REPO/agents/$agent.md" ]; then pass "agents/$agent.md exists"; else fail "agents/$agent.md exists"; fi
done

echo "=== the README names the version the band needs ==="
README="$REPO/README.md"
NOTE="> The progress band above the prompt and its \`/craft-progress\` toggle need Claude Code 2.1.287 or later (the ready row's button needs 2.1.295); everything else in craft works on 2.1."
NOTE_COUNT=$(grep -cF -- "$NOTE" "$README" || true)
if [ "$NOTE_COUNT" -eq 1 ]; then pass "README carries the 2.1.287 sentence once"; else fail "README carries the 2.1.287 sentence once" "1 occurrence" "$NOTE_COUNT"; fi
if grep -qF 'requires-Claude%20Code%202.1%2B' "$README"; then pass "README badge still says 2.1+"; else fail "README badge still says 2.1+"; fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $TOTAL total"
[ "$FAIL_COUNT" -eq 0 ]
