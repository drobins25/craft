# Craft - Design Reference

> Architecture reference for `craft`, a Claude Code plugin that turns the CLI into a development harness. README.md covers what craft is and how to use it, this file covers architecture and internals, and CLAUDE.md is the operating contract Claude works under in this repo.

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
├── commands/                  ← Slash command definitions (36 commands)
│   ├── craft.md               ← Main entry point
│   ├── craft-ask.md           ← Consult a workshop agent (intelligent routing)
│   ├── craft-become.md        ← Agent crystallization (4-phase: research→checkpoint→crystallize→save)
│   ├── craft-docs.md          ← Documentation generation (two-pass: brief then generate)
│   ├── craft-init.md
│   ├── craft-dashboard.md     ← Opens the project graph page - rebuilds first, offers a template pull when stale, then opens (distinct from craft-status.md's terminal snapshot)
│   ├── craft-decisions.md     ← /craft:decisions - the Shelf: renders decisions live from decisions-view.sh, writes through decisions-capture.sh and decisions-transition.sh only
│   ├── craft-guide.md         ← /craft:guide - read-only help on how craft works and what your `.craft/` state means
│   ├── craft-annotate.md      ← /craft:annotate - point at anything in a live tab; each sent pin lands as a live change through the run's session.css, and the run is filed as a record (user-invoked only; the one flow that waits)
│   ├── craft-dial.md          ← Live value calibration shell (candidates injected into the running app)
│   ├── craft-mockup.md        ← Live mockup funnel shell (diverge→refine→polish, solidify at acceptance)
│   ├── craft-notebook.md      ← Low-ceremony capture (ideas/todos/notes); conversational graduate/done
│   ├── craft-bugs.md          ← /craft:bugs - file a bug without fixing it; opens with the open pile via shell preprocessing (the one command with allowed-tools), reads commands/references/bugs-record.md
│   ├── craft-riff.md          ← Riff: the game - two-player idea passing in the main loop; bare invocation seeds from the oldest open notebook idea
│   ├── craft-planning.md
│   ├── craft-status.md
│   ├── craft-project.md
│   ├── craft-review.md        ← PR-style review with standard and --maze modes; writes a record per run (commands/references/review-record.md)
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
│       ├── workflow-formats.md    ← Shared schema reference (frontmatter, stage-file format)
│       ├── annotate-inline.md     ← The raw-tab annotate flow (arm or reuse, begin, inject, change watch, one apply per SEND, re-inject, teardown, file, exits)
│       ├── annotate-overlay.md    ← The comment-mode overlay source, canonical annotate clear, port stamp, channel protocol
│       ├── dial-inject.md         ← Dial injection contract (handles, MEASURE/INJECT/TOGGLE/CLEAR, canonical clear)
│       ├── dial-inline.md         ← The dial flow logic (single source of truth, read inline)
│       ├── mockup-inline.md       ← The mockup funnel logic (single source of truth, read inline)
│       ├── story-from-craft-designs.md ← Story source: search, list, pick and hand-off for the mockups and annotate runs waiting to be built (read by story-new and cycle-design)
│       ├── story-from-annotate.md ← Story ramp: pre-fill a story from an annotate record (the look carries verbatim, content becomes scope; selector and component are anchors)
│       └── story-from-mockup.md   ← Story ramp: pre-fill a story from a converged mockup (CSS normative)
├── skills/                    ← Orchestrator-context skills (11 skills)
│   ├── approve/               ← Scoped write permission gate (AskUserQuestion + TaskCreate)
│   ├── browser/               ← playwright-cli browser automation launcher
│   ├── content-spark/         ← Surface content assumptions before creative/planning
│   ├── creative-spark/        ← Generate creative options; supports muse/alchemist drivers
│   ├── design-vibe/           ← Visual cohesion review across stories
│   ├── adhoc/                 ← Adhoc fix or tweak; shell + references/{fix,tweak}.md
│   ├── lock-decision/         ← Formalize approved decisions
│   ├── plan-chunks/           ← Batch planning with file-based dependency verification
│   ├── validate-chunk/        ← Validation via git diff (not spec file list)
│   ├── refine-chunk/          ← Targeted fixes for validation failures
│   └── test-fix/              ← Triage failing tests, fix the right thing
├── hooks/
│   ├── hooks.json             ← Hook event definitions
│   ├── register.tsx           ← Hooks module (Claude Code 2.1.287+): the progress band and `/craft-progress`
│   ├── take.ts                ← Reads craft's files and decides what the band shows
│   ├── draw.tsx               ← Turns the snapshot into the band's two lines
│   └── scripts/               ← 45+ bash/python hook scripts
│       ├── annotate-run.sh        ← Single entry seam for the annotation channel (arm / listen / ready / status / wait / clear / announce / begin / watch / sheet / apply / stamp / kind / loader / bake / strip / ensure / send / review-clear / sweep / disarm / style; arm --background prepares the session, listen execs the listener so it can run as a Claude Code background command, ready waits for its port, and plain arm keeps the detached launch; style prints a read-only computed-style lookup for evaluate_script)
│       ├── devtools-launch.cjs    ← Browser server launcher: pinned chrome-devtools-mcp, statistics off, shared profile or isolated window decided at the first browser call
│       ├── annotate-resolve.sh    ← Pin to source: probe / resolve / where - the probe runs in the page at SEND; maps the page's matched rules and the component name to project files, honest about bundles, cached per run in resolutions.json
│       ├── annotate-record.sh     ← Files a run as .craft/annotations/<date>-<slug>/ (record.md + session.css), graduates it (story, tweak or todo), closes it (abandoned, files kept) and lists the runs cut short (open + outcome error, read-only); the sweep and the next begin file orphaned runs, and a run begun with --resume carries the old record's pins into its own record and graduates the old one
│       ├── annotate-root.sh       ← Shared folder lookup for the three annotate scripts: --root, then CRAFT_PROJECT_ROOT or the set-up project, then the nearest folder above the current one that already holds the named session or record, so a session armed in a project that never ran init is found without repeating --root; never picks where a new session is made, and commands that name none never walk
│       ├── annotate-external-gate.sh ← External-page pin boundary: holds tool calls outside a closed allowlist while an annotate session is on a page outside the project (PreToolUse), lifted for one turn by a typed message (UserPromptSubmit)
│       └── annotate-channel.py    ← Per-session capture listener (dynamic port, serves the overlay at /overlay.js, replace-the-set / tombstone, history.jsonl ledger, CORS, per-session token and Host check on every route, socket timeout, SSE stream, client registry)
├── types/
│   └── index.d.ts             ← The band's `$.state` contract, named by plugin.json `types`
├── tsconfig.json              ← Local type-checking against the engine-written `.claude-plugin/types/`
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
├── reference/                 ← Orchestration-critical (injected by hooks, read by skills at runtime)
│   ├── calibration-loop.md    ← Shared technique: boundary elicitation (creative-spark +)
│   ├── cold-start-index.min
│   ├── hunch-settling.md      ← Shared technique: executable-threshold gate (mockup funnel +)
│   └── orchestration-index.min
├── docs/                      ← Human-facing documentation (informational, not auto-loaded)
│   ├── agent-catalog.md
│   ├── ci-branch-protection.md
│   ├── creative-workshop.md
│   ├── decision-tree.md       ← Routing map: every /craft path, as flowcharts
│   ├── design-philosophy.md
│   ├── plan-tdd-enforcement.md
│   ├── research-agentic-research-patterns.md
│   └── workflow-reference.md
├── scripts/                   ← Self-contained toolchains outside hooks/
│   ├── map/                   ← Living Map structural generator (Node; seam: map-run.sh)
│   ├── dashboard/             ← Dashboard graph data builder (python stdlib; seams: dashboard-run.sh builds the graph data, dashboard-page.sh delivers the page template; parse_annotation.py reads annotate records for it; output: .craft/graph/, .craft/dashboard.html)
│   ├── ci/                    ← CI helpers: run-suite-group.sh, annotate-check.sh + annotate-probe.mjs (real-browser annotate check), browser-check.sh + browser-probe.mjs (dashboard page check), check-template-stamp.sh
│   └── check-doc-drift.sh     ← Doc drift check (changelog vs plugin.json, feat push gate)
├── tests/                     ← Bash test suite (30+ bash tests)
│   ├── run-all.sh
│   ├── test_helper.sh
│   ├── fixtures/
│   └── test-*.sh
├── CHANGELOG.md               ← User-facing release notes (notable changes only)
├── CLAUDE.md                  ← Auto-loaded every session
├── DESIGN.md                  ← This file (reference only)
└── README.md                  ← Human-facing docs
```

### Map subsystem boundary (Cycle 10, planned)

The Living Map's structural generator lives in a dedicated top-level `scripts/map/` - craft's first Node toolchain. It is **self-contained and invoked only via `scripts/map/map-run.sh`**: nothing else in craft sources or imports `scripts/map/` internals (the `/craft:status` renderer, agent cold-start push, and pull-on-demand all go through `map-run.sh` and nowhere else). Distribution is a bundled single-file `runner.js` (esbuild, no shipped `node_modules`) plus committed grammar `.wasm` data assets under `scripts/map/grammars/`; `node_modules/` is gitignored (build-time only) and a maintainer build step regenerates `runner.js`. The map stays in craft core (not a companion plugin), but this single-seam boundary keeps a future extraction a mechanical move rather than a rethink.

---

## Statuses

| Status | Meaning |
|--------|---------|
| `draft` | Just an idea, not planned |
| `planning` | Being designed, decisions captured |
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

Chunk specs lock **seams, not interiors**. The planner pins contracts (signatures, shapes, routes, invariants - each line carrying a receipt: `[verified: attack evidence]`, `[owner: Chunk N]`, `[investigation: reason]`, `[visual-source: where the look was decided]`, `[defines]`); the implementer owns function bodies and test bodies. No copy-pasteable code in plans - code appears only when the code IS the decision.

A planned story carries four planning artifacts (format reference: `skills/plan-chunks/references/chunk-format-guide.md`):

- **`## The Pitch`** - the plan's guarantee plus a conditions table of every load-bearing assumption, tagged `verified` / `system-owned` / `unverifiable -> becomes Chunk N's first test`. Doubles as the implementer's tripwire watchlist.
- **`## Investigation`** - the planner's causal research narrative, dead ends kept. Transfers the planner's headspace to the implementer and any future re-planner.
- **`## Acceptance Pre-Flight`** - one row per acceptance vehicle, symbolically walked through the path it exercises using the test's own data shape; any `UNREACHABLE` verdict blocks plan acceptance (walk reference: `skills/plan-chunks/references/acceptance-walkthrough.md`).
- **`## Chunks`** - cut bottom-up at layer rungs; later chunks cite earlier chunks' real output via `[owner: Chunk N]`, which self-freshens the spec.

For `type=ui` stories, per-element visual intent lives as an **Element Binding Table** in `## Visual Direction` (the source of truth); each chunk binds the rows it builds as Contract lines carrying a `[visual-source:]` receipt. Visual token assignment is a seam, not an interior - two implementers can assign different valid tokens to the same element, so it is pinned in Contracts rather than left to the implementer. Verification is two-tier: a plan-time enumerating gate (every non-`TBD` row is bound by some chunk) plus a project-local rendered-fidelity Done-When check.

Two escape valves keep the autonomy honest: the planner may stop mid-flight only for a **PLAN FORK** (a user-owned question whose answers produce two different plans) or a **RESEARCH REQUEST** (a load-bearing outside fact three searches did not settle; the orchestrator researches it inline, re-runs alignment and re-launches the planner), and before alignment the orchestrator researches any outside premise the project does not hold (`commands/references/research-inline.md`); the implementer stops on **CONTRACT MISMATCH** (reality contradicts a receipted contract - the report is a deliverable, the orchestrator amends the plan, never the implementer). Lower-stakes decisions are made in flight and triaged by **product-stake** (silent / mention / ask, judged against a perfectionist product owner) rather than confidence alone.

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

**Included skills:** content-spark, creative-spark, design-vibe, lock-decision, plan-chunks, adhoc, approve, browser
**Included agents:** plan-chunks-agent, project-scanner, muse, riff, alchemist, conductor, doc-writer, product-anthropologist, pr-reviewer-expert, maze-architect, researcher, research-synthesizer, verifier, practitioner-reviewer, playwright-browser, become-researcher, crystallizer, guide
**Included commands:** craft, craft:init, craft:cycle-design, craft:cycle-start, craft:cycle-complete, craft:cycle-assign, craft:story-new, craft:story-archive, craft:story-delete, craft:status, craft:update-docs, craft:docs, craft:project, craft:review, craft:become, craft:ask, craft:workflow, craft:workflow-run, craft:workflow-design, craft:research, craft:research-verify, craft:adhoc, craft:mockup, craft:dial, craft:annotate, craft:bugs, craft:dashboard, craft:decisions, craft:guide, craft:notebook, craft:planning, craft:reflect, craft:riff

### Implement Phase

Full write access, gated by `CRAFT_WRITE_ENABLED` in `.global-state`.

**Allowed tools:** Read, Write, Edit, Glob, Grep, Bash, Task
**Included skills:** validate-chunk, refine-chunk, test-fix
**Included agents:** implementer, tester, chunk-validator, claims-auditor
**Included commands:** craft:story-implement, craft:story-implement-auto, craft:story-continue

### Analysis Phase

Triggered by `/craft:analyze` after a cycle ships. No restricted write scope - runs in the active session context.

**Included agents:** qa-analyzer, ux-analyzer, creative-analyzer, style-analyzer, walkthrough-analyzer
**Included commands:** craft:analyze, craft:review

---

## Hooks Detail

All hooks defined in `hooks/hooks.json`. Scripts in `hooks/scripts/`.

### SessionStart
- **`session-start.sh`** (once) - Detects active cycle, sets status line, loads context, runs the annotate sweep
- **`post-compact-reinject.sh`** (on compact) - Re-injects craft context after context compaction

### PreToolUse (Write|Edit)
- **`check-write-permission.py`** - Enforces write permission gating. Checks for active story/cycle context, `CRAFT_WRITE_ENABLED` flag, active workflow session, and allowed paths. Also denies the Write tool on an existing `.craft/design/tokens.yaml` (merge target - redirects to `merge-tokens.py`; Edit and creation stay allowed). Uses hardcoded logic (no external config file).
- **`check-craft-vocab.py`** - Denies writes whose code comments carry craft planning citations ("Chunk 3", "Story 4", tokens.yaml key paths). Off switch: `VOCAB_GATE=false` in the written file's project `.global-state`. Also a CLI: `--scan <files>` reports leaks for validation sweeps, checking only the lines each file adds against the last commit and falling back to the whole file when git cannot tell; `--scan --all` reads whole files. A comma-joined argument is split into paths; a path it cannot read (and git does not show deleted) is printed as not scanned, and the scan fails when it could read none of its files.
- **`merge-tokens.py`** - Not a hook: a CLI invoked by craft-init's token phases. The sole writer for merges into an existing tokens.yaml - `report` mode emits a mechanical per-key CONFLICT/NEW/SAME diff for the token AUQs; `merge` mode does a line-surgical keyed union (snapshot, self-verify, restore-on-violation). Lives here beside the hook that enforces it.

### PreToolUse (Bash)
- **`push-gate.sh`** - Denies a `git push` while custody signals are live (untriaged leftovers, secret-shaped paths in the outgoing range). Never grants approval: a clean push falls through to the user's own permission flow.

### PreToolUse (all tools)
- **`annotate-external-gate.sh pre-tool`** - Deny-only boundary for annotate sessions on a page outside the project. While `annotate-run.sh` has marked a session external (`external.json` plus a pointer in `~/.cache/craft/annotate-boundary/` keyed by the conversation's pid, found by walking the hook's ancestors), every tool call outside a closed allowlist is denied, unless the user typed a message this turn (see `annotate-external-gate.sh prompt` below). The allowlist: `ToolSearch`, `TaskOutput` and `TaskStop`; `Read` of an absolute path inside the plugin; `Bash` or `Monitor` running exactly `bash <plugin>/hooks/scripts/annotate-run.sh <verb>` with one of `arm`, `listen`, `ready`, `status`, `ensure`, `begin`, `watch`, `wait`, `sheet`, `apply`, `stamp`, `loader`, `kind`, `send`, `announce`, `review-clear` or `style`, or `annotate-resolve.sh where`, on one line with arguments holding no shell syntax beyond words and double quotes (one quoted heredoc may follow), and any `--root` or `--owner-pid` naming the owner's own session project or the owner's own pid; and from the chrome-devtools browser tools: `list_pages`, `wait_for`, `take_snapshot` / `take_screenshot` only when they return their result inline (a call that saves to a `filePath` is denied), and `evaluate_script` only when it returns its result inline (a call that saves to a `filePath` is denied, even for craft's own page script) and only for craft's own page scripts (a line `loader`, `stamp`, `sheet`, `apply`, `style`, `review-clear` or `annotate-resolve.sh probe` printed, each data slot holding exactly one value of its kind, or a snippet fence from the annotate references pasted as the body of `() => { ... }`; any other script waits for a typed yes). Never answers allow or ask. If the process list cannot be read while any conversation's boundary is live, the call cannot be matched to its owner and is held; any other error while checking a call also holds it. A pointer 12 hours past its last refresh, or whose session folder is gone, is removed with a visible message. Costs one bash glob per call when no boundary exists. Calls from subagents abstain.

### PostToolUse (Write|Edit)
- **`update-progress.py`** (async) - Tracks which files were modified, updates story progress counts

### PostToolUseFailure
- **`handle-tool-failure.py`** (async) - Logs tool failures, appends to recovery log

### PreCompact
- **`export-progress.sh`** - Exports current progress state before context window compaction

### UserPromptSubmit
- **`inject-craft-context.sh`** - Injects active cycle/story context into every prompt
- **`annotate-external-gate.sh prompt`** - Lifts the external-page boundary for one turn when the user types a message: records that turn's `prompt_id`, and a tool call is lifted only when its own `prompt_id` matches. Prompts that open with a task notification or another session's message, or carry an `EXTERNAL ADDED` / `EXTERNAL EDITED` line, never lift and remove any lift. Prints nothing. `annotate-run.sh` also removes the lift before it prints or sends any external pin, so a pin never rides an earlier yes.

### Stop
- **`stop-hook-guard.sh`** - Guards against unclean session stops, ensures state consistency

### Hooks module
`hooks/register.tsx`, listed under `modules` in `hooks/hooks.json`, runs on Claude Code 2.1.287 and later; older versions skip it and the rest of craft is unaffected (the ready row's button needs 2.1.295). It draws one progress band above the prompt with two views, planning and building, and registers one command. The module is split three ways along the I/O line: `register.tsx` wires the hooks and holds the session state, `take.ts` reads craft's files and decides what the band shows, and `draw.tsx` turns that into the two lines.

- **`session.start`** - Reads craft's state and starts a three-second refresh and a frame timer for the sheen; a non-interactive run (`-p` or the SDK) has nothing to draw on, so it reads nothing and starts no timer
- **`command.run` for `craft-progress`** - Hides or shows the whole band, in either view
- **`ui.render` for `AbovePrompt`** - Draws the planning view or the building view; it yields only to a survey (a question card does not hide it)
- **`turn.start` / `turn.complete`** - A new main-loop turn clears a question card an aborted turn left open; a validator's turn end returns the state to `building`
- **`tool.call`** - A question card up in this session adds `waiting on you` and freezes the sheen; a call to the stage script (`planning-stage.sh`) names the story this session is planning
- **`agent.spawn`** - The chunk validator or the claims auditor spawning moves the building state to `validating`

Both views read `✶ <View> Story N · <state> · <title>` with the second line indented under the view word. The building view draws one ball per chunk of the story being built (a green ring on the chunk in progress, a filled green ball once it passes) and the state `building`, `validating` or `complete`. The planning view draws one ball per step of the six-step planning flow, `step k of 6`, the minutes since the stage first appeared and `next: <step>`; with several stories mid-planning and none of them this session's it reads `Planning N stories`. Precedence: the story this session is planning, then the building view while a story is current, then any story carrying a stage, then the finished story's complete row, then nothing.

The planning view reads the `planning_stage` field in story frontmatter, which plan-chunks writes at each phase through `planning-stage.sh` and clears when planning ends or stops by a path the flow handles (a killed session leaves it until the story's status changes), so every terminal on the project sees it and nothing is added to the state files. When this session's story loses its stage and reads ready, this terminal alone holds a still `ready to implement` row in session memory, writing nothing to disk; its state text is a button that turns the band into a two-line chooser: the row's own story first, then the active cycle's ready stories. Choosing one asks for confirmation; start re-checks the story and the slot, then runs `/craft:story-implement` with the story's `.craft/` path. While a story is implementing, the row reads `ready to implement · after Story N` and is not pressable.

The sheen is a two-letter highlight sweeping the view word, 12 frames at 5 a second. It follows the story, not the conversation: it keeps moving while the story builds in background agents, and freezes while a card is up, for another session's planning story, and on the `ready to implement` and `complete` rows. `progress_band_motion: false` in `.craft/settings.yaml` stops all movement; an absent key means on and craft never writes it.

The band reads `.craft/.global-state`, the active cycle's `.state`, story files' frontmatter and `.craft/settings.yaml`, and writes nothing of craft's: the hidden flag, the held ready row, the chooser and the snapshot live only in session memory. Its value shapes are typed in `types/index.d.ts`.

### Utility Scripts (called by hooks or commands)
| Script | Purpose |
|--------|---------|
| `create-checkpoint.sh` | YAML state snapshots before chunks (no commit; git commit at complete-story.sh) |
| `create-cycle.sh` | Scaffold a new cycle directory |
| `create-story.sh` | Create story file from template |
| `resolve-go.py` | Read a copied tracker issue's comments, find the newest Go, print the stage it grants (plan, build, build and open the PR, or hold) and the first line to show |
| `go-brief.py` | Read a copied Go, or a tracker cycle's newest copy, into the pickup brief and whether Craft answers its own prompts |
| `cycle-stage.sh` | Read-only: say whether a cycle may be implemented from its recorded stage; a cycle with no issue or no recorded stage may, build stages may, plan, hold and any empty or unknown stage stop |
| `find-issue-cycle.py` | Find the planning, ready or active cycle a tracker issue already has |
| `snapshot-delta.py` | Copy only the comments and issue text new since the last copy into a tracker cycle's context |
| `record-go.py` | Re-resolve the newest Go from that copy and update the cycle's stage record |
| `follow-issue.py` | Tell a planning flow whether a tracker cycle still matches its issue (`commands/references/tracker-follow.md`): `check` records a rewritten title or description in the cycle, and `keep` or `update` answer the card, mark the context README's issue copies `(current)` or `(superseded)`, and clear the record |
| `question-answers.py` | List which questions Craft posted on the issue now have answers |
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
| `get-latest-cycle.sh` | Resolve the most recent cycle directory path (`--status=` filters by cycle status) |
| `update-global-state.sh` | Update .global-state key-value pairs |
| `update-cycle-state.sh` | Update cycle .state file |
| `update-story-status.sh` | Change story status in frontmatter; clears the story's planning stage on ready, active and complete |
| `planning-stage.sh` | Write, rewrite or clear a story's `planning_stage` frontmatter field, the one line the progress band's planning view reads |
| `statusline.sh` | Generate status line display |
| `find-workshop.sh` | Locate .craft/ directory. Also owns the shared before-init lookup (`craft_before_init_root`: the set-up project, then the git top level, then the current folder) and the monorepo-top refusal (`craft_refuse_monorepo_top`) that bugs and notebook captures use |
| `discover-projects.sh` | Find all craft projects |
| `count-requests.sh` | Count pending items in requests queue |
| `process-request.sh` | Route a request to a story or cycle |
| `salvage-partial-work.sh` | Recover work from interrupted sessions |
| `append-recovery-log.sh` | Log recovery events |
| `read-events.sh` | Read from the event log |
| `append-event.sh` | Append an entry to the event log |
| `aggregate-failures.py` | Aggregate failure records for triage |
| `gate-signals.sh` | Fingerprint the project's stack signals and hold per-signal gate-reconcile state |
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
│   │       ├── context/           ← Verbatim tracker snapshot, only on tracker-sourced cycles
│   │       ├── .state         ← Current story/chunk progress
│   │       ├── .failures      ← Failure tracking for retry logic
│   │       ├── .learnings.yaml ← Cycle learnings for reflection
│   │       └── stories/
│   │           └── 1-story-name.md
│   ├── checkpoints/           ← Chunk rollback points (YAML)
│   ├── fixes/                 ← Adhoc fix records (created by /craft:adhoc, bug path)
│   │   └── fix-name.md        ← category, root cause, solution, lesson
│   ├── tweaks/                ← Tweak records (created by /craft:adhoc, open until accepted)
│   │   └── tweak-name.md      ← surface, kind, attempts, verbatim reactions
│   ├── analysis/              ← Persistent analysis findings
│   │   ├── pending/           ← Findings queue (survives sessions)
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
│   ├── bugs/                  ← Open bug records (created by /craft:bugs)
│   │   ├── YYYY-MM-DD-slug.md
│   │   └── closed/            ← Fixed or won't-fix bugs
│   │       └── YYYY-MM-DD-slug.md
│   ├── reviews/               ← Review records (created by /craft:review, one per run, clean or not)
│   │   └── YYYY-MM-DD-slug.md
│   ├── design/                ← Design system (enforced)
│   │   ├── tokens.yaml        ← Design tokens
│   │   ├── components.md      ← Component patterns
│   │   ├── locked.md          ← Approved patterns (enforced)
│   │   ├── animations.md      ← Animation patterns
│   │   └── .confidence-signals.yaml ← Scan signals: token confidence (use_count, file_count, consistency_score, recency) + total_files (drives init's first-move recommendation)
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
│   ├── mockups/               ← Mockup artifacts (created by /craft:mockup)
│   │   └── {date}-{slug}/
│   │       ├── mockup.html    ← The living page (replaced per round)
│   │       ├── record.md      ← Durable anchor: status, reactions, polish ledger, materials, backlinks
│   │       ├── assets/        ← Orchestrator-fetched fonts/icons (inlined into the page; travels with the folder)
│   │       └── rounds/        ← Archived outgoing rounds (never rendered)
│   ├── annotations/           ← Annotate records (created by /craft:annotate): <date>-<slug>/ with record.md + session.css; live session folders sit beside them and are swept
│   ├── dials/                 ← Dial session records (created by /craft:dial, born closed - no lifecycle)
│   ├── decisions/             ← Decision records (created by /craft:decisions)
│   │   ├── YYYY-MM-DD-slug.md ← Pending: waiting on a ruling
│   │   ├── approved/          ← Ruled decisions (law); claimed and shipped ones stay here
│   │   └── archive/           ← Declined or retired decisions
│   ├── project.md             ← Project DNA
│   ├── quality.yaml           ← Quality gates
│   ├── settings.yaml          ← Craft settings
│   ├── .global-state          ← Active cycle, global config
│   └── .continuation          ← Breadcrumb for skill continuation (transient, 30-min TTL)
└── src/
```

Projects that gitignore `.craft/` get local-only persistence for everything under it - stories, records, mockups alike. That is the existing craft convention (state is per-machine unless the project chooses to track it), not a gap in any one feature.

When the mockup builder needs material it can't fake (a real typeface, a specific icon set), the orchestrator fetches the asset files from pinned open-license sources (Google Fonts; the jsDelivr CDN mirror of the official Lucide/Phosphor/Heroicons packages) into the mockup's `assets/` folder and wires them into the page - the builder designs with the real material, the page still makes zero requests at load, and the project itself is never touched. Graduation forwards the material's identity (recorded in record.md `## Materials`), never the inlined bytes.

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
- `CRAFT_WRITE_ENABLED` - gates writes outside `.craft/`. Set to `"true"` by active stories, the `adhoc` skill, and the `approve` skill. Empty string means closed.
- `CURRENT_WORKFLOW_SESSION` - active workflow session path (set when a workflow session is running).
- `RUN_MODE` - `autonomous` when an unattended run is active (set by `story-implement-auto`), empty otherwise. Normal cruise runs leave it empty; cruise is craft's single default behavior (chains chunks and stories, stops only at decision points or on failure), not a stored mode. A Go run is decided from the copied Go, never from `RUN_MODE`; `RUN_MODE` becomes `autonomous` only once a build-stage Go run hands off to `story-implement-auto`.
- `CYCLE_STATUS` - current state of the active cycle.

### cycle.yaml Schema

```yaml
name: cycle-slug
title: 'Cycle NN: Display Title'
status: planning | ready | active | complete
created: YYYY-MM-DD
updated: YYYY-MM-DD
target: 'One-line description of what ships'
focus: Primary focus area
source_concept: [planning/concept-a.md, planning/concept-b.md]   # may be empty []

goals:
  - Outcome 1
  - Outcome 2
```

Craft's scripts write `title` and `target` (`create-cycle.sh`), and `focus` and `goals` once they hold ticket text (`cycle_values.py`), as one single-quoted line each with every `'` doubled. Older double-quoted or plain values still read.

**`source_concept`** - YAML flow list of planning doc paths (relative to project root) this cycle is sourced from. Empty list `[]` means the cycle is freeform (no planning source). When populated, cycle-design routes story-creation moments to the From planning protocol (`commands/references/story-from-planning.md`) so each planning-extracted story's spark draws from the planning content. Stories added during the add-a-separate-story moment within a planning-sourced cycle remain freeform and get no `source_concept` of their own. Captured at cycle creation via `create-cycle.sh`'s 5th positional arg, gated behind the Step 1 verbatim-quote rule + AskUserQuestion safety gate.

**`source_issue`, `authorized_stage`, `go_author`, `go_date`** - Present only on tracker-sourced cycles, as one-line single-quoted keys directly after `source_concept`. A cycle created without an issue has none of them, and a cycle for an issue that had no Go has only `source_issue`. Written by `create-cycle.sh`'s 6th to 9th positional args (issue key, stage, Go author, Go date); the stage and what follows it are left out when the issue had no Go. `authorized_stage` is `plan`, `build` or `build and open the PR`; a hold Go creates no cycle. Both build stages require `go_author` and `go_date`. `go_author` and `go_date` are the tracker's record of the Go that granted the stage and are never rewritten by lifecycle scripts. Only a refresh (`record-go.py`) updates the three, and only when it finds a newer Go: a Go on a cycle that had none adds them, and an unreadable newest Go narrows the stage to `plan`. The issue's status never grants or limits work; only the newest Go does. `cycle-stage.sh` reads them before implementation starts: no `source_issue` or no `authorized_stage` key means implement (an issue with no Go works as before), build stages implement, and `plan`, `hold`, or an empty or unknown stage stop.

**`context/`** - Created by tracker intake (`commands/references/tracker-intake.md`) when a cycle starts from an issue key or URL. Holds the issue and every comment copied verbatim, the Go comment when one exists, and a README naming the source. Stories written into the cycle cite these files by absolute path so planning starts from what was decided. Each refresh (`commands/references/tracker-refresh.md`) adds dated files with only the comments and issue text that are new, and earlier copies are never changed. A follow (`follow-issue.py`) also marks each issue copy's README row ` (current)` or ` (superseded)`; the copy files themselves are never changed.

---

## Planning Alignment

Concepts in `.craft/planning/` (managed by `/craft:planning`) have an alignment walkthrough that resolves a concept's strategic sub-decisions before stories get created. The architecture has three load-bearing parts:

**TaskTool queue.** The orchestrator's speculative working list of sub-decisions for a concept lives in TaskTool - session-scoped, allowed to die. The model only sees one task at a time, so multi-decision AskUserQuestion bundles become structurally impossible. Re-derivation on session resume is correct behavior; not loss.

**Three completion destinations.** Every sub-decision terminates in exactly one place: `## Locked decisions` (conversational resolution + explicit lock-confirmation ask - the orchestrator must ask "Want me to lock this as X?" before writing), `pending_decisions[]` frontmatter (user deferred - regenerates as a task on next session), or `## Open questions` with owner annotation (blocked on someone else - doesn't auto-nag).

**Step 9 destination-coverage gate (intra-session).** Before story creation runs, the gate verifies every closed task landed in one of the three destinations. Tasks that closed without filing block story creation and route back to alignment with the unaccounted items named. Cross-session integrity is handled by the immediate-write rule (Locked entries hit disk at the moment of resolution), not by the gate.

The depth ceiling is prose-enforced: planning is for strategic decisions (the ones that shape which stories come out of the concept), not implementation detail. If candidate extraction returns more than ~10 items, the orchestrator reframes some as story-new / plan-chunks work and defers them.

---

## Notebook Lifecycle

The notebook (`/craft:notebook`, `.craft/notebook/`) is a capture surface for ideas, todos, and notes that sit below the backlog. State transitions are conversational, not subcommand-driven:

- **Ideas** start in `ideas/YYYY-MM-DD-slug.md`. When an idea matures into story-shape, the user signals graduation; the orchestrator routes to `/craft:story-new` with the idea pre-filled and flags the idea in place (it stays, marked as graduated, for traceability).
- **Todos** start in `todos/YYYY-MM-DD-slug.md`. When done, the orchestrator confirms via AskUserQuestion (always - asymmetric failure visibility for the destructive action) and moves the file to `todos/done/`. Todos also graduate: when a todo becomes a story, the graduation closes it - `notebook-done.sh <file> <story-slug>` moves it to `todos/done/` with `graduated_to` recording the story that owns the tracking now. The graduate accept is the single consent for both effects (the offer names both); no separate done-AUQ fires on that path. The `graduated_to` ref is generic (story slug, tweak record, fix record) - only the story path is wired today.
- **Notes** start in `notes/YYYY-MM-DD-slug.md` and have NO lifecycle - they never graduate and never get "done." A note is a durable, project/team-local fact whose value is future recall (paragraph 1 = the distilled timeless fact, paragraph 2 = provenance). Each carries a `facet` (`infrastructure | tooling | ownership | process | convention | gotcha`) that keys WHEN it resurfaces. Recall is hybrid: `session-start.sh` injects a one-line-per-note index every session (via `notebook-notes-index.sh`), and the full body is read on demand when the current work matches the facet/topic. Staleness is handled the Claude-memory way - dated filenames + the always-loaded index + "as of {date}" recall framing - not a TTL.
- **Deferral markers** in conversation ("later", "side note", "don't forget", "for next time", etc.) trigger an inline mention of `/craft:notebook` as a closing line. On accept the orchestrator captures silently with session context. No subcommands.

The lifecycle deliberately keeps every state fast: capture is one line, graduate is one prompt (for a todo, that one prompt also closes it), done is one AUQ, and a note is captured silently on an accepted inline offer. Power-user subcommand syntax is explicitly rejected in favor of conversational verbs. Claude offers notes proactively only above a high durability bar (no built-in/vague expiry), mirroring the high-bar-for-Claude / low-bar-for-user discipline of the deferral-marker offer.

## Decision Records

`/craft:decisions` keeps a product ruling in one place before it has a cycle, a story, or a name, so nothing gets decided twice. The command renders the Shelf live from `.craft/decisions/` through `decisions-list.sh` and `decisions-view.sh` and never from memory. Every write to a record goes through two scripts: `decisions-capture.sh` creates a record or reopens one, and `decisions-transition.sh` is the only way a record changes state. A record is never written by hand. The one other edit the command makes is after a retire: it removes the slug from the `decisions:` line of any claiming story still in planning or ready.

Where a record sits is its state. A pending record is in the root of `.craft/decisions/`. Approving it moves it to `approved/` as `status: accepted`, and declining it moves it to `archive/` as `status: declined`. Retiring ruled law also lands in `archive/`, as `deprecated`. The room and the status are written in the same step so they cannot disagree. The ruling itself is the user's typed answer, kept verbatim under `## Approval`, and the answer is passed on stdin so the user's words never sit on a command line.

The Shelf's `○` unclaimed and `●` claimed are not stored. `decisions-list.sh` derives them by scanning story files: a record is claimed while a story that is not complete carries its slug in the story's `decisions:` frontmatter. `✓` done is the one stored disposition: `crafted`, stamped by the `craft` transition when `complete-story.sh` finishes a story that carries the decision. Once crafted, a record is frozen: reopening or retiring it is refused, and the way to change your mind is a new decision. Reopening law requires a fresh approval line, reopening a pending record is a quiet reshape, and the archive is never reopened.

A story carries only the decisions the user names for it. The planner and the alignment check read them as the frame the story fills in, so a question a ruling already answered is not asked again. Retagging moves records between topics without touching their room or status.

## Bug Records

`/craft:bugs` files a bug without fixing it, for a person mid-conversation or an agent mid-run. A bug found during a long test pass cannot be fixed on the spot because the run's own state depends on the code staying still, so the record has to hold enough to reproduce the bug from scratch. One file per bug lives in `.craft/bugs/` as `YYYY-MM-DD-slug.md`; the first line names the symptom in the user's terms, never a suspected cause, and the slug follows it. Seven fields are required at filing (symptom line, `found_during`, Expected, Actual, Consequences, Blocks my next step, Reproduce) and `bugs-capture.sh` refuses a record missing any of them. There is no severity field; the Consequences section is what a reader ranks the pile by.

There are two rooms. The open folder holds what is still broken, and closing a bug (`bugs-close.sh`, after one confirmation) moves it to `closed/` with a stamped close time and a Log line, so "what is still open" never costs a read of every record that ever existed. Status is `fixed` or `wont-fix`; the verdict (`bug`, `unspecified`, `spec-gap`, `not-reproducible`) records whether it was ever a bug and stays blank until triaged. The command opens with the open pile through shell preprocessing (`bugs-list.sh --summary`), `session-start.sh` injects the same `Bugs: N open` header every session, and the dashboard reads both rooms as a `bug` type.

Three trigger tiers decide how the command is reached, mirroring the notebook. Naming it ("file a bug", "log a bug", "bug ticket") is the invocation: it runs with what the session has, no offer and no question. A deferral word plus a defect ("don't let me forget, the save button is broken"), or a bare defect named while a story or chunk is in progress, earns one ignorable inline offer naming `/craft:bugs`, because dropping active work to chase a side sighting is what the feature exists to prevent; nothing is filed until the user says yes. A bare defect in an idle session routes to `/craft:adhoc` as before. Nothing guesses from vocabulary beyond those three signals.

The analyzers feed the same pile. QA findings, and the walkthrough's blocks-ship and looks-wrong findings, file as bug records instead of queueing (UX, Creative, and Style still queue, and the walkthrough's feels-off and nitpick findings go to the UX queue), and a finding that repeats an open bug raises its `hits` count through `bugs-hit.sh` instead of filing a duplicate. The cycle-complete walkthrough files bugs and never fixes them; bug then `/craft:adhoc` is the fix path.

---

## Riff: skill and agent

Riff exists as a **skill** and an **agent** that serve different rooms.

- **The riff skill** (`commands/craft-riff.md`) is a main-loop game for two players, and the file is written for both readers - user and Claude. An idea too hot to hold alone gets passed in small beats (one concept a beat, full strength) until it's ready; the session ends at a mutual hand-stack that fires the build, and a riff that fizzles just sets the idea down - no ceremony, the notebook catches anything worth keeping warm. At the stack, Claude banks a positives-only riff memory to `.craft/riff/notes/` - the legacy layer that lets the next session's Claude walk in knowing how this table plays. No agent dispatch, no AskUserQuestion - the session never leaves the main loop. Bare `/craft:riff` opens from the oldest open notebook idea (via `notebook-list.sh ideas`), reconnecting it to what has changed since capture; with a topic, riff addresses that topic directly and the seeding never fires.
- **The agent** (`agents/riff.md`) is the crystallized deep-consultation partner, reached via `/craft:ask` and direct Agent invocation. The skill never invokes it - `agents/riff.md` stays canonical for the riffing craft it documents. Skills and agents are separate registries, so the `craft:riff` skill and `craft:riff` agent coexist without collision.

The skill mirrors the notebook trigger discipline: bounded triggers, silence as the default, and at most one inline offer per turn so riff never stacks nudges on notebook / creative-spark / design-vibe. The self-catch (a turn about to say a lot at once on an undecided direction - 2+ questions is the clearest tell, but a wall of options or analysis counts the same) is emitted by the orchestration index - the layer that assembles every turn - as one trailing ignorable offer line, never AskUserQuestion; on accept, riff is invoked visibly.

Two standalone techniques distilled from the agent's craft live on in `reference/`. The **calibration loop** (`reference/calibration-loop.md`) is a reusable boundary-elicitation technique (the "optometrist flip test") that converts a tacit "I know it when I see it" into an encodable rule; creative-spark consumes it, and content-spark, design-vibe, and lock-decision can point to it too. **Hunch settling** (`reference/hunch-settling.md`) distills the throw/pull craft into an executable-threshold gate for reaction-driven revision loops: would two different builders make the same first move from this brief? Its first consumer is the mockup funnel (`commands/references/mockup-inline.md`), which Reads it inline and settles a below-threshold reaction conversationally before briefing the alchemist - chain-safe because it runs in the main loop with no agent spawn and no Skill-tool call. Both files distill; `agents/riff.md` stays canonical.

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

*For decision trees, orchestration routing, design philosophy and TDD enforcement patterns, see `docs/` - the human-facing documentation. `reference/` holds only what the harness loads at runtime: the index files injected by hooks and the technique files skills read inline.*
