#!/bin/bash
# test-cycle-design-story-list-asks-in-prose.sh - cycle-design's story list (default mode
# Step 2, roadmap mode Step R1) ends on a prose save question that a yes answers: no widget,
# no fixed-count labels, a singular form for one story, and the outcome rules per reply.
# The unattended-run table answers the default-mode ask with yes.

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

DM="$PLUGIN_ROOT/commands/references/cycle-design/default-mode.md"
RM="$PLUGIN_ROOT/commands/references/cycle-design/roadmap-mode.md"
GORUN="$PLUGIN_ROOT/commands/references/go-run.md"

DM_S2=$(awk '/^### Step 2: Story Brainstorm/ {on=1; next} /^### Step 2.7:/ {on=0} on {print}' "$DM")
RM_R1=$(awk '/^### Step R1:/ {on=1; next} /^### Step R2:/ {on=0} on {print}' "$RM")

begin_test "default mode Step 2 ends on the prose save ask"
assert_not_contains "no widget spec" 'AskUserQuestion' "$DM_S2"
assert_not_contains "no Stories header" 'header: "Stories"' "$DM_S2"
assert_not_contains "no fixed plural label" 'Save these sparks' "$DM_S2"
assert_not_contains "no old scope question" 'Does this capture the scope?' "$DM_S2"
assert_contains_literal "singular form for one story" 'Save this as the spark?' "$DM_S2"
assert_contains_literal "a yes saves" 'A yes** saves the list as it stands: jump to **Step 3-Fast**' "$DM_S2"
assert_contains_literal "one at a time runs every story" 'runs every story through Step 3' "$DM_S2"
assert_contains_literal "edits show the list again" 'edits the list and shows it again' "$DM_S2"
assert_contains_literal "unclear reply gets the same question" 'gets the same question back' "$DM_S2"
assert_eq "no em dash in the new ask" "0" "$(printf '%s\n' "$DM_S2" | grep -c -- 'Save these as the sparks?.*—' || true)"

begin_test "roadmap mode Step R1 ends on the prose save ask"
assert_not_contains "no widget spec" 'AskUserQuestion' "$RM_R1"
assert_not_contains "no fixed plural label" 'Yes, save these' "$RM_R1"
assert_contains_literal "the ask" 'Save these? Or tell me what to add, change or remove.' "$RM_R1"
assert_contains_literal "singular form for one story" 'Save this? Or tell me what to add or change.' "$RM_R1"
assert_contains_literal "a yes continues to R2" 'continue to Step R2' "$RM_R1"
assert_contains_literal "unclear reply gets the same question" 'gets the same question back' "$RM_R1"

begin_test "an unattended run answers the story list ask with yes"
KNOWN="$(sed -n '/^## Known prompts/,/^## Planning/p' "$GORUN")"
assert_contains_literal "row names the ask" '`Save these as the sparks?` | yes.' "$KNOWN"
assert_file_contains "a prose ask with a row is not free text" 'A prose question with its own row in `## Known prompts` is not free text' "$GORUN"
assert_file_contains "its log line" "prose question with a row: \`Answered '<question>' with '<row answer>'.\`" "$GORUN"

finish_tests
