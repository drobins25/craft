#!/bin/bash
# bugs-close.sh - Close an open bug: set its status, stamp the Log, move it to closed/
# Usage: bugs-close.sh <path|dated-slug|fragment> --status=fixed|wont-fix
#          [--verdict=bug|unspecified|spec-gap|not-reproducible]
#          [--fixed-by=<ref>] [--note="<text>"]
#
# Only the text between the --- fences changes in the frontmatter: status,
# closed_at, and verdict / fixed_by when given. With no --verdict the verdict
# line is left exactly as it was. A body line that merely looks like
# frontmatter (`status: ...` in prose) is never touched. One line is appended
# to `## Log` (the section is created when the record has none).
#
# The move is destination-first: the finished file is written in closed/
# before the source is removed, so an interruption never loses a record.
# The target is resolved in the open room only; a trailing fragment that
# matches two or more open records is refused, never guessed. A path or a full
# dated name that matches no open record is refused, never read as a fragment.
#
# Output (stdout): TITLE=<symptom line>, then the closed absolute path
# Exit: 0 on success, 2 on any refusal (nothing written)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "$CRAFT_PROJECT_ROOT" ]; then
  ROOT="${CRAFT_PROJECT_ROOT%/}"
else
  source "$SCRIPT_DIR/find-workshop.sh" >/dev/null 2>&1 || true
  craft_before_init_root >/dev/null
  ROOT="$CRAFT_BEFORE_INIT_ROOT"
fi

OPEN_DIR="$ROOT/.craft/bugs"
CLOSED_DIR="$OPEN_DIR/closed"

TARGET=""
STATUS=""
VERDICT=""
HAVE_VERDICT=0
FIXED_BY=""
NOTE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --status=*) STATUS="${1#*=}" ;;
    --verdict=*) VERDICT="${1#*=}"; HAVE_VERDICT=1 ;;
    --fixed-by=*) FIXED_BY="${1#*=}" ;;
    --note=*) NOTE="${1#*=}" ;;
    --*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) [ -z "$TARGET" ] && TARGET="$1" ;;
  esac
  shift
done

if [ -z "$TARGET" ]; then
  echo "missing target: a path, a dated slug, or a slug fragment" >&2
  exit 2
fi
if [ -z "$STATUS" ]; then
  echo "missing --status" >&2
  exit 2
fi
case "$STATUS" in
  fixed|wont-fix) ;;
  *) echo "invalid --status: $STATUS" >&2; exit 2 ;;
esac
if [ "$HAVE_VERDICT" -eq 1 ]; then
  case "$VERDICT" in
    bug|unspecified|spec-gap|not-reproducible) ;;
    *) echo "invalid --verdict: $VERDICT" >&2; exit 2 ;;
  esac
fi

# ── Resolve the target ────────────────────────────────────────────────
DATED_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\.md$'
NAME="$(basename "$TARGET")"
NAME="${NAME%.md}"
SRC=""
# An empty name would match every dated record in the fragment loop below.
if [ -z "$NAME" ]; then
  echo "missing target: a path, a dated slug, or a slug fragment" >&2
  exit 2
fi

if [ -f "$TARGET" ]; then
  # A symlink is never a record: -f follows links, so refuse it before any move.
  if [ -L "$TARGET" ]; then
    echo "not a bug record: $NAME" >&2
    exit 2
  fi
  TARGET_DIR="$(cd "$(dirname "$TARGET")" && pwd -P)"
  if [ "$TARGET_DIR" = "$(cd "$CLOSED_DIR" 2>/dev/null && pwd -P)" ]; then
    echo "already closed: $NAME" >&2
    exit 2
  fi
  if [ "$TARGET_DIR" = "$(cd "$OPEN_DIR" 2>/dev/null && pwd -P)" ]; then
    SRC="$OPEN_DIR/$NAME.md"
  fi
fi

