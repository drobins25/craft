# Detailing Mode Reference

Flesh out a previously-roadmapped cycle: take stories that have only titles and add sparks, content direction, and visual direction per story. Fires when the user re-enters cycle-design with an existing planning cycle directory.

The orchestrator command (`commands/craft-cycle-design.md`) defines the routing - this reference contains the full mode flow.

---

## Detailing Mode (Flesh Out Planning Cycles)

Entered when `/craft` routes here with an existing cycle directory name as arg. This mode adds sparks and detail to title-only stories created in Roadmap Mode.

### Pre-check

If args are provided:
1. Check if `.craft/cycles/[arg]/` exists
2. Check if `cycle.yaml` has `status: planning`
3. If valid: set PLANNING_CYCLE, **capture cycle.yaml's `source_concept`** into context, and proceed to Step D1
4. If invalid: show error and offer cycle picker

Use **Read** to read `.craft/cycles/[arg]/cycle.yaml`. Parse `status:` AND `source_concept:` values.

If the file exists and `status == "planning"`:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh PLANNING_CYCLE "[arg]"
```

Remember the cycle's `source_concept` for the rest of this session - it determines routing for any NEW stories added during detailing (see Step D2b).

If the file doesn't exist or status is not `planning` → show error and offer cycle picker.

### Step D1: Show Current State

Read all stories in the cycle. Check which have sparks, type tags, and creative tool output:

```
# Check story state
Glob ".craft/cycles/[cycle]/stories/*.md" → story_files

stories = []
for each story_file in story_files:
  Read story_file (limit: 50) → parse frontmatter + section headings
  - title: from frontmatter
  - has_spark: "## Spark" section has non-empty, non-comment content
  - type: from frontmatter `type` field (may be missing)
  - has_content_direction: "## Content Direction" section has non-comment content
  - has_visual_direction: "## Visual Direction" section has non-comment content
  stories.append(title, has_spark, type, has_content_direction, has_visual_direction)
```

**Batch type inference for stories with sparks but no type:**

If any stories have sparks but missing `type` field, infer the type from the spark content and present for confirmation:

> "I've inferred types for stories with existing sparks:
>
> | # | Story | Type (inferred) |
> |---|-------|-----------------|
> | 1 | [Title] | `ui` |
> | 2 | [Title] | `technical` |
>
> Correct? (Say which to change, or confirm to update the files.)"

On confirmation, update each story's frontmatter to add the `type` field.

**Present the full status:**

> "**Cycle: [Name]** — Detailing Mode
>
> | # | Story | Spark | Type | Content | Visual |
> |---|-------|-------|------|---------|--------|
> | 1 | [Title] | ✓ | `ui` | — | — |
> | 2 | [Title] | — | — | — | — |
> | 3 | [Title] | ✓ | `technical` | ✓ | n/a |
>
> [N] stories need sparks. [M] stories are missing creative tool output."

The "Visual" column shows `n/a` for non-ui stories, `—` for ui stories missing Visual Direction, and `✓` for ui stories with it. The "Content" column shows `—` for any story missing Content Direction and `✓` for those with it.

Use **AskUserQuestion**:
```
question: "How do you want to detail these stories?"
header: "Approach"
options:
  - label: "Go through all stories"
    description: "Capture sparks for each story in order"
  - label: "Pick specific stories"
    description: "Choose which stories to detail now"
  - label: "Add more stories first"
    description: "Add new story titles before detailing"
  - label: "Rearrange/rename"
    description: "Reorder or rename existing stories"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their intent.

### Step D2: Capture Sparks

**Planning-source routing applies when cycle.yaml has `source_concept` set (captured in Pre-check).** For each story that needs a spark, apply the action-moment framing:

- **Planning-extraction moment** (the spark for this story should be drawn from the cycle's planning concept): Read `${CLAUDE_PLUGIN_ROOT}/commands/references/story-from-planning.md` and execute its phases against the cycle's source_concept. The protocol writes the spark content from the planning doc and adds `source_concept` + `source_concept_last_updated` to the story's frontmatter.

  **CRITICAL: include the invocation marker** when executing the protocol. State explicitly in your context before running Phase 1:

  > `INVOCATION: cycle-design - planning source already confirmed in cycle.yaml`

  This marker is required for Phase 1's auto-resolve to fire. Without it, Phase 1 falls back to corpus-scan and asks the user to pick a concept.

- **Add-a-separate-story moment / fleshing out a non-planning-sourced story**: Use the existing Step 3 flow below.

For a freeform story (or when cycle.yaml has no source_concept), reuse the existing **Step 3** flow (Capture Each Story):

- **3a. Choose Your Path** — "Let's get creative" or "I know what I want" (with recommendation for `type: ui` stories)
- **3b. Spark** — Capture the essence
- **3c. Rough Acceptance** — Optional
- **3d. Dependencies** — What depends on what
- **3e. Save Story** — Update the existing story file with spark content (including `type` in frontmatter)

Stories that already have sparks are skipped unless user explicitly asks to revisit.

**Existing stories without source_concept are NOT retroactively stamped during detailing.** If an existing story is being detailed and the user signals that it's actually planning-sourced ("this one is from the company-onboarding concept"), the orchestrator MAY ask whether to populate source_concept retroactively - but never silently. Recovery affordance, not default behavior.

### Step D2b: Creative Tool Checks (After Each Story's Spark Is Captured)

After writing/updating a story's spark (whether new or revised), run two independent checks. These also apply to stories that already had sparks but are missing creative tool output.

**Check 1: Content-spark** — runs for ANY story type.

Condition: The story has no `## Content Direction` content (empty or comment-only).

```
question: "[Story Name] has unsurfaced content assumptions. Run content-spark to surface them before planning?"
header: "Content Check"
options:
  - label: "Yes, run content-spark"
    description: "Surface content assumptions before planning"
  - label: "Skip"
    description: "Move on without content-spark"
  - label: "Skip for all remaining"
    description: "Don't prompt for content-spark on remaining stories"
```

If "Yes": Read and execute `${CLAUDE_PLUGIN_ROOT}/commands/references/content-spark-inline.md` inline against this story. After it completes, continue to Check 2.

**Check 2: Creative-spark** - runs for `type: ui` stories only.

Condition: The story has `type: ui` AND no `## Visual Direction` content (empty or comment-only).

```
question: "[Story Name] is a visual story with no creative exploration yet. Run creative-spark to explore directions?"
header: "Creative Check"
options:
  - label: "Yes, explore directions"
    description: "Run creative-spark to generate visual options"
  - label: "Skip"
    description: "Use the current spark as-is"
  - label: "Skip for all remaining"
    description: "Don't prompt for creative-spark on remaining stories"
```

If "Yes": Read and execute `${CLAUDE_PLUGIN_ROOT}/commands/references/creative-spark-inline.md` inline against this story. After it completes, update the story file with the chosen Visual Direction and Wireframe.

**"Skip for all remaining"** sets a flag for the current detailing session — subsequent stories skip that check without prompting. The two checks are independent — skipping content-spark for all doesn't skip creative-spark.

Progress indicator between stories:

> "Stories detailed: 2/5 ✓
>
> Ready for **Story 3: [Name]**?"

### Step D3: Finalize

After all stories have sparks, continue with the existing cycle finalization flow:

- **Step 5: Cycle Review** — Review all stories as a whole
- **Step 6: Finalize Cycle** — Create/update cycle.yaml and .state
- **Step 7: Visual Cohesion** — Optional design-vibe review
- **Step 8: Confirm Cycle** — Next steps

**Clear PLANNING_CYCLE when done:**
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh PLANNING_CYCLE ""
```

---

