#!/bin/bash
# complete-story.sh — Transition: Mark a story as complete
# Usage: complete-story.sh <story-file>
#
# Updates:
# - Story: status = complete (via frontmatter)
# - Cycle: CURRENT_STORY cleared, CURRENT_CHUNK cleared
# - Global: CURRENT_STORY cleared

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STORY_FILE="$1"

if [ -z "$STORY_FILE" ]; then
  echo "Usage: complete-story.sh <story-file>"
  exit 1
fi

# Convert relative paths to absolute — walk up to find actual file
if [[ "$STORY_FILE" != /* ]]; then
  _dir="$PWD"
  _found=""
  while [ "$_dir" != "/" ]; do
    if [ -f "$_dir/$STORY_FILE" ]; then
      _found="$_dir/"
      break
    fi
    _dir=$(dirname "$_dir")
  done
  STORY_FILE="${_found:-$PWD/}${STORY_FILE}"
fi

if [ ! -f "$STORY_FILE" ]; then
  echo "Error: Story file not found: $STORY_FILE"
  exit 1
fi

# Derive project root from story file path
PROJECT_ROOT=$(echo "$STORY_FILE" | sed 's|/.craft/.*||')
if [ -d "${PROJECT_ROOT}/.craft" ]; then
  PROJECT_ROOT="${PROJECT_ROOT}/"
else
  PROJECT_ROOT=""
fi

# Update story status to complete (frontmatter only)
"$SCRIPT_DIR/update-story-status.sh" "$STORY_FILE" complete

# Aggregate knowledge-gap failures for reflect pipeline
python3 "$SCRIPT_DIR/aggregate-failures.py" "$PROJECT_ROOT" 2>/dev/null || true

# --- Git commit: one commit per story, staged from the validated manifest ---
#
# The commit is a receipt of validated work, not a working-tree snapshot.
# Staging is driven entirely by .craft/.commit-manifest (written by the
# orchestrator after validation): first line is a "story: <name>" identity
# header, then one project-relative path per line. No manifest means no
# commit - there is deliberately no fallback that sweeps the tree.

COMMIT_ABORTED=0

if [ -n "$PROJECT_ROOT" ]; then
  cd "${PROJECT_ROOT}"

  MANIFEST="${PROJECT_ROOT}.craft/.commit-manifest"
  STORY_NAME=$(basename "$STORY_FILE" .md)

  if [ ! -f "$MANIFEST" ]; then
    echo "no manifest found, no commit made"
  else
    MANIFEST_HEADER=$(head -1 "$MANIFEST")
    MANIFEST_STORY="${MANIFEST_HEADER#story: }"
    MANIFEST_BODY=$(tail -n +2 "$MANIFEST")

    # Delete after read - a consumed (or bad) manifest must never re-fire
    rm -f "$MANIFEST"

    # A comma in a body line means an unsplit comma-joined file list leaked
    # in: the manifest is malformed. Treated exactly like an absent manifest.
    MALFORMED=0
    while IFS= read -r entry; do
      case "$entry" in
        *,*) MALFORMED=1; break ;;
      esac
    done <<< "$MANIFEST_BODY"

    if [ "$MALFORMED" = "1" ]; then
      echo "malformed manifest, no commit made"
    elif [ "$MANIFEST_STORY" != "$STORY_NAME" ]; then
      # Wrong story's manifest. Abort the commit loudly, but defer the
      # non-zero exit to the end of the script: status is already set to
      # complete above, so bailing here would strand cycle/global state.
      echo "Error: commit manifest is for story '$MANIFEST_STORY', not '$STORY_NAME' - no commit made" >&2
      COMMIT_ABORTED=1
    else
      # Parse story title from frontmatter
      STORY_TITLE=$(grep "^title:" "$STORY_FILE" 2>/dev/null | sed 's/title: *//' | tr -d '"' | tr -d '\r')

      # Parse chunk descriptions from chunk headings
      CHUNK_BODY=""
      while IFS= read -r line; do
        # Strip "### Chunk N: " prefix, keep just the description
        desc=$(echo "$line" | sed 's/### Chunk [0-9]*: //')
        CHUNK_BODY="${CHUNK_BODY}
- ${desc}"
      done < <(grep "^### Chunk [0-9]" "$STORY_FILE" 2>/dev/null)

      # Build commit message
      COMMIT_MSG="feat: ${STORY_TITLE:-$STORY_NAME}"
      if [ -n "$CHUNK_BODY" ]; then
        COMMIT_MSG="${COMMIT_MSG}
${CHUNK_BODY}"
      fi

      # Stage each manifest entry individually. A gitignored path is an
      # intentional exclusion: warn and continue. Any other staging failure
      # poisons the receipt: commit nothing and exit non-zero at script end.
      while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        if git check-ignore -q "$entry" 2>/dev/null; then
          echo "Warning: skipping gitignored manifest entry: $entry" >&2
          continue
        fi
        if ! git add -- "$entry" 2>/dev/null; then
          echo "Error: failed to stage manifest entry '$entry' - no commit made" >&2
          COMMIT_ABORTED=1
          break
        fi
      done <<< "$MANIFEST_BODY"

      if [ "$COMMIT_ABORTED" = "0" ]; then
        if git diff --cached --quiet 2>/dev/null; then
          # Nothing to commit
          true
        else
          git commit -m "$COMMIT_MSG" --no-verify 2>/dev/null || true
        fi
      fi
    fi
  fi
fi

# Get cycle from story frontmatter
cycle_name=$(grep "^cycle:" "$STORY_FILE" 2>/dev/null | sed 's/cycle: *//' | tr -d '\r')

if [ -n "$cycle_name" ]; then
  cycle_dir=$(find "${PROJECT_ROOT}.craft/cycles" -maxdepth 1 -type d -name "*${cycle_name}*" 2>/dev/null | head -1)

  if [ -n "$cycle_dir" ] && [ -d "$cycle_dir" ]; then
    # Clear current story/chunk in cycle state
    "$SCRIPT_DIR/update-cycle-state.sh" "$cycle_dir" CURRENT_STORY ""
    "$SCRIPT_DIR/update-cycle-state.sh" "$cycle_dir" CURRENT_CHUNK "0"
    "$SCRIPT_DIR/update-cycle-state.sh" "$cycle_dir" TOTAL_CHUNKS "0"
  fi
fi

# Clear current story in global state
"$SCRIPT_DIR/update-global-state.sh" CURRENT_STORY "" "$PROJECT_ROOT"
"$SCRIPT_DIR/update-global-state.sh" LAST_ACTIVITY "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_ROOT"
"$SCRIPT_DIR/update-global-state.sh" CRAFT_WRITE_ENABLED "" "$PROJECT_ROOT"

# Emit event
if [ -n "$cycle_name" ] && [ -n "$cycle_dir" ]; then
  STORY_NAME=$(basename "$STORY_FILE" .md)
  chunks_complete=$(grep "^chunks_complete:" "$STORY_FILE" 2>/dev/null | sed 's/chunks_complete: *//' || echo "0")
  EVENTS_DIR="$cycle_dir/.events"
  "$SCRIPT_DIR/append-event.sh" "$EVENTS_DIR" "story_completed" "$STORY_NAME" chunks_complete="$chunks_complete" || true
fi

# Clean up checkpoint YAML files — no longer needed after story commit
rm -f "${PROJECT_ROOT}.craft/checkpoints/"*.yaml 2>/dev/null

# Clean up chunk validation state
rm -f "${PROJECT_ROOT}.craft/.chunk-state" 2>/dev/null

# Deferred abort exit: state transitions above must complete even when the
# commit was aborted, so the non-zero exit is the very last thing that happens.
if [ "${COMMIT_ABORTED:-0}" = "1" ]; then
  echo "Error: story state transitions completed, but the commit was aborted - see messages above" >&2
  exit 1
fi

echo "Story completed: $STORY_FILE"
