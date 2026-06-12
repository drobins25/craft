# Craft - Design Reference

> Architecture reference for `craft`, a Claude Code plugin that turns the CLI into a creative-first development harness. CLAUDE.md is the rules file Claude auto-loads each session; this file holds the architectural detail CLAUDE.md summarizes.

For definitions of cycle, story, chunk, and the workshop concepts, see README.md. This file assumes that vocabulary.

---

## Plugin Structure

```
plugins/craft/
├── .claude-plugin/
│   └── plugin.json            ← Plugin manifest (name, version)
├── agents/                    ← Isolated-context specialist agents (27 agents)
│   ├── alchemist.md           ← CSS interaction physicist (crystallized)
│   ├── become-researcher.md   ← Psychological material collector for /craft:become
│   ├── chunk-validator.md     ← Quality check executor (haiku model)
│   ├── conductor.md           ← AI orchestration architect (crystallized)
│   ├── creative-analyzer.md   ← Delight moments, viral potential
│   ├── crystallizer.md        ← Research-to-agent synthesizer (opus model)
│   ├── doc-writer.md          ← Documentation practitioner (crystallized)
│   ├── implementer.md         ← Implement → validate → refine loop per chunk
│   ├── maze-architect.md      ← Perpendicular review question generator (haiku)
│   ├── muse.md                ← Emotional job translator (crystallized)
│   ├── plan-chunks-agent.md   ← Autonomous chunk planning per story
│   ├── playwright-browser.md  ← Interactive browser session via playwright-cli
│   ├── pr-reviewer-expert.md  ← PR review (crystallized from CodeRabbit)
│   ├── practitioner-reviewer.md ← Practical experience claims challenger
│   ├── product-anthropologist.md ← Human-truth layer for product decisions
│   ├── project-scanner.md     ← Full project analysis for documentation updates
│   ├── qa-analyzer.md         ← Bug hunting via browser inspection
│   ├── researcher.md          ← Research sub-question extractor (haiku)
│   ├── research-synthesizer.md ← Cross-branch synthesis: writes _plan.md + _sources.md (sonnet)
│   ├── style-analyzer.md      ← Token compliance, pattern consistency
│   ├── tester.md              ← Integration tests, E2E, final validation
│   ├── ux-analyzer.md         ← Nielsen heuristics, accessibility
│   ├── verifier.md            ← Adversarial claim checker (primary sources only)
│   └── walkthrough-analyzer.md ← First-time user simulation (chrome-devtools MCP)
├── commands/                  ← Slash command definitions (30 commands)
│   ├── craft.md               ← Main entry point
│   ├── craft-ask.md           ← Consult a workshop agent (intelligent routing)
│   ├── craft-become.md        ← Agent crystallization (4-phase: research→checkpoint→crystallize→save)
│   ├── craft-docs.md          ← Documentation generation (two-pass: brief then generate)
│   ├── craft-init.md
│   ├── craft-notebook.md      ← Low-ceremony capture (ideas/todos/notes); conversational graduate/done
│   ├── craft-riff.md          ← Two-gear thinking partner (thin sensor/router); tight gear in-loop, wide gear → riff agent
│   ├── craft-planning.md
│   ├── craft-status.md
│   ├── craft-project.md
│   ├── craft-review.md        ← PR-style review with standard and --maze modes
│   ├── craft-research.md
│   ├── craft-research-verify.md ← Verify research findings against primary sources
│   ├── craft-cycle-design.md
│   ├── craft-cycle-start.md
│   ├── craft-cycle-assign.md
│   ├── craft-cycle-complete.md
│   ├── craft-story-new.md     ← Runs Likely Files scan; writes ## Likely Files section
│   ├── craft-story-implement.md
│   ├── craft-story-implement-auto.md
│   ├── craft-story-continue.md
│   ├── craft-story-archive.md
│   ├── craft-story-delete.md
│   ├── craft-analyze.md
│   ├── craft-reflect.md
│   ├── craft-update-docs.md
│   ├── craft-workflow.md          ← Workflow router (state read, fast paths, dashboard, dispatch)
│   ├── craft-workflow-run.md      ← Session lifecycle (run/continue/next/run-all/batch/ready)
│   ├── craft-workflow-design.md   ← Definition lifecycle (create/edit/archive)
│   └── references/
│       └── workflow-formats.md    ← Shared schema reference (frontmatter, stage-file format)
├── skills/                    ← Orchestrator-context skills (11 skills)
│   ├── approve/               ← Scoped write permission gate (AskUserQuestion + TaskCreate)
│   ├── browser/               ← playwright-cli browser automation launcher
│   ├── content-spark/         ← Surface content assumptions before creative/planning
│   ├── creative-spark/        ← Generate creative options; supports muse/alchemist drivers
│   ├── design-vibe/           ← Visual cohesion review across stories
│   ├── fix/                   ← Adhoc fix without story ceremony; records to .craft/fixes/
│   ├── lock-decision/         ← Formalize approved decisions
│   ├── plan-chunks/           ← Batch planning with file-based dependency verification
│   ├── validate-chunk/        ← Validation via git diff (not spec file list)
│   ├── refine-chunk/          ← Targeted fixes for validation failures
│   └── test-fix/              ← Triage failing tests, fix the right thing
├── hooks/
│   ├── hooks.json             ← Hook event definitions
│   └── scripts/               ← 45+ bash/python hook scripts
├── templates/                 ← File templates for craft init and scaffolding
│   ├── craft/                 ← .craft/ directory templates
│   │   ├── design/            ← tokens.yaml, components.md, locked.md
│   │   ├── design-cli/        ← CLI-specific design templates
│   │   ├── inspiration/
│   │   ├── project.md
│   │   └── quality.yaml
│   ├── analysis/
│   │   └── pending/           ← Analysis queue templates
│   ├── cycle/
│   │   └── learnings.yaml
│   ├── cycle-state
│   ├── cycle.yaml
│   ├── planning/
│   ├── request.md
│   ├── story-backlog.md       ← Backlog story template
│   ├── story-full.md          ← Full story template (with chunks)
│   └── story-roadmap.md       ← Roadmap-only story template
├── reference/                 ← Orchestration-critical (injected by hooks, drives routing)
│   ├── decision-tree.md
│   └── orchestration-index.min
├── docs/                      ← Generated documentation (informational, not auto-loaded)
│   ├── agent-catalog.md
│   ├── creative-workshop.md
│   ├── design-philosophy.md
│   ├── plan-tdd-enforcement.md
│   ├── research-agentic-research-patterns.md
│   └── workflow-reference.md
├── tests/                     ← Bash test suite (30+ bash tests)
│   ├── run-all.sh
│   ├── test_helper.sh
│   ├── fixtures/
│   └── test-*.sh
├── CLAUDE.md                  ← Auto-loaded every session
├── DESIGN.md                  ← This file (reference only)
└── README.md                  ← Human-facing docs
```

