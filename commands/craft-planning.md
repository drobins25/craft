---
name: craft:planning
description: "Feature roadmap and planning. Manage initiatives, concepts, open questions, and story creation from planning."
aliases:
  - planning
---

# Craft Planning

You are managing the project's **feature roadmap** - the strategic planning layer that sits above cycles and stories. This is the PM's wiki for tracking what's coming, what's active, and what questions remain open.

## Project Root

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`.
Set `PLANNING` to `$PROJECT/.craft/planning`.

## Entry Flow

When `/craft:planning` is invoked, check state and route.

### Step 1: Check if planning exists

Use **Glob** to check if `$PLANNING/active.md` exists.

**If NOT found** -> Go to **Setup Flow** (Step 2).
**If found** -> Go to **Active Flow** (Step 3).

### Step 2: Setup Flow (first time)

No planning folder exists yet. Help the user create one.

> "No planning folder found. Let's set up your roadmap."

Use **AskUserQuestion**:
```
question: "How would you like to start?"
header: "Setup"
options:
  - label: "Generate from input (Recommended)"
    description: "Feed me a transcript, doc, or spec and I'll extract concepts for your review"
  - label: "Start from scratch"
    description: "Describe what you're building and I'll structure it"
  - label: "Import from existing backlog"
    description: "Turn existing backlog stories into a planning roadmap"
```

**If "Generate from input"** -> Go to **Add From Input** (Step 5).
**If "Start from scratch"** -> Go to **Conversational Setup** (Step 6).
**If "Import from existing backlog"** -> Go to **Import Flow** (Step 7).

After setup completes, create the folder structure:

```bash
mkdir -p "$PLANNING"
```

Write `README.md` and `active.md` using templates from `${CLAUDE_PLUGIN_ROOT}/templates/planning/`. Replace template variables with actual values.

### Step 3: Active Flow (planning exists)

Read the current state and suggest the most useful next action.

Use **Read** to read `$PLANNING/active.md`. Extract `last_updated` from frontmatter. Extract the Focus section (content between `## Focus` and the next `---` divider).

Use **Read** to read `$PLANNING/README.md`. Parse the Roadmap table to get concept names, statuses, and files.

**Assess what's most useful:**

1. **Stale active.md** (last_updated >7 days) -> Suggest reviewing and updating
2. **Open questions exist** -> Mention count, offer to review
3. **Concepts with status `open` and no blockers** -> Suggest fleshing out or creating stories
4. **Concepts with status `planned` and all stories complete** -> Prompt completion confirmation
5. **Nothing urgent** -> Show full roadmap and offer menu

Present the assessment and menu:

> "[Focus section content]"
>
> [Assessment: e.g., "4 open questions across 3 concepts. 'CDB Mapping' is ready for stories."]

Use **AskUserQuestion**:
```
question: "What would you like to do?"
header: "Planning"
options:
  - label: "[Most useful action] (Recommended)"
    description: "[context-specific description]"
  - label: "Add concept or input"
    description: "Add a new concept or feed new input to existing ones"
  - label: "Review open questions"
    description: "See all unanswered questions across concepts"
  - label: "Create stories from a concept"
    description: "Turn a mature concept into cycle stories"
```

Route based on selection -> the flows below.

### Step 4: Update active.md

**Call this after any write to a planning file.** This keeps `last_updated` current automatically.

```
Read $PLANNING/active.md
Update `last_updated:` in frontmatter to today's date (YYYY-MM-DD)
Write $PLANNING/active.md
```

If the current focus has changed (e.g., a new concept was activated, a concept was completed), also update the `## Focus` section and `current_concept:` in frontmatter.

---

## Flows

### Step 5: Add From Input

The user provides a transcript, doc, spec, or other input. Craft extracts candidate concepts and confirms with the user before writing anything.

**5a. Gather input**

Use **AskUserQuestion**:
```
question: "What input should I work from?"
header: "Input"
options:
  - label: "Paste or describe now"
    description: "I'll type or paste the content in my next message"
  - label: "Read a file"
    description: "Point me to a file path to read"
  - label: "Read from conversation"
    description: "Use what we've discussed in this session"
```

If file path provided, use **Read** to read it. If the file is a transcript, treat it as raw discovery material.

**5b. Extract candidate concepts**

Analyze the input and identify distinct features, initiatives, or work items. For each candidate, note:
- Suggested name (slug-friendly)
- One-line description
- Scope classification (core, stretch, deferred, external)
- Key open questions from the input
- Any dependencies on other candidates

