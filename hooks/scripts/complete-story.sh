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

# --- The flip: mark every decision record this story carries as crafted ---
#
# A missing/empty `decisions:` field is a byte-identical no-op: no transition
# call, no warning, no buffered line. A failing slug never exits the loop -
# it warns and moves on, so one bad slug can never strand the state
# transitions (cycle/global/event) that still have to run below. The flip
# never stages anything; it only writes into .craft/decisions.

DECISIONS_FLIP_FAILED=0
DECISIONS_FAIL_COUNT=0
CRAFTED_LINES=""

DECISIONS_NAME=$(grep "^name:" "$STORY_FILE" 2>/dev/null | head -1 | sed 's/^name: *//' | tr -d '"' | tr -d '\r')
if [ -z "$DECISIONS_NAME" ]; then
  DECISIONS_NAME=$(basename "$STORY_FILE" .md | sed -E 's/^[0-9]+[a-z]?-//')
fi

DECISIONS_RAW=$(grep "^decisions:" "$STORY_FILE" 2>/dev/null | head -1 | sed 's/^decisions: *//' | tr -d '\r')
DECISIONS_RAW="${DECISIONS_RAW#\[}"
DECISIONS_RAW="${DECISIONS_RAW%\]}"

if [ -n "$DECISIONS_RAW" ]; then
  IFS=',' read -ra DECISIONS_SLUGS <<< "$DECISIONS_RAW"
  for decisions_slug in "${DECISIONS_SLUGS[@]}"; do
    decisions_slug="$(echo "$decisions_slug" | sed 's/^ *//; s/ *$//')"
    [ -z "$decisions_slug" ] && continue

    if ! DECISIONS_TRANSITION_OUT=$(CRAFT_PROJECT_ROOT="${PROJECT_ROOT%/}" "$SCRIPT_DIR/decisions-transition.sh" "$decisions_slug" craft --story="$DECISIONS_NAME" 2>&1); then
      decisions_reason=$(echo "$DECISIONS_TRANSITION_OUT" | tail -1 | sed 's/^Error: *//')
      echo "Warning: decision record '$decisions_slug' could not be flipped to crafted - $decisions_reason - continuing" >&2
      DECISIONS_FLIP_FAILED=1
      DECISIONS_FAIL_COUNT=$((DECISIONS_FAIL_COUNT + 1))
      continue
    fi

    decisions_title=$(echo "$DECISIONS_TRANSITION_OUT" | sed -n 's/^TITLE=//p')
    decisions_changed=$(echo "$DECISIONS_TRANSITION_OUT" | sed -n 's/^CHANGED=//p')
    if [ "$decisions_changed" = "1" ]; then
      CRAFTED_LINES="${CRAFTED_LINES}Crafted: ${decisions_title}"$'\n'
    fi
  done
fi

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
        # An entry gone from the worktree is either a bad manifest line
        # (abort, below) or a change the implementer already staged: the old
        # name of a `git mv` rename, or a file removed with `git rm`. Git
        # records both - the path appears as the SOURCE of a staged rename
        # (R) or as a staged deletion (D) - and only those cases are safe to
        # skip: the change is already in the index and rides the commit.
        # `git add` cannot touch such a path (it is in neither the worktree
        # nor the index). A path git has no record of still aborts.
        if [ ! -e "$entry" ] && git diff --cached --name-status -M 2>/dev/null \
             | awk -F'\t' '$1 ~ /^[RD]/ {print $2}' | grep -qxF -- "$entry"; then
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

# Refresh the dashboard graph data - before the deferred abort exit, because
# the story's state DID change even when the commit was refused. Silenced so
# callers still read this script's own output; guarded so a missing wrapper
# never fails a flow.
bash "$SCRIPT_DIR/../../scripts/dashboard/dashboard-run.sh" --root "$PROJECT_ROOT" >/dev/null 2>&1 || true

# The Crafted: lines are buffered from the flip above and print here, right
# before the deferred abort exit, so they are present on every run - clean
# or refused - because the flip's writes already happened regardless of
# what the commit block decided.
printf '%s' "$CRAFTED_LINES"

# Deferred abort exit: state transitions above must complete even when the
# commit was aborted or a decision record failed to flip, so the non-zero
# exit is the very last thing that happens. The two failure sources report
# distinct messages so neither is ever mistaken for the other.
if [ "${COMMIT_ABORTED:-0}" = "1" ] || [ "${DECISIONS_FLIP_FAILED:-0}" = "1" ]; then
  if [ "${COMMIT_ABORTED:-0}" = "1" ]; then
    echo "Error: story state transitions completed, but the commit was aborted - see messages above" >&2
  fi
  if [ "${DECISIONS_FLIP_FAILED:-0}" = "1" ]; then
    echo "Error: story state transitions completed, but ${DECISIONS_FAIL_COUNT} decision record(s) could not be flipped to crafted - see messages above" >&2
  fi
  exit 1
fi

# The user has never opened the graph page - surface it once, right when
# the project's story data just grew, so the next turn can mention it.
# Once the page exists this never fires again; no counter or state needed.
if [ -n "$PROJECT_ROOT" ] && [ ! -f "${PROJECT_ROOT}.craft/dashboard.html" ]; then
  echo "DASHBOARD_OFFER=1"
fi

echo "Story completed: $STORY_FILE"
