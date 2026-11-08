#!/bin/bash
# Export-progress: Save critical state before context compaction
# Ensures we can resume after context is cleared

set -e

# Resolve project root (CRAFT_PROJECT_ROOT set by session-start, or find-workshop.sh fallback)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/read-key.sh"
if [ -n "$CRAFT_PROJECT_ROOT" ]; then
  ROOT="${CRAFT_PROJECT_ROOT%/}"
else
  source "$SCRIPT_DIR/find-workshop.sh" 2>/dev/null || true
  ROOT="${PROJECT_ROOT%/}"
fi

# Guard: if ROOT is empty, we can't safely write anywhere
if [ -z "$ROOT" ]; then
  exit 0
fi

# Only export if .craft exists
if [ ! -d "$ROOT/.craft" ]; then
  exit 0
fi

# Create export directory if needed
mkdir -p "$ROOT/.craft/.exports"

# Export timestamp
timestamp=$(date +%Y%m%d_%H%M%S)
export_file="$ROOT/.craft/.exports/pre-compact-$timestamp.md"

# Build export content
cat > "$export_file" << 'HEADER'
# Craft State Export (Pre-Compact)

This file was created automatically before context compaction.
Use this to restore state if needed.

HEADER

# Export global state
if [ -f "$ROOT/.craft/.global-state" ]; then
  echo "## Global State" >> "$export_file"
  echo '```bash' >> "$export_file"
  cat "$ROOT/.craft/.global-state" >> "$export_file"
  echo '```' >> "$export_file"
  echo "" >> "$export_file"
fi

# Export active cycle state
if [ -f "$ROOT/.craft/.global-state" ]; then
  source "$ROOT/.craft/.global-state"

  if [ -n "$ACTIVE_CYCLE" ] && [ -f "$ROOT/.craft/cycles/$ACTIVE_CYCLE/.state" ]; then
    cycle_title=$(read_key "$ROOT/.craft/cycles/$ACTIVE_CYCLE/cycle.yaml" title)
    echo "## Cycle State: ${cycle_title:-$ACTIVE_CYCLE}" >> "$export_file"
    echo '```bash' >> "$export_file"
    cat "$ROOT/.craft/cycles/$ACTIVE_CYCLE/.state" >> "$export_file"
    echo '```' >> "$export_file"
    echo "" >> "$export_file"
  fi

  # Export current story summary
  if [ -n "$CURRENT_STORY" ] && [ -n "$ACTIVE_CYCLE" ]; then
    story_file=$(find "$ROOT/.craft/cycles/$ACTIVE_CYCLE/stories" -name "*$CURRENT_STORY*.md" 2>/dev/null | head -1)
    if [ -n "$story_file" ] && [ -f "$story_file" ]; then
      echo "## Current Story" >> "$export_file"
      echo "File: $story_file" >> "$export_file"
      echo "" >> "$export_file"
      # Include first 50 lines of story
      echo '```markdown' >> "$export_file"
      head -50 "$story_file" >> "$export_file"
      echo '```' >> "$export_file"
      echo "" >> "$export_file"
    fi
  fi
fi

# Export recent git commits
echo "## Recent Checkpoints" >> "$export_file"
echo '```' >> "$export_file"
git log --oneline -10 2>/dev/null >> "$export_file" || echo "No git history" >> "$export_file"
echo '```' >> "$export_file"

# Clean up old exports (keep last 5)
ls -t "$ROOT/.craft/.exports/pre-compact-"*.md 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true

echo "State exported to $export_file"
exit 0
