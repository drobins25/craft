#!/bin/bash
# start-cycle.sh — Transition: Activate a cycle for implementation
# Usage: start-cycle.sh <cycle-dir-or-name>
#
# Updates:
# - Global: ACTIVE_CYCLE set, PLANNING_CYCLE cleared
# - Cycle: CYCLE_STATUS = active

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYCLE_INPUT="$1"
PROJECT_ROOT=""

if [ -z "$CYCLE_INPUT" ]; then
  echo "Usage: start-cycle.sh <cycle-dir-or-name>"
  echo "       start-cycle.sh .craft/cycles/1-auth"
  echo "       start-cycle.sh 1-auth"
  exit 1
fi

# Find cycle directory and derive PROJECT_ROOT
if [ -d "$CYCLE_INPUT" ]; then
  CYCLE_DIR="$CYCLE_INPUT"
  # Derive PROJECT_ROOT from cycle dir
  PROJECT_ROOT=$(echo "$CYCLE_DIR" | sed 's|/.craft/.*||')
  if [ -d "${PROJECT_ROOT}/.craft" ]; then
    PROJECT_ROOT="${PROJECT_ROOT}/"
  else
    PROJECT_ROOT=""
  fi
else
  # Name-based lookup uses cwd
  CYCLE_DIR=$(find "${PROJECT_ROOT}.craft/cycles" -maxdepth 1 -type d -name "*${CYCLE_INPUT}*" 2>/dev/null | head -1)
fi

if [ -z "$CYCLE_DIR" ] || [ ! -d "$CYCLE_DIR" ]; then
  echo "Error: Cycle not found: $CYCLE_INPUT"
  exit 1
fi

CYCLE_NAME=$(basename "$CYCLE_DIR")

# Update global state
"$SCRIPT_DIR/update-global-state.sh" ACTIVE_CYCLE "$CYCLE_NAME" "$PROJECT_ROOT"
"$SCRIPT_DIR/update-global-state.sh" PLANNING_CYCLE "" "$PROJECT_ROOT"
"$SCRIPT_DIR/update-global-state.sh" LAST_ACTIVITY "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_ROOT"

# Update cycle state
"$SCRIPT_DIR/update-cycle-state.sh" "$CYCLE_DIR" CYCLE_STATUS "active"

# Also update cycle.yaml status if it exists
if [ -f "$CYCLE_DIR/cycle.yaml" ]; then
  sed -i.bak "s/^status:.*/status: active/" "$CYCLE_DIR/cycle.yaml"
  sed -i.bak "s/^updated:.*/updated: $(date +%Y-%m-%d)/" "$CYCLE_DIR/cycle.yaml"
  rm -f "$CYCLE_DIR/cycle.yaml.bak"
fi

# Emit event
EVENTS_DIR="$CYCLE_DIR/.events"
"$SCRIPT_DIR/append-event.sh" "$EVENTS_DIR" "cycle_started" "_cycle" name="$CYCLE_NAME" || true

# Refresh the dashboard graph data. Silenced so callers still read this
# script's own final line; guarded so a missing wrapper never fails a flow.
bash "$SCRIPT_DIR/../../scripts/dashboard/dashboard-run.sh" --root "${PROJECT_ROOT:-.}" >/dev/null 2>&1 || true

# Display human-readable title
cycle_title=""
if [ -f "$CYCLE_DIR/cycle.yaml" ]; then
  cycle_title=$(grep "^title:" "$CYCLE_DIR/cycle.yaml" 2>/dev/null | sed 's/title: *//' | tr -d '"')
fi
echo "Cycle started: ${cycle_title:-$CYCLE_NAME}"
