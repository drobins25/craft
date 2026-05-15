#!/bin/bash
# Create-cycle: Create a new cycle directory and files
# Usage: create-cycle.sh <cycle-name> [cycle-title] [cycle-target] [project-root] [source-concepts]
#   source-concepts: optional comma-separated planning doc paths (e.g.,
#                    "planning/04-company-onboarding.md" or
#                    "planning/a.md,planning/b.md"). Written to cycle.yaml
#                    as source_concept field. Empty -> source_concept: [].

set -e

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname $(dirname $(dirname "$0")))}"
TEMPLATES_DIR="$PLUGIN_ROOT/templates"

# Arguments
CYCLE_NAME="$1"
CYCLE_TITLE="${2:-$CYCLE_NAME}"
CYCLE_TARGET="${3:-TBD}"
PROJECT_ROOT="${4:-.}"
SOURCE_CONCEPTS="${5:-}"

# Normalize PROJECT_ROOT
PROJECT_ROOT="${PROJECT_ROOT%/}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="."
fi

if [ -z "$CYCLE_NAME" ]; then
  echo "Error: Cycle name required"
  echo "Usage: create-cycle.sh <cycle-name> [cycle-title] [cycle-target] [project-root] [source-concepts]"
  exit 1
fi

# Build source_concept YAML value (flow list with single-quoted items)
# Empty -> "[]"; comma-separated paths -> "['path1', 'path2']"
# Single-quoted items tolerate commas, brackets, and spaces in paths.
if [ -n "$SOURCE_CONCEPTS" ]; then
  QUOTED=""
  IFS=',' read -ra PATHS <<< "$SOURCE_CONCEPTS"
  for path in "${PATHS[@]}"; do
    # Trim leading/trailing whitespace
    path=$(echo "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # Skip empty entries (e.g., trailing comma or "a,,b")
    if [ -z "$path" ]; then continue; fi
    if [ -n "$QUOTED" ]; then QUOTED="${QUOTED}, "; fi
    QUOTED="${QUOTED}'${path}'"
  done
  if [ -n "$QUOTED" ]; then
    SOURCE_CONCEPT_YAML="[${QUOTED}]"
  else
    SOURCE_CONCEPT_YAML="[]"
  fi
else
  SOURCE_CONCEPT_YAML="[]"
fi

# Ensure .craft exists
if [ ! -d "${PROJECT_ROOT}/.craft" ]; then
  echo "Error: .craft directory not found at ${PROJECT_ROOT}. Run /craft:init first."
  exit 1
fi

# Determine cycle number
existing_cycles=$(ls -d "${PROJECT_ROOT}/.craft/cycles"/*/ 2>/dev/null | wc -l | tr -d ' ')
cycle_num=$((existing_cycles + 1))
cycle_dir="${PROJECT_ROOT}/.craft/cycles/${cycle_num}-${CYCLE_NAME}"

# Format title with cycle number (e.g., "Cycle 08: Stability & Quality")
CYCLE_TITLE="Cycle $(printf '%02d' $cycle_num): $CYCLE_TITLE"

# Create cycle directory
mkdir -p "$cycle_dir/stories"

# Get current date
DATE=$(date +%Y-%m-%d)

# Escape sed special characters (& and \) in variables used in replacement strings
escape_sed() { printf '%s' "$1" | sed 's/[&\\]/\\&/g'; }
CYCLE_NAME_ESC=$(escape_sed "$CYCLE_NAME")
CYCLE_TITLE_ESC=$(escape_sed "$CYCLE_TITLE")
CYCLE_TARGET_ESC=$(escape_sed "$CYCLE_TARGET")
SOURCE_CONCEPT_YAML_ESC=$(escape_sed "$SOURCE_CONCEPT_YAML")

# Create cycle.yaml from template
if [ -f "$TEMPLATES_DIR/cycle.yaml" ]; then
  sed -e "s|{{CYCLE_NAME}}|$CYCLE_NAME_ESC|g" \
      -e "s|{{CYCLE_TITLE}}|$CYCLE_TITLE_ESC|g" \
      -e "s|{{DATE}}|$DATE|g" \
      -e "s|{{CYCLE_TARGET}}|$CYCLE_TARGET_ESC|g" \
      -e "s|{{CYCLE_FOCUS}}|TBD|g" \
      -e "s|{{GOAL_1}}|TBD|g" \
      -e "s|{{SOURCE_CONCEPT}}|$SOURCE_CONCEPT_YAML_ESC|g" \
    "$TEMPLATES_DIR/cycle.yaml" > "$cycle_dir/cycle.yaml"
else
  # Fallback: create minimal cycle.yaml
  cat > "$cycle_dir/cycle.yaml" << EOF
name: $CYCLE_NAME
title: "$CYCLE_TITLE"
status: planning
created: $DATE
updated: $DATE
target: $CYCLE_TARGET
focus: TBD
source_concept: $SOURCE_CONCEPT_YAML

goals:
  - TBD
EOF
fi

# Create .state from template
if [ -f "$TEMPLATES_DIR/cycle-state" ]; then
  sed "s|{{CYCLE_NAME}}|$CYCLE_NAME_ESC|g" "$TEMPLATES_DIR/cycle-state" > "$cycle_dir/.state"
else
  # Fallback: create minimal .state
  cat > "$cycle_dir/.state" << EOF
# Cycle State
CYCLE_NAME="$CYCLE_NAME"
CYCLE_STATUS="planning"
CURRENT_STORY=""
CURRENT_CHUNK=0
TOTAL_CHUNKS=0
LAST_VALIDATION=""
LAST_CHECKPOINT=""
EOF
fi

# Ensure project-wide learnings file exists (create if missing)
if [ ! -f "${PROJECT_ROOT}/.craft/.learnings.yaml" ]; then
  cat > "${PROJECT_ROOT}/.craft/.learnings.yaml" << EOF
# Project learnings - captured during implementation
# Processed at cycle-complete into harness updates
# Schema matches craft-story-implement.md canonical format

conventions: []
enforcements: []
behaviors: []
automations: []
skills: []
workflows: []
EOF
fi

echo "$cycle_dir"
