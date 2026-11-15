#!/bin/bash
# test-story-rules.sh - A story hands the planner and the builder the rules
# its sources bring; a story with no special source hands them nothing.
#
# story-rules.sh is the one place those two agents learn what a story
# carries (a mockup, decisions in its header, planning sources, a Motion
# line), plus two things about the work itself: an empty project and a user
# interface. This file checks what the script does, never how a rule is
# worded:
#   - a story with no source prints nothing, so the common path stays silent;
#   - each source prints its checked facts and only that reader's rules;
#   - each source prints whether or not another one did;
#   - a source that cannot do its job says so, the others still print, and
#     the exit code is 1, so a failed check never looks like "nothing applies";
#   - the planner, the builder and the build launch still reach the script.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

RULES_SCRIPT="$SCRIPTS_DIR/story-rules.sh"
REFS="$PLUGIN_ROOT/commands/references"

echo "=== test-story-rules.sh ==="
echo ""

TEST_DIR=$(create_test_dir)
STORIES="$TEST_DIR/.craft/cycles/1-demo/stories"
mkdir -p "$STORIES" "$TEST_DIR/.craft/mockups/2026-01-02-hero" \
  "$TEST_DIR/.craft/decisions/approved" "$TEST_DIR/.craft/decisions/archive" "$TEST_DIR/.craft/design"
echo "<html></html>" > "$TEST_DIR/.craft/mockups/2026-01-02-hero/mockup.html"
# A project with code in it: the empty-project rules stay out of every test
# below that is about something else.
echo "{}" > "$TEST_DIR/package.json"

printf '%s\n' "---" "type: decision" "status: accepted" "created: 2026-02-01" "---" "# Open ruling" \
  > "$TEST_DIR/.craft/decisions/approved/2026-02-01-open-ruling.md"
printf '%s\n' "---" "type: decision" "status: accepted" "created: 2026-03-01" "disposition: crafted" "---" "# Built ruling" \
  > "$TEST_DIR/.craft/decisions/approved/2026-03-01-built-ruling.md"
printf '%s\n' "---" "type: decision" "status: deprecated" "---" "# Old ruling" \
  > "$TEST_DIR/.craft/decisions/archive/2026-01-01-old-ruling.md"

