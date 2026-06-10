---
name: craft:story-new
description: "Create a new story. It lands in the backlog until assigned to a cycle."
---

# Story New

Create a new story from an idea. Stories can be quick sparks (just the idea), creatively explored, or fully designed — you choose how deep to go.

## Flow

### Step 1: Capture the Idea

> "What's the story about?"
>
> [User describes the idea]

**CRITICAL: Questions vs Answers**

Before capturing ANYTHING, distinguish:
- **Question from user:** "What do you recommend?" / "What should this do?" / "Any ideas?" → **ANSWER THE QUESTION FIRST.** Provide recommendations/options. Do NOT capture or lock anything. Wait for user to explicitly confirm.
- **Answer from user:** "Let's do X" / "The spark is Y" / "It should handle Z" → This is input to capture.

**Never lock or save based on a question.** Questions require answers, not actions.

### Step 2: Clarify (if needed)

If the idea is vague or could mean multiple things, use **AskUserQuestion** to clarify.

**For UI/layout changes:**
```
question: "What aspect do you want to change?"
header: "Focus"
options:
  - label: "Rearrange sections"
    description: "Move things around, change order"
  - label: "Responsive behavior"
    description: "How it works on different screen sizes"
  - label: "Add/remove elements"
    description: "New components or removing existing ones"
  - label: "Overall structure"
    description: "Sidebar vs stacked, major layout shift"
```

**For feature work:**
```
question: "What's the core of this change?"
header: "Focus"
options:
  - label: "New functionality"
    description: "Something that doesn't exist yet"
  - label: "Improve existing"
    description: "Make current feature better"
  - label: "Fix a problem"
    description: "Something's broken or confusing"
  - label: "Performance/technical"
    description: "Speed, reliability, code quality"
```

**If user provides custom text:** Use their clarification and proceed to Step 2.5.

**If idea is already clear:** Skip directly to Step 2.5.

### Step 2.5: Planning Source Detection

Before asking "How deep do you want to go?" (Step 3), check whether this project has planning docs that the story could be built from.

**Detection logic:**

Use **Bash**:

```bash
# Glob planning files and check for concept/initiative frontmatter
find "$CRAFT_PROJECT_ROOT/.craft/planning" -maxdepth 3 -type f -name "*.md" 2>/dev/null \
  | xargs grep -l "^concept:\|^initiative:" 2>/dev/null \
  | head -20
```

**If zero matches:** skip this step entirely and continue to Step 3. No AskUserQuestion shown. Users who have never used craft planning see zero behavior change.

**If one or more matches:** present the choice via **AskUserQuestion**:

```
question: "Is this story from planning, or freeform? (I see [N] concepts in .craft/planning/.)"
header: "Source"
options:
  - label: "From planning"
    description: "Build this story from existing planning docs. I'll walk the concept(s) and produce a thorough story with Reference Materials."
  - label: "Freeform"
    description: "Build a fresh story without planning context. Continue with the standard flow."
```

**If "From planning":**

⛔ **DO NOT invoke story-from-planning via the Skill tool (chain break - no return-to-caller).** Instead, Read and execute the logic inline:

```
Read "${CLAUDE_PLUGIN_ROOT}/commands/references/story-from-planning.md"
Execute the phases (1, 2, 3a, 3b, 4, 5, 6, 7) described in that file against the planning corpus.
```

The reference file owns the entire planning-to-story transformation: concept selection, Explore-agent extraction, gap-fill, file write with all canonical sections including `## Reference Materials`, and mandatory forward-linking to active.md + consumed concepts. When it completes Phase 7, the parent flow is DONE.

**Do NOT continue to Step 3 (Choose Your Path) or Step 3b (Content Check)** after the From planning branch completes. The story file is fully written with `alignment: pending` - the existing alignment-check fires when `/craft:story-implement` runs later.

**If "Freeform":** continue to Step 3 (Choose Your Path) unchanged.

### Step 3: Choose Your Path

Use **AskUserQuestion**:
```
question: "How deep do you want to go?"
header: "Depth"
options:
  - label: "Just a spark"
    description: "Save the idea, flesh it out later"
  - label: "Let's get creative"
    description: "Explore options, riff on the design together"
  - label: "I know what I want"
    description: "Skip to planning chunks, let's build it"
```

