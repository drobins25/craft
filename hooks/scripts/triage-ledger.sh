#!/bin/bash
# triage-ledger.sh - read/append helper for the leftover triage ledger
#
# The ledger records one decision per leftover file, exactly once. "Never
# re-ask" is enforced by looking entries up HERE, never by conversation
# memory. Entries carry the story that surfaced them.
#
# Known limitations: decided entries accumulate forever - the ledger is
# never pruned. Compaction of decided entries is future work; consumers
# must use list-untriaged (bounded to pending entries) rather than
# enumerating the whole file.
#
# Ledger file: .craft/.triage-ledger - single hidden YAML document:
#   entries:
#     - path: <project-relative path>
#       decision: pending|ignore|claim|leave
#       story: <story name that surfaced it>
#
# decision: pending  = surfaced, awaiting a triage decision (gate blocks push)
# entry absent       = never surfaced yet (surfacing adds it as pending)
#
# All writes are atomic: build .craft/.triage-ledger.tmp, then mv over the
# target. A crash mid-triage leaves the entry pending - the safe direction.
#
# Usage (CLI):
#   triage-ledger.sh lookup <path> [project-root]            print decision or nothing
#   triage-ledger.sh append <path> <decision> <story> [project-root]
#   triage-ledger.sh list-untriaged [project-root]           print pending paths
#
# Also sourceable: exposes ledger_lookup / ledger_append / ledger_list_untriaged.

set -uo pipefail

ledger_file() {
  local root="${1:-$PWD}"
  echo "${root%/}/.craft/.triage-ledger"
}

# ledger_lookup <path> [root] - prints the recorded decision, or nothing
ledger_lookup() {
  local path="$1" root="${2:-$PWD}"
  local f
  f="$(ledger_file "$root")"
  [ -f "$f" ] || return 0
  awk -v p="$path" '
    /^  - path: / { cur = substr($0, 11) }
    /^    decision: / && cur == p { print substr($0, 15); exit }
  ' "$f"
}

# ledger_append <path> <decision> <story> [root] - upsert one entry, atomically.
# A new path is appended; an existing path has its decision overwritten
# (pending -> ignore/claim/leave is the triage transition).
ledger_append() {
  local path="$1" decision="$2" story="$3" root="${4:-$PWD}"
  local f tmp
  f="$(ledger_file "$root")"
  tmp="${f}.tmp"
  mkdir -p "$(dirname "$f")"
  if [ -f "$f" ] && grep -qxF -- "  - path: $path" "$f"; then
    awk -v p="$path" -v d="$decision" '
      /^  - path: / { cur = substr($0, 11) }
      /^    decision: / && cur == p { print "    decision: " d; next }
      { print }
    ' "$f" > "$tmp"
  else
    if [ -f "$f" ]; then
      cp "$f" "$tmp"
    else
      printf 'entries:\n' > "$tmp"
    fi
    printf '  - path: %s\n    decision: %s\n    story: %s\n' "$path" "$decision" "$story" >> "$tmp"
  fi
  mv "$tmp" "$f"
}

# ledger_list_untriaged [root] - prints paths whose decision is pending
ledger_list_untriaged() {
  local root="${1:-$PWD}"
  local f
  f="$(ledger_file "$root")"
  [ -f "$f" ] || return 0
  awk '
    /^  - path: / { cur = substr($0, 11) }
    /^    decision: pending$/ { print cur }
  ' "$f"
}

# CLI dispatch when executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cmd="${1:-}"
  case "$cmd" in
    lookup)
      ledger_lookup "${2:?usage: triage-ledger.sh lookup <path> [root]}" "${3:-$PWD}"
      ;;
    append)
      ledger_append "${2:?path required}" "${3:?decision required}" "${4:?story required}" "${5:-$PWD}"
      ;;
    list-untriaged)
      ledger_list_untriaged "${2:-$PWD}"
      ;;
    *)
      echo "Usage: triage-ledger.sh {lookup <path>|append <path> <decision> <story>|list-untriaged} [project-root]" >&2
      exit 1
      ;;
  esac
fi
