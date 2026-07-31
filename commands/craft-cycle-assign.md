---
name: cycle-assign
description: "Move a story from backlog to a cycle."
---

# Cycle Assign

Assign stories from the backlog to a cycle.

## Status Guard

Before assigning, **validate story has chunks**:

| Check | Action if Failed |
|-------|------------------|
| Has chunks? | BLOCK: "Story needs planning" → offer path choice |
| Status = `ready`? | OK (backlog stories should be `ready`) |

Use **AskUserQuestion** if story isn't ready:
```
question: "This story doesn't have chunks yet. How do you want to plan it?"
header: "Plan"
options:
  - label: "Get creative"
    description: "Explore options first with creative-spark"
  - label: "Plan directly"
    description: "I know what I want, run plan-chunks"
  - label: "Pick a different story"
    description: "Choose another story to assign"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion before proceeding.

## Flow

### Step 1: Select Story

If no story specified:

> "Which story do you want to assign?"

Use **AskUserQuestion** (options based on actual backlog):
```
question: "Which story do you want to assign?"
header: "Story"
options:
  - label: "[story-1-name]"
    description: "[priority] — [brief spark]"
  - label: "[story-2-name]"
    description: "[priority] — [brief spark]"
  - label: "[story-3-name]"
    description: "[priority] — [brief spark]"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to confirm which story they mean.

If story specified: proceed directly.

### Step 2: Select Cycle

If no cycle specified:

> "Which cycle?"

Use **AskUserQuestion** (options based on existing cycles, sorted by numeric prefix):
```
question: "Which cycle?"
header: "Cycle"
options:
  - label: "[1-auth] (Recommended)"
    description: "active, 3 stories"
  - label: "[2-dashboard]"
    description: "planning, 6 stories"
  - label: "Create new cycle"
    description: "Start a new cycle for this story"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to confirm which cycle.

**Cycle selection logic:**
- Sort cycles by numeric prefix (e.g., `1-auth` < `2-dashboard`)
- If active cycle exists: mark it as "(Recommended)"
- If no active cycle: recommend the lowest-numbered incomplete cycle
- If only one cycle exists: use it directly

### Step 3: Move the Story

Run the move script:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/move-story.sh .craft/backlog/[story].md [cycle-name]
```

This handles:
- Moving the file to `.craft/cycles/[cycle]/stories/`
- Numbering the file (e.g., `1-story-name.md`)
- Updating story frontmatter (cycle, story_number, status → ready)

### Step 4: Confirm

> "**[Story]** assigned to **Cycle: [Name]**.
>
> Work on it now?"

Use **AskUserQuestion**:
```
question: "Work on it now?"
header: "Next"
options:
  - label: "Yes, start implementing"
    description: "Begin work on this story"
  - label: "Assign another story"
    description: "Add more stories to this cycle"
  - label: "Done for now"
    description: "Exit assignment flow"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their intent.

## Batch Assignment

Assign multiple stories at once:

> "Select stories for **Cycle: Auth**:"

Use **AskUserQuestion** with `multiSelect: true`:
```
question: "Select stories to assign to Cycle: Auth"
header: "Batch"
multiSelect: true
options:
  - label: "update-modal"
    description: "high priority"
  - label: "refactor-api"
    description: "medium priority"
  - label: "dashboard-widgets"
    description: "medium priority"
  - label: "fix-mobile-nav"
    description: "low priority"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to confirm which stories they want to include.

> "Assigned [N] stories to Cycle: Auth."

## Priority Ordering

When assigning, order by priority:
1. Urgent → first
2. High → second
3. Medium → third
4. Low → last

> "Suggested order for Auth cycle:
> 1. update-modal (high)
> 2. refactor-api (medium)
>
> Good order, or rearrange?"

Use **AskUserQuestion**:
```
question: "Good order, or rearrange?"
header: "Order"
options:
  - label: "Good order"
    description: "Keep the suggested priority order"
  - label: "Rearrange"
    description: "I want to change the order"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their preferred order.

## Moving Between Cycles

If story is already in a cycle:

> "**[Story]** is currently in **Cycle: [Other]**.
>
> Move to **Cycle: [New]**?"

Use **AskUserQuestion**:
```
question: "Move [Story] to Cycle: [New]?"
header: "Move"
options:
  - label: "Yes, move it"
    description: "Transfer to the new cycle"
  - label: "No, keep where it is"
    description: "Leave in current cycle"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their intent.

## Back to Backlog

Move story back to backlog:

> "Move **[Story]** back to backlog?"

Use **AskUserQuestion**:
```
question: "Move [Story] back to backlog?"
header: "Archive"
options:
  - label: "Yes, remove from cycle"
    description: "Move back to backlog"
  - label: "No, keep in cycle"
    description: "Leave in current cycle"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their intent.

Run the move script:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/move-story.sh .craft/cycles/[cycle]/stories/[story].md backlog
```

This handles moving the file and updating status/counts.

## Remember

- Stories start in backlog
- Assign to cycle when ready to work
- Can move between cycles freely
- Order matters for implementation sequence
- When multiple stories in a cycle need planning, batch planning is available via `craft-cycle-start` or `craft-cycle-design` ("Plan all stories" option)
