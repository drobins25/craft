#!/bin/bash
# test-dashboard-command.sh — Static shape tests over commands/craft-dashboard.md
#
# The command file is thin instructions over dashboard-page.sh (Chunk 1) and
# dashboard-run.sh (story 2's wrapper). It cannot execute an AskUserQuestion,
# so this file asserts the text says the right things, in the right order,
# without leaking a raw machine code as user-facing output.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

CMD_FILE="$PLUGIN_ROOT/commands/craft-dashboard.md"

echo "=== test-dashboard-command.sh ==="
echo ""

begin_test "the command file exists with dashboard frontmatter"
assert_file_exists "commands/craft-dashboard.md exists" "$CMD_FILE"
assert_file_contains "frontmatter names dashboard" '^name: dashboard$' "$CMD_FILE"
echo ""

begin_test "the command names both seams"
assert_file_contains "references dashboard-page.sh --check" 'dashboard-page\.sh --check' "$CMD_FILE"
assert_file_contains "references dashboard-run.sh" 'dashboard-run\.sh' "$CMD_FILE"
echo ""

begin_test "the flow order is check, then rebuild, then open"
CHECK_LINE=$(grep -n 'dashboard-page\.sh --check' "$CMD_FILE" | head -1 | cut -d: -f1)
REBUILD_LINE=$(grep -n 'dashboard-run\.sh --root' "$CMD_FILE" | head -1 | cut -d: -f1)
OPEN_LINE=$(grep -n 'open "\$PAGE"' "$CMD_FILE" | head -1 | cut -d: -f1)
if [ -n "$CHECK_LINE" ] && [ -n "$REBUILD_LINE" ] && [ -n "$OPEN_LINE" ] \
  && [ "$CHECK_LINE" -lt "$REBUILD_LINE" ] && [ "$REBUILD_LINE" -lt "$OPEN_LINE" ]; then
  echo "  PASS: check ($CHECK_LINE) precedes rebuild ($REBUILD_LINE) precedes open ($OPEN_LINE)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected check < rebuild < open, got check=$CHECK_LINE rebuild=$REBUILD_LINE open=$OPEN_LINE"
  FAIL=$((FAIL + 1))
fi
echo ""

begin_test "the file:// link is stated as unconditional"
assert_file_contains "always-print instruction present" 'Always print' "$CMD_FILE"
assert_file_contains "the file:// line itself is documented" 'file://' "$CMD_FILE"
# "opening" never appears without "file://" on the same line or the line
# right after it - the link is never promised as a side note to a status verb.
BAD_OPENING=$(grep -n 'opening' "$CMD_FILE" | grep -v 'file://' || true)
if [ -z "$BAD_OPENING" ]; then
  echo "  PASS: no bare 'opening' mention without the link nearby"
  PASS=$((PASS + 1))
else
  echo "  FAIL: found 'opening' without 'file://' on the same line: $BAD_OPENING"
  FAIL=$((FAIL + 1))
fi
echo ""

begin_test "no machine reason code appears as user-facing output"
# The six degrade() call-site codes from dashboard-run.sh. Each may appear
# only where the file is talking ABOUT the mapping (a reason= comparison),
# never printed as the sentence itself.
for code in root-missing craft-missing python-missing builder-missing builder-error; do
  # These five should never appear at all in the command file - only
  # build-skipped-concurrent is named, because it is the one reason with
  # distinct user-facing wording; the rest share one generic sentence.
  if grep -q "$code" "$CMD_FILE"; then
    echo "  FAIL: machine code '$code' should not appear in the command file"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: machine code '$code' does not appear"
    PASS=$((PASS + 1))
  fi
done
assert_file_not_contains "the raw reason variable is never interpolated into printed output" '\$reason' "$CMD_FILE"
assert_file_contains "build-skipped-concurrent is named only in mapping context" 'build-skipped-concurrent' "$CMD_FILE"
assert_file_contains "the generic degraded sentence is present" "the rebuild didn't finish" "$CMD_FILE"
echo ""

begin_test "the edited-copy offer names the backup path"
assert_file_contains "backup path named in the behind branch" '\.craft/dashboard-backup\.html' "$CMD_FILE"
echo ""

begin_test "check-doc-drift finds no structural drift from the new command"
# check-doc-drift.sh also carries a repo-wide "unpushed feat: needs a
# CHANGELOG entry" gate (finding 9) that is pre-existing and, per this
# cycle's one-bump-at-the-end convention, intentionally stays red until
# cycle-complete - it is not this chunk's to fix. This test isolates the
# findings this chunk actually owns: the command must appear in the
# decision-tree Commands Reference and the doc command counts must match.
set +e
DRIFT_OUT=$(bash "$PLUGIN_ROOT/scripts/check-doc-drift.sh" 2>&1)
set -e
assert_not_contains "no [command] finding for /craft:dashboard" '\[command\] /craft:dashboard' "$DRIFT_OUT"
assert_not_contains "no [count] finding on the commands total" '\[count\].*commands' "$DRIFT_OUT"
echo ""

ROUTING_INDEX="$PLUGIN_ROOT/reference/orchestration-index.min"

begin_test "the orchestration index carries a DASHBOARD_OFFER routing row marked NOT AskUserQuestion"
ROUTING_ROW=$(grep "^DASHBOARD_OFFER=1" "$ROUTING_INDEX" || true)
if [ -n "$ROUTING_ROW" ]; then
  echo "  PASS: DASHBOARD_OFFER routing row present"
  PASS=$((PASS + 1))
else
  echo "  FAIL: no DASHBOARD_OFFER routing row found"
  FAIL=$((FAIL + 1))
fi
assert_contains "row is marked NOT AskUserQuestion" "NOT AskUserQuestion" "$ROUTING_ROW"
assert_contains "row names the command" "/craft:dashboard" "$ROUTING_ROW"
echo ""

begin_test "the orchestration index stays under its size ceiling"
INDEX_BYTES=$(wc -c < "$ROUTING_INDEX" | tr -d ' ')
if [ "$INDEX_BYTES" -lt 5632 ]; then
  echo "  PASS: index is $INDEX_BYTES bytes, under the 5632-byte ceiling"
  PASS=$((PASS + 1))
else
  echo "  FAIL: index is $INDEX_BYTES bytes, at or over the 5632-byte ceiling"
  FAIL=$((FAIL + 1))
fi
echo ""

finish_tests "test-dashboard-command"
