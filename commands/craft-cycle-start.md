---
name: craft:cycle-start
description: "Activate a cycle and start implementing its stories."
---

# Cycle Start

Activate a cycle and begin implementation.

## Flow

### Step 1: Select Cycle

**If cycle name provided:**
Verify it exists in `.craft/cycles/[name]/`

**If no cycle specified:**

Scan for cycles that can be activated (planning or ready status only):

```
# Discover activatable cycles
Glob ".craft/cycles/*/cycle.yaml" → cycle_yaml_files

activatable_cycles = []
for each cycle_yaml in cycle_yaml_files:
  Read cycle_yaml → parse status, title
  if status == "planning" or status == "ready":
    cycle_name = directory name from path
    cycle_title = title value
    Glob ".craft/cycles/$cycle_name/stories/*.md" → count → story_count
    activatable_cycles.append(cycle_name, cycle_title, story_count, status)
```

**Sort and recommend:**
1. Extract numeric prefix from cycle directory names (e.g., `1-auth` → `1`, `2-dashboard` → `2`)
2. Sort cycles by numeric prefix (lowest first)
3. The **recommended cycle** is the lowest-numbered cycle that isn't `complete`
4. If cycles lack numeric prefixes, present them in filesystem order without recommendation

**Recommendation logic:**
```
# For each cycle, extract prefix: cycle_name | sed 's/^\([0-9]*\)-.*/\1/'
# Sort by prefix number
# First in sorted list = recommended
```

> "Which cycle do you want to start?"

Use **AskUserQuestion** (options sorted by numeric prefix, recommended marked):
```
question: "Which cycle do you want to start?"
header: "Cycle"
options:
  - label: "[1-auth] — Auth Flow (Recommended)"
    description: "3 stories, ready — next in sequence"
  - label: "[2-dashboard] — Dashboard Foundation"
    description: "6 stories, ready"
  - label: "[3-api] — API Layer"
    description: "4 stories, [planning] — needs detailing first"
```

**Note:** For cycles with `status: planning`, include `[planning]` in the description to signal they may need detailing. Step 2b already handles the case where stories aren't ready.

**Note:** Show "Already active: [cycle]" in the question text if applicable.

**Note:** If cycles don't have numeric prefixes (legacy projects), omit the "(Recommended)" marker and present cycles in the order found.

**If user provides custom text:** Ask a clarifying AskUserQuestion to confirm which cycle.

### Step 2: Show Cycle Overview

Read `cycle.yaml` and scan stories:

Use **Grep** with pattern `^status: ready`, path `$cycle_dir/stories/`, glob `*.md`, output_mode `files_with_matches` → count → `stories_ready`.

Use **Grep** with pattern `^status: planning`, path `$cycle_dir/stories/`, glob `*.md`, output_mode `files_with_matches` → count → `stories_planning`.

`stories_total = stories_ready + stories_planning`

Present the overview:

> "**Cycle: [Name]**
>
> **Goal:** [Goal from cycle file]
>
> **Stories:**
> | # | Story | Status | Dependencies |
> |---|-------|--------|--------------|
> | 1 | [Name] | ready | none |
> | 2 | [Name] | ready | needs Story 1 |
> | 3 | [Name] | planning ⚠️ | needs Story 2 |
>
> **Ready:** [N] stories can be implemented
> **Need planning:** [M] stories need plan-chunks first

### Step 2b: Handle Unplanned Stories

**If ALL stories are `planning`:**

> "No stories are ready to implement yet.
> Plan at least one story to start the cycle."

Use **AskUserQuestion**:
```
question: "Which story do you want to plan first?"
options:
  - label: "Story 1: [Name]"
    description: "No dependencies — can start here"
  - label: "Story 2: [Name]"
    description: "Depends on Story 1"
  - label: "Cancel"
    description: "Come back later"
```

⛔ **DO NOT plan chunks directly. You MUST invoke the skill:**

```
Skill tool:
  skill: "craft:plan-chunks"
  args: "[selected story file path] — Cycle '[cycle name]' is being activated, this is the first to plan.
  DIRECTION_CONFIRMED: true
  STORY: [story-name]
  CYCLE: [cycle-dir-name]
  CYCLE_GOAL: [goal from cycle.yaml]
  STORY_POSITION: 1 of [N]"
```

Include the story path plus cycle activation context so plan-chunks understands the urgency and scope.

This hands off to `plan-chunks` which produces detailed implementation plans. Do NOT replicate planning inline.

**If SOME stories are `planning`:**

> "[N] of [M] stories still need planning:
> - Story 3: [Name]
> - Story 5: [Name]
>
> Ready stories:
> - Story 1: [Name] (no dependencies) ✓
> - Story 2: [Name] (no dependencies) ✓
> - Story 4: [Name] (needs Story 2) ✓"

Use **AskUserQuestion** (options vary based on unplanned count):

**If unplanned count > 1:**
```
question: "[N] stories need planning before implementation. How do you want to proceed?"
options:
  - label: "Plan all [N] stories (parallel)"
    description: "Launch parallel planning — fastest path to implementation"
  - label: "Plan one at a time"
    description: "Interactive planning for each story sequentially"
  - label: "Start with ready stories"
    description: "Implement [M] ready stories, plan the rest later"
  - label: "Move unplanned to backlog"
    description: "Remove unplanned stories from cycle"
```