# write_story <file> <extra frontmatter lines or empty> <body>
write_story() {
  local file="$1" extra="$2" body="$3"
  {
    echo "---"
    echo "name: demo"
    [ -n "$extra" ] && printf '%s\n' "$extra"
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

# rules_part <rules file> <role> - the text the script should print for that reader
rules_part() {
  awk -v want="## $2" '$0 == want { on = 1; next } /^## / { on = 0 } on' "$REFS/$1" | sed '/./,$!d'
}

# first_rule <rules file> <role> - that part's first bullet, enough to tell the parts apart
first_rule() {
  rules_part "$1" "$2" | grep -m1 '^- '
}

begin_test "a story with no special source prints nothing"
write_story "$STORIES/1-plain.md" "" "## Spark"
run_rules "$STORIES/1-plain.md" planner
assert_eq "exit code is 0" "0" "$RC"
assert_eq "output is empty" "" "$OUT"

begin_test "empty mockup and decisions fields print nothing"
write_story "$STORIES/2-empty.md" "mockup:
decisions: []" "## Spark"
run_rules "$STORIES/2-empty.md" builder
assert_eq "exit code is 0" "0" "$RC"
assert_eq "output is empty for the builder" "" "$OUT"
run_rules "$STORIES/2-empty.md" planner
assert_eq "output is empty for the planner" "" "$OUT"

begin_test "a mockup story gives the planner the mockup file and the planner's rules"
write_story "$STORIES/3-mockup.md" "mockup: 2026-01-02-hero" "## Visual Direction"
run_rules "$STORIES/3-mockup.md" planner
assert_eq "exit code is 0" "0" "$RC"
assert_contains_literal "names the mockup file it found" "- mockup file: $TEST_DIR/.craft/mockups/2026-01-02-hero/mockup.html" "$OUT"
assert_contains "says the story has no binding table" "binding table: none in this story" "$OUT"
assert_contains_literal "carries the planner's part" "$(first_rule mockup-story-rules.md planner)" "$OUT"
assert_not_contains "leaves the builder's part out" "$(first_rule mockup-story-rules.md builder | cut -c1-40)" "$OUT"

begin_test "the same story gives the builder only the builder's rules"
run_rules "$STORIES/3-mockup.md" builder
assert_eq "exit code is 0" "0" "$RC"
assert_contains_literal "carries the builder's part" "$(first_rule mockup-story-rules.md builder)" "$OUT"
assert_not_contains "leaves the planner's part out" "$(first_rule mockup-story-rules.md planner | cut -c1-40)" "$OUT"
assert_not_contains "leaves the binding table to the planner" "binding table" "$OUT"

begin_test "the mockup field may be a path to the record folder, or quoted"
write_story "$STORIES/4-path.md" "mockup: .craft/mockups/2026-01-02-hero" "## Visual Direction"
run_rules "$STORIES/4-path.md" planner
assert_contains_literal "a path resolves to the same mockup file" "- mockup file: $TEST_DIR/.craft/mockups/2026-01-02-hero/mockup.html" "$OUT"
write_story "$STORIES/5-quoted.md" 'mockup: "2026-01-02-hero"' "## Visual Direction"
run_rules "$STORIES/5-quoted.md" planner
assert_contains_literal "a quoted name resolves to the same mockup file" "- mockup file: $TEST_DIR/.craft/mockups/2026-01-02-hero/mockup.html" "$OUT"

begin_test "a mockup whose file is gone is called out, and the mockup rules are held back"
write_story "$STORIES/6-gone.md" "mockup: 2026-09-09-not-there" "## Visual Direction"
run_rules "$STORIES/6-gone.md" builder
assert_eq "exit code is 0" "0" "$RC"
assert_contains "names the missing file" "MOCKUP FILE MISSING: $TEST_DIR/.craft/mockups/2026-09-09-not-there/mockup.html" "$OUT"
assert_contains "tells the builder to stop and report it" "Stop and report this under Not done" "$OUT"
assert_not_contains "holds the builder's rules back" "$(first_rule mockup-story-rules.md builder | cut -c1-40)" "$OUT"
run_rules "$STORIES/6-gone.md" planner
assert_contains "tells the planner to list a blocker" "List this as a Critical Blocker" "$OUT"

begin_test "a mockup story's binding table is counted above the plan only, under either heading"
write_story "$STORIES/7-table.md" "mockup: 2026-01-02-hero" "$TABLE"
run_rules "$STORIES/7-table.md" planner
assert_contains "counts three rows and the TBD row" "binding table: 3 rows, 1 marked TBD" "$OUT"
write_story "$STORIES/8-element.md" "mockup: 2026-01-02-hero" '## Visual Direction

| Element | Mockup selector | Spec |
|---|---|---|
| Dialog | `.dialog` | 460px |
| Title | `.title` | 20px |'
run_rules "$STORIES/8-element.md" planner
assert_contains "a table headed Element counts too" "binding table: 2 rows, 0 marked TBD" "$OUT"
write_story "$STORIES/8b-table-only.md" "" "$TABLE"
run_rules "$STORIES/8b-table-only.md" planner
assert_eq "a binding table alone prints nothing" "" "$OUT"

begin_test "decision records are looked up: open, built, retired and missing"
write_story "$STORIES/9-records.md" "decisions: [2026-02-01-open-ruling, 2026-03-01-built-ruling, 2026-01-01-old-ruling, 2026-04-04-never-written]" "## Spark"
run_rules "$STORIES/9-records.md" planner
assert_eq "exit code is 0" "0" "$RC"
assert_contains_literal "an open record shows its file and date" "- record: $TEST_DIR/.craft/decisions/approved/2026-02-01-open-ruling.md (ruled 2026-02-01)" "$OUT"
assert_contains "a built record is marked frozen" "2026-03-01-built-ruling.md (ruled 2026-03-01; frozen, already built)" "$OUT"
assert_contains "a retired record is called out" "RECORD RETIRED: 2026-01-01-old-ruling" "$OUT"
assert_contains "a missing record is called out" "RECORD NOT FOUND: 2026-04-04-never-written" "$OUT"
assert_contains_literal "carries the decision record rules" "$(first_rule decision-record-story-rules.md planner)" "$OUT"
run_rules "$STORIES/9-records.md" builder
assert_eq "the builder gets nothing for decision records" "" "$OUT"

begin_test "a decisions list written one item per line is read the same way"
write_story "$STORIES/10-records-list.md" "decisions:
  - 2026-02-01-open-ruling
  - 2026-03-01-built-ruling" "## Spark"
run_rules "$STORIES/10-records-list.md" planner
assert_contains "first item found" "2026-02-01-open-ruling.md (ruled 2026-02-01)" "$OUT"
assert_contains "second item found" "2026-03-01-built-ruling.md (ruled 2026-03-01; frozen, already built)" "$OUT"

begin_test "a record named with its folder or its .md ending is still found"
write_story "$STORIES/10a-record-path.md" "decisions: [approved/2026-02-01-open-ruling.md]" "## Spark"
run_rules "$STORIES/10a-record-path.md" planner
assert_contains "the record is found" "2026-02-01-open-ruling.md (ruled 2026-02-01)" "$OUT"
assert_not_contains "and not reported missing" "RECORD NOT FOUND" "$OUT"

begin_test "a decision written out in the header is listed, never looked up as a record"
write_story "$STORIES/10b-written.md" 'decisions:
  - "Both address forms get the field; see Scope"
  - 2026-02-01-open-ruling' "## Spark"
run_rules "$STORIES/10b-written.md" planner
assert_eq "exit code is 0" "0" "$RC"
assert_contains "the sentence is listed whole" "^- Both address forms get the field; see Scope$" "$OUT"
assert_not_contains "no word of it is looked up as a record" "RECORD NOT FOUND" "$OUT"
assert_contains "the record beside it is still looked up" "2026-02-01-open-ruling.md (ruled 2026-02-01)" "$OUT"
assert_contains_literal "carries the rule for written decisions" "$(rules_part decision-record-story-rules.md "planner, decisions written in the header" | grep -m1 '^- ')" "$OUT"

begin_test "a Motion line brings the catalog rules, unless a mockup settles the motion"
write_story "$STORIES/11-motion.md" "" '## Visual Direction

**Motion:** card lifts on hover'
run_rules "$STORIES/11-motion.md" planner
assert_contains "falls back to the plugin's catalog when the project has none" "motion catalog: .*templates/craft/design/animations.md" "$OUT"
assert_contains_literal "carries the planner's motion rules" "$(first_rule motion-story-rules.md planner)" "$OUT"
echo "# catalog" > "$TEST_DIR/.craft/design/animations.md"
run_rules "$STORIES/11-motion.md" planner
assert_contains_literal "prefers the project's own catalog" "- motion catalog: $TEST_DIR/.craft/design/animations.md" "$OUT"
run_rules "$STORIES/11-motion.md" builder
assert_contains_literal "carries the builder's motion rules" "$(first_rule motion-story-rules.md builder)" "$OUT"
assert_not_contains "leaves the catalog to the planner" "motion catalog" "$OUT"
write_story "$STORIES/11b-motion-bullet.md" "" '## Visual Direction

- **Motion:** card lifts on hover'
run_rules "$STORIES/11b-motion-bullet.md" planner
assert_contains "a Motion line written as a bullet is found" "motion catalog:" "$OUT"
write_story "$STORIES/11c-motion-note.md" "" '## Visual Direction

**Motion (all GPU-safe):** card lifts on hover'
run_rules "$STORIES/11c-motion-note.md" planner
assert_contains "a Motion label carrying a note is found" "motion catalog:" "$OUT"
write_story "$STORIES/11d-motion-none.md" "" '## Visual Direction

- **Motion:** none, the page is static'
run_rules "$STORIES/11d-motion-none.md" planner
assert_eq "a Motion line that says none prints nothing" "" "$OUT"
write_story "$STORIES/12-motion-mockup.md" "mockup: 2026-01-02-hero" '## Visual Direction

**Motion:** card lifts on hover'
run_rules "$STORIES/12-motion-mockup.md" planner
assert_not_contains "a mockup story gets no catalog rules" "motion catalog" "$OUT"

begin_test "planning sources bring the citation rules"
write_story "$STORIES/13-concept.md" "source_concept: /plans/concept-08.md" '## Reference Materials

- `/plans/concept-08.md` (`## Locked decisions`)
- `/plans/active.md` (`## Recent state changes`)'
run_rules "$STORIES/13-concept.md" planner
assert_contains "names the planning concept" "written from a planning concept: /plans/concept-08.md" "$OUT"
assert_contains "counts the citations" "Reference Materials: 2 entries" "$OUT"
assert_contains "notes the planning log" "cites a planning log" "$OUT"
assert_contains_literal "carries the citation rules" "$(first_rule citation-story-rules.md planner)" "$OUT"
write_story "$STORIES/14-concept-bare.md" "source_concept: /plans/concept-08.md" "## Spark"
run_rules "$STORIES/14-concept-bare.md" planner
assert_contains "a concept story that cites nothing is called out" "NO REFERENCE MATERIALS" "$OUT"
write_story "$STORIES/15-research.md" "" '## Reference Materials

- `.craft/research/sync/_plan.md` -> "Convergence Points"'
run_rules "$STORIES/15-research.md" planner
assert_contains "a research citation alone is enough" "cites research" "$OUT"
write_story "$STORIES/15b-refs-below-plan.md" "" '## Chunks

### Chunk 1: Thing

## Reference Materials

- `.craft/research/sync/_plan.md` -> "Convergence Points"'
run_rules "$STORIES/15b-refs-below-plan.md" planner
assert_contains "citations that sit below the plan are still seen" "cites research" "$OUT"
write_story "$STORIES/16-plain-refs.md" "" '## Reference Materials

- `src/app.ts:10-20`'
run_rules "$STORIES/16-plain-refs.md" planner
assert_eq "ordinary code citations print nothing" "" "$OUT"

begin_test "an empty project tells the planner to set it up first, and only then"
EMPTY_DIR=$(mktemp -d)
mkdir -p "$EMPTY_DIR/.craft/backlog" "$EMPTY_DIR/.craft/mockups/2026-01-02-hero"
echo "<html></html>" > "$EMPTY_DIR/.craft/mockups/2026-01-02-hero/mockup.html"
echo "# readme" > "$EMPTY_DIR/README.md"
write_story "$EMPTY_DIR/.craft/backlog/a.md" "" "## Spark"
run_rules "$EMPTY_DIR/.craft/backlog/a.md" planner
assert_eq "exit code is 0" "0" "$RC"
assert_contains "says the project has no code" "^This project has no code yet" "$OUT"
assert_contains_literal "carries the empty-project rules" "$(first_rule empty-project-story-rules.md planner)" "$OUT"
run_rules "$EMPTY_DIR/.craft/backlog/a.md" builder
assert_eq "the builder gets nothing for an empty project" "" "$OUT"
write_story "$EMPTY_DIR/.craft/backlog/b.md" "mockup: 2026-01-02-hero" "## Visual Direction"
run_rules "$EMPTY_DIR/.craft/backlog/b.md" planner
assert_not_contains "a mockup story leaves the empty project to the mockup rules" "This project has no code yet" "$OUT"
mkdir "$EMPTY_DIR/src"
run_rules "$EMPTY_DIR/.craft/backlog/a.md" planner
assert_eq "a folder the check does not know means the project is not empty" "" "$OUT"
rm -rf "$EMPTY_DIR"

begin_test "a project inside a larger repository is never called empty"
REPO_DIR=$(mktemp -d)
git -C "$REPO_DIR" init -q
mkdir -p "$REPO_DIR/apps/web/.craft/backlog"
write_story "$REPO_DIR/apps/web/.craft/backlog/a.md" "" "## Spark"
run_rules "$REPO_DIR/apps/web/.craft/backlog/a.md" planner
assert_eq "the planner gets nothing" "" "$OUT"
rm -rf "$REPO_DIR"

begin_test "a user-interface story gives the builder the interface rules"
write_story "$STORIES/18-ui.md" "type: ui" "## Spark"
run_rules "$STORIES/18-ui.md" builder
assert_eq "exit code is 0" "0" "$RC"
assert_contains "says why it counts as a user interface" "^- the story.s type is ui$" "$OUT"
assert_contains_literal "carries the interface rules" "$(first_rule ui-story-rules.md builder)" "$OUT"
run_rules "$STORIES/18-ui.md" planner
assert_eq "the planner gets nothing for the story's type" "" "$OUT"
run_rules "$STORIES/3-mockup.md" builder
assert_contains "a mockup counts as a user interface" "^- the story names a mockup$" "$OUT"
assert_contains_literal "the mockup rules still print beside them" "$(first_rule mockup-story-rules.md builder)" "$OUT"
run_rules "$STORIES/8b-table-only.md" builder
assert_contains "a binding table counts as a user interface" "^- the story has a Visual Direction binding table$" "$OUT"
write_story "$STORIES/19-backend.md" "type: technical" "## Spark"
run_rules "$STORIES/19-backend.md" builder
assert_eq "a story with none of the three prints nothing" "" "$OUT"

begin_test "the orchestrator hears nothing about a story with its table, or with no settled look"
run_rules "$STORIES/1-plain.md" orchestrator
assert_eq "a plain story: exit code is 0" "0" "$RC"
assert_eq "a plain story prints nothing" "" "$OUT"
write_story "$STORIES/20-mockup-table.md" "mockup: 2026-01-02-hero" "$TABLE"
run_rules "$STORIES/20-mockup-table.md" orchestrator
assert_eq "a mockup story that has its table prints nothing" "" "$OUT"
write_story "$STORIES/20-busy.md" "decisions: [2026-02-01-open-ruling]
source_concept: thing" "## Visual Direction

**Motion:** fade in

A confirmation dialog before saving."
run_rules "$STORIES/20-busy.md" orchestrator
assert_eq "the planner's and builder's blocks never print for it" "" "$OUT"
assert_eq "exit code is 0" "0" "$RC"

begin_test "a mockup story with no table tells the orchestrator how to build it"
write_story "$STORIES/21-mockup-bare.md" "mockup: 2026-01-02-hero" "## Visual Direction

**Vibe:** calm"
run_rules "$STORIES/21-mockup-bare.md" orchestrator
assert_eq "exit code is 0" "0" "$RC"
assert_contains "says the table is missing" "^This story was built from a mockup and has no binding table" "$OUT"
assert_contains "names the mockup file" "^- mockup file: .*/2026-01-02-hero/mockup.html$" "$OUT"
assert_contains "names the step that builds the table" "^- how the table is built: .*/story-from-mockup.md" "$OUT"
assert_contains_literal "carries the orchestrator's mockup rules" "$(first_rule settled-look-story-rules.md 'orchestrator, mockup')" "$OUT"
run_rules "$STORIES/21-mockup-bare.md" planner
assert_not_contains "the planner never gets the orchestrator's rules" "how the table is built" "$OUT"
write_story "$STORIES/22-mockup-gone.md" "mockup: 2026-09-09-gone" "## Visual Direction"
run_rules "$STORIES/22-mockup-gone.md" orchestrator
assert_contains "a mockup that is gone is called out" "^- MOCKUP FILE MISSING: " "$OUT"
assert_not_contains "and no build step is offered" "how the table is built" "$OUT"

begin_test "an annotate story with no table tells the orchestrator how to build it"
mkdir -p "$TEST_DIR/.craft/annotations/2026-04-04-hero-polish"
echo "# record" > "$TEST_DIR/.craft/annotations/2026-04-04-hero-polish/record.md"
echo "/* annotate-key 1 */" > "$TEST_DIR/.craft/annotations/2026-04-04-hero-polish/session.css"
write_story "$STORIES/23-annotate-bare.md" "annotate: 2026-04-04-hero-polish" "## Spark"
run_rules "$STORIES/23-annotate-bare.md" orchestrator
assert_eq "exit code is 0" "0" "$RC"
assert_contains "says the table is missing" "^This story was built from an annotate run and has no binding table" "$OUT"
assert_contains "names the sheet the user saw" "^- the changes the user saw on the page: .*/2026-04-04-hero-polish/session.css$" "$OUT"
assert_contains "names the step that builds the table" "^- how the table is built: .*/story-from-annotate.md" "$OUT"
assert_contains_literal "carries the orchestrator's annotate rules" "$(first_rule settled-look-story-rules.md 'orchestrator, annotate')" "$OUT"
write_story "$STORIES/24-annotate-table.md" "annotate: 2026-04-04-hero-polish" "$TABLE"
run_rules "$STORIES/24-annotate-table.md" orchestrator
assert_eq "an annotate story that has its table prints nothing" "" "$OUT"
write_story "$STORIES/25-annotate-gone.md" "annotate: 2026-09-09-gone" "## Spark"
run_rules "$STORIES/25-annotate-gone.md" orchestrator
assert_contains "a run whose files are gone is called out" "^- ANNOTATE RECORD MISSING: " "$OUT"

begin_test "a story that names a dial record on disk, with no table, is not offered a new look"
mkdir -p "$TEST_DIR/.craft/dials"
printf '%s\n' "---" "source: dial" "chose: f" "outcome: story" "---" "let's go B" > "$TEST_DIR/.craft/dials/2026-05-05-warning-on-the-field.md"
write_story "$STORIES/26-dial-bare.md" "" "## Spark

The look was settled in a dial session, record .craft/dials/2026-05-05-warning-on-the-field.md, position F."
run_rules "$STORIES/26-dial-bare.md" orchestrator
assert_eq "exit code is 0" "0" "$RC"
assert_contains "names the record and the position chosen" "^- dial record: .*/2026-05-05-warning-on-the-field.md .position chosen: f.$" "$OUT"
assert_contains_literal "carries the orchestrator's dial rules" "$(first_rule settled-look-story-rules.md 'orchestrator, dial')" "$OUT"
write_story "$STORIES/27-dial-table.md" "dial: .craft/dials/2026-05-05-warning-on-the-field.md" "$TABLE"
run_rules "$STORIES/27-dial-table.md" orchestrator
assert_eq "a dial story that has a table prints nothing" "" "$OUT"
write_story "$STORIES/28-dial-word.md" "" "## Spark

We talked about a dial and a dialog, and no record is named."
run_rules "$STORIES/28-dial-word.md" orchestrator
assert_eq "the word alone, with no record named, prints nothing" "" "$OUT"

begin_test "every source a story carries prints, each in its own block"
write_story "$STORIES/17-both.md" "mockup: 2026-01-02-hero
decisions: [2026-02-01-open-ruling]" "$TABLE"
run_rules "$STORIES/17-both.md" planner
assert_eq "exit code is 0" "0" "$RC"
assert_contains_literal "the mockup block printed" "$(first_rule mockup-story-rules.md planner)" "$OUT"
assert_contains_literal "the decision record block printed" "$(first_rule decision-record-story-rules.md planner)" "$OUT"

begin_test "one broken source says so, and the others still print"
BROKEN_REFS="$TEST_DIR/refs"
mkdir -p "$BROKEN_REFS"
cp "$REFS"/*-story-rules.md "$BROKEN_REFS/"
rm "$BROKEN_REFS/decision-record-story-rules.md"
set +e
OUT=$(STORY_RULES_DIR="$BROKEN_REFS" bash "$RULES_SCRIPT" "$STORIES/17-both.md" planner 2>&1)
RC=$?
set -e
assert_eq "exit code is 1" "1" "$RC"
assert_contains "the broken source prints the unavailable line" "^STORY RULES UNAVAILABLE: this story carries decision records" "$OUT"
assert_contains_literal "the mockup block still printed" "$(first_rule mockup-story-rules.md planner)" "$OUT"

begin_test "a story that cannot be read never looks like a plain story"
run_rules "$STORIES/does-not-exist.md" planner
assert_eq "exit code is 1" "1" "$RC"
assert_contains "prints the unavailable line" "^STORY RULES UNAVAILABLE: cannot read the story file" "$OUT"

begin_test "an unknown reader is refused out loud"
run_rules "$STORIES/3-mockup.md" reviewer
assert_eq "exit code is 1" "1" "$RC"
assert_contains "prints the unavailable line" "^STORY RULES UNAVAILABLE: the reader must be planner, builder or orchestrator" "$OUT"

begin_test "every rules file the script reads has a part for a reader"
for f in mockup-story-rules.md decision-record-story-rules.md citation-story-rules.md motion-story-rules.md empty-project-story-rules.md; do
  assert_file_contains "$f has a planner part" '^## planner$' "$REFS/$f"
done
assert_file_contains "the mockup rules have a builder part" '^## builder$' "$REFS/mockup-story-rules.md"
assert_file_contains "the motion rules have a builder part" '^## builder$' "$REFS/motion-story-rules.md"
assert_file_contains "the interface rules have a builder part" '^## builder$' "$REFS/ui-story-rules.md"
for part in mockup annotate dial; do
  assert_file_contains "the settled-look rules have an orchestrator part for $part" "^## orchestrator, $part\$" "$REFS/settled-look-story-rules.md"
done

begin_test "the planner, the builder, the orchestrator and the build launch still reach the script"
assert_file_contains "the planner names the script" 'hooks/scripts/story-rules.sh' "$PLUGIN_ROOT/agents/plan-chunks-agent.md"
assert_file_contains "the builder names the script" 'hooks/scripts/story-rules.sh' "$PLUGIN_ROOT/agents/implementer.md"
assert_file_contains "the plan-chunks skill runs the script as the orchestrator" 'hooks/scripts/story-rules.sh.* orchestrator' "$PLUGIN_ROOT/skills/plan-chunks/SKILL.md"
assert_file_contains "the build launch still hands the builder the plugin root as a fallback" 'PLUGIN_ROOT:.*the implementer cannot resolve' "$PLUGIN_ROOT/commands/craft-story-implement.md"

cleanup_test_dir
finish_tests
