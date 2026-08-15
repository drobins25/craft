#!/bin/bash
# Delete-story: Remove a story file and clean up state references
# Usage: delete-story.sh <story-file>
#
# If the deleted story is currently active, clears CURRENT_STORY
# from both .global-state and cycle .state.
# Story counts are derived from directory scan.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STORY_FILE="$1"

if [ -z "$STORY_FILE" ]; then
  echo "Error: Story file required"
  echo "Usage: delete-story.sh <story-file>"
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

# Get story name for confirmation message
story_name=$(basename "$STORY_FILE" .md)

# Derive project root from story file path
PROJECT_ROOT=$(echo "$STORY_FILE" | sed 's|/.craft/.*||')
if [ -d "${PROJECT_ROOT}/.craft" ]; then
  PROJECT_ROOT="${PROJECT_ROOT}/"
else
  PROJECT_ROOT=""
fi

# Check if this story is currently active — if so, clear state references
if [ -f "${PROJECT_ROOT}.craft/.global-state" ]; then
  source "${PROJECT_ROOT}.craft/.global-state"
  if [ -n "$CURRENT_STORY" ] && [[ "$story_name" == *"$CURRENT_STORY"* ]]; then
    # Clear global state
    "$SCRIPT_DIR/update-global-state.sh" CURRENT_STORY "" "$PROJECT_ROOT"
    "$SCRIPT_DIR/update-global-state.sh" CRAFT_WRITE_ENABLED "" "$PROJECT_ROOT"
    "$SCRIPT_DIR/update-global-state.sh" LAST_ACTIVITY "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_ROOT"

    # Clear cycle state if story was in a cycle
    cycle_name=$(grep "^cycle:" "$STORY_FILE" 2>/dev/null | sed 's/cycle: *//' | tr -d '\r')
    if [ -n "$cycle_name" ]; then
      cycle_dir=$(find "${PROJECT_ROOT}.craft/cycles" -maxdepth 1 -type d -name "*${cycle_name}*" 2>/dev/null | head -1)
      if [ -n "$cycle_dir" ] && [ -d "$cycle_dir" ]; then
        "$SCRIPT_DIR/update-cycle-state.sh" "$cycle_dir" CURRENT_STORY ""
        "$SCRIPT_DIR/update-cycle-state.sh" "$cycle_dir" CURRENT_CHUNK "0"
        "$SCRIPT_DIR/update-cycle-state.sh" "$cycle_dir" TOTAL_CHUNKS "0"
      fi
    fi
  fi
fi

# Delete the file
rm "$STORY_FILE"

# Refresh the dashboard graph data so the removed record leaves the graph.
# Silenced so callers still read this script's own final line; guarded so a
# missing wrapper never fails a flow.
bash "$SCRIPT_DIR/../../scripts/dashboard/dashboard-run.sh" --root "${PROJECT_ROOT:-.}" >/dev/null 2>&1 || true

echo "Story deleted: $story_name"
