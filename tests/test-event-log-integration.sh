#!/bin/bash
# test-event-log-integration.sh — End-to-end test for Event Log Foundation
#
# Exercises the full lifecycle:
#   start-cycle → start-story → complete-chunk (x2) → complete-story → complete-cycle
# Verifies events appear in correct files with correct types and chronological order.

set -e

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$TESTS_DIR/../hooks/scripts"

# This file does not source test_helper.sh, so it pins the session id itself: the
# story scripts open and close a gate named by it, and CI has none.
export CLAUDE_CODE_SESSION_ID=craft-test-session

# Test infrastructure
PASS=0
FAIL=0
test_name=""

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name — $msg"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if echo "$haystack" | grep -q "$needle" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name — $msg"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
  fi
}

assert_gt() {
  local a="$1" b="$2" msg="$3"
  if [ "$a" -gt "$b" ] 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name — $msg"
    echo "    expected $a > $b"
  fi
}

# ── Setup: Create a full project structure ──
source "$TESTS_DIR/fixtures/with-story.sh"
dir=$(create_craft_with_story "int-cycle" "int-story" "Integration Story" "3" "ready")
cycle_dir="$dir/.craft/cycles/1-int-cycle"
story_file="$cycle_dir/stories/1-int-story.md"
events_dir="$cycle_dir/.events"

cleanup() { rm -rf "$dir"; }
trap cleanup EXIT

# ── Test 1: Start cycle produces cycle_started in _cycle.jsonl ──
test_name="start-cycle event"
bash "$SCRIPTS_DIR/start-cycle.sh" "$cycle_dir" >/dev/null 2>&1

assert_eq "1" "$([ -f "$events_dir/_cycle.jsonl" ] && echo 1 || echo 0)" "_cycle.jsonl exists"
cycle_events=$(cat "$events_dir/_cycle.jsonl" 2>/dev/null)
assert_contains "$cycle_events" '"type":"cycle_started"' "cycle_started event present"
assert_contains "$cycle_events" '"story":"_cycle"' "story field is _cycle"

# ── Test 2: Start story produces story_started ──
test_name="start-story event"
bash "$SCRIPTS_DIR/start-story.sh" "$story_file" >/dev/null 2>&1

assert_eq "1" "$([ -f "$events_dir/1-int-story.jsonl" ] && echo 1 || echo 0)" "story jsonl exists"
story_events=$(cat "$events_dir/1-int-story.jsonl" 2>/dev/null)
assert_contains "$story_events" '"type":"story_started"' "story_started event present"
assert_contains "$story_events" '"chunk_total":"3"' "chunk_total in data"

# ── Test 3: Complete chunk 1 produces chunk_completed ──
test_name="complete-chunk 1 event"
bash "$SCRIPTS_DIR/complete-chunk.sh" "$cycle_dir" >/dev/null 2>&1

story_events=$(cat "$events_dir/1-int-story.jsonl" 2>/dev/null)
chunk1_line=$(echo "$story_events" | grep '"type":"chunk_completed"' | head -1)
assert_contains "$chunk1_line" '"chunk":"1"' "chunk 1 recorded"
assert_contains "$chunk1_line" '"total":"3"' "total chunks in data"

# ── Test 4: Complete chunk 2 produces second chunk_completed ──
test_name="complete-chunk 2 event"
bash "$SCRIPTS_DIR/complete-chunk.sh" "$cycle_dir" >/dev/null 2>&1

story_events=$(cat "$events_dir/1-int-story.jsonl" 2>/dev/null)
chunk_count=$(echo "$story_events" | grep -c '"type":"chunk_completed"')
assert_eq "2" "$chunk_count" "two chunk_completed events"

chunk2_line=$(echo "$story_events" | grep '"type":"chunk_completed"' | tail -1)
assert_contains "$chunk2_line" '"chunk":"2"' "chunk 2 recorded"

# ── Test 5: Complete story produces story_completed ──
test_name="complete-story event"
bash "$SCRIPTS_DIR/complete-story.sh" "$story_file" >/dev/null 2>&1

story_events=$(cat "$events_dir/1-int-story.jsonl" 2>/dev/null)
assert_contains "$story_events" '"type":"story_completed"' "story_completed event present"

