#!/bin/bash
# story-rules.sh - Print the extra rules a story's source brings, for one reader.
#
# Usage: story-rules.sh <story-file> <planner|builder>
#
# The planner and the builder each run this before they start. A story with no
# special source prints nothing, so the common path costs one call and no
# words. A story whose frontmatter names a mockup prints the facts checked
# about it, then that reader's part of
# commands/references/mockup-story-rules.md.
#
# Silence must only ever mean "nothing applies". Every failure prints a line
# starting "STORY RULES UNAVAILABLE" and exits 1, because a reader cannot tell
# an empty answer from a broken one.

STORY="${1:-}"
ROLE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES="$SCRIPT_DIR/../../commands/references/mockup-story-rules.md"

unavailable() {
  echo "STORY RULES UNAVAILABLE: $1"
  exit 1
}

case "$ROLE" in
  planner|builder) ;;
  *) unavailable "the reader must be planner or builder, got '${ROLE}'" ;;
esac
[ -n "$STORY" ] || unavailable "no story file given"
[ -f "$STORY" ] && [ -r "$STORY" ] || unavailable "cannot read the story file $STORY"

# Frontmatter is the block between the first two --- lines.
FRONT=$(awk '
  NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
  /^---[[:space:]]*$/ { exit }
  { print }
' "$STORY")

# The mockup field holds a record name, a path to the record folder, or
# nothing. Quotes, list brackets and a trailing comment are not part of it.
MOCKUP_RAW=$(printf '%s\n' "$FRONT" | sed -n 's/^mockup:[[:space:]]*//p' | head -1 \
  | sed 's/[[:space:]]#.*$//' | tr -d '\r"[]' | tr -d "'" | sed 's/[[:space:]]*$//')
[ -n "$MOCKUP_RAW" ] || exit 0

# The project root is the story path up to /.craft/, the same rule the planner uses.
STORY_DIR="$(cd "$(dirname "$STORY")" 2>/dev/null && pwd)"
STORY_ABS="$STORY_DIR/$(basename "$STORY")"
case "$STORY_ABS" in
  */.craft/*) ROOT="${STORY_ABS%%/.craft/*}" ;;
  *) unavailable "the story names a mockup but is not under a .craft folder, so the mockup cannot be found: $STORY_ABS" ;;
esac

PART=""
if [ -r "$RULES" ]; then
  PART=$(awk -v want="## $ROLE" '
    $0 == want { on = 1; next }
    /^## / { on = 0 }
    on { print }
  ' "$RULES" | sed '/./,$!d')
fi
[ -n "$PART" ] || unavailable "this story names a mockup ($MOCKUP_RAW) but the $ROLE rules could not be read from $RULES"

# One line per mockup the field names.
FOUND=""
MISSING=""
for entry in $(printf '%s' "$MOCKUP_RAW" | tr ',' ' '); do
  name="${entry%/}"
  name="${name%/mockup.html}"
  name="${name##*mockups/}"
  [ -n "$name" ] || continue
  file="$ROOT/.craft/mockups/$name/mockup.html"
  if [ -f "$file" ]; then
    FOUND="${FOUND}- mockup file: $file
"
  else
    MISSING="${MISSING}- MOCKUP FILE MISSING: $file
"
  fi
done

# A mockup that cannot be read leaves nothing to carry over, so the rules are
# held back and the reader is told what to do instead.
if [ -n "$MISSING" ]; then
  echo "This story was built from a mockup, and the approved look cannot be read:"
  printf '%s' "$MISSING"
  if [ "$ROLE" = "planner" ]; then
    echo "List this as a Critical Blocker. Never plan the look from the story's description."
  else
    echo "Stop and report this under Not done. Never rebuild the look from the story's description."
  fi
  exit 0
fi

echo "This story was built from a mockup. Follow the rules below. Facts checked first:"
printf '%s' "$FOUND"

# The binding table: a table whose first column is Part or Element, anywhere
# above the plan. Only the planner binds rows, so only the planner is told.
[ "$ROLE" = "planner" ] && COUNTS=$(awk '
  /^## Chunks/ { exit }
  /^\|[[:space:]]*(Part|Element)[[:space:]]*\|/ { in_table = 1; sep = 1; next }
  in_table && sep && /^\|[-:|[:space:]]+\|[[:space:]]*$/ { sep = 0; next }
  in_table && /^\|/ {
    rows++
    if ($0 ~ /(^|[^A-Za-z])TBD([^A-Za-z]|$)/) tbd++
    sep = 0
    next
  }
  { in_table = 0; sep = 0 }
  END { printf "%d %d", rows, tbd }
' "$STORY")
if [ "$ROLE" = "planner" ]; then
  ROWS="${COUNTS%% *}"
  TBD="${COUNTS##* }"
  if [ "${ROWS:-0}" -gt 0 ]; then
    echo "- binding table: $ROWS rows, $TBD marked TBD"
  else
    echo "- binding table: none in this story"
  fi
fi

echo ""
printf '%s\n' "$PART"
