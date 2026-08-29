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

# File mtime, portable. Linux-tool-first with an empty-check fallback: GNU's
# `stat -f %m FILE` is NOT a clean failure - it dumps a filesystem report to
# stdout before the || fallback fires, so a mac-first || chain captures garbage
# on Linux. BSD stat -c fails with empty stdout, so this order is safe both ways.
mtime_of() {
  local t
  t=$(stat -c %Y "$1" 2>/dev/null)
  [ -n "$t" ] || t=$(stat -f %m "$1" 2>/dev/null)
  printf '%s' "$t"
}

# Resolve project root for state checks
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/find-workshop.sh" 2>/dev/null || exit 0

if [ -z "$PROJECT_ROOT" ] || [ ! -d "${PROJECT_ROOT}.craft" ]; then
  exit 0
fi

# Load craft state once so every layer can speak the full status line
CYCLE_TITLE=""; ACTIVE_CYCLE=""; CURRENT_STORY=""; CURRENT_CHUNK=""; TOTAL_CHUNKS=""
[ -f "${PROJECT_ROOT}.craft/.global-state" ] && source "${PROJECT_ROOT}.craft/.global-state"
CYCLE_STATE_FILE="${PROJECT_ROOT}.craft/cycles/${ACTIVE_CYCLE}/.state"
[ -n "$ACTIVE_CYCLE" ] && [ -f "$CYCLE_STATE_FILE" ] && source "$CYCLE_STATE_FILE"
if [ -n "$ACTIVE_CYCLE" ] && [ -f "${PROJECT_ROOT}.craft/cycles/${ACTIVE_CYCLE}/cycle.yaml" ]; then
  CYCLE_TITLE=$(grep "^title:" "${PROJECT_ROOT}.craft/cycles/${ACTIVE_CYCLE}/cycle.yaml" 2>/dev/null | sed 's/title: *//' | tr -d '"')
fi
[ -z "$CYCLE_TITLE" ] && CYCLE_TITLE="$ACTIVE_CYCLE"

# Progress dial: quarter-rounded COMPLETED chunks (CURRENT_CHUNK is the one in
# progress, so completed = CURRENT_CHUNK - 1). ◔ floor while work is in motion -
# the dial never shows empty on an active story; ○ is reserved for set-down.
dial_glyph() {
  local done=$(( ${CURRENT_CHUNK:-1} - 1 )) total=${TOTAL_CHUNKS:-0} q
  if ! [ "$total" -gt 0 ] 2>/dev/null; then printf '◔'; return; fi
  q=$(( done * 4 / total ))
  case $q in
    0|1) printf '◔' ;;
    2)   printf '◑' ;;
    3)   printf '◕' ;;
    *)   printf '●' ;;
  esac
}

# The "Crafting" lead: brand verb + story + cycle + position, only while in motion
crafting_prefix() {
  if [ -n "$CURRENT_STORY" ]; then
    printf '%s Crafting: %s · [%s] · chunk %s of %s' \
      "$(dial_glyph)" "$CURRENT_STORY" "$CYCLE_TITLE" "${CURRENT_CHUNK:-?}" "${TOTAL_CHUNKS:-?}"
  else
    printf '◔ Crafting'
  fi
}

# Write gate: read the live value every stop - the same variable every gate
# open/close writes through update-global-state.sh (sourced above).
gate_open() { [ "${CRAFT_WRITE_ENABLED:-}" = "true" ]; }

# Set-down lines carry the forgotten-gate warning only while the gate is open
GATE_SUFFIX=""
gate_open && GATE_SUFFIX=" · ⚠ write gate open"

# Adhoc flavor: which records folder got a file since the gate opened -
# the word only, never a record name. Ambiguous or none: plain Adhoc.
gate_flavor() {
  local marker="${PROJECT_ROOT}.craft/.active-fix" f t
  [ -f "$marker" ] || { printf 'Adhoc'; return; }
  f=$(find "${PROJECT_ROOT}.craft/fixes" -name '*.md' -newer "$marker" 2>/dev/null | head -1)
  t=$(find "${PROJECT_ROOT}.craft/tweaks" -name '*.md' -newer "$marker" 2>/dev/null | head -1)
  if [ -n "$t" ] && [ -z "$f" ]; then printf 'Tweak'
  elif [ -n "$f" ] && [ -z "$t" ]; then printf 'Fix'
  else printf 'Adhoc'; fi
}

# --- Layer 0: Breadcrumb continuation ---
# If a skill left a breadcrumb before invoking a nested skill,
# block the stop and inject the continuation instruction.
# Breadcrumbs are one-shot (deleted after reading) with a 30-min TTL.
BREADCRUMB="${PROJECT_ROOT}.craft/.continuation"
if [ -f "$BREADCRUMB" ]; then
  CRUMB_AGE=$(($(date +%s) - $(mtime_of "$BREADCRUMB")))
  if [ "$CRUMB_AGE" -lt 1800 ]; then
    ACTION=$(grep '^ACTION:' "$BREADCRUMB" | sed 's/^ACTION: //' | tr -d '"')
    SKILL=$(grep '^SKILL:' "$BREADCRUMB" | sed 's/^SKILL: //')
    ARGS=$(grep '^ARGS:' "$BREADCRUMB" | sed 's/^ARGS: //')
    rm -f "$BREADCRUMB"
    if [ -n "$SKILL" ]; then
      echo "{\"systemMessage\": \"$(crafting_prefix) · handing off → ${SKILL} · ${ACTION}\"}"
    else
      echo "{\"systemMessage\": \"$(crafting_prefix) · mid-handoff · ${ACTION}\"}"
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
          MARKER_AGE=$(($(date +%s) - $(mtime_of "$CHUNK_MARKER")))
          if [ "$MARKER_AGE" -lt 120 ]; then
            # Second stop within 2 minutes — allow it (prevents infinite loops)
            rm -f "$CHUNK_MARKER"
            echo "{\"systemMessage\": \"○ ${CURRENT_STORY} set down · [${CYCLE_TITLE}] · chunk ${CURRENT_CHUNK} of ${TOTAL_CHUNKS} · /craft:story-continue${GATE_SUFFIX}\"}"
            exit 0
          fi
        fi

        # First stop attempt — status stamp (the pulse line)
        touch "$CHUNK_MARKER"
        echo "{\"systemMessage\": \"$(crafting_prefix)\"}"
        exit 0
      fi
    fi
  fi
fi

# --- Layer 2: Active story persistence warning ---
# No chunks in progress, but story is active — warn user

# Adhoc rail: an open gate with no active story stamps every stop,
# bypassing the warn-once marker - the rail must never be suppressed.
if gate_open && [ -z "$CURRENT_STORY" ]; then
  if [ -f "${PROJECT_ROOT}.craft/.active-fix" ]; then
    echo "{\"systemMessage\": \"◔ $(gate_flavor) in flight · ⚠ write gate open\"}"
  else
    echo "{\"systemMessage\": \"⚠ write gate open · unclaimed\"}"
  fi
  exit 0
fi

MARKER_FILE="/tmp/craft-stop-suggested-${SESSION_ID}"

# Check if marker exists and is recent (less than 5 minutes old)
if [[ -f "$MARKER_FILE" ]]; then
  MARKER_AGE=$(($(date +%s) - $(mtime_of "$MARKER_FILE")))
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
    echo "{\"systemMessage\": \"○ ${CURRENT_STORY} set down · [${CYCLE_TITLE}] · /craft:story-continue${GATE_SUFFIX}\"}"
    exit 0
  fi
fi

exit 0
