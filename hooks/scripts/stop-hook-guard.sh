#!/bin/bash
# Guard script for Stop hook
# Layer 0: Block stops when a skill breadcrumb (.craft/.continuation) is active (30-min TTL)
# Layer 1: Block premature stops during mid-chunk implementation (2-min retry window)
# Layer 2: Warn about active story persistence

set -e

# Read stdin for hook input
INPUT=$(cat)

# Check stop_hook_active to prevent infinite loops
STOP_HOOK_ACTIVE=$(echo "$INPUT" | grep -o '"stop_hook_active":\s*true' 2>/dev/null || true)
if [ -n "$STOP_HOOK_ACTIVE" ]; then
  exit 0
fi

# Use working directory hash as session identifier.
# Linux-tool-first with an empty-check fallback: a piped fallback after || can
# never fire (a pipeline's exit status is its last command's), so md5-less
# machines would silently get an empty SESSION_ID.
SESSION_ID=$(echo "$PWD" | md5sum 2>/dev/null | cut -c1-8)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(echo "$PWD" | md5 2>/dev/null | cut -c1-8)
fi

# Resolve project root for state checks
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/find-workshop.sh" 2>/dev/null || exit 0

if [ -z "$PROJECT_ROOT" ] || [ ! -d "${PROJECT_ROOT}.craft" ]; then
  exit 0
fi

# --- Layer 0: Breadcrumb continuation ---
# If a skill left a breadcrumb before invoking a nested skill,
# block the stop and inject the continuation instruction.
# Breadcrumbs are one-shot (deleted after reading) with a 30-min TTL.
BREADCRUMB="${PROJECT_ROOT}.craft/.continuation"
if [ -f "$BREADCRUMB" ]; then
  CRUMB_AGE=$(($(date +%s) - $(stat -f %m "$BREADCRUMB" 2>/dev/null || stat -c %Y "$BREADCRUMB" 2>/dev/null)))
  if [ "$CRUMB_AGE" -lt 1800 ]; then
    ACTION=$(grep '^ACTION:' "$BREADCRUMB" | sed 's/^ACTION: //')
    SKILL=$(grep '^SKILL:' "$BREADCRUMB" | sed 's/^SKILL: //')
    ARGS=$(grep '^ARGS:' "$BREADCRUMB" | sed 's/^ARGS: //')
    rm -f "$BREADCRUMB"
    if [ -n "$SKILL" ] && [ -n "$ARGS" ]; then
      echo "{\"systemMessage\": \"BLOCKED: You tried to stop mid-chain. ${ACTION}\\n\\nEXECUTE NOW: Invoke the Skill tool with skill=\\\"${SKILL}\\\" and args=\\\"${ARGS}\\\"\\n\\nThis is not optional. The story is incomplete. Output ONLY the Skill tool call — no text, no summary, no explanation.\"}"
    else
      echo "{\"systemMessage\": \"BLOCKED: You tried to stop mid-chain. ${ACTION}\\n\\nContinue IMMEDIATELY. Output ONLY the next tool call — no text, no summary, no explanation.\"}"
    fi
    exit 0
  else
    # Stale breadcrumb (>30min) — clean up and fall through
    rm -f "$BREADCRUMB"
  fi
fi

# --- Layer 1: Chunk-aware continuation guard ---
# If we're mid-implementation (chunks remaining), block premature stops
# with a continuation instruction. Allow on second attempt within 2 minutes.

if [ -f "${PROJECT_ROOT}.craft/.global-state" ]; then
  source "${PROJECT_ROOT}.craft/.global-state"

  if [ -n "$ACTIVE_CYCLE" ] && [ -n "$CURRENT_STORY" ]; then
    CYCLE_STATE="${PROJECT_ROOT}.craft/cycles/${ACTIVE_CYCLE}/.state"

    if [ -f "$CYCLE_STATE" ]; then
      source "$CYCLE_STATE"

      # Check if we're mid-implementation: chunk > 0 and chunk <= total
      if [ "${CURRENT_CHUNK:-0}" -gt 0 ] 2>/dev/null && [ "${TOTAL_CHUNKS:-0}" -gt 0 ] 2>/dev/null && [ "${CURRENT_CHUNK:-0}" -le "${TOTAL_CHUNKS:-0}" ] 2>/dev/null; then
        CHUNK_MARKER="/tmp/craft-chunk-continue-${SESSION_ID}"

        # Check if we already tried to continue recently (2-minute window)
        if [ -f "$CHUNK_MARKER" ]; then
          MARKER_AGE=$(($(date +%s) - $(stat -f %m "$CHUNK_MARKER" 2>/dev/null || stat -c %Y "$CHUNK_MARKER" 2>/dev/null)))
          if [ "$MARKER_AGE" -lt 120 ]; then
            # Second stop within 2 minutes — allow it (prevents infinite loops)
            rm -f "$CHUNK_MARKER"
            echo "{\"systemMessage\": \"Stopping mid-implementation. Story '${CURRENT_STORY}' chunk ${CURRENT_CHUNK}/${TOTAL_CHUNKS} in progress. Use /craft:story-continue to resume.\"}"
            exit 0
          fi
        fi

        # First stop attempt — inject continuation instruction
        touch "$CHUNK_MARKER"
        echo "{\"systemMessage\": \"BLOCKED: You tried to stop mid-implementation (chunk ${CURRENT_CHUNK}/${TOTAL_CHUNKS} of '${CURRENT_STORY}'). The validate-chunk skill told you the next action. Execute it NOW — checkpoint, implementer agent, validate-chunk. Output ONLY the next tool call.\"}"
        exit 0
      fi
    fi
  fi
fi

# --- Layer 2: Active story persistence warning ---
# No chunks in progress, but story is active — warn user

MARKER_FILE="/tmp/craft-stop-suggested-${SESSION_ID}"

# Check if marker exists and is recent (less than 5 minutes old)
if [[ -f "$MARKER_FILE" ]]; then
  MARKER_AGE=$(($(date +%s) - $(stat -f %m "$MARKER_FILE" 2>/dev/null || stat -c %Y "$MARKER_FILE" 2>/dev/null)))
  if [[ $MARKER_AGE -lt 300 ]]; then
    # Already suggested recently, allow stop
    exit 0
  fi
fi

# First time or marker expired - create/update marker
touch "$MARKER_FILE"

if [ -f "${PROJECT_ROOT}.craft/.global-state" ]; then
  source "${PROJECT_ROOT}.craft/.global-state"
  if [ -n "$CURRENT_STORY" ]; then
    echo "{\"systemMessage\": \"Active story '${CURRENT_STORY}' will persist. Use /craft:story-continue to resume.\"}"
    exit 0
  fi
fi

exit 0