**If "Just a spark"** → Skip to Step 10 (Save & Place) — asks priority, writes minimal file, offers placement

**If "Let's get creative"** → Continue to Step 3b (Content Check), then Step 4 (with creative-spark)

**If "I know what I want"** → Continue to Step 3b (Content Check), then Step 7 (Quick Decisions)

---

### Step 3b: Content Check

Before exploring HOW (creative or smart), check if the content direction is clear.

**First, write the story file** so content-spark has something to read. Create a minimal story file at `.craft/backlog/[story-name].md` with the frontmatter and Spark section from Step 1-2. Use `status: planning`.

Then run content-spark inline:

⛔ **DO NOT analyze content assumptions directly. DO NOT invoke content-spark via the Skill tool (chain break - no return-to-caller).** Instead, Read and execute the logic inline:

```
Read "${CLAUDE_PLUGIN_ROOT}/commands/references/content-spark-inline.md"
Execute the phases described in that file against the current story.
```

This surfaces content assumptions and writes `## Content Direction` and `## Risk Tags` to the story file.

After `content-spark` completes:
- **If "Let's get creative"** was chosen → Continue to Step 4 (with creative-spark)
- **If "I know what I want"** was chosen → Continue to Step 7 (Quick Decisions)

**If "Just a spark"** was chosen in Step 3: content-spark does NOT run. The story is saved with just the spark — content direction can be added later.

---

## Path A: With Creative-Spark

### Step 4: Explore Options

⛔ **DO NOT generate creative options from scratch. DO NOT invoke creative-spark via the Skill tool (chain break - no return-to-caller).** Instead, Read and execute the logic inline:

```
Read "${CLAUDE_PLUGIN_ROOT}/commands/references/creative-spark-inline.md"
Execute the steps described in that file against the current story.
```

The creative-spark reference reads its own sub-references (output-formats.md, cross-domain-patterns.md, animation-integration.md) from `${CLAUDE_PLUGIN_ROOT}/skills/creative-spark/references/`.

After creative-spark logic completes, it will have presented options and captured the user's choice.

### UI Placement Principle

For UI stories, apply UX conventions with judgment:

- **Clear convention** (filters above a list, destructive action = confirmation modal, primary action top-right, form fields in logical groups) → decide and state your reasoning. Don't ask.
- **Best practice exists but context matters** (sidebar vs drawer for settings, card grid vs table for this data, inline editing vs modal) → use AskUserQuestion with your recommendation first and why it fits this case.

Think like a senior designer: lead with expertise, explain your reasoning, and only ask when the choice genuinely could go either way.

### Step 5: Capture Design Decisions

When design choices arise, use **AskUserQuestion** to let the user choose. Store structured decisions:

**Layout decisions:**
```
question: "How should [content] be arranged?"
options:
  - label: "List" — Vertical stack, scannable
  - label: "Cards" — Grid of cards, visual
  - label: "Table" — Rows/columns, data-heavy
  - label: "Tabs" — Grouped sections
```

**Component decisions:**
```
question: "How should [feature] appear?"
options:
  - label: "Modal" — Overlay, focused action
  - label: "Inline" — Embedded in page
  - label: "Drawer" — Slide-in panel
  - label: "Dropdown" — Compact, on-demand
```

**Density decisions:**
```
question: "How much content density?"
options:
  - label: "Compact" — Dense, power users
  - label: "Comfortable" — Balanced (default)
  - label: "Spacious" — Breathing room, visual
```

**Visibility decisions:**
```
question: "How much detail to show?"
options:
  - label: "Minimal" — Essential only
  - label: "Rich" — Key details visible
  - label: "Full" — Everything shown
```

**Record each decision in this format:**
```markdown
### [Decision Name]
**Type:** layout | component | density | visibility
**Choice:** [key]
```

Valid keys:
- **layout:** list, cards, table, grid, bento, sidebar, topnav, tabs, gallery
- **component:** modal, inline, drawer, dropdown, pills, tabs, accordion, toggle, readonly
- **density:** compact, comfortable, spacious
- **visibility:** minimal, rich, full

> Tokens Studio renders these as a visual showcase. User changes decisions by asking — not through UI.

### Step 6: Continue or Save?

