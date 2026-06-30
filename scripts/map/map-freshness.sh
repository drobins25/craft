#!/usr/bin/env bash
# map-freshness.sh - script-computed content-hash freshness. The agent never reads
# the file's bytes for this; it gets only a verdict. mtime is never consulted.
#
#   map-freshness.sh <file>                  -> prints the sha256 of the file bytes
#   map-freshness.sh <file> <expected-sha256> -> prints "fresh" or "stale"

set -u

file="${1:-}"
expected="${2:-}"

if [ -z "$file" ] || [ ! -f "$file" ]; then
  printf 'missing\n'
  exit 0
fi

if command -v sha256sum >/dev/null 2>&1; then
  hash="$(sha256sum "$file" | cut -d' ' -f1)"
else
  hash="$(shasum -a 256 "$file" | cut -d' ' -f1)"
fi

if [ -z "$expected" ]; then
  printf '%s\n' "$hash"
else
  [ "$hash" = "$expected" ] && printf 'fresh\n' || printf 'stale\n'
fi
