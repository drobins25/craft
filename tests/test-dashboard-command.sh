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

begin_test "the mining step sits between the rebuild and the open"
MINE_LINE=$(grep -n 'insights-check\.sh --check' "$CMD_FILE" | head -1 | cut -d: -f1)
REBUILD_LINE=$(grep -n 'dashboard-run\.sh --root' "$CMD_FILE" | head -1 | cut -d: -f1)
OPEN_LINE=$(grep -n 'open "\$PAGE"' "$CMD_FILE" | head -1 | cut -d: -f1)
if [ -n "$MINE_LINE" ] && [ -n "$REBUILD_LINE" ] && [ -n "$OPEN_LINE" ] \
  && [ "$REBUILD_LINE" -lt "$MINE_LINE" ] && [ "$MINE_LINE" -lt "$OPEN_LINE" ]; then
  echo "  PASS: rebuild ($REBUILD_LINE) precedes mining ($MINE_LINE) precedes open ($OPEN_LINE)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected rebuild < mining < open, got rebuild=$REBUILD_LINE mining=$MINE_LINE open=$OPEN_LINE"
  FAIL=$((FAIL + 1))
fi
echo ""

begin_test "the mining step gates on the freshness verdict"
MINING_STEP=$(sed -n '/### Step 2.5/,/### Step 3/p' "$CMD_FILE")
assert_contains "the step runs insights-check.sh" 'insights-check\.sh' "$MINING_STEP"
assert_contains "the step names the stale verdict" 'VERDICT=stale' "$MINING_STEP"
assert_contains "the step names the missing verdict" 'VERDICT=missing' "$MINING_STEP"
assert_contains "the fresh verdict does nothing and says nothing" 'say nothing' "$MINING_STEP"
assert_contains "the step is silent on every path" 'silent on every path' "$MINING_STEP"
assert_contains "the step stamps after authoring" 'insights-check\.sh --stamp' "$MINING_STEP"
echo ""

begin_test "the mining reference is anchored in the substitution form"
assert_file_contains "the reference anchor is present" '\${CLAUDE_PLUGIN_ROOT}/commands/references/insight-mining\.md' "$CMD_FILE"
assert_file_exists "the anchored reference exists" "$PLUGIN_ROOT/commands/references/insight-mining.md"
echo ""

REF_FILE="$PLUGIN_ROOT/commands/references/insight-mining.md"

begin_test "the register rules are present in the reference"
assert_file_contains "second person is binding" 'Second person' "$REF_FILE"
assert_file_contains "the affectionate-roast rule is binding" 'Affectionate roast, never snark' "$REF_FILE"
assert_file_contains "no bare number as the whole card" 'Never a bare number as the whole card' "$REF_FILE"
assert_file_contains "one fact plus one turn of phrase per card" 'One specific fact PLUS one turn of phrase' "$REF_FILE"
assert_file_contains "no gamified cheer" 'No gamified cheer' "$REF_FILE"
echo ""

begin_test "the structural evidence rule is stated as a hard gate"
assert_file_contains "a card must cite an evidence id present in graph.js" 'cites at least one `evidence_node_ids` entry that exists in `graph\.js`' "$REF_FILE"
assert_file_contains "an uncitable card is discarded, never softened" 'discarded - never softened' "$REF_FILE"
assert_file_contains "too little material writes no sidecar" 'fewer than 3 mirror-backed cards gets NO sidecar' "$REF_FILE"
echo ""

begin_test "the witness assignment rule is present in the reference"
assert_file_contains "the conductor is in the roster" 'the conductor' "$REF_FILE"
assert_file_contains "the muse is in the roster" 'the muse' "$REF_FILE"
assert_file_contains "the alchemist is in the roster" 'the alchemist' "$REF_FILE"
assert_file_contains "riff is in the roster" '| riff | `riff` |' "$REF_FILE"
assert_file_contains "cycle/story/planning map to the conductor" 'cycle / story / planning | `the conductor`' "$REF_FILE"
assert_file_contains "fix/tweak/dial map to the alchemist" 'fix / tweak / dial | `the alchemist`' "$REF_FILE"
assert_file_contains "the mapping keys off the first evidence node type" 'FIRST evidence node' "$REF_FILE"
echo ""

begin_test "the existing command surface is unchanged"
assert_file_contains "the Step 5 offer is untouched" 'Want to hear the weirdest thing you ever did in here? Just ask\.' "$CMD_FILE"
assert_file_contains "the reveal text is untouched" "your project's second brain" "$CMD_FILE"
assert_file_contains "the degraded sentence is untouched" "the rebuild didn't finish" "$CMD_FILE"
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
