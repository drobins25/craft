#!/bin/bash
# fixtures/with-story.sh — .craft/ with a cycle + story (full frontmatter)
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/fixtures/with-story.sh"
#   dir=$(create_craft_with_story "test-cycle" "my-story" "My Story Title")
#
# Creates everything from with-cycle.sh PLUS:
#   .craft/cycles/1-test-cycle/stories/1-my-story.md (with full frontmatter)
#   .global-state with CURRENT_STORY set
#   .state with CURRENT_STORY, CURRENT_CHUNK, TOTAL_CHUNKS set

# Depends on with-cycle.sh
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FIXTURES_DIR/with-cycle.sh"

create_craft_with_story() {
  local cycle_name="${1:-test-cycle}"
  local story_name="${2:-test-story}"
  local story_title="${3:-Test Story}"
  local total_chunks="${4:-3}"
  local status="${5:-ready}"

  # Create base cycle
  local dir
  dir=$(create_craft_with_cycle "$cycle_name" "Test Cycle" "1")
  local cycle_dir="$dir/.craft/cycles/1-${cycle_name}"

  # Create story file with full frontmatter
  local story_file="$cycle_dir/stories/1-${story_name}.md"
  cat > "$story_file" << EOF
---
name: ${story_name}
title: "${story_title}"
status: ${status}
priority: medium
created: 2026-02-14
updated: 2026-02-14
cycle: ${cycle_name}
story_number: 1
chunks_total: ${total_chunks}
chunks_complete: 0
current_chunk: 0
---

# Story: ${story_title}

## Spark
Test story for automated testing.

## Chunks
### Chunk 1: First chunk
**Goal:** Do the first thing.

### Chunk 2: Second chunk
**Goal:** Do the second thing.

### Chunk 3: Third chunk
**Goal:** Do the third thing.
EOF

  # Update state to point to this story
  cat > "$dir/.craft/.global-state" << EOF
ACTIVE_CYCLE="1-${cycle_name}"
CURRENT_STORY="${story_name}"
PLANNING_CYCLE=""
LAST_ACTIVITY=""
EOF

  cat > "$cycle_dir/.state" << EOF
CYCLE_NAME="${cycle_name}"
CYCLE_STATUS="active"
CURRENT_STORY="${story_name}"
CURRENT_CHUNK="1"
TOTAL_CHUNKS="${total_chunks}"
LAST_VALIDATION=""
LAST_CHECKPOINT=""
EOF

  echo "$dir"
}

# Turn a fixture dir into a real git repo with an initial commit, so tests
# can exercise staging, HEAD diffs, and upstream ranges.
git_init_repo() {
  local dir="$1"
  (
    cd "$dir"
    git init -q
    git config user.name "craft-test"
    git config user.email "craft-test@example.com"
    git add -A
    git commit -q -m "init" --no-verify --allow-empty
  )
}

# Create a story in the backlog (no cycle assignment)
create_backlog_story() {
  local dir="${1}"
  local story_name="${2:-backlog-story}"
  local story_title="${3:-Backlog Story}"

  mkdir -p "$dir/.craft/backlog"
  local story_file="$dir/.craft/backlog/${story_name}.md"
  cat > "$story_file" << EOF
---
name: ${story_name}
title: "${story_title}"
status: backlog
priority: medium
created: 2026-02-14
updated: 2026-02-14
chunks_total: 0
chunks_complete: 0
---

# Story: ${story_title}

## Spark
Backlog story for automated testing.
EOF

  echo "$story_file"
}
