# Default Mode Reference

This is the full creative cycle planning flow. Fires when the user picks "Add stories now" at Step 1b. Brainstorms stories, captures sparks (with optional creative-spark per story), reviews the cycle, and offers planning paths.

The orchestrator command (`commands/craft-cycle-design.md`) defines the routing - this reference contains the full mode flow.

---

### Step 2: Story Brainstorm

> "Let's map out the stories for this cycle.
>
> What needs to happen to achieve: **[goal]**?"

Help the user decompose the cycle into stories through conversation:
- What are the pieces?
- What's the user journey?
- What are the dependencies?

**Note:** Don't automatically invoke `creative-spark` here. The user usually knows what stories they need — they're decomposing a known feature. Creative exploration happens per-story in Step 3.

**Only invoke `creative-spark`** if the user is genuinely unsure what stories the cycle needs (e.g., "I don't know where to start" or "What would you suggest?").

Present initial story list with inferred type tags (`ui`, `technical`, or `content`). Infer the type from conversational context — if the story involves visual design, layout, or animation it's `ui`; if it's API routes, data, or infrastructure it's `technical`; if it's copy, tone, or onboarding flow it's `content`.

**Scope check (before presenting):** Before showing the story list, evaluate whether the story count matches the scope complexity. Count the concrete deliverables in the cycle goal and discussion — interactive features, distinct pages/views, API endpoints, data models, content surfaces. Apply these heuristics:

- If deliverables-per-story ratio exceeds ~3, the stories are probably too coarse
- If any single story covers more than one distinct concern (e.g., "build layout AND wire interactions AND add animations"), it should likely split
- If the project has existing completed cycles, compare story count against similar-scope cycles in `.craft/cycles/`

If the scope looks thin, include a **Scope check** note inline with the story list. If the count looks reasonable, present the list without commentary.

**When the check fires:**

> "Based on our discussion, I'm thinking these stories:
>
> 1. **[Story idea 1]** `ui` — [one line]
> 2. **[Story idea 2]** `ui` — [one line]
> 3. **[Story idea 3]** `ui` — [one line]
>
> **Scope check:** This cycle covers [N deliverables] but only has [M] stories. [Specific concern — e.g., "Story 2 alone covers 5 interactive commands with distinct animations - that could be 8+ chunks. Consider splitting into separate stories per command group."] You can proceed as-is or adjust.
>
> Does this capture the scope? (Check the type tags — correct any that are wrong.)"

**When the check doesn't fire:**

> "Based on our discussion, I'm thinking these stories:
>
> 1. **[Story idea 1]** `ui` — [one line]
> 2. **[Story idea 2]** `technical` — [one line]
> 3. **[Story idea 3]** `ui` — [one line]
>
> Does this capture the scope? (Check the type tags — correct any that are wrong.)"

Use **AskUserQuestion**:
```
question: "Does this capture the scope?"
header: "Stories"
options:
  - label: "Save these sparks"
    description: "The descriptions above are the sparks — write all story files now"
  - label: "Flesh out individually"
    description: "Go through each story to explore or refine the spark"
  - label: "Add another story"
    description: "I have more stories to include"
  - label: "Remove/combine some"
    description: "Some of these should be merged or dropped"
```

**If user selects "Other" or provides custom text:** Ask a clarifying AskUserQuestion before proceeding. Don't assume intent — confirm what they want to change.

**Important:** Don't proceed until user confirms the story list is complete.

**If "Save these sparks":** Jump to **Step 3-Fast** below.

**If "Flesh out individually":** Continue to Step 3 (per-story flow).

### Step 3-Fast: Batch Save Stories

The brainstorm already produced clear sparks. Write all story files at once using the descriptions from Step 2.

For each story in the confirmed list:
1. Use the story description from Step 2 as the spark
2. Use the confirmed type tag from Step 2 (`ui`, `technical`, or `content`) — write it into the `type` frontmatter field
3. Extract dependencies from the brainstorm discussion (e.g., "parser feeds editors" → Story 3 blocked by Story 1). If dependencies were discussed, capture them accurately. If a specific story's dependencies weren't discussed, leave the Dependencies section empty for the user to fill later — do NOT default to "none".
4. Write story file to `.craft/cycles/[cycle-name]/stories/[N]-[slug].md` with `status: planning`
5. Use the story template format from Step 3e

After writing all files, skip to **Step 5: Cycle Review**.

