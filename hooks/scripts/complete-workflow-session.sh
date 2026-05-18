#!/bin/bash
# complete-workflow-session.sh — Transition: Validate and complete a workflow session
# Usage: complete-workflow-session.sh <session-path> [definition-path]
#
# session-path: path to the session directory
# definition-path: optional path to the workflow definition.md (for artifact verification)
#
# Format: stages-v1 (hybrid) - Progress table + per-stage checklist sections in session.md
#
# Runs validation, writes ## Validation section, sets status: complete.

set -e

SESSION_DIR="$1"
DEFINITION_FILE="$2"

if [ -z "$SESSION_DIR" ]; then
  echo "Error: session path required"
  echo "Usage: complete-workflow-session.sh <session-dir> [definition-path]"
  exit 1
fi

# Resolve relative paths
if [[ "$SESSION_DIR" != /* ]]; then
  SESSION_DIR="$PWD/$SESSION_DIR"
fi

SESSION_FILE="$SESSION_DIR/session.md"

if [ ! -f "$SESSION_FILE" ]; then
  echo "Error: session.md not found at $SESSION_FILE"
  exit 1
fi

TODAY=$(date +%Y-%m-%d)

WORKFLOW_DIR="$(dirname "$(dirname "$SESSION_DIR")")"

# Count stages from Progress table
TOTAL_STAGES=$(awk '/^\| [0-9]/' "$SESSION_FILE" | wc -l | tr -d ' ')
COMPLETE_STAGES=$(awk '/^\| [0-9]/' "$SESSION_FILE" | grep -c 'complete' || echo "0")
SKIPPED_STAGES=$(awk '/^\| [0-9]/' "$SESSION_FILE" | grep -c 'skipped' || echo "0")
PENDING_STAGES=$(awk '/^\| [0-9]/' "$SESSION_FILE" | grep -c 'pending' || echo "0")
ACTIVE_STAGES=$(awk '/^\| [0-9]/' "$SESSION_FILE" | grep -c 'active' || echo "0")

# Checklist items are per-session in the hybrid format
TOTAL_ITEMS=$(grep -c '^- \[' "$SESSION_FILE" || echo "0")
CHECKED_ITEMS=$(grep -c '^- \[x\]' "$SESSION_FILE" || echo "0")
UNCHECKED_ITEMS=$(grep -c '^- \[ \]' "$SESSION_FILE" || echo "0")

# Collect issues from ## Stage headings with status tags
ISSUES=""
ISSUE_COUNT=0

# Check for incomplete stages
if [ "$PENDING_STAGES" -gt 0 ]; then
  STAGES_PENDING=$(grep '^## Stage.*\[pending\]' "$SESSION_FILE" | sed 's/## //' || true)
  while IFS= read -r stage; do
    ISSUES="${ISSUES}\n- [ ] $stage never ran"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
  done <<< "$STAGES_PENDING"
fi

if [ "$ACTIVE_STAGES" -gt 0 ]; then
  STAGES_ACTIVE=$(grep '^## Stage.*\[active\]' "$SESSION_FILE" | sed 's/## //' || true)
  while IFS= read -r stage; do
    ISSUES="${ISSUES}\n- [ ] $stage still marked active (not completed)"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
  done <<< "$STAGES_ACTIVE"
fi

# Check for unchecked items on completed stages
if [ "$UNCHECKED_ITEMS" -gt 0 ]; then
  CURRENT_STAGE=""
  while IFS= read -r line; do
    if [[ "$line" == "## Stage"*"[complete]"* ]]; then
      CURRENT_STAGE=$(echo "$line" | sed 's/## //')
    elif [[ "$line" == "## Stage"* ]]; then
      CURRENT_STAGE=""
    elif [[ "$line" == "- [ ]"* ]] && [ -n "$CURRENT_STAGE" ]; then
      ITEM_TEXT=$(echo "$line" | sed 's/^- \[ \] //')
      ISSUES="${ISSUES}\n- [ ] Unchecked on completed stage: $ITEM_TEXT ($CURRENT_STAGE)"
      ISSUE_COUNT=$((ISSUE_COUNT + 1))
    fi
  done < "$SESSION_FILE"
fi

# Check for skipped stages
if [ "$SKIPPED_STAGES" -gt 0 ]; then
  STAGES_SKIPPED=$(grep '^## Stage.*\[skipped\]' "$SESSION_FILE" | sed 's/## //' || true)
  while IFS= read -r stage; do
    ISSUES="${ISSUES}\n- [ ] $stage was skipped"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
  done <<< "$STAGES_SKIPPED"
fi

# Verify artifacts/ directory has expected output files
ARTIFACTS_DIR="$SESSION_DIR/artifacts"
if [ -d "$ARTIFACTS_DIR" ]; then
  for stage_file in "$WORKFLOW_DIR/stages/"*.md; do
    [ -f "$stage_file" ] || continue
    stage_exec=$(awk '/^---$/{n++; next} n==1 && /^execution:/{print $2; exit}' "$stage_file")
    stage_produces=$(awk '/^---$/{n++; next} n==1 && /^produces:/{gsub(/^produces: *"?/, ""); gsub(/"$/, ""); print; exit}' "$stage_file")
    stage_num=$(awk '/^---$/{n++; next} n==1 && /^stage:/{print $2; exit}' "$stage_file")

    # For non-manual stages with produces: set, check artifact exists
    if [ "$stage_exec" != "manual" ] && [ -n "$stage_produces" ] && [ "$stage_produces" != '""' ] && [ "$stage_produces" != "''" ]; then
      artifact_found=$(ls "$ARTIFACTS_DIR/$(printf "%02d" "$stage_num")-"*.md 2>/dev/null | head -1)
      [ -z "$artifact_found" ] && artifact_found=$(ls "$ARTIFACTS_DIR/${stage_num}-"*.md 2>/dev/null | head -1)
      if [ -z "$artifact_found" ]; then
        stage_name=$(awk '/^---$/{n++; next} n==1 && /^name:/{gsub(/^name: */, ""); print; exit}' "$stage_file")
        ISSUES="${ISSUES}\n- [ ] Missing artifact for Stage $stage_num: $stage_name (expected in artifacts/)"
        ISSUE_COUNT=$((ISSUE_COUNT + 1))
      fi
    fi
  done
