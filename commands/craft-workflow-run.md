---
name: workflow-run
description: "Run a session of an existing workflow - start, continue, advance stages, run-all, batch-create sessions, mark ready."
argument-hint: "[run <name> | continue | next <name> | run-all <name> | batch <name> | ready <name>]"
when_to_use: "Use when the user wants to execute workflow work: 'run the workflow', 'continue the workflow', 'next session', 'run all remaining sessions', 'batch create sessions', or 'mark sessions ready'. NOT for authoring or archiving workflow definitions (use craft:workflow-design)."
---

# Workflow Run

Execute a session of an existing workflow. Owns the full session lifecycle: starting new sessions, continuing active ones, advancing through stages, batch-creating drafts, marking drafts ready, and chaining all runnable sessions.

---

⛔ **CRITICAL: ALWAYS USE TASKCREATE FOR STAGE PROGRESS**

When executing a session, you MUST call **TaskCreate** for every stage in the workflow before starting Stage 1. This produces the live progress checklist that you and the user both see in the terminal UI. Narrating stage advances in prose without TaskCreate is NOT acceptable - the user has no progress signal, you have no compaction-recoverable state, and the system has no record of where you are.

---

⛔ **CRITICAL: ALWAYS CALL THE TRANSITION SCRIPTS**

For every state transition, invoke the appropriate script via the Bash tool. Never use Edit/Write/sed to modify `session.md` frontmatter or stage status tags directly:

- `start-workflow-session.sh <session-dir>` - activate a new session
- `complete-workflow-stage.sh <session-dir> <stage-num> [notes]` - mark a stage complete and advance
- `complete-workflow-session.sh <session-dir>` - finalize a session with validation

The scripts contain guards (sibling-active check, format integrity, sentinel updates) that direct edits bypass. Bypassing the scripts is how parallel sessions and corrupt state happen.

---

⛔ **CRITICAL: NEVER RUN TWO SESSIONS IN PARALLEL**

The `start-workflow-session.sh` script enforces a per-workflow sibling-active guard. If you try to start a session while a sibling session is already active in the same workflow, the script exits 1 with an error naming the blocking session. Respect it.

---

⛔ **IF THE SIBLING-ACTIVE GUARD EXITS 1, STOP**

When `start-workflow-session.sh` exits 1 with the sibling-active error, surface the error verbatim to the user and STOP. Do NOT bypass it. Do NOT manually clear sibling state. Do NOT suggest workarounds. The sibling session must be completed or paused by the user before another can start. This is the single most important safeguard against state corruption.

---

⛔ **FORMAT IS STAGES-V1 ONLY**

Every workflow definition in this version uses stages-v1 format: a `definition.md` routing table plus per-stage files in `stages/NN-slug.md`. Do NOT add format-detection branches or fallback code paths for legacy definition layouts. If you encounter a workflow without a `stages/` directory, surface the issue to the user; do not try to handle it.

---

## Project Root

