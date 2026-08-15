#!/bin/bash
# complete-cycle.sh — Transition: Mark a cycle as complete
# Usage: complete-cycle.sh [cycle-dir]
#
# If cycle-dir not provided, uses ACTIVE_CYCLE from global state
#
# Updates:
# - Cycle: CYCLE_STATUS = complete
# - Global: ACTIVE_CYCLE cleared, CURRENT_STORY cleared

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYCLE_DIR="$1"
PROJECT_ROOT=""

# If cycle provided, derive PROJECT_ROOT from it
if [ -n "$CYCLE_DIR" ]; then
  PROJECT_ROOT=$(echo "$CYCLE_DIR" | sed 's|/.craft/.*||')
  if [ -d "${PROJECT_ROOT}/.craft" ]; then
    PROJECT_ROOT="${PROJECT_ROOT}/"
  else
    PROJECT_ROOT=""
  fi
fi

# If no cycle provided, resolve project root and get from global state
if [ -z "$CYCLE_DIR" ]; then
  source "$SCRIPT_DIR/find-workshop.sh" 2>/dev/null || {
    echo "Error: Could not resolve project root"
    exit 1
  }
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

CYCLE_NAME=$(basename "$CYCLE_DIR")
DATE=$(date +%Y-%m-%d)

# Update cycle state
"$SCRIPT_DIR/update-cycle-state.sh" "$CYCLE_DIR" CYCLE_STATUS "complete"
"$SCRIPT_DIR/update-cycle-state.sh" "$CYCLE_DIR" CURRENT_STORY ""
"$SCRIPT_DIR/update-cycle-state.sh" "$CYCLE_DIR" CURRENT_CHUNK "0"

# Update cycle.yaml
if [ -f "$CYCLE_DIR/cycle.yaml" ]; then
  sed -i.bak "s/^status:.*/status: complete/" "$CYCLE_DIR/cycle.yaml"
  sed -i.bak "s/^updated:.*/updated: $DATE/" "$CYCLE_DIR/cycle.yaml"
  rm -f "$CYCLE_DIR/cycle.yaml.bak"
fi

# Clear global state
"$SCRIPT_DIR/update-global-state.sh" ACTIVE_CYCLE "" "$PROJECT_ROOT"
"$SCRIPT_DIR/update-global-state.sh" CURRENT_STORY "" "$PROJECT_ROOT"
"$SCRIPT_DIR/update-global-state.sh" LAST_ACTIVITY "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_ROOT"

# Emit event
stories_complete=$(ls "$CYCLE_DIR/stories/"*.md 2>/dev/null | xargs grep -l "^status: complete" 2>/dev/null | wc -l | tr -d ' ')
EVENTS_DIR="$CYCLE_DIR/.events"
"$SCRIPT_DIR/append-event.sh" "$EVENTS_DIR" "cycle_completed" "_cycle" name="$CYCLE_NAME" stories_complete="$stories_complete" || true

# Clean up checkpoint files for this cycle's stories
CHECKPOINT_DIR="${PROJECT_ROOT}.craft/checkpoints"
if [ -d "$CHECKPOINT_DIR" ]; then
  # Get story names from this cycle
  for story_file in "$CYCLE_DIR/stories/"*.md; do
    story_name=$(basename "$story_file" .md)
    # Remove checkpoint YAMLs matching this story (pattern: story-name-chunk-N.yaml)
    rm -f "$CHECKPOINT_DIR/${story_name}-chunk-"*.yaml 2>/dev/null
  done
  # Remove dir if now empty
  rmdir "$CHECKPOINT_DIR" 2>/dev/null || true
fi

# Refresh the dashboard graph data. Silenced so callers still read this
# script's own final line; guarded so a missing wrapper never fails a flow.
bash "$SCRIPT_DIR/../../scripts/dashboard/dashboard-run.sh" --root "${PROJECT_ROOT:-.}" >/dev/null 2>&1 || true

# Display human-readable title
cycle_title=""
if [ -f "$CYCLE_DIR/cycle.yaml" ]; then
  cycle_title=$(grep "^title:" "$CYCLE_DIR/cycle.yaml" 2>/dev/null | sed 's/title: *//' | tr -d '"')
fi
echo "Cycle completed: ${cycle_title:-$CYCLE_NAME}"
