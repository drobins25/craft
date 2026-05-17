# Craft

> Creative-first, feedback-loop-driven development with a smart pairing partner

For developers using Claude Code who want a pairing partner instead of a code generator.

Craft is a Claude Code plugin that transforms how you build software. Instead of rigid spec-first processes, embrace the way great pairing actually works:

- **Riff on ideas** together (Creative Phase)
- **Lock decisions** as you go
- **Execute with confidence** (Implement Phase)
- **Analyze and inspire** next iteration (Analysis Phase)

## Philosophy

**Creativity as default. Smart execution follows.**

Claude is smarter now. Trust it to run further. Checkpoint for safety, not for control.

**Status:** v1.65.0 - MIT - actively developed

## Core Principles

1. **Quality is Pristine by Default** — Stripe, Linear, Vercel level. Not "good enough."
2. **Nothing Happens Without Approval** — Claude advises, you decide.
3. **Claude Always Offers Suggestions with Reasoning** — Not just options, recommendations.
4. **Perfection Gets Locked** — Approved patterns become enforced standards.
5. **Quality Only Evolves Upward** — Can add requirements, never remove.
6. **Claude Self-Critiques Before Complete** — Compares against your standards.
7. **The Harness Evolves** — Gets smarter with every cycle.

## Install

Inside Claude Code, run these two commands:

```
/plugin marketplace add drobins25/craft
/plugin install craft@craft
```

The first command registers the Craft marketplace by cloning this repo to `~/.claude/plugins/marketplaces/craft/`. The second installs the plugin from it.

Verify it worked:

```
/craft
```

You should see the Craft entry-point prompt.

## Getting Started

### Initialize a Project

```
/craft:init
```

This will:
1. Ask about your project type and energy level
2. Optionally extract inspiration from a reference site
3. Set up the `.craft/` directory with quality standards
4. Configure design tokens and patterns

### Create Your First Story

```
/craft:story-new
```

Stories land in the backlog. Work on them when ready.

### Start a Cycle

```
/craft:cycle-design
/craft:cycle-assign
```

**Planning-sourced cycles:** If you have planning docs in `.craft/planning/` (files with `concept:` or `initiative:` frontmatter), cycle-design detects them. When you mention a specific planning doc in conversation before invoking the command, the orchestrator confirms via a safety gate, captures the source on `cycle.yaml`, and routes story creation through the From planning protocol so each story's spark draws from the planning content. Cycles created without planning sources work exactly as before.

### Implement

```
/craft:story-implement
```

Craft will guide you through:
1. Creative Phase — flesh out the idea
2. Chunk planning — break into implementable pieces
3. Implement Phase — execute with quality gates
4. Validation — ensure everything passes

## Commands

| Command | Purpose |
|---------|---------|
| `/craft` | Main entry point — start here |
| `/craft:status` | Dashboard view of progress |
| `/craft:story-new` | Create story (lands in backlog) |
| `/craft:story-implement` | Implement a story (interactive) |
| `/craft:story-implement-auto` | Implement a story (autonomous) |
| `/craft:story-continue` | Resume interrupted story |
| `/craft:story-archive` | Move story back to backlog |
| `/craft:story-delete` | Delete a story |
| `/craft:cycle-design` | Design a cycle (new or existing) |
| `/craft:cycle-start` | Activate a cycle |
| `/craft:cycle-assign` | Move story to cycle |
| `/craft:cycle-complete` | Complete a cycle, trigger reflection |
| `/craft:analyze` | Run QA, UX, Creative, Style, or Walkthrough analysis |
| `/craft:review` | PR-style code review — branch, story, or project audit. `--maze` flag enables perpendicular review via maze-architect |
| `/craft:reflect` | Improve the harness based on learnings |
| `/craft:update-docs` | Re-scan project, update documentation |
| `/craft:docs` | Generate or update docs using the crystallized doc-writer agent (two-pass: brief then generate) |
| `/craft:become` | Crystallize a tool, role, or person into a portable 9-section agent with beliefs and scar tissue |
| `/craft:ask` | Consult a workshop agent — routes your question to the best available mind |
| `/craft:workflow` | Reusable multi-step workflows with agent/inline/manual/command execution modes |
| `/craft:research` | Ad-hoc research — discover, elaborate, synthesize with ranked branches |
| `/craft:research-verify` | Verify existing research findings against independent primary sources |
| `/craft:fix` | Adhoc fix for small bugs without story ceremony. Creates permanent record in `.craft/fixes/` |
| `/craft:project` | Switch projects or cross-project dashboard |
| `/craft:init` | One-time project setup |

