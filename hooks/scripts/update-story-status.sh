#!/bin/bash
# Update-story-status: Change a story's status in frontmatter
# Usage: update-story-status.sh <story-file> <new-status>
# Statuses: backlog, planning, ready, active, complete
#
# Updates story frontmatter only. No cycle.yaml manipulation.
# Story counts are derived from directory scan, not stored.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STORY_FILE="$1"
NEW_STATUS="$2"

if [ -z "$STORY_FILE" ] || [ -z "$NEW_STATUS" ]; then
  echo "Error: Story file and status required"
  echo "Usage: update-story-status.sh <story-file> <status>"
  echo "Statuses: backlog, planning, ready, active, complete"
  exit 1
fi

# Convert relative paths to absolute using PWD
if [[ "$STORY_FILE" != /* ]]; then
  STORY_FILE="$PWD/$STORY_FILE"
fi

if [ ! -f "$STORY_FILE" ]; then
  echo "Error: Story file not found: $STORY_FILE"
  exit 1
fi

# Validate status
case "$NEW_STATUS" in
  backlog|planning|ready|active|complete) ;;
  *)
    echo "Error: Invalid status '$NEW_STATUS'"
    echo "Valid statuses: backlog, planning, ready, active, complete"
    exit 1
    ;;
esac

DATE=$(date +%Y-%m-%d)

# Update story frontmatter
sed -i.bak "s/^status:.*/status: $NEW_STATUS/" "$STORY_FILE"
sed -i.bak "s/^updated:.*/updated: $DATE/" "$STORY_FILE"
rm -f "$STORY_FILE.bak"

# Derive the project root from the record's own path - never from the
# session environment, which can point at the wrong sub-project in a
# monorepo. A separate variable: the record path variable is echoed back to
# callers in the caller's own spelling and must not be rewritten.
_DASH_ABS="$STORY_FILE"
if [[ "$_DASH_ABS" != /* ]]; then
  _DASH_ABS="$PWD/$_DASH_ABS"
fi
DASHBOARD_ROOT=$(echo "$_DASH_ABS" | sed 's|/.craft/.*||')
if [ ! -d "$DASHBOARD_ROOT/.craft" ]; then
  DASHBOARD_ROOT="."
fi
# Refresh the dashboard graph data. Silenced so callers still read this
# script's own final line; guarded so a missing wrapper never fails a flow.
bash "$SCRIPT_DIR/../../scripts/dashboard/dashboard-run.sh" --root "${DASHBOARD_ROOT:-.}" >/dev/null 2>&1 || true

echo "Story status updated to '$NEW_STATUS': $STORY_FILE"
