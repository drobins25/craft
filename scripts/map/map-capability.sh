#!/usr/bin/env bash
# map-capability.sh - probe the map's capability ONCE and cache the verdict. The
# cache file is the single source the status surface reads; this never re-probes
# per file. Honors the opt-out flag: map.enabled: false in .craft/settings.yaml
# (absent key defaults to enabled). Always exits 0 - the map never blocks.

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$PWD}"
CACHE="$ROOT/.craft/map/capability.json"
SETTINGS="$ROOT/.craft/settings.yaml"

# Cached verdict wins - probe once, remember once.
if [ -f "$CACHE" ]; then
  cat "$CACHE"
  exit 0
fi

mkdir -p "$ROOT/.craft/map"

# Opt-out: a `map:` block whose `enabled:` is false disables the map. Absent = on.
disabled=0
if [ -f "$SETTINGS" ] && awk '
  /^map:/ {inmap=1; next}
  /^[^[:space:]]/ {inmap=0}
  inmap && /enabled:[[:space:]]*false/ {found=1}
  END {exit found?0:1}
' "$SETTINGS"; then
  disabled=1
fi

if [ "$disabled" = "1" ]; then
  printf '{"mode":"disabled"}\n' | tee "$CACHE"
  exit 0
fi

verdict="$(bash "$SELF_DIR/map-run.sh" probe 2>/dev/null)"
[ -z "$verdict" ] && verdict='{"mode":"floor","reason":"probe-empty"}'
printf '%s\n' "$verdict" | tee "$CACHE"
exit 0