Use `$CRAFT_PROJECT_ROOT` (set at session start) as the base path for all `.craft/` references. If not set, resolve by walking up from PWD to find the nearest `.craft/.global-state`.

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`.

## Format Reference

For the definitive specification of workflow definition frontmatter, stage file structure, session frontmatter, and Progress table format, see `${CLAUDE_PLUGIN_ROOT}/commands/references/workflow-formats.md`. That file is a cold-path schema lookup - read it when you need to verify the shape of a frontmatter field or the exact format of the Progress table. All procedural steps for executing a session live in this file, not the schema reference.

---

## Step 0: Determine Verb

Parse args to determine which verb to execute:

- **`run {name}`** -> Step 1 (create new session, then execute)
- **`continue`** -> Step 1g (resume active session, then execute from current stage)
- **`next {name}`** -> Step 1d (find next runnable session, activate it, execute)
- **`run-all {name}`** -> Step 1e (chain through all runnable sessions in order)
- **`batch {name}`** -> Step 1b (create multiple draft sessions, no execution)
- **`ready {name}`** -> Step 1f (transition selected draft sessions to ready)
- **No args** -> AskUserQuestion: "What would you like to do?" with options mapping to the verbs above

---

## Step 1: Create New Session (`run` verb)

### 1.1: Select Workflow

If workflow name provided in args, use it. Otherwise, list available workflows and let the user pick via AskUserQuestion.

Read the workflow's `definition.md` to get variables and stage list.

### 1.2: Name and Configure Session

Ask for a session name (e.g., "MCP Course", "Auth Service Audit").

For each variable in the workflow's definition, ask for the value:

> **Fill in workflow variables:**
> - `{var1}` ({description}):
> - `{var2}` ({description}):

### 1.3: Choose Run Mode

Use **AskUserQuestion**:

```
question: "How do you want to run this session?"
header: "Run mode"
options:
  - label: "Interactive (Recommended)"
    description: "Step through each stage, confirm before advancing"
  - label: "Auto"
    description: "Run all stages automatically, pause only at manual gates"
  - label: "Draft only"
    description: "Create the session file but don't start yet"
```

### 1.4: Write Session File

Create the session and artifacts directories using Bash:

```bash
mkdir -p "$PROJECT/.craft/workflows/{workflow-slug}/sessions/{date}-{session-slug}"
mkdir -p "$PROJECT/.craft/workflows/{workflow-slug}/sessions/{date}-{session-slug}/artifacts"
```

Write `session.md` with the hybrid format (see `${CLAUDE_PLUGIN_ROOT}/commands/references/workflow-formats.md` New Session Format Reference for the exact schema). The session contains:

- **Frontmatter:** workflow, name, status, mode, started, completed, current_stage, variables (including system variable `session_dir` set to the full session directory path)
- **H1 title**
- **`## Progress` table:** one row per stage with columns `#`, `Stage`, `Status`, `Completed`, `Notes`. All stages start with status `pending`. Stage names are read from the definition's `## Stages` routing table.
- **Per-stage checklist sections:** for each stage, read the `## Checklist` from its stage file and copy items into the session as `## Stage N: {Name} [pending]` with `- [ ]` items. Variable substitution on checklist items happens at this point.

No prompts in the session - those stay in stage files and are loaded on demand at dispatch.

**Variable substitution:** Replace all `{variable}` placeholders in checklist items with the session's variable values.

### 1.5: Activate or Draft

- **If "Draft only":** Done. Show the session file path. Stop here.
- **If "Interactive" or "Auto":** Run `start-workflow-session.sh {session-dir}` to set status to active and inject `session_dir` into variables. The script enforces the sibling-active guard - if another session in this workflow is already active, the script exits 1; surface the error and stop. After successful activation, jump to **Step 2** (TaskCreate setup).

---

## Step 1b: Batch Create Sessions (`batch` verb)

Create multiple sessions as `draft` in one pass. No execution.

### 1b.1: Select Workflow

Same as Step 1.1.

### 1b.2: Collect Variable Sets

Ask the user for a list of variable sets. Two input modes:

**List mode** (most common): User provides a comma-separated or newline-separated list of the primary variable. The orchestrator infers the rest from the definition's defaults or from context.

Example:
> Provide the lesson IDs to create sessions for:

User: `mcp-u1-l3, mcp-u1-l4, mcp-u2-l1, mcp-u2-l2`

The orchestrator derives the other variables from each lesson ID (course_id from prefix, unit_number from u-number, etc.) per the workflow's defaults.

**Table mode** (full control): User provides all variables per session as a structured list.

### 1b.3: Create All Sessions

For each variable set:
1. Create the session directory AND `artifacts/` subdirectory
2. Write `session.md` with `status: draft` per the hybrid format
3. Do NOT prompt for run mode - all sessions are draft

After all sessions are created, display:

```
Batch created: {N} sessions for {workflow name}

  [draft] {Session 1 name}
  [draft] {Session 2 name}
  ...

All sessions are draft. Use /craft:workflow-run ready {workflow-name} to mark them ready,
or /craft:workflow-run next {workflow-name} to run them one at a time.
```

**Done.** No execution, no follow-up prompts.

---

## Step 1c: Find Next Runnable Session (Shared Helper)

Shared logic used by `continue`, `next`, and `run-all` to pick the next session.

1. Use **Glob** to find all `session.md` files for the specified workflow: `$PROJECT/.craft/workflows/{slug}/sessions/*/session.md`.
2. Read each session's frontmatter (with `limit: 10`) to get status.
3. Filter for sessions with `status: draft` or `status: ready` (both are runnable).
4. Sort: `ready` before `draft`, then by date prefix ascending, then alphabetical.
5. Return the first match.

**Session priority:** `ready` sessions are picked before `draft` sessions. This means `/craft:workflow-run ready` is useful for prioritizing a subset - but the system does not refuse to run a draft.

**Activation:** Run `start-workflow-session.sh` to transition the session to `active`. The script enforces the sibling-active guard.

---

## Step 1d: Run Next Session (`next` verb)

**Invocation:** `/craft:workflow-run next <workflow-name>`

No-prompt shortcut: finds the next runnable session, activates it, runs to completion, then stops.

1. Use Step 1c to find the next runnable session for the specified workflow.
2. If none found: "No draft or ready sessions for {workflow-name}." Stop.
3. Count total remaining runnable sessions for context.
4. Show: "Activating session: {name} ({M} of {N} remaining)"
5. Activate via `start-workflow-session.sh` (respect sibling-active guard).
6. Execute per **Steps 2-5** (TaskCreate, execute stages, transition, finalize).
7. On completion, show: "Session complete. {N-1} sessions remaining. Run `/craft:workflow-run next {name}` for the next one."
8. **Stop.** Do not auto-advance to the next session.

---

## Step 1e: Run All Sessions (`run-all` verb)

**Invocation:** `/craft:workflow-run run-all <workflow-name>`

Chains through all runnable sessions in sequence. Only stops when no sessions remain or the user interrupts.

1. If an active session exists for this workflow, resume it first (same as `continue`).
2. Use Step 1c to count all runnable sessions. Add 1 if resuming an active session.
3. If none (no active, no runnable): "No sessions to run for {workflow-name}." Stop.
4. Show: "Running {N} sessions for {workflow-name} in sequence."
5. For each session:
   a. If not already active, activate via `start-workflow-session.sh`.
   b. Show: "Starting session {M}/{N}: {name}"
   c. Execute per **Steps 2-5**.
   d. On completion, run `complete-workflow-session.sh`, show validation.
   e. Use Step 1c to find next runnable session.
   f. If found, continue. If none, done.
6. Final summary: "All {N} sessions complete for {workflow-name}."

**Interruption:** If the user stops mid-session, the active session stays active. Resume with `/craft:workflow-run continue` or `/craft:workflow-run run-all {name}` (finishes active + chains remaining).

At manual gates within each session, the orchestrator pauses as normal. Sequential chaining only auto-advances *between* sessions, not within them.

**Enforced by script:** `start-workflow-session.sh` will exit 1 if another session in the same workflow is already active. The script is the gate.

---

## Step 1f: Mark Sessions Ready (`ready` verb)

**Invocation:** `/craft:workflow-run ready <workflow-name>`

Transitions sessions from `draft` to `ready`.

### 1f.1: Find Draft Sessions

Use **Glob** to find all sessions for the specified workflow. Filter for `status: draft`.

If no draft sessions found, report: "No draft sessions for {workflow name}." Stop.

### 1f.2: Select Sessions

Use **AskUserQuestion**:

