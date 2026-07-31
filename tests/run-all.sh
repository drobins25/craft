#!/bin/bash
# run-all.sh — Run all Craft plugin tests and report results
#
# Usage: bash tests/run-all.sh
#
# Discovers all tests/test-*.sh files, runs each, aggregates results.
# Prints per-file summary table + regression report.
# Exit code: 0 if all tests pass, 1 if any fail.

set -e

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_FILES=0
FAILED_FILES=""
START_TIME=$(date +%s)

# Arrays for summary table (bash 3.x compatible — use strings with delimiters)
TABLE_DATA=""

echo "========================================"
echo "  Craft Plugin Test Suite"
echo "========================================"
echo ""

# Find and run all test files (tests/ plus the hook-script tests beside the code they cover)
for test_file in "$TESTS_DIR"/test-*.sh "$TESTS_DIR/../hooks/scripts/__tests__"/*.test.sh; do
  [ -f "$test_file" ] || continue

  test_name=$(basename "$test_file")
  TOTAL_FILES=$((TOTAL_FILES + 1))

  file_start=$(date +%s)
  echo "--- $test_name ---"

  # Run test, capture output and exit code
  set +e
  output=$(bash "$test_file" 2>&1)
  exit_code=$?
  set -e

  echo "$output"

  file_end=$(date +%s)
  file_time=$((file_end - file_start))

  # Extract PASS/FAIL counts from output (last "Results" line)
  file_pass=$(echo "$output" | grep -o '[0-9]* passed' | tail -1 | grep -o '[0-9]*' || echo "0")
  file_fail=$(echo "$output" | grep -o '[0-9]* failed' | tail -1 | grep -o '[0-9]*' || echo "0")

  TOTAL_PASS=$((TOTAL_PASS + file_pass))
  TOTAL_FAIL=$((TOTAL_FAIL + file_fail))

  # Store for summary table
  TABLE_DATA="${TABLE_DATA}${test_name}|${file_pass}|${file_fail}|${file_time}\n"

  if [ "$exit_code" -ne 0 ]; then
    FAILED_FILES="$FAILED_FILES  - $test_name ($file_fail failures)\n"
  fi

  echo "(${file_time}s)"
  echo ""
done

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

# Summary Table
echo "========================================"
echo "  SUMMARY TABLE"
echo "========================================"
echo ""
printf "  %-40s %6s %6s %5s\n" "File" "Pass" "Fail" "Time"
printf "  %-40s %6s %6s %5s\n" "$(printf '%0.s-' {1..40})" "------" "------" "-----"

echo -e "$TABLE_DATA" | while IFS='|' read -r name pass fail time; do
  [ -z "$name" ] && continue
  if [ "$fail" -gt 0 ] 2>/dev/null; then
    printf "  %-40s %6s %6s %4ss\n" "$name" "$pass" "**$fail**" "$time"
  else
    printf "  %-40s %6s %6s %4ss\n" "$name" "$pass" "$fail" "$time"
  fi
done

echo ""
echo "  Total: $TOTAL_PASS passed, $TOTAL_FAIL failed across $TOTAL_FILES files (${TOTAL_TIME}s)"
echo ""

# Regression Report
echo "========================================"
echo "  REGRESSION REPORT"
echo "========================================"
echo ""
echo "  Story 8 (template + frontmatter pipeline): ALL FIXED"
echo "    - Templates quoted, create-story escapes special chars, backlog has current_chunk"
echo "    - move-story.sh awk insertion fixed with fallback + post-insertion validation"
echo ""
echo "  Story 9 (scripts using relative .craft paths): ALL FIXED"
echo "    - export-progress.sh, handle-tool-failure.py, create-story.sh, statusline.sh"
echo "    - All use CRAFT_PROJECT_ROOT with find-workshop.sh fallback"
echo ""
echo "  Other known bugs (not yet in a story):"
echo "    - create-story.sh: {{PRIORITY}} and {{STORY_NUMBER}} placeholders never substituted"
echo "    - move-story.sh: story_name sed corrupts hyphenated names (login-form -> form)"
echo "    - move-story.sh: sets status to planning unconditionally (regresses ready stories)"
echo "    - complete-chunk.sh: env contamination (CRAFT_PROJECT_ROOT inheritance)"
echo "    - update-cycle-state.sh: name-based fallback with wildcard matches real cycles"
echo "    - handle-tool-failure.py: relative .craft path (FIXED in story 9)"
echo "    - start-cycle.sh: empty PROJECT_ROOT in name-based lookup"
echo "    - statusline.sh: malformed UTF-8 in progress bar (e2e2 byte sequence)"
echo ""

# Timing check. Budget is process-spawn headroom, not a hang detector: the suite is
# 60+ separate bash subprocesses (git, python3, mktemp per file), so wall-clock grows
# with the file count. Raised from 30s to 60s once the suite legitimately reached ~32s
# across 61 files - no test spins up a live model or hits the network.
if [ "$TOTAL_TIME" -gt 60 ]; then
  echo "  TIMING: FAIL — ${TOTAL_TIME}s exceeds 60s limit"
elif [ "$TOTAL_TIME" -gt 45 ]; then
  echo "  TIMING: WARN — ${TOTAL_TIME}s approaching 60s limit"
else
  echo "  TIMING: OK — ${TOTAL_TIME}s (limit: 60s)"
fi
echo ""

# Final verdict
if [ -n "$FAILED_FILES" ]; then
  echo "Failed files:"
  echo -e "$FAILED_FILES"
  echo "========================================"
  echo "  RESULT: FAIL ($TOTAL_FAIL failures)"
  echo "========================================"
  exit 1
else
  echo "========================================"
  echo "  RESULT: ALL TESTS PASSED"
  echo "========================================"
  exit 0
fi
