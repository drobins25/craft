#!/bin/bash
# browser-check.sh — the only check in the repo that RUNS the dashboard page.
#
# Builds a real dashboard.html from the tracked fixture corpus in a temp dir,
# opens it in headless Chrome over file:// (the way a user double-clicks
# .craft/dashboard.html - no server), lets the page run its own render loop in
# real time, and asserts the page loaded its data, rendered, and behaves:
#
#   1.  window.CRAFT_GRAPH.nodes.length > 0            (data reached the page)
#   2.  GraphInstance.sim.nodes.length === that count  (the view consumed it)
#   2b. every sim node has finite x/y/homeX/homeY      (the layout fit never
#                                                       produced NaN)
#   2c. GraphInstance.heatCanvas.width === innerWidth  (the cluster heat baked)
#   3.  goTo(sim.nodes[0]) renders that node's label   (a card really rendered)
#       in #panel .p-title
#   4.  #panel .p-summary has >= 1 element child        (the parse produced
#       after that goTo, when the probed node has a     real DOM, not raw text
#       summary - otherwise this prints a guarded SKIP)
#   5-7. a synthetic drag engages a node, pins it where it is dropped, and the
#       render loop parks again (rafId === null)
#   8-9. the four authored insight cards render, each with a leader that ends
#       at finite coordinates
#   10. the page runs one render loop: its ticks never outnumber real frames
#
# scripts/ci/browser-probe.mjs drives Chrome over its DevTools protocol with
# node's built-in WebSocket (no packages). It never calls the page's frame
# callback and never runs under an artificial clock: an earlier probe that
# pushed tick() from a timer stacked ~150 render loops, took 45-90s, and
# passed its own checks only because of that artifact.
#
# All 135 assertions in tests/test-dashboard-template.sh read the template as
# text and would pass on a page that throws on load; this one cannot.
#
# Usage:
#   browser-check.sh               full run (skips legibly when no Chrome)
#   browser-check.sh --build-only  build + artifact verification, no Chrome
#
# With no Chrome binary (or no node) found the full run prints a SKIP line and
# exits 0 - the CI job is non-blocking by decision, so a missing browser must
# read as a legible log line, and the test suite must run on any contributor
# machine. CRAFT_CI_CHROME and CRAFT_CI_NODE override discovery entirely (a
# nonexistent value forces the SKIP path).
#
# Chrome writes noise to stderr on file:// loads that is expected and not a
# defect (scripts/dashboard/README.md documents the Chromium bug) - only the
# probe's JSON verdict decides pass/fail, never stderr content.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MODE="full"
if [ "${1:-}" = "--build-only" ]; then
  MODE="build-only"
fi

# --- Chrome discovery (first behaviour: a missing browser must be legible) ---
find_chrome() {
  if [ -n "${CRAFT_CI_CHROME:-}" ]; then
    if [ -x "$CRAFT_CI_CHROME" ]; then
      echo "$CRAFT_CI_CHROME"
      return 0
    fi
    return 1
  fi
  local c
  for c in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "$c" > /dev/null 2>&1; then
      command -v "$c"
      return 0
    fi
  done
  local mac_chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  if [ -x "$mac_chrome" ]; then
    echo "$mac_chrome"
    return 0
  fi
  return 1
}

CHROME=""
if [ "$MODE" = "full" ]; then
  if ! CHROME="$(find_chrome)"; then
    if [ -n "${CRAFT_CI_CHROME:-}" ]; then
      echo "SKIP: no Chrome binary found (looked for: \$CRAFT_CI_CHROME=$CRAFT_CI_CHROME)"
    else
      echo "SKIP: no Chrome binary found (looked for: google-chrome, google-chrome-stable, chromium, chromium-browser on PATH; /Applications/Google Chrome.app/Contents/MacOS/Google Chrome)"
    fi
    exit 0
  fi
  echo "using Chrome: $CHROME"
  if [ -n "${CRAFT_CI_NODE:-}" ]; then
    NODE="$CRAFT_CI_NODE"
    [ -x "$NODE" ] || { echo "SKIP: no node binary found (looked for: \$CRAFT_CI_NODE=$CRAFT_CI_NODE)"; exit 0; }
  else
    NODE="$(command -v node || true)"
    [ -n "$NODE" ] || { echo "SKIP: no node binary found (looked for: node on PATH)"; exit 0; }
  fi
  # The probe uses node's built-in WebSocket: on by default from node 22, behind
  # --experimental-websocket on 20.10 to 21 (GitHub's ubuntu runners ship 20).
  NODE_VERSION="$("$NODE" -p 'process.versions.node' 2>/dev/null || echo 0.0.0)"
  NODE_MAJOR="${NODE_VERSION%%.*}"
  NODE_MINOR="${NODE_VERSION#*.}"; NODE_MINOR="${NODE_MINOR%%.*}"
  NODE_FLAGS=()
  if [ "$NODE_MAJOR" -ge 22 ] 2>/dev/null; then
    :
  elif [ "$NODE_MAJOR" -eq 21 ] 2>/dev/null || { [ "$NODE_MAJOR" -eq 20 ] && [ "$NODE_MINOR" -ge 10 ]; } 2>/dev/null; then
    NODE_FLAGS=(--experimental-websocket)
  else
    echo "SKIP: node $NODE_VERSION is too old for the probe (needs 20.10 or later)"
    exit 0
  fi
  echo "using node: $NODE ($NODE_VERSION)"
