---
name: story-delete
description: "Permanently delete a story."
argument-hint: "[story-name]"
---

# Story Delete

Permanently remove a story. This is destructive — use archive if you might want it later.

## Flow

### Step 1: Select Story

If no story specified, show all stories:

> "Which story do you want to delete?"
>
> **In Cycle [X]:**
> - [Story 1] — ready
> - [Story 2] — active
>
> **In Backlog:**
> - [Story 3]
> - [Story 4]

Use **AskUserQuestion**:
```
question: "Which story to delete?"
header: "Delete"
options:
  - label: "[Story 1] (cycle)"
  - label: "[Story 2] (cycle)"
  - label: "[Story 3] (backlog)"
```

### Step 2: Confirm (Required)

> "⚠️ **Permanently delete [Story Name]?**
>
> This will:
> - Remove the story file entirely
> - Delete all chunks and decisions
> - Update cycle counts (if in cycle)
>
> **This cannot be undone.** Use `/craft:story-archive` to keep it in backlog instead."

Use **AskUserQuestion**:
```
question: "Confirm permanent deletion?"
options:
  - label: "Yes, delete permanently"
    description: "Cannot be undone"
  - label: "Archive instead"
    description: "Move to backlog, keep for later"
  - label: "Cancel"
    description: "Keep the story"
```

**If "Archive instead":** Run `/craft:story-archive` flow instead.

### Step 3: Execute

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/delete-story.sh "[story-file-path]"
```

### Step 4: Confirm

> "**[Story Name]** deleted."

## Quick Usage

```bash
/craft:story-delete [story-name]
```

Still requires confirmation — no silent deletes.

## Safety

- Always requires explicit confirmation
- Offers archive as alternative
- Updates cycle state automatically
- Git history preserves deleted files (if committed)
