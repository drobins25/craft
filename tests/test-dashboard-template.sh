#!/bin/bash
# test-dashboard-template.sh — Structural gate for scripts/dashboard/template/index.html:
# stripped dev chrome, file:// load path only, nine type hues, ported physics
# constants, and comment hygiene. Pure text properties of a file this repo ships.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

TEMPLATE="$PLUGIN_ROOT/scripts/dashboard/template/index.html"
MOCKUP="$PLUGIN_ROOT/.craft/mockups/2026-08-15-craft-browser-graph/mockup.html"

echo "=== test-dashboard-template.sh ==="
echo ""

# --- Test 1: template file exists at the locked path ---
begin_test "template file exists at the locked path"
assert_file_exists "scripts/dashboard/template/index.html exists" "$TEMPLATE"

if [ ! -f "$TEMPLATE" ]; then
  echo ""
  echo "Template not found - remaining checks cannot run."
  finish_tests "test-dashboard-template.sh"
fi

# --- Test 2: version stamp appears exactly once, within the first 10 lines ---
begin_test "version stamp appears exactly once, within the first 10 lines"
STAMP_COUNT=$(grep -c '<meta name="craft-template-version" content="' "$TEMPLATE" || true)
assert_eq "exactly one version stamp in the whole file" "1" "$STAMP_COUNT"
STAMP_IN_HEAD=$(head -10 "$TEMPLATE" | grep -c '<meta name="craft-template-version" content="' || true)
assert_eq "the version stamp is within the first 10 lines" "1" "$STAMP_IN_HEAD"

# --- Test 3: no dev chrome survives ---
begin_test "no dev chrome survives"
assert_file_not_contains "no #dev-chrome" "dev-chrome" "$TEMPLATE"
assert_file_not_contains "no .round-label" "round-label" "$TEMPLATE"
assert_file_not_contains "no #stance-note" "stance-note" "$TEMPLATE"

# --- Test 4: no network or module loading ---
begin_test "no network or module loading"
assert_file_not_contains "no fetch(" "fetch(" "$TEMPLATE"
assert_file_not_contains "no import statements" "import " "$TEMPLATE"
assert_file_not_contains "no ES module script tags" 'type="module"' "$TEMPLATE"
assert_file_not_contains "no http:// reference" "http://" "$TEMPLATE"
assert_file_not_contains "no https:// reference" "https://" "$TEMPLATE"

# --- Test 5: no parent-relative paths ---
begin_test "no parent-relative paths"
assert_file_not_contains "no ../ anywhere in the file" '\.\./' "$TEMPLATE"

# --- Test 6: data loads from the graph subdirectory ---
begin_test "data loads from the graph subdirectory"
assert_file_contains "build-status.js sibling script tag present" 'src="graph/build-status.js"' "$TEMPLATE"
assert_file_contains "graph.js sibling script tag present" 'src="graph/graph.js"' "$TEMPLATE"
BUILD_LINE=$(grep -n 'src="graph/build-status.js"' "$TEMPLATE" | head -1 | cut -d: -f1)
GRAPH_LINE=$(grep -n 'src="graph/graph.js"' "$TEMPLATE" | head -1 | cut -d: -f1)
if [ -n "$BUILD_LINE" ] && [ -n "$GRAPH_LINE" ] && [ "$BUILD_LINE" -lt "$GRAPH_LINE" ]; then
  echo "  PASS: build-status.js loads before graph.js"
  PASS=$((PASS + 1))
else
  echo "  FAIL: build-status.js loads before graph.js"
  FAIL=$((FAIL + 1))
fi

# --- Test 7: no shadowBlur anywhere ---
begin_test "no shadowBlur anywhere"
assert_file_not_contains "no shadowBlur" "shadowBlur" "$TEMPLATE"