fi

# --- Build the page from the tracked fixture corpus, never in the repo ------
TMP="$(mktemp -d)"
# A browser helper still flushing into the profile dir can make one rm -rf
# lose the race and leave the directory behind, so retry briefly.
cleanup() {
  local attempt=0
  while [ "$attempt" -lt 5 ]; do
    rm -rf "$TMP" 2>/dev/null
    [ -e "$TMP" ] || return 0
    attempt=$((attempt + 1))
    sleep 0.5
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "building fixture page in $TMP"
cp -R "$ROOT/scripts/dashboard/__fixtures__/corpus" "$TMP/.craft"
# The corpus can carry an untracked local .craft/ from someone once building
# with the corpus dir itself as root; a clean CI checkout will not have it.
# Remove it so local and CI builds agree.
rm -rf "$TMP/.craft/.craft"

bash "$ROOT/scripts/dashboard/dashboard-run.sh" --root "$TMP"
bash "$ROOT/scripts/dashboard/dashboard-page.sh" --pull --root "$TMP" > /dev/null

# dashboard-run.sh ALWAYS exits 0, including on a builder crash, so trust
# outputs, not exit codes: all three artifacts must exist before Chrome runs.
FAILED=0
if [ -f "$TMP/.craft/dashboard.html" ]; then
  echo "artifact OK: dashboard.html"
else
  echo "FAIL: build produced no dashboard.html"; FAILED=1
fi
if [ -f "$TMP/.craft/graph/graph.js" ]; then
  echo "artifact OK: graph/graph.js"
else
  echo "FAIL: build produced no graph/graph.js"; FAILED=1
fi
if [ -d "$TMP/.craft/graph/records" ] && [ -n "$(ls -A "$TMP/.craft/graph/records" 2>/dev/null)" ]; then
  echo "artifact OK: graph/records/ is non-empty"
else
  echo "FAIL: build produced no graph/records/ files"; FAILED=1
fi
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

if [ "$MODE" = "build-only" ]; then
  echo "build-only: artifacts verified, skipping Chrome"
  exit 0
fi

# --- Author an insight sidecar from the corpus's own record ids -------------
# The fixture corpus carries no hand-authored insights.js (the sidecar is
# authored, never built), so the card and leader assertions below would be
# vacuous. Write one whose evidence ids are real records, resolved against
# the live graph exactly the way a user's sidecar is.
python3 - "$TMP/.craft" <<'PYEOF'
import json, os, sys
root = sys.argv[1]
records = os.path.join(root, "graph", "records")
ids = sorted(os.path.splitext(f)[0] for f in os.listdir(records) if f.endswith(".js"))
cards = [{"body": "CI observation %d over the fixture corpus." % (i + 1),
          "witness": "browser-check", "evidence_node_ids": [rid]}
         for i, rid in enumerate(ids[:4])]
payload = {"version": 1, "cards": cards}
with open(os.path.join(root, "graph", "insights.js"), "w", encoding="utf-8") as f:
    f.write("window.CRAFT_INSIGHTS = " + json.dumps(payload) + ";\n")
PYEOF
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "FAIL: could not author fixture insights.js (python3 exited $RC)"
  exit "$RC"
fi
echo "authored fixture insights.js (4 cards from real record ids)"

# --- Run the page in real time and read the verdict back ------------------
VERDICT="$("$NODE" ${NODE_FLAGS[@]+"${NODE_FLAGS[@]}"} "$SCRIPT_DIR/browser-probe.mjs" "$CHROME" "file://$TMP/.craft/dashboard.html" "$TMP/chrome-profile" 2>/dev/null | tail -1)"

if [ -z "$VERDICT" ]; then
  echo "FAIL: the probe printed no verdict"
  exit 1
fi

echo "probe verdict: $VERDICT"

python3 - "$VERDICT" <<'PYEOF'
import json, sys
raw = sys.argv[1].strip()
try:
    data = json.loads(raw)
except ValueError as e:
    sys.exit("FAIL: probe verdict is not parseable JSON: %s (%s)" % (raw, e))
failures = []
if data.get("error"):
    failures.append("page error: %s" % data["error"])
graph_count = data.get("graphNodeCount", 0)
sim_count = data.get("simNodeCount", -1)
if graph_count > 0:
    print("assert 1 OK: CRAFT_GRAPH.nodes loaded (%d nodes)" % graph_count)
else:
    failures.append("assert 1 FAILED: CRAFT_GRAPH.nodes is empty - data never reached the page")
if sim_count == graph_count and graph_count > 0:
    print("assert 2 OK: GraphInstance.sim consumed all %d nodes" % sim_count)
else:
    failures.append("assert 2 FAILED: sim has %s nodes, graph has %s" % (sim_count, graph_count))
non_finite = data.get("nonFiniteNodes", -1)
if non_finite == 0:
    print("assert 2b OK: every node has finite x/y/homeX/homeY (0 non-finite of %d)" % sim_count)
else:
    failures.append("assert 2b FAILED: %s of %s nodes carry a non-finite x/y/homeX/homeY" % (non_finite, sim_count))
expected = data.get("expected")
title = data.get("titleText")
if expected and title == expected:
    print("assert 3 OK: selection rendered the card - #panel .p-title == %r" % expected)
else:
    failures.append("assert 3 FAILED: #panel .p-title is %r, expected %r" % (title, expected))
heat_w = data.get("heatW", -1)
inner_w = data.get("innerW", 0)
if heat_w > 0 and heat_w == inner_w:
    print("assert 2c OK: cluster heat baked at the viewport's width (%d)" % heat_w)
else:
    failures.append("assert 2c FAILED: heat canvas width is %s, viewport is %s" % (heat_w, inner_w))
summary_children = data.get("summaryChildren", -1)
probed_has_summary = data.get("probedHasSummary", False)
if probed_has_summary:
    if summary_children >= 1:
        print("assert 4 OK: the parse produced real elements in #panel .p-summary (%d children)" % summary_children)
    else:
        failures.append("assert 4 FAILED: #panel .p-summary has no element children after goTo (%s)" % summary_children)
else:
    print("assert 4 SKIP: probed node has no summary text, nothing to parse")
if data.get("dragEngaged"):
    print("assert 5 OK: the synthetic drag engaged a real node")
else:
    failures.append("assert 5 FAILED: the synthetic mousedown/mousemove never engaged a node")
if data.get("pinnedFx") and data.get("pinnedAtDrop"):
    print("assert 6 OK: release pinned the grabbed node exactly where it was dropped")
else:
    failures.append("assert 6 FAILED: pinnedFx=%s pinnedAtDrop=%s - release did not pin where dropped" % (data.get("pinnedFx"), data.get("pinnedAtDrop")))
if data.get("loopParked"):
    print("assert 7 OK: the render loop parked with a node pinned (rafId === null after %sms)" % data.get("settleMs"))
else:
    failures.append("assert 7 FAILED: the render loop never parked with a node pinned (still alive after %sms)" % data.get("settleMs"))
card_count = data.get("cardCount", -1)
if card_count == 4:
    print("assert 8 OK: four insight cards rendered from the authored sidecar")
else:
    failures.append("assert 8 FAILED: expected 4 insight cards, got %s" % card_count)
leaders = data.get("leaders", -1)
finite_leaders = data.get("finiteLeaders", -1)
if leaders == card_count and finite_leaders == leaders and leaders > 0:
    print("assert 9 OK: every card carries a leader terminating at finite coordinates (%d leaders)" % leaders)
else:
    failures.append("assert 9 FAILED: %s leaders for %s cards, %s finite" % (leaders, card_count, finite_leaders))
frames = data.get("frames", 0)
ticks = data.get("ticks", -1)
if frames > 0 and 0 < ticks <= frames:
    print("assert 10 OK: the page runs one render loop (%d ticks across %d frames)" % (ticks, frames))
else:
    failures.append("assert 10 FAILED: %s ticks across %s frames - more ticks than frames means stacked render loops" % (ticks, frames))
if failures:
    for f in failures:
        print(f)
    sys.exit(1)
print("browser check passed: the page loads and renders over file://")
PYEOF
RC=$?
exit "$RC"
