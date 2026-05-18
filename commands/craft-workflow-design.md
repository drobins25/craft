---
name: craft:workflow-design
description: "Design a workflow - create new definitions, edit existing ones, or archive workflows you no longer need."
argument-hint: "[create | edit <name> | archive <name>]"
when_to_use: "Use when the user wants to author or organize workflow definitions: 'create a new workflow', 'edit the workflow', 'refine this workflow', 'archive a workflow'. NOT for running or prepping sessions (use craft:workflow-run)."
---

# Workflow Design

Author and manage workflow definitions. Owns the definition lifecycle: creating new workflows from scratch or by importing process documents, editing existing definitions (stage prose, prompts, checklists, variables), and archiving workflows no longer in use.

For executing sessions of an existing workflow, use `/craft:workflow-run`. This command does not run anything - it just shapes the definitions that workflow-run executes against.

---

## Project Root

Use `$CRAFT_PROJECT_ROOT` (set at session start) as the base path for all `.craft/` references. If not set, resolve by walking up from PWD to find the nearest `.craft/.global-state`.

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`.

## Format Reference

Every workflow definition uses stages-v1 format: a `definition.md` routing table plus per-stage files in `stages/NN-slug.md`. For the definitive specification of the routing-table schema, stage file frontmatter (execution, agent, produces, consumes, human_gate), and session frontmatter, see [references/workflow-formats.md](references/workflow-formats.md). That file is a cold-path schema lookup; all create/edit/archive procedure lives in this file.

---

## Step 0: Determine Verb

Parse args to determine which verb to execute:

- **`create`** -> Step 1 (define a new workflow from scratch or by importing a process document)
- **`edit {name}`** -> Step 2 (refine an existing workflow's stages, prompts, checklist items, or variables)
- **`archive {name}`** -> Step 3 (move an existing workflow to `.archived/`)
- **No args** -> AskUserQuestion:

```
question: "What would you like to do?"
header: "Workflow design"
options:
  - label: "Create a new workflow"
    description: "Define stages, variables, and execution modes from scratch or import"
  - label: "Edit an existing workflow"
    description: "Refine stage prose, prompts, checklists, or variables"
  - label: "Archive a workflow"
    description: "Move to .archived/ - sessions and definition preserved, hidden from dashboard"
```

Route based on selection.

---

## Step 1: Create New Workflow (`create` verb)

### 1.1: Determine Source

Use **AskUserQuestion**:

```
question: "How do you want to create this workflow?"
header: "Source"
options:
  - label: "From scratch"
    description: "Define stages interactively"
  - label: "Import from file"
    description: "Parse an existing process document (Markdown, any project)"
  - label: "Import from URL"
    description: "Fetch and parse a remote process document"
```

- **"From scratch"** -> Jump to **Step 1.3** (Define Stages).
- **"Import from file"** -> Ask for file path. Jump to **Step 1.2**.
- **"Import from URL"** -> Fetch URL via WebFetch. Jump to **Step 1.2**.

### 1.2: Parse Source Document

Read the source. Identify stages by looking for:

- `### Stage N:` or `## Stage N:` headings
- `### Step N:` or `## Step N:` headings
- Numbered headings (`### 1. Title`, `## 1: Title`)
- Any `##` or `###` level heading pattern that repeats with incrementing numbers

For each stage found, extract:

- **Name** from the heading
- **Description** from the first paragraph
- **Produces** from "Artifacts:" or "What it produces:" sections
- **Key principles** from "Key principle:" sections
- **Sub-steps** from bullet lists or sub-headings within the stage

Present the parsed structure:

> Found **{N} stages** in "{source file}":
> 1. {Stage 1 name} - {first line of description}
> 2. {Stage 2 name} - {first line}
> ...
>
> Does this look right?

Use **AskUserQuestion**:

```
question: "Does the parsed structure look correct?"
header: "Parse review"
options:
  - label: "Looks good"
    description: "Continue to configure execution modes"
  - label: "Needs adjustment"
    description: "I'll tell you what to fix"
```

- **"Looks good"** -> Jump to **Step 1.3**.
- **"Needs adjustment"** -> Let the user describe changes, re-parse. Loop.

### 1.3: Define Workflow Metadata

Ask for:

- **Workflow name** (slugified for the folder name)
- **Description** (one line - this becomes the workflow's frontmatter `description`)
- **Variables** - "What variables does this workflow need? (e.g., topic, domain, project)"

For each variable, capture:

- Name
- Description (what it represents)
- Optional default value

### 1.4: Configure Execution Modes

Walk through each stage. For each one, suggest an execution mode based on the stage description:

- Stages mentioning "research", "investigate", "analyze" with a named agent -> suggest `agent`
- Stages mentioning "verify" with a named agent -> suggest `agent`
- Stages mentioning "synthesize", "combine", "integrate", "review", "decide" -> suggest `inline` (needs prior stage context)
- Stages mentioning "build", "write", "create", "implement" -> suggest `inline` (needs workflow context)
- Stages mentioning "apply", "fix", "update" -> suggest `inline`
- Stages with sub-passes or multiple agents -> suggest `agent`
- Default -> suggest `inline`

Use **AskUserQuestion** per stage:

```
question: "Stage {N}: {name} - How should this execute?"
header: "Execution"
options:
  - label: "{suggested mode} (Recommended)"
    description: "{description of what this mode does}"
  - label: "{alternative 1}"
    description: "{description}"
  - label: "{alternative 2}"
    description: "{description}"
  - label: "{alternative 3}"
    description: "{description}"
```

**Execution modes:**

| Mode | Behavior |
|------|----------|
| `agent` | Spawn isolated sub-agent, auto-advance on success. Use when the work is self-contained and doesn't need prior stage context. |
| `inline` | Orchestrator executes directly with full workflow context, auto-advance. Use when the stage builds on prior stages or needs context continuity. |
| `manual` | Present stage, wait for human to mark complete. |
| `command` | Run a craft command via Skill tool. |

**Trust is controlled at session level, not per stage.** In interactive run mode, every stage pauses for confirmation. In auto run mode, only `manual` stages pause. The execution mode controls *who does the work*, not whether there's a human gate.

**If "Agent":** Ask which agent. Suggest based on stage description (researcher for research stages, verifier for verification, etc.). Also ask for a prompt template with `{variable}` placeholders.

**If "Inline":** Ask for a prompt/instructions template with `{variable}` placeholders. No agent selection - the orchestrator executes directly.

**If "Command":** Ask which craft command (e.g., `craft:research`, `craft:research-verify`).

After configuring all stages, ask about sub-stages:

```
question: "Any stages that should have sub-stages? (e.g., a stage with two distinct passes)"
header: "Sub-stages"
options:
  - label: "No sub-stages needed"
    description: "Each stage is atomic"
  - label: "Yes, let me specify"
    description: "Some stages have distinct sub-passes"
```

### 1.5: Write Definition

Create the workflow directories using Bash:

```bash
mkdir -p "$PROJECT/.craft/workflows/{workflow-slug}/stages"
mkdir -p "$PROJECT/.craft/workflows/{workflow-slug}/sessions"
```

Write `definition.md` as a routing table using this template:

```markdown
---
name: {Workflow Name}
description: {one-line description}
created: {today}
variables:
  {var}: "{description}"
stages: {count}
format: stages-v1
---

# {Workflow Name}

{Overview paragraph.}

## Stages

| # | Name | Execution | File | Produces |
|---|------|-----------|------|----------|
| 1 | {Stage 1 Name} | agent | stages/01-slug.md | {produces or empty} |
| 2 | {Stage 2 Name} | inline | stages/02-slug.md | {produces or empty} |
...
```

For each stage, write `stages/NN-{slug}.md` where NN is zero-padded stage number and slug is the kebab-case stage name. Stage file format:

```markdown
---
stage: {N}
name: {Stage Name}
execution: {agent|inline|manual|command}
agent: {agent-name if execution: agent}
command: {command-name if execution: command}
args: "{command args if execution: command}"
produces: {artifact path or empty}
consumes: []
human_gate: ""
---

# Stage {N}: {Stage Name}

{Human-readable description of what this stage does, why it matters,
and what principles apply. Variable placeholders like {topic} are
substituted at dispatch time from session variables.}

## Prompt

{Agent or inline instructions. Variable placeholders substituted at
dispatch time. Omit this section for execution: manual.}

## Checklist

- [ ] {Completion criterion 1}
- [ ] {Completion criterion 2}

## Artifacts

- **Produces:** {path or "(none)"}
- **Consumes:** {list or "(none - first stage)"}
```

**Stage file rules:**

- Frontmatter contains all machine-readable metadata.
- `consumes:` lists artifact file paths from prior stages. Use `{session_dir}` to reference the current session's artifact directory.
- `produces:` is the artifact this stage creates.
- The `## Prompt` section is the agent/inline instructions.
- The `## Checklist` section defines completion criteria. These are copied into each session at creation time for per-session tracking.
- Stage files are templates shared across all sessions - never modified per-session.

Present result:

> **Workflow created: {name}**
>
> Saved to `.craft/workflows/{slug}/definition.md` plus {N} stage files in `stages/`.
> {N} stages | {agent_count} agent, {inline_count} inline, {manual_count} manual, {command_count} command
>
> Run `/craft:workflow-run run {slug}` to create your first session.

---

## Step 2: Edit Existing Workflow (`edit` verb)

Refine an existing workflow's definition or stages.

### 2.1: Select Workflow

If workflow name provided in args, use it. Otherwise list available workflows via Glob `$PROJECT/.craft/workflows/*/definition.md` and let the user pick via AskUserQuestion.

Read the workflow's `definition.md` and all stage files in `stages/`.

### 2.2: Present Current Structure

Display:

> **Workflow: {name}**
>
> Description: {description}
> Variables: {var1}, {var2}, ...
> Created: {date}
>
> **Stages ({N} total):**
> 1. {Stage 1 Name} - {execution mode} - {one-line description}
> 2. {Stage 2 Name} - {execution mode} - {one-line description}
> ...

### 2.3: Choose What to Edit

Use **AskUserQuestion**:

```
question: "What would you like to edit?"
header: "Edit target"
options:
  - label: "Workflow metadata"
    description: "Description, variables, or overview prose"
  - label: "An existing stage"
    description: "Change a stage's prose, prompt, checklist, execution mode, or agent"
  - label: "Add a new stage"
    description: "Insert a stage at a specific position"
  - label: "Remove a stage"
    description: "Delete a stage and renumber subsequent stages"
```

### 2.4a: Edit Metadata

Ask which field:

- **Description** -> Get new one-line description, update `definition.md` frontmatter.
- **Variables** -> Show current variables, ask which to add/remove/rename. Be careful: removing or renaming a variable used in stage prompts will leave dangling `{var}` placeholders. Surface that risk before saving.
- **Overview prose** -> Show current body text after frontmatter, ask for replacement.

### 2.4b: Edit a Stage

Ask which stage number. Read its file. Present current content. Ask what to change:

```
question: "Stage {N}: {Name} - What to change?"
header: "Stage edit"
options:
  - label: "Stage name (heading)"
    description: "Renames the stage and updates the routing table"
  - label: "Prose description"
    description: "The human-readable description between the heading and ## Prompt"
  - label: "Prompt template"
    description: "The agent or inline instructions"
  - label: "Checklist items"
    description: "Add, remove, or modify completion criteria"
  - label: "Execution metadata"
    description: "Change execution mode, agent, produces, consumes, human_gate"
```

For each, get the new content, write the updated stage file. If the stage name changed, update the routing table row in `definition.md`. If execution mode changed, update the routing table's `Execution` column.

### 2.4c: Add a New Stage

Ask:

- Where to insert (between stage N and N+1, or at the end)
- Stage name
- Execution mode (same options as Step 1.4)
- Agent or command (if applicable)
- Prompt template
- Checklist items
- `produces:` artifact path
- `consumes:` artifact dependencies

Renumber subsequent stage files: if inserting at position K with N existing stages, rename `stages/NN-...md` -> `stages/(NN+1)-...md` for all stages where NN >= K. Update the routing table accordingly. Update the new stage file's `stage:` frontmatter.

### 2.4d: Remove a Stage

Ask which stage to remove. Confirm via AskUserQuestion (this is destructive - sessions referencing this stage will break).

Delete the stage file. Renumber subsequent stage files down by one. Update the routing table: remove the row, renumber remaining rows.

If any other stages have `consumes:` references to the removed stage's `produces:`, warn the user and ask whether to clear those references or abort.

### 2.5: Confirm and Save

Show a diff summary of all changes made in this session:

> **Changes to {workflow name}:**
> - {change 1}
> - {change 2}

Use **AskUserQuestion**:

```
question: "Save these changes?"
header: "Save"
options:
  - label: "Save"
    description: "Write all changes to disk"
  - label: "Cancel"
    description: "Discard changes, leave workflow unchanged"
```

If "Save", write the updated files. Show confirmation:

> **Edited: {workflow name}**
> {N} changes saved. Existing sessions are unaffected; new sessions of this workflow will pick up the changes.

---

## Step 3: Archive Workflow (`archive` verb)

Move a workflow to `.archived/` - preserves definition and sessions, hides from dashboard.

### 3.1: Select Workflow

If workflow name provided in args, use it. Otherwise list workflows and let user pick via AskUserQuestion.

### 3.2: Confirm

Display the workflow's session count and status breakdown:

> **{Workflow name}**
> {N} stages, {M} sessions ({active}, {ready}, {draft}, {complete})

Use **AskUserQuestion**:

```
question: "Archive {workflow name}?"
header: "Archive"
options:
  - label: "Archive"
    description: "Move to .craft/workflows/.archived/. Sessions preserved, hidden from dashboard."
  - label: "Cancel"
    description: "Leave the workflow active"
```

### 3.3: Move

Move the workflow folder using Bash:

```bash
mkdir -p "$PROJECT/.craft/workflows/.archived"
mv "$PROJECT/.craft/workflows/{slug}" "$PROJECT/.craft/workflows/.archived/{slug}"
```

Display:

> **Archived: {workflow name}**
> Moved to `.craft/workflows/.archived/{slug}/`
> Sessions and definition preserved. Not shown in dashboard.
> To restore: move the folder back to `.craft/workflows/`.
