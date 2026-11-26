#!/bin/bash
# update-global-state.sh — Low-level global state setter
# Usage: update-global-state.sh <key> <value> [project-root]
#
# Valid keys: ACTIVE_CYCLE, CURRENT_STORY, PLANNING_CYCLE, RUN_MODE,
#             BACKLOG_COUNT, DEFAULT_MODE, LAST_ACTIVITY, VOCAB_GATE

set -e

KEY="$1"
VALUE="$2"
PROJECT_ROOT="${3:-.}"  # Default to current directory if not provided

# Normalize PROJECT_ROOT (remove trailing slash if present, handle empty)
PROJECT_ROOT="${PROJECT_ROOT%/}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="."
fi

STATE_FILE="${PROJECT_ROOT}/.craft/.global-state"

if [ -z "$KEY" ]; then
  echo "Usage: update-global-state.sh <key> <value> [project-root]"
  echo "       update-global-state.sh <key> \"\"  # to clear"
  exit 1
fi

# The write gate is a per-session file now; a copied old call must fail loudly
# rather than set a key nothing reads.
if [ "$KEY" = "CRAFT_WRITE_ENABLED" ]; then
  echo "Error: CRAFT_WRITE_ENABLED is no longer a state key - open or close this session's write gate with write-gate.sh"
  exit 1
fi

# Ensure .craft exists
if [ ! -d "${PROJECT_ROOT}/.craft" ]; then
  echo "Error: .craft directory not found. Run /craft:init first."
  exit 1
fi


# Create state file if missing
if [ ! -f "$STATE_FILE" ]; then
  cat > "$STATE_FILE" << 'EOF'
# Craft Global State
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
RUN_MODE=""
DEFAULT_MODE="creative"
BACKLOG_COUNT=0
LAST_ACTIVITY=""
EOF
fi

# TEMPORARY - REMOVE ON 2027-01-01 (delete this whole block, and delete
# tests/test-legacy-write-gate-cleanup.sh with it; nothing else depends on either).
# Craft 2.20.3 and earlier kept the write gate as a CRAFT_WRITE_ENABLED line in
# .global-state. Nothing reads it now, so drop that one line from an older
# project the next time any state key is set.
if grep -q '^CRAFT_WRITE_ENABLED=' "$STATE_FILE"; then
  sed -i.bak '/^CRAFT_WRITE_ENABLED=/d' "$STATE_FILE"
  rm -f "$STATE_FILE.bak"
fi
# END TEMPORARY legacy write gate cleanup

# Resolve NOW keyword to current UTC timestamp
if [ "$VALUE" = "NOW" ]; then
  VALUE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

# Update or add the key
if grep -q "^${KEY}=" "$STATE_FILE"; then
  # Key exists — update in place
  sed -i.bak "s|^${KEY}=.*|${KEY}=\"${VALUE}\"|" "$STATE_FILE"
  rm -f "$STATE_FILE.bak"
else
  # Key doesn't exist — append
  echo "${KEY}=\"${VALUE}\"" >> "$STATE_FILE"
fi
