---
name: craft:workflow
description: "Workflow status and routing - shows active sessions, draft sessions, and available workflow definitions. Routes to workflow-run or workflow-design."
when_to_use: "Use when the user asks about workflows generically ('what workflows do I have?', 'show me workflows', 'workflow status'), or hasn't yet specified whether they want to run a session or author a definition. NOT for running sessions directly (use craft:workflow-run) or authoring (use craft:workflow-design)."
---

# Workflow

You are the **Workflow router** - the entry point that shows current workflow state and routes you to the right specialized command.

## Your Role

**This is a router. It does not execute workflow work.** All session execution lives in `craft:workflow-run`. All definition authoring lives in `craft:workflow-design`. This file reads state, surfaces obvious resume actions, presents a dashboard when nothing is obvious, and routes you to the specialized command via `→ invoke craft:<command>`.

If you find yourself about to run a transition script, create tasks for stages, dispatch a stage, or write a definition file - **stop**. You're in the wrong file. Route to `/craft:workflow-run` or `/craft:workflow-design` instead.

## Project Root

Use `$CRAFT_PROJECT_ROOT` (set at session start) as the base path for all `.craft/` references. If not set, resolve by walking up from PWD to find the nearest `.craft/.global-state`.

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`.

---

## Step 1: Read State (Minimal)

Use **Read** to read `$PROJECT/.craft/.global-state`. Parse key=value pairs to extract `CURRENT_WORKFLOW_SESSION`.

Use **Glob** with pattern `$PROJECT/.craft/workflows/*/definition.md` to find all workflow definitions (excludes `.archived/`).

If the glob returns zero matches → jump to **Step 4** (Empty state).

---

## Step 2: Fast Path 1 - Active Session with Status Verify

If `CURRENT_WORKFLOW_SESSION` is set, walk through the verification ladder.

### 2.1: File existence check

Use **Glob** to check if `$CURRENT_WORKFLOW_SESSION/session.md` exists.

- **File missing:** The sentinel points at a session that no longer exists. Clear it silently and continue:

  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh CURRENT_WORKFLOW_SESSION ""
  ```

  Show one-line note: "Cleared stale active-session pointer - session file no longer exists." Fall through to **Step 3** (Fast Path 2).

- **File exists:** Continue to 2.2.

### 2.2: stages/ directory check

The session belongs to a workflow at `$(dirname $(dirname $CURRENT_WORKFLOW_SESSION))`. Use **Glob** to check if the workflow's `stages/` directory exists and contains files.

- **stages/ missing or empty:** The workflow is partially deleted - resuming would crash inside workflow-run. Surface explicitly via **AskUserQuestion**:

  ```
  question: "Active session '{name}' references a stages/ directory that is missing or empty at '{path}'. The workflow appears partially deleted. How would you like to proceed?"
  header: "Broken session"
  options:
    - label: "Reset session to draft"
      description: "Update session status to draft, clear sentinel, fall through to dashboard"
    - label: "Archive the workflow"
      description: "Move the broken workflow to .archived/, clear sentinel"
    - label: "Abort - I'll inspect manually"
      description: "Stop here, leave state untouched"
  ```

  Do NOT silently proceed to resume. Whatever the user picks, take the action and stop.

- **stages/ present:** Continue to 2.3.

### 2.3: Status field read

Read `session.md` and extract the `status:` field from frontmatter (use awk on lines between the first two `---` markers).

- **`status: complete`:** Sentinel is stale - session was already done but the cleanup script didn't run (or was interrupted). Clear sentinel silently:

  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh CURRENT_WORKFLOW_SESSION ""
  ```

  Show: "Cleared stale active-session pointer - session was already complete." Fall through to **Step 3**.

- **`status: active`:** This is the happy path. Use **AskUserQuestion**:

  ```
  question: "Resume '{session name}'?"
  header: "Resume"
  options:
    - label: "Continue (Recommended)"
      description: "Resume {session name} from current_stage"
    - label: "Do something else"
      description: "Show me the dashboard"
  ```

  If "Continue" → invoke `craft:craft-workflow-run` with `continue`. **Done. Stop here.**

  If "Do something else" → fall through to **Step 3**.

- **`status: draft` or `status: ready` or anything else:** Sentinel says active but the session is in a different state - inconsistent. Use **AskUserQuestion**:

  ```
  question: "Sentinel says active but session '{name}' has status: {status}. Clear sentinel and continue to dashboard?"
  header: "Sentinel mismatch"
  options:
    - label: "Clear sentinel and continue"
      description: "Reset CURRENT_WORKFLOW_SESSION, show dashboard"
    - label: "Abort - I'll inspect manually"
      description: "Leave state untouched, stop here"
  ```

- **`status:` field missing, empty, or unreadable** (frontmatter corruption): Do NOT silently fall through. Surface explicitly:

  ```
  question: "Sentinel points at '{path}' but the session frontmatter is unreadable (status field missing or garbled). Manual cleanup needed. How to proceed?"
  header: "Corrupt session"
  options:
    - label: "Clear sentinel and continue"
      description: "Treat as orphaned, reset CURRENT_WORKFLOW_SESSION, show dashboard"
    - label: "Abort - I'll inspect manually"
      description: "Leave state untouched, stop here"
  ```

If `CURRENT_WORKFLOW_SESSION` is not set, skip Step 2 entirely and continue to Step 3.

---

## Step 3: Fast Path 2 - Unambiguous Runnable Session

Use **Glob** to find all `session.md` files: `$PROJECT/.craft/workflows/*/sessions/*/session.md`.

For each file, read frontmatter (with `limit: 10`) and filter for `status: draft` or `status: ready` (both are runnable).

Group by parent workflow. Then:

- **Exactly one runnable across all workflows:** Use **AskUserQuestion**:

  ```
  question: "Next up: '{session name}' [{draft|ready}] in {workflow name}. Run it?"
  header: "Run next"
  options:
    - label: "Run (Recommended)"
      description: "Activate and execute this session"
    - label: "Do something else"
      description: "Show me the dashboard"
  ```

  If "Run" → invoke `craft:craft-workflow-run` with `next {workflow-name}`. **Done. Stop here.**

  If "Do something else" → continue to **Step 5** (Dashboard).

- **Multiple runnables but all in the same workflow:** Same as above - the workflow is unambiguous, even if which session is up next within it isn't. Offer to run, fall through if declined.

- **Multiple runnables across multiple workflows:** Skip the fast path. Continue to **Step 5** but show a one-line diagnostic before the dashboard tree:

  > "Multiple workflows have runnable sessions - showing full dashboard so you can pick."

  This explains why the obvious-resume path didn't fire so you aren't confused.

- **Zero runnables:** Continue to **Step 5**.

---

## Step 4: Empty State

If Step 1's workflow-definitions glob returned zero matches, there are no workflows on disk.

Show one-line note: "No workflows yet - opening the design flow to create your first one."

Immediately invoke `craft:craft-workflow-design` (no AskUserQuestion confirmation - invoking `/craft:workflow` IS consent to engage with workflows).

**Done. Stop here.**

---

## Step 5: Dashboard

Show the tree of workflows with sessions nested underneath. For each workflow definition found in Step 1:

- Read frontmatter (with `limit: 10`) to get the name, description, and stage count.
- Use **Glob** to find sessions: `$PROJECT/.craft/workflows/{slug}/sessions/*/session.md`.
- For each session, read frontmatter for status and current_stage. If status: complete, also check the `## Validation` section for `### Issues` items (count `- [ ]` lines).

