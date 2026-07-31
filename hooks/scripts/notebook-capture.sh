#!/bin/bash
# notebook-capture.sh - Write a notebook idea, todo, or note file
# Usage: notebook-capture.sh <type> "<text>" [--facet="<facet>"] [--source="<source>"] [--tags="tag1,tag2"] [--body-paragraph2="<text>"]
#   <type>: "idea", "todo", or "note"
#   <text>: capture text (may contain inline #tags, which are extracted and scrubbed)
#   --facet: optional recall lever for notes (infrastructure|tooling|ownership|process|convention|gotcha)
#   --source: optional source string for frontmatter (e.g. "session 2026-05-30")
#   --tags: optional ADDITIONAL tags (comma-separated) merged with parsed inline tags
#           used by Claude-driven captures to add session-context tags beyond inline #tags
#   --body-paragraph2: optional second-paragraph elaboration appended after blank line
#
# Output (stdout): the full path to the written file
# Exit: 0 on success, non-zero on error

set -e

# Resolve project root (matches pattern from create-story.sh)
if [ -n "$CRAFT_PROJECT_ROOT" ]; then
  ROOT="${CRAFT_PROJECT_ROOT%/}"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/find-workshop.sh" 2>/dev/null || true
  ROOT="${PROJECT_ROOT%/}"
fi

# Cold fallback: no initialized project resolved. Anchor to the git toplevel
# (never a subdirectory), else PWD, so one-line capture works before /craft:init.
# A non-git landing spot is announced - an orphaned capture must be loud, since
# nothing recalls it until the project is initialized.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -z "$ROOT" ]; then
    ROOT="$PWD"
    echo "not a git repo - capturing to $ROOT/.craft/notebook/ (local to this directory)" >&2
  fi
fi

# Parse arguments
TYPE=""
TEXT=""
SOURCE=""
EXTRA_TAGS=""
BODY_PARAGRAPH2=""
FACET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --facet=*)
      FACET="${1#*=}"
      shift
      ;;
    --source=*)
      SOURCE="${1#*=}"
      shift
      ;;
    --tags=*)
      EXTRA_TAGS="${1#*=}"
      shift
      ;;
    --body-paragraph2=*)
      BODY_PARAGRAPH2="${1#*=}"
      shift
      ;;
    *)
      if [ -z "$TYPE" ]; then
        TYPE="$1"
      elif [ -z "$TEXT" ]; then
        TEXT="$1"
      fi
      shift
      ;;
  esac
done

# Validate
if [ "$TYPE" != "idea" ] && [ "$TYPE" != "todo" ] && [ "$TYPE" != "note" ]; then
  echo "Error: type must be 'idea', 'todo', or 'note'" >&2
  exit 1
fi

if [ -z "$TEXT" ]; then
  echo "Error: text is required" >&2
  exit 1
fi

# ── Tag extraction ─────────────────────────────────────────────────
PARSED=$(python3 - "$TEXT" "$EXTRA_TAGS" <<'PYEOF'
import sys, re
text = sys.argv[1]
extra = sys.argv[2] if len(sys.argv) > 2 else ""

# Extract inline #tags
tags = []
seen = set()
for m in re.finditer(r'(?:^|\s)#([a-zA-Z0-9][a-zA-Z0-9-]*)', text):
    t = m.group(1).lower()
    if t not in seen:
        seen.add(t)
        tags.append(t)

# Merge extra tags (comma-separated), normalized
if extra:
    for raw in extra.split(','):
        t = raw.strip().lower()
        if t and re.match(r'^[a-z0-9][a-z0-9-]*$', t) and t not in seen:
            seen.add(t)
            tags.append(t)

# Scrub #tag tokens from text; collapse multiple spaces; strip
scrubbed = re.sub(r'(?:^|\s)#[a-zA-Z0-9][a-zA-Z0-9-]*', ' ', text)
scrubbed = re.sub(r'\s+', ' ', scrubbed).strip()

print(scrubbed)
print(','.join(tags))
PYEOF
)

