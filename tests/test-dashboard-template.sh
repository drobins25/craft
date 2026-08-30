#!/bin/bash
# test-dashboard-template.sh — Structural gate for scripts/dashboard/template/index.html:
# stripped dev chrome, file:// load path only, nine type hues, ported physics
# constants, and comment hygiene. Pure text properties of a file this repo ships.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

TEMPLATE="$PLUGIN_ROOT/scripts/dashboard/template/index.html"
MOCKUP="$PLUGIN_ROOT/.craft/mockups/2026-08-29-cluster-anchored-insight-layer/mockup.html"

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
assert_file_contains "flat circle pad is 6" "const pad = 6;" "$TEMPLATE"
assert_file_contains "fill sprites bake 4x supersampled" "const SS = 4;" "$TEMPLATE"
assert_file_contains "bake canvas dimensions scale by the supersample" "(bakeR \\* 2 + pad \\* 2) \\* SS" "$TEMPLATE"
assert_file_contains "bake radius scales by the supersample" "bakeR \\* SS, 0, TAU" "$TEMPLATE"
assert_file_contains "flat circle rim width max(1px, 0.08r), scaled by the supersample" "Math.max(1, bakeR \\* 0.08) \\* SS" "$TEMPLATE"
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
assert_file_contains "Sim options match the accepted stance" "repulse: 30000, springK: 0.9, springLength: 92, damping: 0.94, gravity: 10, maxSpeed: 6000, alphaDecay: 0.026" "$TEMPLATE"
assert_file_contains "GOLDEN_ANGLE matches the locked value" "2.399963229728653" "$TEMPLATE"
assert_file_contains "spiral scale is (10 + sqrt(members) * 8) * spread" "(10 + Math.sqrt(members.length) \* 8) \* spreadMult" "$TEMPLATE"
assert_file_contains "the spread multiplier is 1.0" "const SPREAD_MULT = 1.0;" "$TEMPLATE"
assert_file_contains "the plate fits 0.72 x 0.66 of the viewport" "0.72, 0.66)" "$TEMPLATE"
assert_file_contains "camera scale clamps to 0.2..6" "clamp(this.scale \* factor, 0.2, 6)" "$TEMPLATE"
assert_file_contains "wheel-zoom factor expression matches" "Math.pow(2, -px \* (ev.ctrlKey ? 0.02 : 0.002))" "$TEMPLATE"
assert_file_contains "line-scroll deltaMode is scaled by 50" "ev.deltaMode === 1 ? 50 : 1" "$TEMPLATE"

# --- Test 9b: type-anchor relaxation matches the accepted stance ---
begin_test "type-anchor relaxation matches the accepted stance"
assert_file_contains "anchor spread radius is 26 + sqrt(massArea) * 1.15" "26 + Math.sqrt(massArea) \* 1.15" "$TEMPLATE"
assert_file_contains "anchors seed at 220 + spreadR" "const seedR = 220 + a.spreadR;" "$TEMPLATE"
assert_file_contains "anchor seed y is scaled 0.7" "Math.sin(ang) \* seedR \* 0.7" "$TEMPLATE"
assert_file_contains "anchors relax for 420 iterations" "iter < 420" "$TEMPLATE"
assert_file_contains "pairwise clearance is spreadR + spreadR + 46" "ai.spreadR + bj.spreadR + 46" "$TEMPLATE"
assert_file_contains "anchor push factor is 0.05" "(minD - d) \* 0.05" "$TEMPLATE"
assert_file_contains "anchor centre gravity is 0.00016 * spreadR" "0.00016 \* ai.spreadR" "$TEMPLATE"
assert_file_contains "node mass is 0.6 + t * 2.2" "n.mass = 0.6 + t \* 2.2;" "$TEMPLATE"
assert_file_contains "repulsion floors at half the combined radii" "Math.max(d, combined \* 0.5)" "$TEMPLATE"
assert_file_contains "soft collision correction is 3.4x overlap" "(combined - d) \* 3.4" "$TEMPLATE"
assert_file_not_contains "the old fixed repulsion floor is gone" "Math.max(d, 4)" "$TEMPLATE"

# --- Test 9c: the plate is fitted with one uniform scale ---
begin_test "the plate is fitted with one uniform scale"
assert_file_contains "the fit takes the smaller axis scale" "Math.min(scaleX, scaleY)" "$TEMPLATE"
assert_file_not_contains "homes never scale per-axis on x" "homeRefX - cx0) \* scaleX" "$TEMPLATE"
assert_file_not_contains "homes never scale per-axis on y" "homeRefY - cy0) \* scaleY" "$TEMPLATE"

# --- Test 9d: the cycle-ring layout is gone ---
begin_test "the cycle-ring layout is gone"
assert_file_not_contains "no RING_R" "RING_R" "$TEMPLATE"
assert_file_not_contains "no computeRealLayout" "computeRealLayout" "$TEMPLATE"
assert_file_not_contains "no dust ring base radius" "DUST_R0" "$TEMPLATE"
assert_file_not_contains "no FIT_W_FRAC" "FIT_W_FRAC" "$TEMPLATE"
assert_file_not_contains "no FIT_H_FRAC" "FIT_H_FRAC" "$TEMPLATE"
assert_file_not_contains "no MEMBERSHIP_KINDS read" "MEMBERSHIP_KINDS" "$TEMPLATE"
assert_file_not_contains "the vocabulary fallback drops its membership key" "membership: \[\]" "$TEMPLATE"

# --- Test 9e: the rest predicate reads the held node, not the pinned set ---
begin_test "the rest predicate reads the held node, not the pinned set"
HASFIXED_LINE=$(grep "hasFixed()" "$TEMPLATE" | head -1)
assert_contains "hasFixed reads the held node" "this.dragNode != null" "$HASFIXED_LINE"
assert_not_contains "hasFixed no longer scans the node set" "for (" "$HASFIXED_LINE"

# --- Test 9f: cluster heat is baked, additive, and analytic ---
begin_test "cluster heat is baked, additive, and analytic"
assert_file_contains "heat sprite centre stop is 0.55" "addColorStop(0, rgbCss(rgb, 0.55))" "$TEMPLATE"
assert_file_contains "heat sprite mid stop is 0.22 at 0.4" "addColorStop(0.4, rgbCss(rgb, 0.22))" "$TEMPLATE"
assert_file_contains "heat sprite outer stop fades to 0" "addColorStop(1, rgbCss(rgb, 0))" "$TEMPLATE"
assert_file_contains "heat is stamped additively" "globalCompositeOperation = 'lighter'" "$TEMPLATE"
assert_file_contains "heat size derives from the analytic final-scatter prediction" "analyticMaxDRef" "$TEMPLATE"
BAKE_HEAT_FN=$(awk '/  bakeHeat\(\) \{/,/^  \}/' "$TEMPLATE")
assert_not_contains "no live member-position averaging survives in the bake" "cx += " "$BAKE_HEAT_FN"
assert_contains "heat position projects the FITTED anchor" "(anchor.x - fit.cx0) \* fit.scale" "$BAKE_HEAT_FN"
assert_file_contains "heat alpha is 0.5" "const HEAT_ALPHA = 0.5;" "$TEMPLATE"
assert_file_contains "heat size multiplier is 1.1" "const HEAT_SIZE_MULT = 1.1;" "$TEMPLATE"
assert_contains "the cooled region's heat drops to 0.7x alpha" "HEAT_ALPHA \* 0.7" "$BAKE_HEAT_FN"
assert_file_contains "the early heat beat is 1600ms" "const EARLY_HEAT_MS = 1600;" "$TEMPLATE"
assert_file_contains "the heat fade is 600ms" "const HEAT_FADE_MS = 600;" "$TEMPLATE"
CAMERA_PASS=$(awk '/ctx.translate\(w \/ 2, h \/ 2\); ctx.scale/,/ctx.restore\(\)/' "$TEMPLATE")
assert_contains "heat draws inside the camera transform" "drawImage(this.heatCanvas, 0, 0, w, h)" "$CAMERA_PASS"

