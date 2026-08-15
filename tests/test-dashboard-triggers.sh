#!/bin/bash
# test-dashboard-triggers.sh — The transition scripts rebuild the dashboard
# graph data: static wiring checks (exactly one silenced, guarded invocation
# per wired script) plus behavioral checks that stdout contracts survive and
# the graph actually lands.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"

HOOKS="$PLUGIN_ROOT/hooks/scripts"
# Fixed strings, not regex: the invocation line contains '||', which ERE
# reads as an empty alternation.
ANCHOR_STR='$SCRIPT_DIR/../../scripts/dashboard/dashboard-run.sh'
SILENCE_STR='>/dev/null 2>&1 || true'

# Counts one properly-formed invocation line: anchored on SCRIPT_DIR AND
# silenced AND guarded, all on the same line.
count_wired() {
  grep -F "$ANCHOR_STR" "$1" 2>/dev/null | grep -cF "$SILENCE_STR" || true
}

# All fifteen locked trigger scripts (move-story carries two invocations,
# one per destination branch).
WIRED_ONCE="complete-chunk.sh complete-story.sh start-story.sh delete-story.sh start-cycle.sh complete-cycle.sh create-story.sh create-cycle.sh update-story-status.sh notebook-capture.sh notebook-graduate-mark.sh notebook-done.sh dials-capture.sh process-request.sh"

echo "=== test-dashboard-triggers.sh ==="
echo ""

# --- Static wiring checks ---
begin_test "all fifteen locked trigger scripts carry exactly one silenced, guarded invocation"

for script in $WIRED_ONCE; do
  count=$(count_wired "$HOOKS/$script")
  assert_eq "$script has exactly one invocation" "1" "$count"
done

count=$(count_wired "$HOOKS/move-story.sh")
assert_eq "move-story.sh wires both destination branches" "2" "$count"
echo ""

begin_test "no other script in hooks/scripts invokes the wrapper"

TOTAL_FILES=$(grep -rlF "$ANCHOR_STR" "$HOOKS" | wc -l | tr -d ' ')
assert_eq "exactly the fifteen wired scripts reference the wrapper" "15" "$TOTAL_FILES"
echo ""

begin_test "complete-story.sh rebuilds before its deferred abort exit"

INVOKE_LINE=$(grep -nF "$ANCHOR_STR" "$HOOKS/complete-story.sh" | head -1 | cut -d: -f1)
ABORT_LINE=$(grep -n 'COMMIT_ABORTED:-0' "$HOOKS/complete-story.sh" | tail -1 | cut -d: -f1)
if [ -n "$INVOKE_LINE" ] && [ -n "$ABORT_LINE" ] && [ "$INVOKE_LINE" -lt "$ABORT_LINE" ]; then
  echo "  PASS: invocation (line $INVOKE_LINE) precedes the deferred abort exit (line $ABORT_LINE)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: invocation line '$INVOKE_LINE' does not precede abort guard line '$ABORT_LINE'"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Behavioral checks ---
begin_test "start-story.sh stdout is unchanged and the graph is rebuilt"

TEST_DIR=$(create_craft_with_story "trigger-cycle" "trigger-story" "Trigger Story" "3" "ready")
STORY="$TEST_DIR/.craft/cycles/1-trigger-cycle/stories/1-trigger-story.md"

set +e
OUT=$(cd "$TEST_DIR" && bash "$HOOKS/start-story.sh" "$STORY" 2>&1)
RC=$?
set -e

assert_exit_code "start-story exits 0" "0" "$RC"
LAST_LINE=$(echo "$OUT" | tail -1)
assert_eq "last stdout line unchanged" "Story started: 1-trigger-story (chunks: 3)" "$LAST_LINE"
assert_file_exists "graph.js rebuilt" "$TEST_DIR/.craft/dashboard/graph.js"
assert_file_contains "build-status reports ok" '"status":"ok"' "$TEST_DIR/.craft/dashboard/build-status.js"

cleanup_test_dir
echo ""

begin_test "delete-story.sh stdout is unchanged and the graph is rebuilt"

TEST_DIR=$(create_craft_with_story "trigger-cycle" "doomed-story" "Doomed Story" "2" "ready")
STORY="$TEST_DIR/.craft/cycles/1-trigger-cycle/stories/1-doomed-story.md"

set +e
OUT=$(cd "$TEST_DIR" && bash "$HOOKS/delete-story.sh" "$STORY" 2>&1)
RC=$?
set -e

assert_exit_code "delete-story exits 0" "0" "$RC"
LAST_LINE=$(echo "$OUT" | tail -1)
assert_eq "last stdout line unchanged" "Story deleted: 1-doomed-story" "$LAST_LINE"
assert_file_exists "graph.js rebuilt" "$TEST_DIR/.craft/dashboard/graph.js"

cleanup_test_dir
echo ""

begin_test "a trigger run with no python3 still succeeds with unchanged stdout"

TEST_DIR=$(create_craft_with_story "trigger-cycle" "degraded-story" "Degraded Story" "2" "ready")
STORY="$TEST_DIR/.craft/cycles/1-trigger-cycle/stories/1-degraded-story.md"

STUB=$(mktemp -d)
for tool in bash sh dirname basename mkdir printf date find rm cp mv cat grep sed ls touch awk head tail sort uniq wc tr mktemp env chmod ln; do
  src=$(command -v "$tool" 2>/dev/null) || continue
  ln -s "$src" "$STUB/$tool" 2>/dev/null || true
done

set +e
OUT=$(cd "$TEST_DIR" && PATH="$STUB" bash "$HOOKS/start-story.sh" "$STORY" 2>&1)
RC=$?
set -e

