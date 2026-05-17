---
name: craft:docs
description: "Generate or update project documentation using the crystallized doc-writer agent. Two-pass: brief (analysis + plan) then generate (write docs). Detects first-run vs update automatically."
argument-hint: "[continue | --scope=<path>]"
---

# Docs

Generate quality GitHub documentation for any craft project. Uses the crystallized doc-writer agent for both analysis and writing. Two passes - brief then generate - with a human gate in between.

## Project Root

Use `$CRAFT_PROJECT_ROOT` (set at session start) as the base path. If not set, resolve by walking up from PWD to find the nearest `.craft/.global-state`.

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`.

## Flow

### Step 0: Determine Run Context

Parse args:

- **"continue"** - Resume from an existing brief. Jump to **Step 3**.
- **"--scope=path"** - Scope the analysis to a subdirectory. Store as `SCOPE`.
- **No args** - Full project analysis.

### Step 1: Detect State

Check what already exists:

```bash
# Check for existing brief
BRIEF="$PROJECT/.craft/docs/brief.md"

# Check for existing docs
README=$(ls "$PROJECT"/README.md "$PROJECT"/README.MD 2>/dev/null | head -1)
DOCS_DIR=$(ls -d "$PROJECT"/docs/ 2>/dev/null)
```

Also check for craft-specific sources of truth:
- `$PROJECT/CLAUDE.md`
- `$PROJECT/.craft/design/locked.md`
- `$PROJECT/.craft/project.md`

**If an unapproved brief exists** (status: draft in frontmatter):

Use **AskUserQuestion**:
```
question: "Found a draft brief from {date}."
header: "Resume"
options:
  - label: "Continue with this brief"
    description: "Review and approve the existing brief"
  - label: "Start fresh"
    description: "Generate a new brief"
```

**If "Continue"** -> Jump to **Step 2e** (Present Brief).
**If "Start fresh"** -> Continue to **Step 2** (Investigate).

**Determine mode based on what exists:**
- No README, no docs/ -> `MODE=first-run`
- README or docs/ exists -> `MODE=update`

### Step 2: Investigate Documentation Health

Create the brief directory:

```bash
mkdir -p "$PROJECT/.craft/docs"
```

#### Step 2a: Gather Context

**For update mode**, gather git changes since the last docs run:

```bash
LAST_DOCS_DATE={date from existing brief frontmatter, e.g. 2026-04-17}
GIT_LOG=$(git log --oneline --since="$LAST_DOCS_DATE" -- . ':!.craft/cycles' ':!.craft/backlog')
GIT_DIFF_STAT=$(git diff $(git log --since="$LAST_DOCS_DATE" --format="%H" --reverse -- . | head -1)^..HEAD --stat -- . ':!.craft/cycles' ':!.craft/backlog' 2>/dev/null || echo "Unable to compute diff stat")
```

**Check for PR review findings:**

```bash
REVIEW_FINDINGS="$PROJECT/.craft/docs/review-findings.md"
```

If the file exists, read its contents. These are known doc-drift issues flagged by `craft:review`.

#### Step 2b: Dispatch Explore Agent

Read the doc standards reference file: `commands/references/doc-standards.md` (from the plugin, not the project). This defines what the Explore agent should look for.

Dispatch an **Explore agent** via the Agent tool with `subagent_type: "Explore"`. The prompt adapts to mode.

**First-run prompt:**

```
You are investigating a project's documentation health. Your job is to find what's
stale, missing, or uncertain - NOT to write the brief. That happens later.

Read the doc standards reference first - it defines what "current" means and how
to handle uncertainty:

[Paste full contents of commands/references/doc-standards.md]

Project root: {PROJECT}
Scope: {SCOPE or "full project"}

{If REVIEW_FINDINGS exists:}
## Known Issues from PR Reviews
The following doc-drift findings were flagged by recent PR reviews. Investigate
each one and include them in your findings, attributed as "flagged by PR review":
{REVIEW_FINDINGS content}

Investigate:
1. Glob for ALL .md files (excluding node_modules, .git, .craft/cycles, .craft/backlog, .craft/research)
2. Read each doc and check claims against the codebase
3. Check CLAUDE.md, .craft/project.md, .craft/design/locked.md for source alignment
4. Look for undocumented subsystems or features