### Step 3: Capture Each Story (Spark Level Only)

**Cycle planning is high-level.** Capture the spark for each story — detailed planning happens later via `plan-chunks`.

**CRITICAL: Questions vs Answers**

Before capturing ANYTHING, distinguish:
- **Question from user:** "What do you recommend?" / "What should this do?" / "Any ideas?" → **ANSWER THE QUESTION FIRST.** Provide recommendations/options. Do NOT capture or lock anything. Wait for user to explicitly confirm.
- **Answer from user:** "Let's do X" / "The spark is Y" / "It should handle Z" → This is input to capture.

**Never lock or save based on a question.** Questions require answers, not actions.

For EACH story in the list:

> "Let's capture **Story 1: [Name]**"

**3a. Choose Your Path (Per Story)**

**If the story has `type: ui`**, prepend a recommendation:

> "This is a visual story — I'd recommend exploring directions before locking in the spark."

Use **AskUserQuestion**:
```
question: "How formed is the idea for [Story Name]?"
header: "Approach"
options:
  - label: "Let's get creative (recommended)"
    description: "Explore visual options, riff on the design together"
  - label: "I know what I want"
    description: "Capture the spark directly"
```

**If the story has `type: technical` or `type: content`**, present the options neutrally (no recommendation, no "(recommended)" suffix):

Use **AskUserQuestion**:
```
question: "How formed is the idea for [Story Name]?"
header: "Approach"
options:
  - label: "Let's get creative"
    description: "Explore options, riff on the design together"
  - label: "I know what I want"
    description: "Capture the spark directly"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their preferred approach.

**If "I know what I want":**
- Proceed directly to capturing the spark

**For either path, run content-spark first** (if the story spark has been captured).

⛔ **DO NOT analyze content assumptions directly. DO NOT invoke content-spark via the Skill tool (chain break - no return-to-caller).** Instead, Read and execute the logic inline:

```
Read "${CLAUDE_PLUGIN_ROOT}/commands/references/content-spark-inline.md"
Execute the phases described in that file against the current story.
```

**After content-spark logic completes:**
- If "I know what I want" was selected, continue to spark capture (Step 3b).
- If "Let's get creative" was selected, immediately continue to creative-spark below. Do NOT stop or ask the user again - they already chose the creative path.

**Running creative-spark inline:**

⛔ **DO NOT generate creative options from scratch. DO NOT invoke creative-spark via the Skill tool (chain break).** Instead, Read and execute the logic inline:

```
Read "${CLAUDE_PLUGIN_ROOT}/commands/references/creative-spark-inline.md"
Execute the steps described in that file against the current story.
```

The creative-spark reference file reads its own sub-references (output-formats.md, cross-domain-patterns.md, animation-integration.md) from `${CLAUDE_PLUGIN_ROOT}/skills/creative-spark/references/`. After creative-spark logic completes, capture the user's chosen direction as the spark.

**3b. Spark (What & Why)**
> "What's the spark? What problem does it solve?"

Capture 2-3 sentences describing the essence. Be an active partner:
- "Who specifically benefits from this?"
- "What's the 'wow' moment?"
- "Is this a must-have or nice-to-have?"

**3c. Rough Acceptance (Optional)**

If the user wants to capture high-level acceptance criteria:
- User can [action]
- [Behavior] when [condition]

**Note:** Detailed acceptance criteria come during `plan-chunks`, not here.

**3d. Dependencies**

> "Does this depend on other stories? Does anything depend on this?"

**Before writing dependencies, check for file-level overlap with sibling stories already in the cycle.** Read each sibling's spark and do a lightweight scan: what files will this story likely touch? What files will siblings likely touch? If two stories will modify the same files, they MUST declare a dependency - even if they touch different data fields within those files. Shared files means shared risk.

Present any detected overlap to the user:
> "This story and [sibling] both touch [files]. One should depend on the other so plan-chunks orders them correctly. Which goes first?"

**If no sibling overlap detected:** Proceed normally - dependencies may still exist for other reasons.

**If dependencies weren't discussed and no overlap detected:** Leave the Dependencies section empty for the user to fill later - do NOT default to "none". An empty section means "not yet determined." `Blocked by: none` means "I checked and there are no dependencies."

Capture the dependency chain for story ordering.

**3e. Save Story**

Write story file to `.craft/cycles/[cycle-name]/stories/[N]-[slug].md` with `status: planning`.

```markdown
---
name: [slug]
title: "[Title]"
type: [ui/technical/content]
status: planning
priority: [high/medium/low]
created: [date]
updated: [date]
cycle: [cycle-name]
story_number: [N]
alignment: pending
chunks_total: 0
chunks_complete: 0
current_chunk: 0
---

