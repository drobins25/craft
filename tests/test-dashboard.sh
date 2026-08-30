#!/bin/bash
# test-dashboard.sh — Runs the dashboard builder's python unittest suite and
# translates its result into the pass/fail phrasing run-all.sh scrapes.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

echo "=== test-dashboard.sh ==="
echo ""

SUITE_DIR="$PLUGIN_ROOT/scripts/dashboard/__tests__"
TOP_DIR="$PLUGIN_ROOT/scripts/dashboard"

set +e
OUTPUT=$(python3 -m unittest discover -s "$SUITE_DIR" -t "$TOP_DIR" 2>&1)
RC=$?
set -e

RAN=$(echo "$OUTPUT" | grep -o 'Ran [0-9]* test' | grep -o '[0-9]*' | head -1)
RAN=${RAN:-0}
FAILURES=$(echo "$OUTPUT" | grep -o 'failures=[0-9]*' | grep -o '[0-9]*' | head -1)
ERRORS=$(echo "$OUTPUT" | grep -o 'errors=[0-9]*' | grep -o '[0-9]*' | head -1)
FAILED=$(( ${FAILURES:-0} + ${ERRORS:-0} ))

# A non-zero unittest exit with no parsed counts (import crash, missing
# python) must still register as a failure, never as silent green.
if [ "$RC" -ne 0 ] && [ "$FAILED" -eq 0 ]; then
  FAILED=1
fi

PASSED=$(( RAN - FAILED ))
if [ "$PASSED" -lt 0 ]; then
  PASSED=0
fi

if [ "$RC" -ne 0 ]; then
  echo "$OUTPUT"
else
  echo "$OUTPUT" | tail -3
fi

echo ""
echo "=== Results (test-dashboard): $PASSED passed, $FAILED failed ==="
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
