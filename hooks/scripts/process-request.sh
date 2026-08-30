#!/bin/bash
# Process-request: Move a request file to .craft/requests/processed/
# Usage: process-request.sh <request-file> <outcome-type> <outcome-name> [project-root]
#   outcome-type: "story" or "cycle"
#   outcome-name: the story/cycle name that was created
#
# Appends a processing comment to the file before moving.
# Creates processed/ directory if it doesn't exist.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REQUEST_FILE="$1"
OUTCOME_TYPE="$2"
OUTCOME_NAME="$3"
PROJECT_ROOT="${4:-.}"

PROJECT_ROOT="${PROJECT_ROOT%/}"

if [ -z "$REQUEST_FILE" ] || [ -z "$OUTCOME_TYPE" ] || [ -z "$OUTCOME_NAME" ]; then
  echo "Error: request file, outcome type, and outcome name required"
  echo "Usage: process-request.sh <request-file> <outcome-type> <outcome-name> [project-root]"
  exit 1
fi

if [ ! -f "$REQUEST_FILE" ]; then
  echo "Error: Request file not found: $REQUEST_FILE"
  exit 1
fi

# Ensure processed directory exists
PROCESSED_DIR="${PROJECT_ROOT}/.craft/requests/processed"
mkdir -p "$PROCESSED_DIR"

# Append processing reference to the file
DATE=$(date +%Y-%m-%dT%H:%M:%S%z)
echo "" >> "$REQUEST_FILE"
echo "<!-- Processed: $DATE | $OUTCOME_TYPE: $OUTCOME_NAME -->" >> "$REQUEST_FILE"

# Move to processed directory
FILENAME=$(basename "$REQUEST_FILE")
mv "$REQUEST_FILE" "$PROCESSED_DIR/$FILENAME"

# Refresh the dashboard graph data. Silenced so callers still read this
# script's own final line; guarded so a missing wrapper never fails a flow.
bash "$SCRIPT_DIR/../../scripts/dashboard/dashboard-run.sh" --root "$PROJECT_ROOT" >/dev/null 2>&1 || true

echo "$PROCESSED_DIR/$FILENAME"