```
question: "Which sessions to mark ready?"
header: "Mark ready"
multiSelect: true
options:
  - label: "All {N} draft sessions"
    description: "Mark everything ready for execution"
  - label: "{Session 1 name}"
    description: "draft"
  - label: "{Session 2 name}"
    description: "draft"
```

### 1f.3: Update Sessions

For each selected session, update `session.md` frontmatter: `status: ready`.

Display:

```
Marked ready: {N} sessions

  [ready] {Session 1 name}
  [ready] {Session 2 name}

Run /craft:workflow-run next {workflow-name} to start executing.
```

**Done.** No execution.

---

## Step 1g: Continue Active Session (`continue` verb)

Find the active session and resume it.

1. Use **Glob** to find all `session.md` files: `$PROJECT/.craft/workflows/*/sessions/*/session.md`.
2. Read each with `limit: 10` to check frontmatter. Filter for `status: active`.

**If an active session exists:** Auto-select (or pick via AskUserQuestion if multiple). Jump to **Step 2** (TaskCreate setup) and resume execution from `current_stage`.

**If NO active session exists:** Check for runnable sessions (draft or ready) across all workflows using Step 1c logic.

If runnable sessions found, show the next one and offer to activate:

> "No active session. Next up: **{session name}** [{draft|ready}] in {workflow name}"

Use **AskUserQuestion**:

```
question: "No active workflow session. {N} runnable sessions remaining. Next up: {session name}"
header: "Continue"
options:
  - label: "Activate next and run"
    description: "Run {session name}, stop after it completes"
  - label: "Run all in sequence"
    description: "Chain through all {N} remaining sessions"
  - label: "Pick a different one"
    description: "Choose which session to run"
```

- **"Activate next and run":** Run `start-workflow-session.sh` for that session, execute per Step 2-5. After session completes, stop.
- **"Run all in sequence":** Behave as `run-all` (Step 1e).
- **"Pick a different one":** List all non-complete sessions, let user select via AskUserQuestion. Activate the chosen session and proceed.

If no runnable sessions found: "No active, draft, or ready sessions found." Stop.

---

## Step 2: Create Tasks for Live Progress Tracking

**Use the built-in Task tools to create a live checklist visible in the terminal UI.** This is the primary progress display - not custom text output.

Read the workflow's `definition.md` `## Stages` routing table. Each row gives the stage number, name, execution mode, and file path.

For each stage, call **TaskCreate**:

```
TaskCreate({
  subject: "Stage {N}: {Name}",
  description: "{execution mode} | {one-line stage description}",
  activeForm: "Running Stage {N}: {Name}"
})
```

Then set up dependencies with **TaskUpdate**:

```
TaskUpdate({
  taskId: "{stage-2-id}",
  addBlockedBy: ["{stage-1-id}"]
})
```

This produces a persistent, visible checklist that:

- Shows completed/in-progress/pending status for every stage
- Updates in real-time as stages advance
- Survives context compaction (recover state via TaskList)
- Is visible to both the agent and the user at all times

Set Stage 1 to `in_progress` immediately after creating all tasks (or set the resume stage to `in_progress` if continuing).

**After context compaction or session restart:** Call **TaskList** to recover current workflow state. The task with `status: in_progress` is the current stage. All `completed` tasks are done stages. This replaces the need to re-read session.md for live state.

---

## Step 3: Execute Current Stage

### 3.1: Load Stage Details

1. Read the routing table from `definition.md` `## Stages` to find the stage file path for the current stage number.
2. Read the stage file (e.g., `stages/03-domain-map.md`).
3. Extract execution mode, agent, prompt, produces, consumes, human_gate from the stage file frontmatter and body.

### 3.2: Artifact Dependency Check (Fail Fast)

If the stage has a non-empty `consumes:` list:

1. Substitute `{session_dir}` in each path with the session's directory.
2. Verify each consumed artifact exists on disk using Glob or Read.
3. If ANY consumed artifact is missing, **do not dispatch the stage.**

