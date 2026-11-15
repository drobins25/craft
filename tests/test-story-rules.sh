#!/bin/bash
# test-story-rules.sh - A story built from a mockup hands its rules to the
# planner and the builder; every other story hands them nothing.
#
# story-rules.sh is the one place those two agents learn that a story came
# from a mockup. Pins:
#   - a story with no mockup prints nothing, so the common path stays silent;
#   - a mockup story prints the checked facts and only that reader's rules;
#   - the mockup field works as a record name or as a path to the record;
#   - a failed check never looks like "nothing applies";
#   - a mockup that cannot be read holds the rules back and says what to do;
#   - the planner, the builder and the build launch still point at the script;
#   - the story check never rewords a mockup's port-it-unchanged line.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

RULES_SCRIPT="$SCRIPTS_DIR/story-rules.sh"
RULES_FILE="$PLUGIN_ROOT/commands/references/mockup-story-rules.md"

echo "=== test-story-rules.sh ==="
echo ""

TEST_DIR=$(create_test_dir)
STORIES="$TEST_DIR/.craft/cycles/1-demo/stories"
mkdir -p "$STORIES" "$TEST_DIR/.craft/mockups/2026-01-02-hero"
echo "<html></html>" > "$TEST_DIR/.craft/mockups/2026-01-02-hero/mockup.html"

# write_story <file> <mockup field line or empty> <body>
write_story() {
  local file="$1" field="$2" body="$3"
  {
    echo "---"
    echo "name: demo"
    echo "type: ui"
    [ -n "$field" ] && echo "$field"
    echo "status: planning"
    echo "---"
    echo ""
    echo "# Story: Demo"
    echo ""
    printf '%s\n' "$body"
  } > "$file"
}

TABLE='## Visual Direction

**Element Binding Table**
| Part | Role/State | Token | Value/Source |
|------|------------|-------|--------------|
| hero | surface | primary | mockup `#hero` |
| title | on-surface | TBD | mockup `#hero h1` |
| pulse | resting | - | mockup `#pulse` |

## Chunks

### Chunk 1: Hero

| Part | Role/State | Token | Value/Source |
|------|------------|-------|--------------|
| a row inside the plan | x | y | z |'

# run_rules <story> <role> - sets OUT and RC
run_rules() {
  set +e
  OUT=$(bash "$RULES_SCRIPT" "$1" "$2" 2>&1)
  RC=$?
  set -e
}

begin_test "a story with no mockup field prints nothing"
write_story "$STORIES/1-plain.md" "" "## Spark"
run_rules "$STORIES/1-plain.md" planner
assert_eq "exit code is 0" "0" "$RC"
assert_eq "output is empty" "" "$OUT"

begin_test "an empty mockup field prints nothing"
write_story "$STORIES/2-empty.md" "mockup:" "## Spark"
run_rules "$STORIES/2-empty.md" builder
assert_eq "exit code is 0" "0" "$RC"
assert_eq "output is empty" "" "$OUT"

begin_test "a mockup story gives the planner its facts and its own rules"
write_story "$STORIES/3-mockup.md" "mockup: 2026-01-02-hero" "$TABLE"
run_rules "$STORIES/3-mockup.md" planner
assert_eq "exit code is 0" "0" "$RC"
assert_contains "says it is a mockup story and that rules follow" "^This story was built from a mockup. Follow the rules below. Facts checked first:" "$OUT"
assert_contains_literal "names the mockup file it found" "- mockup file: $TEST_DIR/.craft/mockups/2026-01-02-hero/mockup.html" "$OUT"
assert_contains "counts binding rows above the plan only, and the TBD row" "binding table: 3 rows, 1 marked TBD" "$OUT"
assert_contains "carries a planner rule" "The mockup is the visual contract" "$OUT"
assert_not_contains "leaves the builder's rules out" "Copy from the file, never from how it looks" "$OUT"

begin_test "the same story gives the builder only the builder's rules"
run_rules "$STORIES/3-mockup.md" builder
assert_eq "exit code is 0" "0" "$RC"
assert_contains "says it is a mockup story and that rules follow" "^This story was built from a mockup. Follow the rules below. Facts checked first:" "$OUT"
assert_not_contains "leaves the binding table count to the planner" "binding table:" "$OUT"
assert_contains "carries a builder rule" "Copy from the file, never from how it looks" "$OUT"
assert_not_contains "leaves the planner's rules out" "The mockup is the visual contract" "$OUT"

