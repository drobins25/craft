#!/bin/bash
# complete-chunk.sh — Transition: Mark current chunk as complete, advance to next
# Usage: complete-chunk.sh [--not-done] [cycle-dir]
#
# If cycle-dir not provided, uses ACTIVE_CYCLE from global state
#
# Updates:
# - Cycle .state: CURRENT_CHUNK incremented, LAST_VALIDATION timestamp
# - Story frontmatter: chunks_complete incremented, current_chunk updated
# - With --not-done (the caller holds the builder's report): the chunk's open
#   Done When boxes are ticked, except the ones listed in
#   .craft/.chunk-not-done.txt, which stay open with the builder's reason.
#   Without the flag no box changes. The file is removed on every exit once the
#   flag is parsed, so it can never apply to a later chunk.
#
# Callers read the last line printed: "Chunk N complete..." or "ALL CHUNKS COMPLETE...".

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NOT_DONE=0
if [ "${1:-}" = "--not-done" ]; then
  NOT_DONE=1
  shift
  # Single quotes: PROJECT_ROOT is settled later, the trap reads it at exit.
  trap 'rm -f "${PROJECT_ROOT}.craft/.chunk-not-done.txt"' EXIT
fi

CYCLE_DIR="${1:-}"

# Convert relative paths to absolute using PWD
if [ -n "$CYCLE_DIR" ] && [[ "$CYCLE_DIR" != /* ]]; then
  CYCLE_DIR="$PWD/$CYCLE_DIR"
fi

# If cycle provided, derive PROJECT_ROOT from it
if [ -n "$CYCLE_DIR" ]; then
  PROJECT_ROOT=$(echo "$CYCLE_DIR" | sed 's|/.craft/.*||')
  if [ -d "${PROJECT_ROOT}/.craft" ]; then
    PROJECT_ROOT="${PROJECT_ROOT}/"
  else
    PROJECT_ROOT=""
  fi
else
  # Walk up to find project root (handles monorepo subdirectories)
  PROJECT_ROOT=""
  source "$SCRIPT_DIR/find-workshop.sh"
fi

# If no cycle provided, get from global state
if [ -z "$CYCLE_DIR" ]; then
  if [ -f "${PROJECT_ROOT}.craft/.global-state" ]; then
    source "${PROJECT_ROOT}.craft/.global-state"
    if [ -n "$ACTIVE_CYCLE" ]; then
      CYCLE_DIR="${PROJECT_ROOT}.craft/cycles/$ACTIVE_CYCLE"
    fi
  fi
fi

if [ -z "$CYCLE_DIR" ] || [ ! -d "$CYCLE_DIR" ]; then
  echo "Error: No active cycle found"
  exit 1
fi

# Get current state
if [ ! -f "$CYCLE_DIR/.state" ]; then
  echo "Error: Cycle state file not found"
  exit 1
fi

source "$CYCLE_DIR/.state"

if [ -z "$CURRENT_STORY" ]; then
  echo "Error: No active story in cycle"
  exit 1
fi

# Increment chunk
NEW_CHUNK=$((CURRENT_CHUNK + 1))

# Update cycle state
"$SCRIPT_DIR/update-cycle-state.sh" "$CYCLE_DIR" CURRENT_CHUNK "$NEW_CHUNK"
"$SCRIPT_DIR/update-cycle-state.sh" "$CYCLE_DIR" LAST_VALIDATION "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Find the current story's file for the counters: the exact name first, then the
# one numbered form (<number>-<name>.md) a story moved into a cycle carries. Names
# are compared as plain strings, never as patterns, so a story whose name merely
# contains this one is never picked.
STORY_FILE=""
if [ -f "$CYCLE_DIR/stories/${CURRENT_STORY}.md" ]; then
  STORY_FILE="$CYCLE_DIR/stories/${CURRENT_STORY}.md"
else
  numbered_re='^[0-9]+[a-z]?-(.*)$'
  numbered_count=0
  numbered_file=""
  for candidate in "$CYCLE_DIR/stories/"*.md; do
    [ -f "$candidate" ] || continue
    candidate_base="${candidate##*/}"
    if [[ "$candidate_base" =~ $numbered_re ]] && [ "${BASH_REMATCH[1]}" = "${CURRENT_STORY}.md" ]; then
      numbered_count=$((numbered_count + 1))
      numbered_file="$candidate"
    fi
  done
  if [ "$numbered_count" -eq 1 ]; then
    STORY_FILE="$numbered_file"
  fi
fi

# Update story file chunks_complete
if [ -n "$STORY_FILE" ] && [ -f "$STORY_FILE" ]; then
  current_complete=$(grep "^chunks_complete:" "$STORY_FILE" 2>/dev/null | sed 's/chunks_complete: *//' || echo "0")
  new_complete=$((current_complete + 1))
  sed -i.bak "s/^chunks_complete:.*/chunks_complete: $new_complete/" "$STORY_FILE"
  sed -i.bak "s/^current_chunk:.*/current_chunk: $NEW_CHUNK/" "$STORY_FILE"
  sed -i.bak "s/^updated:.*/updated: $(date +%Y-%m-%d)/" "$STORY_FILE"
  rm -f "$STORY_FILE.bak"
fi

# Tick the passed chunk's Done When boxes (only when the caller holds the
# builder's report). Guarded: a failure here, or no python3, must not stop the
# steps after it. The python block prints its own result line as its last act;
# when it did not get that far, the line below says no box changed.
if [ "$NOT_DONE" -eq 1 ]; then
  tick_rc=0
  python3 - "$CYCLE_DIR/stories/${CURRENT_STORY}.md" "$CURRENT_CHUNK" "$CURRENT_STORY" \
    "${PROJECT_ROOT}.craft/.chunk-not-done.txt" "$SCRIPT_DIR" 2>/dev/null <<'PYEOF' || tick_rc=$?
import os
import re
import sys

story_path, chunk, story_name, list_path, script_dir = sys.argv[1:6]


class Refuse(Exception):
    """The list cannot be applied exactly; no box changes."""


def collapse(text):
    return re.sub(r'\s+', ' ', text).strip()


def parse_list(one_line, path):
    try:
        with open(path, 'rb') as handle:
            raw = handle.read()
    except OSError:
        raise Refuse('no open-box list was written')
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError:
        raise Refuse('the open-box list is not readable text')
    story = None
    stamp = None
    entries = []  # type: list
    waiting = None
    for line in text.split('\n'):
        if line.endswith('\r'):
            line = line[:-1]
        if not line.strip():
            continue
        if ': ' in line:
            field, value = line.split(': ', 1)
        elif line.endswith(':'):
            field, value = line[:-1], ''
        else:
            raise Refuse('the open-box list is malformed')
        # one_line leaves a tab alone; a reason must not carry one into the story.
        value = one_line(value).replace('\t', ' ')
        if field == 'story' and story is None and waiting is None:
            story = value
        elif field == 'chunk' and stamp is None and waiting is None:
            stamp = value
        elif field == 'box' and waiting is None:
            waiting = value
        elif field == 'reason' and waiting is not None and value:
            entries.append((waiting, value))
            waiting = None
        else:
            raise Refuse('the open-box list is malformed')
    if waiting is not None or story is None or stamp is None:
        raise Refuse('the open-box list is malformed')
    return story, stamp, entries


def main():
    sys.path.insert(0, script_dir)
    from cycle_values import one_line
    from annotate_write import write_atomic
    from tracker_comments import split_lines

    listed_story, listed_chunk, entries = parse_list(one_line, list_path)
    if listed_story != story_name or listed_chunk != chunk:
        raise Refuse('the open-box list was written for another chunk or story')
    if not os.path.isfile(story_path):
        raise Refuse('the story file was not found')
    try:
        with open(story_path, 'rb') as handle:
            text = handle.read().decode('utf-8')
    except (OSError, UnicodeDecodeError):
        raise Refuse('the story file is not readable text')
    lines = split_lines(text)

    fence = re.compile(r'^ {0,3}(```|~~~)')
    heading = re.compile(r'^### Chunk ' + re.escape(chunk) + r'(?:[:/\s]|$)')
    done_when = re.compile(r'^\*\*Done [Ww]hen:\*\*[ \t]*\r?\n?$')
    state = 'seek'
    in_fence = False
    boxes = []  # (index, is_open, text)
    for index, line in enumerate(lines):
        if fence.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if state == 'seek':
            if heading.match(line):
                state = 'chunk'
        elif state == 'chunk':
            if line.startswith('## ') or line.startswith('### '):
                break
            if done_when.match(line):
                state = 'list'
        elif state == 'list':
            if line.startswith('## ') or line.startswith('### ') or line.startswith('#') \
                    or line.startswith('**') or line.startswith('---'):
                break
            marker = line[:6]
            if marker in ('- [ ] ', '- [x] ', '- [X] '):
                boxes.append((index, marker == '- [ ] ', collapse(line[6:])))

    reasons = {}  # type: dict
    for name, reason in entries:
        wanted = collapse(name)
        hit = False
        for index, is_open, box_text in boxes:
            if box_text == wanted:
                hit = True
                reasons.setdefault(index, []).append(reason)
        if not hit:
            raise Refuse('a listed box is not in the chunk\'s Done When list')

    ticked = 0
    left_open = 0
    for index, is_open, box_text in boxes:
        if not is_open:
            continue
        line = lines[index]
        body = line.rstrip('\r\n')
        ending = line[len(body):]
        if index in reasons:
            lines[index] = body.rstrip(' \t') + ' (not done: ' + '; '.join(reasons[index]) + ')' + ending
            left_open += 1
        else:
            lines[index] = '- [x] ' + line[6:]
            ticked += 1
    if ticked or left_open:
        write_atomic(story_path, ''.join(lines), mode=os.stat(story_path).st_mode & 0o777)
    print('Done When: chunk %s - %d ticked, %d left open.' % (chunk, ticked, left_open))


try:
    main()
except Refuse as refusal:
    print('Done When: chunk %s - no boxes changed (%s).' % (chunk, refusal))
except Exception:
    print('Done When: chunk %s - no boxes changed (the tick step failed).' % chunk)
PYEOF
  if [ "$tick_rc" -ne 0 ]; then
    echo "Done When: chunk $CURRENT_CHUNK - no boxes changed (the tick step could not run)."
  fi
fi

# Update global last activity
"$SCRIPT_DIR/update-global-state.sh" LAST_ACTIVITY "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_ROOT"

# Clean up chunk validation state (REFINE_COUNT tracking)
rm -f "${PROJECT_ROOT}.craft/.chunk-state"

# Emit event
EVENTS_DIR="$CYCLE_DIR/.events"
"$SCRIPT_DIR/append-event.sh" "$EVENTS_DIR" "chunk_completed" "$CURRENT_STORY" chunk="$CURRENT_CHUNK" total="$TOTAL_CHUNKS" || true

# Refresh the dashboard graph data. Silenced so callers still read this
# script's own final line; guarded so a missing wrapper never fails a flow.
bash "$SCRIPT_DIR/../../scripts/dashboard/dashboard-run.sh" --root "$PROJECT_ROOT" >/dev/null 2>&1 || true

# Signal whether this was the last chunk
if [ "$NEW_CHUNK" -gt "$TOTAL_CHUNKS" ]; then
  echo "ALL CHUNKS COMPLETE ($TOTAL_CHUNKS/$TOTAL_CHUNKS). Run complete-story.sh to finalize."
else
  echo "Chunk $CURRENT_CHUNK complete. Now on chunk $NEW_CHUNK of $TOTAL_CHUNKS."
fi