# Story: [Title]

## Spark
[2-3 sentences from discussion]

## Dependencies
**Blocked by:** [stories this depends on]
**Blocks:** [stories that depend on this]

## Content Direction
<!-- Captured during content-spark - assumptions surfaced and resolved -->

## Acceptance
[Rough criteria if captured, otherwise empty for plan-chunks to fill]

## Chunks
<!-- Detailed chunks added via plan-chunks -->
```

**Note:** Stories are saved with `status: planning`. They become `status: ready` after `plan-chunks` is run.

### Step 4: Repeat for All Stories

Go through Step 3 for each story. Each story is saved immediately with `status: planning`.

> "Stories captured: 2/5 ✓
>
> Ready for **Story 3: [Name]**?"

**If context compacts:** Read existing story files from `.craft/cycles/[cycle-name]/stories/`, resume with next unwritten story.

### Step 5: Cycle Review

**Print this status line before composing the review:**

> *Compiling the cycle review — this can take 30-90 seconds on complex cycles...*

All stories are now saved. Review the cycle as a whole:

> "**Cycle: [Name]** — Story List
>
> **Goal:** [Goal]
>
> ---
>
> **Story 1: [Name]** — [spark summary]
> **Story 2: [Name]** — [spark summary]
> **Story 3: [Name]** — [spark summary]
>
> **Dependencies:**
> - Story 2 depends on Story 1
> - Story 3 can run parallel
>
> ---
>
> **Total:** [N] stories (all need plan-chunks before implementation)
>
> Is this the right scope and order?"

Use **AskUserQuestion**:
```
question: "Is this the right scope and order?"
header: "Review"
options:
  - label: "Yes, finalize the cycle"
    description: "Lock in the story list — you can still run creative-spark and plan-chunks on each story"
  - label: "Add another story"
    description: "I have more to include"
  - label: "Reorder stories"
    description: "Change the implementation order"
  - label: "Revisit a spark"
    description: "Refine one of the story descriptions"
```

**If user selects "Other" or provides custom text:** Ask a clarifying AskUserQuestion to understand specifically what they want to change before making modifications.

**Note:** Stories have `status: planning`. Run `plan-chunks` on each before starting implementation.

### Step 6: Finalize Cycle

Stories are already saved. Update the cycle metadata created in Step 1 with final details from discussion.

**6a. Cycle structure already exists (created by `create-cycle.sh` in Step 1):**
```
.craft/cycles/[N]-[name]/
├── cycle.yaml          ✓ created in Step 1 — update now with final goals/notes
├── .state              ✓ created in Step 1 — no changes needed
└── stories/            ← Already populated
    ├── 1-[story].md    ✓ saved in Step 3
    ├── 2-[story].md    ✓ saved in Step 3
    └── ...
```

**Note:** Learnings are project-wide at `.craft/.learnings.yaml`, not per-cycle.

**6b. Update cycle.yaml** — use targeted edits on the existing file (created by `create-cycle.sh` in Step 1). **NEVER rewrite cycle.yaml from scratch** — that causes YAML formatting bugs (null goals, unquoted titles).

Use `sed` for simple field updates:
```bash
cycle_yaml="[cycle_dir]/cycle.yaml"
sed -i.bak "s/^status:.*/status: ready/" "$cycle_yaml"
sed -i.bak "s/^updated:.*/updated: $(date +%Y-%m-%d)/" "$cycle_yaml"
sed -i.bak "s/^focus:.*/focus: [Primary focus area]/" "$cycle_yaml"
rm -f "$cycle_yaml.bak"
```

For goals and notes, use the Edit tool to replace the existing `goals:` and `notes:` sections.

**Goals are outcomes, not story summaries.** Each goal should be a state that will be TRUE when the cycle completes - something you could verify. Good: "Failures feed back into learnings pipeline instead of being discarded." Bad: "Implement failure tracking story." If you find yourself restating story sparks as goals, stop - that's the wrong level.

**Before writing goals, check what exists:** Read the current `goals:` value from cycle.yaml.

- **If goals were discussed this session** (full creation path, Step 1): Write the outcome-oriented goals from that conversation.
- **If goals were NOT discussed** (Detailing Mode, pre-planned stories): Ask the user with AskUserQuestion: "What outcomes should this cycle achieve? (Or I can leave goals as TBD for now.)" Then write their answer, or leave the existing TBD value untouched.
- **Never auto-fill goals by summarizing story sparks.** That produces generic descriptions that add no value to plan-chunks agents. TBD is better than watered-down spark rewrites.

```yaml
goals:
  - [Outcome 1 - what will be true when done]
  - [Outcome 2 - what will be true when done]