# --- Test 8: nine node type hues are defined ---
begin_test "nine node type hues are defined"
TYPE_HSL_BLOCK=$(awk '/const TYPE_HSL = \{/,/^\};/' "$TEMPLATE")
HUE_KEY_COUNT=$(echo "$TYPE_HSL_BLOCK" | grep -cE '^\s*[a-z]+:\s*\[')
assert_eq "TYPE_HSL has nine keys" "9" "$HUE_KEY_COUNT"
for t in cycle story fix tweak planning notebook riff dial mockup; do
  assert_contains "TYPE_HSL has a $t key" "$t:" "$TYPE_HSL_BLOCK"
done
assert_contains "dial hue matches the locked value" "\[302, 42, 63\]" "$TYPE_HSL_BLOCK"
assert_contains "mockup hue matches the locked value" "\[135, 45, 56\]" "$TYPE_HSL_BLOCK"
assert_file_not_contains "the banned yellow-green hue never appears" "\[80, 55, 56\]" "$TEMPLATE"

# --- Test 9: ported constants match their locked values ---
begin_test "ported constants match their locked values"
assert_file_contains "GROUND is #121214" "GROUND = '#121214'" "$TEMPLATE"
assert_file_contains "dust bucket maxR 11 bakeR 12" "key: 'dust', maxR: 11, bakeR: 12" "$TEMPLATE"
assert_file_contains "small bucket maxR 19 bakeR 20" "key: 'small', maxR: 19, bakeR: 20" "$TEMPLATE"
assert_file_contains "medium bucket maxR 29 bakeR 30" "key: 'medium', maxR: 29, bakeR: 30" "$TEMPLATE"
assert_file_contains "hub bucket maxR Infinity bakeR 42" "key: 'hub', maxR: Infinity, bakeR: 42" "$TEMPLATE"
assert_file_contains "radial glow stop at 0.8" "rgba(\${cs},0.8)" "$TEMPLATE"
assert_file_contains "radial glow stop at 0.26 / 0.45" "0.45, \`rgba(\${cs},0.26)\`" "$TEMPLATE"
assert_file_contains "radial glow stop at 0 / 1" "1, \`rgba(\${cs},0)\`" "$TEMPLATE"
assert_file_contains "flat circle pad is 6" "const pad = 6;" "$TEMPLATE"
assert_file_contains "flat circle rim width max(1px, 0.08r)" "Math.max(1, bakeR \\* 0.08)" "$TEMPLATE"
assert_file_contains "flat circle rim is own hue +16 lightness at 0.55 alpha" "rimRgb\\[2\\]},0.55)" "$TEMPLATE"
assert_file_contains "vignette inner radius 0.22" "Math.min(w, h) \* 0.22" "$TEMPLATE"
assert_file_contains "vignette outer radius 1.05" "Math.max(w, h) \\* 1.05" "$TEMPLATE"
assert_file_contains "vignette fades to 0.62 black at the edge" "rgba(0,0,0,0.62)" "$TEMPLATE"
assert_file_contains "DEG_CAP is 40" "const DEG_CAP = 40;" "$TEMPLATE"
assert_file_contains "MIN_R 6 and MAX_R 40" "const MIN_R = 6, MAX_R = 40;" "$TEMPLATE"
assert_file_contains "cycleScale is 0.65" "cycleScale: 0.65" "$TEMPLATE"
assert_file_contains "LT degreeAlwaysOn/hubZoom/dustZoom/ramp" "degreeAlwaysOn: Infinity, hubZoom: 2.2, dustZoom: 4.6, ramp: 0.8" "$TEMPLATE"
assert_file_contains "LABEL_HUB_ZOOM is 0.6" "const LABEL_HUB_ZOOM = 0.6;" "$TEMPLATE"
assert_file_contains "LABEL_DUST_ZOOM is 3.4" "const LABEL_DUST_ZOOM = 3.4;" "$TEMPLATE"
assert_file_contains "LABEL_RAMP is 0.9" "const LABEL_RAMP = 0.9;" "$TEMPLATE"
assert_file_contains "label pass renders at a constant 11px" "11px system-ui" "$TEMPLATE"
assert_file_contains "Sim options match the locked physics" "repulse: 60000, springK: 2.5, springLength: 110, damping: 0.94, gravity: 12, maxSpeed: 6000, alphaDecay: 0.025" "$TEMPLATE"
assert_file_contains "RING_R is 380" "const RING_R = 380;" "$TEMPLATE"
assert_file_contains "GOLDEN_ANGLE matches the locked value" "2.399963229728653" "$TEMPLATE"
assert_file_contains "spiral scale is 14 + sqrt(members) * 9" "14 + Math.sqrt(members.length) \* 9" "$TEMPLATE"
assert_file_contains "FIT_W_FRAC is 0.80" "const FIT_W_FRAC = 0.80;" "$TEMPLATE"
assert_file_contains "FIT_H_FRAC is 0.74" "const FIT_H_FRAC = 0.74;" "$TEMPLATE"
assert_file_contains "seedCompactCloud is called at scale 0.06" "0.06)" "$TEMPLATE"
assert_file_contains "entrance ramp is 0.38s" "/ 0.38" "$TEMPLATE"
assert_file_contains "camera scale clamps to 0.2..6" "clamp(this.scale \* factor, 0.2, 6)" "$TEMPLATE"
assert_file_contains "wheel-zoom factor expression matches" "Math.pow(2, -px \* (ev.ctrlKey ? 0.02 : 0.002))" "$TEMPLATE"
assert_file_contains "line-scroll deltaMode is scaled by 50" "ev.deltaMode === 1 ? 50 : 1" "$TEMPLATE"

