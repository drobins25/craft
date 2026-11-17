#!/bin/bash
# test-complete-chunk.sh — Tests for complete-chunk.sh
# Validates chunk completion: state increment, frontmatter update, last-chunk signal

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"

COMPLETE_CHUNK_SCRIPT="$SCRIPTS_DIR/complete-chunk.sh"

# --- Tests ---

echo "=== test-complete-chunk.sh ==="
echo ""

# Test 1: Happy path — chunk 1 of 3 increments to chunk 2
begin_test "Happy path — chunk 1→2 of 3"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")
trap cleanup_test_dir EXIT
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"
STORY_FILE="$CYCLE_DIR/stories/1-test-story.md"

set +e
RESULT=$(cd "$TEST_DIR" && bash "$COMPLETE_CHUNK_SCRIPT" "$CYCLE_DIR" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"

# Cycle state should show CURRENT_CHUNK=2
source "$CYCLE_DIR/.state"
assert_eq "CURRENT_CHUNK is 2" "2" "$CURRENT_CHUNK"

# Story frontmatter chunks_complete should be 1
CHUNKS_COMPLETE=$(grep "^chunks_complete:" "$STORY_FILE" | sed 's/chunks_complete: *//')
assert_eq "chunks_complete is 1" "1" "$CHUNKS_COMPLETE"

# Story frontmatter current_chunk should be 2
CURRENT_CHUNK_FM=$(grep "^current_chunk:" "$STORY_FILE" | sed 's/current_chunk: *//')
assert_eq "current_chunk is 2" "2" "$CURRENT_CHUNK_FM"

# Output should indicate continuation
assert_contains "output shows chunk progress" "chunk 2" "$RESULT"

cleanup_test_dir
echo ""

# Test 2: Last chunk — signals all chunks complete
begin_test "Last chunk — signals all chunks complete"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "2" "active")
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"

# Set to chunk 2 of 2 (about to complete last chunk)
cat > "$CYCLE_DIR/.state" << 'EOF'
CYCLE_NAME="test-cycle"
CYCLE_STATUS="active"
CURRENT_STORY="test-story"
CURRENT_CHUNK="2"
TOTAL_CHUNKS="2"
LAST_VALIDATION=""
LAST_CHECKPOINT=""
EOF

set +e
RESULT=$(cd "$TEST_DIR" && bash "$COMPLETE_CHUNK_SCRIPT" "$CYCLE_DIR" 2>/dev/null)
set -e

# Output should signal completion
assert_contains "signals ALL CHUNKS COMPLETE" "ALL CHUNKS COMPLETE" "$RESULT"

# CURRENT_CHUNK should be 3 (past total)
source "$CYCLE_DIR/.state"
assert_eq "CURRENT_CHUNK is 3 (past total)" "3" "$CURRENT_CHUNK"

cleanup_test_dir
echo ""

# Test 3: Updates story frontmatter — chunks_complete incremented
begin_test "Updates story frontmatter — updated date changes"

TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"
STORY_FILE="$CYCLE_DIR/stories/1-test-story.md"

# Check original date
ORIG_UPDATED=$(grep "^updated:" "$STORY_FILE" | sed 's/updated: *//')

set +e
(cd "$TEST_DIR" && bash "$COMPLETE_CHUNK_SCRIPT" "$CYCLE_DIR" 2>/dev/null)
set -e

# Updated date should be today
TODAY=$(date +%Y-%m-%d)
NEW_UPDATED=$(grep "^updated:" "$STORY_FILE" | sed 's/updated: *//')
assert_eq "updated date is today" "$TODAY" "$NEW_UPDATED"

cleanup_test_dir
echo ""

# Test 4: BUG — complete-chunk.sh picks up CRAFT_PROJECT_ROOT from environment
# When called with no args from a random directory, find-workshop.sh inherits
# CRAFT_PROJECT_ROOT from the parent environment and operates on the REAL project.
# This is a safety issue: an accidental invocation can corrupt real state.
# The test verifies the bug exists by checking that env isolation changes behavior.
begin_test "BUG: no args + no env isolation → picks up real CRAFT_PROJECT_ROOT"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"

