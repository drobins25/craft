#!/bin/bash
# Inject-craft-context: Add Craft state to user prompts
# Gives Claude awareness of current story/cycle without user typing it

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_INDEX="$(dirname "$SCRIPT_DIR")/../reference/orchestration-index.min"
COLD_INDEX="$(dirname "$SCRIPT_DIR")/../reference/cold-start-index.min"

# Uninitialized project: emit the cold-start index instead of going silent,
# so Claude knows craft exists and can route to what works before /craft:init.
# Fires on find-workshop failure, which covers BOTH "no .craft/ at all" and
# "bare .craft/ without .global-state/project.md" (a cold notebook or mockup
# capture creates that shape, and the index must keep injecting after it).
emit_cold_index() {
  if [ -f "$COLD_INDEX" ]; then
    cat "$COLD_INDEX"
  fi
}

# Resolve project root (handles monorepo with multiple .craft/ dirs).
# The if-form consumes find-workshop's non-zero return so set -e survives it.
if ! source "$SCRIPT_DIR/find-workshop.sh" 2>/dev/null; then
  emit_cold_index
  exit 0
fi

# Defensive: resolution succeeded but root is unusable — treat as uninitialized
if [ -z "$PROJECT_ROOT" ] || [ ! -d "${PROJECT_ROOT}.craft" ]; then
  emit_cold_index
  exit 0
fi

# Multi-project ambiguity — remind user to select
if [ "$CRAFT_MULTI_PROJECT" = "true" ]; then
  echo "[Craft: No project selected — use /craft:project to choose]"
  exit 0
fi

# Detect package manager from project.md
PM=""
if [ -f "${PROJECT_ROOT}.craft/project.md" ]; then
  PM=$(grep "^package_manager:" "${PROJECT_ROOT}.craft/project.md" 2>/dev/null | sed 's/package_manager: *//' | tr -d '"' | tr -d "'")
fi

# Build context string
context=""

# Project name prefix for monorepo mode
project_tag=""
if [ -n "$CRAFT_PROJECT_NAME" ]; then
  project_tag="${CRAFT_PROJECT_NAME} "
fi

if [ -f "${PROJECT_ROOT}.craft/.global-state" ]; then
  source "${PROJECT_ROOT}.craft/.global-state"

  # Planning a cycle takes priority - stories go to THIS cycle
  if [ -n "$PLANNING_CYCLE" ]; then
    plan_title=""
    if [ -f "${PROJECT_ROOT}.craft/cycles/$PLANNING_CYCLE/cycle.yaml" ]; then
      plan_title=$(grep "^title:" "${PROJECT_ROOT}.craft/cycles/$PLANNING_CYCLE/cycle.yaml" 2>/dev/null | sed 's/title: *//' | tr -d '"')
    fi
    plan_display="${plan_title:-$PLANNING_CYCLE}"
    context="[Craft:${project_tag}PLANNING cycle '$plan_display' — stories go to ${PROJECT_ROOT}.craft/cycles/$PLANNING_CYCLE/stories/]"

  elif [ -n "$ACTIVE_CYCLE" ]; then
    cycle_title=""
    if [ -f "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/cycle.yaml" ]; then
      cycle_title=$(grep "^title:" "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/cycle.yaml" 2>/dev/null | sed 's/title: *//' | tr -d '"')
    fi
    cycle_display="${cycle_title:-$ACTIVE_CYCLE}"

    pm_tag=""
    [ -n "$PM" ] && pm_tag=" ($PM)"
    context="[Craft:${project_tag}Cycle '$cycle_display'${pm_tag}"

    if [ -n "$CURRENT_STORY" ]; then
      context="$context, Story '$CURRENT_STORY'"

      # Get chunk progress from cycle state
      if [ -f "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/.state" ]; then
        source "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE/.state"
        if [ -n "$CURRENT_CHUNK" ] && [ -n "$TOTAL_CHUNKS" ]; then
          context="$context, Chunk $CURRENT_CHUNK/$TOTAL_CHUNKS"
        fi
      fi
    fi

    context="$context]"

    # Unread implementer observations for this cycle (only when count > 0).
    # Lives inside the ACTIVE_CYCLE branch so it never fires for planning/backlog
    # contexts. The count helper is pure bash/grep (hot path - runs every prompt).
    obs_count=$(bash "$SCRIPT_DIR/observations-count.sh" "${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE" 2>/dev/null || true)
    if [ -n "$obs_count" ]; then
      context="$context
[Craft observations: $obs_count - review at story/cycle complete]"
    fi
  else
    # No active cycle
    backlog_count=$(ls -1 "${PROJECT_ROOT}.craft/backlog/"*.md 2>/dev/null | wc -l | tr -d ' ')
    pm_tag=""
    [ -n "$PM" ] && pm_tag=" ($PM)"

    # Check for cycles with ready stories that could be activated
    ready_cycle=""
    for cycle_dir in "${PROJECT_ROOT}.craft/cycles"/*/; do
      if [ -d "$cycle_dir" ] && [ -f "$cycle_dir/cycle.yaml" ]; then
        ready_stories=$(grep -l "^status: ready" "$cycle_dir/stories/"*.md 2>/dev/null | wc -l | tr -d ' ')
        if [ "$ready_stories" -gt 0 ]; then
          ready_cycle=$(basename "$cycle_dir")
          break
        fi
      fi
    done

    if [ -n "$ready_cycle" ]; then
      context="[Craft:${project_tag}No active cycle${pm_tag} — use /craft:cycle-start to activate '$ready_cycle']"
    elif [ "$backlog_count" -gt 0 ]; then
      context="[Craft:${project_tag}$backlog_count stories in backlog${pm_tag}]"
    fi
  fi
fi

# Active workflow session (can coexist with cycle context)
if [ -n "$CURRENT_WORKFLOW_SESSION" ] && [ -d "$CURRENT_WORKFLOW_SESSION" ]; then
  wf_session_file="$CURRENT_WORKFLOW_SESSION/session.md"
  if [ -f "$wf_session_file" ]; then
    wf_status=$(awk '/^---$/{n++; next} n==1 && /^status:/{print $2; exit}' "$wf_session_file")
    if [ "$wf_status" = "active" ]; then
      wf_name=$(awk '/^name:/{gsub(/^name: */, ""); print; exit}' "$wf_session_file")
      wf_stage=$(awk '/^current_stage:/{gsub(/^current_stage: */, ""); print; exit}' "$wf_session_file")
      wf_workflow=$(awk '/^workflow:/{gsub(/^workflow: */, ""); print; exit}' "$wf_session_file")
      # Count stages from Progress table (stages-v1 format)
      wf_total=$(awk '/^\| [0-9]/' "$wf_session_file" 2>/dev/null | wc -l | tr -d ' ')
      [ -z "$wf_total" ] || [ "$wf_total" = "0" ] && wf_total="?"
      context="${context:+$context
}[Craft:Workflow '$wf_workflow' session '$wf_name' - stage $wf_stage/$wf_total - writes allowed (active session)]"
    fi
  fi
fi

# Output context as system message if we have any
if [ -n "$context" ]; then
  echo "$context"
fi

# Append orchestration index (always, when .craft/ exists)
# Following Vercel AGENTS.md pattern: passive context > on-demand skills
# The plugin-root line pairs with the index so every relative path in it (and in
# raw-Read reference files) resolves against a root the reader can see.
if [ -f "$ORCH_INDEX" ]; then
  echo ""
  echo "[Craft plugin root: $(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)]"
  cat "$ORCH_INDEX"
fi

exit 0
