#!/bin/bash
# gate-signals.sh - fingerprint the project's stack signals and hold per-signal
# gate-reconcile state.
#
# One action per invocation:
#
#   scan (default)     -> print one "manifest <glob> <count>" line per manifest
#                         glob PRESENT in the project (package.json, *.csproj,
#                         *.sln, composer.json, pyproject.toml, go.mod,
#                         Cargo.toml, Makefile). Counts only, never file paths.
#                         Dependency/build dirs are pruned and the search depth
#                         is capped so nested vendored manifests never drown the
#                         output.
#   lookup <signal>    -> print the recorded reconcile state for the signal
#                         (declined|wired), or nothing; always exit 0.
#   record <signal> <state>
#                      -> write "<signal>: <state> <YYYY-MM-DD>" to
#                         .craft/.gate-signals, exactly one line per signal
#                         (re-record replaces the existing line).
#
# Pure filesystem read/write - this script never executes a toolchain command.
# No set -e: a grep/find with no match returns non-zero, which under set -e
# would abort a command substitution; every read below tolerates empty results.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve the project root (handles monorepo + CRAFT_PROJECT_ROOT); exports
# PROJECT_ROOT with a trailing slash.
source "$SCRIPT_DIR/find-project-root.sh" 2>/dev/null || {
  echo "Error: could not resolve project root" >&2
  exit 1
}

STATE_FILE="${PROJECT_ROOT}.craft/.gate-signals"

MANIFEST_GLOBS=(
  "package.json"
  "*.csproj"
  "*.sln"
  "composer.json"
  "pyproject.toml"
  "go.mod"
  "Cargo.toml"
  "Makefile"
)

# Dirs that hold vendored/generated copies of manifests, never the project's own.
PRUNE_EXPR=( \( -name node_modules -o -name vendor -o -name dist -o -name build -o -name .git -o -name .venv -o -name target \) -prune )

ACTION="${1:-scan}"

case "$ACTION" in
  scan)
    for glob in "${MANIFEST_GLOBS[@]}"; do
      count=$(find "$PROJECT_ROOT" -maxdepth 3 "${PRUNE_EXPR[@]}" -o -name "$glob" -type f -print 2>/dev/null | wc -l | tr -d ' ')
      if [ "$count" -ge 1 ] 2>/dev/null; then
        echo "manifest $glob $count"
      fi
    done
    ;;

  lookup)
    signal="$2"
    if [ -z "$signal" ]; then
      echo "Error: lookup requires a signal argument" >&2
      exit 1
    fi
    if [ -f "$STATE_FILE" ]; then
      # Literal prefix match - signals contain glob characters, so no regex.
      awk -v key="$signal" 'index($0, key ": ") == 1 { print $(NF-1); exit }' "$STATE_FILE"
    fi
    exit 0
    ;;

  record)
    signal="$2"
    state="$3"
    if [ -z "$signal" ] || [ -z "$state" ]; then
      echo "Error: record requires <signal> <state>" >&2
      exit 1
    fi
    mkdir -p "${PROJECT_ROOT}.craft"
    today=$(date +%Y-%m-%d)
    if [ -f "$STATE_FILE" ] && awk -v key="$signal" 'index($0, key ": ") == 1 { found=1 } END { exit !found }' "$STATE_FILE"; then
      tmp=$(mktemp)
      # Rewrite the signal's line in place; drop any later duplicates so exactly
      # one line per signal survives.
      awk -v key="$signal" -v line="$signal: $state $today" '
        index($0, key ": ") == 1 { if (seen) next; print line; seen=1; next }
        { print }
      ' "$STATE_FILE" > "$tmp"
      mv "$tmp" "$STATE_FILE"
    else
      echo "$signal: $state $today" >> "$STATE_FILE"
    fi
    ;;

  *)
    echo "Error: unknown action '$ACTION' (expected scan|lookup|record)" >&2
    exit 1
    ;;
esac
