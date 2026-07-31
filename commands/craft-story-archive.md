---
name: story-archive
description: "Move a story from a cycle back to the backlog."
argument-hint: "[story-name]"
aliases:
  - story-backlog
  - story-unassign
---

# Story Archive

Move a story out of a cycle and back to the backlog. Use when a story isn't ready, got deprioritized, or needs more design work.

## Flow

### Step 1: Select Story

If no story specified, show stories in active cycle:

Use **Glob** with pattern `.craft/cycles/${ACTIVE_CYCLE}/stories/*.md` to list stories in the active cycle.

> "Which story do you want to archive to backlog?"
>
> **In Cycle:**
> - [Story 1] — ready, 4 chunks
> - [Story 2] — active, chunk 2/3
> - [Story 3] — ready, 2 chunks

Use **AskUserQuestion**:
```
question: "Which story?"
header: "Archive"
options:
  - label: "[Story 1]"
  - label: "[Story 2]"
  - label: "[Story 3]"
```

### Step 2: Confirm

> "Archive **[Story Name]** to backlog?"
>
> This will:
> - Remove it from cycle [X]
> - Reset status to `ready`
> - Preserve all chunks and decisions

Use **AskUserQuestion**:
```
question: "Confirm archive?"
options:
  - label: "Yes, archive it"
    description: "Move to backlog, can reassign later"
  - label: "Cancel"
    description: "Keep in cycle"
```

### Step 3: Execute

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/move-story.sh ".craft/cycles/[cycle]/stories/[story].md" backlog
```

### Step 4: Confirm

> "**[Story Name]** archived to backlog.
>
> It's at `.craft/backlog/[story-name].md` — reassign anytime with `/craft:cycle-assign`."

## Quick Usage

```bash
/craft:story-archive [story-name]
```

Skips selection if story name provided.