notes: |
  [All locked decisions from planning]
```

**IMPORTANT:** Every goal must be a non-empty string. Never leave a trailing `- ` with no value — Craftsman's Zod parser will reject it. If goals are unknown, keep the existing `- TBD` value rather than inventing content.

**Note:** No stories array in cycle.yaml. Stories are discovered by scanning the `stories/` directory.

**6d. Stories already created in Step 3 with `status: planning`.**

Story files look like:

```markdown
---
name: [slug]
title: "[Full title]"
type: [ui/technical/content]
status: planning
priority: [high/medium/low]
created: [date]
cycle: [cycle-name]
story_number: [N]
alignment: pending
chunks_total: 0
chunks_complete: 0
current_chunk: 0
---

# Story: [Title]

## Spark
[2-3 sentence essence from discussion]

## Dependencies
**Blocked by:** [list or "none"]
**Blocks:** [list or "none"]

## Content Direction
<!-- Captured during content-spark - assumptions surfaced and resolved -->

## Visual Direction
<!-- For type: ui stories only - captured during creative-spark -->
**Vibe:** [Name from creative-spark, e.g., "Friendly Energy"]
**Feel:** [2-3 words, e.g., "Clean, warm, approachable"]
**Inspiration:** [Reference sites/patterns]
**Key tokens:** [Token names this story will use]
**Motion:** [Animation approach from creative-spark]

<!-- Leave empty for non-UI stories -->

## Wireframe
<!-- For type: ui stories - capture the chosen layout as ASCII art -->
<!-- This preserves the visual context for plan-chunks -->

```
[Paste the chosen wireframe option here]
```

<!-- Leave empty for non-UI stories -->

## Acceptance
<!-- Detailed criteria added via plan-chunks -->

## Chunks
<!-- Detailed chunks added via plan-chunks -->

## Notes
[Any additional context, open questions, references]
```

### Step 7: Visual Cohesion Review (Optional)

Check if the cycle has UI stories that would benefit from a cohesion review:

Use **Grep** with pattern `^type: ui`, path `.craft/cycles/[cycle]/stories/`, glob `*.md`, output_mode `files_with_matches` → count → `ui_stories`.

**If ui_stories > 1:**

> "This cycle has [N] stories with visual direction. Want to review them for cohesion before implementation?"

Use **AskUserQuestion**:
```
question: "Review visual cohesion across stories?"
header: "Design"
options:
  - label: "Yes, let's review"
    description: "Ensure consistent visual language across all UI stories"
  - label: "Skip for now"
    description: "Move forward, review later if needed"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their intent.

**If "Yes, let's review":**

⛔ **DO NOT review visual cohesion directly. You MUST invoke the skill:**

```
Skill tool:
  skill: "craft:design-vibe"
  args: "[cycle directory path] — Cycle '[cycle name]' has [N] UI stories with visual direction.
  CYCLE: [cycle-dir-name]
  STORY_VIBES: [story1: vibe1, story2: vibe2, ...]
  TOKEN_FILES: [.craft/design/tokens.yaml]"
```

Include the cycle path, which stories have visual direction, and their vibe names. This gives design-vibe targeted context for the cohesion review.

This hands off to `design-vibe` which reviews visual direction across all stories, identifies inconsistencies, and proposes unified design tokens. Do NOT replicate visual cohesion analysis inline.

**If "Skip for now" or no UI stories:**
- Continue to Step 8

### Step 8: Confirm Cycle

> "**Cycle: [Name]** created!
>
> - [N] stories captured (all `status: planning`)
> - Stories need `plan-chunks` before implementation
>
> What's next?"

Use **AskUserQuestion** (options vary based on story count):

