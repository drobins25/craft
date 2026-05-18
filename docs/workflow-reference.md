# Workflow Reference

> How `/craft:workflow` works - formats, stage types, artifact handoff, and session lifecycle.

This page covers the workflow system holistically. The `commands/references/` files are operational instructions for the orchestrator. This page is for you - a human trying to understand or design a workflow.

---

## What a Workflow Is

A workflow is a named multi-step process you define once and run many times with different input variables. Each step can be:

- **agent** - the orchestrator spawns an isolated agent with a prompt
- **inline** - the orchestrator executes directly with full workflow context
- **manual** - a human step (the workflow pauses and waits)
- **command** - the orchestrator invokes a craft command via the Skill tool

This is different from a story + chunks. Stories are single-feature units of implementation work. Workflows are repeatable processes - research pipelines, documentation cycles, review rituals, content generation runs.

---

## Two Formats

Workflows exist in two formats. The format is detected automatically from the presence of a `stages/` directory.

### Monolithic Format

All stage definitions live in `definition.md`. Good for short workflows (3-5 stages) where the entire definition fits comfortably in one file.

```
.craft/workflows/
  my-workflow/
    definition.md    # All stages here
    sessions/
      2026-04-10-run1/
        session.md
```

Stage metadata and prose are co-located in `definition.md`:

```markdown
## Stage 1: Research
execution: agent
agent: craft:researcher
prompt: "Research {topic} focusing on {domain}"
produces: .craft/research/{topic}/
requires: []

Description of what this stage does and why it matters.

- [ ] Completion criterion 1
- [ ] Completion criterion 2
```

### stages-v1 Format

Each stage lives in its own file in `stages/`. The `definition.md` becomes a routing table. Good for longer workflows (6+ stages) and when stages have substantial per-stage documentation.

```
.craft/workflows/
  my-workflow/
    definition.md    # Routing table only
    stages/
      01-research.md
      02-landscape.md
      03-synthesis.md
    sessions/
      2026-04-10-run1/
        session.md
        artifacts/
          01-research-output.md
          02-landscape-map.md
```

The `definition.md` routing table:

```markdown
## Stages

| # | Name | Execution | File | Produces |
|---|------|-----------|------|----------|
| 1 | Research | agent | stages/01-research.md | .craft/research/{topic}/ |
| 2 | Landscape | inline | stages/02-landscape.md | |
| 3 | Synthesis | manual | stages/03-synthesis.md | |
```

Each stage file is self-contained:

```markdown
---
stage: 1
name: Research
execution: agent
agent: craft:researcher
produces: .craft/research/{topic}/
consumes: []
human_gate: ""
---

# Stage 1: Research

What this stage does and why it matters. Variable placeholders like
{topic} and {domain} are substituted at dispatch time.

## Prompt

Research {topic} for {domain}. Focus on evidence-based approaches.

## Checklist

- [ ] Research branches produced
- [ ] Expert agent crystallized

## Artifacts

- **Produces:** `.craft/research/{topic}/`
- **Consumes:** (none - first stage)
```

---

## Artifact Handoff (stages-v1)

The key capability of stages-v1 is structured artifact handoff between stages. A stage can declare what it `consumes` from prior stages using `{session_dir}` as a reference to the current session's artifact directory.

```markdown
---
stage: 3
name: Synthesis
execution: inline
produces: {session_dir}/artifacts/03-synthesis.md
consumes:
  - "{session_dir}/artifacts/01-research-output.md"
  - "{session_dir}/artifacts/02-landscape-map.md"
---
```

At dispatch time, the orchestrator reads the artifact files listed in `consumes` and includes their content in the stage prompt. This replaces the problem of trying to pass rich outputs through conversation history across session compaction boundaries.

**Why this matters:** Agent sessions are finite. Context compacts. If Stage 5 needs the detailed output of Stage 1, storing it in the artifact directory and declaring it in `consumes` guarantees it survives compaction. The artifact path is the handoff contract - not conversation memory.

---

## Stage Types in Detail

### agent

The orchestrator spawns an isolated agent with the stage's prompt. The agent has no access to workflow state or session history - it gets only what's in the prompt plus its normal tool access.

```yaml
execution: agent
agent: craft:researcher
prompt: "Research {topic} in the context of {domain}"
```

Use when: the task benefits from isolated context (exploration, research, analysis). Context isolation prevents prior stage outputs from polluting the agent's reasoning.

### inline

The orchestrator executes the stage directly, with full workflow context visible. No isolated agent is spawned.

```yaml
execution: inline
prompt: "Synthesize the findings from Stage 1 into a landscape map"
```

Use when: the task needs awareness of prior stage outputs and workflow variables that are already in context. Inline stages are faster (no agent spawn overhead) and can reference artifacts directly.

### manual

