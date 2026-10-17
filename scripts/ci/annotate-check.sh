#!/bin/bash
# annotate-check.sh - runs the annotate loop in real headless Chrome.
#
# Serves a small fixture project over http on 127.0.0.1 (never straight from disk: Chrome
# refuses to expose a disk-loaded sheet's rules, and the resolver needs them),
# arms a real annotate session against it, and drives the real verbs (begin,
# loader --run, watch, apply, announce) together with the real overlay, which
# the probe operates through genuine mouse and keyboard input. Every claim is
# read back from the page itself or from the session's files, never from the
# output being judged:
#
#   1.  the page holds /changes; announce's /events registry stays empty
#   2.  a SEND carries the page's probe and the pin resolves on receipt
#   3.  two quick SENDs give two changes, a resent SEND gives none
#   4.  a change sent while no watch ran arrives on restart (watch --once)
#   5.  apply's numbers equal the page's own, and survive re-renders
#   6.  a covered element reports covered
#   7.  a container background reports its true height
#   8.  a change below the fold is flagged out of view and the page never scrolls
#   9.  DELETE then SEND undoes a change; CLEAR PINS undoes nothing
#   10. a reload is restored by the loader line alone
#   11. a stale sent pin drops, an unsent pin stays
#   12. announce never reaches the annotate page
#   13. the canonical clear leaves nothing behind
#   14. a pin on an element under a utility-class section (md:flex w-1/2) with no id above it
#       stays attached after comment mode is turned off and after a reload
#   15. a pin saved while a SEND is in flight is not marked sent
#   16. the listener refuses a request without the token (403, readable by the page), and a SEND
#       holding a stale token shows NOT ARMED
#   17. a page file baked by `bake`, opened straight from disk, holds its stream and a SEND returns RETURNED
#   18. a page on a foreign origin (a host-resolver map sends external.test to this machine) takes
#       the pasted stamp and overlay, its SEND reaches the listener and the watch prints
#       EXTERNAL ADDED, and the listener refuses a fetch that names it by that foreign host (403)
#
# scripts/ci/annotate-probe.mjs drives Chrome over its DevTools protocol with
# node's built-in WebSocket (no packages), in real time.
#
# With no Chrome binary (or no usable node) found the run prints a SKIP line and
# exits 0, so a machine without a browser reads as a legible log line. When
# CRAFT_CI_REQUIRE_BROWSER=1 (the blocking CI job sets it) the same conditions
# print a FAIL line and exit 1, so a required check can never pass by skipping.
# CRAFT_CI_CHROME and CRAFT_CI_NODE override discovery entirely (a nonexistent
# value forces the missing-browser path).
#
# Everything the run starts - the page server, Chrome, the listener and the
# watch - is stopped on every exit path, and the fixture root is removed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUN_SH="$ROOT/hooks/scripts/annotate-run.sh"
CHANNEL_PY="$ROOT/hooks/scripts/annotate-channel.py"

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

# unavailable <what was missing> - the one exit for a missing tool: SKIP, or FAIL when required
unavailable() {
  if [ "${CRAFT_CI_REQUIRE_BROWSER:-}" = "1" ]; then
    echo "FAIL: $1"
    exit 1
  fi
  echo "SKIP: $1"
  exit 0
}

if ! CHROME="$(find_chrome)"; then
  if [ -n "${CRAFT_CI_CHROME:-}" ]; then
    unavailable "no Chrome binary found (looked for: \$CRAFT_CI_CHROME=$CRAFT_CI_CHROME)"
  else
    unavailable "no Chrome binary found (looked for: google-chrome, google-chrome-stable, chromium, chromium-browser on PATH; /Applications/Google Chrome.app/Contents/MacOS/Google Chrome)"
  fi
fi
echo "using Chrome: $CHROME"

if [ -n "${CRAFT_CI_NODE:-}" ]; then
  NODE="$CRAFT_CI_NODE"
  [ -x "$NODE" ] || unavailable "no node binary found (looked for: \$CRAFT_CI_NODE=$CRAFT_CI_NODE)"
