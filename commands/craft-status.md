---
name: craft:status
description: "Show current Craft progress — cycles, stories, backlog in a rich dashboard view."
---

# Craft Status

Display a comprehensive view of current Craft state.

## Dashboard Format

```
┌─────────────────────────────────────────────────────────────┐
│  CRAFT                                               $X.XX  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ● Cycle [N]: [Name]                              [status]  │
│  ├── ✓ [Story 1]                               complete     │
│  ├── ◐ [Story 2]                      chunk X/Y  ███░░      │
│  └── ○ [Story 3]                            ready           │
│                                                             │
│  ○ Cycle [N+1]: [Name]                       [status]       │
│  └── X stories planned                                      │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  Backlog: X stories                                         │
│  ├── [story-name] (priority)                                │
│  ├── [story-name]                                           │
│  └── +N more                                                │
└─────────────────────────────────────────────────────────────┘
```

## Status Indicators

| Symbol | Meaning |
|--------|---------|
| `○` | Ready/Pending |
| `◐` | In Progress |
| `✓` | Complete |
| `⚠` | Blocked |
| `✗` | Failed |

## Planning Section

If `.craft/planning/` exists, show a planning summary between the cycle dashboard and the backlog:

```
├─────────────────────────────────────────────────────────────┤
│  Planning                          updated 2 days ago       │
│  ► customer-modernization (3 concepts, 1 planned)           │
│  ├── profile-tab                              complete      │
│  ├── cdb-mapping                              planned       │
│  └── invoice-email                            open          │
│  ○ permissions-cleanup                        open          │
│  ○ user-preferences                           open          │
│  ? 4 open questions across 3 concepts                       │
├─────────────────────────────────────────────────────────────┤
```

### Planning data gathering

Use **Glob** with pattern `$PROJECT/.craft/planning/active.md` to check if planning exists. If not found, skip the planning section silently.

If found:
1. Use **Read** to read `$PROJECT/.craft/planning/active.md`. Extract `last_updated` from frontmatter. Calculate days since last update. If >3 days, show "updated N days ago" in the header.
2. Use **Read** to read `$PROJECT/.craft/planning/README.md`. Extract the Roadmap table rows for initiative/concept names and statuses.
3. For each initiative folder (detected via Glob `$PROJECT/.craft/planning/*/README.md`), read the initiative README to get sub-concept count and statuses.
4. Scan for open questions: Use **Bash** to count `- [ ]` items across all planning `.md` files:
   ```bash
   grep -r "^- \[ \]" "${CRAFT_PROJECT_ROOT:-.}/.craft/planning/" --include="*.md" 2>/dev/null | wc -l
   ```
5. **Broken link check:** For each concept file with a `stories:` frontmatter field containing paths, use **Glob** to verify each story path exists. Flag any that don't resolve as `[broken]` in the output.

### Planning display rules

- Show initiatives as indented groups with their sub-concepts
- Show standalone concepts at root level
- Status indicators: `open`, `planned`, `complete`, `archived`
- Show open questions count if >0
- Show broken story links if any found
- If `last_updated` is missing from active.md frontmatter, show "updated: unknown"

## Data Sources

Read from:
- `.craft/.global-state` — active cycle, global config
- `.craft/cycles/*/cycle.yaml` — cycle details
- `.craft/cycles/*/.state` — cycle state
- `.craft/cycles/*/stories/*.md` — story details
- `.craft/backlog/*.md` — backlog stories
- `.craft/planning/active.md` — planning live state (if exists)
- `.craft/planning/README.md` — planning roadmap index (if exists)
- `.craft/planning/*/README.md` — initiative details (if exists)
- `.craft/map/capability.json` — Living Map capability verdict (if exists)
- `.craft/map/index.json` — Living Map index: areas + per-file anchor keys (if exists)
- `.craft/mockups/*/record.md` — mockup records (if any exist)

## Map status

The Living Map is an unrequested optimization, so its status is **pulled here, never pushed** - no toast or notice fires when a grammar degrades; the only place a user learns the map's state is by asking for it.

Render ONE line, only if `.craft/map/` exists (a project that has never needed the map shows nothing - that is the normal first-run state, not an error). Read `.craft/map/capability.json`:
- `mode: full` — `Map: active · N langs` (N = grammars that loaded true)
- `mode: partial` — `Map: active · N langs · M degraded` (M = grammars that loaded false; name them, e.g. "C# - why?", the "why?" pointing at `commands/references/map.md`)
- `mode: floor` — `Map: basic mode (full parsing unavailable - see references/map.md)`
- `mode: disabled` — `Map: off (map.enabled: false)`