The workflow pauses and waits for a human action. The orchestrator shows the stage description as instructions and asks the user to confirm completion.

```yaml
execution: manual
```

Use when: there's a human review step, an external action required (stakeholder approval, external tool run), or a decision that should not be automated.

### command

The orchestrator invokes a craft command via the Skill tool. A breadcrumb is written before invocation to prevent the orchestrator from stopping after the skill returns.

```yaml
execution: command
command: craft:research-verify
args: "{topic}-domain-map"
```

Use when: a stage is best served by an existing craft command (research verification, story creation, review).

---

## human_gate

Any stage type can declare a `human_gate`. In interactive mode, the orchestrator presents an AskUserQuestion after the stage completes before moving to the next stage. In auto/batch mode, `human_gate` is ignored.

```yaml
human_gate: "Review the landscape map before proceeding to domain mapping"
```

This is useful for checkpoints in long automated workflows where a human review at a specific inflection point is optional but valuable.

---

## Variables

Workflows declare variables in their frontmatter. Variables substitute into stage prompts, produces paths, and checklist items at runtime using `{variable}` syntax.

```yaml
variables:
  topic: "the research topic"
  domain: "the application domain"
  project: "which project this applies to"
```

Variables are set when a session is created. The orchestrator substitutes them throughout the stage files before dispatching each stage.

---

## Session Lifecycle

```
create workflow   → definition.md + stages/ directory
run workflow      → session.md created with variables substituted
  stage 1 runs   → artifacts written to sessions/{date}-{slug}/artifacts/
  stage 2 runs   → reads stage 1 artifacts via consumes: declaration
  ...
  final stage    → session marked complete
archive workflow  → moved to .craft/workflows/.archived/ (data preserved)
```

### Session States

| Status | Meaning |
|--------|---------|
| `active` | In progress, current stage known |
| `ready` | Created but not yet started |
| `complete` | All stages done |
| `paused` | Manual stage pending human action |

### Batch Mode

`/craft:workflow-run batch {name}` creates multiple sessions at once from a list of variable sets. Useful for running the same workflow against multiple subjects (research on 5 topics, documentation for 8 commands).

Sessions created in batch mode start as `draft` and can be marked `ready` via `/craft:workflow-run ready {name}`, or run sequentially with `/craft:workflow-run run-all {name}`.

---

## Breadcrumb Pattern for Command Stages

When a `command`-type stage invokes a craft skill via the Skill tool, the orchestrator writes a breadcrumb before invocation. Without it, the orchestrator stops after the skill returns instead of continuing to the next stage.

```bash
cat > "${CRAFT_PROJECT_ROOT:-.}/.craft/.continuation" << CRUMB
ACTION: Continue workflow session "{session-name}" from stage {N+1}
SKILL: craft:craft-workflow-run
ARGS: continue
WRITTEN_BY: craft-workflow-run
TIMESTAMP: $(date -u +%Y-%m-%dT%H:%M:%S)
CRUMB
```

The Stop hook reads this file, injects a "DO NOT STOP" continuation instruction, and deletes the file (one-shot). The breadcrumb has a 30-minute TTL and is cleaned up on session start.

---

## File Structure Reference

```
.craft/workflows/
  {workflow-slug}/
    definition.md              # Routing table for stages
    stages/                    # Per-stage briefs (self-contained)
      01-{slug}.md             # Stage 1 - self-contained brief
      02-{slug}.md             # Stage 2
    sessions/
      {YYYY-MM-DD}-{slug}/
        session.md             # Progress tracking, variable values, stage status
        artifacts/             # Stage outputs for cross-stage handoff
          01-{slug}-output.md
          02-{slug}-output.md
  .archived/                   # Archived workflows (still readable, not shown in dashboard)
```

---

## Quick Commands

```bash
# Router - status and dispatch
/craft:workflow                        # Dashboard - see all workflows and sessions

# Session lifecycle (workflow-run)
/craft:workflow-run run {name}         # Start a new session for a workflow
/craft:workflow-run continue           # Resume the active session at current stage
/craft:workflow-run next {name}        # Activate and run the next runnable session
/craft:workflow-run run-all {name}     # Chain through all runnable sessions
/craft:workflow-run batch {name}       # Create multiple draft sessions at once
/craft:workflow-run ready {name}       # Mark draft sessions as ready

# Definition lifecycle (workflow-design)
/craft:workflow-design create          # Create a new workflow
/craft:workflow-design edit {name}     # Edit an existing workflow's stages/prompts/checklists
/craft:workflow-design archive {name}  # Archive a workflow (preserves sessions, hides from dashboard)
```

---

*For the complete operational spec, see `commands/craft-workflow.md` (router), `commands/craft-workflow-run.md` (session execution), and `commands/craft-workflow-design.md` (definition authoring). For frontmatter and stage-file schema, see `commands/references/workflow-formats.md`.*
