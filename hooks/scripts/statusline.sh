#!/bin/bash
# Statusline: Generate the status line content
# Format: [cycle] status story | chunk X/Y | ctx% | $cost

set -e

# Require jq for JSON parsing
if ! command -v jq &> /dev/null; then
  exit 0
fi

# Read input from Claude (includes cost, token info)
input=$(cat)
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Extract token usage for context percentage
input_tokens=$(echo "$input" | jq -r '.tokenUsage.input // 0')
context_limit=$(echo "$input" | jq -r '.tokenUsage.contextLimit // 200000')

# Calculate context percentage
if [ "$context_limit" -gt 0 ] 2>/dev/null; then
  ctx_pct=$((input_tokens * 100 / context_limit))
else
  ctx_pct=0
fi

# Context warning indicator
if [ "$ctx_pct" -gt 80 ]; then
  ctx_indicator="🔴${ctx_pct}%"
elif [ "$ctx_pct" -gt 60 ]; then
  ctx_indicator="🟡${ctx_pct}%"
else
  ctx_indicator="${ctx_pct}%"
fi

# Resolve project root (CRAFT_PROJECT_ROOT set by session-start, or find-workshop.sh fallback)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Without the helper the status line shows the cycle slug instead of failing
if [ -f "$SCRIPT_DIR/read-key.sh" ]; then
  source "$SCRIPT_DIR/read-key.sh"
else
  read_key() { return 0; }
fi
if [ -n "$CRAFT_PROJECT_ROOT" ]; then
  ROOT="${CRAFT_PROJECT_ROOT%/}"
else
  source "$SCRIPT_DIR/find-workshop.sh" 2>/dev/null || true
  ROOT="${PROJECT_ROOT%/}"
fi

# Default output if no Craft state
if [ -z "$ROOT" ] || [ ! -f "$ROOT/.craft/.global-state" ]; then
  printf "No active cycle | %s | \$%.2f" "$ctx_indicator" "$cost"
  exit 0
fi

source "$ROOT/.craft/.global-state"

if [ -z "$ACTIVE_CYCLE" ]; then
  # Check backlog count
  backlog_count=$(ls -1 "$ROOT/.craft/backlog/"*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$backlog_count" -gt 0 ]; then
    printf "Backlog: %d stories | %s | \$%.2f" "$backlog_count" "$ctx_indicator" "$cost"
  else
    printf "No active cycle | %s | \$%.2f" "$ctx_indicator" "$cost"
  fi
  exit 0
fi

# Get cycle display name (prefer title from yaml, fall back to slug)
cycle_name=""
if [ -f "$ROOT/.craft/cycles/$ACTIVE_CYCLE/cycle.yaml" ]; then
  cycle_name=$(read_key "$ROOT/.craft/cycles/$ACTIVE_CYCLE/cycle.yaml" title)
fi
if [ -z "$cycle_name" ]; then
  cycle_name=$(echo "$ACTIVE_CYCLE" | sed 's/^[0-9]*-//')
fi

if [ -f "$ROOT/.craft/cycles/$ACTIVE_CYCLE/.state" ]; then
  source "$ROOT/.craft/cycles/$ACTIVE_CYCLE/.state"

  # Determine status symbol
  case "$CYCLE_STATUS" in
    "active") status_symbol="◐" ;;
    "complete") status_symbol="✓" ;;
    "planning") status_symbol="○" ;;
    *) status_symbol="○" ;;
  esac

  if [ -n "$CURRENT_STORY" ]; then
    # Active story
    story_name=$(echo "$CURRENT_STORY" | sed 's/^[0-9]*-//' | tr '-' ' ')

    if [ -n "$CURRENT_CHUNK" ] && [ -n "$TOTAL_CHUNKS" ]; then
      # Calculate progress bar (5 chars)
      if [ "$TOTAL_CHUNKS" -gt 0 ]; then
        filled=$((CURRENT_CHUNK * 5 / TOTAL_CHUNKS))
        empty=$((5 - filled))
        progress=$(printf '█%.0s' $(seq 1 $filled 2>/dev/null) | head -c $filled)
        progress="${progress}$(printf '░%.0s' $(seq 1 $empty 2>/dev/null) | head -c $empty)"
      else
        progress="░░░░░"
      fi

      printf "[%s] %s %s | chunk %d/%d %s | %s | \$%.2f" \
        "$cycle_name" "$status_symbol" "$story_name" \
        "$CURRENT_CHUNK" "$TOTAL_CHUNKS" "$progress" "$ctx_indicator" "$cost"
    else
      printf "[%s] %s %s | %s | \$%.2f" \
        "$cycle_name" "$status_symbol" "$story_name" "$ctx_indicator" "$cost"
    fi
  else
    # No current story - get counts from directory scan
    cycle_dir="$ROOT/.craft/cycles/$ACTIVE_CYCLE"
    stories_total=$(ls "$cycle_dir/stories/"*.md 2>/dev/null | wc -l | tr -d ' ')
    stories_complete=$(grep -l "^status: complete" "$cycle_dir/stories/"*.md 2>/dev/null | wc -l | tr -d ' ')
    printf "[%s] %s | %d/%d stories | %s | \$%.2f" \
      "$cycle_name" "$status_symbol" \
      "$stories_complete" "$stories_total" "$ctx_indicator" "$cost"
  fi
else
  printf "[%s] | %s | \$%.2f" "$cycle_name" "$ctx_indicator" "$cost"
fi

exit 0
