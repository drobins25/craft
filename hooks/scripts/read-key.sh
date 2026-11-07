#!/bin/bash
# read-key.sh - The one shell decoder for a flat key in cycle.yaml (or any file
# that keeps one `key: value` per line). Sourced; it defines read_key and runs
# nothing on source.
#
# read_key <file> <key>
#   Prints the value of the first line starting `<key>:`, with surrounding
#   whitespace removed, then decoded:
#     '...'  (length >= 2)  the inside, each '' read as one '
#     "..."  (length >= 2)  the inside, verbatim (no backslash is unescaped)
#     else                  the value verbatim (a plain '' stays '')
#   A missing file or key prints nothing. Always exits 0, so a caller under
#   `set -e` survives.
#
# craft's scripts write ticket-derived values as one-line single-quoted scalars
# with each ' doubled; the double-quoted and plain branches keep older files
# reading correctly.

read_key() {
  local file="$1" key="$2" line value inner q dq
  q="'"
  dq="''"
  [ -f "$file" ] || return 0
  line=$(grep -m1 "^${key}:" "$file" 2>/dev/null) || return 0
  value="${line#"${key}":}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [ "${#value}" -ge 2 ]; then
    case "$value" in
      "$q"*"$q")
        inner="${value#?}"
        inner="${inner%?}"
        inner=${inner//"$dq"/$q}
        printf '%s\n' "$inner"
        return 0
        ;;
      \"*\")
        inner="${value#?}"
        printf '%s\n' "${inner%?}"
        return 0
        ;;
    esac
  fi
  printf '%s\n' "$value"
  return 0
}
