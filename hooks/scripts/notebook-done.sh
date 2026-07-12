#!/bin/bash
# notebook-done.sh — Mark a todo done: move to todos/done/ + update frontmatter
# Usage: notebook-done.sh <todo-file> [graduated-to-ref]
#   <todo-file>: absolute or project-relative path to the todo .md file
#   [graduated-to-ref]: optional artifact the todo graduated into (story slug,
#                       tweak record, fix record). When present, recorded as
#                       graduated_to: <ref> in frontmatter.
#
# Actions:
#   1. Update frontmatter: status: <any> -> done (tolerates hand-edited
#      non-open statuses); insert done_at: YYYY-MM-DD when absent
#   2. When a graduated-to-ref is given, insert graduated_to: <ref> after done_at
#      (or update it in place if already present)
#   3. Move file to .craft/notebook/todos/done/{basename}
#
# Output (stdout): the new file path (in done/)
# Exit: 0 on success, non-zero on error

set -e

TODO_FILE="$1"
REF="${2:-}"

if [ -z "$TODO_FILE" ]; then
  echo "Error: todo file required" >&2
  echo "Usage: notebook-done.sh <todo-file> [graduated-to-ref]" >&2
  exit 1
fi

if [ ! -f "$TODO_FILE" ]; then
  echo "Error: todo file not found: $TODO_FILE" >&2
  exit 1
fi

if ! grep -q "^type: todo$" "$TODO_FILE"; then
  echo "Error: file is not a todo (type: todo not found): $TODO_FILE" >&2
  exit 1
fi

DATE=$(date +%Y-%m-%d)

python3 - "$TODO_FILE" "$DATE" "$REF" <<'PYEOF'
import sys, re
path, date = sys.argv[1], sys.argv[2]
ref = sys.argv[3] if len(sys.argv) > 3 else ''
with open(path, 'r') as f:
    content = f.read()
content = re.sub(r'^status:\s*\S+\s*$', 'status: done', content, count=1, flags=re.MULTILINE)
if not re.search(r'^done_at:', content, flags=re.MULTILINE):
    content = re.sub(
        r'^(status:\s*done)\s*$',
        r'\1\ndone_at: ' + date,
        content, count=1, flags=re.MULTILINE
    )
if ref:
    if re.search(r'^graduated_to:', content, flags=re.MULTILINE):
        content = re.sub(
            r'^graduated_to:.*$',
            'graduated_to: ' + ref,
            content, count=1, flags=re.MULTILINE
        )
    else:
        content = re.sub(
            r'^(done_at:.*)$',
            r'\1\ngraduated_to: ' + ref,
            content, count=1, flags=re.MULTILINE
        )
with open(path, 'w') as f:
    f.write(content)
PYEOF

TODO_DIR=$(dirname "$TODO_FILE")
BASENAME=$(basename "$TODO_FILE")
DONE_DIR="$TODO_DIR/done"
mkdir -p "$DONE_DIR"

DEST="$DONE_DIR/$BASENAME"
mv "$TODO_FILE" "$DEST"

echo "$DEST"
