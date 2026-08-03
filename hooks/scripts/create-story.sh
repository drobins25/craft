#!/bin/bash
# Create-story: Create a new story file
# Usage: create-story.sh <story-name> <story-title> [--cycle=<cycle>]

set -e

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname $(dirname $(dirname "$0")))}"
TEMPLATES_DIR="$PLUGIN_ROOT/templates"

# Resolve project root (CRAFT_PROJECT_ROOT set by session-start, or find-workshop.sh fallback)
if [ -n "$CRAFT_PROJECT_ROOT" ]; then
  ROOT="${CRAFT_PROJECT_ROOT%/}"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/find-workshop.sh" 2>/dev/null || true
  ROOT="${PROJECT_ROOT%/}"
fi

if [ -z "$ROOT" ]; then
  echo "Error: Could not resolve project root"
  exit 1
fi

# Parse arguments
STORY_NAME=""
STORY_TITLE=""
CYCLE=""

for arg in "$@"; do
  case $arg in
    --cycle=*)
      CYCLE="${arg#*=}"
      shift
      ;;
    *)
      if [ -z "$STORY_NAME" ]; then
        STORY_NAME="$arg"
      elif [ -z "$STORY_TITLE" ]; then
        STORY_TITLE="$arg"
      fi
      ;;
  esac
done

if [ -z "$STORY_NAME" ]; then
  echo "Error: Story name required"
  echo "Usage: create-story.sh <story-name> <story-title> [--cycle=<cycle>]"
  exit 1
fi

# Get current date
DATE=$(date +%Y-%m-%d)

# Determine destination
if [ -n "$CYCLE" ]; then
  # Find the cycle directory
  cycle_dir=$(find "$ROOT/.craft/cycles" -maxdepth 1 -type d -name "*-$CYCLE" 2>/dev/null | head -1)
  if [ -z "$cycle_dir" ]; then
    echo "Error: Cycle '$CYCLE' not found"
    exit 1
  fi

  # Next number = highest existing filename prefix + 1
  # (a file count breaks after any archived story leaves a gap: count < max, so count+1 collides)
  max=$(ls "$cycle_dir/stories/" 2>/dev/null | grep -o '^[0-9]*' | sed 's/^0*//' | sort -n | tail -1)
  story_num=$(( ${max:-0} + 1 ))
  story_file="$cycle_dir/stories/${story_num}-${STORY_NAME}.md"
  template="$TEMPLATES_DIR/story-full.md"
else
  # Backlog story
  story_file="$ROOT/.craft/backlog/${STORY_NAME}.md"
  template="$TEMPLATES_DIR/story-backlog.md"
fi

# Create story from template
if [ -f "$template" ]; then
  # Escape characters that would break sed substitution or YAML parsing
  # Double quotes in title → escaped so they don't break the template's "{{STORY_TITLE}}"
  # Ampersands → escaped so sed doesn't treat & as backreference
  # Pipe/backslash → escaped for sed safety
  SAFE_TITLE=$(echo "${STORY_TITLE:-$STORY_NAME}" | sed 's/[&\\/]/\\&/g; s/"/\\"/g')
  sed "s|{{STORY_NAME}}|$STORY_NAME|g; s|{{STORY_TITLE}}|$SAFE_TITLE|g; s|{{DATE}}|$DATE|g; s|{{CYCLE_NAME}}|${CYCLE:-}|g; s|{{PROJECT_NAME}}||g; s|{{STORY_DESCRIPTION}}|TBD|g; s|{{CRITERION_1}}|TBD|g; s|{{CRITERION_2}}|TBD|g; s|{{CRITERION_3}}|TBD|g" \
    "$template" > "$story_file"
fi

echo "$story_file"
