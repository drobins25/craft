#!/usr/bin/env bash
# dashboard-run.sh - the single entry seam for the dashboard graph builder.
# Everything reaches the builder only through this wrapper. It probes its
# preconditions and, on any failure, records a degraded build status and
# exits 0 so the dashboard never blocks a craft flow. Stale-but-valid beats
# absent: no degrade path ever touches graph.js or the record mirrors.

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER="$SELF_DIR/build.py"

ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
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

STATUS_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown')"

# Probed once, before any mkdir in this file: whether the output folder
# already existed at entry. The .gitignore seed below is scoped to the run
# that CREATES the folder, so a user who deletes the seeded file has opted
# the folder back into commits permanently - it is never recreated.
GRAPH_DIR="$ROOT/.craft/graph"
GRAPH_DIR_EXISTED=0
if [ -n "$ROOT" ] && [ -d "$GRAPH_DIR" ]; then
  GRAPH_DIR_EXISTED=1
fi

# Creates the output folder and, only when this run is its creator, seeds a
# one-line .gitignore ('*') so the timestamp-churning build-status.js never
# dirties a project that commits .craft/. The seed write can never fail the
# caller.
ensure_graph_dir() {
  mkdir -p "$GRAPH_DIR" 2>/dev/null || return 1
  if [ "$GRAPH_DIR_EXISTED" = "0" ] && [ ! -f "$GRAPH_DIR/.gitignore" ]; then
    printf '*\n' > "$GRAPH_DIR/.gitignore" 2>/dev/null || true
  fi
  return 0
}

# Pure bash on purpose: the staleness note must be reachable on a machine
# with no python3 at all. Never creates .craft/ - only graph/ inside an
# existing .craft/ - and degrades quietly when it cannot write.
write_status() {
  status="$1"
  reason="$2"
  [ -n "$ROOT" ] && [ -d "$ROOT/.craft" ] || return 0
  ensure_graph_dir || return 0
  printf 'window.CRAFT_BUILD = {"status":"%s","reason":"%s","at":"%s"};\n' \
    "$status" "$reason" "$STATUS_AT" \
    > "$ROOT/.craft/graph/build-status.js" 2>/dev/null || true
}

degrade() {
  write_status "degraded" "$1"
  printf '{"status":"degraded","reason":"%s"}\n' "$1"
  exit 0
}

[ -n "$ROOT" ] && [ -d "$ROOT" ] || degrade "root-missing"
[ -d "$ROOT/.craft" ] || degrade "craft-missing"
command -v python3 >/dev/null 2>&1 || degrade "python-missing"
[ -f "$BUILDER" ] || degrade "builder-missing"

# Single-flight: two transition scripts firing close together must never
# interleave into a graph/mirrors pair that was not one coherent build.
# Advisory mkdir lock; a stale lock from a dead holder is broken after a
# bounded age.
LOCK_DIR="$ROOT/.craft/graph/.build-lock"
ensure_graph_dir || degrade "craft-missing"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
    rm -rf "$LOCK_DIR" 2>/dev/null
    mkdir "$LOCK_DIR" 2>/dev/null || degrade "build-skipped-concurrent"
  else
    degrade "build-skipped-concurrent"
  fi
fi
trap 'rm -rf "$LOCK_DIR" 2>/dev/null' EXIT

out="$(python3 "$BUILDER" --root "$ROOT" 2>/dev/null)"
RC=$?

if [ "$RC" -ne 0 ]; then
  degrade "builder-error"
fi

write_status "ok" "ok"
printf '%s\n' "$out"
exit 0
