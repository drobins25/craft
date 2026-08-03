#!/bin/bash
# Move-story: Move a story between backlog and cycle
# Usage: move-story.sh <story-file> <destination> [project-root]
# destination: "backlog" or cycle name like "auth" or "1-auth"
#
# Updates story frontmatter only. No cycle.yaml manipulation.
# Stories are discovered by directory scan, not stored in cycle.yaml.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STORY_FILE="$1"
DESTINATION="$2"

if [ -z "$STORY_FILE" ] || [ -z "$DESTINATION" ]; then
  echo "Error: Story file and destination required"
  echo "Usage: move-story.sh <story-file> <destination>"
  exit 1
fi

# Convert relative paths to absolute — walk up to find actual file
if [[ "$STORY_FILE" != /* ]]; then
  _dir="$PWD"
  _found=""
  while [ "$_dir" != "/" ]; do
    if [ -f "$_dir/$STORY_FILE" ]; then
      _found="$_dir/"
      break
    fi
    _dir=$(dirname "$_dir")
  done
  STORY_FILE="${_found:-$PWD/}${STORY_FILE}"
fi

if [ ! -f "$STORY_FILE" ]; then
  echo "Error: Story file not found: $STORY_FILE"
  exit 1
fi

# Derive project root from story file path
# Story file is in .craft/backlog/ or .craft/cycles/*/stories/
PROJECT_ROOT=$(echo "$STORY_FILE" | sed 's|/.craft/.*||')
if [ -d "${PROJECT_ROOT}/.craft" ]; then
  PROJECT_ROOT="${PROJECT_ROOT}/"
else
  # Fallback: assume current directory
  PROJECT_ROOT=""
fi

# Get story name from filename — strip ONLY the numeric prefix (e.g., "1-" or "10a-")
# The old regex [0-9]*[a-z]*- was too greedy: it ate "login-" from "login-form"
# because [a-z]* matched "login" then - matched "-". Now we only strip digits
# optionally followed by a single letter, then a hyphen.
story_name=$(basename "$STORY_FILE" .md | sed 's/^[0-9][0-9]*[a-z]\{0,1\}-//')
DATE=$(date +%Y-%m-%d)

if [ "$DESTINATION" = "backlog" ]; then
  # === MOVE TO BACKLOG ===

  new_file="${PROJECT_ROOT}.craft/backlog/${story_name}.md"

  # Remove cycle and story_number fields from frontmatter
  sed -i.bak '/^cycle:/d' "$STORY_FILE"
  sed -i.bak '/^story_number:/d' "$STORY_FILE"
  sed -i.bak "s/^updated:.*/updated: $DATE/" "$STORY_FILE"
  rm -f "$STORY_FILE.bak"

  # Move file
  mv "$STORY_FILE" "$new_file"

  # Set status to backlog
  "$SCRIPT_DIR/update-story-status.sh" "$new_file" backlog

  echo "$new_file"

else
  # === MOVE TO CYCLE ===

  cycle_dir=$(find "${PROJECT_ROOT}.craft/cycles" -maxdepth 1 -type d -name "*$DESTINATION*" 2>/dev/null | head -1)

  if [ -z "$cycle_dir" ] || [ ! -d "$cycle_dir" ]; then
    echo "Error: Cycle not found: $DESTINATION"
    exit 1
  fi

  # Ensure stories directory exists
  mkdir -p "$cycle_dir/stories"

  # Next number = highest existing filename prefix + 1
  # (a file count breaks after any archived story leaves a gap: count < max, so count+1 collides)
  max=$(ls "$cycle_dir/stories/" 2>/dev/null | grep -o '^[0-9]*' | sed 's/^0*//' | sort -n | tail -1)
  story_num=$(( ${max:-0} + 1 ))
  new_file="$cycle_dir/stories/${story_num}-${story_name}.md"

  # Get cycle name from directory
  cycle_name=$(basename "$cycle_dir" | sed 's/^[0-9]*-//')

  # Insert cycle field — use closing --- as reliable anchor if status: not found
  if ! grep -q "^cycle:" "$STORY_FILE"; then
    if grep -q "^status:" "$STORY_FILE"; then
      awk -v val="$cycle_name" '/^status:/{print; print "cycle: " val; next}1' "$STORY_FILE" > "$STORY_FILE.tmp" && mv "$STORY_FILE.tmp" "$STORY_FILE"
    else
      # Fallback: insert before closing --- of frontmatter
      awk -v val="$cycle_name" 'NR>1 && /^---$/{print "cycle: " val} {print}' "$STORY_FILE" > "$STORY_FILE.tmp" && mv "$STORY_FILE.tmp" "$STORY_FILE"
    fi
  else
    sed -i.bak "s/^cycle:.*/cycle: $cycle_name/" "$STORY_FILE"
    rm -f "$STORY_FILE.bak"
  fi

  # Insert story_number field — use closing --- as reliable anchor if cycle: not found
  if ! grep -q "^story_number:" "$STORY_FILE"; then
    if grep -q "^cycle:" "$STORY_FILE"; then
      awk -v val="$story_num" '/^cycle:/{print; print "story_number: " val; next}1' "$STORY_FILE" > "$STORY_FILE.tmp" && mv "$STORY_FILE.tmp" "$STORY_FILE"
    else
      # Fallback: insert before closing --- of frontmatter
      awk -v val="$story_num" 'NR>1 && /^---$/{print "story_number: " val} {print}' "$STORY_FILE" > "$STORY_FILE.tmp" && mv "$STORY_FILE.tmp" "$STORY_FILE"
    fi
  else
    sed -i.bak "s/^story_number:.*/story_number: $story_num/" "$STORY_FILE"
    rm -f "$STORY_FILE.bak"
  fi

  # Update status and date BEFORE moving — ensures status is correct regardless of post-move script
  sed -i.bak "s/^status:.*/status: planning/" "$STORY_FILE"
  sed -i.bak "s/^updated:.*/updated: $DATE/" "$STORY_FILE"
  rm -f "$STORY_FILE.bak"

  # Post-insertion validation — verify fields exist before moving
  if ! grep -q "^cycle:" "$STORY_FILE"; then
    echo "Error: Failed to insert cycle field into $STORY_FILE"
    exit 1
  fi
  if ! grep -q "^story_number:" "$STORY_FILE"; then
    echo "Error: Failed to insert story_number field into $STORY_FILE"
    exit 1
  fi

  # Move file
  mv "$STORY_FILE" "$new_file"

  # Set status to planning (needs plan-chunks before ready)
  "$SCRIPT_DIR/update-story-status.sh" "$new_file" planning

  echo "$new_file"
fi