# A path or a full dated name (<YYYY-MM-DD>-<slug>) names one record exactly:
# when no open record has that name it is refused, never matched as a fragment.
# Only a short undated name is a fragment.
EXACT=0
case "$TARGET" in */*) EXACT=1 ;; esac
[[ "$NAME.md" =~ $DATED_RE ]] && EXACT=1

if [ -z "$SRC" ]; then
  if [ -f "$OPEN_DIR/$NAME.md" ]; then
    SRC="$OPEN_DIR/$NAME.md"
  elif [ "$EXACT" -eq 0 ]; then
    MATCHES=()
    for f in "$OPEN_DIR"/*.md; do
      [ -f "$f" ] || continue
      b="$(basename "$f")"
      [[ "$b" =~ $DATED_RE ]] || continue
      case "$b" in *"$NAME"*) MATCHES+=("${b%.md}") ;; esac
    done
    if [ "${#MATCHES[@]}" -gt 1 ]; then
      LIST=""
      for m in "${MATCHES[@]}"; do LIST="${LIST:+$LIST, }$m"; done
      echo "ambiguous: $LIST" >&2
      exit 2
    elif [ "${#MATCHES[@]}" -eq 1 ]; then
      SRC="$OPEN_DIR/${MATCHES[0]}.md"
    fi
  fi
fi

if [ -z "$SRC" ]; then
  for f in "$CLOSED_DIR"/*.md; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    [[ "$b" =~ $DATED_RE ]] || continue
    if [ "$EXACT" -eq 1 ]; then
      [ "$b" = "$NAME.md" ] && { echo "already closed: $NAME" >&2; exit 2; }
    else
      case "$b" in *"$NAME"*) echo "already closed: ${b%.md}" >&2; exit 2 ;; esac
    fi
  done
  echo "not found: $NAME" >&2
  exit 2
fi

SLUG="$(basename "$SRC" .md)"
# Same record rule as bugs-list.sh, on every route: a dated basename here, and a
# fenced `type: bug` checked in the python below. README.md and _TEMPLATE.md fail it.
if ! [[ "$SLUG.md" =~ $DATED_RE ]]; then
  echo "not a bug record: $SLUG" >&2
  exit 2
fi
DEST="$CLOSED_DIR/$SLUG.md"
if [ -e "$DEST" ]; then
  echo "already in closed/: $SLUG" >&2
  exit 2
fi

# ── Build the finished file (fence-scoped frontmatter edit, Log line) ──
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
TODAY=$(date +%Y-%m-%d)

python3 - "$SRC" "$WORK_DIR/closed.md" "$WORK_DIR/title.txt" "$STATUS" \
  "$HAVE_VERDICT" "$VERDICT" "$FIXED_BY" "$NOTE" "$TODAY" "$SLUG" <<'PYEOF'
import re
import sys

(src, out, title_path, status, have_verdict, verdict, fixed_by, note,
 today, slug) = sys.argv[1:11]

# newline='' keeps every byte we do not edit exactly as it was
with open(src, encoding='utf-8', errors='surrogateescape', newline='') as f:
    content = f.read()

m = re.match(r'^(---\n)(.*?)(\n---\n?)(.*)$', content, re.DOTALL)
if not m:
    sys.stderr.write('not a bug record: ' + slug + '\n')
    sys.exit(2)
head, fm, fence_tail, body = m.groups()
if not re.search(r'^type:[ \t]*bug[ \t]*$', fm, re.MULTILINE):
    sys.stderr.write('not a bug record: ' + slug + '\n')
    sys.exit(2)


def one_line(text):
    return re.sub(r'\s+', ' ', text).strip()


def set_key(fm, key, value):
    value = one_line(value)
    line = key + ':' + (' ' + value if value else '')
    pattern = r'^' + re.escape(key) + r':.*$'
    if re.search(pattern, fm, re.MULTILINE):
        return re.sub(pattern, lambda mm: line, fm, count=1, flags=re.MULTILINE)
    return fm + '\n' + line


fm = set_key(fm, 'status', status)
if have_verdict == '1':
    fm = set_key(fm, 'verdict', verdict)
if fixed_by:
    fm = set_key(fm, 'fixed_by', fixed_by)
fm = set_key(fm, 'closed_at', today)

entry = '- ' + today + ' closed: ' + status
if have_verdict == '1':
    entry += ', verdict ' + verdict
if fixed_by:
    entry += ', fixed by ' + one_line(fixed_by)
if note:
    entry += ' - ' + one_line(note)


def add_log(text, entry):
    """Append entry as the last line of '## Log'; else create the section
    before '## Notes' if present, else at the end."""
    ls = text.split('\n')
    log = next((i for i, l in enumerate(ls) if re.match(r'^## Log[ \t]*$', l)), None)
    if log is not None:
        end = next((j for j in range(log + 1, len(ls)) if ls[j].startswith('## ')), len(ls))
        k = end
        while k > log + 1 and not ls[k - 1].strip():
            k -= 1
        ls.insert(k, entry)
        return '\n'.join(ls)
    notes = next((i for i, l in enumerate(ls) if re.match(r'^## Notes[ \t]*$', l)), None)
    if notes is not None:
        before = ls[:notes]
        while before and not before[-1].strip():
            before.pop()
        return '\n'.join(before + ['', '## Log', '', entry, ''] + ls[notes:])
    return text.rstrip('\n') + '\n\n## Log\n\n' + entry + '\n'


body = add_log(body, entry)
if not body.endswith('\n'):
    body += '\n'

title = next((l.strip() for l in body.split('\n') if l.strip()), '')
with open(title_path, 'w', encoding='utf-8', errors='surrogateescape') as f:
    f.write(title)
with open(out, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
    f.write(head + fm + fence_tail + body)
PYEOF
RC=$?
if [ "$RC" -ne 0 ]; then
  exit "$RC"
fi

# ── Destination first, then remove the source ─────────────────────────
mkdir -p "$CLOSED_DIR"
cat "$WORK_DIR/closed.md" > "$DEST.tmp" && mv "$DEST.tmp" "$DEST"
if [ ! -f "$DEST" ]; then
  rm -f "$DEST.tmp"
  echo "could not write closed/$SLUG.md" >&2
  exit 1
fi
if ! rm "$SRC"; then
  echo "closed copy written but could not remove source: $SRC" >&2
  exit 1
fi

bash "$SCRIPT_DIR/../../scripts/dashboard/dashboard-run.sh" --root "$ROOT" >/dev/null 2>&1 || true

echo "TITLE=$(cat "$WORK_DIR/title.txt")"
echo "$DEST"