else
  NODE="$(command -v node || true)"
  [ -n "$NODE" ] || unavailable "no node binary found (looked for: node on PATH)"
fi
# The probe uses node's built-in WebSocket: on by default from node 22, behind
# --experimental-websocket on 20.10 to 21.
NODE_VERSION="$("$NODE" -p 'process.versions.node' 2>/dev/null || echo 0.0.0)"
NODE_MAJOR="${NODE_VERSION%%.*}"
NODE_MINOR="${NODE_VERSION#*.}"; NODE_MINOR="${NODE_MINOR%%.*}"
NODE_FLAGS=()
if [ "$NODE_MAJOR" -ge 22 ] 2>/dev/null; then
  :
elif [ "$NODE_MAJOR" -eq 21 ] 2>/dev/null || { [ "$NODE_MAJOR" -eq 20 ] && [ "$NODE_MINOR" -ge 10 ]; } 2>/dev/null; then
  NODE_FLAGS=(--experimental-websocket)
else
  unavailable "node $NODE_VERSION is too old for the probe (needs 20.10 or later)"
fi
echo "using node: $NODE ($NODE_VERSION)"

# --- The fixture project, in a root that is removed on every exit ------------
TMP="$(mktemp -d)"
SESSION_ID="annotate-check"
# How many asserts the probe makes; the verdict below must report each of 1..ASSERT_COUNT.
ASSERT_COUNT=18
SESSION_DIR="$TMP/.craft/annotations/$SESSION_ID"
# The external-page boundary pointer lives under the user's cache by default; keep this run's inside its root.
export CRAFT_ANNOTATE_BOUNDARY_DIR="$TMP/boundary"
SERVER_PID=""

stop_pid() {
  local pid="${1:-}"
  case "$pid" in ''|*[!0-9]*) return 0 ;; esac
  kill -9 "$pid" 2>/dev/null || true
}

cleanup() {
  # Chrome leads its own process group, so one kill takes its helpers too.
  if [ -f "$TMP/chrome.pid" ]; then
    local chrome_pid
    chrome_pid="$(cat "$TMP/chrome.pid" 2>/dev/null || true)"
    case "$chrome_pid" in
      ''|*[!0-9]*) ;;
      *) kill -9 -- "-$chrome_pid" 2>/dev/null || true; stop_pid "$chrome_pid" ;;
    esac
  fi
  stop_pid "$(cat "$SESSION_DIR/watch.pid" 2>/dev/null || true)"
  bash "$RUN_SH" disarm --root "$TMP" --session "$SESSION_ID" > /dev/null 2>&1 || true
  stop_pid "$(cat "$SESSION_DIR/listener.pid" 2>/dev/null || true)"
  stop_pid "$SERVER_PID"
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

echo "annotate fixture root: $TMP"
mkdir -p "$TMP/site"