# ── Test 6: Complete cycle produces cycle_completed in _cycle.jsonl ──
test_name="complete-cycle event"

# Re-activate cycle (complete-story clears ACTIVE_CYCLE via complete flow)
bash "$SCRIPTS_DIR/start-cycle.sh" "$cycle_dir" >/dev/null 2>&1
bash "$SCRIPTS_DIR/complete-cycle.sh" "$cycle_dir" >/dev/null 2>&1

cycle_events=$(cat "$events_dir/_cycle.jsonl" 2>/dev/null)
assert_contains "$cycle_events" '"type":"cycle_completed"' "cycle_completed event present"

# ── Test 7: Event count verification ──
test_name="event counts"

story_event_count=$(wc -l < "$events_dir/1-int-story.jsonl" | tr -d ' ')
cycle_event_count=$(wc -l < "$events_dir/_cycle.jsonl" | tr -d ' ')

# Story: story_started + chunk_completed(x2) + story_completed = 4
assert_eq "4" "$story_event_count" "story has 4 events"

# Cycle: cycle_started + cycle_started(re-activate) + cycle_completed = 3
assert_eq "3" "$cycle_event_count" "cycle has 3 events"

# ── Test 8: Chronological ordering ──
test_name="chronological order"

# Extract timestamps from story events, verify each >= previous
prev_ts=""
ordering_ok="yes"
while IFS= read -r line; do
  ts=$(echo "$line" | sed 's/.*"timestamp":"\([^"]*\)".*/\1/')
  if [ -n "$prev_ts" ]; then
    # String comparison works for ISO timestamps
    if [[ "$ts" < "$prev_ts" ]]; then
      ordering_ok="no"
    fi
  fi
  prev_ts="$ts"
done < "$events_dir/1-int-story.jsonl"
assert_eq "yes" "$ordering_ok" "story events in chronological order"

# Same for cycle events
prev_ts=""
ordering_ok="yes"
while IFS= read -r line; do
  ts=$(echo "$line" | sed 's/.*"timestamp":"\([^"]*\)".*/\1/')
  if [ -n "$prev_ts" ]; then
    if [[ "$ts" < "$prev_ts" ]]; then
      ordering_ok="no"
    fi
  fi
  prev_ts="$ts"
done < "$events_dir/_cycle.jsonl"
assert_eq "yes" "$ordering_ok" "cycle events in chronological order"

# ── Test 9: read-events.sh filters correctly across full dataset ──
test_name="read-events filtering"

# Filter by type
chunk_events=$(bash "$SCRIPTS_DIR/read-events.sh" "$events_dir" --type=chunk_completed)
chunk_lines=$(echo "$chunk_events" | grep -c "chunk_completed" || echo 0)
assert_eq "2" "$chunk_lines" "read-events type filter returns 2 chunk_completed"

# Filter by story
story_only=$(bash "$SCRIPTS_DIR/read-events.sh" "$events_dir" --story=1-int-story)
story_only_count=$(echo "$story_only" | wc -l | tr -d ' ')
assert_eq "4" "$story_only_count" "read-events story filter returns 4 events"

# --last=1 returns only most recent
last_one=$(bash "$SCRIPTS_DIR/read-events.sh" "$events_dir" --story=1-int-story --last=1)
last_count=$(echo "$last_one" | wc -l | tr -d ' ')
assert_eq "1" "$last_count" "read-events --last=1 returns 1 event"
assert_contains "$last_one" '"type":"story_completed"' "last event is story_completed"

# ── Test 10: All event types have valid JSON ──
test_name="JSON validity"

all_valid="yes"
for jsonl_file in "$events_dir"/*.jsonl; do
  while IFS= read -r line; do
    # Basic JSON check: starts with { ends with }
    if [[ "$line" != "{"* ]] || [[ "$line" != *"}" ]]; then
      all_valid="no"
    fi
    # Has required fields
    if ! echo "$line" | grep -q '"timestamp"' || ! echo "$line" | grep -q '"type"' || ! echo "$line" | grep -q '"story"'; then
      all_valid="no"
    fi
  done < "$jsonl_file"
done
assert_eq "yes" "$all_valid" "all events are valid JSONL with required fields"

# ── Results ──
echo ""
echo "=== Results (test-event-log-integration): $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