begin_test "the mockup field may be a path to the record folder"
write_story "$STORIES/4-path.md" "mockup: .craft/mockups/2026-01-02-hero" "$TABLE"
run_rules "$STORIES/4-path.md" planner
assert_contains_literal "resolves to the same mockup file" "- mockup file: $TEST_DIR/.craft/mockups/2026-01-02-hero/mockup.html" "$OUT"

begin_test "a quoted mockup name resolves too"
write_story "$STORIES/5-quoted.md" 'mockup: "2026-01-02-hero"' "$TABLE"
run_rules "$STORIES/5-quoted.md" planner
assert_contains_literal "resolves to the same mockup file" "- mockup file: $TEST_DIR/.craft/mockups/2026-01-02-hero/mockup.html" "$OUT"

begin_test "a table headed Element counts as the binding table"
write_story "$STORIES/6-element.md" "mockup: 2026-01-02-hero" '## Visual Direction

| Element | Mockup selector | Spec |
|---|---|---|
| Dialog | `.dialog` | 460px |
| Title | `.title` | 20px |'
run_rules "$STORIES/6-element.md" planner
assert_contains "counts both rows" "binding table: 2 rows, 0 marked TBD" "$OUT"

begin_test "a mockup story with no binding table says so"
write_story "$STORIES/7-no-table.md" "mockup: 2026-01-02-hero" "## Visual Direction"
run_rules "$STORIES/7-no-table.md" planner
assert_contains "names the missing table" "binding table: none in this story" "$OUT"

begin_test "a mockup whose file is gone is called out, and the rules are held back"
write_story "$STORIES/8-gone.md" "mockup: 2026-09-09-not-there" "$TABLE"
run_rules "$STORIES/8-gone.md" builder
assert_eq "exit code is 0" "0" "$RC"
assert_contains "names the missing file" "MOCKUP FILE MISSING: $TEST_DIR/.craft/mockups/2026-09-09-not-there/mockup.html" "$OUT"
assert_contains "tells the builder to stop and report it" "Stop and report this under Not done" "$OUT"
assert_not_contains "holds the rules back" "Copy from the file, never from how it looks" "$OUT"
run_rules "$STORIES/8-gone.md" planner
assert_contains "tells the planner to list a blocker" "List this as a Critical Blocker" "$OUT"

begin_test "a story that cannot be read never looks like a plain story"
run_rules "$STORIES/does-not-exist.md" planner
assert_eq "exit code is 1" "1" "$RC"
assert_contains "prints the unavailable line" "^STORY RULES UNAVAILABLE: cannot read the story file" "$OUT"

begin_test "an unknown reader is refused out loud"
run_rules "$STORIES/3-mockup.md" reviewer
assert_eq "exit code is 1" "1" "$RC"
assert_contains "prints the unavailable line" "^STORY RULES UNAVAILABLE: the reader must be planner or builder" "$OUT"

begin_test "the rules file has a part for each reader"
assert_file_contains "planner part" '^## planner$' "$RULES_FILE"
assert_file_contains "builder part" '^## builder$' "$RULES_FILE"

begin_test "the planner, the builder and the build launch still point at the script"
assert_file_contains "planner runs it as the planner" 'hooks/scripts/story-rules.sh <story file> planner' "$PLUGIN_ROOT/agents/plan-chunks-agent.md"
assert_file_contains "builder runs it as the builder" 'hooks/scripts/story-rules.sh <STORY_FILE> builder' "$PLUGIN_ROOT/agents/implementer.md"
assert_file_contains "the build launch hands the builder the plugin root" '\*\*PLUGIN_ROOT:\*\*.*story-rules' "$PLUGIN_ROOT/commands/craft-story-implement.md"

begin_test "the story check leaves a mockup's port-it-unchanged line alone"
assert_file_contains "the exception sits in the planning skill" 'non-empty `mockup:`, the line telling the builder to port the mockup.s look and motion unchanged is not a finding and is never reworded' "$PLUGIN_ROOT/skills/plan-chunks/SKILL.md"

cleanup_test_dir
finish_tests
