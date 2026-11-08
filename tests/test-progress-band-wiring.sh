#!/bin/bash
# test-progress-band-wiring.sh - wiring coverage for the progress band's hooks module
#
# Freezes the seams CI can check without network or the claude CLI:
#   1. hooks.json names the module beside its seven classic events
#   2. plugin.json names the types contract and the file exists
#   3. the module registers /craft-progress
#   4. the engine-written types folder is never tracked
#   5. the module carries no planning citation and no absolute home path
#   6. the module draws the band above the prompt, with props every build from 2.1.287 draws,
#      and reads the project-root setting by a literal name
#   7. the README names the 2.1.287 requirement once and keeps its 2.1+ badge

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/.."
HOOKS_JSON="$REPO/hooks/hooks.json"
PLUGIN_JSON="$REPO/.claude-plugin/plugin.json"
MODULE="$REPO/hooks/register.tsx"
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

echo "=== the engine-written types folder is not tracked ==="
TRACKED=$(git -C "$REPO" ls-files .claude-plugin/types 2>/dev/null || true)
if [ -z "$TRACKED" ]; then pass ".claude-plugin/types is not tracked"; else fail ".claude-plugin/types is not tracked" "no tracked files" "$TRACKED"; fi

echo "=== no planning citation or home path in the module ==="
if [ -f "$MODULE" ]; then
  HITS=$(gate_hits "$MODULE")
  if [ -z "$HITS" ]; then pass "no comment line trips the vocabulary gate"; else fail "no comment line trips the vocabulary gate" "no flagged lines" "lines: $HITS"; fi
  if grep -nE '/Users/|/home/' "$MODULE" >/dev/null; then fail "no absolute home path in the module" "none" "$(grep -nE '/Users/|/home/' "$MODULE" | head -3)"; else pass "no absolute home path in the module"; fi

  # Prove the check can fail: a seeded copy with a planning citation must be flagged.
  SEED_DIR=$(mktemp -d)
  trap 'rm -rf "$SEED_DIR"' EXIT
  { cat "$MODULE"; echo "// chunk 3 reads the state"; } > "$SEED_DIR/seeded.tsx"
  SEED_HITS=$(gate_hits "$SEED_DIR/seeded.tsx")
  if [ -n "$SEED_HITS" ]; then pass "seeded planning citation is flagged"; else fail "seeded planning citation is flagged" "a flagged line" "none"; fi
else
  fail "no comment line trips the vocabulary gate" "module present" "missing"
fi

echo "=== the module draws the band above the prompt ==="
if [ -f "$MODULE" ] && grep -q "component: 'AbovePrompt'" "$MODULE" && grep -q "on('ui.render'" "$MODULE"; then
  pass "module hooks ui.render for AbovePrompt"
else
  fail "module hooks ui.render for AbovePrompt"
fi
# weight, size, mono and tabular make the whole tree undrawn before Claude Code 2.1.299
if [ -f "$MODULE" ] && ! grep -nE '\b(weight|size|mono|tabular)=' "$MODULE" >/dev/null; then
  pass "no weight/size/mono/tabular prop in the module"
else
  fail "no weight/size/mono/tabular prop in the module" "none" "$(grep -nE '\b(weight|size|mono|tabular)=' "$MODULE" | head -3)"
fi
if [ -f "$MODULE" ] && grep -q "\$.env.get('CRAFT_PROJECT_ROOT')" "$MODULE"; then
  pass "module reads CRAFT_PROJECT_ROOT as a literal"
else
  fail "module reads CRAFT_PROJECT_ROOT as a literal"
fi
if [ -f "$MODULE" ] && ! grep -nE '\$\.(fs\.write|store|env\.set)' "$MODULE" >/dev/null; then
  pass "module writes no file, store key or environment variable"
else
  fail "module writes no file, store key or environment variable"
fi

echo "=== the README names the version the band needs ==="
README="$REPO/README.md"
NOTE='> The progress band above the prompt and its `/craft-progress` toggle need Claude Code 2.1.287 or later; everything else in craft works on 2.1.'
NOTE_COUNT=$(grep -cF -- "$NOTE" "$README" || true)
if [ "$NOTE_COUNT" -eq 1 ]; then pass "README carries the 2.1.287 sentence once"; else fail "README carries the 2.1.287 sentence once" "1 occurrence" "$NOTE_COUNT"; fi
if grep -qF 'requires-Claude%20Code%202.1%2B' "$README"; then pass "README badge still says 2.1+"; else fail "README badge still says 2.1+"; fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $TOTAL total"
[ "$FAIL_COUNT" -eq 0 ]