assert_exit_code "start-story exits 0 without python3" "0" "$RC"
LAST_LINE=$(echo "$OUT" | tail -1)
assert_eq "last stdout line unchanged without python3" "Story started: 1-degraded-story (chunks: 2)" "$LAST_LINE"
assert_file_contains "build-status degraded, not absent" '"reason":"python-missing"' "$TEST_DIR/.craft/dashboard/build-status.js"

rm -rf "$STUB"
cleanup_test_dir
echo ""

begin_test "notebook-graduate-mark.sh echoes the caller's relative path spelling unchanged"

TEST_DIR=$(create_craft_with_story "trigger-cycle" "graph-story" "Graph Story" "2" "ready")
mkdir -p "$TEST_DIR/.craft/notebook/ideas"
cat > "$TEST_DIR/.craft/notebook/ideas/2026-02-01-sample-idea.md" <<'IDEA'
---
type: idea
created: 2026-02-01
status: open
source: session 2026-02-01
tags: [sample]
---
A sample idea body line.
IDEA

set +e
OUT=$(cd "$TEST_DIR" && bash "$HOOKS/notebook-graduate-mark.sh" ".craft/notebook/ideas/2026-02-01-sample-idea.md" "sample-story" 2>&1)
RC=$?
set -e

assert_exit_code "graduate-mark exits 0" "0" "$RC"
LAST_LINE=$(echo "$OUT" | tail -1)
assert_eq "relative path spelling echoed unchanged" ".craft/notebook/ideas/2026-02-01-sample-idea.md" "$LAST_LINE"
assert_file_exists "graph rebuilt into the record's own project" "$TEST_DIR/.craft/dashboard/graph.js"

cleanup_test_dir
echo ""

begin_test "notebook-done.sh echoes the done/ destination and rebuilds the graph"

TEST_DIR=$(create_craft_with_story "trigger-cycle" "graph-story" "Graph Story" "2" "ready")
mkdir -p "$TEST_DIR/.craft/notebook/todos"
cat > "$TEST_DIR/.craft/notebook/todos/2026-02-02-sample-todo.md" <<'TODO'
---
type: todo
created: 2026-02-02
status: open
source: session 2026-02-02
tags: [sample]
---
A sample todo body line.
TODO

set +e
OUT=$(cd "$TEST_DIR" && bash "$HOOKS/notebook-done.sh" ".craft/notebook/todos/2026-02-02-sample-todo.md" 2>&1)
RC=$?
set -e

assert_exit_code "notebook-done exits 0" "0" "$RC"
LAST_LINE=$(echo "$OUT" | tail -1)
assert_eq "done/ destination echoed" ".craft/notebook/todos/done/2026-02-02-sample-todo.md" "$LAST_LINE"
assert_file_exists "graph rebuilt" "$TEST_DIR/.craft/dashboard/graph.js"

cleanup_test_dir
echo ""

begin_test "create-cycle.sh rebuilds and still echoes the cycle directory"

TEST_DIR=$(create_test_dir)
mkdir -p "$TEST_DIR/.craft/cycles"

set +e
OUT=$(bash "$HOOKS/create-cycle.sh" "sample-cycle" "Sample Cycle" "A goal" "$TEST_DIR" 2>&1)
RC=$?
set -e

assert_exit_code "create-cycle exits 0" "0" "$RC"
LAST_LINE=$(echo "$OUT" | tail -1)
assert_eq "cycle dir echoed unchanged" "$TEST_DIR/.craft/cycles/1-sample-cycle" "$LAST_LINE"
assert_file_contains "build-status reports ok" '"status":"ok"' "$TEST_DIR/.craft/dashboard/build-status.js"

cleanup_test_dir
echo ""

begin_test "update-story-status.sh derives the root from the story path, not the environment"

TEST_DIR=$(create_craft_with_story "trigger-cycle" "nested-story" "Nested Story" "2" "planning")
STORY="$TEST_DIR/.craft/cycles/1-trigger-cycle/stories/1-nested-story.md"

set +e
OUT=$(CRAFT_PROJECT_ROOT="" bash "$HOOKS/update-story-status.sh" "$STORY" ready 2>&1)
RC=$?
set -e

assert_exit_code "update-story-status exits 0" "0" "$RC"
LAST_LINE=$(echo "$OUT" | tail -1)
assert_eq "status sentence unchanged" "Story status updated to 'ready': $STORY" "$LAST_LINE"
assert_file_exists "graph rebuilt into the story's own project" "$TEST_DIR/.craft/dashboard/graph.js"

cleanup_test_dir
echo ""

begin_test "a cold capture still echoes its target file and the wrapper builds only inside capture's own .craft"

# notebook-capture's cold path creates .craft/notebook/ itself - so the
# wrapper correctly builds inside it. The wrapper's own never-create-.craft
# property is proven separately (test-dashboard-wrapper.sh test 4).
BARE=$(mktemp -d)

set +e
OUT=$(cd "$BARE" && CRAFT_PROJECT_ROOT="" bash "$HOOKS/notebook-capture.sh" idea "A stray idea" 2>&1)
RC=$?
set -e

assert_exit_code "cold capture exits 0" "0" "$RC"
LAST_LINE=$(echo "$OUT" | tail -1)
assert_contains "last line is still the captured file path" "notebook/ideas/" "$LAST_LINE"
# Capture's cold path creates .craft/notebook/ itself, so the wrapper must
# have built inside it - a missing dashboard here means the trigger never
# fired or the wrapper degraded on a healthy root.
assert_dir_exists "capture created its .craft" "$BARE/.craft"
assert_dir_exists "wrapper built inside capture's own .craft" "$BARE/.craft/dashboard"
assert_file_exists "seeded .gitignore rode along" "$BARE/.craft/dashboard/.gitignore"

rm -rf "$BARE"
echo ""

finish_tests "test-dashboard-triggers"