# --- Test 9g: completed records of the most numerous type cool to grey texture ---
begin_test "completed records of the most numerous type cool to grey texture"
assert_file_contains "the dim sprite bakes from the near-neutral triple" "\[220, 4, 36\]" "$TEMPLATE"
assert_file_contains "the cooled branch draws the dim sprite at 0.8" "cooled ? 0.8 : 1" "$TEMPLATE"
assert_file_contains "cooling keys on the completed and shipped states" "n.status === 'complete' || n.status === 'shipped'" "$TEMPLATE"

# --- Test 9h: no per-node glow survives anywhere ---
begin_test "no per-node glow survives anywhere"
assert_file_not_contains "no bakeAmbientGlow" "bakeAmbientGlow" "$TEMPLATE"
assert_file_not_contains "no bakeRadialGlow" "bakeRadialGlow" "$TEMPLATE"
assert_file_not_contains "no GLOW_ACCENT_TO_R" "GLOW_ACCENT_TO_R" "$TEMPLATE"
assert_file_not_contains "no GLOW_HUB ratios" "GLOW_HUB" "$TEMPLATE"
assert_file_not_contains "no ambientGlowFor" "ambientGlowFor" "$TEMPLATE"
assert_file_not_contains "no glowFor" "glowFor" "$TEMPLATE"
assert_file_not_contains "no hoverGlow bakery" "hoverGlow" "$TEMPLATE"

# --- Test 9i: no silhouette or contour code exists ---
begin_test "no silhouette or contour code exists"
assert_file_not_contains "no computeSilhouette" "computeSilhouette" "$TEMPLATE"
assert_file_not_contains "no marching squares" "marching" "$TEMPLATE"
assert_file_not_contains "no chaikin smoothing" "chaikin" "$TEMPLATE"

# --- Test 9j: no depth or mesh distance ramp survives ---
begin_test "no depth or mesh distance ramp survives"
assert_file_not_contains "no DEPTH_ALPHA_FLOOR" "DEPTH_ALPHA_FLOOR" "$TEMPLATE"
assert_file_not_contains "no DEPTH_REACH_TO_W" "DEPTH_REACH_TO_W" "$TEMPLATE"
assert_file_not_contains "no MESH_ALPHA_NEAR" "MESH_ALPHA_NEAR" "$TEMPLATE"
assert_file_not_contains "no MESH_REACH_TO_W" "MESH_REACH_TO_W" "$TEMPLATE"
assert_file_not_contains "no heroHub depth origin" "heroHub" "$TEMPLATE"
assert_file_contains "the resting mesh strokes the accepted quiet value" "rgba(180,190,210,0.085)" "$TEMPLATE"

# --- Test 9k: the swirl entrance matches the accepted stance ---
begin_test "the swirl entrance matches the accepted stance"
MATCHMEDIA_COUNT=$(grep -c "matchMedia" "$TEMPLATE")
assert_eq "reduced motion is evaluated once, at module scope" "1" "$MATCHMEDIA_COUNT"
assert_file_contains "the reduced-motion query gates the swirl" "prefers-reduced-motion: reduce" "$TEMPLATE"
assert_file_contains "the seed scales are the accepted pair" "? 0.022 : 0.055" "$TEMPLATE"
assert_file_not_contains "the old flat seed scale call is gone" "h / 2, 0.06)" "$TEMPLATE"
assert_file_contains "the launch caps at 900" "Math.min(dist \* 2.6, 900)" "$TEMPLATE"
assert_file_contains "the launch carries a dominant tangential component" "launch \* 0.35 + tx \* launch \* 0.9" "$TEMPLATE"
assert_file_contains "the repulsion pop decays over 380ms" "(1 - elapsed / 380) \* 0.7" "$TEMPLATE"

# --- Test 9l: drag tows direct neighbours and release pins where dropped ---
begin_test "drag tows direct neighbours and release pins where dropped"
assert_file_contains "the tow coefficient is 26" "const towK = 26;" "$TEMPLATE"
assert_file_contains "the tow skips already-pinned neighbours" "if (tn.fx != null) continue;" "$TEMPLATE"
assert_file_contains "grab raises alpha to at least the 0.35 target" "this.sim.alphaTarget = 0.35;" "$TEMPLATE"
RELEASE_FN=$(awk '/const release = \(\) => \{/,/^    \};/' "$TEMPLATE")
assert_not_contains "release never clears the held node's pin" "dragNode.fx = null" "$RELEASE_FN"
assert_not_contains "release never re-seeds" "seedCompactCloud" "$RELEASE_FN"
assert_not_contains "release never replays the entrance" "replay()" "$RELEASE_FN"
assert_contains "release reheats the field" "this.sim.alpha = 1;" "$RELEASE_FN"
assert_contains "release opens the recovery window" "this.sim.recoverT0 = performance.now();" "$RELEASE_FN"

# --- Test 9m: the recovery window eases damping from 0.992 over 1100ms ---
begin_test "the recovery window eases damping from 0.992 over 1100ms"
assert_file_contains "the recovery window is 1100ms" "const RECOVER_MS = 1100;" "$TEMPLATE"
assert_file_contains "damping eases down from 0.992" "(0.992 - damping) \* (1 - elapsed / RECOVER_MS)" "$TEMPLATE"

# --- Test 9n: replay clears every pin before seeding ---
begin_test "replay clears every pin before seeding"
REPLAY_ORDER_FN=$(awk '/  replay\(\) \{/,/^  \}/' "$TEMPLATE")
PIN_CLEAR_LINE=$(echo "$REPLAY_ORDER_FN" | grep -n "n.fx = null; n.fy = null;" | head -1 | cut -d: -f1)
SEED_LINE=$(echo "$REPLAY_ORDER_FN" | grep -n "seedCompactCloud" | head -1 | cut -d: -f1)
if [ -n "$PIN_CLEAR_LINE" ] && [ -n "$SEED_LINE" ] && [ "$PIN_CLEAR_LINE" -lt "$SEED_LINE" ]; then
  echo "  PASS: the pin sweep precedes the seed call in replay()"
  PASS=$((PASS + 1))
else
  echo "  FAIL: the pin sweep precedes the seed call in replay() (sweep=$PIN_CLEAR_LINE seed=$SEED_LINE)"
  FAIL=$((FAIL + 1))
fi

# --- Test 9o: the two-profile decay system and the global entrance fade are gone ---
begin_test "the two-profile decay system and the global entrance fade are gone"
assert_file_not_contains "no DECAY_SNAPPY" "DECAY_SNAPPY" "$TEMPLATE"
assert_file_not_contains "no DECAY_CINEMATIC" "DECAY_CINEMATIC" "$TEMPLATE"
assert_file_not_contains "no entranceGlobalAlpha" "entranceGlobalAlpha" "$TEMPLATE"

# --- Test 10: ported constants match the mockup (skipped when the mockup is absent) ---
begin_test "ported constants match the mockup"
if [ ! -f "$MOCKUP" ]; then
  echo "  SKIP: mockup.html not present (gitignored .craft/ in a fresh clone)"