This is render-only: read the cached verdict and print the line in the dashboard's existing style. Do NOT probe, build, or re-derive anything from the status command.

## Gates posture

Render ONE line showing quality-gate coverage. Run the stack probe (sub-100ms, pure filesystem - the one exception to render-only, and it executes no toolchain commands):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/gate-signals.sh scan
```

Each output line is `manifest <glob> <count>` (undecided) or `manifest <glob> <count> <state> <date>` (recorded decision). Render:
- All signals wired or built-in-covered (package.json with runnable scripts) → `Gates: full coverage`
- Declined signals exist → append them labeled as chosen: `Gates: 1 ungated by choice: *.csproj (declined 2026-07-08)` - the user waived it; this is information, never a prompt
- Undecided signals exist → `Gates: N undecided: <globs>` - craft will ask at the next attended validation
- No manifests found or scan unavailable → omit the line entirely

This line never asks anything. Its job is that a declined toolchain stays visible as the user's choice - and quietly reminds that saying "wire up <glob>" reopens it any time.

## Mockups

Render a Mockups section ONLY when at least one non-abandoned record exists - empty-state silence, never an empty header. Source: glob `.craft/mockups/*/record.md`, read frontmatter only, exclude `status: abandoned`. One line per mockup:

```
Mockups:
  [slug] · [status] · [age, e.g. 3d] · [graduated_to value, or "awaiting destination" when converged with no graduation]
```

No new state files - the records ARE the state. Conversational recall ("what mockups do I have open?") reads the same records and answers in the same shape; there is no subcommand syntax.

## Implementation

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`.

**Cold guard (uninitialized project):** if `$PROJECT/.craft/.global-state` and `$PROJECT/.craft/project.md` are both absent, this project is not initialized - do NOT run the dashboard reads below (they assume state that does not exist). Answer instead:

> **Craft is installed here, but this project isn't initialized - so there's no cycle or story state to show yet.**
>
> Works right now, no setup: `/craft:mockup` (visual options funnel), `/craft:notebook` (capture thoughts), `/craft:guide` / `/craft:ask` / `/craft:riff` (consult), `/craft:research` and `/craft:become` (artifacts land at the repo root).
>
> `/craft:init` unlocks the rest - stories, cycles, tweaks, adhoc fixes - and makes anything already captured recallable and buildable.

If a bare `.craft/` exists (cold captures or mockups), count what's in `.craft/notebook/` and `.craft/mockups/` and name it in the answer ("You already have [N] captured notes and [M] mockups - init makes them part of the workshop"). Recommend `/craft:init` when they're ready to build. Then stop - no dashboard section below applies.

Otherwise (initialized project):

Use **Read** to read `$PROJECT/.craft/.global-state`. Parse key=value pairs to extract `ACTIVE_CYCLE`, `CURRENT_STORY`, etc.

Use **Glob** with pattern `$PROJECT/.craft/cycles/*/cycle.yaml` to find all cycles.
For each cycle, use **Read** to read `cycle.yaml` for status and **Read** to read `.state` for progress.
Use **Glob** with pattern `$PROJECT/.craft/cycles/[cycle-name]/stories/*.md` to list stories per cycle.

Use **Glob** with pattern `$PROJECT/.craft/backlog/*.md` → count results → `backlog_count`.

## Options

- `/craft status` — Full dashboard (default)
- `/craft status --cycle` — Current cycle only
- `/craft status --backlog` — Backlog list only
- `/craft status --story` — Current story details

## Quick Aliases

For convenience, these shortcuts should also work:
- `/s` — Current story details
- `/c` — Current cycle overview
- `/b` — Backlog list

## Output

The dashboard IS the answer. Render it, then close with 2-3 SHORT next-move suggestions in plain prose - and stop. No question widget: nothing here blocks on a choice, and a dialog would cover the very table the user just asked to see.

Derive the suggestions from the state you just rendered - name the specific story or cycle and the command that advances it. Never offer canned moves the data contradicts (no "continue current story" when no story is active). Examples of the shape:

> Story 14 (agent-finding-handoff) is still unplanned - `/craft:plan-chunks` gets it ready.
> The active story is mid-chunk (3/5) - `/craft:story-continue` picks it back up.
> All stories in this cycle are complete - `/craft:cycle-complete` archives it.

Then end the turn. The user replies conversationally and normal routing takes it from there.