# --- Test 10: ported constants match the mockup (skipped when the mockup is absent) ---
begin_test "ported constants match the mockup"
if [ ! -f "$MOCKUP" ]; then
  echo "  SKIP: mockup.html not present (gitignored .craft/ in a fresh clone)"
else
  PARITY_STRINGS=(
    "GROUND = '#121214'"
    "key: 'dust', maxR: 11, bakeR: 12"
    "key: 'hub', maxR: Infinity, bakeR: 42"
    "const DEG_CAP = 40;"
    "const MIN_R = 6, MAX_R = 40;"
    "cycleScale: 0.65"
    "degreeAlwaysOn: Infinity, hubZoom: 2.2, dustZoom: 4.6, ramp: 0.8"
    "const LABEL_HUB_ZOOM = 0.6;"
    "const LABEL_DUST_ZOOM = 3.4;"
    "const LABEL_RAMP = 0.9;"
    "repulse: 60000, springK: 2.5, springLength: 110, damping: 0.94, gravity: 12, maxSpeed: 6000, alphaDecay: 0.025"
    "const RING_R = 380;"
    "2.399963229728653"
    "const FIT_W_FRAC = 0.80;"
    "const FIT_H_FRAC = 0.74;"
    "clamp(this.scale * factor, 0.2, 6)"
  )
  for s in "${PARITY_STRINGS[@]}"; do
    if grep -qF "$s" "$MOCKUP"; then
      assert_file_contains "template matches mockup for: $s" "$(printf '%s' "$s" | sed 's/[.[\*^$/]/\\&/g')" "$TEMPLATE"
    else
      echo "  SKIP: '$s' not found in mockup.html (nothing to compare against)"
    fi
  done
fi

