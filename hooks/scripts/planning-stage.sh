#!/bin/bash
# Planning-stage: Write, rewrite or clear a story's planning_stage frontmatter field
# Usage: planning-stage.sh <story-file> <stage|clear>
# Stages: content-check, alignment-check, direction, planner, plan-check, triage
#
# Edits that one line in the story's first frontmatter block and nothing else: no
# updated: date, no state files, no dashboard refresh. The progress band in every
# terminal reads this field, so the write is atomic (temp file, then mv).
#
# The last stdout line is parsed by the progress band:
#   Planning stage set to <stage>: <absolute-path>
#   Planning stage cleared: <absolute-path>

set -e

STORY_FILE="$1"
STAGE="$2"
USAGE="Usage: planning-stage.sh <story-file> <stage|clear>"

if [ -z "$STORY_FILE" ] || [ -z "$STAGE" ]; then
  echo "Error: Story file and stage required"
  echo "$USAGE"
  exit 1
fi

case "$STAGE" in
  content-check|alignment-check|direction|planner|plan-check|triage|clear) ;;
  *)
    echo "Error: Invalid stage '$STAGE'"
    echo "Valid stages: content-check, alignment-check, direction, planner, plan-check, triage, clear"
    exit 1
    ;;
esac

# Convert relative paths to absolute using PWD
if [[ "$STORY_FILE" != /* ]]; then
  STORY_FILE="$PWD/$STORY_FILE"
fi

if [ ! -f "$STORY_FILE" ]; then
  echo "Error: Story file not found: $STORY_FILE"
  exit 1
fi

if [ "$(head -n 1 "$STORY_FILE")" != "---" ]; then
  echo "Error: Story file has no frontmatter block: $STORY_FILE"
  exit 1
fi

TMP_FILE="$(mktemp "$(dirname "$STORY_FILE")/.planning-stage.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

# Two passes over the story: the first notes whether the field exists, the second
# rewrites. Both track the first frontmatter block only (line 1 opens it, the next
# --- closes it), so a planning_stage: line or a --- rule in the body is never touched.
# Write: replace an existing line, else insert after status:, else before the closing ---.
awk -v stage="$STAGE" '
  BEGIN { hasfield = 0 }
  NR == FNR {
    if (FNR == 1) { inblock = 1; next }
    if (inblock && /^---[[:space:]]*$/) { inblock = 0; next }
    if (inblock && /^planning_stage:/) hasfield = 1
    next
  }
  FNR == 1 { inblock = 1; print; next }
  inblock && /^---[[:space:]]*$/ {
    if (stage != "clear" && !done) { print "planning_stage: " stage; done = 1 }
    inblock = 0; print; next
  }
  inblock && /^planning_stage:/ {
    if (stage != "clear" && !done) { print "planning_stage: " stage; done = 1 }
    next
  }
  { print }
  inblock && /^status:/ && !hasfield && stage != "clear" && !done { print "planning_stage: " stage; done = 1 }
' "$STORY_FILE" "$STORY_FILE" > "$TMP_FILE"

# A clear on a story without the field must leave its bytes alone
if cmp -s "$TMP_FILE" "$STORY_FILE"; then
  rm -f "$TMP_FILE"
else
  chmod --reference="$STORY_FILE" "$TMP_FILE" 2>/dev/null || chmod "$(stat -c '%a' "$STORY_FILE" 2>/dev/null || stat -f '%Lp' "$STORY_FILE")" "$TMP_FILE"
  mv "$TMP_FILE" "$STORY_FILE"
fi

if [ "$STAGE" = "clear" ]; then
  echo "Planning stage cleared: $STORY_FILE"
else
  echo "Planning stage set to $STAGE: $STORY_FILE"
fi
