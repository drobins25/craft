#!/bin/bash
# dials-list.sh - Emit structured list of dial records
# Usage: dials-list.sh [--surface=<s>] [--kind=<k>]
#   --surface / --kind: optional filters, exact match against the record's
#   frontmatter. They exist so a consumer joining against .craft/tweaks/ on
#   the shared surface+kind vocabulary does not re-implement filtering.
#
# Output (stdout): key=value records, one entry per block, separated by blank lines
#   FILE=<absolute-path>
#   DATE=<YYYY-MM-DD from frontmatter>
#   SLUG=<filename slug, without date prefix and .md>
#   SURFACE=<surface>
#   KIND=<kind>
#   SCOPE=<magnitude|approach>
#   CHOSE=<letter|none>
#   OUTCOME=<nothing|tweak|story|todo>
#   PREVIEW=<first non-blank line of body>
#
# Dial records carry no lifecycle, so there is deliberately NO status filter
# here: every record in the directory lists, always. A session that ended in
# "keep the current value" is data, not an open item.
# Exit: 0 always (empty output if no entries)

set -e

if [ -n "$CRAFT_PROJECT_ROOT" ]; then
  ROOT="${CRAFT_PROJECT_ROOT%/}"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/find-workshop.sh" 2>/dev/null || true
  ROOT="${PROJECT_ROOT%/}"
fi

# Cold fallback: mirror dials-capture.sh's anchor (git toplevel, else PWD)
# so a record captured before /craft:init is listable from the same root.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
fi

SURFACE_FILTER=""
KIND_FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --surface=*) SURFACE_FILTER="${1#*=}"; shift ;;
    --kind=*)    KIND_FILTER="${1#*=}"; shift ;;
    *) shift ;;
  esac
done

DIALS_DIR="$ROOT/.craft/dials"

if [ ! -d "$DIALS_DIR" ]; then
  exit 0
fi

for file in $(ls "$DIALS_DIR"/*.md 2>/dev/null | sort); do
  [ -e "$file" ] || continue

  parsed=$(python3 - "$file" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

m = re.match(r'^---\n(.*?)\n---\n?(.*)$', content, re.DOTALL)
if not m:
    sys.exit(0)
fm, body = m.group(1), m.group(2)

def get(field):
    mm = re.search(r'^' + re.escape(field) + r':\s*(.*)$', fm, re.MULTILINE)
    return mm.group(1).strip() if mm else ''

preview = ''
for line in body.splitlines():
    s = line.strip()
    if s:
        preview = s
        break

print(f"DATE={get('created')}")
print(f"SURFACE={get('surface')}")
print(f"KIND={get('kind')}")
print(f"SCOPE={get('scope')}")
print(f"CHOSE={get('chose')}")
print(f"OUTCOME={get('outcome')}")
print(f"PREVIEW={preview}")
PYEOF
)
  [ -n "$parsed" ] || continue

  date=$(printf '%s\n' "$parsed" | sed -n 's/^DATE=//p' | head -1)
  surface=$(printf '%s\n' "$parsed" | sed -n 's/^SURFACE=//p' | head -1)
  kind=$(printf '%s\n' "$parsed" | sed -n 's/^KIND=//p' | head -1)
  scope=$(printf '%s\n' "$parsed" | sed -n 's/^SCOPE=//p' | head -1)
  chose=$(printf '%s\n' "$parsed" | sed -n 's/^CHOSE=//p' | head -1)
  outcome=$(printf '%s\n' "$parsed" | sed -n 's/^OUTCOME=//p' | head -1)
  preview=$(printf '%s\n' "$parsed" | sed -n 's/^PREVIEW=//p' | head -1)

  if [ -n "$SURFACE_FILTER" ] && [ "$surface" != "$SURFACE_FILTER" ]; then continue; fi
  if [ -n "$KIND_FILTER" ] && [ "$kind" != "$KIND_FILTER" ]; then continue; fi

  base=$(basename "$file" .md)
  slug="${base#${date}-}"

  echo "FILE=$file"
  echo "DATE=$date"
  echo "SLUG=$slug"
  echo "SURFACE=$surface"
  echo "KIND=$kind"
  echo "SCOPE=$scope"
  echo "CHOSE=$chose"
  echo "OUTCOME=$outcome"
  echo "PREVIEW=$preview"
  echo ""
done

exit 0