Use **AskUserQuestion**:
```
question: "We've got a solid creative direction. Want to keep designing or save what we have?"
header: "Next"
options:
  - label: "Save what we have"
    description: "Capture the creative direction, flesh out details later"
  - label: "Keep designing"
    description: "Define acceptance criteria, scope, constraints"
```

**If "Save what we have"** → Skip to Step 10 (Save & Place) — writes story with creative context (visual direction, wireframe, decisions)
**If "Keep designing"** → Continue to Step 8 (Full Design)

---

## Path B: Skip Creative-Spark

User has a formed idea — skip creative exploration, go straight to planning.

### Step 7: Quick Decisions (Skip Creative-Spark)

> "Got it. A few quick decisions before we plan:"

Ask only essential questions:
- Key technical approach (if not obvious)
- Any design constraints?
- Target scope (MVP vs full)?

**Record decisions in the story file** using the same format as Step 5:
```markdown
### [Decision Name]
**Type:** layout | component | density | visibility
**Choice:** [key]
```

These are **story-scoped decisions** — they describe what THIS story will do, not project-wide standards.

**Only invoke `lock-decision`** if the user explicitly establishes a project-wide pattern — e.g., "from now on all forms should use this approach" or "this should be the standard for all dropdowns." Most story creation decisions are story-scoped and do NOT need locking.

### Step 7b: Continue or Save?

Use **AskUserQuestion**:
```
question: "Decisions captured. Want to keep designing or save what we have?"
header: "Next"
options:
  - label: "Save what we have"
    description: "Capture decisions, flesh out details later"
  - label: "Keep designing"
    description: "Define acceptance criteria, scope, constraints"
  - label: "Let's get creative"
    description: "Explore options, riff on the design"
```

**If "Save what we have"** → Skip to Step 10 (Save & Place) — writes story with decisions captured
**If "Keep designing"** → Continue to Step 8 (Full Design)
**If "Let's get creative"** → Go to Step 4 (invoke creative-spark)

---

## Full Design (Optional - for those who chose "Keep designing")

### Step 8: Codebase Alignment Check (REQUIRED)

Before defining acceptance criteria or planning chunks, investigate the codebase where this work will land and surface every product question that only the user can answer.

⛔ **DO NOT skip this step.** Read `commands/references/alignment-check.md` and follow the alignment loop.

**Summary:** Spawn an Explore agent to investigate the codebase. Process findings. Surface genuine product questions via AskUserQuestion. If answers expand scope, use SendMessage to the same agent for follow-up investigation. Loop until zero unasked product questions remain. Then record the `## Alignment` receipt in the story and set `alignment: complete` in frontmatter.

After the alignment loop completes, continue to Step 9.

### Step 9: Define Acceptance Criteria

> "What defines 'done' for this story?"
>
> Based on our discussion, I'd suggest:
> - [ ] Given [context], when [action], then [outcome]
> - [ ] Given [context], when [action], then [outcome]
> - [ ] Given [context], when [action], then [outcome]
>
> Add or adjust any criteria?

### Step 9b: Define Scope Boundaries