**If N > 1 (multiple stories):**
```
question: "What's next?"
header: "Next step"
options:
  - label: "Plan all [N] stories"
    description: "Reads dependency graph, plans chains sequentially, parallelizes independent stories"
  - label: "Plan a specific story"
    description: "Run plan-chunks on one story interactively"
  - label: "Review visual cohesion"
    description: "Run design-vibe to ensure consistent visual language"
  - label: "Keep in planning"
    description: "I'll come back to plan stories later"
```

**If N = 1 (single story):**
```
question: "What's next?"
header: "Next step"
options:
  - label: "Explore a story creatively"
    description: "Run creative-spark on a story to explore design options"
  - label: "Plan a story now"
    description: "Run plan-chunks on a story to make it implementation-ready"
  - label: "Review visual cohesion"
    description: "Run design-vibe to ensure consistent visual language"
  - label: "Keep in planning"
    description: "I'll come back to plan stories later"
```

**If user selects "Other" or provides custom text:** Ask a clarifying AskUserQuestion to understand their intent before proceeding.

**Note:** Cycle stays in `planning` status until stories are planned and you're ready to implement.

**If user wants to explore a story creatively:**

⛔ **DO NOT generate creative options directly. You MUST invoke the skill:**

```
Skill tool:
  skill: "craft:creative-spark"
  args: "[story name] — [context from story file]
  STORY: [story-name]
  CYCLE: [cycle-dir-name]
  CYCLE_GOAL: [cycle goal]"
```

This hands off to `creative-spark` which generates options, wireframes, and visual direction. After the user picks a direction, update the story file with the chosen spark and visual direction.

**If user wants to review visual cohesion:**

⛔ **DO NOT review visual cohesion directly. You MUST invoke the skill:**

```
Skill tool:
  skill: "craft:design-vibe"
  args: "[cycle directory path] — Cycle '[cycle name]' has [N] UI stories.
  CYCLE: [cycle-dir-name]
  STORY_VIBES: [story1: vibe1, story2: vibe2, ...]
  TOKEN_FILES: [.craft/design/tokens.yaml]"
```

This hands off to `design-vibe` which reviews visual cohesion. Do NOT replicate this work inline.

**Before planning any story**, check `alignment` in frontmatter. If `alignment: pending`, run the alignment check first. Read `commands/references/alignment-check.md` and follow the loop for each story before invoking plan-chunks. The alignment check surfaces product questions from codebase investigation - it must complete before chunking begins.

**If user wants to plan all stories:**

⛔ **DO NOT plan chunks directly. You MUST invoke the skill:**

```
Skill tool:
  skill: "craft:plan-chunks"
  args: "DIRECTION_CONFIRMED: true
  MODE: batch
  CYCLE: [cycle-dir-name]
  CYCLE_GOAL: [cycle goal]"
```

This hands off to `plan-chunks` in batch mode, which reads the dependency graph from story files, plans dependency chains sequentially (level by level), and parallelizes independent stories within each level. The skill handles agent orchestration, batch triage, per-story approval, and story file writing. Do NOT replicate any of this inline.

**If user wants to plan a specific story:**

⛔ **DO NOT plan chunks or break down implementation directly. You MUST invoke the skill:**

```
Skill tool:
  skill: "craft:plan-chunks"
  args: "[story file path] — Part of cycle '[cycle name]'.
  DIRECTION_CONFIRMED: true
  STORY: [story-name]
  CYCLE: [cycle-dir-name]
  CYCLE_GOAL: [cycle goal]
  SIBLINGS: [story1, story2, story3]
  DECISIONS: [key decisions from planning discussion]"
```

Include the story path, cycle context, sibling stories, and any relevant discussion context. This gives plan-chunks the full cycle picture for coordination.

This hands off to `plan-chunks` which produces detailed chunk-by-chunk implementation plans. Do NOT replicate planning inline. Story becomes `status: ready` when chunks are complete.

**After plan-chunks returns:** Check if all stories in the cycle are now `status: ready`. If so, clear PLANNING_CYCLE — the cycle is implementation-ready:

Use **Glob** with pattern `.craft/cycles/[cycle]/stories/*.md` → count → `stories_total`.

Use **Grep** with pattern `^status: ready`, path `.craft/cycles/[cycle]/stories/`, glob `*.md`, output_mode `files_with_matches` → count → `stories_ready`.

If `stories_total > 0` and `stories_total == stories_ready`:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh PLANNING_CYCLE ""
```

**If kept for later:**
- Clear PLANNING_CYCLE:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh PLANNING_CYCLE ""
```
- Cycle stays `status: planning` until activated

---