Report your findings using the format defined in the doc standards reference.
Group by confidence level (high first). Be honest about uncertainty.
Report in under 800 words.
```

**Update prompt:**

```
You are investigating documentation drift for a project. Your job is to find what's
stale since the last docs update - NOT to write the brief. That happens later.

Read the doc standards reference first - it defines what "current" means and how
to handle uncertainty:

[Paste full contents of commands/references/doc-standards.md]

Project root: {PROJECT}
Scope: {SCOPE or "full project"}

## Git Changes Since Last Docs Update ({LAST_DOCS_DATE})
### Commit Log
{GIT_LOG}
### Diff Stats
{GIT_DIFF_STAT}

Use these changes as your primary investigation guide. Every commit is a potential
documentation gap. For renames or terminology changes, grep for the OLD term to
find stale references.

{If REVIEW_FINDINGS exists:}
## Known Issues from PR Reviews
The following doc-drift findings were flagged by recent PR reviews. Investigate
each one and include them in your findings, attributed as "flagged by PR review":
{REVIEW_FINDINGS content}

Investigate:
1. Glob for ALL .md files (excluding node_modules, .git, .craft/cycles, .craft/backlog, .craft/research)
2. For each doc, check if the git changes made any of its claims stale
3. Check CLAUDE.md, .craft/project.md, .craft/design/locked.md for source alignment
4. Look for terminology drift between docs and current code

Report your findings using the format defined in the doc standards reference.
Group by confidence level (high first). Be honest about uncertainty.
Every existing doc should appear as either "current" or with specific staleness findings.
Report in under 800 words.
```

**Save the Explore agent's ID** for potential follow-up via SendMessage.

#### Step 2c: Surface Findings via AskUserQuestion

Read the Explore agent's findings. Filter to genuine documentation issues (not editorial preferences). Group them for presentation.

**If zero findings:** Skip to Step 2d with a minimal brief.

**If findings exist:** Present them to the user. Group related findings together:

> "I investigated the docs against the current codebase. Here's what I found:"
>
> **High confidence (verified against code):**
> 1. **[Category]:** [finding summary]. [Evidence.]
> 2. **[Category]:** [finding summary]. [Evidence.]
>
> **Uncertain (could go either way):**
> 3. **[Category]:** [finding summary]. [What I couldn't confirm.]
>
> {If review findings were pre-loaded:}
> **Flagged by PR review:**
> 4. **[Category]:** [finding from review-findings.md]

Use **AskUserQuestion**:
```
question: "I found [N] documentation issues. Which should go into the update brief?"
header: "Doc Health"
options:
  - label: "All of them (Recommended)"
    description: "Include all findings in the brief for the doc-writer"
  - label: "Let me pick"
    description: "I'll select which findings to include"
  - label: "Add context first"
    description: "Some findings need correction or additional context from me"
```

**If "All of them":** All findings enter the brief.
**If "Let me pick":** Use AskUserQuestion with multiSelect to let the user choose.
**If "Add context first":** Let the user provide corrections or context. Update findings accordingly.

**If user's answers expand scope** (e.g., "also check the API docs" or "that whole section is wrong"):

Use **SendMessage** to the same Explore agent:
```
The user provided additional context:
[Summarize what the user said]

Investigate the implications. Same format. Only report NEW findings.
```

Process new findings and surface them. Loop until no new questions remain.

#### Step 2d: Build Brief from Confirmed Findings

After the user confirms which findings to act on, build the brief. The brief is now informed by dialogue, not raw exploration.

Write to `{PROJECT}/.craft/docs/brief.md`:

**First-run brief format:**

```markdown
---
status: draft
created: {YYYY-MM-DD}
mode: first-run
project: {project name}
scope: {scope or full}
---

# Documentation Brief

## Project Understanding
{2-3 paragraphs proving comprehension. Name specific subsystems, patterns,
and architectural choices.}

## Proposed Documentation

