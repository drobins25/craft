# Craft Orchestration Index (Compressed)
# Injected as passive context via UserPromptSubmit hook
# Following Vercel AGENTS.md pattern: always-present routing knowledge
# Detailed instructions stay in SKILL.md files (loaded on invocation)
# Target: <3KB compressed, pipe-delimited where possible

## ROUTING: State → Action

```
STATE                              | ACTION
-----------------------------------|------------------------------------------
Story in progress (CURRENT_STORY)  | AskUserQuestion: Continue? → craft:story-continue
Planning cycle (PLANNING_CYCLE)    | All ready? → craft:cycle-start | Still planning? → craft:cycle-design
Pending requests (.craft/requests) | AskUserQuestion: Review? → Step 5b of /craft
Story status: planning (no chunks) | craft:plan-chunks (must have chunks before implement)
Story alignment: pending           | Run alignment check before plan-chunks (see commands/references/alignment-check.md)
Story status: ready                | craft:story-implement
Story in backlog (not in cycle)    | craft:cycle-assign first, then implement
Mid-chunk (CURRENT_CHUNK > 0)      | Continue implement loop (checkpoint→implementer→validate)
Validation FAILED (test errors)    | craft:test-fix (invoked BY validate-chunk, not directly)
Validation FAILED (build/lint/type)| craft:refine-chunk (invoked BY validate-chunk, not directly)
All cycle stories complete         | craft:cycle-complete
Post-cycle                         | craft:analyze (QA, UX, Creative, Style)
```

## IMPLEMENT LOOP (per-chunk sequence)

```
For each chunk 1..N:
  1. create-checkpoint.sh [story] [chunk_n]
  2. INVOKE implementer agent via Task tool (NEVER implement directly)
  3. INVOKE craft:validate-chunk via Skill tool (NEVER validate directly)
  4. validate-chunk routes failures → test-fix OR refine-chunk
  5. On pass: complete-chunk.sh runs, read >>> NEXT ACTION block
  6. Loop back to step 1 for next chunk
After all chunks:
  7. INVOKE craft:validate-chunk MODE=story-final (full test suite)
  8. Self-critique + spark verification
  9. complete-story.sh → check cycle completion
```

## SKILL CHAINS (what invokes what)

```
story-implement ──→ [checkpoint → implementer(Task) → validate-chunk(Skill)] ×N
                 ──→ validate-chunk MODE=story-final
                 ──→ complete-story.sh

validate-chunk  ──→ chunk-validator agent (haiku)
                ──→ ON test fail: craft:test-fix (breadcrumb continuation)
                ──→ ON other fail: craft:refine-chunk (breadcrumb continuation)
                ──→ ON pass: complete-chunk.sh + >>> NEXT ACTION

test-fix        ──→ triage: stale test | code wrong | ambiguous
                ──→ >>> HAND BACK TO validate-chunk

refine-chunk    ──→ surgical fix (no over-engineering)
                ──→ >>> HAND BACK TO validate-chunk

cycle-design       ──→ content-spark (inline via reference) → creative-spark (inline,optional)
                ──→ design-vibe (visual cohesion across UI stories)
                ──→ alignment check (codebase investigation, surfaces product questions)
                ──→ plan-chunks MODE=batch (parallel planning)

story-new       ──→ content-spark (inline via reference) → creative-spark (inline,optional)
                ──→ alignment check (codebase investigation, surfaces product questions)
                ──→ plan-chunks (single story)
```

## CRITICAL RULES (violations cause errors)

```
NEVER  implement chunks directly — ALWAYS invoke implementer agent via Task tool
NEVER  validate directly — ALWAYS invoke craft:validate-chunk via Skill tool
NEVER  edit .state or .global-state directly — use transition scripts
NEVER  run_in_background for test/typecheck/lint/build — must be synchronous
NEVER  override FAILED verdict — FAILED means FAILED, no dismissals
NEVER  present story content from memory — Read story file fresh every time
NEVER  batch concerns into summaries — surface each individually via AskUserQuestion
ALWAYS checkpoint before each chunk (create-checkpoint.sh)
ALWAYS use transition scripts for state changes (see list below)
ALWAYS write breadcrumb before nested skill invocation (see .continuation pattern)
ALWAYS clean up breadcrumb on ALL exit paths (success, failure, escalation)
```

## TRANSITION SCRIPTS (hooks/scripts/)

```
start-cycle.sh [cycle-name]           | Activate cycle, set ACTIVE_CYCLE
complete-cycle.sh                     | Archive cycle, clear ACTIVE_CYCLE
start-story.sh [story-file]           | Set CURRENT_STORY, CURRENT_CHUNK=1, status=active
complete-story.sh [story-file]        | Git commit (feat: title + chunk bullets), clear state, status=complete
complete-chunk.sh                     | Increment CURRENT_CHUNK
create-checkpoint.sh [story] [chunk]  | YAML state snapshot to .craft/checkpoints/ (no git commit)
update-global-state.sh KEY VALUE      | Update .global-state safely
```

## STATE FILES (quick reference)

```
.craft/.global-state         | ACTIVE_CYCLE, CURRENT_STORY, PLANNING_CYCLE, RUN_MODE
.craft/cycles/{c}/.state     | CURRENT_CHUNK, TOTAL_CHUNKS, CURRENT_STORY
.craft/cycles/{c}/cycle.yaml | title, goal, status (planning|ready|active|complete)
Story frontmatter: status    | planning → ready → active → complete
Story frontmatter: alignment | pending → complete (set by alignment check before plan-chunks)
.craft/.continuation         | Breadcrumb for nested skill chains (30-min TTL, one-shot)
.craft/settings.yaml         | default_mode, parallel planning prefs
.craft/design/locked.md      | Locked decisions (enforced by validation)
.craft/design/tokens.yaml    | Design tokens (enforced by style-analyzer)
```

## PACKAGE MANAGER DETECTION

```
1. Check .craft/project.md → package_manager field
2. Fallback: pnpm-lock.yaml → yarn.lock → bun.lockb → package-lock.json
3. Unknown: AskUserQuestion
Use detected PM for ALL install/run commands (never hardcode npm/npx)
```