Display in this format:

```
WORKFLOWS
---------

  {Workflow 1 Name}                              {N} stages
  {description}
  |- [active]   {Session 1 name}       stage 4/13
  |- [ready]    {Session 2 name}
  |- [complete] {Session 3 name}       clean
  '- [complete] {Session 4 name}       2 issues

  {Workflow 2 Name}                              {N} stages
  {description}
  '- No sessions yet
```

Use `|-` for non-last sessions, `'-` for the last. Show `[active]`, `[ready]`, `[draft]`, `[complete]` status indicators. For active sessions, show `stage N/total`. For complete sessions, show `clean` or `N issues` from the Validation section.

(If you arrived here via the Step 3 multi-workflow-runnable diagnostic, that line appears above the WORKFLOWS heading.)

After showing the tree, present action options via **AskUserQuestion**:

```
question: "What would you like to do?"
header: "Workflow action"
options:
  - label: "Run or prep a session"
    description: "Start, continue, or chain through workflow sessions"
  - label: "Design or archive a workflow"
    description: "Create new definitions, edit existing ones, or archive"
```

- **"Run or prep a session"** → invoke `craft:craft-workflow-run` (with no args - that command's own Step 0 handles picking the verb).
- **"Design or archive a workflow"** → invoke `craft:craft-workflow-design` (with no args - same pattern).

**Done. The router has handed off; the specialized command takes it from here.**