## Skills

| Skill | Phase | Purpose |
|-------|-------|---------|
| `content-spark` | Creative | Surface content assumptions, capture content direction |
| `creative-spark` | Creative | Generate creative options and ideas. Supports Creative Driver step (Step 1.5) with muse/alchemist interrogators |
| `design-vibe` | Creative | Visual cohesion review across stories |
| `lock-decision` | Creative | Formalize approved decisions |
| `plan-chunks` | Smart | Transform stories into implementation plans. Supports parallel batch mode with file-based dependency verification |
| `validate-chunk` | Smart | Quick validation after chunk implementation. Derives `FILES_CHANGED` from git diff, not spec file list |
| `refine-chunk` | Smart | Targeted fixes for validation failures |
| `test-fix` | Smart | Triage failing tests, fix the right thing |
| `fix` | Any | Adhoc fix without story ceremony. Investigate → confidence check → apply → validate → commit |
| `approve` | Any | Request scoped write permission from the user. Opens the write gate only after explicit AskUserQuestion approval |
| `browser` | Any | Launch a persistent playwright-cli browser session. ~4x cheaper than Chrome DevTools MCP in token cost |

## Agents

23 agents across five categories. See `docs/agent-catalog.md` for full descriptions, model assignments, and when to use each.

**Core Workflow** — run inside the implementation pipeline

| Agent | Role |
|-------|------|
| `implementer` | Owns the implement → validate → refine loop per chunk |
| `tester` | Integration tests, E2E, final validation |
| `chunk-validator` | Runs quality checks, returns structured report (haiku model) |
| `plan-chunks-agent` | Autonomous chunk planning per story — used in batch mode |
| `project-scanner` | Full project analysis for documentation updates |

**Analysis** — inspect the live app post-cycle

| Agent | Role |
|-------|------|
| `qa-analyzer` | Finds bugs using browser inspection |
| `ux-analyzer` | Nielsen heuristics, accessibility, mental models |
| `creative-analyzer` | Delight moments, viral potential |
| `style-analyzer` | Token compliance, pattern consistency |
| `walkthrough-analyzer` | First-time user simulation — clicks everything, tests every state |

**Review and Research** — code review, research, verification

| Agent | Role |
|-------|------|
| `pr-reviewer-expert` | PR review crystallized from CodeRabbit — reads locked.md before any opinion |
| `maze-architect` | Generates perpendicular review questions from a diff with zero intent context (haiku) |
| `researcher` | Investigates one research sub-question, writes branch file to disk |
| `verifier` | Adversarial claim checker — tries to disprove findings using primary sources |
| `practitioner-reviewer` | Challenges verified claims from practical experience |

**Browser**

| Agent | Role |
|-------|------|
| `playwright-browser` | Owns a live browser session via playwright-cli. Interactive, steerable via SendMessage |

**Crystallized Experts** — consult via `/craft:ask`

| Agent | Role |
|-------|------|
| `muse` | Emotional job translator — finds why anyone will care before exploring how to build |
| `alchemist` | CSS interaction physicist — sees the browser as a physics engine |
| `conductor` | AI orchestration architect — knows which patterns hold under real conditions |
| `doc-writer` | Documentation diagnostician — crystallized from Stripe/Linear-quality practitioners |
| `product-anthropologist` | Human-truth layer — diagnoses whether a product solves a real problem |
| `crystallizer` | Psychological synthesizer that distills research into agent personas (opus model) |
| `become-researcher` | Psychological material collector for `/craft:become` — gathers beliefs, not facts |

## How craft work flows

