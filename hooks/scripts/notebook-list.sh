#!/bin/bash
# notebook-list.sh - Emit structured list of notebook entries
# Usage: notebook-list.sh [type]
#   type: optional - "ideas", "todos", "notes", or empty for all three
#
# Output (stdout): key=value records, one entry per block, separated by blank lines
#   TYPE=idea|todo|note
#   N=<sequence-number-within-group>
#   FILE=<absolute-path>
#   DATE=<YYYY-MM-DD from frontmatter>
#   SLUG=<filename slug, without date prefix and .md>
#   TAGS=<semicolon-separated tags, or empty>
#   PREVIEW=<first non-blank line of body>
#
# Ideas and todos skip entries where status != "open". Notes carry no lifecycle
# status, so the notes group lists every entry (emit_group is called with
# "skip-status" for notes).
# Exit: 0 always (empty output if no entries)

set -e

if [ -n "$CRAFT_PROJECT_ROOT" ]; then
  ROOT="${CRAFT_PROJECT_ROOT%/}"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/find-workshop.sh" 2>/dev/null || true
  ROOT="${PROJECT_ROOT%/}"
fi

# Cold fallback: mirror notebook-capture.sh's anchor (git toplevel, else PWD)
# so a note captured before /craft:init is listable from the same root.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
fi

FILTER="${1:-}"
NOTEBOOK_DIR="$ROOT/.craft/notebook"

if [ ! -d "$NOTEBOOK_DIR" ]; then
  exit 0
fi

emit_group() {
  local type="$1"
  local dir="$2"
  local n=1
  if [ ! -d "$dir" ]; then return 0; fi

  local file
  for file in $(ls "$dir"/*.md 2>/dev/null | sort); do
    [ -e "$file" ] || continue

    local parsed
    parsed=$(python3 - "$file" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

m = re.match(r'^---\n(.*?)\n---\n(.*)$', content, re.DOTALL)
if not m:
    print('STATUS=missing')
    sys.exit(0)
fm, body = m.group(1), m.group(2)

def get(field):
    mm = re.search(r'^' + re.escape(field) + r':\s*(.*)$', fm, re.MULTILINE)
    return mm.group(1).strip() if mm else ''

status = get('status') or 'open'
date = get('created')
tags_raw = get('tags')

tags = ''
if tags_raw:
    mm = re.match(r'\[(.*)\]', tags_raw)
    if mm:
        inner = mm.group(1)
        parts = [p.strip() for p in inner.split(',') if p.strip()]
        tags = ';'.join(parts)

preview = ''
for line in body.splitlines():
    s = line.strip()
    if s:
        preview = s
        break

print(f'STATUS={status}')
print(f'DATE={date}')
print(f'TAGS={tags}')
print(f'PREVIEW={preview}')
PYEOF
)

    local status date tags preview
    status=$(printf '%s\n' "$parsed" | sed -n 's/^STATUS=//p' | head -1)
    date=$(printf '%s\n' "$parsed" | sed -n 's/^DATE=//p' | head -1)
    tags=$(printf '%s\n' "$parsed" | sed -n 's/^TAGS=//p' | head -1)
    preview=$(printf '%s\n' "$parsed" | sed -n 's/^PREVIEW=//p' | head -1)

    if [ "$3" != "skip-status" ] && [ "$status" != "open" ]; then continue; fi

    local base slug
    base=$(basename "$file" .md)
    slug="${base#${date}-}"

    echo "TYPE=$type"
    echo "N=$n"
    echo "FILE=$file"
    echo "DATE=$date"
    echo "SLUG=$slug"
    echo "TAGS=$tags"
    echo "PREVIEW=$preview"
    echo ""
    n=$((n + 1))
  done
}

if [ -z "$FILTER" ] || [ "$FILTER" = "ideas" ]; then
  emit_group "idea" "$NOTEBOOK_DIR/ideas"
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "todos" ]; then
  emit_group "todo" "$NOTEBOOK_DIR/todos"
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "notes" ]; then
  emit_group "note" "$NOTEBOOK_DIR/notes" "skip-status"
fi

exit 0