**5c. Confirm with user (MANDATORY)**

Present the extracted candidates via **AskUserQuestion** with multiSelect:

```
question: "I found [N] potential concepts. Which ones are real work you intend to do?"
header: "Confirm"
options:
  - label: "[Concept 1 name]"
    description: "[one-line description] (scope: [classification])"
  - label: "[Concept 2 name]"
    description: "[one-line description] (scope: [classification])"
  - label: "[Concept 3 name]"
    description: "[one-line description] (scope: [classification])"
multiSelect: true
```

**Only confirmed concepts get written.** Unselected candidates are discarded.

**5d. Determine structure**

For confirmed concepts, assess grouping:
- If 3+ confirmed concepts share a common theme -> propose an initiative folder
- Otherwise -> create as standalone concept files

Use **AskUserQuestion** if grouping is ambiguous:
```
question: "These [N] concepts seem related to [theme]. Group them as an initiative?"
header: "Structure"
options:
  - label: "Yes, create [theme] initiative"
    description: "Folder with sub-concepts inside"
  - label: "No, keep as standalone concepts"
    description: "Individual files at planning root"
```

**5e. Write files**

For each confirmed concept, write a concept file using the template at `${CLAUDE_PLUGIN_ROOT}/templates/planning/concept.md`. Replace template variables with extracted content.

If creating an initiative folder:
1. Create the folder: `mkdir -p "$PLANNING/[initiative-slug]"`
2. Write initiative README using template at `${CLAUDE_PLUGIN_ROOT}/templates/planning/initiative-readme.md`
3. Write sub-concept files inside the folder

Update `$PLANNING/README.md` Roadmap table with new entries.
Update `$PLANNING/active.md` via Step 4.

**5f. Incremental mode**

If planning already exists and new input is provided, the flow is the same but:
- Check if any extracted concepts match existing ones (by name similarity)
- For matches: offer to **update** the existing concept (fold new info, resolve questions) rather than create a duplicate
- For new concepts: confirm and create as normal
- For resolved questions: mark `- [x]` in the concept file with source citation

### Step 6: Conversational Setup

No input document - the user describes what they're building conversationally.

Ask focused questions to extract the roadmap:

> "Tell me about the project. What are the main features or work items you need to ship?"

Listen for:
- Distinct features or initiatives
- Priority signals ("first", "most important", "later")
- Dependencies ("X needs Y first")
- Open questions the user has
- Scope boundaries ("not in this project", "stretch goal")

After gathering enough context, go to Step 5c (confirm candidates) with the conversationally-extracted concepts.

### Step 7: Import From Backlog

Read existing backlog stories and convert them into planning concepts.

Use **Glob** with pattern `$PROJECT/.craft/backlog/*.md` to list backlog stories.
For each story, use **Read** to extract title, spark, and status.

Present as candidates (Step 5c flow). The user selects which become planning concepts. Selected stories get concept files created from their content; the backlog story itself is not moved or modified.

### Step 8: Review Open Questions

Scan all concept files for unresolved questions.

Use **Bash**:
```bash
grep -rn "^- \[ \]" "$PLANNING/" --include="*.md" 2>/dev/null
```

Parse results into a grouped list:
```
Open Questions (N total):

customer-modernization/profile-tab.md:
  - [ ] Option A vs B for purposes DTO? (Pending: Brandon + Andy)

customer-modernization/cdb-mapping.md:
  - [ ] CDB schema migration strategy? (Owner: Fidel)

permissions-cleanup.md:
  - [ ] Migration path for existing B2C users? (Owner: Jesse)
```

Use **AskUserQuestion**:
```
question: "N open questions. What would you like to do?"
header: "Questions"
options:
  - label: "Try to answer from input"
    description: "Feed me a doc, site, or info and I'll resolve what I can"
  - label: "Update a specific question"
    description: "Mark one as answered or add context"
  - label: "Back to planning menu"
    description: "Return to the main planning view"
```

**If "Try to answer from input":**
1. Gather input (same as Step 5a)
2. For each open question, check if the input contains an answer
3. For questions that can be resolved, present the proposed answers via AskUserQuestion for confirmation
4. For confirmed answers, update the concept file: change `- [ ]` to `- [x]` and add the answer with source citation
5. Run Step 4 (update active.md)

### Step 9: Create Stories From Concept

Turn a mature concept into one or more cycle stories.

**9a. Select concept**

If args specify a concept file, use that. Otherwise, present concepts that are ready for stories (status `open`, no major open questions blocking):