> A kitchen has prep, line, and pass - three stations, same kitchen, different work as the dish comes together.

### Creative Phase
*The prep station.*

Story creation, design, planning, and locking decisions. Write access restricted to `.craft/` (no source-code edits). Active skills: content-spark, creative-spark, design-vibe, lock-decision, plan-chunks.

### Implement Phase
*The line.*

Autonomous execution against a ready story. The implementer builds each chunk; chunk-validator checks it; failures route to refine-chunk or test-fix. Full write access, gated by the active story.

### Analysis Phase
*Tasting after service.*

Post-cycle review triggered by `/craft:analyze`. Four analyzer agents (QA, UX, Creative, Style) scan what shipped to surface bugs, friction, missed opportunities, and design drift.

## Directory Structure

After initialization, your project will have:

```
.craft/
├── backlog/              # Stories waiting to be worked
├── cycles/               # Time-boxed work containers
│   └── 1-auth/
│       ├── cycle.yaml
│       ├── .state
│       └── stories/
├── checkpoints/          # Chunk rollback points
├── fixes/                # Adhoc fix records (created by /craft:fix)
├── analysis/             # Persistent analysis findings
│   └── pending/          # Findings queues (survive sessions)
├── inspiration/          # Reference library
├── design/
│   ├── tokens.yaml       # Design tokens (enforced)
│   ├── components.md     # Component patterns
│   ├── locked.md         # Approved patterns (enforced)
│   └── .confidence-signals.yaml  # Token confidence scores (written by project-scanner)
├── workflows/            # Reusable multi-step workflows
│   └── {workflow-name}/
│       ├── definition.md # Routing table (stages-v1) or full definition (monolithic)
│       ├── stages/       # Per-stage briefs (stages-v1 format only)
│       └── sessions/     # Per-run instances with progress + artifacts
├── requests/             # External feature requests
│   └── processed/        # Requests routed to stories or cycles
├── docs/                 # Documentation briefs (created by /craft:docs)
├── research/             # Ad-hoc research folders (created by /craft:research)
├── project.md            # Project DNA
├── quality.yaml          # Quality gates
├── settings.yaml         # Craft settings
├── .global-state         # Current state
└── .continuation         # Breadcrumb for skill continuation (transient)
```

## Hooks

Craft uses 7 hook events to manage state, enforce permissions, and track progress:

- **SessionStart** — Load context, set status line
- **PreToolUse** — Gate write permissions by mode
- **PostToolUse** — Track file changes, update progress
- **PostToolUseFailure** — Log and recover from failures
- **PreCompact** — Export progress before context compaction
- **UserPromptSubmit** — Inject active cycle/story context
- **Stop** — Guard against unclean stops

## Quality Gates

Every story passes through:

1. **TypeScript check** — Type safety
2. **Lint check** — Code quality
3. **Format check** — Consistency
4. **Tests** — Affected tests must pass
5. **Accessibility** — WCAG AA compliance
6. **Build** — Must build successfully

Plus polish requirements:
- Loading states (skeletons, not spinners)
- Error handling (recovery, not just display)
- Empty states (helpful, not blank)
- Keyboard navigation
- Responsive design
- Subtle animations

## Testing

```bash
./tests/run-all.sh
```

30+ bash tests covering hook scripts, state management, and lifecycle operations.

## MCP Integration

Craft uses `chrome-devtools` MCP for the Analysis Phase:
- Screenshot capture
- Accessibility audits
- Element inspection
- Console log capture
- Performance tracing

The `browser` skill (`/craft:browser`) uses `playwright-cli` as an alternative to Chrome DevTools MCP. Playwright saves accessibility snapshots to disk as YAML files (~27k tokens per task) rather than streaming them into context (~114k tokens per task) - approximately 4x cheaper in token cost. It also supports persistent named sessions steerable via SendMessage. Both tools coexist; playwright-cli is purely additive.

To use `/craft:browser`, install playwright-cli globally:

```bash
npm install -g @playwright/cli && playwright-cli install-browser
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow.

## License

[MIT](LICENSE)

---

Built with ❤️ using Claude Code
