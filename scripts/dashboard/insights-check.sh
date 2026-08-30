#!/usr/bin/env bash
# insights-check.sh - freshness verdict for the dashboard's insight sidecar
# (.craft/graph/insights.js). The sidecar is authored, not built: this script
# never writes or validates its content. It answers one question in pure bash:
# has graph.js moved since the sidecar was last stamped? graph.js is
# deliberately timestamp-free and byte-stable, so its sha256 is an exact
# corpus-moved key - the same primitive the page's own delivery receipt uses.
#
#   --check  prints VERDICT=missing|stale|fresh, SIDECAR=<path>, GRAPH_SHA=<sha>
#   --stamp  records the current graph.js sha at .craft/graph/.insights.sha256
#
# Both modes exit 0 on every path, including no project at all - a freshness
# check must never be the thing that blocks a craft flow.

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRESHNESS="$SELF_DIR/../map/map-freshness.sh"

MODE=""
ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--stamp)
      MODE="${1#--}"
      shift
      ;;
    --root)
      ROOT="${2:-}"
      shift 2 || shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ -z "$ROOT" ]; then
  if [ -n "${CRAFT_PROJECT_ROOT:-}" ]; then
    ROOT="$CRAFT_PROJECT_ROOT"
  else
    PROJECT_ROOT=""
    # shellcheck disable=SC1091
    source "$SELF_DIR/../../hooks/scripts/find-workshop.sh" 2>/dev/null || true
    ROOT="${PROJECT_ROOT:-}"
  fi
fi

# A relative --root would leak into SIDECAR and print a path with no meaning
# outside the caller's shell. Resolve to absolute so every consumer of the
# printed paths gets something that works regardless of where it's read from.
case "$ROOT" in
  /*) ;;
  *)
    ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || ROOT=""
    ;;
esac

GRAPH="$ROOT/.craft/graph/graph.js"
SIDECAR="$ROOT/.craft/graph/insights.js"
RECEIPT="$ROOT/.craft/graph/.insights.sha256"

has_project() {
  [ -n "$ROOT" ] && [ -d "$ROOT/.craft" ]
}

do_check() {
  local sha verdict expected
  sha="$(bash "$FRESHNESS" "$GRAPH")"
  if ! has_project || [ "$sha" = "missing" ] || [ ! -f "$SIDECAR" ]; then
    # No project, no graph to mine, or no sidecar yet - nothing to compare.
    verdict="missing"
  else
    expected="$(tr -d '[:space:]' < "$RECEIPT" 2>/dev/null)"
    if [ -z "$expected" ]; then
      # A sidecar with no receipt can't prove its corpus - regenerating is
      # the only honest answer.
      verdict="stale"
    else
      verdict="$(bash "$FRESHNESS" "$GRAPH" "$expected")"
    fi
  fi
  printf 'VERDICT=%s\n' "$verdict"
  printf 'SIDECAR=%s\n' "$SIDECAR"
  printf 'GRAPH_SHA=%s\n' "$sha"
  exit 0
}

do_stamp() {
  local sha
  if ! has_project; then
    printf 'STAMPED=0\n'
    printf 'REASON=no-project\n'
    exit 0
  fi
  sha="$(bash "$FRESHNESS" "$GRAPH")"
  if [ "$sha" = "missing" ]; then
    printf 'STAMPED=0\n'
    printf 'REASON=graph-missing\n'
    exit 0
  fi
  mkdir -p "$ROOT/.craft/graph" 2>/dev/null || { printf 'STAMPED=0\nREASON=write-failed\n'; exit 0; }
  printf '%s\n' "$sha" > "$RECEIPT" 2>/dev/null || { printf 'STAMPED=0\nREASON=write-failed\n'; exit 0; }
  printf 'STAMPED=1\n'
  printf 'GRAPH_SHA=%s\n' "$sha"
  exit 0
}

case "$MODE" in
  check) do_check ;;
  stamp) do_stamp ;;
  *)
    printf 'VERDICT=missing\n'
    printf 'REASON=no-mode\n'
    exit 0
    ;;
esac
