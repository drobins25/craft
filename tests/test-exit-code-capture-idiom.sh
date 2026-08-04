#!/bin/bash
# test-exit-code-capture-idiom.sh — Guard: exit-code captures in test files must
# be wrapped in the set +e / set -e window.
#
# Under set -e, a bare `RC=$?` after a command substitution is decorative: a
# non-zero exit kills the whole test file before the capture line runs, so the
# assertion it feeds can never fail with its own message. The house idiom
# (established across the older suites) is:
#
#   set +e
#   OUT=$(command)
#   RC=$?
#   set -e
#
# This guard scans every test file that runs under set -e, tracks the set
# +e/-e state line by line, and fails on any `<VAR>=$?` capture that happens
# while errexit is on.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Detail: $2"; }

echo "=== test-exit-code-capture-idiom.sh ==="
echo ""

VIOLATIONS=$(python3 - "$SCRIPT_DIR" <<'PYEOF'
import os, re, sys
tests_dir = sys.argv[1]
violations = []
for fname in sorted(os.listdir(tests_dir)):
    if not (fname.startswith("test-") and fname.endswith(".sh")):
        continue
    path = os.path.join(tests_dir, fname)
    lines = open(path).read().splitlines()
    if not any(re.match(r'\s*set -e', l) for l in lines):
        continue
    errexit_on = False
    for i, line in enumerate(lines):
        if re.match(r'\s*set \+e\b', line):
            errexit_on = False
        elif re.match(r'\s*set -e', line):
            errexit_on = True
        elif errexit_on and re.match(r'\s*(local\s+)?[A-Za-z_][A-Za-z_0-9]*=\$\?\s*$', line):
            violations.append(f"{fname}:{i + 1}")
print("\n".join(violations))
PYEOF
)

if [ -z "$VIOLATIONS" ]; then
  pass "every exit-code capture in tests/ sits inside a set +e window"
else
  fail "unguarded exit-code capture(s) found" "$(echo "$VIOLATIONS" | tr '\n' ' ')- wrap in set +e / set -e (see this file's header)"
fi

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