**If unplanned count = 1:**
```
question: "1 story needs planning before implementation. How do you want to proceed?"
options:
  - label: "Plan it now"
    description: "Run plan-chunks to make it implementation-ready"
  - label: "Start with ready stories"
    description: "Implement [M] ready stories, plan this one later"
  - label: "Move to backlog"
    description: "Remove unplanned story from cycle"
```

**If "Plan all [N] stories (parallel)":**

⛔ **DO NOT plan chunks directly. You MUST invoke the skill:**

```
Skill tool:
  skill: "craft:plan-chunks"
  args: "DIRECTION_CONFIRMED: true
  MODE: batch
  CYCLE: [cycle-dir-name]
  CYCLE_GOAL: [goal from cycle.yaml]"
```

This hands off to `plan-chunks` in batch mode, which launches parallel planning agents, runs batch triage, and writes approved plans. Do NOT replicate any of this inline. Return to Step 2 when all stories are planned.

**If "Plan one at a time" or "Plan it now":**

⛔ **DO NOT plan chunks directly. You MUST invoke the skill for each unplanned story:**

```
Skill tool:
  skill: "craft:plan-chunks"
  args: "[story file path] — Planning before cycle start.
  DIRECTION_CONFIRMED: true
  STORY: [story-name]
  CYCLE: [cycle-dir-name]
  CYCLE_GOAL: [goal from cycle.yaml]"
```

This hands off to `plan-chunks` which produces detailed implementation plans. Do NOT replicate planning inline. Return to Step 2 when all stories are planned.

**If "Start with ready stories":**
- Proceed to activation
- Only ready stories can be implemented
- Unplanned stories stay in cycle with `status: planning`

**If ALL stories are `ready`:**
- Proceed directly to Step 3

### Step 3: Activate

**Run the transition script:**
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/start-cycle.sh .craft/cycles/[cycle-name]
```

This updates:
- Global: `ACTIVE_CYCLE` set, `PLANNING_CYCLE` cleared
- Cycle: `CYCLE_STATUS = active`
- cycle.yaml: `status: active`

**Confirm activation:**

> "**Cycle activated: [Name]**
>
> 🚀 **Cruise mode ON** — I'll run autonomously
> ├── Implement all [N] stories ([M] chunks)
> ├── State snapshot before each chunk, commit at story completion
> ├── Validate after each chunk
> └── Only stop if something breaks
>
> You'll see progress in the status line. Ready?"

Use **AskUserQuestion**:
```
question: "Ready to start?"
header: "Go"
options:
  - label: "Go — review first story"
    description: "Review before implementing"
  - label: "Let me pick which story"
    description: "Choose a different starting story"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their intent.

### Step 4: Start First Story (Optional)

**If user chose "start with Story 1":**

> "Starting **Story 1: [Name]**
>
> [Spark summary]
>
> This story has [N] chunks. Ready to implement?"

Use **AskUserQuestion**:
```
question: "Ready to implement this story?"
header: "Start"
options:
  - label: "Yes, begin implementation"
    description: "Start working on chunks"
  - label: "Review the full story first"
    description: "Show me all the details"
  - label: "Pick a different story"
    description: "Choose another story to start"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their intent.

⛔ **DO NOT implement the story directly. You MUST invoke the command:**

```
Skill tool:
  skill: "craft:craft-story-implement"
  args: "[story file path] — Cycle '[cycle name]', starting implementation.
  STORY: [story-name]
  CYCLE: [cycle-dir-name]
  STORY_POSITION: [M] of [total]"
```

Include the story path, chunk count, and cycle position. This gives story-implement full context for how to run.

This hands off to `story-implement` which orchestrates the full implementation workflow with checkpoints, validation, and agent invocations. Do NOT replicate implementation inline.

**If user chose "let me pick":**

> "Which story?"

Use **AskUserQuestion** (options based on ready stories):
```
question: "Which story do you want to start?"
header: "Story"
options:
  - label: "Story 1: [Name]"
    description: "[brief spark summary]"
  - label: "Story 2: [Name]"
    description: "[brief spark summary]"
  - label: "Story 3: [Name]"
    description: "[brief spark summary]"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to confirm which story.

## Quick Start

With cycle name:
```
/craft:cycle-start dashboard-foundation
```

Activates immediately and offers to start Story 1.

## Switching Cycles

If there's already an active cycle:

> "**[Current Cycle]** is currently active with [progress].
>
> Switch to **[New Cycle]**?"

Use **AskUserQuestion**:
```
question: "Switch to [New Cycle]?"
header: "Switch"
options:
  - label: "Yes, switch"
    description: "Current progress is saved"
  - label: "No, stay on current cycle"
    description: "Continue with [Current Cycle]"
  - label: "Show me current status first"
    description: "Review progress before deciding"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their intent.

## Remember

- Only one cycle can be active at a time
- Progress is saved in story files, so switching is safe
- Stories must be in the cycle's `stories/` folder
- Use `/craft:status` to see current state anytime
