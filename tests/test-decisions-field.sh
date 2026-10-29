#!/bin/bash
# test-decisions-field.sh - Guards the `decisions:` frontmatter field this
# story adds to every story writer, and the canonical header order every
# writer's block is reordered to match. Grown chunk by chunk:
#   Chunk 1 - the field itself, in every template and prose writer block
#   Chunk 2 - the planning agent carries it through its rewrite and reads records
#   Chunk 3 - the S-2 row 9 belt that fails a plan citing none of its records
#   Chunk 4 - the alignment gate, story-final claim, and the release pins
#   Writers' rule - each story writer states, right after its frontmatter
#                   fence, that the list holds only the records the user named
#
# A missing `decisions:` field always reads as `[]` - no warning, no error,
# no rewrite. Every assertion below either pins that or pins the one writer
# that can eat the field (the planning agent, from Chunk 2 on).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-cycle.sh"

echo "=== test-decisions-field.sh ==="
echo ""

# --- Canonical header order (declared once, per the story's ## Decisions) ---
# identity -> state -> dates -> membership -> provenance links -> alignment -> chunk counters
CANONICAL_ORDER=(
  name title type
  status priority
  created updated
  cycle story_number
  source_concept source_concept_last_updated mockup grew_from decisions
  alignment
  chunks_total chunks_complete current_chunk
)

canonical_index() {
  local key="$1" i
  for i in "${!CANONICAL_ORDER[@]}"; do
    if [ "${CANONICAL_ORDER[$i]}" = "$key" ]; then
      echo "$i"
      return 0
    fi
  done
  echo "-1"
}

