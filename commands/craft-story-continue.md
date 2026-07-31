---
name: story-continue
description: "Resume an interrupted story from where you left off."
---

# Story Continue

Resume a story that was paused or interrupted.

## Flow

### Step 1: Find Current Story

Check state files:

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`.

Use **Read** to read `$PROJECT/.craft/.global-state`. Parse key=value pairs to extract `CURRENT_STORY`, `ACTIVE_CYCLE`.

Use **Read** to read `$PROJECT/.craft/cycles/$ACTIVE_CYCLE/.state`. Parse key=value pairs to extract `CURRENT_CHUNK`, `TOTAL_CHUNKS`, `LAST_CHECKPOINT`.

**If no current story:**
> "No story in progress.
>
> Pick one to work on?"

Use **AskUserQuestion** (options based on ready stories):
```
question: "No story in progress. Pick one to work on?"
header: "Story"
options:
  - label: "[Story 1 name]"
    description: "[N] chunks, [status]"
  - label: "[Story 2 name]"
    description: "[N] chunks, [status]"
  - label: "[Story 3 name]"
    description: "[N] chunks, [status]"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to confirm which story.

**If story found:**
> Proceed to resume

### Step 2: Show Context

> "Resuming **[Story Name]**
>
> **Progress:**
> - Chunk 1: ✓ Complete
> - Chunk 2: ✓ Complete
> - Chunk 3: ◐ In progress ← you are here
> - Chunk 4: ○ Pending
>
> **Last activity:** [timestamp]
> **Last checkpoint:** [snapshot timestamp]
>
> Continue with Chunk 3?"

### Step 3: Verify State

Check if files match expected state:

```bash
# Compare current files with checkpoint
git diff [checkpoint-hash]
```

**If clean:**
> Continue normally

**If changes detected:**
> "Files have changed since last checkpoint:
> - `auth.ts` — modified
> - `login.tsx` — modified
>
> How to proceed?"

Use **AskUserQuestion**:
```
question: "Files changed since checkpoint. How to proceed?"
header: "Changes"
options:
  - label: "Keep changes, continue"
    description: "These are part of my progress"
  - label: "Rollback to checkpoint"
    description: "Discard changes, start fresh"
  - label: "Review changes first"
    description: "Show me the diff before deciding"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand what happened with the changes.

### Step 4: Hand Off to story-implement

⛔ **DO NOT implement the chunk yourself. Hand off to craft:story-implement which uses the implementer agent.**

After Steps 1-3 have established context and verified state, invoke `craft:story-implement` with the story name. It already handles `status: active` stories via its Resume Support section and routes through the implementer agent for every chunk.

```
Skill tool:
  skill: "craft:story-implement"
  args: "[story-name]"
```

**Do NOT re-read context, continue chunks, or run validation here.** All of that is owned by `craft:story-implement`.

## Quick Resume

For the common case, make it fast:

> `/story continue`
>
> "Continuing **Registration** — Chunk 3 of 4.
>
> Ready when you are."

## Handling Stale State

If significant time has passed:

> "It's been [X days] since you worked on this.
>
> Quick refresh:
> - **Story:** [Name]
> - **Goal:** [Brief summary]
> - **Current chunk:** [Description]
> - **Dependencies:** [Any changes since then?]
>
> Still want to continue this, or pick something else?"

Use **AskUserQuestion**:
```
question: "Continue this story or pick something else?"
header: "Resume"
options:
  - label: "Continue this story"
    description: "Resume where I left off"
  - label: "Pick something else"
    description: "Show me other options"
  - label: "Review story first"
    description: "Show me the full context before deciding"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their preference.

## Handling Multiple Paused Stories

If multiple stories are paused:

> "You have 2 paused stories:"

Use **AskUserQuestion**:
```
question: "Which story do you want to continue?"
header: "Story"
options:
  - label: "Registration"
    description: "chunk 3/4, paused 2 hours ago"
  - label: "Dashboard"
    description: "chunk 1/3, paused yesterday"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to confirm which story.

## State Recovery

If `.state` file is corrupted or missing:

> "State file is missing. Reconstructing from story file...
>
> Based on the story file:
> - Chunks 1-2 are marked complete
> - Chunk 3 is unmarked
>
> Start from Chunk 3?"

Use **AskUserQuestion**:
```
question: "Start from Chunk 3?"
header: "Recovery"
options:
  - label: "Yes, start Chunk 3"
    description: "Continue from reconstructed state"
  - label: "Review first"
    description: "Show me what was completed"
  - label: "Start fresh"
    description: "Re-implement from Chunk 1"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand where they want to resume.

## Remember

- Files are source of truth
- State can always be reconstructed
- Offer rollback if anything looks wrong
- Re-establish context before diving in
