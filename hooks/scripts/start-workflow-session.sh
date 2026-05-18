#!/bin/bash
# start-workflow-session.sh — Transition: Set a workflow session to active
# Usage: start-workflow-session.sh <session-path>
#
# session-path: path to the session directory (e.g., .craft/workflows/write-lesson/sessions/2026-04-10-mcp-u1-l3)
#
# Updates:
# - session.md frontmatter: status -> active, current_stage -> 1
# - Stage 1 heading: [pending] -> [active]
# - .global-state: CURRENT_WORKFLOW_SESSION -> session path (for compaction recovery)

set -e

SESSION_DIR="$1"

if [ -z "$SESSION_DIR" ]; then
  echo "Error: session path required"
  echo "Usage: start-workflow-session.sh <session-dir>"
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

# Guard: only one active session per workflow
SESSIONS_DIR="$(dirname "$SESSION_DIR")"
THIS_SESSION="$(basename "$SESSION_DIR")"

for SIBLING in "$SESSIONS_DIR"/*/session.md; do
  [ -f "$SIBLING" ] || continue
  SIBLING_DIR="$(basename "$(dirname "$SIBLING")")"
  [ "$SIBLING_DIR" = "$THIS_SESSION" ] && continue
  if awk '/^---$/{n++; next} n==1 && /^status:/{print $2; exit}' "$SIBLING" | grep -q "^active$"; then
    echo "Error: session '$SIBLING_DIR' is already active in this workflow."
    echo "Complete or pause it before starting another."
    exit 1
  fi
done

# Guard: don't re-activate an already-active session (would reset current_stage to 1)
CURRENT_STATUS=$(awk '/^---$/{n++; next} n==1 && /^status:/{print $2; exit}' "$SESSION_FILE")
if [ "$CURRENT_STATUS" = "active" ]; then
  echo "Error: session '$(basename "$SESSION_DIR")' is already active."
  echo "Use /craft:workflow-run continue to resume it."
  exit 1
fi

# Update frontmatter: status -> active, current_stage -> 1
sed -i.bak "s/^status:.*/status: active/" "$SESSION_FILE"
sed -i.bak "s/^current_stage:.*/current_stage: 1/" "$SESSION_FILE"

# Inject session_dir into variables if missing
if ! grep -q '^  session_dir:' "$SESSION_FILE" 2>/dev/null; then
  # Insert session_dir after the variables: line
  sed -i.bak "/^variables:/a\\
  session_dir: \"$SESSION_DIR\"" "$SESSION_FILE"
  rm -f "$SESSION_FILE.bak"
fi

# Mark Stage 1 as active in Progress table + checklist section
awk '
  /^\| 1 / {
    gsub(/pending/, "active")
  }
  { print }
' "$SESSION_FILE" > "$SESSION_FILE.tmp" && mv "$SESSION_FILE.tmp" "$SESSION_FILE"
sed -i.bak -E "s/(## Stage 1:.*)\[pending\]/\1[active]/" "$SESSION_FILE"

rm -f "$SESSION_FILE.bak"

# Set CURRENT_WORKFLOW_SESSION in .global-state for compaction recovery
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/update-global-state.sh" CURRENT_WORKFLOW_SESSION "$SESSION_DIR"

echo "Session activated: $(grep '^name:' "$SESSION_FILE" | sed 's/name: *//')"
echo "Starting at Stage 1."