else
  PARITY_STRINGS=(
    "'#121214'"
    "key: 'dust', maxR: 11, bakeR: 12"
    "key: 'hub', maxR: Infinity, bakeR: 42"
    "DEG_CAP = 40"
    "MIN_R = 6, MAX_R = 40"
    "repulse: 30000, springK: 0.9, springLength: 92,"
    "2.399963229728653"
    "26 + Math.sqrt(massArea) * 1.15"
    "const seedR = 220 + a.spreadR;"
    "const minD = ai.spreadR + bj.spreadR + 46;"
    "const push = (minD - d) * 0.05;"
    "const gk = 0.00016 * ai.spreadR;"
    "(10 + Math.sqrt(members.length) * 8)"
    "spiralScale * Math.sqrt(j + 0.5)"
    "const scale = Math.min(scaleX, scaleY);"
    "0.72, 0.66)"
    "const dd = Math.max(d, combined * 0.5);"
    "(combined - d) * 3.4"
    "n.mass = 0.6 + "
    "addColorStop(0, rgbCss(rgb, 0.55))"
    "addColorStop(0.4, rgbCss(rgb, 0.22))"
    "bake('story_dim', [220, 4, 36])"
    "const analyticMaxD = Math.max(30, analyticMaxDRef * fit.scale);"
    "(analyticMaxD + 40) * 2.1"
    "const EARLY_HEAT_MS = 1600;"
    "rgba(180,190,210,0.085)"
    "? 0.022 : 0.055"
    "const launch = Math.min(dist * 2.6, 900);"
    "launch * 0.35 + tx * launch * 0.9"
    "(1 - elapsed / 380) * 0.7"
    "const towK = 26;"
    "const RECOVER_MS = 1100;"
    "(0.992 - damping) * (1 - elapsed / RECOVER_MS)"
    "rgba(14,15,19,0.94)"
    "box-shadow: inset 0 1px 0 rgba(255,255,255,0.06), 0 10px 30px rgba(0,0,0,0.45);"
    "transition: opacity 480ms ease, transform 480ms cubic-bezier(0.16,1,0.3,1);"
    "(ci * 110) + 'ms'"
    "{ side: 'left', x: 0.028, y: 0.075 }"
    "const stepSize = 6, standoff = 14;"
    "const fallback = Math.max(dist - 60, dist * 0.5);"
    "'left' ? 1 : -1) * 14"
    "const back = 8, spread = 4;"
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
REL_LABEL_COUNT=$(echo "$FILLPANEL_BLOCK" | grep -c "className = 'p-rel-label")
assert_eq "fillPanel creates exactly two p-rel-label elements (work, connections)" "2" "$REL_LABEL_COUNT"
assert_contains "the Connections label is only created when a relation exists" "if (rels.length)" "$FILLPANEL_BLOCK"

# --- Test 16: no requestAnimationFrame is scheduled unconditionally ---
begin_test "no requestAnimationFrame is scheduled unconditionally"
assert_file_not_contains "no unconditional self-rescheduling loop" "requestAnimationFrame(this.loop)" "$TEMPLATE"
RAF_CALL_COUNT=$(grep -c "requestAnimationFrame(" "$TEMPLATE")
assert_eq "exactly three requestAnimationFrame call sites (requestRender, requestFrame, tick)" "3" "$RAF_CALL_COUNT"
assert_file_contains "the request-side call is guarded by a pending-frame check" "if (!this.rafId) this.rafId = requestAnimationFrame(this.tick);" "$TEMPLATE"
assert_file_contains "the loop-side call is guarded by the still flag AND a pending-frame check" "if (still && !this.rafId) this.rafId = requestAnimationFrame(this.tick);" "$TEMPLATE"

# --- Test 17: entranceStart is not seeded at construction ---
begin_test "entranceStart is not seeded at construction"
assert_file_not_contains "no entranceStart = performance.now() literal" "entranceStart = performance.now()" "$TEMPLATE"
assert_file_contains "entranceStart anchors to the first painted frame inside tick" "if (!this.entranceStart) this.entranceStart = now;" "$TEMPLATE"
assert_file_contains "the simulation's pop window anchors on the same painted frame" "if (!this.sim.entranceT0) this.sim.entranceT0 = now;" "$TEMPLATE"

# --- Test 18: the rest predicate is defined once ---
begin_test "the rest predicate is defined once"
REST_THRESHOLD_COUNT=$(grep -c "0.0008" "$TEMPLATE")
assert_eq "the 0.0008 rest threshold appears exactly once" "1" "$REST_THRESHOLD_COUNT"
assert_file_contains "the loop reads rest through the shared predicate" "!this.sim.isAtRest()" "$TEMPLATE"

# --- Test 19: every input path calls requestRender; internal animations use requestFrame ---
begin_test "every input path calls requestRender"
REQUEST_RENDER_COUNT=$(grep -c "this.requestRender();" "$TEMPLATE")
assert_eq "requestRender is called from every input site (mousedown, mousemove, release, mouseleave, wheel, resize, replay, goTo, goBack)" "9" "$REQUEST_RENDER_COUNT"
REQUEST_FRAME_COUNT=$(grep -c "this.requestFrame();" "$TEMPLATE")
assert_eq "requestFrame is called from every internal-animation site (revealCards, heat arm, leader fade)" "3" "$REQUEST_FRAME_COUNT"

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

# --- Test 32: the page still loads data through exactly three sibling script tags ---
begin_test "the page still loads data through exactly three sibling script tags"
SCRIPT_SRC_COUNT=$(grep -c '<script src=' "$TEMPLATE")
assert_eq "exactly three script src tags" "3" "$SCRIPT_SRC_COUNT"
assert_file_contains "insights.js sibling script tag present" 'src="graph/insights.js"' "$TEMPLATE"
GRAPH_TAG_LINE=$(grep -n 'src="graph/graph.js"' "$TEMPLATE" | head -1 | cut -d: -f1)
INSIGHTS_TAG_LINE=$(grep -n 'src="graph/insights.js"' "$TEMPLATE" | head -1 | cut -d: -f1)
if [ -n "$GRAPH_TAG_LINE" ] && [ -n "$INSIGHTS_TAG_LINE" ] && [ "$GRAPH_TAG_LINE" -lt "$INSIGHTS_TAG_LINE" ]; then
  echo "  PASS: insights.js loads after graph.js"
  PASS=$((PASS + 1))
else
  echo "  FAIL: insights.js loads after graph.js"
  FAIL=$((FAIL + 1))
fi

# --- Test 33: an unrecognised status falls through to the stored value ---
begin_test "an unrecognised status falls through to the stored value"
assert_file_contains "the status fallback preserves the raw stored value" "|| n.status" "$TEMPLATE"

# --- Test 34: the data-version notice names the command that fixes it ---
begin_test "the data-version notice names the command that fixes it"
assert_file_contains "the notice tells the user to run /craft:dashboard" "/craft:dashboard" "$TEMPLATE"

# --- Test 35: the data-version notice no longer tells the user to refresh ---
begin_test "the data-version notice no longer tells the user to refresh"
assert_file_not_contains "the stale 'Refresh to try again' notice is gone" "Refresh to try again" "$TEMPLATE"

# --- Test 36: the sidecar guard uses the shipped absent-or-malformed idiom ---
begin_test "the sidecar guard uses the shipped absent-or-malformed idiom"
assert_file_contains "guard reads window.CRAFT_INSIGHTS through a conjunction" "window.CRAFT_INSIGHTS && window.CRAFT_INSIGHTS.version === 1" "$TEMPLATE"
assert_file_contains "guard checks cards is an array" "Array.isArray(window.CRAFT_INSIGHTS.cards)" "$TEMPLATE"
assert_file_not_contains "no try/catch wraps the sidecar read" "try {" "$TEMPLATE"
assert_file_contains "the per-card pass drops null and non-object entries" "filter(c => c && typeof c === 'object')" "$TEMPLATE"

# --- Test 37: card surface constants match the ruled values ---
begin_test "card surface constants match the ruled values"
CARD_CSS=$(awk '/#stage #cards .card \{/,/^  \}/' "$TEMPLATE")
assert_contains "card fill is the near-opaque value" "background: rgba(14,15,19,0.94);" "$CARD_CSS"
assert_contains "card radius is 11px" "border-radius: 11px;" "$CARD_CSS"
assert_contains "card padding matches" "padding: 13px 15px 14px;" "$CARD_CSS"
assert_contains "the card shadow is the inset highlight plus the ruled drop shadow" "box-shadow: inset 0 1px 0 rgba(255,255,255,0.06), 0 10px 30px rgba(0,0,0,0.45);" "$CARD_CSS"
assert_contains "card width is 300px" "width: 300px;" "$CARD_CSS"
assert_file_contains "the border carries the evidence hue at 0.55 alpha" '%,0.55)' "$TEMPLATE"
assert_contains "the card entrance rests hidden and shifted" "transform: translateY(8px);" "$CARD_CSS"
assert_contains "the card entrance rides the accepted curve" "transition: opacity 480ms ease, transform 480ms cubic-bezier(0.16,1,0.3,1);" "$CARD_CSS"
assert_file_contains "cards stagger in 110ms apart" "(ci \* 110) + 'ms'" "$TEMPLATE"
assert_contains "card face is the zero-download system stack" "font-family: -apple-system, system-ui, 'Segoe UI', sans-serif;" "$CARD_CSS"
assert_contains "card weight is 450" "font-weight: 450;" "$CARD_CSS"
assert_contains "card tracking is 0em" "letter-spacing: 0em;" "$CARD_CSS"
assert_contains "optical sizing is auto" "font-optical-sizing: auto;" "$CARD_CSS"

# --- Test 38: eyebrow, body and witness typography match the ruled values ---
begin_test "eyebrow, body and witness typography match the ruled values"
EYEBROW_CSS=$(awk '/#stage #cards .card .c-eyebrow \{/,/^  \}/' "$TEMPLATE")
assert_contains "eyebrow is mono" 'ui-monospace, "SF Mono", Menlo, Consolas, monospace' "$EYEBROW_CSS"
assert_contains "eyebrow is 11px" "font-size: 11px;" "$EYEBROW_CSS"
assert_contains "eyebrow tracking is 0.14em" "letter-spacing: 0.14em;" "$EYEBROW_CSS"
assert_contains "eyebrow is uppercase" "text-transform: uppercase;" "$EYEBROW_CSS"
assert_contains "eyebrow lays out as flex with a 6px gap" "gap: 6px;" "$EYEBROW_CSS"
assert_file_contains "the eyebrow dot is 6px round" '.c-eyebrow .dot { width: 6px; height: 6px; border-radius: 50%;' "$TEMPLATE"
assert_file_contains "eyebrow colour lifts the hue by 12 lightness" "Math.min(90, hsl\[2\] + 12)" "$TEMPLATE"
BODY_CSS=$(awk '/#stage #cards .card .c-body \{/,/^  \}/' "$TEMPLATE")
assert_contains "body is 14px" "font-size: 14px;" "$BODY_CSS"
assert_contains "body line-height is 1.5" "line-height: 1.5;" "$BODY_CSS"
assert_contains "body colour is #e8eaef" "color: #e8eaef;" "$BODY_CSS"
WITNESS_CSS=$(awk '/#stage #cards .card .c-witness \{/,/^  \}/' "$TEMPLATE")
assert_contains "witness line is mono" 'ui-monospace, "SF Mono", Menlo, Consolas, monospace' "$WITNESS_CSS"
assert_contains "witness line is 11px" "font-size: 11px;" "$WITNESS_CSS"

# --- Test 39: card prose is left-aligned unconditionally ---
begin_test "card prose is left-aligned unconditionally"
assert_contains "the body rule pins text-align left" "text-align: left;" "$BODY_CSS"
assert_not_contains "no right-aligned prose in the body rule" "text-align: right" "$BODY_CSS"
assert_file_contains "right-pinned cards justify only the eyebrow" ".card.pin-right .c-eyebrow { justify-content: flex-end; }" "$TEMPLATE"

# --- Test 40: the ruled drop shadow is the card's only non-inset shadow ---
begin_test "the ruled drop shadow is the card's only non-inset shadow"
assert_not_contains "no backdrop-filter in the card rule" "backdrop-filter" "$CARD_CSS"
assert_not_contains "no filter property in the card rule" "filter:" "$CARD_CSS"
CARD_SHADOWS=$(echo "$CARD_CSS" | grep "box-shadow" || true)
NON_INSET_SHADOWS=$(echo "$CARD_SHADOWS" | grep -v "inset" || true)
assert_eq "every card box-shadow line carries the inset highlight" "" "$NON_INSET_SHADOWS"
# The surgical allowance: strip the one ruled non-inset literal and only the
# inset highlight may remain - any other non-inset shadow still fails here.
STRIPPED_SHADOWS=$(echo "$CARD_SHADOWS" | sed 's/, 0 10px 30px rgba(0,0,0,0.45)//')
assert_contains "stripping the ruled literal leaves only the inset highlight" "box-shadow: inset 0 1px 0 rgba(255,255,255,0.06);" "$STRIPPED_SHADOWS"

# --- Test 41: the witness footer renders from the sidecar ---
begin_test "the witness footer renders from the sidecar"
assert_file_contains "the witnessed by prefix is rendered" "'witnessed by ' + card.witness" "$TEMPLATE"
assert_file_contains "an empty witness skips the footer entirely" "if (card.witness) {" "$TEMPLATE"

# --- Test 42: slot insets match the ported plate percentages ---
begin_test "slot insets match the ported plate percentages"
SLOTS_BLOCK=$(awk '/const CARD_SLOTS = \[/,/^\];/' "$TEMPLATE")
assert_contains "slot 1 is left 2.8% top 7.5%" "side: 'left', x: 0.028, y: 0.075" "$SLOTS_BLOCK"
assert_contains "slot 2 is right 2.8% top 10%" "side: 'right', x: 0.028, y: 0.10" "$SLOTS_BLOCK"
assert_contains "slot 3 is left 2.8% top 62%" "side: 'left', x: 0.028, y: 0.62" "$SLOTS_BLOCK"
assert_contains "slot 4 is right 2.8% top 60%" "side: 'right', x: 0.028, y: 0.60" "$SLOTS_BLOCK"
assert_file_contains "the layer hides below the desktop floor" "CARD_MIN_W = 1100, CARD_MIN_H = 700" "$TEMPLATE"

# --- Test 43: reveal races rest against a 2000ms ceiling ---
begin_test "reveal races rest against a 2000ms ceiling"
REVEAL_LINE=$(grep "this.revealCards();" "$TEMPLATE")
assert_contains "the reveal condition names the rest predicate" "this.sim.isAtRest()" "$REVEAL_LINE"
assert_contains "the reveal condition names the hard ceiling" "CARD_REVEAL_MS" "$REVEAL_LINE"
assert_file_contains "the reveal ceiling is 2000ms" "const CARD_REVEAL_MS = 2000;" "$TEMPLATE"
assert_file_not_contains "the old fixed-delay reveal constant is gone" "CARD_REVEAL_DELAY_MS" "$TEMPLATE"
REVEAL_FN=$(awk '/  revealCards\(\) \{/,/^  \}/' "$TEMPLATE")
assert_contains "the reveal path schedules a frame without stamping input" "this.requestFrame();" "$REVEAL_FN"
REVEAL_RR_COUNT=$(echo "$REVEAL_FN" | grep -c "this.requestRender();" || true)
assert_eq "the reveal path never calls requestRender" "0" "$REVEAL_RR_COUNT"
LATCH_ORDER=$(echo "$REVEAL_FN" | awk '/cardsViewportOk\(\)/{if (!b) b=NR} /this.cardsShown = true/{if (!l) l=NR} END{print (b && l && b < l) ? "bail-first" : "latch-first"}')
assert_eq "the viewport bail precedes the reveal latch" "bail-first" "$LATCH_ORDER"

# --- Test 44: replay resets the card reveal flag ---
begin_test "replay resets the card reveal flag"
REPLAY_FN=$(awk '/  replay\(\) \{/,/^  \}/' "$TEMPLATE")
assert_contains "replay clears cardsShown" "this.cardsShown = false;" "$REPLAY_FN"
assert_contains "replay removes the shown class" "classList.remove('shown')" "$REPLAY_FN"

# --- Test 45: the panel and the card layer share one visibility seam ---
begin_test "the panel and the card layer share one visibility seam"
SEAM_FN=$(awk '/  setPanelVisible\(on\) \{/,/^  \}/' "$TEMPLATE")
assert_contains "the seam toggles the panel" "this.panel.classList.toggle('visible', on)" "$SEAM_FN"
assert_contains "the seam suppresses the card layer" "classList.toggle('suppressed', on)" "$SEAM_FN"
DIRECT_PANEL_TOGGLES=$(grep -c "panel.classList.toggle('visible'" "$TEMPLATE")
assert_eq "the panel visible class is toggled only inside the seam" "1" "$DIRECT_PANEL_TOGGLES"

# --- Test 46: leaders are canvas strokes, never SVG ---
begin_test "leaders are canvas strokes, never SVG"
assert_file_not_contains "no createElementNS" "createElementNS" "$TEMPLATE"
assert_file_not_contains "no SVG namespace url can exist (http:// gate re-run)" "http://" "$TEMPLATE"
LEADER_PASS=$(awk '/Leader pass:/,/Screen-space label pass/' "$TEMPLATE")
assert_contains "the leader pass strokes with ctx.stroke" "ctx.stroke();" "$LEADER_PASS"
assert_contains "the leader is a quadratic curve" "quadraticCurveTo" "$LEADER_PASS"
assert_contains "the leader is dotted 1-on-6" "setLineDash(\[1, 6\])" "$LEADER_PASS"
assert_contains "the dot caps are round" "lineCap = 'round'" "$LEADER_PASS"

# --- Test 47: every hue stroke rides a casing stroke ---
begin_test "every hue stroke rides a casing stroke"
assert_contains "the casing colour is the locked dark value" "rgba(8,9,12,0.65)" "$LEADER_PASS"
CASING_WIDTH_COUNT=$(echo "$LEADER_PASS" | grep -c "ctx.lineWidth = 3; ctx.strokeStyle = CASING; ctx.stroke();")
assert_eq "the 3px casing stroke is drawn once, under the hue stroke" "1" "$CASING_WIDTH_COUNT"
FIRST_CASING_LINE=$(echo "$LEADER_PASS" | grep -n "strokeStyle = CASING" | head -1 | cut -d: -f1)
FIRST_HUE_LINE=$(echo "$LEADER_PASS" | grep -n "strokeStyle = L.hue" | head -1 | cut -d: -f1)
if [ -n "$FIRST_CASING_LINE" ] && [ -n "$FIRST_HUE_LINE" ] && [ "$FIRST_CASING_LINE" -lt "$FIRST_HUE_LINE" ]; then
  echo "  PASS: the casing stroke precedes the hue stroke"
  PASS=$((PASS + 1))
else
  echo "  FAIL: the casing stroke precedes the hue stroke (casing=$FIRST_CASING_LINE hue=$FIRST_HUE_LINE)"
  FAIL=$((FAIL + 1))
fi
assert_contains "the arrowhead is a filled triangle at the endpoint" "ctx.closePath(); ctx.fillStyle = L.hue; ctx.fill();" "$LEADER_PASS"

# --- Test 48: the leader stops short of the dot field ---
begin_test "the leader stops short of the dot field"
DERIVE_FN=$(awk '/  cloudContact\(/,/^  \}/' "$TEMPLATE")
assert_contains "the march steps 6px with a 14px standoff" "const stepSize = 6, standoff = 14;" "$DERIVE_FN"
assert_contains "every node is tested at its projected radius plus a 3px pad" "n.hw \* scale + 3" "$DERIVE_FN"
assert_contains "first contact backs off by the standoff" "stepSize \* s - standoff" "$DERIVE_FN"
assert_contains "a rayless miss still stops well short of the centroid" "Math.max(dist - 60, dist \* 0.5)" "$DERIVE_FN"

# --- Test 49: leader geometry is live, layout-box anchored, and gently bent ---
begin_test "leader geometry is live, layout-box anchored, and gently bent"
LEADERS_FN=$(awk '/  deriveLeaders\(/,/^  \}/' "$TEMPLATE")
assert_contains "the card end reads the untransformed layout box" "el.offsetLeft + el.offsetWidth" "$LEADERS_FN"
assert_contains "the card end centres on the layout height" "el.offsetTop + el.offsetHeight / 2" "$LEADERS_FN"
assert_contains "the bend is capped at 14" "'left' ? 1 : -1) \* 14" "$LEADERS_FN"
assert_contains "the arrowhead sits back 8 with a 4 spread" "const back = 8, spread = 4;" "$LEADERS_FN"
assert_contains "coordinates round to integers before caching" "Math.round(x1)" "$LEADERS_FN"
assert_contains "the leader hue lifts the evidence hue by 6" "Math.min(85, meta.hsl\[2\] + 6)" "$LEADERS_FN"
assert_contains "a card with no resolving evidence carries no leader" "meta.leader = null; continue;" "$LEADERS_FN"

# --- Test 50: the leader fade and re-march ride their own clocks ---
begin_test "the leader fade and re-march ride their own clocks"
assert_file_contains "leaders fade in over 500ms" "const LEADER_FADE_MS = 500;" "$TEMPLATE"
assert_file_contains "the fade starts 400ms after the reveal" "const LEADER_FADE_DELAY_MS = 400;" "$TEMPLATE"
assert_file_contains "contacts re-derive at most once per 100ms" "const LEADER_REMARCH_MS = 100;" "$TEMPLATE"
assert_file_contains "the leader alpha ramps off the reveal clock" "(performance.now() - this.cardsShownAt - LEADER_FADE_DELAY_MS) / LEADER_FADE_MS" "$TEMPLATE"

# --- Test 51: no shadowBlur enters the file with the leader pass present ---
begin_test "no shadowBlur enters the file with the leader pass present"
assert_file_not_contains "no shadowBlur (re-run against the enlarged file)" "shadowBlur" "$TEMPLATE"

# --- Test 52: leaders draw only while cards are shown and the panel is closed ---
begin_test "leaders draw only while cards are shown and the panel is closed"
assert_contains "the leader pass gates on cardsShown" "this.cardsShown && this.cardMeta.length" "$LEADER_PASS"
assert_contains "the leader pass gates on the suppressed class" "classList.contains('suppressed')" "$LEADER_PASS"
assert_contains "the leader pass gates on the desktop viewport floor" "cardsViewportOk()" "$LEADER_PASS"
assert_contains "a card whose leader never resolved draws nothing" "if (!L) continue;" "$LEADER_PASS"

# --- Test 53: the ring and hover warmth are ruled deletions ---
begin_test "the ring and hover warmth are ruled deletions"
assert_file_not_contains "no card hover index survives" "hoverCardIndex" "$TEMPLATE"
assert_file_not_contains "no warmth easing constant survives" "CARD_GLOW_EASE" "$TEMPLATE"
assert_file_not_contains "no hover bloom gradient survives" "createRadialGradient(nx, ny" "$TEMPLATE"
assert_file_not_contains "no card glow state survives" "cardGlow" "$TEMPLATE"
assert_file_contains "cards accept the mouse only once revealed" "#stage #cards.shown .card { pointer-events: auto; }" "$TEMPLATE"
assert_file_contains "a suppressed layer gives the mouse back" "#stage #cards.suppressed .card { pointer-events: none; }" "$TEMPLATE"

# --- Test 53b: the eyebrow date badge derives from the quote-source node ---
begin_test "the eyebrow date badge derives from the quote-source node"
assert_file_contains "the badge element rides the eyebrow" "dateEl.className = 'c-date';" "$TEMPLATE"
assert_file_contains "the badge takes the far end via the auto margin" ".c-eyebrow .c-date { margin-left: auto; font-size: 9.5px; letter-spacing: 0.1em; opacity: 0.75; }" "$TEMPLATE"
assert_file_contains "the month renders from the uppercase table" "const CARD_MONTHS = \['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'\];" "$TEMPLATE"
assert_file_contains "the badge reads the first evidence node's date" "const src = card.nodes\[0\];" "$TEMPLATE"

# --- Test 54: work rows carry a status dot, never a number ---
begin_test "work rows carry a status dot, never a number"
FILLPANEL_NOW=$(awk '/fillPanel\(n\) \{/,/^  \}/' "$TEMPLATE")
assert_not_contains "no ordinal prefix renders in a work row" "c.number" "$FILLPANEL_NOW"
assert_contains "each work row carries a status dot element" "p-chunk-dot" "$FILLPANEL_NOW"
assert_contains "a completed row is classed for its faded title" "' is-complete'" "$FILLPANEL_NOW"
CHUNK_ROW_CSS=$(awk '/#stage #panel .p-chunk \{/,/^  \}/' "$TEMPLATE")
assert_contains "work rows lay out as flex" "display: flex;" "$CHUNK_ROW_CSS"
assert_contains "work rows use the ruled 0.5em gap" "gap: 0.5em;" "$CHUNK_ROW_CSS"
assert_contains "text-indent is pinned to 0" "text-indent: 0;" "$CHUNK_ROW_CSS"
CHUNK_DOT_CSS=$(awk '/#stage #panel .p-chunk .p-chunk-dot \{/,/^  \}/' "$TEMPLATE")
assert_contains "the dot is 7px wide" "width: 7px;" "$CHUNK_DOT_CSS"
assert_contains "the dot is 7px tall" "height: 7px;" "$CHUNK_DOT_CSS"
assert_contains "the resting dot is the pending 1px ring" "border: 1px solid #6b7080;" "$CHUNK_DOT_CSS"
assert_contains "the pending ring rides at 0.5 opacity" "opacity: 0.5;" "$CHUNK_DOT_CSS"
assert_file_contains "the active dot is a 1.5px accent ring" "border: 1.5px solid #9fd8ff;" "$TEMPLATE"
assert_file_contains "the complete dot fills solid" "background: #c7cbd4;" "$TEMPLATE"
assert_file_contains "a completed row's title fades to 0.65" "p-chunk.is-complete .p-chunk-title { opacity: 0.65; }" "$TEMPLATE"

# --- Test 55: the spark is always the whole record, scrolling in its own window ---
begin_test "the spark is always the whole record, scrolling in its own window"
assert_file_not_contains "no reveal control survives in the markup" 'class="p-more"' "$TEMPLATE"
assert_file_not_contains "no line clamp survives" "webkit-line-clamp" "$TEMPLATE"
assert_file_not_contains "no clamped state survives" "is-clamped" "$TEMPLATE"
assert_file_not_contains "no expanded state survives - there is only one state" "is-expanded" "$TEMPLATE"
SUMMARY_CSS=$(awk '/#stage #panel .p-summary \{/,/^  \}/' "$TEMPLATE")
assert_contains "the spark scrolls inside its own window" "overflow-y: auto;" "$SUMMARY_CSS"
assert_contains "the reading window caps at 36vh" "max-height: 36vh;" "$SUMMARY_CSS"
assert_contains "the scroll is contained - it never flings the page" "overscroll-behavior: contain;" "$SUMMARY_CSS"
assert_contains "the record reads in the serif reading voice" 'font-family: Charter, "Iowan Old Style", Georgia, serif;' "$SUMMARY_CSS"
assert_file_contains "the scrollbar is the slim 4px thumb" "p-summary::-webkit-scrollbar { width: 4px; }" "$TEMPLATE"
assert_file_contains "the full source loads the moment the panel opens" "if (n.summary) this.loadRecordText(n.id, text => {" "$TEMPLATE"
assert_file_contains "a fresh record starts scrolled to the top" "summaryEl.scrollTop = 0;" "$TEMPLATE"

# --- Test 56: the full text loads through the sibling-script idiom ---
begin_test "the full text loads through the sibling-script idiom"
assert_file_contains "the mirror path is built from the graph subdirectory" "'graph/records/' + id + '.js'" "$TEMPLATE"
assert_file_contains "a failed mirror load degrades instead of breaking" "tag.onerror" "$TEMPLATE"
assert_file_contains "rapid re-opens queue on one in-flight tag per id" "_mirrorWaiters\[id\].push(cb)" "$TEMPLATE"
assert_file_contains "the arrival only writes into the panel it was asked for" "if (this.selectedNode !== n) return;" "$TEMPLATE"

# --- Test 57: the type line tiers its colours through spans ---
begin_test "the type line tiers its colours through spans"
assert_file_contains "the status span steps back" "p-type-status { color: #9298a6; }" "$TEMPLATE"
assert_file_contains "the date span steps back further" "p-type-date { color: #7b808e; }" "$TEMPLATE"
assert_contains "the status word renders into its own span" "'p-type-status'" "$FILLPANEL_NOW"
assert_contains "the date renders into its own span" "'p-type-date'" "$FILLPANEL_NOW"
assert_contains "the separator stays the bare middle dot" "' · '" "$FILLPANEL_NOW"

# --- Test 58: the back control keeps its ruled bare style ---
begin_test "the back control keeps its ruled bare style"
P_BACK_CSS=$(awk '/#stage #panel .p-back \{/,/^  \}/' "$TEMPLATE")
assert_contains "the back control stays fully unstyled" "all: unset;" "$P_BACK_CSS"
assert_not_contains "no border crept onto the back control" "border" "$P_BACK_CSS"
assert_not_contains "no background crept onto the back control" "background" "$P_BACK_CSS"

# --- Test 59: hover arms at calm - after the fling, before full rest ---
begin_test "hover arms at calm - after the fling, before full rest"
assert_file_contains "the hover hit-test rides the calm latch" "this.calm ? hitTestNode" "$TEMPLATE"
assert_file_contains "the calm point is one named tunable constant" "const HOVER_CALM_MS = 1500;" "$TEMPLATE"
CALM_LINE=$(grep "this.calm = true;" "$TEMPLATE")
CALM_LINE_COUNT=$(echo "$CALM_LINE" | grep -c "this.calm = true;")
assert_eq "the latch is armed at exactly one site" "1" "$CALM_LINE_COUNT"
assert_contains "the latch arms on the load clock" "(now - this.entranceStart) > HOVER_CALM_MS" "$CALM_LINE"
assert_not_contains "the latch is not chained to the physics energy" "this.sim.alpha" "$CALM_LINE"
assert_not_contains "the latch does not wait for full rest" "isAtRest" "$CALM_LINE"
REPLAY_REARM=$(awk '/  replay\(\) \{/,/^  \}/' "$TEMPLATE")
assert_contains "replay re-arms the hover gate alongside the card reveal" "this.calm = false;" "$REPLAY_REARM"

# --- Test 60: the record reads in a lit well over a distinct deck ---
begin_test "the record reads in a lit well over a distinct deck"
assert_file_contains "the well wraps the summary in the static markup" '<div class="p-summary-well"><div class="p-summary" tabindex="0"></div></div>' "$TEMPLATE"
WELL_CSS=$(awk '/#stage #panel .p-summary-well \{/,/^  \}/' "$TEMPLATE")
assert_contains "the well is its own recessed layer" "background: rgba(18,18,21,0.4);" "$WELL_CSS"
assert_contains "the well insets its own chrome" "box-shadow: inset 0 1px 0 rgba(255,255,255,0.05), inset 0 -10px 16px -12px rgba(0,0,0,0.5);" "$WELL_CSS"
assert_file_contains "the well carries a diagonal sheen overlay" ".p-summary-well::before {" "$TEMPLATE"
assert_file_contains "the well carries a corner vignette overlay" ".p-summary-well::after {" "$TEMPLATE"

REL_CSS=$(awk '/#stage #panel .p-rels \{/,/^  \}/' "$TEMPLATE")
assert_contains "the deck carries its own fill" "background: rgba(255,255,255,0.018);" "$REL_CSS"
assert_contains "the deck rounds its own corners" "border-radius: 8px;" "$REL_CSS"

REL_LABEL_CSS=$(awk '/#stage #panel .p-rel-label \{/,/^  \}/' "$TEMPLATE")
assert_not_contains "no hairline separates the well from the deck" "border-top" "$REL_LABEL_CSS"

assert_file_contains "the drop-cap carries the record's hue" "p-summary p:first-of-type::first-letter {" "$TEMPLATE"
assert_file_contains "the drop-cap has an initial-letter override" "@supports (initial-letter: 2) or (-webkit-initial-letter: 2) {" "$TEMPLATE"

PANEL_FRAME_CSS=$(awk '/#stage #panel \{/,/^  \}/' "$TEMPLATE")
assert_contains "the panel frame takes the card radius" "border-radius: 11px;" "$PANEL_FRAME_CSS"

TITLE_CSS=$(awk '/#stage #panel .p-title \{/,/^  \}/' "$TEMPLATE")
assert_contains "the record title reads in the serif voice" 'font-family: Charter, "Iowan Old Style", Georgia, serif;' "$TITLE_CSS"
assert_contains "the record title holds the mockup's size" "font-size: 18px;" "$TITLE_CSS"

STAMP_LINE=$(head -10 "$TEMPLATE" | grep '<meta name="craft-template-version" content="')
assert_not_contains "the template stamp moved off 5" 'content="5"' "$STAMP_LINE"

# --- Test 61: record text becomes structured, verbatim DOM through the parse ---
begin_test "record text becomes structured, verbatim DOM through the parse"
RENDER_PROSE=$(awk '/  renderProse\(/,/^  \}/' "$TEMPLATE")
RENDER_YAML=$(awk '/  renderYamlFields\(/,/^  \}/' "$TEMPLATE")
RENDER_RECORD=$(awk '/  renderRecord\(/,/^  \}/' "$TEMPLATE")
assert_contains "a line break inside a paragraph survives as a break element" "createElement('br')" "$RENDER_PROSE"
assert_not_contains "renderProse never writes record text through innerHTML" "innerHTML" "$RENDER_PROSE"
assert_not_contains "renderYamlFields never writes record text through innerHTML" "innerHTML" "$RENDER_YAML"
assert_not_contains "renderRecord never writes record text through innerHTML" "innerHTML" "$RENDER_RECORD"
assert_contains "an ATX heading line renders as a heading, marker consumed" "#\{1,6\}" "$RENDER_PROSE"
assert_contains "the heading becomes an h2 element" "'h2'" "$RENDER_PROSE"
assert_contains "a leading title heading is deduped against the panel title" "String(title" "$RENDER_PROSE"
assert_contains "cycle records render key/value field wrappers" "'yaml-field'" "$RENDER_YAML"
assert_contains "cycle records render dim mono keys" "'yaml-key'" "$RENDER_YAML"
assert_contains "cycle records render hanging values" "'yaml-val'" "$RENDER_YAML"
assert_contains "list items carry their own marker" "'yaml-list-marker'" "$RENDER_YAML"
assert_contains "the chrome-duplicated keys are a fixed list, not a judgment" "name: true" "$RENDER_YAML"
assert_contains "the fixed key list omits the status/date chrome fields too" "updated: true" "$RENDER_YAML"

FILLPANEL_NOW=$(awk '/fillPanel\(n\) \{/,/^  \}/' "$TEMPLATE")
assert_contains "the record's hue reaches the panel on every fill" "setProperty('--h'" "$FILLPANEL_NOW"
assert_contains "the type word renders into its own hued span" "'p-type-name'" "$FILLPANEL_NOW"
assert_contains "an empty summary hides the whole well, not just the summary" "p-summary-well" "$FILLPANEL_NOW"
assert_contains "the teaser paints through the parse" "this.renderRecord(summaryEl" "$FILLPANEL_NOW"
assert_file_contains "the mirror guard still gates a race between records" "if (this.selectedNode !== n) return;" "$TEMPLATE"

TYPE_CSS=$(awk '/#stage #panel .p-type \{/,/^  \}/' "$TEMPLATE")
assert_contains "the type line's separators dim to the machine gray" "color: #7b808e;" "$TYPE_CSS"
assert_file_contains "the type word takes the record's own hue" ".p-type .p-type-name { color: hsl(var(--h) var(--s) var(--l)); }" "$TEMPLATE"

SUMMARY_CSS=$(awk '/#stage #panel .p-summary \{/,/^  \}/' "$TEMPLATE")
assert_not_contains "the reading window no longer relies on pre-wrap" "white-space: pre-wrap;" "$SUMMARY_CSS"

# --- Test 62: no new frame loop enters the template (rAF-stacking scar stays closed) ---
# FIRST TEST for chunk 3: pinned to the pre-chunk-3 count so a new call site fails loudly.
begin_test "no new frame loop enters the template"
RAF_COUNT=$(grep -c "requestAnimationFrame" "$TEMPLATE" || true)
assert_eq "requestAnimationFrame call sites are unchanged by this story" "4" "$RAF_COUNT"

# --- Test 63: the record arrives by an ink wipe, sequenced after the panel's slide-in ---
begin_test "the record arrives by an ink wipe, sequenced after the panel's slide-in"
assert_file_contains "the wipe keyframe is the mockup's clip-path reveal" "@keyframes c-ink-wipe { from { clip-path: inset(0 0 0 100%); } to { clip-path: inset(0 0 0 0%); } }" "$TEMPLATE"
assert_file_contains "the reduced-motion wipe is an opacity-only equivalent" "@keyframes c-ink-wipe-reduced { from { opacity: 0; } to { opacity: 1; } }" "$TEMPLATE"
SUMMARY_CSS=$(awk '/#stage #panel .p-summary \{/,/^  \}/' "$TEMPLATE")
assert_contains "the wipe animation rides on the summary rule" "animation: c-ink-wipe 320ms ease both;" "$SUMMARY_CSS"
assert_contains "the wipe is sequenced ~100ms after the panel's own slide-in" "animation-delay: 0.32s;" "$SUMMARY_CSS"

FILLPANEL_NOW=$(awk '/fillPanel\(n\) \{/,/^  \}/' "$TEMPLATE")
assert_contains "fillPanel reads whether the panel was already open" "const wasOpen = this.panel.classList.contains('visible');" "$FILLPANEL_NOW"
assert_contains "the wipe restarts by clearing the animation shorthand" "summaryEl.style.animation = 'none';" "$FILLPANEL_NOW"
assert_contains "the restart forces a reflow before restoring the shorthand" "void summaryEl.offsetHeight;" "$FILLPANEL_NOW"
assert_contains "the shorthand is restored before the delay override" "summaryEl.style.animation = '';" "$FILLPANEL_NOW"
assert_contains "a record switch plays the wipe with no delay; a fresh open keeps the stylesheet's delay" "summaryEl.style.animationDelay = wasOpen ? '0s' : '';" "$FILLPANEL_NOW"
# the delay assignment must follow the shorthand restore (the shorthand clears any inline delay)
ANIMATION_RESET_LINE=$(echo "$FILLPANEL_NOW" | grep -n "summaryEl.style.animation = ''\|summaryEl.style.animationDelay" | head -2)
RESET_ORDER=$(echo "$ANIMATION_RESET_LINE" | awk -F: '{print $1}' | tr '\n' ' ')
FIRST_LINE=$(echo "$RESET_ORDER" | awk '{print $1}')
SECOND_LINE=$(echo "$RESET_ORDER" | awk '{print $2}')
if [ -n "$FIRST_LINE" ] && [ -n "$SECOND_LINE" ] && [ "$FIRST_LINE" -lt "$SECOND_LINE" ]; then
  ORDER_OK="yes"
else
  ORDER_OK="no"
fi
assert_eq "the delay is assigned AFTER the shorthand restore, not before" "yes" "$ORDER_OK"

RENDER_RECORD=$(awk '/  renderRecord\(/,/^  \}/' "$TEMPLATE")
LOAD_MIRROR_BLOCK=$(awk '/this.loadRecordText\(n.id, text => \{/,/^    \}\);/' "$TEMPLATE")
assert_not_contains "the mirror text swap does not restart the wipe" "style.animation" "$LOAD_MIRROR_BLOCK"

# --- Test 64: scroll fades are class-toggled, not computed per frame ---
begin_test "scroll fades are class-toggled, not computed per frame"
WIRE_FADE=$(awk '/  wireVerticalFade\(/,/^  \}/' "$TEMPLATE")
assert_contains "the fade updater toggles the at-top class" "classList.toggle('at-top'" "$WIRE_FADE"
assert_contains "the fade updater toggles the at-bottom class" "classList.toggle('at-bottom'" "$WIRE_FADE"
assert_not_contains "the scroll handler writes no inline styles" "style." "$WIRE_FADE"
assert_contains "the scroll listener is passive" "{ passive: true }" "$WIRE_FADE"
assert_contains "the updater is returned so a fill can re-run it" "return update;" "$WIRE_FADE"

SUMMARY_CSS=$(awk '/#stage #panel .p-summary \{/,/^  \}/' "$TEMPLATE")
assert_contains "the summary's base mask hides a 22px top band" "transparent 0, #000 22px, #000 calc(100% - 40px), transparent 100%" "$SUMMARY_CSS"
SUMMARY_AT_TOP_CSS=$(awk '/#stage #panel .p-summary.at-top \{/,/^  \}/' "$TEMPLATE")
assert_contains "at the top, only the bottom edge fades" "#000 0, #000 calc(100% - 40px), transparent 100%" "$SUMMARY_AT_TOP_CSS"
SUMMARY_AT_BOTTOM_CSS=$(awk '/#stage #panel .p-summary.at-bottom \{/,/^  \}/' "$TEMPLATE")
assert_contains "at the bottom, only the top edge fades" "transparent 0, #000 22px, #000 100%" "$SUMMARY_AT_BOTTOM_CSS"
assert_file_contains "a resting panel with nothing to hide shows no mask at all" ".p-summary.at-top.at-bottom { -webkit-mask-image: none; mask-image: none; }" "$TEMPLATE"

REL_CSS=$(awk '/#stage #panel .p-rels \{/,/^  \}/' "$TEMPLATE")
assert_contains "the deck's base mask uses the smaller 14px bands" "transparent 0, #000 14px, #000 calc(100% - 14px), transparent 100%" "$REL_CSS"
assert_file_contains "the deck fades on the same mechanic at the top" ".p-rels.at-top {" "$TEMPLATE"
assert_file_contains "the deck fades on the same mechanic at the bottom" ".p-rels.at-bottom {" "$TEMPLATE"
assert_file_contains "a resting deck with nothing to hide shows no mask at all" ".p-rels.at-top.at-bottom { -webkit-mask-image: none; mask-image: none; }" "$TEMPLATE"

assert_file_contains "the summary fade is wired exactly once, alongside the panel it persists on" "this._summaryFade = this.wireVerticalFade(this.panel.querySelector('.p-summary'));" "$TEMPLATE"
assert_file_contains "the deck fade is wired exactly once, alongside the panel it persists on" "this._relsFade = this.wireVerticalFade(this.panel.querySelector('.p-rels'));" "$TEMPLATE"
assert_contains "every fill re-runs both fade updaters synchronously" "if (this._summaryFade) this._summaryFade();" "$FILLPANEL_NOW"
assert_contains "the deck's fade updater re-runs on every fill too" "if (this._relsFade) this._relsFade();" "$FILLPANEL_NOW"

# --- Test 65: heading focus is feature-detected and silent without headings ---
begin_test "heading focus is feature-detected and silent without headings"
HEADING_FOCUS_BLOCK=$(awk '/@supports \(animation-timeline: view\(\)\) \{/,/^  \}/' "$TEMPLATE")
assert_contains "heading focus only applies inside the feature-detect block" "animation-timeline: view();" "$HEADING_FOCUS_BLOCK"
assert_contains "the heading focus keyframe dims at both ends and peaks mid-crossing" "@keyframes c-heading-focus { 0% { opacity: 0.55; } 40% { opacity: 1; } 60% { opacity: 1; } 100% { opacity: 0.55; } }" "$HEADING_FOCUS_BLOCK"
assert_contains "the heading focus range spans the full crossing of the scroller" "animation-range: entry 0% exit 100%;" "$HEADING_FOCUS_BLOCK"

# --- Test 66: reduced motion drops the wipe to a fade and the panel entrance to no translate ---
begin_test "reduced motion drops the wipe to a fade and the panel entrance to no translate"
REDUCED_MOTION_BLOCK=$(awk '/@media \(prefers-reduced-motion: reduce\) \{/,/^  \}/' "$TEMPLATE")
assert_contains "the reduced-motion wipe replaces the clip-path reveal" "c-ink-wipe-reduced 220ms ease both;" "$REDUCED_MOTION_BLOCK"
assert_contains "the reduced-motion wipe keeps the mockup's 0.28s delay" "animation-delay: 0.28s;" "$REDUCED_MOTION_BLOCK"
assert_contains "the panel entrance drops its translate under reduced motion" "transform: none;" "$REDUCED_MOTION_BLOCK"

# --- Test 67: the work list is collapsible and ships collapsed every fill ---
begin_test "the work list is collapsible and ships collapsed every fill"
assert_file_contains "the toggle label is not selectable text" ".p-rel-label.chunks-toggle { cursor: pointer; user-select: none; }" "$TEMPLATE"
assert_file_contains "the disclosure glyph reserves a fixed width" ".chunks-toggle .disclosure { display: inline-block; width: 0.9em; }" "$TEMPLATE"
assert_file_contains "a collapsed work list is hidden outright" ".p-chunk-list.is-collapsed { display: none; }" "$TEMPLATE"
assert_contains "the work label carries the toggle class" "'p-rel-label chunks-toggle'" "$FILLPANEL_NOW"
assert_contains "the work label opens with a collapsed disclosure glyph" "▸" "$FILLPANEL_NOW"
assert_contains "the chunk list ships collapsed on every fill" "'p-chunk-list is-collapsed'" "$FILLPANEL_NOW"
assert_contains "clicking the label toggles the collapsed class on the list" "classList.toggle('is-collapsed')" "$FILLPANEL_NOW"
assert_contains "the disclosure glyph flips between the collapsed and open marks" "collapsed ? '▸' : '▾'" "$FILLPANEL_NOW"
assert_contains "the Connections label is never given the toggle class" "label.className = 'p-rel-label'; label.textContent = 'Connections';" "$FILLPANEL_NOW"

finish_tests "test-dashboard-template.sh"
