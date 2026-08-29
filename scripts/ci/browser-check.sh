#!/bin/bash
# browser-check.sh — the only check in the repo that RUNS the dashboard page.
#
# Builds a real dashboard.html from the tracked fixture corpus in a temp dir,
# opens it in headless Chrome over file:// (the way a user double-clicks
# .craft/dashboard.html - no server), and asserts the page actually loaded
# its data and rendered a record card:
#
#   1. window.CRAFT_GRAPH.nodes.length > 0            (data reached the page)
#   2. GraphInstance.sim.nodes.length === that count  (the view consumed it)
#   3. goTo(sim.nodes[0]) renders that node's label   (a card really rendered)
#      in #panel .p-title
#   4. #panel .p-summary has >= 1 element child        (the parse produced
#      after that goTo, when the probed node has a     real DOM, not raw text
#      summary - otherwise this prints a guarded SKIP)
#

# All 135 assertions in tests/test-dashboard-template.sh read the template as
# text and would pass on a page that throws on load; this one cannot.
#
# Usage:
#   browser-check.sh               full run (skips legibly when no Chrome)
#   browser-check.sh --build-only  build + artifact verification, no Chrome
#
# With no Chrome binary found the full run prints a SKIP line and exits 0 -
# the CI job is non-blocking by decision, so a missing browser must read as
# a legible log line, and the test suite must run on any contributor machine.
# CRAFT_CI_CHROME overrides discovery entirely (a nonexistent value forces
# the SKIP path).
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
fi

# --- Build the page from the tracked fixture corpus, never in the repo ------
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
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

# --- Inject the probe into a COPY beside the real page ----------------------
# Beside, so the sibling <script src="graph/*.js"> tags still resolve. The
# probe reports through document.title, which --dump-dom captures. It reads
# GraphInstance.sim.nodes (NOT GraphInstance.nodes, which silently falls
# through to raw graph nodes that carry no .label). Page globals are
# published on purpose for exactly this kind of probe (template/index.html
# documents window.NS/window.LT; window.GraphInstance is assigned the same
# way).
python3 - "$TMP/.craft/dashboard.html" "$TMP/.craft/ci-probe.html" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
probe = """
<script>
(function () {
  'use strict';
  function report(o) { document.title = 'CRAFTCI ' + JSON.stringify(o); }
  setTimeout(function () {
    var res = {};
    try {
      var g = window.CRAFT_GRAPH || {};
      res.graphNodeCount = (g.nodes || []).length;
      var gi = window.GraphInstance;
      if (!gi || !gi.sim || !gi.sim.nodes) {
        res.error = 'GraphInstance.sim.nodes not reachable';
        report(res);
        return;
      }
      res.simNodeCount = gi.sim.nodes.length;
      var n = gi.sim.nodes[0];
      res.expected = n ? n.label : null;
      gi.goTo(n);
      setTimeout(function () {
        try {
          var t = document.querySelector('#panel .p-title');
          res.titleText = t ? t.textContent : null;
          var p = document.querySelector('#panel');
          res.panelLen = p ? p.textContent.length : 0;
          var s = document.querySelector('#panel .p-summary');
          res.summaryChildren = s ? s.childElementCount : -1;
          res.probedHasSummary = !!(n && n.summary);
          report(res);
        } catch (e) { res.error = String(e); report(res); }
      }, 900);
    } catch (e) { res.error = String(e); report(res); }
  }, 600);
})();
</script>
"""
html = open(src, encoding="utf-8").read()
if "</body>" not in html:
    sys.exit("probe injection failed: no </body> in " + src)
open(dst, "w", encoding="utf-8").write(html.replace("</body>", probe + "</body>", 1))
PYEOF

# --- Run Chrome over file:// and read the verdict back ----------------------
DOM="$("$CHROME" --headless=new --disable-gpu --no-sandbox \
  --window-size=1400,900 --virtual-time-budget=15000 \
  --dump-dom "file://$TMP/.craft/ci-probe.html" 2>/dev/null)"

TITLE_JSON="$(printf '%s' "$DOM" | grep -o '<title>CRAFTCI [^<]*</title>' | head -1 \
  | sed -e 's/^<title>CRAFTCI //' -e 's#</title>$##')"

if [ -z "$TITLE_JSON" ]; then
  echo "FAIL: probe reported nothing (no CRAFTCI title in dumped DOM, $(printf '%s' "$DOM" | wc -c | tr -d ' ') bytes dumped)"
  exit 1
fi

echo "probe verdict: $TITLE_JSON"

python3 - "$TITLE_JSON" <<'PYEOF'
import html, json, sys
raw = sys.argv[1].strip()
try:
    data = json.loads(html.unescape(raw))
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
expected = data.get("expected")
title = data.get("titleText")
if expected and title == expected:
    print("assert 3 OK: selection rendered the card - #panel .p-title == %r" % expected)
else:
    failures.append("assert 3 FAILED: #panel .p-title is %r, expected %r" % (title, expected))
summary_children = data.get("summaryChildren", -1)
probed_has_summary = data.get("probedHasSummary", False)
if probed_has_summary:
    if summary_children >= 1:
        print("assert 4 OK: the parse produced real elements in #panel .p-summary (%d children)" % summary_children)
    else:
        failures.append("assert 4 FAILED: #panel .p-summary has no element children after goTo (%s)" % summary_children)
else:
    print("assert 4 SKIP: probed node has no summary text, nothing to parse")
if failures:
    for f in failures:
        print(f)
    sys.exit(1)
print("browser check passed: the page loads and renders over file://")
PYEOF
RC=$?
exit "$RC"
