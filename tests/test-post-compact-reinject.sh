#!/bin/bash
# test-post-compact-reinject.sh - the post-compaction hook names a Go run's rule file
# only for a cycle whose copied Go says Craft answers its own prompts.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

HOOK="$SCRIPTS_DIR/post-compact-reinject.sh"
FREEFORM_EXPECTED="$SCRIPT_DIR/fixtures/go-run-unchanged/reinject-freeform.expected"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "=== test-post-compact-reinject.sh ==="
echo ""

# make_project <planning|active> <tracker|freeform> <answer|bring>
# Builds a temp project; PROJECT is its root, CYCLE its cycle dir.
make_project() {
  local where="$1" kind="$2" verdict="$3"
  PROJECT=$(mktemp -d "$WORK/proj.XXXXXX")
  CYCLE="$PROJECT/.craft/cycles/1-x"
  mkdir -p "$CYCLE/stories" "$CYCLE/context" "$PROJECT/.craft/backlog"
  if [ "$where" = planning ]; then
    printf 'ACTIVE_CYCLE=""\nCURRENT_STORY=""\nPLANNING_CYCLE="1-x"\n' > "$PROJECT/.craft/.global-state"
  else
    printf 'ACTIVE_CYCLE="1-x"\nCURRENT_STORY=""\nPLANNING_CYCLE=""\n' > "$PROJECT/.craft/.global-state"
  fi
  if [ "$kind" = tracker ]; then
    cat > "$CYCLE/cycle.yaml" <<YAML
name: x
title: "Cycle 01: X"
status: planning
source_concept: []
source_issue: 'DRO-21'
authorized_stage: 'build'
go_author: 'Darin'
go_date: '2026-10-31T18:40:00.000Z'

goals:
  - TBD
YAML
    local phrase='Workflow prompts: answer them yourself.'
    [ "$verdict" = bring ] && phrase='Workflow prompts: bring them to me.'
    printf '## Go - build (Wright, May 20, 2026)\n\nStage: build\nScope: Ship it\nRun rules: none saved\n%s\n' "$phrase" \
      > "$CYCLE/context/dro-21-go-20261031T1840Z.md"
  else
    printf 'name: x\ntitle: "Cycle 01: X"\nstatus: planning\nsource_concept: []\n\ngoals:\n  - TBD\n' > "$CYCLE/cycle.yaml"
  fi
}

run_hook() {
  set +e
  OUT=$(cd "$PROJECT" && CRAFT_PROJECT_ROOT="$PROJECT" bash "$HOOK" 2>/dev/null)
  EXIT_CODE=$?
  set -e
}

GO_LINE_PREFIX='Go on DRO-21: its run rules say Craft answers its own prompts up to stage build. If this conversation was running that Go, re-read '
GO_RUN_PATH="$ROOT/commands/references/go-run.md"

begin_test "reinject: answer Go on a planning cycle"
make_project planning tracker answer
run_hook
assert_eq "exits 0" "0" "$EXIT_CODE"
GO_LINES=$(printf '%s\n' "$OUT" | grep '^Go on ' || true)
assert_eq "one Go line, exact text" "${GO_LINE_PREFIX}${GO_RUN_PATH} before the next prompt." "$GO_LINES"
assert_contains "absolute path ends in go-run.md" "/commands/references/go-run.md before" "$GO_LINES"
LINE_NO=$(printf '%s\n' "$OUT" | grep -n '^Go on ' | cut -d: -f1)
END_NO=$(printf '%s\n' "$OUT" | grep -n '^--- END CRAFT CONTEXT ---' | cut -d: -f1)
if [ -n "$LINE_NO" ] && [ -n "$END_NO" ] && [ "$LINE_NO" -lt "$END_NO" ]; then
  echo "  PASS: Go line sits before the end marker"; PASS=$((PASS + 1))
else
  echo "  FAIL: Go line '$LINE_NO' not before end marker '$END_NO'"; FAIL=$((FAIL + 1))
fi

begin_test "reinject: answer Go on an active cycle"
make_project active tracker answer
run_hook
assert_contains "Go line present" "Go on DRO-21: its run rules say Craft answers its own prompts up to stage build." "$OUT"

begin_test "reinject: bring Go prints no Go line"
make_project planning tracker bring
run_hook
assert_eq "exits 0" "0" "$EXIT_CODE"
assert_not_contains "no Go line" "Go on " "$OUT"

begin_test "reinject: freeform cycle output equals the pre-edit output"
make_project planning freeform answer
run_hook
assert_eq "exits 0" "0" "$EXIT_CODE"
assert_not_contains "no Go line" "Go on " "$OUT"
assert_eq "byte-identical to the captured output" "$(cat "$FREEFORM_EXPECTED")" "$OUT"

begin_test "reinject: no cycle set prints no Go line"
make_project planning freeform answer
printf 'ACTIVE_CYCLE=""\nCURRENT_STORY=""\nPLANNING_CYCLE=""\n' > "$PROJECT/.craft/.global-state"
run_hook
assert_eq "exits 0" "0" "$EXIT_CODE"
assert_not_contains "no Go line" "Go on " "$OUT"

begin_test "reinject survives a broken go-brief"
make_project planning tracker answer
chmod 000 "$CYCLE/cycle.yaml"
run_hook
chmod 644 "$CYCLE/cycle.yaml"
assert_eq "exits 0" "0" "$EXIT_CODE"
assert_not_contains "no Go line" "Go on " "$OUT"
assert_contains_literal "context block still ends" "--- END CRAFT CONTEXT ---" "$OUT"
rm -f "$CYCLE/cycle.yaml"
run_hook
assert_eq "missing cycle.yaml exits 0" "0" "$EXIT_CODE"
assert_not_contains "missing cycle.yaml, no Go line" "Go on " "$OUT"

finish_tests
