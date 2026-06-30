#!/usr/bin/env bash
# map-run.sh - the single entry seam for the Living Map structural generator.
# Everything else reaches the map only through this wrapper. It probes node and,
# on any failure, emits a floor signal and exits 0 so the map never blocks a task.

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SELF_DIR/runner.js"

floor() {
  printf '{"tier":"floor","reason":"%s"}\n' "$1"
  exit 0
}

command -v node >/dev/null 2>&1 || floor "node-missing"
[ -f "$RUNNER" ] || floor "runner-missing"

if out="$(node "$RUNNER" "$@" 2>/dev/null)"; then
  printf '%s' "$out"
  exit 0
else
  floor "runner-error"
fi