### {Doc Title}
- **Type:** {reference | how-to | tutorial | explanation | architecture | ADR}
- **Audience:** {who reads this and what state they're in}
- **Location:** {where this file goes}
- **Key content:** {specific things this doc covers}
- **Diagrams:** {mermaid diagrams planned, with one-line descriptions}

## Source Alignment
{Misalignment between CLAUDE.md, locked.md, project.md, and actual code.}

## User Context
{Any corrections or context the user provided during the dialogue.}
```

**Update brief format:**

```markdown
---
status: draft
created: {YYYY-MM-DD}
mode: update
project: {project name}
scope: {scope or full}
last_docs_modified: {date of most recent doc file change}
---

# Documentation Update Brief

## Health Check
{One line: how stale are the docs?}

## What Changed
{Specific code changes that affect documentation, from git + exploration.}

## Docs to Update
### {Doc filename}
- **What's stale:** {confirmed finding - specific sections or claims}
- **What to change:** {specific updates needed}
- **Source:** {how this was found - exploration, PR review, user context}

## New Docs Needed
### {Doc Title}
- **Type:** {reference | how-to | tutorial | explanation | architecture | ADR}
- **Why now:** {what changed that makes this doc necessary}
- **Location:** {where this file goes - must be in docs/ folder}

## Source Alignment
{Misalignment between CLAUDE.md, locked.md, project.md, and actual code.}

## User Context
{Any corrections or context the user provided during the dialogue.}
```

**If review findings were consumed**, clear the review-findings file:

```bash
rm -f "$PROJECT/.craft/docs/review-findings.md"
```

### Step 2e: Present Brief

Read the brief from `$PROJECT/.craft/docs/brief.md`. Present the full content to the user.

Use **AskUserQuestion**:
```
question: "Here's the documentation brief. How do you want to proceed?"
header: "Brief Review"
options:
  - label: "Approve - generate docs"
    description: "Write all proposed documentation"
  - label: "Approve with notes"
    description: "I have adjustments before you write"
  - label: "Skip items"
    description: "I want to exclude some proposed docs"
  - label: "Cancel"
    description: "Don't generate anything right now"
```

**If "Approve"** -> Update brief status to `approved`. Jump to **Step 3**.
**If "Approve with notes"** -> Let user provide notes. Append to brief under `## User Notes`. Update status to `approved`. Jump to **Step 3**.
**If "Skip items"** -> Let user specify which items to skip. Mark them in the brief. Update status to `approved`. Jump to **Step 3**.
**If "Cancel"** -> Brief stays as `draft` for later. Done.

### Step 3: Dispatch Doc-Writer for Generation

Read the approved brief from `$PROJECT/.craft/docs/brief.md`.

Dispatch the **doc-writer agent** via the Agent tool with `subagent_type: "craft:doc-writer"`:

```
You are writing documentation for a project based on an approved brief.

Project root: {PROJECT}
Brief: {full content of brief.md}

Write every document listed in the approved brief. Follow the brief's guidance on
doc types, audiences, locations, and content.

Rules:
- Generated documentation goes in the `docs/` folder at the project root. Do NOT
  write to `reference/` (orchestration-critical files only) or `commands/references/`
  (command-specific execution files only). If the brief specifies a location in
  `reference/`, redirect to `docs/` instead.
- Write to the file locations specified in the brief (subject to the docs/ constraint above)
- Include mermaid diagrams where the brief planned them
- Match the project's existing voice (read CLAUDE.md, existing docs, commit messages)
- Code samples must be real - pulled from actual project code, not invented
- Every doc must work as "page one" - a reader arriving from a search engine
  must be able to orient without reading anything else first
- Do not write docs the brief marked as skipped
- For update mode: edit existing docs surgically, don't rewrite from scratch
  unless the brief says to. Flag stale sections, don't silently replace them.
- After writing all docs, list every file you created or modified
```

### Step 4: Report

After the agent completes, present the results:

```
DOCUMENTATION
-------------

  {filename}                    {type}        {new | updated}
  {filename}                    {type}        {new | updated}
  ...

Brief: .craft/docs/brief.md
```

Update the brief frontmatter: `status: complete`, add `completed: {YYYY-MM-DD}`.

Done.