SCRUBBED_TEXT=$(printf '%s\n' "$PARSED" | sed -n '1p')
TAG_CSV=$(printf '%s\n' "$PARSED" | sed -n '2p')

# Fallback: if scrubbing left nothing, use "untitled"
if [ -z "$SCRUBBED_TEXT" ]; then
  SCRUBBED_TEXT="untitled"
fi

# ── Slug generation ─────────────────────────────────────────────────
DATE=$(date +%Y-%m-%d)
CAPTURED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

RAW_SLUG=$(printf '%s' "$SCRUBBED_TEXT" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g' \
  | sed -E 's/^-//' \
  | sed -E 's/-$//')

# Cap at 50 chars (word-boundary-friendly: cut at last hyphen <=50 if possible)
if [ ${#RAW_SLUG} -gt 50 ]; then
  TRUNC="${RAW_SLUG:0:50}"
  LAST_HYPHEN_TRUNC="${TRUNC%-*}"
  if [ -n "$LAST_HYPHEN_TRUNC" ] && [ "$LAST_HYPHEN_TRUNC" != "$TRUNC" ] && [ ${#LAST_HYPHEN_TRUNC} -ge 20 ]; then
    SLUG="$LAST_HYPHEN_TRUNC"
  else
    SLUG="$TRUNC"
  fi
else
  SLUG="$RAW_SLUG"
fi

if [ -z "$SLUG" ]; then
  SLUG="untitled"
fi

# ── Folder creation (AC8: folders on demand) ─────────────────────────
NOTEBOOK_DIR="$ROOT/.craft/notebook"
if [ "$TYPE" = "idea" ]; then
  TARGET_DIR="$NOTEBOOK_DIR/ideas"
elif [ "$TYPE" = "note" ]; then
  TARGET_DIR="$NOTEBOOK_DIR/notes"
else
  TARGET_DIR="$NOTEBOOK_DIR/todos"
fi
mkdir -p "$TARGET_DIR"

# ── Collision resolution (AC3) ───────────────────────────────────────
FINAL_SLUG="$SLUG"
TARGET_FILE="$TARGET_DIR/${DATE}-${FINAL_SLUG}.md"
COUNTER=2
while [ -e "$TARGET_FILE" ]; do
  FINAL_SLUG="${SLUG}-${COUNTER}"
  TARGET_FILE="$TARGET_DIR/${DATE}-${FINAL_SLUG}.md"
  COUNTER=$((COUNTER + 1))
done

# ── Frontmatter assembly ─────────────────────────────────────────────
if [ -n "$TAG_CSV" ]; then
  TAGS_YAML="tags: [$(printf '%s' "$TAG_CSV" | sed 's/,/, /g')]"
else
  TAGS_YAML=""
fi

if [ -n "$SOURCE" ]; then
  SOURCE_YAML="source: $SOURCE"
else
  SOURCE_YAML=""
fi

# ── Write file ───────────────────────────────────────────────────────
{
  echo "---"
  echo "type: $TYPE"
  echo "created: $DATE"
  echo "captured_at: $CAPTURED_AT"
  if [ "$TYPE" = "note" ]; then
    # Notes carry no lifecycle status (no graduate/done); facet is the recall lever.
    [ -n "$FACET" ] && echo "facet: $FACET"
  else
    echo "status: open"
  fi
  [ -n "$SOURCE_YAML" ] && echo "$SOURCE_YAML"
  [ -n "$TAGS_YAML" ] && echo "$TAGS_YAML"
  echo "---"
  echo "$SCRUBBED_TEXT"
  if [ -n "$BODY_PARAGRAPH2" ]; then
    echo ""
    echo "$BODY_PARAGRAPH2"
  fi
} > "$TARGET_FILE"

echo "$TARGET_FILE"
