#!/bin/bash
# Post-compact-reinject: Re-inject critical Craft context after compaction
# Fires on SessionStart with matcher "compact"
# Outputs rich state so the orchestrator can resume without re-reading everything

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Walk up to find project root (handles monorepo subdirectories)
PROJECT_ROOT=""
source "$SCRIPT_DIR/find-project-root.sh" 2>/dev/null || exit 0

if [ ! -f "${PROJECT_ROOT}.craft/.global-state" ]; then
  exit 0
fi

source "${PROJECT_ROOT}.craft/.global-state"

# Detect package manager
PM=""
if [ -f "${PROJECT_ROOT}.craft/project.md" ]; then
  PM=$(grep "^package_manager:" "${PROJECT_ROOT}.craft/project.md" 2>/dev/null | sed 's/package_manager: *//' | tr -d '"' | tr -d "'")
fi

# Build re-injection context
echo "--- CRAFT CONTEXT (post-compaction recovery) ---"

# Active cycle + story + chunk
if [ -n "$ACTIVE_CYCLE" ]; then
  cycle_title=""
  if [ -f "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/cycle.yaml" ]; then
    cycle_title=$(grep "^title:" "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/cycle.yaml" 2>/dev/null | sed 's/title: *//' | tr -d '"')
  fi
  echo "Active cycle: ${cycle_title:-$ACTIVE_CYCLE}"
  [ -n "$PM" ] && echo "Package manager: $PM"
  [ -n "$RUN_MODE" ] && echo "Run mode: $RUN_MODE"

  if [ -n "$CURRENT_STORY" ]; then
    echo "Current story: $CURRENT_STORY"

    # Get chunk progress
    if [ -f "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/.state" ]; then
      source "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/.state"
      if [ -n "$CURRENT_CHUNK" ] && [ -n "$TOTAL_CHUNKS" ]; then
        echo "Progress: chunk $CURRENT_CHUNK of $TOTAL_CHUNKS"
      fi
    fi

    # Include current story frontmatter (compact — just the YAML header)
    story_file=$(find "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/stories" -name "*${CURRENT_STORY}*.md" 2>/dev/null | head -1)
    if [ -n "$story_file" ] && [ -f "$story_file" ]; then
      echo ""
      echo "Story file: $story_file"
      # Extract just the frontmatter (between --- markers)
      sed -n '/^---$/,/^---$/p' "$story_file" | head -30
    fi
  fi
else
  backlog_count=$(ls -1 "${PROJECT_ROOT}.craft/backlog/"*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "No active cycle. Backlog: $backlog_count stories."
  [ -n "$PM" ] && echo "Package manager: $PM"
fi

# Active workflow session
if [ -n "$CURRENT_WORKFLOW_SESSION" ]; then
  echo "Active workflow session: $CURRENT_WORKFLOW_SESSION"
  WF_SESSION_FILE="$CURRENT_WORKFLOW_SESSION/session.md"
  if [ -f "$WF_SESSION_FILE" ]; then
    WF_NAME=$(awk '/^name:/{gsub(/^name: */, ""); print; exit}' "$WF_SESSION_FILE")
    WF_STAGE=$(awk '/^current_stage:/{gsub(/^current_stage: */, ""); print; exit}' "$WF_SESSION_FILE")
    WF_WORKFLOW=$(awk '/^workflow:/{gsub(/^workflow: */, ""); print; exit}' "$WF_SESSION_FILE")
    echo "Session: $WF_NAME"
    echo "Workflow: $WF_WORKFLOW"
    echo "Current stage: $WF_STAGE"
    # Get the workflow definition path for stage details
    WF_DEF_DIR="$(dirname "$(dirname "$CURRENT_WORKFLOW_SESSION")")"
    [ -f "$WF_DEF_DIR/definition.md" ] && echo "Definition: $WF_DEF_DIR/definition.md"
    # Output the current stage file for quick recovery
    STAGE_FILE=$(ls "$WF_DEF_DIR/stages/$(printf "%02d" "$WF_STAGE")-"*.md 2>/dev/null | head -1)
    [ -z "$STAGE_FILE" ] && STAGE_FILE=$(ls "$WF_DEF_DIR/stages/${WF_STAGE}-"*.md 2>/dev/null | head -1)
    if [ -n "$STAGE_FILE" ]; then
      echo "Current stage file: $STAGE_FILE"
    fi
  fi
  echo ""
  echo "ACTION REQUIRED: You were running craft:workflow-run continue. Re-invoke it via the Skill tool to reload full instructions and resume."
  echo ""
fi

# Check for pending learnings
if [ -f "${PROJECT_ROOT}.craft/.learnings.yaml" ]; then
  unprocessed=$(grep -c "status: pending" "${PROJECT_ROOT}.craft/.learnings.yaml" 2>/dev/null || echo "0")
  if [ "$unprocessed" -gt 0 ]; then
    echo "Pending learnings: $unprocessed"
  fi
fi

echo "--- END CRAFT CONTEXT ---"
echo ""
echo "IMPORTANT: Use transition scripts for state changes (complete-chunk.sh, complete-story.sh, start-story.sh). Never edit .state files directly."

# Tell Claude which command to re-invoke to reload full instructions
if [ -n "$CURRENT_STORY" ]; then
  if [ "$RUN_MODE" = "autonomous" ]; then
    echo ""
    echo "ACTION REQUIRED: You were running craft:story-implement-auto. Re-invoke it via the Skill tool to reload full instructions and resume."
  else
    echo ""
    echo "ACTION REQUIRED: You were running craft:story-implement. Re-invoke it via the Skill tool to reload full instructions and resume."
  fi
fi

exit 0