Report:
> "Stage {N} requires artifact `{path}` from a prior stage, but it doesn't exist. The prior stage may not have produced output, or artifact capture was skipped."

Use AskUserQuestion to let the user re-run the prior stage or provide the artifact manually.

### 3.3: Variable Substitution

Substitute all `{variable}` placeholders in the stage file content using the session's `variables:` frontmatter values PLUS the system variable `{session_dir}` (the full path to this session's directory). This is on-the-fly substitution - the stage file on disk stays as a template.

### 3.4: Dispatch by Execution Mode

**If `agent`:**

1. Substituted `## Prompt` section becomes the agent prompt.
2. Spawn the specified agent via the Agent tool.
3. When agent completes, check output for success indicators.
4. **Artifact capture:** Write the agent's output to `{session_dir}/artifacts/NN-{stage-slug}.md`. This makes the output available to downstream stages that declare it in their `consumes:` frontmatter.
5. Mark checklist items as complete in session.md.
6. **Interactive mode:** If the stage has a `human_gate:`, present it as an AskUserQuestion (see human_gate AskUserQuestion below). Otherwise, show agent results and ask "Ready to proceed to Stage {N+1}?"
7. **Auto mode:** Advance automatically. `human_gate:` is ignored.

**If `inline`:**

1. Substituted body (everything after frontmatter) becomes the orchestrator's instructions.
2. Execute the instructions directly - read files, make edits, run commands, etc. You have full workflow context including all prior stage results.
3. When complete, mark checklist items as complete.
4. **Artifact capture:** Write a summary of what you did to `{session_dir}/artifacts/NN-{stage-slug}.md` (files modified, decisions made, key outputs).
5. **Interactive mode:** If the stage has a `human_gate:`, present it. Otherwise, ask "Ready to proceed to Stage {N+1}?"
6. **Auto mode:** Advance automatically.

**If `manual`:**

1. Display the stage description and checklist.
2. **Artifact requirement check:** If this stage has a non-empty `produces:` or any downstream stage's `consumes:` references this stage's artifact, inform the user: "This stage's output is needed by a later stage. When you're done, paste or describe your output so I can write it to `{session_dir}/artifacts/NN-{stage-slug}.md`."
3. Present: "This stage requires your input. Mark items as you complete them."
4. Use **AskUserQuestion**:

```
question: "Stage {N}: {Name} - What's the status?"
header: "Stage status"
options:
  - label: "Complete"
    description: "All items done, advance to next stage"
  - label: "In progress"
    description: "Still working, pause here"
  - label: "Skip"
    description: "Skip this stage (flagged in validation)"
```

5. **If "Complete" and artifact is required:** Ask the user for their output and write it to the artifact file BEFORE transitioning. The `complete-workflow-stage.sh` script will verify it exists.

**If `command`:**

1. **Write breadcrumb** before invoking the skill (see Breadcrumb Pattern below):

```bash
cat > "${CRAFT_PROJECT_ROOT:-.}/.craft/.continuation" << CRUMB
ACTION: Continue workflow session "{session-name}" from stage {N+1}
SKILL: craft:craft-workflow-run
ARGS: continue
WRITTEN_BY: craft-workflow-run
TIMESTAMP: $(date -u +%Y-%m-%dT%H:%M:%S)
CRUMB
```

2. Invoke the specified craft command via the **Skill** tool.
3. When the command completes, the stop hook reads the breadcrumb and re-invokes `/craft:workflow-run continue`.
4. The orchestrator loads the session, sees the stage is done, marks it complete, and advances.

**`human_gate:` AskUserQuestion** (used by `agent` and `inline` types in interactive mode):

```
question: "{human_gate description from stage file}"
header: "Review"
options:
  - label: "Approve and continue"
    description: "Output looks good"
  - label: "Needs work"
    description: "Provide feedback, re-run stage"
  - label: "I'll handle it manually"
    description: "Skip automation, do it myself"
```