---

## Statuses

| Status | Meaning |
|--------|---------|
| `draft` | Just an idea, not planned |
| `planning` | In creative mode, locking decisions |
| `ready` | Story file complete, can implement |
| `active` | Currently being implemented |
| `blocked` | Waiting on dependency |
| `complete` | 95% done, tests passing |
| `verified` | Human reviewed & approved |
| `reverted` | Story was started but reverted after a checkpoint; preserved for history |

## Parallelism

### Implementation Parallelism
- Max 2 stories in parallel, use `1a`, `1b` suffix
- Parallel stories must NOT touch same files

### Planning Parallelism
- `plan-chunks` skill supports batch mode: plans all `status: planning` stories in a cycle in parallel
- **Dual-mode orchestration:**
  - Agent teams (primary) - when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Teammates coordinate live (file overlap, dependency awareness)
  - Task subagents (fallback) - isolated agents with post-hoc cohesion check by orchestrator
- Batch size: determined by story dependency graph (topological levels - independent stories plan in parallel, dependent chains plan sequentially)
- Pattern: **skill as orchestrator + agents as workers** - plan-chunks orchestrates, plan-chunks-agent does the heavy lifting per story
- After agents complete → batch triage (BT-1 through BT-7) reviews all plans with user

## Planned Story Format (contracts model)