> "Let's be explicit about scope."
>
> **Included** (what we're building):
> - [Feature/change 1]
> - [Feature/change 2]
>
> **Excluded** (explicitly NOT doing):
> - [Thing we won't touch]
> - [Out of scope item]
>
> Does this capture the boundaries?

### Step 9c: Identify Preserve List

> "What must remain working? These are DO NOT TOUCH items."
>
> Based on the codebase, I'd suggest preserving:
> - [Existing feature that must keep working]
> - [Related functionality that could break]
> - [Integration point that must stay intact]
>
> Anything else that must remain untouched?

### Step 9d: Surface Hardest Constraint (REQUIRED)

> "What's the biggest risk or challenge here?"
>
> I see: [Identified constraint — technical challenge, dependency, complexity]
>
> Is that the main concern, or is there something else?

### Step 9e: Map Dependencies

> "Any dependencies to track?"
>
> **Blocked by** (must complete first):
> - [Other story or feature this depends on]
>
> **Blocks** (waiting on this):
> - [Stories or features that need this done first]
>
> If none, that's fine — this story can run independently.

### Step 10: Save & Place

**CRITICAL: Write the story file BEFORE invoking plan-chunks.** This ensures all creative work (wireframes, visual direction, decisions) is captured and available for planning.

**Note:** If content-spark already ran (Step 3b), the story file already exists. Update it with any new sections from the creative/smart path rather than creating from scratch.

**Ask for priority** (if not already captured):

Use **AskUserQuestion** (from Priority Levels section below).

**Create the story file.** Only include sections that have content from the discussion. Omit empty sections to keep the file clean.

**Infer the story type** from the conversation context and include it in the save confirmation:

> "Saving **[Story Name]** as a `[ui/technical/content]` story with [priority] priority."

If the user corrects the type, adjust before writing. The `type` field drives creative tool recommendations during planning - `ui` stories get creative-spark prompts, all stories get content-spark prompts.

**CRITICAL for UI stories that went through creative-spark:** The Visual Direction block (Vibe, Feel, Inspiration, Key tokens, Motion) and Wireframe from the chosen option MUST be included in the story file. These details are the entire point of creative-spark — without them, all creative work is lost and plan-chunks has no visual context to work from.

**Likely Files scan (required for all stories except "Just a spark"):**

Before writing the story file, scan the codebase to identify files this story will likely touch. This powers the dependency verification gate in batch planning - without it, `Blocked by:` declarations can't be trusted.

1. Read the spark text and any scope/decisions captured so far
2. Extract key terms: file names, component names, domain keywords, feature areas
3. Use **Grep** and **Glob** to find matching files in the codebase (grep for domain keywords, glob for file patterns)
4. Categorize each file: `modify` (will change), `create` (new file), `read-only` (reference only)
5. Write the `## Likely Files` section with today's date

**Keep it fast** - this is grep/glob work, not deep analysis. 5-15 files max. Only `modify` and `create` files matter for dependency detection.

**Skip for "Just a spark"** - minimal stories don't have enough context for a useful scan. The scan runs when the story gets fleshed out later.

Target path: `.craft/backlog/[story-name].md`

**Frontmatter (always required):**
```markdown
---
name: [kebab-case-name]
title: "[Full title]"
type: [ui/technical/content]
status: planning
created: [date]
updated: [date]
priority: [priority]
alignment: pending
chunks_total: 0
chunks_complete: 0
current_chunk: 0
---
```

**Spark section (always required):**
```markdown
# Story: [Title]

## Spark
[2-3 sentences capturing the idea]
```

**Include these sections ONLY if content was captured during the discussion:**

```markdown
## Scope
**Included:**
- [What we're building]
**Excluded:**
- [What we're NOT doing]

## Preserve
- [Existing feature that must keep working]

## Hardest Constraint
[The biggest risk or challenge]

## Technical Concerns
- [Specific concern about feasibility, performance, or architecture]

## Recommendations
- [Ways to reduce risk or complexity]

## Dependencies
**Blocked by:** [None, or list]
**Blocks:** [None, or list]

## Likely Files
_Scanned: [YYYY-MM-DD]_
- `path/to/file.ext` - modify (reason)
- `path/to/other.ext` - create (new file for feature)
- `path/to/ref.ext` - read-only (reference only)
<!-- Action tags: modify, create, read-only. Only modify/create count for dependency overlap detection. -->

## Decisions
<!-- Typed decisions from lock-decision skill - structured for Tokens Studio UI -->
### [Decision Name]
**Type:** layout | component | density | visibility
**Choice:** [key from valid keys]
<!-- Valid keys:
- layout: list, cards, table, grid, bento, sidebar, topnav, tabs, gallery
- component: modal, inline, drawer, dropdown, pills, tabs, accordion, toggle, readonly
- density: compact, comfortable, spacious
- visibility: minimal, rich, full
-->

## Content Direction
<!-- Captured during content-spark — assumptions surfaced and resolved -->

## Visual Direction
<!-- For type: ui stories only - captured during creative-spark -->
**Vibe:** [Name from creative-spark]
**Feel:** [2-3 words]
**Inspiration:** [Reference sites/patterns]
**Key tokens:** [Token names]
**Motion:** [Animation spec]

## Wireframe
```
[Chosen wireframe ASCII art]
```

## Acceptance
[Given/When/Then criteria]

## Notes
[Any additional context]
```

**Examples by depth:**

- **Spark only** (from "Just a spark"): Frontmatter + Spark. That's it. No Likely Files scan (not enough context).
- **Creative direction** (from Step 6 "Save what we have"): Frontmatter + Spark + Likely Files + Visual Direction + Wireframe + Decisions (if captured).
- **Skip Creative-Spark path** (from Step 7b "Save what we have"): Frontmatter + Spark + Likely Files + Decisions.
- **Fully designed** (from Step 8 flow): All sections that have content, including Likely Files.

---

### Step 11: Plan Chunks (Optional)

Now that the story file exists with all context, offer to plan chunks.

Use **AskUserQuestion**:
```
question: "Do you want to plan implementation details now?"
options:
  - label: "Yes, plan chunks now"
    description: "Get full implementation details before saving"
  - label: "Explore creatively first"
    description: "Riff on the approach before planning chunks"
  - label: "Later, just save the spark"
    description: "Save to backlog, plan before implementing"
```

**If "Yes, plan chunks now":**

⛔ **DO NOT plan chunks or break down implementation directly. You MUST invoke the skill:**

```
Skill tool:
  skill: "craft:plan-chunks"
  args: "[story file path] — Story covers [brief spark summary].
  STORY: [story-name]
  DECISIONS: [key decisions from discussion]
  DEPTH: [creative/smart/spark]"
```

Include the story file path AND a brief summary of what was discussed — decisions, constraints, creative direction chosen. This gives plan-chunks conversational context that may not be fully captured in the story file yet.

This hands off to `plan-chunks` which reads the story file (including wireframe, visual direction, decisions) and produces detailed chunk-by-chunk implementation plans. Do NOT replicate this work inline.

When complete, update story: `status: ready`, add chunks, set `chunks_total`

**If "Explore creatively first":**

⛔ **DO NOT generate creative options from scratch. DO NOT invoke creative-spark via the Skill tool (chain break).** Instead, Read and execute inline:

```
Read "${CLAUDE_PLUGIN_ROOT}/commands/references/creative-spark-inline.md"
Execute the steps described in that file against the current story.
```

After creative-spark logic completes, re-present Step 11 to offer plan-chunks.

**If "Later, just save the spark":**
- Story stays with `status: planning`
- User must run `plan-chunks` before implementing
- Proceed to Step 12

---

### Step 12: Place Story

Use **AskUserQuestion**:
```
question: "Where should this story go?"
options:
  - label: "Save to backlog"
    description: "Plan and implement later"
  - label: "Add to current cycle"
    description: "Assign to active cycle"
  - label: "Create new cycle"
    description: "Start a new cycle with this story"
```

**If adding to cycle:**
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/move-story.sh .craft/backlog/[story].md [cycle-name]
```

## Story Naming

- Use kebab-case for file names: `update-login-modal.md`
- Keep titles clear and action-oriented
- Examples:
  - "Add password requirements to login"
  - "Refactor API error handling"
  - "Build dashboard widgets"

## Priority Levels

During creation, set priority:

> "How important is this?"

Use **AskUserQuestion**:
```
question: "How important is this story?"
header: "Priority"
options:
  - label: "Urgent"
    description: "Need it ASAP"
  - label: "High"
    description: "Important, soon"
  - label: "Medium (default)"
    description: "Normal priority"
  - label: "Low"
    description: "Nice to have"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand the priority level.

## Batch Creation

If user has multiple ideas:

> "I'll create stories for each. Let's design them one at a time:
>
> **Story 1: [Name]**
> [Go through the creative-spark flow]
>
> **Story 2: [Name]**
> [Go through the creative-spark flow]
>
> All stories created and ready."

Use **AskUserQuestion**:
```
question: "Assign any of these to the current cycle?"
header: "Assign"
multiSelect: true
options:
  - label: "[Story 1 name]"
    description: "[priority]"
  - label: "[Story 2 name]"
    description: "[priority]"
  - label: "Keep all in backlog"
    description: "Assign later"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand which stories they want to assign.

## Remember

- Stories are first-class — create anytime
- **plan-chunks is optional during creation** — user chooses via AskUserQuestion
- Stories without chunks: `status: planning` (need plan-chunks before implementing)
- Stories with chunks: `status: ready` (can be implemented)
- **Story path:** `.craft/backlog/[slug].md` (default home)
- User controls placement — can move to cycle via `/craft:cycle-assign`
