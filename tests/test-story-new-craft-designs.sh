#!/bin/bash
# test-story-new-craft-designs.sh - The "craft designs" source: one search, pick
# and hand-off reference shared by story-new and cycle-design, and the two
# graduation references' fallback searches that must list exactly what it lists.
# The search is executed against fixtures, set up and before init; the prompt
# text around it is pinned as facts about text.
# Usage: bash tests/test-story-new-craft-designs.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

REPO="$PLUGIN_ROOT"
REF="$REPO/commands/references/story-from-craft-designs.md"
MOCKUP_REF="$REPO/commands/references/story-from-mockup.md"
ANNOTATE_REF="$REPO/commands/references/story-from-annotate.md"

PINNED_CALL='bash -c '"'"'source "$1" >/dev/null 2>&1; craft_before_init_root'"'"' _ "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/find-workshop.sh"'

BI_TMP=()
bi_cleanup() {
  local d
  for d in "${BI_TMP[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done
  return 0
}
trap bi_cleanup EXIT

# bi_dir - a fresh physical temp folder, so expected paths match git's toplevel
bi_dir() {
  BI_DIR=$(cd "$(mktemp -d)" && pwd -P)
  BI_TMP+=("$BI_DIR")
}

# bi_env <dir> <command...> - run from <dir> with no project variables
bi_env() {
  local dir="$1"; shift
  (cd "$dir" && env -u CRAFT_PROJECT_ROOT -u PROJECT_ROOT -u CRAFT_PROJECT_NAME -u CRAFT_MULTI_PROJECT CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$@")
}

# fence_under <heading> <file> - body of the first bash fence under the heading
fence_under() {
  awk -v h="$1" '
    $0 == h {under=1; next}
    under && /^## / {exit}
    under && $0 == "```bash" {inside=1; next}
    inside && $0 == "```" {exit}
    inside {print}
  ' "$2"
}

# mk_record <root> <kind> <name> <key: value lines...> - write a record.md
mk_record() {
  local root="$1" kind="$2" name="$3"; shift 3
  mkdir -p "$root/.craft/$kind/$name"
  { echo "---"; printf '%s\n' "$@"; echo "---"; echo ""; echo "## Brief"; } > "$root/.craft/$kind/$name/record.md"
}

# mk_setup_fixture <root> - one of every status, a set-up project
mk_setup_fixture() {
  local root="$1"
  mkdir -p "$root/.craft"
  : > "$root/.craft/.global-state"
  mk_record "$root" mockups a-parked "status: parked"
  mk_record "$root" mockups b-converged "status: converged"
  mk_record "$root" mockups c-graduated "status: graduated-story"
  mk_record "$root" mockups d-converging "status: converging"
  mk_record "$root" mockups e-abandoned "status: abandoned"
  mk_record "$root" annotations x-open "status: open" "outcome: nothing"
  mk_record "$root" annotations y-cut-short "status: open" "outcome: error"
  mk_record "$root" annotations z-graduated "status: graduated" "outcome: nothing"
}

SEARCH=$(fence_under "## Search" "$REF" 2>/dev/null || true)
MOCKUP_FALLBACK=$(fence_under "## Phase 1: Select the record" "$MOCKUP_REF")
ANNOTATE_FALLBACK=$(fence_under "## Phase 1: Select the record" "$ANNOTATE_REF")

run_fence() { # <dir> <fence text> - run from dir, project variables unset
  bi_env "$1" bash -c "$2"
}

# --- Executed: the bug's own repro comes first ---

begin_test "before init, the search finds designs at the git top from a subfolder"
bi_dir; top="$BI_DIR"
git -C "$top" init -q
mk_record "$top" mockups story-card "status: converged"
mkdir -p "$top/sub/deeper"
out=$(run_fence "$top/sub/deeper" "$SEARCH" || true)
assert_eq "first line is ROOT <git top>" "ROOT $top" "$(printf '%s\n' "$out" | sed -n 1p)"
assert_contains_literal "the converged mockup follows" "MOCKUP $top/.craft/mockups/story-card/record.md" "$out"

begin_test "a set-up project lists only waiting designs"
bi_dir; root="$BI_DIR"
mk_setup_fixture "$root"
out=$(run_fence "$root" "$SEARCH")
assert_eq "exactly the parked and converged mockups, the open run" \
  "ROOT $root
MOCKUP $root/.craft/mockups/a-parked/record.md
MOCKUP $root/.craft/mockups/b-converged/record.md
ANNOTATE $root/.craft/annotations/x-open/record.md" "$out"

begin_test "a cut-short run alone yields no designs"
bi_dir; root="$BI_DIR"
mkdir -p "$root/.craft"; : > "$root/.craft/.global-state"
mk_record "$root" annotations y-cut-short "status: open" "outcome: error"
rc=0
out=$(run_fence "$root" "$SEARCH") || rc=$?
assert_eq "only the ROOT line" "ROOT $root" "$out"
assert_eq "exits 0" "0" "$rc"

begin_test "a project folder with spaces in its path still lists designs"
bi_dir; root="$BI_DIR/my project"
mkdir -p "$root"; git -C "$root" init -q
mk_record "$root" mockups spaced "status: parked"
out=$(run_fence "$root" "$SEARCH")
assert_contains_literal "spaced path survives" "MOCKUP $root/.craft/mockups/spaced/record.md" "$out"

begin_test "the graduation fallbacks list exactly what the reference lists"
for mode in setup before-init; do
  bi_dir; root="$BI_DIR"
  if [ "$mode" = setup ]; then
    mk_setup_fixture "$root"
  else
    git -C "$root" init -q
    mk_record "$root" mockups a-parked "status: parked"
    mk_record "$root" mockups b-converged "status: converged"
    mk_record "$root" mockups c-graduated "status: graduated-story"
    mk_record "$root" annotations x-open "status: open" "outcome: nothing"
    mk_record "$root" annotations y-cut-short "status: open" "outcome: error"
    mkdir -p "$root/sub"
  fi
  start="$root"; [ "$mode" = before-init ] && start="$root/sub"
  ref_out=$(run_fence "$start" "$SEARCH")
  want_m=$(printf '%s\n' "$ref_out" | sed -n 's/^MOCKUP //p' | sort)
  want_a=$(printf '%s\n' "$ref_out" | sed -n 's/^ANNOTATE //p' | sort)
  got_m=$(run_fence "$start" "$MOCKUP_FALLBACK" | sort)
  got_a=$(run_fence "$start" "$ANNOTATE_FALLBACK" | sort)
  assert_eq "$mode: mockup fallback equals the reference" "$want_m" "$got_m"
  assert_eq "$mode: annotate fallback equals the reference" "$want_a" "$got_a"
  assert_eq "$mode: fixture lists a mockup" "1" "$([ -n "$want_m" ] && echo 1 || echo 0)"
  assert_eq "$mode: fixture lists an annotate run" "1" "$([ -n "$want_a" ] && echo 1 || echo 0)"
done

# --- Text: the reference ---

REF_TEXT=$(cat "$REF" 2>/dev/null || true)
MOCKUP_TEXT=$(cat "$MOCKUP_REF")
ANNOTATE_TEXT=$(cat "$ANNOTATE_REF")

begin_test "the reference has Search, Pick, Hand-off in order and says who reads it"
order=$(grep -n '^## ' "$REF" | sed 's/^[0-9]*://' | tr '\n' '|')
assert_eq "section order" "## Search|## Pick|## Hand-off|" "$order"
title=$(sed -n 1p "$REF")
assert_contains_literal "title names story-new Step 2.5" "craft:story-new Step 2.5" "$title"
assert_contains_literal "title names cycle-design Step 2.7" "craft:cycle-design default mode Step 2.7" "$title"

begin_test "every search runs the pinned before-init call and none sets CRAFT_PROJECT_ROOT"
assert_contains_literal "reference has the pinned call" "$PINNED_CALL" "$REF_TEXT"
assert_contains_literal "mockup fallback has the pinned call" "$PINNED_CALL" "$MOCKUP_TEXT"
assert_contains_literal "annotate fallback has the pinned call" "$PINNED_CALL" "$ANNOTATE_TEXT"
for t in "$REF_TEXT" "$MOCKUP_TEXT" "$ANNOTATE_TEXT"; do
  assert_not_contains "no export of CRAFT_PROJECT_ROOT" "export CRAFT_PROJECT_ROOT" "$t"
  assert_not_contains "no assignment of CRAFT_PROJECT_ROOT" "CRAFT_PROJECT_ROOT=" "$t"
done

begin_test "the reference hands off inline"
assert_contains_literal "mockup read line" 'Read "${CLAUDE_PLUGIN_ROOT}/commands/references/story-from-mockup.md"' "$REF_TEXT"
assert_contains_literal "annotate read line" 'Read "${CLAUDE_PLUGIN_ROOT}/commands/references/story-from-annotate.md"' "$REF_TEXT"
assert_contains_literal "never via Skill" "never via the Skill tool" "$REF_TEXT"
assert_contains_literal "absolute write target" "instead of its relative target" "$REF_TEXT"
assert_contains_literal "one-design line" "Building from [slug] - that one?" "$REF_TEXT"
assert_contains_literal "step 10 read for non-story-new callers" "craft-story-new.md" "$REF_TEXT"

begin_test "the reference names no question widget"
all=$(grep -o 'AskUserQuestion' "$REF" | wc -l | tr -d ' ')
safe=$(grep -o 'no AskUserQuestion' "$REF" | wc -l | tr -d ' ')
assert_eq "every mention is 'no AskUserQuestion'" "$all" "$safe"
assert_eq "at least one mention" "1" "$([ "$all" -ge 1 ] && echo 1 || echo 0)"

begin_test "the reference re-implements no pre-fill"
assert_not_contains "no binding table header" "| Part | Role/State |" "$REF_TEXT"
assert_eq "no line starting mockup: " "0" "$(grep -c '^mockup: ' "$REF" || true)"
assert_eq "no line starting annotate: " "0" "$(grep -c '^annotate: ' "$REF" || true)"
assert_not_contains "no annotate-record call" "annotate-record.sh" "$REF_TEXT"
assert_not_contains "no store scan rule" "never scan the store for candidates" "$REF_TEXT"

begin_test "hygiene: no em dash and no dated slug in the new and edited references"
for f in "$REF" "$MOCKUP_REF" "$ANNOTATE_REF"; do
  assert_eq "$(basename "$f") has no em dash" "0" "$(grep -c '—' "$f" || true)"
done
assert_eq "reference has no dated slug" "0" "$(grep -cE '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[a-z]' "$REF" || true)"
assert_eq "annotate reference has no dated slug" "0" "$(grep -cE '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[a-z]' "$ANNOTATE_REF" || true)"

begin_test "DESIGN.md lists the reference"
assert_contains_literal "tree line" "story-from-craft-designs.md" "$(cat "$REPO/DESIGN.md")"

# --- Text: story-new Step 2.5 ---

STORY_NEW="$REPO/commands/craft-story-new.md"
S25=$(awk '/^### Step 2.5: Story Source Detection/ {on=1; next} /^### Step 3: Choose Your Path/ {on=0} on {print}' "$STORY_NEW")

begin_test "Step 2.5 offers craft designs only when the search found any"
assert_contains_literal "label" 'label: "craft designs"' "$S25"
assert_contains_literal "conditional marker" '(only if the craft designs search found any)' "$S25"
assert_contains_literal "description carries the counts phrase" '[counts phrase from the search, e.g. 2 mockups, 1 annotate run] waiting to be built' "$S25"
assert_eq "no From mockup left in story-new" "0" "$(grep -c 'From mockup' "$STORY_NEW" || true)"
assert_eq "no From annotate left in story-new" "0" "$(grep -c 'From annotate' "$STORY_NEW" || true)"

begin_test "the Step 2.5 option set has at most three labels"
assert_eq "label count" "3" "$(printf '%s\n' "$S25" | grep -c '^  - label: ')"

begin_test "the craft designs branch continues in the reference inline"
BR=$(printf '%s\n' "$S25" | awk '/^\*\*If "craft designs":\*\*/ {on=1} /^\*\*If "Freeform":\*\*/ {on=0} on {print}')
assert_contains_literal "reference path" 'commands/references/story-from-craft-designs.md' "$BR"
assert_contains_literal "Read tool, never Skill" 'never via the Skill tool' "$BR"
assert_contains_literal "parent flow done" 'the parent flow is DONE - do not continue to Step 3' "$BR"
assert_contains_literal "a no continues as Freeform" 'continues as Freeform' "$BR"
FREE_LINE=$(printf '%s\n' "$S25" | grep -n '^\*\*If "Freeform":\*\*' | cut -d: -f1)
CD_LINE=$(printf '%s\n' "$S25" | grep -n '^\*\*If "craft designs":\*\*' | cut -d: -f1)
assert_eq "branch sits immediately before Freeform" "1" "$([ -n "$CD_LINE" ] && [ -n "$FREE_LINE" ] && [ "$CD_LINE" -lt "$FREE_LINE" ] && echo 1 || echo 0)"

begin_test "Step 2.5 skips the question when the conversation answers it"
OPEN=$(printf '%s\n' "$S25" | awk '/Detection logic:/ {exit} {print}')
assert_contains_literal "stranger litmus" 'Could a stranger reading the conversation so far tell where this story comes from without asking?' "$OPEN"
assert_contains_literal "freeform with no question" 'no search, no question' "$OPEN"
assert_contains_literal "one-line idea does not answer" 'A one-line idea given only at Step 1 does not answer the source' "$OPEN"
assert_contains_literal "default toward asking" 'default toward asking' "$OPEN"
assert_contains_literal "named design goes to the Pick" 'Pick' "$OPEN"

begin_test "the question counts are the craft designs counts"
assert_contains_literal "counts tie to the search lines" 'MOCKUP and ANNOTATE lines the craft designs search printed, never directory counts' "$S25"

begin_test "From planning is unchanged"
assert_contains_literal "planning search block" 'find "$CRAFT_PROJECT_ROOT/.craft/planning" -maxdepth 3 -type f -name "*.md" 2>/dev/null \
  | xargs grep -l "^concept:\|^initiative:" 2>/dev/null \
  | head -20' "$S25"
assert_contains_literal "planning option description" 'description: "Build this story from existing planning docs. I'"'"'ll walk the concept(s) and produce a thorough story with Reference Materials."' "$S25"
assert_contains_literal "empty-skip sentence" 'If all come back empty' "$S25"
assert_eq "no em dash in Step 2.5" "0" "$(printf '%s\n' "$S25" | grep -c '—' || true)"

# --- Text: cycle-design default mode call-site ---

DM="$REPO/commands/references/cycle-design/default-mode.md"
DM_S2=$(awk '/^### Step 2: Story Brainstorm/ {on=1; next} /^### Step 2.7:/ {on=0} on {print}' "$DM")
DM_S27=$(awk '/^### Step 2.7:/ {on=1; next} /^### Step 3-Fast:/ {on=0} on {print}' "$DM")
DM_FAST=$(awk '/^### Step 3-Fast:/ {on=1; next} /^### Step 3: Capture/ {on=0} on {print}' "$DM")
DM_S3=$(awk '/^### Step 3: Capture/ {on=1; next} /^### Step 4:/ {on=0} on {print}' "$DM")

begin_test "cycle-design's brainstorm presentation reads the craft designs reference inline"
assert_contains_literal "reference path" 'commands/references/story-from-craft-designs.md' "$DM_S2"
assert_contains_literal "Read tool, never Skill" 'never via the Skill tool' "$DM_S2"
assert_contains_literal "runs the Search" '## Search' "$DM_S2"

begin_test "the presented list template carries the source tag and the Also waiting line"
assert_contains_literal "source tag shape" '*From the <slug> <mockup|annotate run>* (<status word>, waiting)' "$DM_S2"
assert_contains_literal "trailing line" 'Also waiting, not in this goal: <slug> (<kind>, <date>)' "$DM_S2"
assert_eq "tag appears in both templates" "2" "$(printf '%s\n' "$DM_S2" | grep -c '^> .*waiting)' || true)"

begin_test "no new question in Step 2"
assert_eq "exactly one question line" "1" "$(printf '%s\n' "$DM_S2" | grep -c '^question: ' || true)"
assert_contains_literal "the existing question" 'question: "Does this capture the scope?"' "$DM_S2"

begin_test "the Step 2.7 heading and its mentions say Story-Source Routing"
assert_eq "heading" "1" "$(grep -c '^### Step 2.7: Story-Source Routing (Per Story, Before Step 3 or Step 3-Fast)$' "$DM" || true)"
assert_eq "no Planning-Source Routing left" "0" "$(grep -c 'Planning-Source Routing' "$DM" || true)"
assert_eq "two mentions" "2" "$(grep -c 'Step 2.7 (Story-Source Routing)' "$DM" || true)"

begin_test "the design moment runs before the freeform-cycle skip"
DESIGN_LINE=$(grep -n '^\*\*Design-extraction moment\.\*\*' "$DM" | head -1 | cut -d: -f1)
YAML_LINE=$(grep -n 'ACTIVE_CYCLE=\$(grep' "$DM" | head -1 | cut -d: -f1)
FREEFORM_LINE=$(grep -n 'this cycle is freeform' "$DM" | head -1 | cut -d: -f1)
assert_eq "design moment exists" "1" "$([ -n "$DESIGN_LINE" ] && echo 1 || echo 0)"
assert_eq "before the cycle.yaml read" "1" "$([ -n "$DESIGN_LINE" ] && [ -n "$YAML_LINE" ] && [ "$DESIGN_LINE" -lt "$YAML_LINE" ] && echo 1 || echo 0)"
assert_eq "before the freeform skip" "1" "$([ -n "$DESIGN_LINE" ] && [ -n "$FREEFORM_LINE" ] && [ "$DESIGN_LINE" -lt "$FREEFORM_LINE" ] && echo 1 || echo 0)"

begin_test "a design-tied story is moved into the cycle"
assert_contains_literal "move-story call" 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/move-story.sh" "<story path the graduation reference reported>" "<this cycle'"'"'s directory name>"' "$DM_S27"
assert_contains_literal "runs Pick then Hand-off" '## Pick' "$DM_S27"
assert_contains_literal "Hand-off named" '## Hand-off' "$DM_S27"
assert_contains_literal "removed candidate leaves record untouched" 'record untouched' "$DM_S27"

begin_test "planning routing is unchanged"
assert_contains_literal "invocation marker" '`INVOCATION: cycle-design - planning source already confirmed in cycle.yaml`' "$DM_S27"
assert_contains_literal "litmus sentence" 'Could a stranger reading the conversation that produced this story tell which moment it was?' "$DM_S27"

begin_test "Step 3-Fast and Step 3 route design-tied stories"
assert_contains_literal "Step 3-Fast names the design moment" 'design-extraction moment' "$DM_FAST"
assert_contains_literal "Step 3 names the design moment" 'design-extraction moment' "$DM_S3"

begin_test "hygiene: cycle-design default mode gains no em dash in the new text"
assert_eq "no em dash in the design moment" "0" "$(printf '%s\n' "$DM_S27" | awk '/^\*\*Design-extraction moment\./ {on=1} /^\*\*Before doing per-story/ {on=0} on {print}' | grep -c '—' || true)"

begin_test "mockup's story ending names the craft designs source"
MOCKUP_INLINE="$REPO/commands/references/mockup-inline.md"
assert_eq "craft designs source named twice" "2" "$(grep -c "story-new's craft designs source" "$MOCKUP_INLINE" || true)"
assert_eq "no From mockup left" "0" "$(grep -c "From mockup" "$MOCKUP_INLINE" || true)"
assert_contains_literal "option description" 'description: "story-new'"'"'s craft designs source pre-fills the story from this record"' "$(cat "$MOCKUP_INLINE")"
assert_contains_literal "line tail unchanged" "(commands/references/story-from-mockup.md) does the pre-fill. The mockup's CSS is NORMATIVE there" "$(cat "$MOCKUP_INLINE")"

begin_test "the decision tree drops From mockup and shows craft designs"
TREE="$REPO/docs/decision-tree.md"
assert_eq "no From mockup" "0" "$(grep -c "From mockup" "$TREE" || true)"
assert_eq "no FROM_MOCKUP node" "0" "$(grep -c "FROM_MOCKUP" "$TREE" || true)"
assert_contains_literal "names the shared reference" 'commands/references/story-from-craft-designs.md' "$(cat "$TREE")"
assert_contains_literal "craft designs edge" 'SOURCE -->|"craft designs"|' "$(cat "$TREE")"
assert_contains_literal "names the mockup graduation reference" 'story-from-mockup.md' "$(sed -n '/^## Story Creation Flow/,/^## /p' "$TREE")"
assert_contains_literal "names the annotate graduation reference" 'story-from-annotate.md' "$(sed -n '/^## Story Creation Flow/,/^## /p' "$TREE")"
assert_contains_literal "skip rule precedes SCAN" 'CLARIFY -->|Yes| SKIP{' "$(cat "$TREE")"
assert_contains_literal "freeform skips to CHOOSE_PATH" 'SKIP -->|"Freeform"| CHOOSE_PATH' "$(cat "$TREE")"
assert_contains_literal "SCAN label names the filters" 'open annotate runs not cut short' "$(cat "$TREE")"
assert_contains_literal "cycle-design node renamed" 'Step 2.7 Story-Source Routing' "$(cat "$TREE")"
assert_contains_literal "design-extraction edge" 'MOMENT -->|"Design-extraction moment"|' "$(cat "$TREE")"
assert_contains_literal "default-mode design sentence" '*design-extraction* moment' "$(grep '^\*\*Story-source routing' "$TREE")"
assert_contains_literal "mockup node" "story-new 'craft designs'" "$(cat "$TREE")"
assert_eq "no Planning-Source left" "0" "$(grep -ci 'Planning-Source' "$TREE" || true)"

begin_test "annotate never promises a cut-short run to a later story"
assert_eq "no later-story promise" "0" "$(grep -c "for a later story" "$REPO/commands/references/annotate-inline.md" || true)"

begin_test "the changelog history line is untouched"
assert_eq "history line kept" "1" "$(grep -cF -- '- Changed story creation: the source question now also offers "From mockup" when converged mockup records exist' "$REPO/CHANGELOG.md" || true)"

# Full Design, Step 9: five sections, each its own Edit to the story file, one
# question after the fifth. A tweak once folded the five steps into a single
# one-pass draft with one-line slots and every test stayed green; the first
# live story through it came out thin. These pins make that fold a red test.
begin_test "full design is five passes and one question"
STORY_NEW="$REPO/commands/craft-story-new.md"
STEP9="$(sed -n '/^### Step 9: Full Design, Five Passes, One Question/,/^### Step 10/p' "$STORY_NEW")"
assert_contains_literal "step 9 heading" "### Step 9: Full Design, Five Passes, One Question" "$STEP9"
for P in "Pass 1, Acceptance" "Pass 2, Scope" "Pass 3, Preserve" "Pass 4, Hardest constraint" "Pass 5, Dependencies"; do
  assert_eq "$P present once" "1" "$(printf '%s\n' "$STEP9" | grep -cF -- "**$P.**" || true)"
done
for H in "## Acceptance" "## Scope" "## Preserve" "## Hardest Constraint" "## Dependencies"; do
  assert_eq "$H section template present" "1" "$(printf '%s\n' "$STEP9" | grep -cF -- "> $H" || true)"
done
assert_contains_literal "one Edit per section" "A pass is one Edit to the story file" "$STEP9"
assert_contains_literal "never two sections in one Edit" "Never write two sections in one Edit" "$STEP9"
assert_contains_literal "section text exists first in the Edit" "exists first in the Edit, never in chat ahead of it" "$STEP9"
assert_eq "one closing question" "1" "$(printf '%s\n' "$STEP9" | grep -cF -- "> Anything to change?" || true)"
assert_eq "no one-pass draft" "0" "$(printf '%s\n' "$STEP9" | grep -cF -- "Draft all five sections" || true)"
assert_eq "no widget in step 9" "0" "$(printf '%s\n' "$STEP9" | grep -cF -- "AskUserQuestion" || true)"
assert_eq "hardest constraint never none" "1" "$(printf '%s\n' "$STEP9" | grep -cF -- 'Never "none"' || true)"
assert_eq "no em dash in step 9" "0" "$(printf '%s\n' "$STEP9" | grep -c -- '—' || true)"

finish_tests