Chunk specs lock **seams, not interiors**. The planner pins contracts (signatures, shapes, routes, invariants - each line carrying a receipt: `[verified: attack evidence]`, `[owner: Chunk N]`, `[investigation: reason]`, `[defines]`); the implementer owns function bodies and test bodies. No copy-pasteable code in plans - code appears only when the code IS the decision.

A planned story carries four planning artifacts (format reference: `skills/plan-chunks/references/chunk-format-guide.md`):

- **`## The Pitch`** - the plan's guarantee plus a conditions table of every load-bearing assumption, tagged `verified` / `system-owned` / `unverifiable -> becomes Chunk N's first test`. Doubles as the implementer's tripwire watchlist.
- **`## Investigation`** - the planner's causal research narrative, dead ends kept. Transfers the planner's headspace to the implementer and any future re-planner.
- **`## Acceptance Pre-Flight`** - one row per acceptance vehicle, symbolically walked through the path it exercises using the test's own data shape; any `UNREACHABLE` verdict blocks plan acceptance (walk reference: `skills/plan-chunks/references/acceptance-walkthrough.md`).
- **`## Chunks`** - cut bottom-up at layer rungs; later chunks cite earlier chunks' real output via `[owner: Chunk N]`, which self-freshens the spec.

Two escape valves keep the autonomy honest: the planner may stop mid-flight only for a **PLAN FORK** (a user-owned question whose answers produce two different plans); the implementer stops on **CONTRACT MISMATCH** (reality contradicts a receipted contract - the report is a deliverable, the orchestrator amends the plan, never the implementer). Lower-stakes decisions are made in flight and triaged by **product-stake** (silent / mention / ask, judged against a perfectionist product owner) rather than confidence alone.

## Workflow Formats

*Full format reference: [docs/workflow-reference.md](docs/workflow-reference.md).*

The workflow command supports two formats detected by checking for a `stages/` directory.


**stages-v1** - `definition.md` is a routing table; each stage is a self-contained file in `stages/`. Sessions get an `artifacts/` directory for cross-stage handoff. Stage files declare `consumes:` (artifact paths from prior stages) and `produces:` (output path). This is the preferred format for workflows with 6+ stages or substantial per-stage documentation.

Artifact handoff replaces relying on conversation memory across compaction boundaries. Stage 5 can reliably read Stage 1's output by declaring it in `consumes:` - the orchestrator reads the artifact file at dispatch time regardless of whether the original context is still present.

See `docs/workflow-reference.md` for the full format spec and examples.

---

## Human Checkpoints

- If ANYTHING weird → NO assumptions, ask human
- State snapshot before every chunk; at story completion, one commit staged from the validated file manifest (leftover files are surfaced for triage, never swept in)
- Trust by default, verify when uncertain

---

## Phases Detail

### Creative Phase

Write access restricted to `.craft/` and `.claude/`. Used for story creation, design, planning, and locking decisions - no source-code edits.

**Included skills:** content-spark, creative-spark, design-vibe, lock-decision, plan-chunks, fix, approve, browser
**Included agents:** plan-chunks-agent, project-scanner, muse, riff, alchemist, conductor, doc-writer, product-anthropologist, pr-reviewer-expert, maze-architect, researcher, research-synthesizer, verifier, practitioner-reviewer, playwright-browser, become-researcher, crystallizer, guide
**Included commands:** craft, craft:init, craft:cycle-design, craft:cycle-start, craft:cycle-complete, craft:cycle-assign, craft:story-new, craft:story-archive, craft:story-delete, craft:status, craft:update-docs, craft:docs, craft:project, craft:review, craft:become, craft:ask, craft:workflow, craft:workflow-run, craft:workflow-design, craft:research, craft:research-verify, craft:fix