# Asserts a list of keys (in file order) is a subsequence of CANONICAL_ORDER.
# Keys not found in CANONICAL_ORDER (e.g. a writer's own extra fields) are
# ignored rather than failing the assertion - only relative order among
# canonical fields is being pinned.
assert_canonical_order() {
  local desc="$1"
  shift
  local keys=("$@")
  local prev=-1
  local ok=1
  local bad_key=""
  local k idx
  for k in "${keys[@]}"; do
    idx=$(canonical_index "$k")
    if [ "$idx" = "-1" ]; then
      continue
    fi
    if [ "$idx" -le "$prev" ]; then
      ok=0
      bad_key="$k"
      break
    fi
    prev="$idx"
  done
  if [ "$ok" = "1" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    out of canonical order at: '$bad_key'"
    echo "    keys seen: ${keys[*]}"
    FAIL=$((FAIL + 1))
  fi
}

# Extracts frontmatter keys (file order) from a template's `---`...`---` fence.
extract_template_keys() {
  local file="$1"
  sed -n '/^---$/,/^---$/p' "$file" | grep -v '^---$' | grep -oE '^[a-z_]+:' | sed 's/:$//'
}

# Locates a prose file's embedded frontmatter fence (a `---`...`---` pair
# inside a fenced code sample) by searching for the first such fence AT OR
# AFTER a unique anchor line. Returns "start_line end_line" (both `---` line
# numbers, exclusive of content between them).
locate_fence() {
  local file="$1" anchor="$2"
  local anchor_line fence_start fence_end
  anchor_line=$(grep -n -F "$anchor" "$file" | head -1 | cut -d: -f1)
  fence_start=$(awk -v start="$anchor_line" 'NR >= start && /^---$/ { print NR; exit }' "$file")
  fence_end=$(awk -v start="$((fence_start + 1))" 'NR >= start && /^---$/ { print NR; exit }' "$file")
  echo "$fence_start $fence_end"
}

# Extracts the raw block text (between the two fence lines) for a prose
# writer's frontmatter sample, given a unique anchor above it.
extract_block_text() {
  local file="$1" anchor="$2"
  local range fence_start fence_end
  range=$(locate_fence "$file" "$anchor")
  fence_start=$(echo "$range" | cut -d' ' -f1)
  fence_end=$(echo "$range" | cut -d' ' -f2)
  sed -n "$((fence_start + 1)),$((fence_end - 1))p" "$file"
}

extract_block_keys() {
  local file="$1" anchor="$2"
  extract_block_text "$file" "$anchor" | grep -oE '^[a-z_]+:' | sed 's/:$//'
}

# Prints the three lines after the bare closing code fence that follows a
# prose writer's frontmatter sample (found by the same anchor locate_fence
# takes). The writers' rule sentence must sit in this window, outside the fence.
writer_rule_window() {
  local file="$1" anchor="$2"
  local range fence_end closer
  range=$(locate_fence "$file" "$anchor")
  fence_end=$(echo "$range" | cut -d' ' -f2)
  closer=$(awk -v start="$fence_end" 'NR >= start && /^```$/ { print NR; exit }' "$file")
  sed -n "$((closer + 1)),$((closer + 3))p" "$file"
}

TEMPLATES_DIR_LOCAL="$PLUGIN_ROOT/templates"
FULL_TEMPLATE="$TEMPLATES_DIR_LOCAL/story-full.md"
ROADMAP_TEMPLATE="$TEMPLATES_DIR_LOCAL/story-roadmap.md"
BACKLOG_TEMPLATE="$TEMPLATES_DIR_LOCAL/story-backlog.md"

DEFAULT_MODE="$PLUGIN_ROOT/commands/references/cycle-design/default-mode.md"
ROADMAP_MODE="$PLUGIN_ROOT/commands/references/cycle-design/roadmap-mode.md"
STORY_FROM_PLANNING="$PLUGIN_ROOT/commands/references/story-from-planning.md"
STORY_NEW="$PLUGIN_ROOT/commands/craft-story-new.md"
STORY_FROM_MOCKUP="$PLUGIN_ROOT/commands/references/story-from-mockup.md"
CREATE_STORY_SH="$SCRIPTS_DIR/create-story.sh"
FRONTMATTER_PY_DIR="$PLUGIN_ROOT/scripts/dashboard"

# =====================================================================
# Chunk 1: the field, and every emitter of it
# =====================================================================

# --- Templates: literal + canonical order ---
begin_test "all three templates carry decisions: [] and their headers are in canonical order"
for tpl_name in "story-full.md:$FULL_TEMPLATE" "story-roadmap.md:$ROADMAP_TEMPLATE" "story-backlog.md:$BACKLOG_TEMPLATE"; do
  name="${tpl_name%%:*}"
  file="${tpl_name#*:}"
  assert_file_contains "$name: literal 'decisions: []' present" '^decisions: \[\]$' "$file"
  keys=($(extract_template_keys "$file"))
  assert_canonical_order "$name: header keys in canonical order" "${keys[@]}"
done

# --- Templates: no block-list shape ---
begin_test "no template carries a block-list decisions field"
for file in "$FULL_TEMPLATE" "$ROADMAP_TEMPLATE" "$BACKLOG_TEMPLATE"; do
  assert_file_not_contains "$(basename "$file"): no bare 'decisions:' with no inline value" '^decisions:[[:space:]]*$' "$file"
done

# --- Templates: rendered output still passes the inline-shape gate ---
# Reuses the exact substitution list from tests/test-templates.sh's
# clean-values render test, extended with CYCLE_NAME/STORY_NUMBER/SPARK so
# the same list covers all three templates without drifting between them.
RENDER_SUBST="s|{{STORY_NAME}}|test-story|g; s|{{STORY_TITLE}}|Test Story|g; s|{{DATE}}|2026-02-14|g; s|{{PRIORITY}}|medium|g; s|{{STORY_DESCRIPTION}}|A test story|g; s|{{CYCLE_NAME}}|test-cycle|g; s|{{STORY_NUMBER}}|1|g; s|{{SPARK}}|A test spark|g; s|{{HARDEST_CONSTRAINT}}|N/A|g"

begin_test "rendered templates still pass the inline-shape gate"
for file in "$FULL_TEMPLATE" "$ROADMAP_TEMPLATE" "$BACKLOG_TEMPLATE"; do
  TEST_DIR=$(create_test_dir)
  sed "$RENDER_SUBST" "$file" > "$TEST_DIR/rendered.md"
  RENDERED_FM=$(sed -n '2,/^---$/p' "$TEST_DIR/rendered.md" | grep -v '^---$')
  BROKEN_LINES=$(echo "$RENDERED_FM" | grep -v "^$" | grep -v "^[a-z_]*:" | head -5)
  if [ -z "$BROKEN_LINES" ]; then
    echo "  PASS: $(basename "$file"): all rendered frontmatter lines are key: value format"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $(basename "$file"): found non key:value lines in rendered frontmatter"
    echo "    broken: $BROKEN_LINES"
    FAIL=$((FAIL + 1))
  fi
  cleanup_test_dir
done

# --- Every writer frontmatter block: field present + canonical order ---
begin_test "default-mode.md Step 3e block carries decisions: [] in canonical order"
BLOCK=$(extract_block_text "$DEFAULT_MODE" "**3e. Save Story**")
assert_contains_literal "3e block: literal 'decisions: []' present" 'decisions: []' "$BLOCK"
keys=($(extract_block_keys "$DEFAULT_MODE" "**3e. Save Story**"))
assert_canonical_order "3e block: header keys in canonical order" "${keys[@]}"

begin_test "default-mode.md Step 6d block carries decisions: [] in canonical order"
BLOCK=$(extract_block_text "$DEFAULT_MODE" "**6d. Stories already created in Step 3")
assert_contains_literal "6d block: literal 'decisions: []' present" 'decisions: []' "$BLOCK"
keys=($(extract_block_keys "$DEFAULT_MODE" "**6d. Stories already created in Step 3"))
assert_canonical_order "6d block: header keys in canonical order" "${keys[@]}"

begin_test "roadmap-mode.md frontmatter block carries decisions: [] and alignment: pending, in canonical order"
BLOCK=$(extract_block_text "$ROADMAP_MODE" 'Write to `.craft/cycles/[cycle-dir]/stories/[N]-[slug].md`:')
assert_contains_literal "roadmap-mode block: literal 'decisions: []' present" 'decisions: []' "$BLOCK"
assert_contains_literal "roadmap-mode block: gains 'alignment: pending'" 'alignment: pending' "$BLOCK"
keys=($(extract_block_keys "$ROADMAP_MODE" 'Write to `.craft/cycles/[cycle-dir]/stories/[N]-[slug].md`:'))
assert_canonical_order "roadmap-mode block: header keys in canonical order" "${keys[@]}"

begin_test "story-from-planning.md Phase 5 frontmatter carries decisions: [] in canonical order"
BLOCK=$(extract_block_text "$STORY_FROM_PLANNING" "### Frontmatter construction")
assert_contains_literal "Phase 5 block: literal 'decisions: []' present" 'decisions: []' "$BLOCK"
keys=($(extract_block_keys "$STORY_FROM_PLANNING" "### Frontmatter construction"))
assert_canonical_order "Phase 5 block: header keys in canonical order" "${keys[@]}"

begin_test "craft-story-new.md Step 10 frontmatter carries decisions: [] in canonical order"
BLOCK=$(extract_block_text "$STORY_NEW" "**Frontmatter (always required):**")
assert_contains_literal "Step 10 block: literal 'decisions: []' present" 'decisions: []' "$BLOCK"
keys=($(extract_block_keys "$STORY_NEW" "**Frontmatter (always required):**"))
assert_canonical_order "Step 10 block: header keys in canonical order" "${keys[@]}"

# --- story-from-mockup delegates instead of duplicating ---
begin_test "story-from-mockup delegates instead of duplicating"
assert_file_contains "delegates to craft-story-new Step 10" 'see craft-story-new Step 10' "$STORY_FROM_MOCKUP"
assert_file_not_contains "carries no frontmatter fence of its own" '^---$' "$STORY_FROM_MOCKUP"

# --- create-story.sh round trip: cycle story and backlog story both carry the field ---
begin_test "a story created by create-story.sh carries the field"
TEST_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")

CYCLE_STORY=$(CRAFT_PROJECT_ROOT="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$CREATE_STORY_SH" "cycle-story" "Cycle Story" --cycle=test-cycle)
assert_file_exists "cycle story file created" "$CYCLE_STORY"
assert_file_contains "cycle story carries decisions: []" '^decisions: \[\]$' "$CYCLE_STORY"

BACKLOG_STORY=$(CRAFT_PROJECT_ROOT="$TEST_DIR" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$CREATE_STORY_SH" "backlog-story" "Backlog Story")
assert_file_exists "backlog story file created" "$BACKLOG_STORY"
assert_file_contains "backlog story carries decisions: []" '^decisions: \[\]$' "$BACKLOG_STORY"

rm -rf "$TEST_DIR"

# --- Parser: absent, empty and populated all read the same shape ---
begin_test "the parser reads absent, empty and populated the same shape"
PARSE_OUT=$(python3 -c "
import sys
sys.path.insert(0, '$FRONTMATTER_PY_DIR')
from src import frontmatter

absent = frontmatter.parse('---\nname: x\n---\n')[0].get('decisions', [])
empty = frontmatter.parse('---\nname: x\ndecisions: []\n---\n')[0].get('decisions', [])
populated = frontmatter.parse('---\nname: x\ndecisions: [a, b]\n---\n')[0].get('decisions', [])
print(repr(absent))
print(repr(empty))
print(repr(populated))
")
ABSENT_LINE=$(echo "$PARSE_OUT" | sed -n '1p')
EMPTY_LINE=$(echo "$PARSE_OUT" | sed -n '2p')
POPULATED_LINE=$(echo "$PARSE_OUT" | sed -n '3p')
assert_eq "absent decisions: field reads as []" "[]" "$ABSENT_LINE"
assert_eq "empty decisions: [] reads as []" "[]" "$EMPTY_LINE"
assert_eq "populated decisions: [a, b] reads as ['a', 'b']" "['a', 'b']" "$POPULATED_LINE"

# =====================================================================
# Chunk 2: the planner carries the field and opens the records
# =====================================================================

PLAN_CHUNKS_AGENT="$PLUGIN_ROOT/agents/plan-chunks-agent.md"
IMPLEMENTER_AGENT="$PLUGIN_ROOT/agents/implementer.md"

# Returns "start_line end_line" for the text strictly between the first
# fixed-string match of start_pat and the next fixed-string match of
# end_pat after it (or EOF if end_pat never recurs). Mirrors
# extract_block_text's fence-scoping approach but for prose sections
# bounded by headings rather than `---` fences.
section_bounds() {
  local file="$1" start_pat="$2" end_pat="$3"
  local start_line end_line
  start_line=$(grep -n -F "$start_pat" "$file" | head -1 | cut -d: -f1)
  end_line=$(awk -v s="$start_line" -v pat="$end_pat" 'NR > s && index($0, pat) { print NR; exit }' "$file")
  if [ -z "$end_line" ]; then
    end_line=$(($(wc -l < "$file") + 1))
  fi
  echo "$start_line $end_line"
}

extract_section_text() {
  local file="$1" start_pat="$2" end_pat="$3"
  local bounds start_line end_line
  bounds=$(section_bounds "$file" "$start_pat" "$end_pat")
  start_line=$(echo "$bounds" | cut -d' ' -f1)
  end_line=$(echo "$bounds" | cut -d' ' -f2)
  sed -n "$((start_line + 1)),$((end_line - 1))p" "$file"
}

# --- Phase 3.8 REQUIRED block: decisions: sits between story_number and chunks_total ---
begin_test "the REQUIRED frontmatter block names decisions: between story_number and chunks_total"
FENCE_OPEN=$(awk '/^### 3.8 Write Story File/ { s=1 } s && /^```markdown$/ { print NR; exit }' "$PLAN_CHUNKS_AGENT")
FENCE_CLOSE=""
if [ -n "$FENCE_OPEN" ]; then
  FENCE_CLOSE=$(awk -v s="$FENCE_OPEN" 'NR > s && /^```$/ { print NR; exit }' "$PLAN_CHUNKS_AGENT")
fi
STORY_NUMBER_LINE=""
DECISIONS_FIELD_LINE=""
CHUNKS_TOTAL_LINE=""
if [ -n "$FENCE_OPEN" ] && [ -n "$FENCE_CLOSE" ]; then
  STORY_NUMBER_LINE=$(awk -v s="$FENCE_OPEN" -v e="$FENCE_CLOSE" 'NR > s && NR < e && /^story_number:/ { print NR; exit }' "$PLAN_CHUNKS_AGENT")
  DECISIONS_FIELD_LINE=$(awk -v s="$FENCE_OPEN" -v e="$FENCE_CLOSE" 'NR > s && NR < e && /^decisions:/ { print NR; exit }' "$PLAN_CHUNKS_AGENT")
  CHUNKS_TOTAL_LINE=$(awk -v s="$FENCE_OPEN" -v e="$FENCE_CLOSE" 'NR > s && NR < e && /^chunks_total:/ { print NR; exit }' "$PLAN_CHUNKS_AGENT")
fi
if [ -n "$STORY_NUMBER_LINE" ] && [ -n "$DECISIONS_FIELD_LINE" ] && [ -n "$CHUNKS_TOTAL_LINE" ] \
   && [ "$STORY_NUMBER_LINE" -lt "$DECISIONS_FIELD_LINE" ] && [ "$DECISIONS_FIELD_LINE" -lt "$CHUNKS_TOTAL_LINE" ]; then
  echo "  PASS: decisions: sits between story_number and chunks_total in the REQUIRED block"
  PASS=$((PASS + 1))
else
  echo "  FAIL: decisions: not correctly positioned in the REQUIRED block"
  echo "    story_number=$STORY_NUMBER_LINE decisions=$DECISIONS_FIELD_LINE chunks_total=$CHUNKS_TOTAL_LINE"
  FAIL=$((FAIL + 1))
fi

# --- Phase 1.1: the record-read bullet precedes the ## Decisions bullet ---
begin_test "the Phase 1.1 record bullet sits above the ## Decisions bullet"
RECORD_BULLET_LINE=$(grep -n -F '**Decision records**' "$PLAN_CHUNKS_AGENT" | head -1 | cut -d: -f1)
DECISIONS_BULLET_LINE=$(grep -n -F '**Decisions** —' "$PLAN_CHUNKS_AGENT" | head -1 | cut -d: -f1)
if [ -n "$RECORD_BULLET_LINE" ] && [ -n "$DECISIONS_BULLET_LINE" ] && [ "$RECORD_BULLET_LINE" -lt "$DECISIONS_BULLET_LINE" ]; then
  echo "  PASS: record bullet (line $RECORD_BULLET_LINE) precedes the Decisions bullet (line $DECISIONS_BULLET_LINE)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: record bullet does not precede the Decisions bullet"
  echo "    record=$RECORD_BULLET_LINE decisions=$DECISIONS_BULLET_LINE"
  FAIL=$((FAIL + 1))
fi

RECORD_BULLET_TEXT=""
if [ -n "$RECORD_BULLET_LINE" ]; then
  RECORD_BULLET_TEXT=$(sed -n "${RECORD_BULLET_LINE}p" "$PLAN_CHUNKS_AGENT")
fi

# --- The bullet names both record headings ---
begin_test "the record bullet names both ## Decision and ## Consequences"
assert_contains_literal 'names ## Decision' '## Decision' "$RECORD_BULLET_TEXT"
assert_contains_literal 'names ## Consequences' '## Consequences' "$RECORD_BULLET_TEXT"

# --- The bullet names the approved/ path shape ---
begin_test "the record bullet names the .craft/decisions/approved/ path shape"
assert_contains_literal 'names the approved/ path shape' '.craft/decisions/approved/' "$RECORD_BULLET_TEXT"

# --- Unresolvable slug: CONCERN, not a guess, not a skip ---
begin_test "an unresolvable slug is specified as a CONCERN, not a guess and not a skip"
assert_contains_literal 'names CONCERN' 'CONCERN' "$RECORD_BULLET_TEXT"
assert_contains_literal "names the story's created: date" "story's \`created:\` date" "$RECORD_BULLET_TEXT"
assert_contains_literal 'never a guess' 'never a guess' "$RECORD_BULLET_TEXT"
assert_contains_literal 'never a silent skip' 'never a silent skip' "$RECORD_BULLET_TEXT"

# --- Absent or empty decisions: reads as [] with no CONCERN ---
begin_test "an absent or empty decisions: field is specified as [] with no CONCERN"
assert_contains_literal 'states missing or empty means []' 'missing or empty' "$RECORD_BULLET_TEXT"
assert_contains_literal 'states no CONCERN, no warning, no error' 'no CONCERN, no warning, no error' "$RECORD_BULLET_TEXT"
assert_contains_literal 'states the story file is never rewritten' 'never rewritten' "$RECORD_BULLET_TEXT"

# --- Phase 2.5: records validated by slug into the Design Decision Validation table ---
begin_test "Phase 2.5 validates records by slug into the Design Decision Validation table"
PHASE_2_5_TEXT=$(extract_section_text "$PLAN_CHUNKS_AGENT" '### 2.5 Validate Design Decisions' '### 2.6')
assert_contains_literal 'mentions the decisions: field' 'decisions:' "$PHASE_2_5_TEXT"
assert_contains_literal 'mentions valid / concern / invalid' 'valid / concern / invalid' "$PHASE_2_5_TEXT"
assert_contains_literal 'mentions the Design Decision Validation table' 'Design Decision Validation table' "$PHASE_2_5_TEXT"
assert_contains_literal 'mentions full dated slug' 'full dated slug' "$PHASE_2_5_TEXT"

# --- 1.3.5 Reference Materials contract is untouched; no mention of records ---
begin_test "the Reference Materials contract is untouched"
SECTION_1_3_5=$(extract_section_text "$PLAN_CHUNKS_AGENT" '### 1.3.5 Reading Reference Materials (Contract)' '### 1.4')
assert_file_contains '1.3.5 heading is present' '^### 1\.3\.5 Reading Reference Materials (Contract)$' "$PLAN_CHUNKS_AGENT"
assert_contains_literal 'anchor table header row is present' '| File type | Anchor format | How to read |' "$SECTION_1_3_5"
assert_not_contains '1.3.5 makes no mention of the approved/ path' '\.craft/decisions/approved' "$SECTION_1_3_5"
assert_not_contains '1.3.5 does not name the decisions: field' 'decisions:' "$SECTION_1_3_5"

# --- The preserve-everything-else frontmatter rule survives ---
begin_test "the preserve-everything-else frontmatter rule survives"
assert_file_contains 'preserve-everything-else row is present' 'Update `chunks_total`, `updated`.*preserve everything else' "$PLAN_CHUNKS_AGENT"

# --- The implementer never learns about decisions: (ruled 2026-09-04: "Only the plan") ---
begin_test "agents/implementer.md carries no mention of decisions:"
assert_file_not_contains 'implementer.md has no decisions: mention' 'decisions:' "$IMPLEMENTER_AGENT"

# =====================================================================
# Chunk 3: the belt - S-2 row 9
# =====================================================================

SKILL_MD="$PLUGIN_ROOT/skills/plan-chunks/SKILL.md"

# --- Row 9 exists, keyed on decision-record evidence ---
begin_test "SKILL.md carries an S-2 row 9 keyed on decision-record evidence"
assert_file_contains "row 9 exists in the check table" '^| 9 |' "$SKILL_MD"
assert_file_contains "row 9 is keyed on the decisions: field" '^| 9 |.*decisions:' "$SKILL_MD"
ROW_9_LINE=$(grep -n '^| 9 |' "$SKILL_MD" | head -1 | cut -d: -f1)
ROW_9_TEXT=""
if [ -n "$ROW_9_LINE" ]; then
  ROW_9_TEXT=$(sed -n "${ROW_9_LINE}p" "$SKILL_MD")
fi
assert_contains_literal "row 9 declares grep+read logic, not a single regex" 'This is grep+read logic, not a single regex.' "$ROW_9_TEXT"
assert_contains_literal "row 9 carries the legacy-plans clause verbatim" 'Applies only to plans produced after this gate shipped - legacy plans never re-triage' "$ROW_9_TEXT"

# --- Row 9's failure text names the slugs with no evidence ---
begin_test "row 9's failure text names the slugs with no evidence"
assert_contains_literal "failure text carries a [list] placeholder for the missing slugs" '[list]' "$ROW_9_TEXT"
assert_contains_literal "failure text names decision record(s) with no evidence" 'show no evidence of being read' "$ROW_9_TEXT"

# --- Row 9 states the empty-or-absent exemption inline ---
begin_test "row 9 states the empty-or-absent exemption inline"
assert_contains_literal "exemption: empty or absent decisions: passes with no output" 'an empty or absent' "$ROW_9_TEXT"
assert_contains_literal "exemption: passes with no output" 'passes with no output' "$ROW_9_TEXT"

# --- Step 3 routing range widens to cover rows 8 and 9 ---
begin_test "the Step 3 routing range covers rows 8 and 9"
assert_file_not_contains "old 'Checks 2-7' range no longer present" 'Checks 2-7' "$SKILL_MD"
assert_file_contains "routing range now reads 'Checks 2-9'" 'Checks 2-9' "$SKILL_MD"

# --- Row 9's prose uses regular dashes only ---
begin_test "row 9's prose uses regular dashes, never an em dash"
assert_not_contains "row 9 text has no em dash" $'\xe2\x80\x94' "$ROW_9_TEXT"

# --- The eight existing check rows survive, unchanged, in ascending order ---
begin_test "the eight existing check rows survive in order"
CHECK_NAME_STRINGS=(
  '`## Chunks` section exists'
  '`chunks_total` in frontmatter is 2-7'
  '`## The Pitch` section has content + conditions table'
  '`## Investigation` section has content'
  '`## Acceptance` section has detailed criteria'
  'Each chunk has required sub-sections'
  'Contract lines carry receipts'
  'Visual bindings cover the Element Binding Table (UI/styling stories)'
  "Each chunk's Done When asserts a green tree"
  '`## Acceptance Pre-Flight` receipt present, no unreachable vehicles'
  'Risk tag comments name a mechanism, not a bare threshold'
)
PREV_LINE=0
ROWS_IN_ORDER=1
BAD_ROW=""
for check_name in "${CHECK_NAME_STRINGS[@]}"; do
  line=$(grep -n -F "$check_name" "$SKILL_MD" | head -1 | cut -d: -f1)
  if [ -z "$line" ] || [ "$line" -le "$PREV_LINE" ]; then
    ROWS_IN_ORDER=0
    BAD_ROW="$check_name"
    break
  fi
  PREV_LINE="$line"
done
if [ "$ROWS_IN_ORDER" = "1" ]; then
  echo "  PASS: all eight existing check rows present, in ascending line order"
  PASS=$((PASS + 1))
else
  echo "  FAIL: existing check rows out of order or missing"
  echo "    first bad row: '$BAD_ROW'"
  FAIL=$((FAIL + 1))
fi

# --- S-3 Step 3 is intact ---
begin_test "S-3 Step 3 is intact"
assert_file_contains "S-3 Step 3 heading present" 'Design Decision Validation:\*\*' "$SKILL_MD"
assert_file_contains "anchor sentence: proceed with no interaction" 'proceed with no interaction\.' "$SKILL_MD"
assert_file_contains "anchor sentence: surface explicitly, user stays in control" 'Surface them explicitly so the user stays in control\.' "$SKILL_MD"

# --- Gate mirror: reimplements row 9's logic in bash, exercised against
#     fixture story files (mirrors tests/test-risk-tag-mechanism.sh:17-40's
#     mirror of check #8). This is what makes the model-behaviour belt
#     testable at all - the mirror pins the LOGIC; the text pins above pin
#     that the logic is actually the one wired into SKILL.md. ---

# Extracts the frontmatter decisions: list as space-separated slugs.
row9_extract_slugs() {
  local file="$1" line
  line=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^decisions:' | head -1)
  echo "$line" | sed 's/^decisions:[[:space:]]*//; s/\[//; s/\]//; s/,/ /g'
}

# Prints the story's ## Investigation section body.
row9_investigation_text() {
  awk '/^## Investigation/{f=1; next} /^## /{if(f) exit} f' "$1"
}

# Prints every chunk's **Contracts:** and **Approach:** lines.
row9_contracts_and_approach_text() {
  awk '
    /^\*\*Contracts:\*\*/ { f=1; next }
    /^\*\*Approach:\*\*/   { f=1; next }
    /^\*\*[A-Za-z ]+:\*\*/ { f=0 }
    /^### Chunk/           { f=0 }
    f { print }
  ' "$1"
}

# Prints the agent's Design Decision Validation table, if any.
row9_design_decision_validation_text() {
  awk '/Design Decision Validation/{f=1; next} /^## /{if(f) exit} f' "$1"
}

# Row 9 gate mirror: prints "pass" or "fail:slug1,slug2" for a story file.
row9_gate() {
  local file="$1" slugs evidence missing=() slug
  slugs=$(row9_extract_slugs "$file")
  if [ -z "$(echo "$slugs" | tr -d '[:space:]')" ]; then
    echo "pass"
    return
  fi
  evidence=$(
    row9_investigation_text "$file"
    row9_contracts_and_approach_text "$file"
    row9_design_decision_validation_text "$file"
  )
  for slug in $slugs; do
    if ! echo "$evidence" | grep -qF "$slug"; then
      missing+=("$slug")
    fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    echo "pass"
  else
    local IFS=,
    echo "fail:${missing[*]}"
  fi
}

TEST_DIR=$(create_test_dir)
ROW9_FIXTURE_DIR="$TEST_DIR"

ROW9_FIXTURE_NO_EVIDENCE="$ROW9_FIXTURE_DIR/story-no-evidence.md"
cat > "$ROW9_FIXTURE_NO_EVIDENCE" << 'EOF'
---
name: fixture-no-evidence
decisions: [2026-01-01-example-record]
---

# Story: Fixture with no evidence

## Investigation
Nothing in this narrative names the record read.

## Chunks

### Chunk 1: Something
**Goal:** does something
**Contracts:**
- some unrelated contract line [defines]
**Approach:**
- some unrelated approach note
EOF

ROW9_FIXTURE_CITED="$ROW9_FIXTURE_DIR/story-cited-in-investigation.md"
cat > "$ROW9_FIXTURE_CITED" << 'EOF'
---
name: fixture-cited
decisions: [2026-01-01-example-record]
---

# Story: Fixture cited under Investigation

## Investigation
The record 2026-01-01-example-record was opened and its ruling folded into this plan.

## Chunks

### Chunk 1: Something
**Goal:** does something
**Contracts:**
- some unrelated contract line [defines]
**Approach:**
- some unrelated approach note
EOF

ROW9_FIXTURE_EMPTY="$ROW9_FIXTURE_DIR/story-empty-decisions.md"
cat > "$ROW9_FIXTURE_EMPTY" << 'EOF'
---
name: fixture-empty
decisions: []
---

# Story: Fixture with no decision records

## Investigation
No decision record is carried, so nothing needs citing.

## Chunks

### Chunk 1: Something
**Goal:** does something
**Contracts:**
- some unrelated contract line [defines]
EOF

begin_test "gate mirror: a plan citing none of its slugs fails, and the failure names the slug"
assert_eq "gate fails and names the uncited slug" "fail:2026-01-01-example-record" "$(row9_gate "$ROW9_FIXTURE_NO_EVIDENCE")"

begin_test "gate mirror: a slug cited under ## Investigation passes"
assert_eq "gate passes when the slug is cited in Investigation" "pass" "$(row9_gate "$ROW9_FIXTURE_CITED")"

begin_test "gate mirror: an empty decisions: list passes with no evidence anywhere"
assert_eq "gate passes on an empty decisions: list" "pass" "$(row9_gate "$ROW9_FIXTURE_EMPTY")"

cleanup_test_dir

# =====================================================================
# Chunk 4: the downstream readers, and the release
# =====================================================================

ALIGNMENT_CHECK="$PLUGIN_ROOT/commands/references/alignment-check.md"
STORY_IMPLEMENT="$PLUGIN_ROOT/commands/craft-story-implement.md"
CLAIMS_AUDITOR="$PLUGIN_ROOT/agents/claims-auditor.md"
LEGACY_STORIES_DIR="$PLUGIN_ROOT/tests/fixtures/legacy-stories"

# --- Step 0.5 detection names decisions: alongside source_concept: ---
begin_test "Step 0.5 detection names decisions: alongside source_concept:"
DETECTION_LINE_NUM=$(grep -n -F '**Detection:**' "$ALIGNMENT_CHECK" | head -1 | cut -d: -f1)
DETECTION_TEXT=""
if [ -n "$DETECTION_LINE_NUM" ]; then
  DETECTION_TEXT=$(sed -n "${DETECTION_LINE_NUM}p" "$ALIGNMENT_CHECK")
fi
assert_contains_literal "detection names source_concept:" 'source_concept:' "$DETECTION_TEXT"
assert_contains_literal "detection names decisions:" 'decisions:' "$DETECTION_TEXT"
assert_contains_literal "detection is one condition with an OR, not two paragraphs" ' OR ' "$DETECTION_TEXT"
assert_contains_literal "skip-to-Step-1 branch stays in the same sentence flow" 'skip directly to Step 1 with the existing prompt unchanged' "$DETECTION_TEXT"

# --- Heading no longer claims planning-sourced stories only ---
begin_test "the Step 0.5 heading no longer claims planning-sourced stories only"
assert_file_not_contains "old heading suffix is gone" 'Planning-Sourced Stories Only' "$ALIGNMENT_CHECK"
assert_file_contains "Step 0.5 heading still present" '^### Step 0\.5: Planning Context Injection$' "$ALIGNMENT_CHECK"

# --- Record extraction is its own numbered step, reading the two record headings ---
begin_test "record pointer step hands paths and the read-first sentence, never excerpts"
RECORD_STEP_LINE=$(grep -n -F '4a. **Decision records (pointer, not extraction)' "$ALIGNMENT_CHECK" | head -1 | cut -d: -f1)
RECORD_STEP_TEXT=""
if [ -n "$RECORD_STEP_LINE" ]; then
  RECORD_STEP_TEXT=$(sed -n "${RECORD_STEP_LINE}p" "$ALIGNMENT_CHECK")
fi
assert_contains_literal "record step tells the agent to read Decision and Consequences first" 'Read the Decision and Consequences of each record above before investigating' "$RECORD_STEP_TEXT"
assert_contains_literal "record step tells the agent to raise contradictions as CONFLICT" 'report it as a CONFLICT naming the record' "$RECORD_STEP_TEXT"
assert_contains_literal "records never enter the Planning Context block or its cap" 'never enter the Planning Context block or its token cap' "$RECORD_STEP_TEXT"
assert_contains_literal "record step names the approved/ path shape" '.craft/decisions/approved/' "$RECORD_STEP_TEXT"
assert_contains_literal "record step keys off the decisions: frontmatter list" "story's \`decisions:\`" "$RECORD_STEP_TEXT"

# --- Record extraction is NOT folded into the Reference Materials anchor loop ---
begin_test "record extraction is not folded into the Reference Materials anchor rules"
ANCHOR_LOOP_TEXT=$(extract_section_text "$ALIGNMENT_CHECK" '3. For each cited file + anchor' '4a. **Decision records (pointer')
assert_not_contains "step 3's anchor-type list gains no decisions entry" 'approved/' "$ANCHOR_LOOP_TEXT"
assert_not_contains "step 3's anchor-type list names no decision record type" 'decision record' "$ANCHOR_LOOP_TEXT"
assert_contains_literal "the record step is its own numbered entry (4a), not folded into step 3 or 4" '4a. **Decision records (pointer' "$RECORD_STEP_TEXT"

# --- Unresolvable slug: noted in the block, not raised as a stale-anchor question ---
begin_test "an unresolvable slug is listed as (not found), not raised as a stale-anchor question"
assert_contains_literal "an unresolvable slug is listed with (not found)" 'listed anyway with "(not found)"' "$RECORD_STEP_TEXT"
assert_contains_literal "it explicitly does not raise the stale-anchor question" 'does NOT raise the stale-anchor question from step 4' "$RECORD_STEP_TEXT"

# --- Approved records lead the keep-order; the four existing tiers survive in order ---
begin_test "the keep-order holds the four Reference Materials tiers in order; records are not in it"
assert_not_contains "records no longer compete for the cap" 'Approved decision records' "$(sed -n '/Hard 2000-token cap/,/If citations are dropped/p' "$ALIGNMENT_CHECK")"
KEEP_ORDER_STRINGS=(
  'active.md dated entries'
  'Concept Locked Decisions sections'
  'Sibling story precedents'
  'Mockups (visual contracts'
)
PREV_LINE=0
KEEP_ORDER_OK=1
BAD_TIER=""
for tier in "${KEEP_ORDER_STRINGS[@]}"; do
  line=$(grep -n -F "$tier" "$ALIGNMENT_CHECK" | head -1 | cut -d: -f1)
  if [ -z "$line" ] || [ "$line" -le "$PREV_LINE" ]; then
    KEEP_ORDER_OK=0
    BAD_TIER="$tier"
    break
  fi
  PREV_LINE="$line"
done
if [ "$KEEP_ORDER_OK" = "1" ]; then
  echo "  PASS: keep-order runs active.md, Concept Locked Decisions, Sibling story, Mockups, in ascending line order"
  PASS=$((PASS + 1))
else
  echo "  FAIL: keep-order out of order or missing a tier"
  echo "    first bad tier: '$BAD_TIER'"
  FAIL=$((FAIL + 1))
fi

# --- Step 5.1b names the decisions claim, conditional on a non-empty list ---
begin_test "Step 5.1b names the decisions claim, conditional on a non-empty list"
assert_file_contains "5.1b adds the bare decisions claim" 'frontmatter decisions: present and equals \[slug, \.\.\.\]' "$STORY_IMPLEMENT"
assert_file_contains "5.1b states an empty or absent list adds no claim" 'an empty or absent list adds no claim' "$STORY_IMPLEMENT"

# --- The claims auditor evidence table still has exactly three data rows ---
begin_test "the claims auditor evidence table still has exactly three rows"
EVIDENCE_TABLE_TEXT=$(extract_section_text "$CLAIMS_AUDITOR" '## Evidence sources' '## Verdict rules')
EVIDENCE_ROW_COUNT=$(echo "$EVIDENCE_TABLE_TEXT" | grep '^|' | grep -v 'Claim type' | grep -v '^|-' | grep -c '.')
assert_eq "evidence table has exactly three data rows" "3" "$EVIDENCE_ROW_COUNT"

# --- The field survives completion (update-story-status.sh) ---
begin_test "the field survives completion"
TEST_DIR=$(create_test_dir)
COMPLETION_DIR="$TEST_DIR"
COMPLETION_STORY="$COMPLETION_DIR/fixture-completion.md"
cat > "$COMPLETION_STORY" << 'EOF'
---
name: fixture-completion
title: "Fixture Completion"
status: active
priority: medium
created: 2026-01-01
updated: 2026-01-01
decisions: [a, b]
alignment: complete
chunks_total: 1
chunks_complete: 1
current_chunk: 1
---

# Story: Fixture Completion
EOF
DECISIONS_BEFORE=$(grep '^decisions:' "$COMPLETION_STORY" || true)
STATUS_BEFORE=$(grep '^status:' "$COMPLETION_STORY" || true)
UPDATED_BEFORE=$(grep '^updated:' "$COMPLETION_STORY" || true)
"$SCRIPTS_DIR/update-story-status.sh" "$COMPLETION_STORY" complete > /dev/null
DECISIONS_AFTER=$(grep '^decisions:' "$COMPLETION_STORY" || true)
STATUS_AFTER=$(grep '^status:' "$COMPLETION_STORY" || true)
UPDATED_AFTER=$(grep '^updated:' "$COMPLETION_STORY" || true)
assert_eq "decisions line is byte-identical after completion" "$DECISIONS_BEFORE" "$DECISIONS_AFTER"
assert_not_eq "status changed on completion" "$STATUS_BEFORE" "$STATUS_AFTER"
assert_not_eq "updated changed on completion" "$UPDATED_BEFORE" "$UPDATED_AFTER"
cleanup_test_dir

# --- The field survives backlog-to-cycle promotion (move-story.sh) ---
begin_test "the field survives backlog-to-cycle promotion"
PROMO_DIR=$(create_craft_with_cycle "test-cycle" "Test Cycle" "1")
PROMO_STORY="$PROMO_DIR/.craft/backlog/fixture-promo.md"
cat > "$PROMO_STORY" << 'EOF'
---
name: fixture-promo
title: "Fixture Promo"
status: backlog
priority: medium
created: 2026-01-01
updated: 2026-01-01
decisions: []
alignment: pending
---

# Story: Fixture Promo
EOF
PROMOTED_STORY=$("$SCRIPTS_DIR/move-story.sh" "$PROMO_STORY" "test-cycle" | tail -1)
assert_file_exists "promoted story file exists" "$PROMOTED_STORY"
assert_file_contains "promoted story still carries decisions: []" '^decisions: \[\]$' "$PROMOTED_STORY"
# move-story.sh inserts cycle:/story_number: right after status:/cycle: (its own
# untouched mechanism, unrelated to decisions:), so a full-header canonical-order
# subsequence check is not the invariant this story protects. What survives
# promotion by construction is the one anchor the Investigation locked: decisions:
# stays directly above alignment:, because nothing inserts anything at that seam.
PROMO_DECISIONS_LINE=$(grep -n '^decisions: \[\]$' "$PROMOTED_STORY" | head -1 | cut -d: -f1)
PROMO_ALIGNMENT_LINE=$(grep -n '^alignment:' "$PROMOTED_STORY" | head -1 | cut -d: -f1)
if [ -n "$PROMO_DECISIONS_LINE" ] && [ -n "$PROMO_ALIGNMENT_LINE" ] && [ "$((PROMO_DECISIONS_LINE + 1))" = "$PROMO_ALIGNMENT_LINE" ]; then
  echo "  PASS: decisions: still sits directly above alignment: after promotion"
  PASS=$((PASS + 1))
else
  echo "  FAIL: decisions: no longer sits directly above alignment: after promotion"
  echo "    decisions=$PROMO_DECISIONS_LINE alignment=$PROMO_ALIGNMENT_LINE"
  FAIL=$((FAIL + 1))
fi
rm -rf "$PROMO_DIR"

# --- The changelog's newest heading is never ahead of plugin.json's version ---
# Entries are notable-only: internal changes bump plugin.json with no entry, so the
# newest heading may lag the version but never lead it (check-doc-drift.sh rule 8).
begin_test "the changelog's newest heading is never ahead of plugin.json's version"
PLUGIN_VERSION=$(grep -oE '"version": *"[^"]+"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | sed -E 's/.*"([^"]+)"$/\1/')
CHANGELOG_TOP_ENTRY=$(grep -m1 -E '^## ' "$PLUGIN_ROOT/CHANGELOG.md" 2>/dev/null | sed -E 's/^## +//')
CHANGELOG_TOP_VERSION=$(printf '%s' "$CHANGELOG_TOP_ENTRY" | sed -E 's/ - [0-9]{4}-[0-9]{2}-[0-9]{2}$//')
# not_ahead PLUGIN CHANGELOG: yes when CHANGELOG sorts at or below PLUGIN.
not_ahead() { [ -n "$1" ] && [ -n "$2" ] && [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -1)" = "$1" ] && echo yes || echo no; }
assert_eq "newest heading ($CHANGELOG_TOP_VERSION) is not ahead of plugin.json ($PLUGIN_VERSION)" "yes" "$(not_ahead "$PLUGIN_VERSION" "$CHANGELOG_TOP_VERSION")"
assert_eq "a heading equal to the version passes" "yes" "$(not_ahead 2.10.0 2.10.0)"
assert_eq "a heading behind the version passes" "yes" "$(not_ahead 2.10.1 2.10.0)"
assert_eq "a heading behind across a minor boundary passes" "yes" "$(not_ahead 2.10.0 2.9.3)"
assert_eq "a heading ahead of the version fails" "no" "$(not_ahead 2.10.0 2.10.1)"
assert_eq "a missing version fails" "no" "$(not_ahead "" 2.10.0)"

# --- agents/claims-auditor.md and agents/implementer.md carry no mention of decisions: ---
begin_test "agents/claims-auditor.md and agents/implementer.md carry no decisions: mention"
assert_file_not_contains "claims-auditor.md has no decisions: mention" 'decisions:' "$CLAIMS_AUDITOR"
assert_file_not_contains "implementer.md has no decisions: mention" 'decisions:' "$IMPLEMENTER_AGENT"

# --- Pre-update stories are untouched by the parser, the row-9 gate mirror,
#     and a bash mirror of the Step 0.5 detection logic ---

# Mirrors the Step 0.5 detection sentence: fires if source_concept: is
# populated OR decisions: is non-empty; a missing field reads as empty.
step05_detect() {
  local file="$1" sc dec
  sc=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^source_concept:' | head -1 | sed 's/^source_concept:[[:space:]]*//')
  if [ -n "$(echo "$sc" | tr -d '[:space:]')" ]; then
    echo "inject"
    return
  fi
  dec=$(sed -n '/^---$/,/^---$/p' "$file" | grep '^decisions:' | head -1 | sed 's/^decisions:[[:space:]]*//')
  dec=$(echo "$dec" | tr -d '[:space:]')
  if [ -n "$dec" ] && [ "$dec" != "[]" ]; then
    echo "inject"
    return
  fi
  echo "skip"
}

begin_test "pre-update stories are untouched"
LEGACY_OK=1
for legacy_file in "$LEGACY_STORIES_DIR"/*.md; do
  before_sum=$(shasum -a 256 "$legacy_file" | cut -d' ' -f1)

  parsed_decisions=$(python3 -c "
import sys
sys.path.insert(0, '$FRONTMATTER_PY_DIR')
from src import frontmatter
fields, _ = frontmatter.read('$legacy_file')
print(repr(fields.get('decisions', [])))
" 2>&1)
  if [ "$parsed_decisions" != "[]" ]; then
    LEGACY_OK=0
    echo "    parser did not read decisions: as [] for $(basename "$legacy_file"): $parsed_decisions"
  fi

  gate_result=$(row9_gate "$legacy_file" 2>&1)
  if [ "$gate_result" != "pass" ]; then
    LEGACY_OK=0
    echo "    row-9 gate mirror did not pass $(basename "$legacy_file"): $gate_result"
  fi

  detect_result=$(step05_detect "$legacy_file" 2>&1)
  if [ "$detect_result" != "skip" ]; then
    LEGACY_OK=0
    echo "    Step 0.5 detection mirror did not skip $(basename "$legacy_file"): $detect_result"
  fi

  after_sum=$(shasum -a 256 "$legacy_file" | cut -d' ' -f1)
  if [ "$before_sum" != "$after_sum" ]; then
    LEGACY_OK=0
    echo "    fixture file was mutated: $(basename "$legacy_file")"
  fi
done
if [ "$LEGACY_OK" = "1" ]; then
  echo "  PASS: every legacy fixture reads as [], passes the row-9 gate mirror, skips Step 0.5 injection, and is byte-identical afterward"
  PASS=$((PASS + 1))
else
  echo "  FAIL: legacy fixture check failed (see above)"
  FAIL=$((FAIL + 1))
fi

# =====================================================================
# The writers' rule: only the records the user named
# =====================================================================

assert_writer_rule() {
  local window="$1"
  assert_contains_literal "window holds 'never scan the store for candidates'" 'never scan the store for candidates' "$window"
  assert_contains_literal "window holds the reader-side 'by tag, by topic, or by judged relevance'" 'by tag, by topic, or by judged relevance' "$window"
  assert_contains_literal "window holds 'NOT LAW for this story - it is history'" 'NOT LAW for this story - it is history' "$window"
}

begin_test "craft-story-new.md Step 10: the writers' rule sits right after the frontmatter fence"
assert_writer_rule "$(writer_rule_window "$STORY_NEW" "**Frontmatter (always required):**")"

begin_test "story-from-planning.md Phase 5: the writers' rule sits right after the frontmatter fence"
assert_writer_rule "$(writer_rule_window "$STORY_FROM_PLANNING" "### Frontmatter construction")"

begin_test "default-mode.md Step 3e: the writers' rule sits right after the story fence, outside it"
assert_writer_rule "$(writer_rule_window "$DEFAULT_MODE" "**3e. Save Story**")"

begin_test "roadmap-mode.md step 3: the writers' rule sits right after the story fence, outside it"
assert_writer_rule "$(writer_rule_window "$ROADMAP_MODE" 'Write to `.craft/cycles/[cycle-dir]/stories/[N]-[slug].md`:')"

begin_test "each writer carries the writers' rule exactly once"
for writer_file in "$STORY_NEW" "$STORY_FROM_PLANNING" "$DEFAULT_MODE" "$ROADMAP_MODE"; do
  rule_count=$(grep -c -F "never scan the store for candidates" "$writer_file" || true)
  if [ "$rule_count" = "1" ]; then
    echo "  PASS: $(basename "$writer_file") carries the rule once"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $(basename "$writer_file") carries the rule $rule_count times"
    FAIL=$((FAIL + 1))
  fi
done

finish_tests
