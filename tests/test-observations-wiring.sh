#!/bin/bash
# test-observations-wiring.sh - Chunk 5: implementer Bar + orchestrator wiring.
# Doc-level assertions that the three high-traffic files carry the required wiring.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

IMPL="$PLUGIN_ROOT/agents/implementer.md"
STORY_IMPL="$PLUGIN_ROOT/commands/craft-story-implement.md"
CYCLE_COMPLETE="$PLUGIN_ROOT/commands/craft-cycle-complete.md"

# --- implementer.md: the Bar + return schema ---
begin_test "implementer doc carries the Bar and Observations schema"
assert_file_exists "implementer.md exists" "$IMPL"
assert_file_contains "has Observations section" "^## Observations" "$IMPL"
assert_file_contains "confirmed/suspicion grades" "confirmed.*suspicion" "$IMPL"
assert_file_contains "pipe-delimited schema example" "grade=confirmed | severity=high" "$IMPL"

# --- craft-story-implement.md: parse + chain-end surfacing ---
begin_test "story-implement gates the parse behind no-mismatch"
assert_file_contains "has Observations parse step" "Observations parse" "$STORY_IMPL"
assert_file_contains "skips parse on CONTRACT MISMATCH" "Skip this parse entirely on a CONTRACT MISMATCH" "$STORY_IMPL"
assert_file_contains "calls observations-append.sh" "observations-append.sh" "$STORY_IMPL"

begin_test "story-implement parse skips malformed bullets and continues"
assert_file_contains "malformed-bullet safety" "Malformed-bullet safety" "$STORY_IMPL"
assert_file_contains "skip and continue" "SKIP it.*CONTINUE to the next bullet" "$STORY_IMPL"

begin_test "story-implement chain-end surfacing wired"
assert_file_contains "Step 9a surfacing" "Surface unread observations" "$STORY_IMPL"
assert_file_contains "reads the surfacing reference" "observations-surfacing.md" "$STORY_IMPL"
assert_file_contains "recomputes via count helper" "observations-count.sh" "$STORY_IMPL"

begin_test "story-implement autonomous mode is a no-op at surfacing"
assert_file_contains "RUN_MODE autonomous guard" "RUN_MODE == autonomous" "$STORY_IMPL"
assert_file_contains "accumulate unattended" "accumulate across the unattended run" "$STORY_IMPL"

# --- craft-cycle-complete.md: surfacing before archive ---
begin_test "cycle-complete references surfacing before archive"
assert_file_contains "has surfacing step" "Surface Unread Observations" "$CYCLE_COMPLETE"
assert_file_contains "reads the surfacing reference" "observations-surfacing.md" "$CYCLE_COMPLETE"
# The surfacing step must appear BEFORE the complete-cycle.sh archive call.
surfacing_ln=$(grep -n "Surface Unread Observations" "$CYCLE_COMPLETE" | head -1 | cut -d: -f1)
archive_ln=$(grep -n "complete-cycle.sh" "$CYCLE_COMPLETE" | head -1 | cut -d: -f1)
if [ -n "$surfacing_ln" ] && [ -n "$archive_ln" ] && [ "$surfacing_ln" -lt "$archive_ln" ]; then
  echo "  PASS: surfacing step precedes the archive call"
  PASS=$((PASS + 1))
else
  echo "  FAIL: surfacing not before archive (surf=$surfacing_ln archive=$archive_ln)"
  FAIL=$((FAIL + 1))
fi
assert_file_contains "cycle-complete autonomous no-op" "RUN_MODE == autonomous" "$CYCLE_COMPLETE"

finish_tests
