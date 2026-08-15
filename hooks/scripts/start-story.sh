#!/bin/bash
# start-story.sh — Transition: Begin implementing a story
# Usage: start-story.sh <story-file>
#
# Updates:
# - Global: CURRENT_STORY set
# - Cycle: CURRENT_STORY, CURRENT_CHUNK=1, TOTAL_CHUNKS from story
# - Story: status = active

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STORY_FILE="$1"

if [ -z "$STORY_FILE" ]; then
  echo "Usage: start-story.sh <story-file>"
  echo "       start-story.sh .craft/cycles/1-auth/stories/1-login-form.md"
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
PROJECT_ROOT=$(echo "$STORY_FILE" | sed 's|/.craft/.*||')
if [ -d "${PROJECT_ROOT}/.craft" ]; then
  PROJECT_ROOT="${PROJECT_ROOT}/"
else
  PROJECT_ROOT=""
fi

# Get story name from filename
STORY_NAME=$(basename "$STORY_FILE" .md)

# Get cycle from story path or frontmatter
CYCLE_DIR=$(dirname "$(dirname "$STORY_FILE")")
if [ ! -d "$CYCLE_DIR" ] || [ "$(basename "$CYCLE_DIR")" = "backlog" ]; then
  # Story might be in backlog, check frontmatter
  cycle_name=$(grep "^cycle:" "$STORY_FILE" 2>/dev/null | sed 's/cycle: *//' | tr -d '\r')
  if [ -n "$cycle_name" ]; then
    CYCLE_DIR=$(find "${PROJECT_ROOT}.craft/cycles" -maxdepth 1 -type d -name "*${cycle_name}*" 2>/dev/null | head -1)
  fi
fi

if [ -z "$CYCLE_DIR" ] || [ ! -d "$CYCLE_DIR" ]; then
  echo "Error: Story must be in a cycle to start implementation"
  exit 1
fi

# Get chunks_total from story frontmatter
TOTAL_CHUNKS=$(grep "^chunks_total:" "$STORY_FILE" 2>/dev/null | sed 's/chunks_total: *//' | tr -d '\r')
TOTAL_CHUNKS="${TOTAL_CHUNKS:-0}"

# Validate required frontmatter fields before starting
# Stories in cycles must have cycle:, story_number:, and current_chunk:
MISSING=""
if ! grep -q "^cycle:" "$STORY_FILE"; then
  MISSING="${MISSING} cycle:"
fi
if ! grep -q "^story_number:" "$STORY_FILE"; then
  MISSING="${MISSING} story_number:"
fi
if ! grep -q "^current_chunk:" "$STORY_FILE"; then
  MISSING="${MISSING} current_chunk:"
fi
if [ -n "$MISSING" ]; then
  echo "Error: Story is missing required frontmatter fields:$MISSING"
  echo "  File: $STORY_FILE"
  echo "  This usually means move-story.sh failed to insert fields."
  echo "  Fix the story file manually or re-run move-story.sh."
  exit 1
fi

# Update story status to active
"$SCRIPT_DIR/update-story-status.sh" "$STORY_FILE" active

# Update global state
"$SCRIPT_DIR/update-global-state.sh" CURRENT_STORY "$STORY_NAME" "$PROJECT_ROOT"
"$SCRIPT_DIR/update-global-state.sh" LAST_ACTIVITY "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_ROOT"
"$SCRIPT_DIR/update-global-state.sh" CRAFT_WRITE_ENABLED "true" "$PROJECT_ROOT"

# Update cycle state
"$SCRIPT_DIR/update-cycle-state.sh" "$CYCLE_DIR" CURRENT_STORY "$STORY_NAME"
"$SCRIPT_DIR/update-cycle-state.sh" "$CYCLE_DIR" CURRENT_CHUNK "1"
"$SCRIPT_DIR/update-cycle-state.sh" "$CYCLE_DIR" TOTAL_CHUNKS "$TOTAL_CHUNKS"

# Emit event
EVENTS_DIR="$CYCLE_DIR/.events"
"$SCRIPT_DIR/append-event.sh" "$EVENTS_DIR" "story_started" "$STORY_NAME" chunk_total="$TOTAL_CHUNKS" || true

# Refresh the dashboard graph data. Silenced so callers still read this
# script's own final line; guarded so a missing wrapper never fails a flow.
bash "$SCRIPT_DIR/../../scripts/dashboard/dashboard-run.sh" --root "${PROJECT_ROOT:-.}" >/dev/null 2>&1 || true

echo "Story started: $STORY_NAME (chunks: $TOTAL_CHUNKS)"