### Implement Phase

Full write access, gated by `CRAFT_WRITE_ENABLED` in `.global-state`. Runs with `acceptEdits` permission mode.

**Allowed tools:** Read, Write, Edit, Glob, Grep, Bash, Task
**Included skills:** validate-chunk, refine-chunk, test-fix
**Included agents:** implementer, tester, chunk-validator
**Included commands:** craft:story-implement, craft:story-implement-auto, craft:story-continue

### Analysis Phase

Triggered by `/craft:analyze` after a cycle ships. No restricted write scope - runs in the active session context.

**Included agents:** qa-analyzer, ux-analyzer, creative-analyzer, style-analyzer, walkthrough-analyzer
**Included commands:** craft:analyze, craft:review

---

## Hooks Detail

All hooks defined in `hooks/hooks.json`. Scripts in `hooks/scripts/`.

### SessionStart
- **`session-start.sh`** (once) - Detects active cycle, sets status line, loads context
- **`post-compact-reinject.sh`** (on compact) - Re-injects craft context after context compaction

### PreToolUse (Write|Edit)
- **`check-write-permission.py`** - Enforces write permission gating. Checks for active story/cycle context, `CRAFT_WRITE_ENABLED` flag, active workflow session, and allowed paths. Uses hardcoded logic (no external config file).

### PreToolUse (Bash)
- **`auto-approve-plugin-scripts.sh`** - Auto-approves bash invocations of plugin scripts to reduce permission prompts.

### PostToolUse (Write|Edit)
- **`update-progress.py`** (async) - Tracks which files were modified, updates story progress counts

### PostToolUseFailure
- **`handle-tool-failure.py`** (async) - Logs tool failures, appends to recovery log

### PreCompact
- **`export-progress.sh`** - Exports current progress state before context window compaction

### UserPromptSubmit
- **`inject-craft-context.sh`** - Injects active cycle/story context into every prompt

### Stop
- **`stop-hook-guard.sh`** - Guards against unclean session stops, ensures state consistency

### Utility Scripts (called by hooks or commands)
| Script | Purpose |
|--------|---------|
| `create-checkpoint.sh` | Git stash-based rollback points before chunks |
| `create-cycle.sh` | Scaffold a new cycle directory |
| `create-story.sh` | Create story file from template |
| `delete-story.sh` | Remove a story file |
| `move-story.sh` | Move story between backlog and cycle |
| `start-cycle.sh` | Set active cycle in .global-state |
| `start-story.sh` | Set active story, enable writes |
| `complete-chunk.sh` | Mark chunk done, update .state |
| `complete-story.sh` | Mark story complete, disable writes |
| `complete-cycle.sh` | Complete cycle, trigger learnings |
| `start-workflow-session.sh` | Initialize a workflow session directory and state |
| `complete-workflow-session.sh` | Mark a workflow session complete |
| `complete-workflow-stage.sh` | Advance workflow to the next stage |
| `get-latest-cycle.sh` | Resolve the most recent cycle directory path |
| `update-global-state.sh` | Update .global-state key-value pairs |
| `update-cycle-state.sh` | Update cycle .state file |
| `update-story-status.sh` | Change story status in frontmatter |
| `statusline.sh` | Generate status line display |
| `find-project-root.sh` | Locate .craft/ directory |
| `discover-projects.sh` | Find all craft projects |
| `count-requests.sh` | Count pending items in requests queue |
| `process-request.sh` | Route a request to a story or cycle |
| `salvage-partial-work.sh` | Recover work from interrupted sessions |
| `append-recovery-log.sh` | Log recovery events |
| `read-events.sh` | Read from the event log |
| `append-event.sh` | Append an entry to the event log |
| `aggregate-failures.py` | Aggregate failure records for triage |
| `run-gates.sh` | Run quality gate checks |
| `check-polish.sh` | Check polish requirements |
| `self-critique.sh` | Self-critique against locked patterns |
| `generate-project-md.sh` | Generate project.md from scan |
| `setup-craft.sh` | Initial .craft/ directory setup |
| `track-usage.sh` | Track usage metrics |