If "Approve" -> advance. If "Needs work" -> get feedback, re-run stage. If "Manually" -> switch to manual for this stage only.

---

## Step 4: Stage Transition (MANDATORY - BOTH SCRIPT AND TASKS)

After completing a stage, do BOTH. Do not skip either.

**1. Run the transition script** (updates session.md - the permanent record):

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/complete-workflow-stage.sh "{session-dir}" {stage-number} "{optional notes}"
```

Example:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/complete-workflow-stage.sh ".craft/workflows/write-lesson/sessions/2026-04-10-mcp-u1-l3" 3 "5 violations found, all fixed"
```

The script updates the Progress table row (status -> complete, adds date and notes), checks `- [ ]` items in the stage's checklist section, updates stage heading status tags, increments `current_stage`, marks next stage active in both the Progress table and checklist heading. Also verifies artifact existence for non-manual stages with `produces:`.

**2. Update Tasks** (updates live UI - what you and the user see):

```
TaskUpdate({ taskId: "{completed-stage-task-id}", status: "completed" })
TaskUpdate({ taskId: "{next-stage-task-id}", status: "in_progress" })
```

**If the script reports "ALL STAGES COMPLETE":** Jump to Step 5 (Session Finalization).

**Otherwise:**

- **Interactive mode:** Pause for the human_gate AskUserQuestion (if any) or "Ready to proceed?" before continuing to next stage.
- **Auto mode:** Continue to next stage immediately. Loop back to Step 3.

---

## Step 5: Session Finalization

When all stages report complete, run the finalization script:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/complete-workflow-session.sh "{session-dir}"
```

The script:

- Counts stages by status from the Progress table
- Counts checklist items checked vs unchecked
- Verifies artifacts exist for all non-manual stages with `produces:` declared
- Writes a `## Validation` section to session.md with `status: clean` or `passed-with-issues`
- Updates frontmatter: `status: complete`, `completed: {today}`
- Clears `CURRENT_WORKFLOW_SESSION` from `.global-state`

Read the script's stdout to see the validation report.

**If validation is clean:** Show "Session complete. All clean."

**If passed-with-issues:** Show the issue list. Ask the user whether to address them or leave for later.

Mark all remaining Task entries as `completed`. Show:

> "Session complete: {session name}. {N} stages done. {Validation summary}."

---

## Step 6: Session Interruption

If the user needs to stop mid-session:

- The session stays `active` with `current_stage` pointing to where they stopped.
- `/craft:workflow-run continue` picks up exactly here next time.
- No state is lost - everything is in `session.md` and recoverable via TaskList.
- `session-start.sh` surfaces active workflow sessions as a reminder (same pattern as active stories).

---

## Breadcrumb Pattern

For `command`-type stages that invoke skills via the Skill tool, write a breadcrumb before invocation to prevent the orchestrator from stopping after the skill returns.

**Write before invoking the skill:**

```bash
cat > "${CRAFT_PROJECT_ROOT:-.}/.craft/.continuation" << CRUMB
ACTION: Continue workflow session "{session-name}" from stage {N+1}
SKILL: craft:craft-workflow-run
ARGS: continue
WRITTEN_BY: craft-workflow-run
TIMESTAMP: $(date -u +%Y-%m-%dT%H:%M:%S)
CRUMB
```

**Clean up on ALL exit paths** (session complete, user cancels, error):

```bash
rm -f "${CRAFT_PROJECT_ROOT:-.}/.craft/.continuation"
```

**Not needed for:** `agent`-type stages (Agent tool returns inline), `inline`-type stages (orchestrator executes directly), or `manual` stages (AskUserQuestion pauses naturally).

**Safety:** Same guarantees as all craft breadcrumbs - 30-minute TTL, one-shot, session-start cleanup.