# WITHOUT env isolation — script inherits CRAFT_PROJECT_ROOT from parent
# It will find the real project and try to operate on it (dangerous!)
# WITH env isolation — script can't find any active cycle → should exit 1
set +e
RESULT=$(cd "$TEST_DIR" && unset CRAFT_PROJECT_ROOT && unset PROJECT_ROOT && bash "$COMPLETE_CHUNK_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 1 with no cycle (env isolated)" "1" "$EXIT_CODE"

rm -rf "$TEST_DIR"
echo ""

# Test 5: No active story in cycle — exits 1
begin_test "No active story in cycle — exits 1"

TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"

# Ensure no CURRENT_STORY
cat > "$CYCLE_DIR/.state" << 'EOF'
CYCLE_NAME="test-cycle"
CYCLE_STATUS="active"
CURRENT_STORY=""
CURRENT_CHUNK="0"
TOTAL_CHUNKS="0"
LAST_VALIDATION=""
LAST_CHECKPOINT=""
EOF

set +e
RESULT=$(cd "$TEST_DIR" && bash "$COMPLETE_CHUNK_SCRIPT" "$CYCLE_DIR" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 1 with no story" "1" "$EXIT_CODE"

cleanup_test_dir
echo ""

# --- Done When ticking (the --not-done flag) ---

# Story bodies below write their level-three headings as "@@@ " so a heredoc line
# never reads as a shell comment; put_story_body turns them into "### ".

# A story file named exactly <CURRENT_STORY>.md with the frontmatter these tests
# expect; the body comes from stdin.
put_story_body() {
  {
    cat << 'EOF'
---
name: tick-story
title: "Tick Story"
status: active
priority: medium
created: 2026-02-14
updated: 2026-02-14
cycle: test-cycle
story_number: 1
chunks_total: 3
chunks_complete: 1
current_chunk: 2
---
EOF
    sed 's/^@@@ /### /'
  } > "$STORY"
}

default_body() {
  cat << 'EOF'

# Story: Tick

## Acceptance
- [ ] Acceptance one
- [ ] Safari check passes

## Chunks

@@@ Chunk 1: First
**Goal:** one

**Done When:**
- [ ] One A
- [ ] One B

@@@ Chunk 2: Second
**Goal:** two

**Done When:**
- [ ] Build passes
- [ ] Safari check passes
- [ ] Docs written

@@@ Chunk 3: Third
**Goal:** three

**Done When:**
- [ ] Three A

## Definition of Done
- [ ] DoD one
EOF
}

write_state() { # story current-chunk total
  cat > "$CYCLE_DIR/.state" << EOF
CYCLE_NAME="test-cycle"
CYCLE_STATUS="active"
CURRENT_STORY="$1"
CURRENT_CHUNK="$2"
TOTAL_CHUNKS="$3"
LAST_VALIDATION=""
LAST_CHECKPOINT=""
EOF
}

# A fixture with the default story and the cycle on its second of three chunks.
new_tick_fixture() {
  TEST_DIR=$(create_craft_with_story "test-cycle" "tick-story" "Tick Story" "3" "active")
  CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"
  rm -f "$CYCLE_DIR/stories/1-tick-story.md"
  STORY="$CYCLE_DIR/stories/tick-story.md"
  ND="$TEST_DIR/.craft/.chunk-not-done.txt"
  default_body | put_story_body
  write_state "tick-story" 2 3
  cp "$STORY" "$TEST_DIR/before.md"
}

# Replace the story with the body on stdin and remember it as the "before" copy.
set_story() {
  put_story_body
  cp "$STORY" "$TEST_DIR/before.md"
}

# write_nd <story> <chunk-number> [<box> <reason>]... - the open-box file, written
# with printf so no value is ever read as shell syntax.
write_nd() {
  local story="$1" number="$2"
  shift 2
  {
    printf 'story: %s\n' "$story"
    printf 'chunk: %s\n' "$number"
    while [ $# -ge 2 ]; do
      printf 'box: %s\n' "$1"
      printf 'reason: %s\n' "$2"
      shift 2
    done
  } > "$ND"
}

# Run the script the way the build loop does with a cycle dir; sets RESULT and EXIT_CODE.
run_cc() {
  set +e
  RESULT=$(cd "$TEST_DIR" && bash "$COMPLETE_CHUNK_SCRIPT" "$@" "$CYCLE_DIR" 2>/dev/null)
  EXIT_CODE=$?
  set -e
}

# The story without its frontmatter, as a file.
body_to() { # <story> <out>
  awk 'n >= 2 { print } /^---$/ { n++ }' "$1" > "$2"
}

# assert_body <desc> <expected-body-file>: the story's body is byte-identical to the file.
assert_body() {
  body_to "$STORY" "$TEST_DIR/after.body"
  if cmp -s "$2" "$TEST_DIR/after.body"; then
    assert_eq "$1" "same" "same"
  else
    assert_eq "$1" "same" "differs: $(diff "$2" "$TEST_DIR/after.body" | head -6 | tr '\n' '|')"
  fi
}

# The before body, unchanged, as the expected body.
same_body() { # <out>
  body_to "$TEST_DIR/before.md" "$1"
}

fm_value() { # <file> <key>
  grep "^$2:" "$1" | sed "s/$2: *//"
}

state_chunk() {
  grep '^CURRENT_CHUNK=' "$CYCLE_DIR/.state" | tr -d '"' | cut -d= -f2
}

last_line() {
  printf '%s\n' "$1" | tail -1
}

# The default story's expected body once the second chunk is ticked. With "skip",
# the Safari line there stays as it was (the Acceptance one never changes).
tick_second_expected() { # <out> [skip]
  body_to "$TEST_DIR/before.md" "$TEST_DIR/before.body"
  awk -v skip="${2:-}" '
    /^### Chunk / { inchunk = ($3 == "2:") }
    inchunk && /^- \[ \] Build passes$/ { print "- [x] Build passes"; next }
    inchunk && /^- \[ \] Safari check passes$/ { if (skip == "") print "- [x] Safari check passes"; else print; next }
    inchunk && /^- \[ \] Docs written$/ { print "- [x] Docs written"; next }
    { print }
  ' "$TEST_DIR/before.body" > "$1"
}

echo "--- Done When ticking ---"
echo ""

# Test: a failing python3 never stops the chunk
begin_test "a failing python3 never stops the chunk"
new_tick_fixture
write_nd "tick-story" 2
mkdir -p "$TEST_DIR/fakebin"
printf '#!/bin/sh\nexit 2\n' > "$TEST_DIR/fakebin/python3"
chmod +x "$TEST_DIR/fakebin/python3"
set +e
RESULT=$(cd "$TEST_DIR" && PATH="$TEST_DIR/fakebin:$PATH" bash "$COMPLETE_CHUNK_SCRIPT" --not-done "$CYCLE_DIR" 2>/dev/null)
EXIT_CODE=$?
set -e
assert_eq "exits 0" "0" "$EXIT_CODE"
assert_eq "CURRENT_CHUNK moved" "3" "$(state_chunk)"
assert_eq "chunks_complete moved" "2" "$(fm_value "$STORY" chunks_complete)"
assert_file_not_exists "chunk-state removed" "$TEST_DIR/.craft/.chunk-state"
assert_eq "event appended" "1" "$( (cat "$CYCLE_DIR"/.events/* 2>/dev/null || true) | grep -c chunk_completed || true)"
assert_contains_literal "reports no boxes changed" "Done When: chunk 2 - no boxes changed (" "$RESULT"
assert_eq "last line unchanged" "Chunk 2 complete. Now on chunk 3 of 3." "$(last_line "$RESULT")"
same_body "$TEST_DIR/exp.body"
assert_body "no box changed" "$TEST_DIR/exp.body"
cleanup_test_dir
echo ""

# Test: nothing left open ticks every open box in the current chunk only
begin_test "nothing left open ticks every open box in the current chunk only"
new_tick_fixture
write_nd "tick-story" 2
run_cc --not-done
tick_second_expected "$TEST_DIR/exp.body"
assert_body "second chunk's boxes ticked, every other line byte-identical" "$TEST_DIR/exp.body"
assert_contains_literal "ticked line reads as spec" "- [x] Build passes" "$(cat "$STORY")"
assert_contains_literal "output counts" "Done When: chunk 2 - 3 ticked, 0 left open." "$RESULT"
cleanup_test_dir
echo ""

# Test: a named box stays open with the reason on its line
begin_test "a named box stays open with the reason on its line"
new_tick_fixture
write_nd "tick-story" 2 "Safari check passes" "Chrome engine only, 2026-11-15. Safari not run."
run_cc --not-done
assert_contains_literal "reason on the box line" "- [ ] Safari check passes (not done: Chrome engine only, 2026-11-15. Safari not run.)" "$(cat "$STORY")"
tick_second_expected "$TEST_DIR/exp.body" skip
# Only the second chunk's Safari line carries the reason; the Acceptance line with the same text stays as it was.
awk '/^### Chunk / { c = ($3 == "2:") } c && /^- \[ \] Safari check passes$/ { print $0 " (not done: Chrome engine only, 2026-11-15. Safari not run.)"; next } { print }' "$TEST_DIR/exp.body" > "$TEST_DIR/exp2.body"
assert_body "other two ticked, nothing else moved" "$TEST_DIR/exp2.body"
assert_contains_literal "output counts" "Done When: chunk 2 - 2 ticked, 1 left open." "$RESULT"
cleanup_test_dir
echo ""

# Test: counters and final line with the flag
begin_test "with the flag, counters and final line move exactly as without it"
new_tick_fixture
write_nd "tick-story" 2
run_cc --not-done
assert_eq "chunks_complete" "2" "$(fm_value "$STORY" chunks_complete)"
assert_eq "current_chunk" "3" "$(fm_value "$STORY" current_chunk)"
assert_eq ".state CURRENT_CHUNK" "3" "$(state_chunk)"
assert_eq "last line mid-story" "Chunk 2 complete. Now on chunk 3 of 3." "$(last_line "$RESULT")"
write_state "tick-story" 3 3
write_nd "tick-story" 3
run_cc --not-done
assert_eq "last line on the last chunk" "ALL CHUNKS COMPLETE (3/3). Run complete-story.sh to finalize." "$(last_line "$RESULT")"
cleanup_test_dir
echo ""

# Test: without the flag no box changes
begin_test "without the flag no box changes and no Done When line prints"
new_tick_fixture
write_nd "tick-story" 2
run_cc
same_body "$TEST_DIR/exp.body"
assert_body "body byte-identical" "$TEST_DIR/exp.body"
assert_not_contains "no Done When line" "Done When:" "$RESULT"
assert_eq "chunks_complete moved" "2" "$(fm_value "$STORY" chunks_complete)"
cleanup_test_dir
echo ""

# Test: already ticked stays ticked
begin_test "an already-ticked box stays ticked, even when named"
new_tick_fixture
sed -e 's/^- \[ \] Build passes$/- [x] Build passes/' -e 's/^- \[ \] Docs written$/- [X] Docs written/' "$TEST_DIR/before.md" > "$TEST_DIR/swap.md"
cp "$TEST_DIR/swap.md" "$STORY"
cp "$STORY" "$TEST_DIR/before.md"
write_nd "tick-story" 2 "Build passes" "never ran"
run_cc --not-done
STORY_TEXT=$(cat "$STORY")
assert_contains_literal "x kept" "- [x] Build passes" "$STORY_TEXT"
assert_contains_literal "X kept" "- [X] Docs written" "$STORY_TEXT"
assert_not_contains "no reason on a ticked box" "never ran" "$STORY_TEXT"
assert_contains_literal "the one open box is ticked" "Done When: chunk 2 - 1 ticked, 0 left open." "$RESULT"
cleanup_test_dir
echo ""

# Test: plain bullets, indented, nested, inline
begin_test "plain bullets, indented lines, nested boxes and the inline Done When form never change"
new_tick_fixture
set_story << 'EOF'

## Chunks

@@@ Chunk 1: First
**Done When:** inline text, not a list
- [ ] Inline form box stays

@@@ Chunk 2: Second
**Done When:**
- [ ] Real box
- Plain bullet
  - [ ] Nested box
  continuation line with - [ ] inside
    - [ ] Indented box
-  [ ] Two spaces after dash
- [] No space
EOF
write_nd "tick-story" 2
run_cc --not-done
same_body "$TEST_DIR/exp.body"
sed 's/^- \[ \] Real box$/- [x] Real box/' "$TEST_DIR/exp.body" > "$TEST_DIR/exp2.body"
assert_body "only the column-0 box ticked" "$TEST_DIR/exp2.body"
assert_contains_literal "counts" "1 ticked, 0 left open." "$RESULT"
cleanup_test_dir
echo ""

# Test: no Done When list
begin_test "a chunk with no Done When list changes nothing and still completes"
new_tick_fixture
set_story << 'EOF'

## Chunks

@@@ Chunk 2: Second
**Goal:** no list here

- [ ] Stray box outside any Done When list
EOF
write_nd "tick-story" 2
run_cc --not-done
same_body "$TEST_DIR/exp.body"
assert_body "body unchanged" "$TEST_DIR/exp.body"
assert_contains_literal "zero counts" "Done When: chunk 2 - 0 ticked, 0 left open." "$RESULT"
assert_eq "counters moved" "2" "$(fm_value "$STORY" chunks_complete)"
cleanup_test_dir
echo ""

# Test: lower-case heading
begin_test "a lower-case Done when heading ticks the same"
new_tick_fixture
sed 's/^\*\*Done When:\*\*$/**Done when:**/' "$TEST_DIR/before.md" > "$TEST_DIR/swap.md"
cp "$TEST_DIR/swap.md" "$STORY"
cp "$STORY" "$TEST_DIR/before.md"
write_nd "tick-story" 2
run_cc --not-done
tick_second_expected "$TEST_DIR/exp.body"
assert_body "second chunk ticked" "$TEST_DIR/exp.body"
cleanup_test_dir
echo ""

# Test: chunk heading forms
begin_test "Chunk 2/3 heading form is found; Chunk 1 never matches Chunk 10"
new_tick_fixture
set_story << 'EOF'

## Chunks

@@@ Chunk 10: Tenth
**Done When:**
- [ ] Ten A

@@@ Chunk 2/3: Split heading
**Done When:**
- [ ] Split A
EOF
write_nd "tick-story" 2
run_cc --not-done
same_body "$TEST_DIR/exp.body"
sed 's/^- \[ \] Split A$/- [x] Split A/' "$TEST_DIR/exp.body" > "$TEST_DIR/exp2.body"
assert_body "slash form ticked, tenth untouched" "$TEST_DIR/exp2.body"
cleanup_test_dir
new_tick_fixture
set_story << 'EOF'

@@@ Chunk 10: Tenth
**Done When:**
- [ ] Ten A
EOF
write_state "tick-story" 1 3
write_nd "tick-story" 1
run_cc --not-done
same_body "$TEST_DIR/exp.body"
assert_body "the first chunk does not touch the tenth" "$TEST_DIR/exp.body"
assert_contains_literal "zero counts" "0 ticked, 0 left open." "$RESULT"
cleanup_test_dir
echo ""

# Test: fences
begin_test "fenced examples are ignored"
new_tick_fixture
set_story << 'EOF'

## Chunks

@@@ Chunk 2: Second
Example of the format:

```
**Done When:**
- [ ] Fenced box
@@@ Chunk 3: Fenced heading
```

**Done When:**
- [ ] Real one
~~~
- [ ] Tilde fenced box
~~~
- [ ] Real two
EOF
write_nd "tick-story" 2
run_cc --not-done
same_body "$TEST_DIR/exp.body"
sed -e 's/^- \[ \] Real one$/- [x] Real one/' -e 's/^- \[ \] Real two$/- [x] Real two/' "$TEST_DIR/exp.body" > "$TEST_DIR/exp2.body"
assert_body "only the real list ticked" "$TEST_DIR/exp2.body"
assert_contains_literal "counts" "2 ticked, 0 left open." "$RESULT"
cleanup_test_dir
echo ""

# Test: box name matches nothing
begin_test "a box name that matches nothing changes no line"
new_tick_fixture
write_nd "tick-story" 2 "Nonexistent box" "whatever"
run_cc --not-done
same_body "$TEST_DIR/exp.body"
assert_body "no change (no match)" "$TEST_DIR/exp.body"
assert_contains_literal "refusal line" "no boxes changed (" "$RESULT"
assert_eq "counters still move" "2" "$(fm_value "$STORY" chunks_complete)"
cleanup_test_dir
new_tick_fixture
same_body "$TEST_DIR/exp.body"
write_nd "tick-story" 2 "One A" "a box of another chunk"
run_cc --not-done
assert_body "no change (box of another chunk)" "$TEST_DIR/exp.body"
assert_contains_literal "refusal line (other chunk)" "no boxes changed (" "$RESULT"
cleanup_test_dir
new_tick_fixture
same_body "$TEST_DIR/exp.body"
write_nd "tick-story" 2 "Acceptance one" "a box in Acceptance"
run_cc --not-done
assert_body "no change (Acceptance box)" "$TEST_DIR/exp.body"
assert_contains_literal "refusal line (Acceptance)" "no boxes changed (" "$RESULT"
cleanup_test_dir
echo ""

# Test: wrong chunk or story
begin_test "a file for another chunk or another story changes no line"
new_tick_fixture
write_nd "tick-story" 1
run_cc --not-done
same_body "$TEST_DIR/exp.body"
assert_body "file for the first chunk, second current" "$TEST_DIR/exp.body"
assert_contains_literal "refusal" "no boxes changed (" "$RESULT"
cleanup_test_dir
new_tick_fixture
same_body "$TEST_DIR/exp.body"
write_nd "other-story" 2
run_cc --not-done
assert_body "other story's file" "$TEST_DIR/exp.body"
assert_contains_literal "refusal" "no boxes changed (" "$RESULT"
assert_eq "completes anyway" "0" "$EXIT_CODE"
cleanup_test_dir
echo ""

# Test: malformed files
begin_test "a malformed file changes no line"
new_tick_fixture
same_body "$TEST_DIR/exp.body"
check_malformed() { # <desc>; the file is already written
  cp "$TEST_DIR/before.md" "$STORY"
  write_state "tick-story" 2 3
  run_cc --not-done
  assert_body "$1: no change" "$TEST_DIR/exp.body"
  assert_contains_literal "$1: refusal line" "no boxes changed (" "$RESULT"
  assert_eq "$1: exit 0" "0" "$EXIT_CODE"
}
: > "$ND"
check_malformed "empty file"
printf 'story: tick-story\nchunk: 2\nbox: Build passes\n' > "$ND"
check_malformed "box with no reason"
printf 'story: tick-story\nchunk: 2\nbox: Build passes\nreason:\n' > "$ND"
check_malformed "empty reason"
printf 'story: tick-story\nchunk: 2\nbox: Build passes\nreason: \n' > "$ND"
check_malformed "blank reason"
printf 'story: tick-story\nchunk: 2\nfoo: bar\n' > "$ND"
check_malformed "unknown field"
printf 'story: tick-story\nchunk: 2\nchunk: 2\n' > "$ND"
check_malformed "chunk twice"
printf 'story: tick-story\nchunk: 2\nbox: Build passes\nreason: caf\351 \377\n' > "$ND"
check_malformed "non-UTF-8 bytes"
cleanup_test_dir
echo ""

# Test: flag with no file
begin_test "the flag with no file changes no line and still completes"
new_tick_fixture
run_cc --not-done
same_body "$TEST_DIR/exp.body"
assert_body "no change" "$TEST_DIR/exp.body"
assert_contains_literal "refusal" "no boxes changed (" "$RESULT"
assert_eq "exit 0" "0" "$EXIT_CODE"
assert_eq "counters moved" "2" "$(fm_value "$STORY" chunks_complete)"
assert_eq "last line" "Chunk 2 complete. Now on chunk 3 of 3." "$(last_line "$RESULT")"
cleanup_test_dir
echo ""

# Test: no cycle dir, the way the build loop calls it
begin_test "the flag with no cycle dir finds the file and ticks"
new_tick_fixture
write_nd "tick-story" 2
set +e
RESULT=$(cd "$TEST_DIR" && CRAFT_PROJECT_ROOT="$TEST_DIR" bash "$COMPLETE_CHUNK_SCRIPT" --not-done 2>/dev/null)
EXIT_CODE=$?
set -e
assert_eq "exit 0" "0" "$EXIT_CODE"
tick_second_expected "$TEST_DIR/exp.body"
assert_body "boxes ticked" "$TEST_DIR/exp.body"
assert_file_not_exists "file removed" "$ND"
assert_eq "counters moved" "2" "$(fm_value "$STORY" chunks_complete)"
cleanup_test_dir
echo ""

# Test: wrapped item
begin_test "a wrapped item is named by its box line"
new_tick_fixture
set_story << 'EOF'

@@@ Chunk 2: Second
**Done When:**
- [ ] A long item that wraps
  onto an indented continuation line
- [ ] Short item
EOF
write_nd "tick-story" 2 "A long item that wraps" "not run"
run_cc --not-done
same_body "$TEST_DIR/exp.body"
sed -e 's/^\(- \[ \] A long item that wraps\)$/\1 (not done: not run)/' -e 's/^- \[ \] Short item$/- [x] Short item/' "$TEST_DIR/exp.body" > "$TEST_DIR/exp2.body"
assert_body "reason on box line, continuation untouched" "$TEST_DIR/exp2.body"
cleanup_test_dir
echo ""

# Test: control characters in the reason
begin_test "a reason with line breaks, a tab and an escape character is written on one line"
new_tick_fixture
printf 'story: tick-story\nchunk: 2\nbox: Docs written\n' > "$ND"
printf 'reason: first\tsecond\033[31m third\rfourth\r\n' >> "$ND"
run_cc --not-done
assert_eq "one line, controls are spaces" "- [ ] Docs written (not done: first second [31m third fourth)" "$(grep '^- \[ \] Docs written' "$STORY")"
assert_eq "no escape character remains" "0" "$(grep -c "$(printf '\033')" "$STORY" || true)"
assert_eq "line count unchanged" "$(wc -l < "$TEST_DIR/before.md" | tr -d ' ')" "$(wc -l < "$STORY" | tr -d ' ')"
cleanup_test_dir
echo ""

# Test: hostile reason
begin_test "a reason holding command substitution, backticks and quotes is written verbatim and nothing runs"
new_tick_fixture
HOSTILE='$(touch pwned) `touch pwned2` "dq" '"'"'sq'"'"' \n $HOME'
write_nd "tick-story" 2 "Docs written" "$HOSTILE"
run_cc --not-done
assert_file_not_exists "no pwned" "$TEST_DIR/pwned"
assert_file_not_exists "no pwned2" "$TEST_DIR/pwned2"
assert_contains_literal "verbatim" "(not done: $HOSTILE)" "$(cat "$STORY")"
cleanup_test_dir
echo ""

# Test: duplicate text
begin_test "two boxes with the same text both stay open when named once"
new_tick_fixture
set_story << 'EOF'

@@@ Chunk 2: Second
**Done When:**
- [ ] Same text
- [ ] Same text
- [ ] Other
EOF
write_nd "tick-story" 2 "Same text" "reason"
run_cc --not-done
assert_eq "both annotated" "2" "$(grep -c '^- \[ \] Same text (not done: reason)$' "$STORY" || true)"
assert_contains_literal "other ticked" "- [x] Other" "$(cat "$STORY")"
assert_contains_literal "counts" "1 ticked, 2 left open." "$RESULT"
cleanup_test_dir
echo ""

# Test: file removed on every path
begin_test "the open-box file is gone after a success, a refusal and an early exit 1"
new_tick_fixture
write_nd "tick-story" 2
run_cc --not-done
assert_file_not_exists "after success" "$ND"
cleanup_test_dir
new_tick_fixture
write_nd "other-story" 2
run_cc --not-done
assert_file_not_exists "after refusal" "$ND"
cleanup_test_dir
new_tick_fixture
write_state "" 0 0
write_nd "tick-story" 2
run_cc --not-done
assert_eq "early exit is 1" "1" "$EXIT_CODE"
assert_file_not_exists "after early exit 1" "$ND"
cleanup_test_dir
echo ""

# Test: CRLF, no final newline, mode
begin_test "CRLF lines keep CRLF, a missing final newline stays missing, and mode 0644 stays 0644"
new_tick_fixture
printf -- '---\nname: tick-story\nchunks_complete: 1\ncurrent_chunk: 2\nupdated: 2026-02-14\n---\r\n### Chunk 2: Second\r\n**Done When:**\r\n- [ ] Crlf one\r\n- [ ] Crlf two\r\n- [ ] Last no newline' > "$STORY"
chmod 0644 "$STORY"
write_nd "tick-story" 2 "Crlf two" "r"
run_cc --not-done
printf -- '---\nname: tick-story\nchunks_complete: 2\ncurrent_chunk: 3\nupdated: %s\n---\r\n### Chunk 2: Second\r\n**Done When:**\r\n- [x] Crlf one\r\n- [ ] Crlf two (not done: r)\r\n- [x] Last no newline' "$(date +%Y-%m-%d)" > "$TEST_DIR/exp.md"
if cmp -s "$TEST_DIR/exp.md" "$STORY"; then
  assert_eq "bytes exact (CRLF kept, no final newline)" "same" "same"
else
  assert_eq "bytes exact (CRLF kept, no final newline)" "same" "differs: $(od -c "$STORY" | tail -8 | tr '\n' '|')"
fi
MODE=$(stat -c '%a' "$STORY" 2>/dev/null || stat -f '%Lp' "$STORY")
assert_eq "mode kept" "644" "$MODE"
cleanup_test_dir
echo ""

# Test: two stories whose names contain the current one
begin_test "two stories whose names contain the current one: only the current story moves"
for FLAG in "" "--not-done"; do
  TEST_DIR=$(create_craft_with_story "test-cycle" "auth-x" "X" "3" "active")
  CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"
  rm -f "$CYCLE_DIR/stories/1-auth-x.md"
  for NAME in 11-auth 1-auth; do
    STORY="$CYCLE_DIR/stories/$NAME.md"
    {
      cat << 'EOF'
---
name: auth
chunks_total: 3
chunks_complete: 0
current_chunk: 1
updated: 2026-01-01
---

@@@ Chunk 1: First
**Done When:**
- [ ] Auth box
EOF
    } | sed 's/^@@@ /### /' > "$STORY"
  done
  write_state "1-auth" 1 3
  ND="$TEST_DIR/.craft/.chunk-not-done.txt"
  printf 'story: 1-auth\nchunk: 1\n' > "$ND"
  cp "$CYCLE_DIR/stories/11-auth.md" "$TEST_DIR/other.before"
  STORY="$CYCLE_DIR/stories/1-auth.md"
  if [ -n "$FLAG" ]; then
    run_cc "$FLAG"
  else
    run_cc
  fi
  assert_eq "[$FLAG] 1-auth chunks_complete" "1" "$(fm_value "$STORY" chunks_complete)"
  assert_eq "[$FLAG] 1-auth current_chunk" "2" "$(fm_value "$STORY" current_chunk)"
  assert_eq "[$FLAG] 11-auth untouched" "same" "$(cmp -s "$TEST_DIR/other.before" "$CYCLE_DIR/stories/11-auth.md" && echo same || echo differs)"
  if [ -n "$FLAG" ]; then
    assert_eq "1-auth box ticked" "1" "$(grep -c '^- \[x\] Auth box$' "$CYCLE_DIR/stories/1-auth.md" || true)"
    assert_eq "11-auth box still open" "1" "$(grep -c '^- \[ \] Auth box$' "$CYCLE_DIR/stories/11-auth.md" || true)"
  fi
  cleanup_test_dir
done
echo ""

# Test: exact file missing, one numbered file
begin_test "exact file missing, one numbered file: its counters move"
TEST_DIR=$(create_craft_with_story "test-cycle" "test-story" "Test Story" "3" "active")
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"
STORY="$CYCLE_DIR/stories/1-test-story.md"
ND="$TEST_DIR/.craft/.chunk-not-done.txt"
cp "$STORY" "$TEST_DIR/before.md"
write_nd "test-story" 1
run_cc --not-done
assert_eq "chunks_complete" "1" "$(fm_value "$STORY" chunks_complete)"
assert_eq "current_chunk" "2" "$(fm_value "$STORY" current_chunk)"
assert_eq "updated today" "$(date +%Y-%m-%d)" "$(fm_value "$STORY" updated)"
assert_contains_literal "tick refuses" "no boxes changed (" "$RESULT"
same_body "$TEST_DIR/exp.body"
assert_body "body unchanged" "$TEST_DIR/exp.body"
cleanup_test_dir
echo ""

# Test: two numbered files
begin_test "exact file missing, two numbered files: neither is touched"
TEST_DIR=$(create_craft_with_story "test-cycle" "auth-x" "X" "3" "active")
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"
rm -f "$CYCLE_DIR/stories/1-auth-x.md"
for NAME in 1-auth 2-auth; do
  printf -- '---\nname: auth\nchunks_complete: 0\ncurrent_chunk: 1\nupdated: 2026-01-01\n---\nbody\n' > "$CYCLE_DIR/stories/$NAME.md"
done
write_state "auth" 1 3
cp "$CYCLE_DIR/stories/1-auth.md" "$TEST_DIR/a.before"
cp "$CYCLE_DIR/stories/2-auth.md" "$TEST_DIR/b.before"
run_cc
assert_eq "exit 0" "0" "$EXIT_CODE"
assert_eq "1-auth untouched" "same" "$(cmp -s "$TEST_DIR/a.before" "$CYCLE_DIR/stories/1-auth.md" && echo same || echo differs)"
assert_eq "2-auth untouched" "same" "$(cmp -s "$TEST_DIR/b.before" "$CYCLE_DIR/stories/2-auth.md" && echo same || echo differs)"
assert_eq "state moved" "2" "$(state_chunk)"
assert_eq "last line" "Chunk 1 complete. Now on chunk 2 of 3." "$(last_line "$RESULT")"
cleanup_test_dir
echo ""

# Test: loose match only
begin_test "exact file missing, only a loose match: it is not touched"
TEST_DIR=$(create_craft_with_story "test-cycle" "auth-x" "X" "3" "active")
CYCLE_DIR="$TEST_DIR/.craft/cycles/1-test-cycle"
rm -f "$CYCLE_DIR/stories/1-auth-x.md"
printf -- '---\nname: login-form\nchunks_complete: 0\ncurrent_chunk: 1\nupdated: 2026-01-01\n---\nbody\n' > "$CYCLE_DIR/stories/3-login-form.md"
write_state "login" 1 3
cp "$CYCLE_DIR/stories/3-login-form.md" "$TEST_DIR/a.before"
run_cc
assert_eq "exit 0" "0" "$EXIT_CODE"
assert_eq "loose match untouched" "same" "$(cmp -s "$TEST_DIR/a.before" "$CYCLE_DIR/stories/3-login-form.md" && echo same || echo differs)"
assert_eq "state moved" "2" "$(state_chunk)"
cleanup_test_dir
echo ""

# Test: build loop wiring
begin_test "the build loop's passed-chunk call passes the flag, and manual validation's calls do not"
IMPL_CMD="$SCRIPT_DIR/../commands/craft-story-implement.md"
VALIDATE_SKILL="$SCRIPT_DIR/../skills/validate-chunk/SKILL.md"
assert_contains "build loop uses the flag" "complete-chunk.sh --not-done" "$(cat "$IMPL_CMD")"
LOOP_CALLS=$(grep -c 'bash .*complete-chunk\.sh' "$IMPL_CMD" || true)
LOOP_FLAGGED=$(grep 'bash .*complete-chunk\.sh' "$IMPL_CMD" | grep -c -- '--not-done' || true)
assert_eq "every build loop call carries the flag" "$LOOP_CALLS" "$LOOP_FLAGGED"
VAL_CALLS=$(grep -c 'bash .*complete-chunk\.sh' "$VALIDATE_SKILL" || true)
VAL_FLAGGED=$(grep 'complete-chunk\.sh' "$VALIDATE_SKILL" | grep -c -- '--not-done' || true)
assert_eq "manual validation has its three calls" "3" "$VAL_CALLS"
assert_eq "no manual validation call carries the flag" "0" "$VAL_FLAGGED"
echo ""

# --- Summary ---
finish_tests