# --- Test 11: no comment references a workflow artifact ---
begin_test "no comment references a workflow artifact"
# "cycle" is a legitimate domain word (record type, cycleScale, computeRealLayout's
# cluster anchors) and is never itself a violation - only workflow vocabulary is.
# Only the comment PORTION of a line is scanned - an inline "//" comment sitting
# after real code (e.g. an object key literally named "story") must not flag the code.
COMMENT_TEXT=$(awk '
  { line = $0
    idx = index(line, "//")
    if (idx > 0) { print substr(line, idx); next }
    if (line ~ /^[ \t]*\*/ || line ~ /\/\*/) { print line }
  }
' "$TEMPLATE")
VIOLATIONS=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if printf '%s' "$line" | grep -qiE '\b(chunk|story|kept|dial-kept)\b|dial session|user-approved|20[0-9]{2}-[0-9]{2}-[0-9]{2}'; then
    echo "  offending line: $line"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done <<< "$COMMENT_TEXT"
assert_eq "no comment lines reference a workflow artifact" "0" "$VIOLATIONS"

# --- Test 12: page title is Craft Browser ---
begin_test "page title is Craft Browser"
assert_file_contains "title tag reads Craft Browser" "<title>Craft Browser</title>" "$TEMPLATE"

# --- Test 13: dial and mockup node hues plus a fallback ---
begin_test "dial and mockup node types render with their own hues"
assert_file_contains "dial hue is defined" "dial:" "$TEMPLATE"
assert_file_contains "mockup hue is defined" "mockup:" "$TEMPLATE"
assert_file_contains "an unrecognized type falls back to a neutral hue" "FALLBACK" "$TEMPLATE"

# --- Test 14: the panel carries the summary line and the chunk list ---
begin_test "the panel adapter carries chunks and summary through cloneNodes"
CLONE_BLOCK=$(awk '/function cloneNodes\(\)/,/^\}/' "$TEMPLATE")
assert_contains "cloneNodes copies chunks" "chunks:" "$CLONE_BLOCK"
assert_contains "cloneNodes copies summary" "summary:" "$CLONE_BLOCK"
assert_file_contains "the panel has a summary line element" "p-summary" "$TEMPLATE"

# --- Test 15: the panel renders exactly one Connections label, gated on having relations ---
begin_test "the panel renders exactly one Connections label, gated on having relations"
assert_file_not_contains "no static Connections label in the panel markup" '<div class="p-rel-label">Connections</div>' "$TEMPLATE"
FILLPANEL_BLOCK=$(awk '/fillPanel\(n\) \{/,/^  \}/' "$TEMPLATE")
REL_LABEL_COUNT=$(echo "$FILLPANEL_BLOCK" | grep -c "className = 'p-rel-label'")
assert_eq "fillPanel creates exactly two p-rel-label elements (work, connections)" "2" "$REL_LABEL_COUNT"
assert_contains "the Connections label is only created when a relation exists" "if (rels.length)" "$FILLPANEL_BLOCK"

# --- Test 16: no requestAnimationFrame is scheduled unconditionally ---
begin_test "no requestAnimationFrame is scheduled unconditionally"
assert_file_not_contains "no unconditional self-rescheduling loop" "requestAnimationFrame(this.loop)" "$TEMPLATE"
RAF_CALL_COUNT=$(grep -c "requestAnimationFrame(" "$TEMPLATE")
assert_eq "exactly two requestAnimationFrame call sites (requestRender, tick)" "2" "$RAF_CALL_COUNT"
assert_file_contains "the request-side call is guarded by a pending-frame check" "if (!this.rafId) this.rafId = requestAnimationFrame(this.tick);" "$TEMPLATE"
assert_file_contains "the loop-side call is guarded by the still flag" "if (still) this.rafId = requestAnimationFrame(this.tick);" "$TEMPLATE"

# --- Test 17: entranceStart is not seeded at construction ---
begin_test "entranceStart is not seeded at construction"
assert_file_not_contains "no entranceStart = performance.now() literal" "entranceStart = performance.now()" "$TEMPLATE"
assert_file_contains "entranceStart anchors to the first painted frame inside tick" "if (!this.entranceStart) this.entranceStart = now;" "$TEMPLATE"
assert_file_contains "entranceGlobalAlpha returns 0 while the anchor is unset" "if (!entranceStart) return 0;" "$TEMPLATE"

# --- Test 18: the rest predicate is defined once ---
begin_test "the rest predicate is defined once"
REST_THRESHOLD_COUNT=$(grep -c "0.0006" "$TEMPLATE")
assert_eq "the 0.0006 rest threshold appears exactly once" "1" "$REST_THRESHOLD_COUNT"
assert_file_contains "the loop reads rest through the shared predicate" "!this.sim.isAtRest()" "$TEMPLATE"

# --- Test 19: every input path calls requestRender ---
begin_test "every input path calls requestRender"
REQUEST_RENDER_COUNT=$(grep -c "this.requestRender();" "$TEMPLATE")
assert_eq "requestRender is called from every input site (mousedown, mousemove, release, mouseleave, wheel, resize, replay, goTo, goBack)" "9" "$REQUEST_RENDER_COUNT"

# --- Test 20: both controls exist ---
begin_test "both controls exist"
assert_file_contains "the controls cluster exists" 'id="controls"' "$TEMPLATE"
assert_file_contains "a replay control is present" 'id="replay-btn"' "$TEMPLATE"
assert_file_contains "a refresh control is present" 'id="refresh-btn"' "$TEMPLATE"

# --- Test 21: controls are not styled as dev chrome ---
begin_test "controls are not styled as dev chrome"
assert_file_not_contains "no dev-chrome fill colour #2a2a2a" "#2a2a2a" "$TEMPLATE"
assert_file_not_contains "no dev-chrome fill colour #1b1b1b" "#1b1b1b" "$TEMPLATE"
CONTROLS_BUTTON_CSS=$(awk '/#stage #controls button \{/,/^  \}/' "$TEMPLATE")
assert_contains "control buttons have no filled background" "background: transparent;" "$CONTROLS_BUTTON_CSS"

# --- Test 22: controls use the machine voice and the ghost border/text values ---
begin_test "controls use the machine voice and the ghost border/text values"
CONTROLS_CSS=$(awk '/#stage #controls \{/,/^  \}/' "$TEMPLATE")
assert_contains "controls use the machine-voice font stack" 'ui-monospace, "SF Mono", Menlo, Consolas, monospace' "$CONTROLS_CSS"
assert_contains "control buttons carry the hairline border" "1px solid rgba(210, 215, 225, 0.16)" "$CONTROLS_BUTTON_CSS"
# Raised from the original ghost 0.34: that measured 2.2:1, under the 4.5:1
# WCAG minimum, leaving the page's only two controls unreadable until hover.
assert_contains "control buttons rest at a legible value" "rgba(226, 230, 238, 0.78)" "$CONTROLS_BUTTON_CSS"
assert_file_contains "control buttons brighten on hover" "#stage #controls button:hover" "$TEMPLATE"

# --- Test 23: refresh reloads the page ---
begin_test "refresh reloads the page"
assert_file_contains "refresh calls location.reload()" "location.reload()" "$TEMPLATE"
assert_file_not_contains "refresh does not navigate any other way" "location.href = " "$TEMPLATE"

# --- Test 24: the notice is hidden by default ---
begin_test "the notice is hidden by default"
assert_file_contains "the notice element exists" 'class="notice"' "$TEMPLATE"
assert_file_contains "the notice's resting state is display: none" ".notice { display: none;" "$TEMPLATE"
assert_file_contains "the notice is only shown by adding a visible class" "classList.add('visible')" "$TEMPLATE"

# --- Test 25: the notice fires on a degraded build status ---
begin_test "the notice fires on a degraded build status"
NOTICE_FN=$(awk '/function computeNotice\(/,/^\}/' "$TEMPLATE")
assert_contains "computeNotice checks build.status for a non-ok value" "build.status !== 'ok'" "$NOTICE_FN"

# --- Test 26: the notice fires on a data version mismatch ---
begin_test "the notice fires on a data version mismatch"
assert_contains "computeNotice checks graph.version against the expected constant" "graph.version !== EXPECTED_DATA_VERSION" "$NOTICE_FN"
assert_file_contains "EXPECTED_DATA_VERSION is defined as 1" "const EXPECTED_DATA_VERSION = 1;" "$TEMPLATE"

# --- Test 27: the notice fires when no graph data is present ---
begin_test "the notice fires when no graph data is present"
assert_contains "computeNotice checks for absent or empty graph data" "!graph || !graph.nodes || !graph.nodes.length" "$NOTICE_FN"

# --- Test 28: the notice is silent when status is ok, version matches, and nodes exist ---
begin_test "the notice is silent when status is ok, version matches, and nodes exist"
NOTICE_FN_TRIMMED=$(echo "$NOTICE_FN" | grep -v '^[[:space:]]*//' | grep -v '^[[:space:]]*$')
LAST_LINE=$(echo "$NOTICE_FN_TRIMMED" | tail -2 | head -1)
assert_contains "computeNotice's final fallthrough is a null return" "return null;" "$LAST_LINE"

# --- Test 29: no age-based staleness threshold exists ---
begin_test "no age-based staleness threshold exists"
assert_file_not_contains "no comparison against CRAFT_BUILD.at" "\.at\b" "$NOTICE_FN"
assert_file_not_contains "no Date.now() elapsed-time comparison anywhere" "Date.now()" "$TEMPLATE"

# --- Test 30: controls do not overlap the panel or hint ---
begin_test "controls do not overlap the panel or hint"
assert_contains "controls sit near the top" "top: 20px;" "$CONTROLS_CSS"
assert_contains "controls align to the panel's right edge" "right: 22px;" "$CONTROLS_CSS"
assert_file_contains "the panel starts at top: 62px, clear of the controls above it" "top: 62px;" "$TEMPLATE"
assert_file_contains "the hint stays left-aligned, clear of the right-aligned controls" "left: 20px;" "$TEMPLATE"

# --- Test 31: no relationship, status or type display table is declared in the page ---
begin_test "no relationship, status or type display table is declared in the page"
assert_file_not_contains "no hardcoded KIND_OUT table" "const KIND_OUT" "$TEMPLATE"
assert_file_not_contains "no hardcoded KIND_IN table" "const KIND_IN" "$TEMPLATE"
assert_file_not_contains "no hardcoded STATUS table" "const STATUS = {" "$TEMPLATE"
assert_file_not_contains "no hardcoded TYPE_NAME table" "const TYPE_NAME = {" "$TEMPLATE"
# The card prints no relationship verbs since the Connections region became
# the commit strip, so there is no VOCAB.kinds read to assert. What must hold
# is that the words never creep back in as a hardcoded table (asserted above).
assert_file_not_contains "the panel reads no relationship words at all" "VOCAB.kinds" "$TEMPLATE"
assert_file_contains "the panel reads type words off the emitted vocabulary" "VOCAB.types" "$TEMPLATE"
assert_file_contains "the panel reads status words off the emitted vocabulary" "VOCAB.statuses" "$TEMPLATE"
assert_file_contains "the panel reads dial outcome words off the emitted vocabulary" "VOCAB.dial_outcomes" "$TEMPLATE"

# --- Test 32: the page still loads data through exactly two sibling script tags ---
begin_test "the page still loads data through exactly two sibling script tags"
SCRIPT_SRC_COUNT=$(grep -c '<script src=' "$TEMPLATE")
assert_eq "exactly two script src tags" "2" "$SCRIPT_SRC_COUNT"

# --- Test 33: an unrecognised status falls through to the stored value ---
begin_test "an unrecognised status falls through to the stored value"
assert_file_contains "the status fallback preserves the raw stored value" "|| n.status" "$TEMPLATE"

# --- Test 34: the data-version notice names the command that fixes it ---
begin_test "the data-version notice names the command that fixes it"
assert_file_contains "the notice tells the user to run /craft:dashboard" "/craft:dashboard" "$TEMPLATE"

# --- Test 35: the data-version notice no longer tells the user to refresh ---
begin_test "the data-version notice no longer tells the user to refresh"
assert_file_not_contains "the stale 'Refresh to try again' notice is gone" "Refresh to try again" "$TEMPLATE"

finish_tests "test-dashboard-template.sh"
