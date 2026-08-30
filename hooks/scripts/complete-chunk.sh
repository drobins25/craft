#!/bin/bash
# complete-chunk.sh — Transition: Mark current chunk as complete, advance to next
# Usage: complete-chunk.sh [cycle-dir]
#
# If cycle-dir not provided, uses ACTIVE_CYCLE from global state
#
# Updates:
# - Cycle .state: CURRENT_CHUNK incremented, LAST_VALIDATION timestamp
# - Story frontmatter: chunks_complete incremented, current_chunk updated

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYCLE_DIR="$1"

# Convert relative paths to absolute using PWD
if [ -n "$CYCLE_DIR" ] && [[ "$CYCLE_DIR" != /* ]]; then
  CYCLE_DIR="$PWD/$CYCLE_DIR"
fi

# If cycle provided, derive PROJECT_ROOT from it
if [ -n "$CYCLE_DIR" ]; then
  PROJECT_ROOT=$(echo "$CYCLE_DIR" | sed 's|/.craft/.*||')
  if [ -d "${PROJECT_ROOT}/.craft" ]; then
    PROJECT_ROOT="${PROJECT_ROOT}/"
  else
    PROJECT_ROOT=""
  fi
else
  # Walk up to find project root (handles monorepo subdirectories)
  PROJECT_ROOT=""
  source "$SCRIPT_DIR/find-workshop.sh"
fi

# If no cycle provided, get from global state
if [ -z "$CYCLE_DIR" ]; then
  if [ -f "${PROJECT_ROOT}.craft/.global-state" ]; then
    source "${PROJECT_ROOT}.craft/.global-state"
    if [ -n "$ACTIVE_CYCLE" ]; then
      CYCLE_DIR="${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE"
    fi
  fi
fi

if [ -z "$CYCLE_DIR" ] || [ ! -d "$CYCLE_DIR" ]; then
  echo "Error: No active cycle found"
  exit 1
fi

# Get current state
if [ ! -f "$CYCLE_DIR/.state" ]; then
  echo "Error: Cycle state file not found"
  exit 1
fi

source "$CYCLE_DIR/.state"

if [ -z "$CURRENT_STORY" ]; then
  echo "Error: No active story in cycle"
  exit 1
fi

# Increment chunk
NEW_CHUNK=$((CURRENT_CHUNK + 1))

# Update cycle state
"$SCRIPT_DIR/update-cycle-state.sh" "$CYCLE_DIR" CURRENT_CHUNK "$NEW_CHUNK"
"$SCRIPT_DIR/update-cycle-state.sh" "$CYCLE_DIR" LAST_VALIDATION "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Update story file chunks_complete
STORY_FILE=$(find "$CYCLE_DIR/stories" -name "*${CURRENT_STORY}*.md" 2>/dev/null | head -1)
if [ -n "$STORY_FILE" ] && [ -f "$STORY_FILE" ]; then
  current_complete=$(grep "^chunks_complete:" "$STORY_FILE" 2>/dev/null | sed 's/chunks_complete: *//' || echo "0")
  new_complete=$((current_complete + 1))
  sed -i.bak "s/^chunks_complete:.*/chunks_complete: $new_complete/" "$STORY_FILE"
  sed -i.bak "s/^current_chunk:.*/current_chunk: $NEW_CHUNK/" "$STORY_FILE"
  sed -i.bak "s/^updated:.*/updated: $(date +%Y-%m-%d)/" "$STORY_FILE"
  rm -f "$STORY_FILE.bak"
fi

# Update global last activity
"$SCRIPT_DIR/update-global-state.sh" LAST_ACTIVITY "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_ROOT"

# Clean up chunk validation state (REFINE_COUNT tracking)
rm -f "${PROJECT_ROOT}.craft/.chunk-state"

# Emit event
EVENTS_DIR="$CYCLE_DIR/.events"
"$SCRIPT_DIR/append-event.sh" "$EVENTS_DIR" "chunk_completed" "$CURRENT_STORY" chunk="$CURRENT_CHUNK" total="$TOTAL_CHUNKS" || true

# Refresh the dashboard graph data. Silenced so callers still read this
# script's own final line; guarded so a missing wrapper never fails a flow.
bash "$SCRIPT_DIR/../../scripts/dashboard/dashboard-run.sh" --root "${PROJECT_ROOT:-.}" >/dev/null 2>&1 || true

# Signal whether this was the last chunk
if [ "$NEW_CHUNK" -gt "$TOTAL_CHUNKS" ]; then
  echo "ALL CHUNKS COMPLETE ($TOTAL_CHUNKS/$TOTAL_CHUNKS). Run complete-story.sh to finalize."
else
  echo "Chunk $CURRENT_CHUNK complete. Now on chunk $NEW_CHUNK of $TOTAL_CHUNKS."
fi
