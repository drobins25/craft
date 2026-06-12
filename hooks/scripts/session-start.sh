#!/bin/bash
# SessionStart: Initialize craft context at session start
# Validates state, outputs welcome context for Claude

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve project root (handles monorepo with multiple .craft/ dirs)
source "$SCRIPT_DIR/find-project-root.sh" 2>/dev/null || exit 0

# No .craft/ found anywhere — not a craft project
if [ -z "$PROJECT_ROOT" ] || [ ! -d "${PROJECT_ROOT}.craft" ]; then
  exit 0
fi

# Clean up stale breadcrumbs and orphaned fix markers from crashed sessions
rm -f "${PROJECT_ROOT}.craft/.continuation"
rm -f "${PROJECT_ROOT}.craft/.active-fix"
rm -f "${PROJECT_ROOT}.craft/.commit-manifest"

# Clear stale CURRENT_WORKFLOW_SESSION if the session is no longer active
if [ -f "${PROJECT_ROOT}.craft/.global-state" ]; then
  WF_SESSION_PATH=$(grep "^CURRENT_WORKFLOW_SESSION=" "${PROJECT_ROOT}.craft/.global-state" 2>/dev/null | sed 's/CURRENT_WORKFLOW_SESSION="\(.*\)"/\1/')
  if [ -n "$WF_SESSION_PATH" ] && [ -f "$WF_SESSION_PATH/session.md" ]; then
    WF_STATUS=$(awk '/^---$/{n++; next} n==1 && /^status:/{print $2; exit}' "$WF_SESSION_PATH/session.md")
    if [ "$WF_STATUS" != "active" ]; then
      "$SCRIPT_DIR/update-global-state.sh" CURRENT_WORKFLOW_SESSION "" "${PROJECT_ROOT%/}"
    fi
  elif [ -n "$WF_SESSION_PATH" ]; then
    # Session directory gone - clear the stale reference
    "$SCRIPT_DIR/update-global-state.sh" CURRENT_WORKFLOW_SESSION "" "${PROJECT_ROOT%/}"
  fi
fi

# Persist project root for this session
if [ -n "$CLAUDE_ENV_FILE" ] && [ -n "$PROJECT_ROOT" ]; then
  echo "export CRAFT_PROJECT_ROOT=\"${PROJECT_ROOT%/}\"" >> "$CLAUDE_ENV_FILE"
  [ -n "$CRAFT_PROJECT_NAME" ] && echo "export CRAFT_PROJECT_NAME=\"$CRAFT_PROJECT_NAME\"" >> "$CLAUDE_ENV_FILE"

  # Also write persistent pin file so hooks (which don't get CLAUDE_ENV_FILE) can resolve
  _repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || true
  if [ -n "$_repo_root" ] && [ -d "$_repo_root/.craft" ] && [ "$CRAFT_MULTI_PROJECT" != "true" ]; then
    printf '%s\n%s\n' "${PROJECT_ROOT%/}" "${CRAFT_PROJECT_NAME:-}" > "$_repo_root/.craft/.pinned-project"
  fi
fi

# Handle multi-project ambiguity
if [ "$CRAFT_MULTI_PROJECT" = "true" ]; then
  # List available projects for Claude to present
  projects=$("$SCRIPT_DIR/discover-projects.sh" 2>/dev/null)
  echo "Craft: Multiple projects detected. Use /craft:project to select:"
  echo "$projects" | while IFS='|' read -r name path status pm; do
    echo "  - $name ($status)"
  done
  exit 0
fi

# Ensure global state exists
if [ ! -f "${PROJECT_ROOT}.craft/.global-state" ]; then
  cat > "${PROJECT_ROOT}.craft/.global-state" << 'EOF'
ACTIVE_CYCLE=""
CURRENT_STORY=""
PLANNING_CYCLE=""
RUN_MODE=""
HARNESS_CHECKED="true"
LAST_ACTIVITY=""
EOF
fi

source "${PROJECT_ROOT}.craft/.global-state"

# Detect package manager from project.md
PM=""
if [ -f "${PROJECT_ROOT}.craft/project.md" ]; then
  PM=$(grep "^package_manager:" "${PROJECT_ROOT}.craft/project.md" 2>/dev/null | sed 's/package_manager: *//' | tr -d '"' | tr -d "'")
fi

# Build context summary for Claude
context=""

# Project name prefix (only in monorepo mode)
project_prefix=""
if [ -n "$CRAFT_PROJECT_NAME" ]; then
  project_prefix="[$CRAFT_PROJECT_NAME] "
fi

# Active cycle info
if [ -n "$ACTIVE_CYCLE" ]; then
  cycle_title=""
  if [ -f "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/cycle.yaml" ]; then
    cycle_title=$(grep "^title:" "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/cycle.yaml" | sed 's/title: *//' | tr -d '"')
  fi
  cycle_display="${cycle_title:-$ACTIVE_CYCLE}"
  context="${project_prefix}Active cycle: $cycle_display"

  # Current story
  if [ -n "$CURRENT_STORY" ]; then
    context="$context | Story in progress: $CURRENT_STORY"

    # Current chunk
    if [ -f "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/.state" ]; then
      source "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/.state"
      if [ -n "$CURRENT_CHUNK" ] && [ -n "$TOTAL_CHUNKS" ]; then
        context="$context (chunk $CURRENT_CHUNK/$TOTAL_CHUNKS)"
      fi
    fi
  else
    # Count stories in cycle by status
    story_count=$(ls -1 "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/stories/"*.md 2>/dev/null | wc -l | tr -d ' ')
    complete_count=$(grep -l "^status: complete" "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/stories/"*.md 2>/dev/null | wc -l | tr -d ' ')
    ready_count=$(grep -l "^status: ready" "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/stories/"*.md 2>/dev/null | wc -l | tr -d ' ')
    planning_count=$(grep -l "^status: planning" "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/stories/"*.md 2>/dev/null | wc -l | tr -d ' ')
    context="$context | Stories: $complete_count done, $ready_count ready, $planning_count planning ($story_count total)"
  fi