cat > "$TMP/site/app.css" <<'CSSEOF'
body { margin: 0; font: 16px/1.4 sans-serif; background: #ffffff; }
#app { padding: 20px; }
.panel { width: 360px; padding: 12px; }
.card { display: flex; gap: 8px; align-items: center; }
.icon { width: 28px; height: 28px; border-radius: 50%; background-color: rgb(120, 120, 200); }
.name { color: rgb(20, 20, 20); font-weight: 600; }
.wrap { position: relative; width: 120px; height: 40px; margin: 30px 0 0 20px; }
.badge { width: 120px; height: 40px; background-color: rgb(240, 200, 50); color: rgb(0, 0, 0); }
.cover { position: absolute; left: 36px; top: 8px; width: 48px; height: 24px; background-color: rgba(0, 0, 0, 0.3); }
.spacer { height: 200vh; }
.below { padding: 20px; color: rgb(10, 10, 10); }
.md\:flex { display: flex; }
.w-1\/2 { width: 50%; }
.lede { margin: 0; padding: 6px; }
CSSEOF

# The app rebuilds #app's children on a timer, as a framework re-render does,
# so a change that only holds until the next render is caught.
cat > "$TMP/site/index.html" <<'HTMLEOF'
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>annotate fixture</title>
<link rel="stylesheet" href="app.css">
</head>
<body>
<div id="app"></div>
<section class="md:flex w-1/2"><p class="lede">utility lede</p></section>
<div class="spacer"></div>
<div class="below">below the fold</div>
<script>
window.__renders = 0;
function render() {
  document.getElementById('app').innerHTML =
    '<div class="panel"><div class="card"><span class="icon"></span><span class="name">Ada Lovelace</span></div></div>' +
    '<div class="wrap"><div class="badge">NEW</div><div class="cover"></div></div>';
  window.__renders++;
}
render();
setInterval(render, 200);
</script>
</body>
</html>
HTMLEOF

read -r -d '' SERVER_PY <<'PYEOF' || true
import functools
import http.server
import sys

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
handler.log_message = lambda *args: None
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
print("PORT %d" % server.server_address[1], flush=True)
server.serve_forever()
PYEOF

python3 -u -c "$SERVER_PY" "$TMP/site" > "$TMP/server.out" 2>&1 < /dev/null &
SERVER_PID=$!
disown "$SERVER_PID" 2>/dev/null || true
SITE_PORT=""
for _ in $(seq 1 50); do
  SITE_PORT="$(grep -m1 '^PORT ' "$TMP/server.out" 2>/dev/null | sed 's/^PORT //' || true)"
  [ -n "$SITE_PORT" ] && break
  sleep 0.1
done
if [ -z "$SITE_PORT" ]; then
  echo "FAIL: the fixture server did not start"
  exit 1
fi

ARM_OUT="$(bash "$RUN_SH" arm --root "$TMP" --session "$SESSION_ID" --owner-pid $$ 2>&1)"
case "$ARM_OUT" in
  "SESSION $SESSION_ID PORT "*) ;;
  *) echo "FAIL: arm did not start a listener: $ARM_OUT"; exit 1 ;;
esac
echo "armed: $ARM_OUT; page at http://127.0.0.1:$SITE_PORT/index.html"

# --- Run the loop in real time and read the verdict back ----------------------
VERDICT="$("$NODE" ${NODE_FLAGS[@]+"${NODE_FLAGS[@]}"} "$SCRIPT_DIR/annotate-probe.mjs" \
  "$CHROME" "$TMP/chrome-profile" "$TMP/chrome.pid" "$RUN_SH" "$CHANNEL_PY" "$TMP" "$SESSION_ID" \
  "http://127.0.0.1:$SITE_PORT/index.html" 2>/dev/null | tail -1)"

if [ -z "$VERDICT" ]; then
  echo "FAIL: the probe printed no verdict"
  exit 1
fi

python3 -I - "$VERDICT" "$ASSERT_COUNT" <<'PYEOF'
import json
import sys

raw = sys.argv[1].strip()
try:
    data = json.loads(raw)
except ValueError as error:
    sys.exit("FAIL: probe verdict is not parseable JSON: %s (%s)" % (raw[:300], error))
failed = False
seen = {}
for item in data.get("asserts", []):
    seen[item["n"]] = item
for n in range(1, int(sys.argv[2]) + 1):
    item = seen.get(n)
    if item is None:
        print("assert %d FAIL: not reached (%s)" % (n, data.get("error") or "no verdict for it"))
        failed = True
    elif item["ok"]:
        print("assert %d OK: %s" % (n, item["text"]))
    else:
        print("assert %d FAIL: %s (%s)" % (n, item["text"], item.get("detail", "")))
        failed = True
print("DIAG chromeStart: %s" % json.dumps(data.get("chromeStart")))
if data.get("error"):
    print("probe error: %s" % data["error"])
    failed = True
if failed:
    sys.exit(1)
print("annotate check passed: the loop holds in a real browser")
PYEOF
exit $?