fi

# Determine validation status
if [ "$ISSUE_COUNT" -eq 0 ]; then
  VAL_STATUS="clean"
else
  VAL_STATUS="passed-with-issues"
fi

# Remove any existing Validation section (in case of re-run)
sed -i.bak '/^## Validation$/,$ d' "$SESSION_FILE"
rm -f "$SESSION_FILE.bak"

# Append Validation section
{
  echo ""
  echo "## Validation"
  echo "status: $VAL_STATUS"
  echo "checked: $TODAY"
  echo ""
  if [ "$ISSUE_COUNT" -gt 0 ]; then
    echo "### Issues"
    echo -e "$ISSUES"
    echo ""
  fi
  echo "### Summary"
  echo "Stages: $COMPLETE_STAGES/$TOTAL_STAGES complete, $SKIPPED_STAGES skipped"
  echo "Checklist: $CHECKED_ITEMS/$TOTAL_ITEMS items checked"
  if [ "$ISSUE_COUNT" -eq 0 ]; then
    echo "All stages complete. All artifacts present. All items checked."
  fi
} >> "$SESSION_FILE"

# Update frontmatter: status -> complete, completed -> today
sed -i.bak "s/^status:.*/status: complete/" "$SESSION_FILE"
sed -i.bak "s/^completed:.*/completed: $TODAY/" "$SESSION_FILE"
rm -f "$SESSION_FILE.bak"

# Clear CURRENT_WORKFLOW_SESSION in .global-state
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/update-global-state.sh" CURRENT_WORKFLOW_SESSION ""

# Print report to stdout
echo ""
echo "=== Session Validation ==="
SESSION_NAME=$(awk '/^name:/{gsub(/^name: */, ""); print; exit}' "$SESSION_FILE")
echo "$SESSION_NAME"
echo ""

if [ "$ISSUE_COUNT" -eq 0 ]; then
  echo "CLEAN - all stages complete, all items checked."
else
  echo "$ISSUE_COUNT issues found:"
  echo -e "$ISSUES" | grep -v '^$'
  echo ""
  echo "Issues tracked in session file."
fi

echo ""
echo "Stages: $COMPLETE_STAGES/$TOTAL_STAGES complete, $SKIPPED_STAGES skipped"
echo "Checklist: $CHECKED_ITEMS/$TOTAL_ITEMS items checked"
echo "Status: complete"
