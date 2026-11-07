#!/bin/bash
# get-latest-cycle.sh — Get the highest-numbered cycle and its status
# Usage: get-latest-cycle.sh [project-root] [--status=<s>]
#   --status=<s>  pick the highest-numbered cycle whose cycle.yaml status
#                 equals <s> exactly (flag may come before or after the root)
#
# Output: key=value pairs for the most recent cycle
#   LATEST_CYCLE=45-hero-card-share
#   CYCLE_TITLE="Cycle 45: Share + Signature Moments"
#     (the title is printed verbatim, so it may itself hold quotes: the value
#      runs from the first " to the last " on the line)
#   CYCLE_STATUS=planning
#   STORIES_TOTAL=2
#   STORIES_READY=2
#   STORIES_COMPLETE=0
#   STORIES_PLANNING=0
#
# If no cycles exist (or none match --status), outputs LATEST_CYCLE=""

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/read-key.sh"

PROJECT="."
WANT_STATUS=""
HAS_FILTER=0
for arg in "$@"; do
  case "$arg" in
    --status=*) WANT_STATUS="${arg#--status=}"; HAS_FILTER=1 ;;
    *) PROJECT="$arg" ;;
  esac
done
# An explicit empty root means the current directory, as ${1:-.} did before the flag.
if [ -z "$PROJECT" ]; then PROJECT="."; fi
CYCLES_DIR="$PROJECT/.craft/cycles"

if [ ! -d "$CYCLES_DIR" ]; then
  echo 'LATEST_CYCLE=""'
  exit 0
fi

# Get the highest-numbered cycle directory
# ls directories, sort by leading number, take the last one
SORTED=$(ls -d "$CYCLES_DIR"/*/ 2>/dev/null | sed 's|.*/\([^/]*\)/$|\1|' | sort -t'-' -k1 -n)

if [ "$HAS_FILTER" -eq 1 ]; then
  # Walk newest to oldest; a cycle.yaml without a status line is skipped
  LATEST=""
  while IFS= read -r folder; do
    [ -z "$folder" ] && continue
    yaml="$CYCLES_DIR/$folder/cycle.yaml"
    [ -f "$yaml" ] || continue
    folder_status=$(grep "^status:" "$yaml" | head -1 | awk '{print $2}' || true)
    if [ "$folder_status" = "$WANT_STATUS" ]; then
      LATEST="$folder"
      break
    fi
  done <<< "$(echo "$SORTED" | sed '1!G;h;$!d')"
else
  LATEST=$(echo "$SORTED" | tail -1)
fi

if [ -z "$LATEST" ]; then
  echo 'LATEST_CYCLE=""'
  exit 0
fi

CYCLE_YAML="$CYCLES_DIR/$LATEST/cycle.yaml"
STORIES_DIR="$CYCLES_DIR/$LATEST/stories"

echo "LATEST_CYCLE=\"$LATEST\""

# Read cycle.yaml for title and status
if [ -f "$CYCLE_YAML" ]; then
  TITLE=$(read_key "$CYCLE_YAML" title)
  STATUS=$(grep "^status:" "$CYCLE_YAML" | head -1 | awk '{print $2}')
  echo "CYCLE_TITLE=\"$TITLE\""
  echo "CYCLE_STATUS=\"$STATUS\""
else
  echo 'CYCLE_TITLE=""'
  echo 'CYCLE_STATUS=""'
fi

# Count stories by status
if [ -d "$STORIES_DIR" ]; then
  TOTAL=$(ls "$STORIES_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
  READY=$(grep -l "^status: ready" "$STORIES_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
  COMPLETE=$(grep -l "^status: complete" "$STORIES_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
  PLANNING=$(grep -l "^status: planning" "$STORIES_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "STORIES_TOTAL=\"$TOTAL\""
  echo "STORIES_READY=\"$READY\""
  echo "STORIES_COMPLETE=\"$COMPLETE\""
  echo "STORIES_PLANNING=\"$PLANNING\""
else
  echo 'STORIES_TOTAL="0"'
  echo 'STORIES_READY="0"'
  echo 'STORIES_COMPLETE="0"'
  echo 'STORIES_PLANNING="0"'
fi
