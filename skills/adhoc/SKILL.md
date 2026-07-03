---
name: craft:adhoc
description: "Adhoc workflow for small targeted changes to existing behavior or appearance, without the full story ceremony. Use when the orchestrator encounters a bug with a clear root cause and surgical solution, OR a small enhancement to something already built (a different icon, wording, spacing, color). Triggers on: 'fix this', 'this is broken', 'the alignment is off', 'that button doesn't work', 'quick fix', 'patch this', 'tweak this', 'change the icon', 'adjust the wording', post-story corrections, or any situation where the write gate blocks a small targeted change. Acts NOW - deferred work belongs in the notebook. Do NOT use for new features, design exploration, or changes requiring creative spark."
allowed-tools: ["Read", "Edit", "Write", "Glob", "Grep", "Bash", "AskUserQuestion", "TaskCreate", "TaskUpdate"]
---

<!-- EDITORS: This file is the shared SHELL only - guards, classification, write gate,
     commit step. The actual flows live in references/fix.md (bugs) and
     references/tweak.md (enhancements). Flow changes go THERE, not here. -->

# Adhoc

You are the orchestrator making a small targeted change. No implementer agent, no chunks, no story ceremony. Adhoc work comes in two flavors: a **fix** (something is broken and you can see why) and a **tweak** (something works as built, but the user wants it different). This shell classifies which one you're holding, then runs the matching flow from its reference file.

## Why This Exists

The full story ceremony is right for features and complex work. But when a button doesn't respond - or a shipped icon just isn't the one the user wants - spinning up that machinery wastes time and adds no value. Fixes and tweaks need different treatment: a fix is gated on root-cause confidence ("will it work"), a tweak on visual fit ("will it fit"). Both leave permanent records for pattern analysis, in separate corpora.

## Step 1: Guard Rails

**Active story check:** If CURRENT_STORY is set in `.global-state`, warn: "There's an active story ([name]). Apply this change within that story's scope, or complete/pause the story first." Do not set CRAFT_WRITE_ENABLED if it's already set by a story - that would create overlapping write sessions.

**No new features:** Adhoc work changes something that already exists. If the solution adds something that wasn't there before (a new component, a new API endpoint, a new element on the page), it's a story.

**No design exploration:** If the change requires choosing between creative directions, it's a story (or design-vibe). Adhoc executes a known intent.

## Step 2: Classify - Fix or Tweak

Apply the tie-breaker:

- **Fix:** the change restores something that used to work, or makes behavior match a stated spec. There is a symptom and a root cause. ("The button doesn't respond." "Font weights render wrong.")
- **Tweak:** the change alters something working as built because it doesn't look or read right. Nothing is broken; taste or intent changed. ("I want a different icon." "That heading is too loud.")
- **Genuinely ambiguous** ("the icon looks wrong" - broken render or bad taste?): **ask the user which they mean.** Never silently pick a lane.

## Step 3: Open the Gate

```bash
# Open the write gate
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh CRAFT_WRITE_ENABLED "true" "${CRAFT_PROJECT_ROOT:-.}"

# Safety marker - session-start.sh clears orphans
echo "$(date -u +%Y-%m-%dT%H:%M:%S)" > "${CRAFT_PROJECT_ROOT:-.}/.craft/.active-fix"
```

Create the close-obligation task pair so the open gate stays visible even if the conversation drifts:

1. **TaskCreate** - "Adhoc [fix|tweak]: [brief description]" - set `in_progress`.
2. **TaskCreate** - "Close write gate" (description: "Set CRAFT_WRITE_ENABLED='' after the adhoc work is done.") - set `addBlockedBy` to the work task's ID.

The gate stays open for the whole work thread - including follow-up requests and tweak attempt loops. The pending "Close write gate" task is the closure obligation.

## Step 4: Run the Flow

Read the matching reference file and execute it inline (never via the Skill tool):

- **Fix** -> Read `references/fix.md`
- **Tweak** -> Read `references/tweak.md`

The reference owns the record file, the gate question (confidence vs fit), the edits, and validation. It hands back here for each commit.

**Soft scope check (both flavors):** If you find yourself touching 5+ files, pause and tell the user: "This is touching [N] files - that's getting bigger than a typical adhoc change. Want me to continue or create a story?" Let them decide.

## Step 5: Commit

Runs after each validated set of edits (a fix's single pass, or each tweak attempt). Stage ONLY the files the change touched - never the whole tree. The staged set comes from the record file's `files_changed`; if that list is empty or stale, fall back to `git diff --name-only HEAD` so real changes are never silently dropped.

```bash
cd "${CRAFT_PROJECT_ROOT:-.}"

# Stage each file from the record's files_changed list
git add -- [path from files_changed] [path from files_changed] ...

# Fallback ONLY if files_changed is empty or 0: stage the tracked changes
# git diff --name-only HEAD | while IFS= read -r f; do git add -- "$f"; done

git diff --cached --quiet || git commit -m "fix: [short description]" --no-verify
```

Do NOT use `git add -A` or `git add .` - either would sweep unrelated untracked files (scratch files, local configs, secrets) into the commit.

Commit message prefix: `fix:` for fixes, `tweak:` for tweaks. Example: `tweak: settings icon swapped to hammer, matching toolbar stroke weight`.

## Step 6: Close the Gate

At **thread end** - the fix validated, or the tweak record reached accepted/abandoned/escalated, or the user has visibly moved on:

```bash
# Close the write gate
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh CRAFT_WRITE_ENABLED "" "${CRAFT_PROJECT_ROOT:-.}"

# Remove safety marker
rm -f "${CRAFT_PROJECT_ROOT:-.}/.craft/.active-fix"
```

Then complete both tasks (work task, then "Close write gate").

A tweak record left `status: open` does NOT keep the gate open - the record's openness is bookkeeping in `.craft/tweaks/`; the gate closes with the thread. Cross-session state lives ONLY in the record.