else
  # No active cycle - check backlog
  backlog_count=$(ls -1 "${PROJECT_ROOT}.craft/backlog/"*.md 2>/dev/null | wc -l | tr -d '[:space:]')
  cycle_count=$(ls -1d "${PROJECT_ROOT}.craft/cycles/"*/ 2>/dev/null | wc -l | tr -d '[:space:]')

  if [ "$backlog_count" -gt 0 ] || [ "$cycle_count" -gt 0 ]; then
    context="${project_prefix}No active cycle"
    [ "$backlog_count" -gt 0 ] && context="$context | Backlog: $backlog_count stories"
    [ "$cycle_count" -gt 0 ] && context="$context | Cycles: $cycle_count"
  else
    context="${project_prefix}Craft initialized but empty. Run /craft to get started."
  fi
fi

# Package manager info
if [ -n "$PM" ]; then
  context="$context | Package manager: $PM"
fi

# Check for pending learnings
if [ -f "${PROJECT_ROOT}.craft/.learnings.yaml" ]; then
  unprocessed=$(grep -c "status: pending" "${PROJECT_ROOT}.craft/.learnings.yaml" 2>/dev/null) || true
  unprocessed="${unprocessed:-0}"
  if [ "$unprocessed" -gt 0 ]; then
    context="$context | $unprocessed unprocessed learnings"
  fi
fi

# Check for stale docs (> 30 days)
if [ -f "${PROJECT_ROOT}.craft/project.md" ]; then
  last_updated=$(grep "^last_updated:" "${PROJECT_ROOT}.craft/project.md" 2>/dev/null | sed 's/last_updated: *//')
  if [ -n "$last_updated" ]; then
    last_epoch=$(date -j -f "%Y-%m-%d" "$last_updated" "+%s" 2>/dev/null || echo "0")
    now_epoch=$(date "+%s")
    days_old=$(( (now_epoch - last_epoch) / 86400 ))
    if [ "$days_old" -gt 30 ]; then
      context="$context | project.md is ${days_old}d old"
    fi
  fi
fi

# Check for pending requests
if [ -d "${PROJECT_ROOT}.craft/requests" ]; then
  requests_count=$(find "${PROJECT_ROOT}.craft/requests" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$requests_count" -gt 0 ]; then
    context="$context | $requests_count pending request(s)"
  fi
fi

# Check for active/ready workflow sessions
if [ -d "${PROJECT_ROOT}.craft/workflows" ]; then
  wf_active=0
  wf_ready=0
  wf_active_names=""
  wf_ready_names=""
  for wf_dir in "${PROJECT_ROOT}.craft/workflows"/*/; do
    [ -d "$wf_dir/sessions" ] || continue
    wf_name=$(basename "$wf_dir")
    [ "$wf_name" = ".archived" ] && continue
    for sess_dir in "$wf_dir/sessions"/*/; do
      [ -f "$sess_dir/session.md" ] || continue
      sess_status=$(awk '/^status:/{print $2; exit}' "$sess_dir/session.md" 2>/dev/null)
      sess_name=$(awk '/^name:/{gsub(/^name: */, ""); print; exit}' "$sess_dir/session.md" 2>/dev/null)
      if [ "$sess_status" = "active" ]; then
        wf_active=$((wf_active + 1))
        wf_active_names="${wf_active_names}${sess_name}, "
      elif [ "$sess_status" = "ready" ]; then
        wf_ready=$((wf_ready + 1))
        wf_ready_names="${wf_ready_names}${sess_name}, "
      fi
    done
  done
  if [ "$wf_active" -gt 0 ]; then
    context="$context | Workflow: ${wf_active} active (${wf_active_names%, })"
  fi
  if [ "$wf_ready" -gt 0 ]; then
    context="$context | Workflow: ${wf_ready} ready"
  fi
fi

# Report orchestration index status (one-time, SessionStart only)
ORCH_INDEX="$(dirname "$SCRIPT_DIR")/../reference/orchestration-index.min"
if [ -f "$ORCH_INDEX" ]; then
  IDX_SIZE=$(wc -c < "$ORCH_INDEX" | tr -d ' ')
  context="$context | Routing index: loaded (${IDX_SIZE} bytes)"
fi

# Output context as system message if we have anything
if [ -n "$context" ]; then
  echo "Craft: $context"
fi

# Surface the durable-notes index (the "index in" half of hybrid recall).
# The generator no-ops when there are no notes, so projects without notes see
# zero added output. Full note bodies are read on demand at recall time.
NOTES_INDEX=$("$SCRIPT_DIR/notebook-notes-index.sh" 2>/dev/null || true)
if [ -n "$NOTES_INDEX" ]; then
  echo ""
  echo "$NOTES_INDEX"
fi

exit 0