---

## .craft/ Directory Structure (Complete)

```
project-root/
├── .craft/
│   ├── backlog/               ← Stories not yet in a cycle
│   │   └── story-name.md
│   ├── cycles/                ← Time-boxed work containers
│   │   └── 1-auth/
│   │       ├── cycle.yaml     ← Cycle metadata (name, goal, dates, optional source_concept)
│   │       ├── .state         ← Current story/chunk progress
│   │       ├── .failures      ← Failure tracking for retry logic
│   │       ├── .learnings.yaml ← Cycle learnings for reflection
│   │       └── stories/
│   │           └── 1-story-name.md
│   ├── checkpoints/           ← Chunk rollback points (YAML)
│   ├── fixes/                 ← Adhoc fix records (created by /craft:fix)
│   │   └── fix-name.md        ← category, root cause, solution, lesson
│   ├── analysis/              ← Persistent analysis findings
│   │   ├── pending/           ← Findings queue (survives sessions)
│   │   │   ├── qa.yaml
│   │   │   ├── ux.yaml
│   │   │   ├── creative.yaml
│   │   │   └── style.yaml
│   │   ├── screenshots/
│   │   └── reports/
│   ├── inspiration/           ← Reference library for the Creative Phase
│   │   ├── screenshots/
│   │   ├── sites.md
│   │   └── patterns.md
│   ├── notebook/              ← Low-ceremony capture (created by /craft:notebook)
│   │   ├── ideas/             ← Half-formed thoughts; graduated ideas stay in place with flag
│   │   │   └── YYYY-MM-DD-slug.md
│   │   ├── todos/             ← Concrete actions
│   │   │   ├── YYYY-MM-DD-slug.md
│   │   │   └── done/          ← Archive for completed todos
│   │   │       └── YYYY-MM-DD-slug.md
│   │   └── notes/             ← Durable project facts; no lifecycle, recalled by facet
│   │       └── YYYY-MM-DD-slug.md
│   ├── design/                ← Design system (enforced)
│   │   ├── tokens.yaml        ← Design tokens
│   │   ├── components.md      ← Component patterns
│   │   ├── locked.md          ← Approved patterns (enforced)
│   │   ├── animations.md      ← Animation patterns
│   │   └── .confidence-signals.yaml ← Token confidence scores (use_count, file_count, consistency_score, recency)
│   ├── workflows/             ← Reusable multi-step workflows
│   │   └── {workflow-slug}/
│   │       ├── definition.md  ← Routing table for stages
│   │       ├── stages/        ← Per-stage self-contained briefs (stages-v1 format only)
│   │       └── sessions/      ← Per-run instances with progress + artifacts
│   ├── requests/              ← External feature requests
│   │   └── processed/         ← Requests routed to stories or cycles
│   ├── docs/                  ← Documentation briefs (created by /craft:docs)
│   │   └── brief.md
│   ├── research/              ← Ad-hoc research folders (created by /craft:research)
│   │   └── {topic-slug}/
│   │       ├── _plan.md
│   │       ├── 01-branch.md
│   │       └── verification-{slug}.md
│   ├── project.md             ← Project DNA
│   ├── quality.yaml           ← Quality gates
│   ├── settings.yaml          ← Craft settings
│   ├── .global-state          ← Active cycle, global config
│   └── .continuation          ← Breadcrumb for skill continuation (transient, 30-min TTL)
└── src/
```

### .global-state Fields