Use **AskUserQuestion**:
```
question: "Which concept should we create stories from?"
header: "Concept"
options:
  - label: "[Concept 1]"
    description: "[status] - [N] open questions"
  - label: "[Concept 2]"
    description: "[status] - [N] open questions"
```

**9b. Read and analyze the concept**

Use **Read** to read the concept file. Analyze scope, locked decisions, and actionable items to propose story breakdowns.

**9c. Propose stories**

Present proposed stories via AskUserQuestion:

```
question: "I'd suggest [N] stories from this concept. Approve this breakdown?"
header: "Stories"
options:
  - label: "Approve and create"
    description: "[Story 1 title], [Story 2 title], ..."
  - label: "Adjust breakdown"
    description: "Change the story split before creating"
  - label: "Not ready yet"
    description: "Go back - concept needs more work"
```

**9d. Create stories**

For each approved story:
1. Create the story file in the backlog using the standard story template
2. Add `source_concept: planning/[path-to-concept.md]` to the story's frontmatter
3. Read the concept file's frontmatter `last_updated:` value. If present, also write `source_concept_last_updated: [value]` to the story's frontmatter (snapshot of the planning concept's last_updated at story creation time - used for downstream staleness detection). If the concept has no `last_updated:` field, omit `source_concept_last_updated:` entirely (do not substitute another date).
4. Add the story path to the concept's `stories:` frontmatter field

**9e. Update concept status**

After stories are created:
1. Update concept frontmatter: `status: planned`
2. Run Step 4 (update active.md)

> "Created [N] stories from '[concept name]'. Concept marked as planned."

### Step 10: Concept Completion Check

**This is called from the story/cycle completion flow, not directly by the user.**

When a story completes, check if it has `source_concept:` in frontmatter. If so:

1. Read the source concept file
2. Check all paths in the concept's `stories:` field
3. For each story path, read the story file and check if `status: complete`
4. If ALL linked stories are complete:

Use **AskUserQuestion**:
```
question: "All stories from '[concept name]' are complete. Mark the concept done?"
header: "Concept"
options:
  - label: "Yes, mark complete"
    description: "Update concept status to complete"
  - label: "Not yet"
    description: "There's still more to do for this concept"
```

If "Yes": Update concept frontmatter `status: complete`. Run Step 4.
If "Not yet": Leave as `planned`. The user may create additional stories later.

### Step 11: Auto-Promotion

When adding a sub-concept to a standalone concept file, automatically promote it to a folder.

**Trigger:** The user adds a sub-concept to a concept that currently exists as a single `.md` file.

**Process:**
1. Read the existing concept file content
2. Create a folder with the same slug: `mkdir -p "$PLANNING/[slug]"`
3. Move the original content to `$PLANNING/[slug]/README.md`, reformatted as an initiative README (add Concepts table, preserve existing content under appropriate sections)
4. Create the new sub-concept file inside the folder
5. Update `$PLANNING/README.md` - change the file reference from `[slug].md` to `[slug]/README.md`
6. Remove the old standalone file
7. Run Step 4

**Path discovery rule:** All planning file reads use Glob to discover paths. Nothing hardcodes a planning file path except `active.md` and `README.md` (which are fixed convention paths that never promote).

---

## Concept File Frontmatter

| Field | Type | Description |
|-------|------|-------------|
| `concept` | string | Slug identifier |
| `title` | string | Display name |
| `status` | enum | `open` / `planned` / `complete` / `archived` |
| `created` | date | Creation date |
| `last_updated` | date | Last modification date |
| `owner` | string | Who owns this concept |
| `stories` | list | Paths to stories created from this concept |

## Initiative README Frontmatter

| Field | Type | Description |
|-------|------|-------------|
| `initiative` | string | Slug identifier |
| `title` | string | Display name |
| `status` | enum | `open` / `planned` / `complete` / `archived` |
| `created` | date | Creation date |
| `last_updated` | date | Last modification date |
| `concepts_total` | int | Count of sub-concepts |
| `concepts_complete` | int | Count of completed sub-concepts |

## Key Principles

1. **Nothing without confirmation.** Craft proposes, user approves. Every concept, every story, every status change.
2. **Source everything.** Every locked decision cites a person, date, and quote or code reference.
3. **Planning is forward-looking.** History lives in the vault or git. Planning is what we're going to do.
4. **Concepts are not stories.** Concepts live in planning until they mature into stories. The two artifacts serve different purposes at different stages.
5. **File content IS the state.** If a concept file exists, it's tracked. If `status: complete`, it's done. No external state files needed.