```
LAST_ACTIVITY="2026-04-14T00:11:52Z"
ACTIVE_CYCLE="8-token-lifecycle-v3"
CURRENT_STORY=""
DEFAULT_MODE="creative"
BACKLOG_COUNT="10"
PLANNING_CYCLE=""
CRAFT_WRITE_ENABLED=""
CYCLE_STATUS=""
CURRENT_WORKFLOW_SESSION=""
RUN_MODE=""
```

Key fields:
- `CRAFT_WRITE_ENABLED` - gates writes outside `.craft/`. Set to `"true"` by active stories, the `fix` skill, and the `approve` skill. Empty string means closed.
- `CURRENT_WORKFLOW_SESSION` - active workflow session path (set when a workflow session is running).
- `RUN_MODE` - `autonomous` when an unattended run is active (set by `story-implement-auto`), empty otherwise. Normal cruise runs leave it empty; cruise is craft's single default behavior (chains chunks and stories, stops only at decision points or on failure), not a stored mode.
- `CYCLE_STATUS` - current state of the active cycle.

### cycle.yaml Schema

```yaml
name: cycle-slug
title: "Cycle NN: Display Title"
status: planning | ready | active | complete
created: YYYY-MM-DD
updated: YYYY-MM-DD
target: One-line description of what ships
focus: Primary focus area
source_concept: [planning/concept-a.md, planning/concept-b.md]   # may be empty []

goals:
  - Outcome 1
  - Outcome 2
```

**`source_concept`** - YAML flow list of planning doc paths (relative to project root) this cycle is sourced from. Empty list `[]` means the cycle is freeform (no planning source). When populated, cycle-design routes story-creation moments to the From planning protocol (`commands/references/story-from-planning.md`) so each planning-extracted story's spark draws from the planning content. Stories added during the add-a-separate-story moment within a planning-sourced cycle remain freeform and get no `source_concept` of their own. Captured at cycle creation via `create-cycle.sh`'s 5th positional arg, gated behind the Step 1 verbatim-quote rule + AskUserQuestion safety gate.

---

## Planning Alignment

Concepts in `.craft/planning/` (managed by `/craft:planning`) have an alignment walkthrough that resolves a concept's strategic sub-decisions before stories get created. The architecture has three load-bearing parts:

**TaskTool queue.** The orchestrator's speculative working list of sub-decisions for a concept lives in TaskTool — session-scoped, allowed to die. The model only sees one task at a time, so multi-decision AskUserQuestion bundles become structurally impossible. Re-derivation on session resume is correct behavior; not loss.

**Three completion destinations.** Every sub-decision terminates in exactly one place: `## Locked decisions` (conversational resolution + explicit lock-confirmation ask — the orchestrator must ask "Want me to lock this as X?" before writing), `pending_decisions[]` frontmatter (user deferred — regenerates as a task on next session), or `## Open questions` with owner annotation (blocked on someone else — doesn't auto-nag).

**Step 9 destination-coverage gate (intra-session).** Before story creation runs, the gate verifies every closed task landed in one of the three destinations. Tasks that closed without filing block story creation and route back to alignment with the unaccounted items named. Cross-session integrity is handled by the immediate-write rule (Locked entries hit disk at the moment of resolution), not by the gate.

The depth ceiling is prose-enforced: planning is for strategic decisions (the ones that shape which stories come out of the concept), not implementation detail. If candidate extraction returns more than ~10 items, the orchestrator reframes some as story-new / plan-chunks work and defers them.

---

## Notebook Lifecycle

The notebook (`/craft:notebook`, `.craft/notebook/`) is a capture surface for ideas, todos, and notes that sit below the backlog. State transitions are conversational, not subcommand-driven:

- **Ideas** start in `ideas/YYYY-MM-DD-slug.md`. When an idea matures into story-shape, the user signals graduation; the orchestrator routes to `/craft:story-new` with the idea pre-filled and flags the idea in place (it stays, marked as graduated, for traceability).
- **Todos** start in `todos/YYYY-MM-DD-slug.md`. When done, the orchestrator confirms via AskUserQuestion (always - asymmetric failure visibility for the destructive action) and moves the file to `todos/done/`.
- **Notes** start in `notes/YYYY-MM-DD-slug.md` and have NO lifecycle - they never graduate and never get "done." A note is a durable, project/team-local fact whose value is future recall (paragraph 1 = the distilled timeless fact, paragraph 2 = provenance). Each carries a `facet` (`infrastructure | tooling | ownership | process | convention | gotcha`) that keys WHEN it resurfaces. Recall is hybrid: `session-start.sh` injects a one-line-per-note index every session (via `notebook-notes-index.sh`), and the full body is read on demand when the current work matches the facet/topic. Staleness is handled the Claude-memory way - dated filenames + the always-loaded index + "as of {date}" recall framing - not a TTL.
- **Deferral markers** in conversation ("later", "side note", "don't forget", "for next time", etc.) trigger an inline mention of `/craft:notebook` as a closing line. On accept the orchestrator captures silently with session context. No subcommands.

The lifecycle deliberately keeps every state fast: capture is one line, graduate is one prompt, done is one AUQ, and a note is captured silently on an accepted inline offer. Power-user subcommand syntax is explicitly rejected in favor of conversational verbs. Claude offers notes proactively only above a high durability bar (no built-in/vague expiry), mirroring the high-bar-for-Claude / low-bar-for-user discipline of the deferral-marker offer.

---

## Riff: skill and agent

Riff exists as a **skill** and an **agent** that work as a pair, not as one replacing the other.

- **The riff skill** (`commands/craft-riff.md`) is a thin sensor/router. It carries a `when_to_use` that does the gear-sensing from the main loop: a FOCUS GATE on top (heads-down user -> a future-leaning spark routes to `/craft:notebook`, not riff), four reads (tight gear, wide gear, presignal offer, silence), and a nag FLOOR on the bottom. It re-documents none of the riffing craft - it only decides WHEN riff engages or is offered. It runs the tight gear itself and hands the wide gear off.
- **The riff agent** (`agents/riff.md`) is the crystallized partner that does the actual riffing (the throw/pull/catch/dislocate gears, the silence-vs-abandonment read, the exhausted-user restraint). It is the wide-gear destination, invoked via the Agent tool (`subagent_type: "craft:riff"`) and via `/craft:ask`. Skills and agents are separate registries, so the `craft:riff` skill and `craft:riff` agent coexist without collision.

The skill mirrors the notebook trigger discipline exactly: ignorable inline offers (never AskUserQuestion), bounded triggers, silence as the default, and at most one inline offer per turn so riff never stacks nudges on notebook / creative-spark / design-vibe.

The skill's **tight gear** runs the **calibration loop** (`reference/calibration-loop.md`) - a standalone, reusable boundary-elicitation technique (the "optometrist flip test") that converts a tacit "I know it when I see it" into an encodable rule. It is deliberately written skill-agnostic so content-spark, design-vibe, and lock-decision can point to it too.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  ENTRY: /craft or just start talking                            │
│  → Creates story → Assign to cycle or backlog                   │
└─────────────────────────────────────────────────────────────────┘
         │                                    │
    BACKLOG ──assign──▶ CYCLE ──▶ CREATIVE PHASE
                                      │
                               IMPLEMENT PHASE (autonomous)
                                      │
                               ANALYSIS PHASE (post-cycle)
                                      │
                               Back to Backlog / Cycle
```

---

## Testing

Bash test suite in `tests/`. Run all tests:

```bash
./tests/run-all.sh
```

Individual tests follow the pattern `test-{script-name}.sh` and test the corresponding hook script. Tests use `test_helper.sh` for shared setup/teardown and fixtures from `tests/fixtures/`.

---

*For decision trees and orchestration routing, see `reference/`. For design philosophy and TDD enforcement patterns, see `docs/`.*
