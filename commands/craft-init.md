---
name: craft:init
description: "One-time setup to initialize the Craft harness for a project."
---

# Project Init

Set up the Craft harness for your project. Run once at the start.

## Flow

### Phase 0: Init

Before scanning or asking questions, check what the user needs.

Use **AskUserQuestion**:
```
question: "What kind of setup do you need?"
header: "Setup"
options:
  - label: "Full setup (Recommended)"
    description: "Scan project, extract patterns, configure tokens/conventions"
  - label: "Quick setup"
    description: "Just the .craft/ directory structure — for projects with strong existing docs (CLAUDE.md, etc.)"
```

**Use these exact option labels and the (Recommended) marker as written.** Do not reframe descriptions, swap the order, or move (Recommended) to a different option based on directory state. Quick setup is for users with a strong existing CLAUDE.md who explicitly want to skip scanning. Full setup is the default for everyone else, **including empty directories** — Phase 3 (the inspiration design session) is the project-DNA flow that runs regardless of whether code is present yet.

**If "Quick setup":**

Ask one follow-up for project type:

Use **AskUserQuestion**:
```
question: "What type of project is this?"
header: "Type"
options:
  - label: "UI / Web app"
    description: "Includes design tokens, inspiration, components templates"
  - label: "CLI / Backend / Plugin"
    description: "Includes naming conventions, schemas, code patterns"
```

Then:
1. **For UI projects:** Run `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/setup-craft.sh ui`
   - Quick setup skips the scanner, so there's no visual file count. Tokens are deferred - the setup script never creates tokens.yaml.
   - The user chose quick setup because they have strong existing docs. Tokens can be added later when you have visual code to reference.
2. **For CLI projects:** Run `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/setup-craft.sh cli`
   - Conventions are deferred too - quick setup never scans, so there's nothing real to write yet.
3. Go to Phase 6 (First Cycle Kickoff) and present its AskUserQuestion. Do NOT improvise a kickoff prompt here - Phase 6 owns the kickoff on every path.

The `.craft/` structure is created with sensible template defaults. The project's existing CLAUDE.md serves as the source of truth for stack, patterns, and conventions - no need to duplicate into project.md. Run `/craft:update-docs` later when there's code to scan.

Show this recap before the Phase 6 question:

> "Directory structure created.
>
> Your CLAUDE.md is your project DNA - Craft will use it alongside `.craft/` state.
> [If UI:] Design tokens can be added later when you're ready - no guessing upfront.
> [If CLI:] Project conventions can be added when there's code to learn from - run `/craft:update-docs` once you have code to scan, or add conventions to `.craft/design/locked.md` directly."

Quick setup never scans, so `.craft/design/.confidence-signals.yaml` carries no `total_files` key on this path - per Phase 6's marker rule, NO option carries (Recommended). `PROJECT_TYPE` comes from the type question above (UI / Web app -> `ui`; CLI / Backend / Plugin -> `cli`) and gates the mockup option as usual.

**If "Full setup":** Create the task rail, then continue to Phase 0.5 below.

**The task rail (Full setup only - Quick setup is seconds long and never builds one):** six TaskCreate tasks, blockedBy-chained in order: **Intent -> Scan -> Shape -> Design -> Scaffold -> Kickoff**. Task SUBJECTS are exactly the six beat names - no "Init:" prefix, no descriptive suffix; the subject is a label, detail goes in the task description. Beat-to-phase mapping: Intent = Phase 0.5, Scan = Phase 0a/0b + Phase 1, Shape = Phase 1b + 2 + 2b, Design = Phase 3 (the whole inspiration session - ONE task across all sources and riffs, like mockup's Polish), Scaffold = Phase 4 + 5 + 5b, Kickoff = Phase 6. Substeps never become tasks - no AskUserQuestion, agent spawn, or script run gets its own task. Beats the flow bypasses complete-with-note, never delete. The rail ENDS at Kickoff - whatever the first move routes into (mockup, cycle creation) creates its own tasks.

**If invoked with `RESUME_INSPIRATION=true`:**

Read `.craft/design/.inspiration-session`. Check the `phase` field:
- `"collecting"` -> Skip to Phase 3a. Present: "Resuming your inspiration session. You have [N] source(s) so far."
- `"assembling"` -> Skip to Phase 3b. Present: "Resuming your inspiration session. Let me re-assemble your [N] sources."
- `"riffing"` -> Skip to Phase 3b first (to re-present the assembly), then proceed to Phase 3c. Present: "Resuming your inspiration session with [N] riff(s) applied."

Skip Phase 0, 0a, 0b, 1, 2, and 2b entirely - the session file already has all context needed.

Recreate the task rail (tasks are session-ephemeral - the previous session's rail is gone): create the six tasks exactly as the Full-setup rail block above specifies, immediately complete Intent, Scan, and Shape with the note "pre-resume - settled in the original init session", and leave Design open. The `.inspiration-session` file is the durable truth the rail is rebuilt from - the same role record.md plays for mockup.

---

### Phase 0.5: Project Intent (Optional)

Before scanning the codebase, capture the user's project intent in their own words. This becomes substrate for the muse session in Phase 5b and surfaces the user's voice in `project.md`. Skipping is fine — projects that just want structure can move on; the muse session in Phase 5b will also be skipped.

This phase only fires on the Full setup path (Quick setup routes directly to setup script + Phase 6, bypassing everything in between).

Use **AskUserQuestion**:
```
question: "Want to capture your project intent now? Two short questions about what you're building."
header: "Intent"
options:
  - label: "Yes, capture intent"
    description: "Two short answers the muse distills into your project's Emotional Core - every cycle you plan later reads it"
  - label: "Skip - just scaffold"
    description: "No intent capture - skip the muse session later too"
```

**If "Skip":** Set `INTENT_CAPTURED=false`. Complete the Intent task with a note (skipped - no intent capture). Continue to Phase 0a. Phase 5b will skip muse session.

**If "Yes":** Set `INTENT_CAPTURED=true` and ask the two intent prompts:

Ask the user directly:

> "What's the one thing this app helps people do? (One sentence is enough.)"

Capture their next response as `PROJECT_INTENT_Q1`. If the response is whitespace-only or empty, treat as Skip — set `INTENT_CAPTURED=false`, complete Intent with the same skipped note, and continue to Phase 0a.

Then ask:

> "What's the moment in the app you're most excited to build? (The feature, screen, or interaction you can't stop thinking about.)"

Capture their next response as `PROJECT_INTENT_Q2`. Same whitespace-handling rule.

Both answers will be:
1. Written verbatim into `project.md` as a `## Project Intent` section in Phase 5
2. Used as substrate for the muse session in Phase 5b (which generates the Emotional Core)

Mark Intent complete. Continue to Phase 0a.

---

### Phase 0a: Project Scan

Before asking any questions, understand the project by scanning it.

**Empty-directory pre-check (early skip):**

Before invoking the scanner, check if the directory has any source-relevant files. If empty, the scanner has nothing to extract — skip the agent invocation, write the empty confidence signals directly, and route to Phase 0b for project-type selection.

Use **Glob** at the project root (`${CRAFT_PROJECT_ROOT:-.}`) with these patterns, excluding `.git/**`, `node_modules/**`, and `.craft/**`:
- `**/*.tsx`, `**/*.jsx`, `**/*.vue`, `**/*.svelte`
- `**/*.css`, `**/*.scss`, `**/*.sass`, `**/*.less`
- `**/*.ts`, `**/*.js`, `**/*.mjs`, `**/*.cjs`
- `**/*.json`, `**/*.yaml`, `**/*.yml`
- `**/*.md`, `**/*.sh`, `**/*.py`

Sum the matches across all patterns → `total_files`.

**If `total_files == 0`** (truly empty repo):

> "This directory is empty - no code to scan yet. Setting up a fresh scaffold."

Create `.craft/design/` if it doesn't exist:

```bash
mkdir -p "${CRAFT_PROJECT_ROOT:-.}/.craft/design"
```

Write `.craft/design/.confidence-signals.yaml` directly using the Write tool with this content (replace `[ISO timestamp]` with the current UTC timestamp in the form `YYYY-MM-DDTHH:MM:SSZ`):

```yaml
total_files: 0
visual_file_count: 0
scanned_at: "[ISO timestamp]"
patterns: []
```

The `total_files` key is read back by Phase 6 to place its (Recommended) marker - it must land in this file, not just in conversation memory.

Set the in-memory state for the rest of init:
- `PROJECT_TYPE` is undetermined (will be asked in Phase 0b)
- `TECH_STACK` is empty
- `PATTERNS` is empty
- `visual_file_count = 0`

Skip Phase 1 entirely (nothing to confirm) and skip directly to Phase 0b for project-type selection. Phase 0b normally serves as fallback when the agent fails — here it serves as the primary path because we know the directory is empty without needing to invoke the agent.

**If `total_files > 0`:** Continue to the scanner agent invocation below (existing flow).

---

**Launch the project-scanner agent:**

> "Let me analyze your project..."


**INVOKE the project-scanner agent using the Task tool:**

```
Task tool:
  subagent_type: "craft:project-scanner"
  description: "Analyze project for Craft init"
  prompt: "Scan this project comprehensively.

  **Project root:** [current working directory]

  Follow your full analysis checklist (P1-P9). Be thorough but efficient.
  Return findings in your structured output format."
```

The agent returns:
- Project type (UI / CLI / API / Hybrid)
- Tech stack (languages, framework, package manager)
- Architecture and patterns discovered
- Conventions already in use
- Quality infrastructure status
- Existing documentation
- Locked patterns discovered
- Confidence signals (YAML) for visual patterns

**Extract confidence signals:**

If the agent's output contains a `## Confidence Signals (YAML)` section:
1. Extract the YAML content from the fenced code block in that section
2. Write it to `.craft/design/.confidence-signals.yaml` at the project root
3. This file is consumed by craft-init for project-state matrix branching.
4. Add `total_files: [the Phase 0a Glob sum]` as a key in that file.

If the section is missing (agent failed, non-UI project), skip steps 1-3 but still write `.craft/design/.confidence-signals.yaml` containing the `total_files` key (create the file and `.craft/design/` if needed). The other signals' absence is a valid state - consumers handle it gracefully - but `total_files` must be on disk on every Full-setup path: Phase 6 reads it from this file to place its (Recommended) marker, and conversation memory across the intervening phases is not a reliable carrier.

**Fallback:** If the agent fails or returns empty, fall back to manual detection (Phase 0b).

---

### Phase 0b: Manual Detection

Reached either when the empty-directory pre-check (Phase 0a) routed here directly, or when the project-scanner agent fails. In both cases the orchestrator needs basic facts about the project type before continuing. When reached from the empty pre-check, the file counts below will all be zero — skip the inference logic and ask the user directly for project type, language, and framework.

Quick detection via file presence:

```
# Project type indicators
Glob "src/components" or "components" or "app" or "pages" → count matches → UI_INDICATORS
Glob "bin" or "cli" or "commands" → count matches → CLI_INDICATORS
Glob "routes" or "controllers" or "handlers" or "api" → count matches → API_INDICATORS

# Package manager
Glob "pnpm-lock.yaml" → if found: PM = "pnpm"
else Glob "yarn.lock" → if found: PM = "yarn"
else Glob "bun.lockb" → if found: PM = "bun"
else Glob "package-lock.json" → if found: PM = "npm"
else PM = "none"

# Language (count files, excluding node_modules/venv)
Glob "**/*.ts" + "**/*.tsx" (exclude node_modules) → count → TS_COUNT
Glob "**/*.js" + "**/*.jsx" (exclude node_modules) → count → JS_COUNT
Glob "**/*.py" (exclude venv) → count → PY_COUNT
Glob "**/*.md" → count → MD_COUNT
Glob "**/*.sh" → count → SH_COUNT
```

Use these counts to infer project type and stack.

**If reached from empty-directory pre-check (Phase 0a):** Skip Phase 1 (nothing to confirm — directory is empty). Ask the user the project-type question below directly, complete Scan with a note (empty directory - nothing to scan), then continue to Phase 1b.

**If reached from agent failure:** Continue to Phase 1 with partial findings.

**Project-type question (used when Phase 1's findings are unavailable):**

Use **AskUserQuestion**:
```
question: "What kind of project is this?"
header: "Project type"
options:
  - label: "UI / Web app"
    description: "Frontend application with screens and user interaction"
  - label: "CLI tool"
    description: "Command-line tool installed and run from a terminal"
  - label: "API / Backend service"
    description: "Server, API, or backend service - no UI"
  - label: "Hybrid (UI + backend)"
    description: "Full-stack app with both frontend and backend in one project"
```

**Do NOT** add a `(Recommended)` marker or inference suffix based on Phase 0.5's intent answers. Project type is a structural decision; word-matching from free-text intent is unreliable signal and biases a foundational choice. Let the user pick fresh.

Store the chosen option as `PROJECT_TYPE` in slug form: `ui`, `cli`, `api`, or `hybrid`.

If the user types a free-text response (option 5: "Type something") naming a different shape (e.g., "library", "static site", "documentation"), capture it as a free-text slug and proceed. Downstream phases that branch on `PROJECT_TYPE` will fall through to their default paths.

---

### Phase 1: Confirm Findings

Present the agent's findings and let the user confirm or correct.

> "I've analyzed your project. Here's what I found:
>
> **Project type:** [detected type]
> **Primary language:** [language] ([percentage]%)
> **Framework:** [framework or 'None']
> **Package manager:** [pm]
>
> **Key patterns discovered:**
> - [pattern 1]
> - [pattern 2]
> - [pattern 3]
>
> Does this look right?"

Use **AskUserQuestion**:
```
question: "Does this look right?"
header: "Confirm"
options:
  - label: "Yes, that's accurate"
    description: "Proceed with these settings"
  - label: "Mostly right, minor corrections"
    description: "I'll note what's different"
  - label: "Needs significant changes"
    description: "Let me describe the project"
```

**If "Mostly right":** Ask what needs correction, update findings, proceed.

**If "Needs significant changes":** Fall back to asking key questions (project type, language, framework). Don't ask about things that are verifiable from files.

Mark Scan complete once findings are settled.

**Store confirmed values:**
- `PROJECT_TYPE` = `ui` | `cli` | `api` | `hybrid` — preserve through the phase chain so Phase 1b can route by type. When calling `setup-craft.sh` in Phase 4, pass `cli` for `api` and `hybrid` types (they share the CLI scaffolding templates).
- `TECH_STACK` = agent findings or user corrections
- `PATTERNS` = discovered patterns for locked.md

---

### Phase 1b: Deploy Target

Where the user plans to deploy informs downstream stack recommendations. Ask now so cycle planning can reference this hint when offering framework / hosting / tooling choices later.

This is a HINT, not a constraint. The answer is stored in `project.md` as `deploy_target` and read by orchestration prompts to compute (Recommended) markers. The user retains override authority at every downstream prompt.

Use **AskUserQuestion** with options scoped to `PROJECT_TYPE`:

**If `PROJECT_TYPE` is `ui`:**
```
question: "Where do you intend to deploy this? (Type 'not sure' if you haven't decided yet.)"
header: "Deploy"
options:
  - label: "Vercel (Recommended)"
    description: "Next.js, serverless functions, edge runtime, image optimization"
  - label: "Netlify"
    description: "Static sites, Netlify Functions, JAMstack-friendly"
  - label: "Cloudflare Pages"
    description: "Edge-first, Workers, KV/D1 for state"
  - label: "Self-hosted"
    description: "Docker/VPS/your own infrastructure"
```

**If `PROJECT_TYPE` is `cli`:**
```
question: "Where do you intend to publish this CLI tool? (Type 'not sure' if you haven't decided yet.)"
header: "Distribute"
options:
  - label: "npm (Recommended for Node.js)"
    description: "Standard JavaScript/TypeScript package distribution"
  - label: "PyPI"
    description: "Python Package Index"
  - label: "GitHub Releases"
    description: "Pre-built binaries via GitHub"
  - label: "Homebrew"
    description: "macOS/Linux package manager"
```

**If `PROJECT_TYPE` is `api`:**
```
question: "Where do you intend to deploy this service? (Type 'not sure' if you haven't decided yet.)"
header: "Deploy"
options:
  - label: "Fly.io (Recommended)"
    description: "Edge VMs, simple deploy, generous free tier"
  - label: "Railway"
    description: "Git-push deploys, integrated databases"
  - label: "Render"
    description: "Managed services, good for full-stack"
  - label: "Self-hosted"
    description: "Docker/VPS/k8s/your own infrastructure"
```

**For `hybrid`** (UI + backend in one project): Ask the UI question first, then the API question. Capture both answers — typically a hybrid project deploys frontend and backend to different targets (e.g., Vercel + Fly.io). Store as `DEPLOY_TARGET_UI` and `DEPLOY_TARGET_API` separately, then combine into `deploy_target: "vercel + fly-io"` style string in project.md.

**If the user picks an explicit option:** Store the slug form of the label (e.g., `vercel`, `cloudflare-pages`, `self-hosted`, `fly-io`).

**If the user types a free-text response (option 5: "Type something") or routes through option 6 ("Chat about this"):**

Parse the response against three buckets:

1. **Indecision signal** — response matches `not sure`, `tbd`, `skip`, `decide later`, `haven't decided`, `idk`, `unknown`, or any close paraphrase. Set `DEPLOY_TARGET=unknown`. Downstream prompts will skip Recommended-marker influence.
2. **Recognized free-text target** — response names a deploy target (e.g., `fly.io`, `cloud run`, `aws lambda`, `digital ocean`, `coolify`, `cargo`, `apt`, `winget`). Slugify (lowercase, spaces → hyphens) and store as `DEPLOY_TARGET`.
3. **Ambiguous** — response doesn't clearly fit either bucket. Ask one clarifying AskUserQuestion: "Want me to record `[their input]` as your deploy target, or leave it as Not sure yet?" Capture their final answer.

This applies to all three blocks above (UI / CLI / API).

Store the answer:
- `DEPLOY_TARGET` = chosen option in slug form (e.g., `vercel`, `netlify`, `cloudflare-pages`, `self-hosted`, `npm`, `pypi`, `github-releases`, `homebrew`, `fly-io`, `railway`, `render`, `cloud-run-aws-gcp`, `unknown`, or a free-text slug from the parser above)

This value is written to `project.md` in Phase 5 and read by orchestration prompts (cycle-design, story-new, plan-chunks-agent) when offering stack-related options.

---

### Phase 2: Project-State Matrix

Route the init flow based on what the scanner found. For UI projects, this replaces the old "What are we working with?" question - the visual file count tells us what we're working with.

**Read the visual file count from the scanner output.** The scanner reports `visual_file_count` in its Quick Summary and Visual File Analysis section. Parse this number.

**If PROJECT_TYPE is `cli` or `api`:** -> **CLI/Backend branch**

> "This is a CLI/backend project - I'll set up Project Conventions (naming, structure, code style) and enforce them immediately."

The scanner's convention findings feed Phase 5, which creates the conventions tokens.yaml.
Continue to Phase 2b.

**If PROJECT_TYPE is `ui` or `hybrid`:** Route by visual file count:

**Branch: UI from scratch (0 visual files)**

> "Fresh start! I won't guess at design tokens - I'll learn your visual language from what you build. No design tokens yet. When you're ready to establish a design system, re-run `/craft:init` with inspiration or add tokens.yaml manually."

Nothing is locked on this branch - Phase 5 will write no tokens.yaml.
Continue to Phase 2b.

**Branch: UI existing early (< 5 visual files)**

> "Your project has [N] visual files - not quite enough signal to extract confident design tokens yet. I'll defer tokens and learn from what you build next. When you have more visual code, run `/craft:update-docs` and I'll extract patterns."

Nothing is locked on this branch - Phase 5 will write no tokens.yaml.
Continue to Phase 2b.

**Branch: UI existing mid (5-20 visual files)**

> "Your project has [N] visual files - enough to start seeing patterns. Let me extract what I can find..."

**Pre-existing tokens.yaml check:** if `.craft/design/tokens.yaml` already exists (e.g. born from a converged `/craft:mockup`), Phase 5 will merge extracted values into it - see "Reference: Keyed tokens.yaml merge". Run the script's report mode over the extracted values NOW and paste its CONFLICT/NEW/SAME output verbatim into the presentation below - the conflict list comes from code, never from your own comparison.

Extract visual patterns from the scanner's findings (colors, fonts, spacing mentioned in the Key Patterns table). Present them to the user:

> "Here's what I found in your code:
>
> **Colors:** [list extracted colors with file references]
> **Typography:** [list font families found]
> **Spacing:** [list spacing patterns if consistent]
>
> These aren't confident enough to lock automatically. Want me to save them as starting tokens?"

Use **AskUserQuestion**:
```
question: "Save these as starting design tokens?"
header: "Tokens"
options:
  - label: "Yes, save and enforce"
    description: "Write to tokens.yaml - new code should follow these"
  - label: "Skip for now"
    description: "I'll skip tokens for now - add them later when patterns are clearer"
```

If "Yes": the locked values feed Phase 5's tokens.yaml step - the single write site.
If "Skip": nothing is locked - Phase 5 writes no tokens.

**If a tokens.yaml already exists and conflicts exist**, extend this same widget in place - never a new one. List the conflict set in the question's presentation text:

> "Your tokens.yaml already has values for [conflicting keys]. The scan found different values: [key: existing value vs scanned value]. Existing values stay unless you review each conflict."

and add one option to the two above:

```
  - label: "Save + review conflicts"
    description: "Add non-conflicting values, then walk each conflicting key individually"
```

If "Save + review conflicts": walk each conflicting key with an individual AskUserQuestion (keep existing value / take scanned value), record each "take scanned" choice as a `--resolve section.key=incoming` flag for Phase 5's merge invocation.

With an existing tokens.yaml, "Yes, save and enforce" adds only non-conflicting scan keys - every conflicting key keeps its existing value. A bulk choice never overwrites an existing (mockup-owned) key; only the per-key conflict walk can. Phase 5's keyed merge performs the actual write - this branch's job is extraction and conflict resolution only.

Continue to Phase 2b.

**Branch: UI existing mature (20+ visual files)**

> "Your project has [N] visual files - rich enough for confident pattern extraction."

**Pre-existing tokens.yaml check:** if `.craft/design/tokens.yaml` already exists (e.g. born from a converged `/craft:mockup`), Phase 5 will merge extracted values into it - see "Reference: Keyed tokens.yaml merge". Run the script's report mode over the extracted values NOW and paste its CONFLICT/NEW/SAME output verbatim into the presentation below - the conflict list comes from code, never from your own comparison. Frame it e.g.:

> "Your tokens.yaml already has values for [conflicting keys]. The scan found different values: [key: existing value vs scanned value]. Bulk options below won't touch those - pick 'Review each' to resolve them."

Extract visual patterns from scanner findings. Split into high-confidence (consistent, widely used) and low-confidence (inconsistent, few usages):

> "Here's what I found:
>
> **High confidence** (consistent across files):
> [list with use counts and file references]
>
> **Low confidence** (inconsistent or sparse):
> [list with use counts and notes]
>
> I recommend locking the high-confidence patterns immediately."

Use **AskUserQuestion**:
```
question: "How should I handle these patterns?"
header: "Token Recognition"
options:
  - label: "Lock high-confidence, defer low (Recommended)"
    description: "Enforce consistent patterns now, revisit uncertain ones later"
  - label: "Lock all"
    description: "Save everything as tokens - I'll adjust later if needed"
  - label: "Review each"
    description: "Walk me through each pattern for individual approve/skip"
  - label: "Skip all"
    description: "Don't save any tokens now"
```

If "Lock high-confidence": lock the high-confidence patterns, skip low-confidence.
If "Lock all": lock all patterns.
If "Review each": Walk through each pattern with individual AskUserQuestion; whatever is approved is locked.
If "Skip all": nothing is locked - Phase 5 writes no tokens.

The locked set feeds Phase 5's `#### tokens.yaml` step - the single write site for extracted tokens. This branch's job is extraction and conflict resolution, not writing.

With an existing tokens.yaml: "Lock high-confidence" and "Lock all" apply to **non-conflicting scan keys only** - bulk choices generate NO `--resolve` flags, so the merge script keeps every existing (mockup-owned) value. Conflicting keys change only via "Review each": record each "take scanned" choice as a `--resolve section.key=incoming` flag for Phase 5's merge invocation - the only path that can change an existing value.

Continue to Phase 2b.

---

### Phase 2b: Energy + Path Selection

Phase 2b runs unconditionally after Phase 2's matrix routing, regardless of project type or visual file count. It captures the project's energy (required by Phase 5's `project.md` template) and then routes UI projects through an inspiration question.

**Step 1 — Energy question (all project types):**

> "What's the energy?"

Use **AskUserQuestion**:
```
question: "What's the energy?"
header: "Energy"
options:
  - label: "Steady and solid (Recommended)"
    description: "Production mode - thorough validation, careful work. Best default for new projects and first-time users."
  - label: "Move fast, break things"
    description: "Startup mode - momentum over perfection"
  - label: "Learning/exploring"
    description: "Experimental mode - educational checkpoints"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion.

Store the captured energy as `ENERGY_LEVEL`.

**Step 2 — Path selection:**

**If PROJECT_TYPE is `cli` or `api`:** Mark Shape complete; complete Design with a note (no inspiration session for CLI/backend). Skip to Phase 4 (setup-craft.sh).

**If PROJECT_TYPE is `ui` or `hybrid`:** Ask the inspiration question. The gate is conditional on whether Phase 0.5 captured intent - the suggest option only exists when there is substrate to seed it.

**If INTENT_CAPTURED=true:**

Use **AskUserQuestion**:
```
question: "Do you have design inspiration to draw from?"
header: "Inspiration"
options:
  - label: "Suggest some for me (Recommended)"
    description: "I'll find live reference sites from what you told me about the project - starting points to react against"
  - label: "Yes, I have reference sites"
    description: "Pull colors, typography, spacing from sites I admire"
  - label: "No, continue with what we have"
    description: "Use the token decision from Phase 2"
```

**If INTENT_CAPTURED=false:** The suggest option does not appear - there are no intent answers to seed it. Render today's two-option gate:

Use **AskUserQuestion**:
```
question: "Do you have design inspiration to draw from?"
header: "Inspiration"
options:
  - label: "Yes, I have reference sites"
    description: "Pull colors, typography, spacing from sites I admire"
  - label: "No, continue with what we have"
    description: "Use the token decision from Phase 2"
```

**Routing (both branches):**

**If "Suggest some for me":** Run the suggestion beat below.

**If "Yes":**

> "Let's build your design from inspiration. You can pull colors from one site, typography from another, spacing from a third - and iterate until it feels right."

Proceed to Phase 3 (Inspiration Design Session).

**If "No":** Mark Shape complete; complete Design with a note (skipped - riding on Phase 2's token decision). Skip Phase 3. Continue to Phase 4 (setup-craft.sh).

**Step 2b - The suggestion beat** (reached only from "Suggest some for me"):

Spawn EXACTLY ONE subagent via the Task tool. Do not run WebSearch in the main loop, and do not spawn a second agent except for the single re-roll defined below.

```
Task tool:
  subagent_type: "general-purpose"
  model: "haiku"
  description: "Find inspiration sites"
  prompt: |
    Find up to 3 live reference websites to inspire this project's visual design.

    PROJECT INTENT (the user's own words - your only seed):
    Q1 - what the app helps people do: [PROJECT_INTENT_Q1 verbatim]
    Q2 - the moment they're most excited to build: [PROJECT_INTENT_Q2 verbatim]

    Rules:
    - Use WebSearch to find candidates. NEVER suggest a URL from model memory.
    - Verify EVERY candidate with WebFetch before including it: the URL must load real
      content right now. Silently drop anything that errors, 404s, or is a parked domain.
    - The 3 must be genuinely different stances, not variations - and at least one must
      sit outside the obvious category for this kind of project.
    - Return your result INLINE as your final text output. Do NOT write any file.
    - Format: one line per candidate - URL | stance name | one-line why it fits.
    - If fewer than 3 verify, return only what verified (minimum 1). If nothing
      verifies, return exactly: NO_VERIFIED_CANDIDATES
```

**Present the candidates as prose** - these are starting points to react against, not picks. Never auto-select one. Name each stance and its one-line why, then invite a reaction conversationally ("Which one pulls? What's wrong with the others?") - **no AskUserQuestion widget at this beat.** The user can always bring their own URL here instead; that is a first-class answer.

**On a pick (or a user-supplied URL):** proceed to Phase 3 with that URL as the first source - Phase 3a skips its opening URL ask and goes straight to the aspects question. Unpicked candidates stay visible in the conversation; the user can feed them into the existing "Add another source" loop later, which needs no changes.

**On reject-all:** fire exactly ONE re-roll - a second spawn of the same Task block, with the user's rejections appended to the prompt as constraints ("The user rejected: [candidates + verbatim reasons]. Avoid these directions."). If the user rejects the re-roll too, stop suggesting: fall back to the "Yes" path's prose and Phase 3's normal URL ask.

**Degrade rules:** If WebSearch is unavailable, the spawn fails, or the agent returns NO_VERIFIED_CANDIDATES, say one line ("I couldn't verify live suggestions - let's use yours instead.") and fall back to the "Yes" path's flow. **Never show an unverified URL** - a dead link hard-fails Phase 3a's navigation at the most fragile moment of onboarding, worse than no suggestion at all.

---

### Reference: Keyed tokens.yaml merge

When a `.craft/design/tokens.yaml` already exists before this init run (most often born from a converged `/craft:mockup`), the file is a **merge target** - never skip extraction because of it, never regenerate over it. The Write tool is DENIED on an existing tokens.yaml (write-permission hook enforces this); `merge-tokens.py` is the only writer. This block owns the decisions; the script owns every write mechanic - see `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/merge-tokens.py` (docstring) for exact behavior. Do not restate or improvise write mechanics at any call site.

**Signal:** none needed - Phase 5 checks live state. If `.craft/design/tokens.yaml` exists when Phase 5 runs, it is genuinely pre-existing (nothing in the init flow before Phase 5 creates it except Phase 3's Lock step, which handles its own write), and locked extracted values merge into it.

**The decisions:**

- **The per-key diff comes from code, not interpretation.** Before any token AskUserQuestion, run report mode and paste its output verbatim into the presentation:
  ```bash
  echo "$EXTRACTED_VALUES" | python3 ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/merge-tokens.py report .craft/design/tokens.yaml
  # stdin: one line per value - section.key=value|provenance comment
  # stdout: CONFLICT / NEW / SAME per key
  ```
- **Precedence:** extraction path (Phase 5) = existing wins - a mockup value is the user's approved browser-reaction choice, a scanned value is inferred from code. Inspiration Lock (Phase 3) = incoming wins - the user's explicit fresh choice supersedes the earlier mockup. Precedence direction is the ONLY thing that varies by call site.
- **Conflicts (same key, different value) resolve only through the calling path's sanctioned resolution.** Extraction path: the user's per-key AUQ choices, passed to the script as `--resolve section.key=incoming` flags. Bulk options ("Lock all", "Lock high-confidence") generate NO `--resolve` flags - the script keeps existing values for unresolved conflicts, so a bulk choice structurally cannot overwrite an existing key. Inspiration path: precedence itself is the resolution, no prompt. The script hard-errors on any `--resolve` naming a key outside its derived conflict set.
- **The write:**
  ```bash
  echo "$LOCKED_VALUES" | python3 ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/merge-tokens.py merge .craft/design/tokens.yaml \
    --template ${CLAUDE_PLUGIN_ROOT}/templates/craft/design/tokens.yaml \
    [--precedence incoming] [--resolve section.key=incoming ...]
  ```
  The script snapshots first, merges by key (union: scan-only keys added, existing keys kept, untouched lines byte-preserved with their provenance comments), backfills absent template sections with literals (never a `{{...}}` placeholder), self-verifies, and restores + exits non-zero on any violation. **A non-zero exit means the merge did NOT happen** - report the script's error to the user; never fall back to the Write tool.

Echo the script's summary line (kept/added/replaced/backfilled) to the user after a successful merge.

---

### Phase 3: Inspiration Design Session

**Entry conditions:**
- User selected "Yes, I have reference sites" in Phase 2's inspiration AskUserQuestion, OR
- User picked a suggested candidate (or brought their own URL) in the Phase 2b suggestion beat - that URL enters as the first source and Phase 3a skips its opening URL ask, OR
- Craft was invoked with `RESUME_INSPIRATION=true` (resuming interrupted session)

**If RESUME_INSPIRATION=true:** Read `.craft/design/.inspiration-session`, check `phase` field, and jump to the matching sub-phase (3a if collecting, 3b if assembling, 3c if riffing). Present a brief summary of what's already captured before continuing.

**If starting fresh:** Create the session file and begin at Phase 3a.

**Rail:** on any entry to Phase 3, mark Shape complete if it is still open - the suggestion beat's pick, fallback, and degrade paths all land here, so this one site covers them all. Design is now the open beat; it stays ONE task across every source and riff below.

#### Phase 3a: Source Collection

Initialize the session file (if starting fresh):

```bash
cat > "${CRAFT_PROJECT_ROOT:-.}/.craft/design/.inspiration-session" << 'YAML'
phase: "collecting"
started: "[ISO UTC timestamp]"
sources: []
assembly: null
riffs: []
YAML
```

**Source collection loop:**

**If arriving from the Phase 2b suggestion beat with a URL already in hand (picked candidate or user-supplied):** use that URL as the first source - skip the prompt below and go straight to the aspects question.

**Otherwise:**

> "Let's build your design from inspiration. Give me a URL to start with."

[User provides URL]

Ask which aspects to capture from this source:

Use **AskUserQuestion**:
```
question: "What should I capture from [URL]? (Or type which aspects to combine, e.g., 'colors and typography'.)"
header: "Aspects"
options:
  - label: "Whole vibe"
    description: "Colors, typography, spacing, shadows - everything visual"
  - label: "Colors only"
    description: "Color palette and usage"
  - label: "Typography only"
    description: "Font families, sizes, weights"
  - label: "Spacing & layout"
    description: "Spacing scale, component gaps, section padding"
```

**If the user types a free-text response (option 5: "Type something") or routes through option 6 ("Chat about this"):**

Parse the response directly against the aspect category enum (`colors`, `typography`, `spacing`, `shadows`, `radius`, `borders`, `whole-vibe`). Common patterns:

- `"colors and typography"` → `[colors, typography]`
- `"shadows + radius"` → `[shadows, radius]`
- `"everything except spacing"` → `[colors, typography, shadows, radius, borders]`
- `"just borders"` → `[borders]`
- `"whole vibe"` / `"everything"` → `[whole-vibe]` (expands to all categories)

If the response is unparseable or mentions an aspect not in the enum, ask one clarifying AskUserQuestion with the enum members as picks. Don't loop on free-text refinement.

**Aspect categories** (enum used throughout): `colors`, `typography`, `spacing`, `shadows`, `radius`, `borders`, `whole-vibe` (expands to all categories).

**Extract from the source site:**

Check if chrome-devtools MCP tools are available by looking for `navigate_page` tool.

**If chrome-devtools MCP is available (primary path):**

Step 1 - Navigate: Use `navigate_page` tool with the URL. Wait for page load.

Step 2 - Screenshot: Use `take_screenshot` tool. Save to `.craft/inspiration/screenshots/[domain-slug].png`.

Step 3 - Extract: Use `evaluate_script` tool with JavaScript that extracts the requested aspects. The script depends on which aspects were selected:

For **colors**: Run this JavaScript via `evaluate_script`:
```javascript
(() => {
  const colors = new Map();
  const els = document.querySelectorAll('*');
  for (const el of els) {
    const s = getComputedStyle(el);
    for (const prop of ['color', 'backgroundColor', 'borderColor', 'boxShadow']) {
      const v = s[prop];
      if (v && v !== 'rgba(0, 0, 0, 0)' && v !== 'transparent' && v !== 'rgb(0, 0, 0)') {
        const hex = rgbToHex(v);
        if (hex) colors.set(hex, (colors.get(hex) || 0) + 1);
      }
    }
  }
  const rootSheet = [...document.styleSheets].flatMap(s => {
    try { return [...s.cssRules]; } catch { return []; }
  });
  for (const rule of rootSheet) {
    if (rule.selectorText === ':root' && rule.style) {
      for (let i = 0; i < rule.style.length; i++) {
        const prop = rule.style[i];
        if (prop.startsWith('--') && /color|bg|surface|brand|primary|accent/i.test(prop)) {
          const val = rule.style.getPropertyValue(prop).trim();
          colors.set(val, (colors.get(val) || 0) + 100);
        }
      }
    }
  }
  function rgbToHex(rgb) {
    const m = rgb.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
    if (!m) return null;
    return '#' + [m[1],m[2],m[3]].map(x => parseInt(x).toString(16).padStart(2,'0')).join('');
  }
  return [...colors.entries()].sort((a,b) => b[1] - a[1]).slice(0, 20).map(([hex, count]) => ({hex, count}));
})()
```

For **typography**: Run this JavaScript via `evaluate_script`:
```javascript
(() => {
  const fonts = new Map();
  const sizes = new Map();
  const weights = new Map();
  const els = document.querySelectorAll('h1,h2,h3,h4,h5,h6,p,span,a,li,button,label,input');
  for (const el of els) {
    const s = getComputedStyle(el);
    const family = s.fontFamily.split(',')[0].trim().replace(/['"]/g, '');
    fonts.set(family, (fonts.get(family) || 0) + 1);
    sizes.set(s.fontSize, (sizes.get(s.fontSize) || 0) + 1);
    weights.set(s.fontWeight, (weights.get(s.fontWeight) || 0) + 1);
  }
  return {
    fonts: [...fonts.entries()].sort((a,b) => b[1] - a[1]).slice(0, 5),
    sizes: [...sizes.entries()].sort((a,b) => b[1] - a[1]).slice(0, 10),
    weights: [...weights.entries()].sort((a,b) => b[1] - a[1]).slice(0, 5)
  };
})()
```

For **spacing**: Run this JavaScript via `evaluate_script`:
```javascript
(() => {
  const gaps = new Map();
  const paddings = new Map();
  const els = document.querySelectorAll('*');
  for (const el of els) {
    const s = getComputedStyle(el);
    for (const prop of ['gap', 'rowGap', 'columnGap']) {
      const v = s[prop];
      if (v && v !== 'normal' && v !== '0px') gaps.set(v, (gaps.get(v) || 0) + 1);
    }
    for (const prop of ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft']) {
      const v = s[prop];
      if (v && v !== '0px') paddings.set(v, (paddings.get(v) || 0) + 1);
    }
  }
  return {
    gaps: [...gaps.entries()].sort((a,b) => b[1] - a[1]).slice(0, 10),
    paddings: [...paddings.entries()].sort((a,b) => b[1] - a[1]).slice(0, 10)
  };
})()
```

For **shadows**: Run via `evaluate_script`:
```javascript
(() => {
  const shadows = new Map();
  for (const el of document.querySelectorAll('*')) {
    const s = getComputedStyle(el).boxShadow;
    if (s && s !== 'none') shadows.set(s, (shadows.get(s) || 0) + 1);
  }
  return [...shadows.entries()].sort((a,b) => b[1] - a[1]).slice(0, 5);
})()
```

For **radius**: Run via `evaluate_script`:
```javascript
(() => {
  const radii = new Map();
  for (const el of document.querySelectorAll('*')) {
    const r = getComputedStyle(el).borderRadius;
    if (r && r !== '0px') radii.set(r, (radii.get(r) || 0) + 1);
  }
  return [...radii.entries()].sort((a,b) => b[1] - a[1]).slice(0, 5);
})()
```

For **whole-vibe**: Run all of the above scripts sequentially.

Step 4 - Present extraction results to user:

> "From **[site name]**, I captured:
>
> [For each aspect category extracted:]
> **Colors:** [top 5-8 colors with hex values and usage counts]
> **Typography:** [font families, top sizes, weights]
> **Spacing:** [gap/padding patterns]
> [etc.]
>
> Screenshot saved to `.craft/inspiration/screenshots/[slug].png`"

Step 5 - Update the session file. Append a new entry to the `sources` array with the URL, site name (derive from domain - e.g., "linear.app" becomes "Linear"), aspects selected, and extracted values. Write the updated YAML to `.craft/design/.inspiration-session`.

**If chrome-devtools MCP is NOT available (WebFetch fallback):**

Use WebFetch to fetch the URL. Extract what's available from HTML/CSS:
- Colors from inline styles, style tags, and linked stylesheets (limited - only what's in the HTML response)
- Font families from CSS font-family declarations
- Note that spacing/shadows/radius are less reliable from static HTML

Present results with a caveat:
> "I used basic HTML extraction (browser tools aren't available). Results may be less accurate than full browser extraction. Consider restarting Claude Code to enable chrome-devtools MCP for better results."

Still update the session file the same way.

**After extraction, ask the loop question:**

Use **AskUserQuestion**:
```
question: "Source captured! What next?"
header: "Sources"
options:
  - label: "Add another source"
    description: "Pull from one more reference site"
  - label: "Assemble what I have"
    description: "Combine [N] sources into a token set"
  - label: "Done for now"
    description: "Save session, I'll come back later"
```

**If "Add another source":** Loop back to the URL prompt. Repeat the extraction flow.

**If "Assemble":** Update session file `phase` to `"assembling"`. Proceed to Phase 3b.

**If "Done for now":** Session file already has all state. Print:
> "Session saved! You have [N] source(s) captured. Run `/craft` anytime to resume where you left off."
Skip to Phase 4 (tokens aren't locked yet, so Phase 5 will write none).

#### Phase 3b: Assembly + Interpretation

Read the session file. For each token category, merge values across all sources. When multiple sources contribute to the same category, use these merging rules:

**Color merging:**
- If one source was captured for colors and another wasn't, use the captured source's colors directly
- If multiple sources have colors, prefer the source whose colors were explicitly selected (not "whole vibe" default). If both explicitly selected, present both palettes and ask user to pick primary/surface/text

**Typography merging:**
- Use the most common font family across sources as the primary sans
- If sources have different fonts, present both and ask: "Which feels right for body text?"
- Mono font: use whichever source had a mono font, or fall back to "JetBrains Mono, monospace"

**Spacing merging:**
- Find the base unit by looking at the smallest common gap value across sources
- If sources use different spacing scales, note the difference and pick the one closest to a 4px base unit

**Shadows, radius, borders:**
- Use the source with the most entries in that category
- If roughly equal, present both and let user pick

**After merging, map to the tokens.yaml structure.** Use the template at `${CLAUDE_PLUGIN_ROOT}/templates/craft/design/tokens.yaml` as the target schema. For each section in the template, fill in the merged value if available, or leave the template default if no source provided that aspect.

Specifically, map extracted values to these token keys:
- `colors.primary` - the most prominent non-neutral color from color extraction
- `colors.background` - the most common background color (lightest or darkest depending on theme detection)
- `colors.surface` - second most common background color
- `colors.text-primary` - most common text color
- `colors.text-secondary` - second most common text color
- `typography.font-sans` - most common font family, with system fallbacks appended
- `typography.font-mono` - mono font if found, or template default
- `spacing.unit` - detected base unit (round to nearest 4px multiple)
- `radius.md` - most common border radius
- `shadows.md` - most common box shadow

**Creative interpretation:** After assembling tokens, write a 1-2 sentence creative description that names the combined feeling. This is NOT a technical summary - it's an evocative label. Examples:
- "Calm authority with warm accents - Linear's restraint meets Stripe's confidence"
- "Playful clarity - Vercel's precision softened by Notion's warmth"
- "Dark brutalism with generous breathing room"

Present the assembly:

> "I've combined your [N] sources into a unified design language:
>
> **[Creative interpretation]**
>
> **Colors:**
> | Token | Value | Source |
> |-------|-------|--------|
> | primary | #5E6AD2 | Linear |
> | background | #FFFFFF | Vercel |
> | surface | #FAFAF9 | Stripe |
> | text-primary | #171717 | Vercel |
> | text-secondary | #6B7280 | template default |
>
> **Typography:**
> | Token | Value | Source |
> |-------|-------|--------|
> | font-sans | Inter, -apple-system, ... | Vercel |
> | font-mono | Geist Mono, monospace | Vercel |
>
> **Spacing:**
> | Token | Value | Source |
> |-------|-------|--------|
> | unit | 4px | Linear |
>
> **Shadows:**
> [if captured]
>
> **Radius:**
> [if captured]
>
> Any values not captured from your sources use sensible defaults.
>
> How does this feel?"

Use **AskUserQuestion**:
```
question: "How does this feel?"
header: "Assembly"
options:
  - label: "Love it, lock these"
    description: "Write to tokens.yaml immediately"
  - label: "Close, let me adjust"
    description: "Riff on specific aspects"
  - label: "Add more sources first"
    description: "Go back to source collection"
  - label: "Save for later"
    description: "Keep the assembly, come back to finalize"
```

**If "Love it, lock these":** Jump to the Lock step below.

**If "Close, let me adjust":** Update session file `phase` to `"riffing"`. Proceed to Phase 3c.

**If "Add more sources":** Update session file `phase` to `"collecting"`. Loop back to Phase 3a's URL prompt.

**If "Save for later":** Update session file with current assembly. Print save message. Skip to Phase 4 (nothing locked - Phase 5 writes no tokens).

Update session file with the assembly (interpretation text + full token map).

#### Phase 3c: Riff Loop

The user adjusts, Claude responds. This is a conversational loop.

> "What would you like to adjust? (e.g., 'more warmth', 'less corporate', 'darker backgrounds', 'swap the font to Geist')"

[User provides free text adjustment]

**Interpret the adjustment.** The user speaks in vibes, not hex codes. Map their intent to specific token changes:

- "more warmth" -> shift colors toward amber/warm tones. Adjust primary/surface/accent colors.
- "less corporate" -> reduce spacing formality, consider rounder radius, softer shadows
- "darker" -> shift background toward darker values, invert text colors if needed
- "swap font to X" -> replace font-sans or font-mono with the specified font + system fallbacks
- "bolder" -> increase contrast between text-primary and background, consider heavier font weights
- Specific hex values -> apply directly to the mentioned token

After interpreting, present the updated tokens:

> "Got it - [echo back the interpretation]. Here's the update:
>
> **Changes:**
> | Token | Was | Now |
> |-------|-----|-----|
> | colors.primary | #5E6AD2 | #7C3AED |
> | colors.surface | #FAFAF9 | #FFFBF5 |
>
> **Updated interpretation:** [new creative description reflecting the riff]
>
> How's this?"

Use **AskUserQuestion**:
```
question: "How's this?"
header: "Riff"
options:
  - label: "Yeah THAT - lock it"
    description: "Write these tokens to tokens.yaml"
  - label: "Keep adjusting"
    description: "More riffing"
  - label: "Go back to assembly"
    description: "Start the riff from the original assembly"
  - label: "Save for later"
    description: "Keep progress, come back to finalize"
```

**If "Yeah THAT":** Proceed to Lock step.

**If "Keep adjusting":** Append the riff to session file's `riffs` array (input, response, token_changes). Loop back to the free text prompt.

**If "Go back to assembly":** Clear `riffs` array in session file. Update phase to `"assembling"`. Return to Phase 3b presentation.

**If "Save for later":** Update session file. Skip to Phase 4 (nothing locked - Phase 5 writes no tokens).

**Riff limit:** After 5 riffs without locking, gently nudge:
> "We've done [N] rounds of adjustments. These are looking refined. Ready to lock, or still want to adjust?"
This is a nudge, not a hard limit - the user can keep going.

#### Lock: Write Tokens

When the user confirms ("Love it, lock these" or "Yeah THAT"):

Step 1 - Read the current assembly tokens from the session file.

Step 2 - Read the tokens.yaml template from `${CLAUDE_PLUGIN_ROOT}/templates/craft/design/tokens.yaml`. This is the target structure.

Step 3 - Branch on whether `.craft/design/tokens.yaml` already exists:

**If no tokens.yaml exists:** Generate the final tokens.yaml by filling in the template structure with the assembled values. For each token in the template:
- If the assembly has a value for this token, use the assembly value
- If the assembly doesn't have a value, keep the template default
- Add a comment noting the source: `# from [source name]` or `# default`

**If tokens.yaml already exists (e.g. born from a converged `/craft:mockup`):** run the **Keyed tokens.yaml merge** script with reversed precedence - the inspiration-locked value wins on same-key collisions, and keys the session didn't cover survive with their provenance comments:

```bash
echo "$ASSEMBLY_VALUES" | python3 ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/merge-tokens.py merge .craft/design/tokens.yaml \
  --template ${CLAUDE_PLUGIN_ROOT}/templates/craft/design/tokens.yaml --precedence incoming
```

`$ASSEMBLY_VALUES` = one `section.key=value|from [source name]` line per assembled token. No `--resolve` flags here - precedence IS the resolution. On a non-zero exit the merge did NOT happen - report the script's error; never fall back to the Write tool.

Step 4 - On the no-pre-existing-file branch ONLY: write the populated tokens.yaml to `.craft/design/tokens.yaml` using the Write tool (creation is allowed; the deny applies only to an existing file). On the merge branch, Step 3's script already wrote the file - echo its summary line and skip this step.

Whichever Step 3 branch ran, set `INSPIRATION_WROTE_TOKENS=true`. Phase 5 reads this variable - not file existence, which cannot distinguish a file this session just locked from one that predates the run - to decide whether Phase 2's conflict answers still apply.

Step 5 - Update `.craft/inspiration/sites.md` with all source URLs and the creative interpretation.

Step 6 - Delete the session file:
```bash
rm -f "${CRAFT_PROJECT_ROOT:-.}/.craft/design/.inspiration-session"
```

Step 7 - Confirm to user:
> "Design tokens locked! Your design language: **[creative interpretation]**
>
> [N] source(s) combined, [M] riff(s) applied. Tokens are in `.craft/design/tokens.yaml` and will be enforced from now on.
>
> Let's continue setup."

Mark Design complete. Proceed to Phase 4.

---

### Phase 4: Create Structure

**Rail sweep on entry:** any beat still open ahead of Scaffold completes-with-note now, stating why the flow bypassed it - "parked - inspiration session saved for resume" for Phase 3's Done-for-now / Save-for-later doors, "skipped" for anything else. This single site backstops every early-exit door so no beat is left dangling.

Run the setup script with detected project type:

Export `SKIP_INSPIRATION` before calling the setup script. If Phase 3's inspiration session captured `inspiration/sites.md`, the flag prevents the setup script from overwriting it. The setup script never creates or touches `tokens.yaml` - an existing file (mockup-born, inspiration-locked, or prior init) is safe through this phase with no flag needed:

```bash
# If inspiration session already wrote sites.md, tell setup to skip the inspiration files block
if [ -f "${CRAFT_PROJECT_ROOT:-.}/.craft/inspiration/sites.md" ]; then
  SKIP_INSPIRATION=1
fi
SKIP_INSPIRATION=${SKIP_INSPIRATION:-0} ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/setup-craft.sh [PROJECT_TYPE]
# PROJECT_TYPE is "ui" or "cli" from Phase 1
```

**For UI projects** (`setup-craft.sh ui`):
```
.craft/
├── backlog/                    ← Empty, ready for stories
├── cycles/                     ← Empty, ready for cycles
├── projects/                   ← Empty, ready for projects
├── inspiration/
│   ├── screenshots/            ← From Phase 3
│   ├── sites.md                ← Reference URLs
│   └── patterns.md             ← UI patterns to follow
├── design/
│   ├── .confidence-signals.yaml ← Scanner confidence output (auto-generated)
│   ├── components.md           ← Component patterns
│   ├── locked.md               ← Approved UI patterns
│   └── animations.md           ← Motion patterns
│       (tokens.yaml is NOT created here - Phase 5 creates it from real values when tokens are locked)
├── project.md                  ← Project DNA (tech stack, conventions)
├── quality.yaml                ← Quality gates
├── settings.yaml               ← User preferences
├── .learnings.yaml             ← Captured learnings
└── .global-state               ← Runtime state
```

**For CLI/Backend projects** (`setup-craft.sh cli`):
```
.craft/
├── backlog/                    ← Empty, ready for stories
├── cycles/                     ← Empty, ready for cycles
├── projects/                   ← Empty, ready for projects
├── design/
│   ├── locked.md               ← Approved code patterns
│   └── schemas.md              ← Frontmatter schemas
│       (tokens.yaml is NOT created here - Phase 5 creates it from scanned conventions)
├── project.md                  ← Project DNA (tech stack, conventions)
├── quality.yaml                ← Quality gates
├── settings.yaml               ← User preferences
├── .learnings.yaml             ← Captured learnings
└── .global-state               ← Runtime state
```

---

### Phase 5: Generate Rich Files

The setup script copied structural templates (locked.md, components.md, quality.yaml). Now **enhance them with agent findings** - and create tokens.yaml from real values where the flow below says to (setup never creates it).

This is the key improvement — files are populated from actual project analysis, not templates with blanks.

#### project.md

**Use the agent's findings to generate a comprehensive project.md:**

```markdown
---
name: [project-name from package.json or directory]
type: [ui/cli/api]
package_manager: [detected]
deploy_target: [DEPLOY_TARGET from Phase 1b, or 'unknown' if user picked Not sure yet]
---

# [Project Name]

[Brief description from README or inferred from structure]

## Deployment

**Target:** [DEPLOY_TARGET human-readable form]

[If DEPLOY_TARGET is unknown: "Deploy target not specified at init. Stack recommendations will be neutral. Re-run `/craft:init` or edit `deploy_target` in this file's frontmatter when you're ready to commit to a target."]

[If DEPLOY_TARGET is known: "This value is a hint for downstream orchestration. When cycle planning offers framework, library, or tooling choices, options compatible with [DEPLOY_TARGET] are marked (Recommended). The user can override at any prompt."]

[If INTENT_CAPTURED=true, include the next two sections. If INTENT_CAPTURED=false, omit both entirely - they get added later if the user re-runs init with intent capture enabled.]

## Project Intent

**What it does for people:** [PROJECT_INTENT_Q1 verbatim]

**Killer moment to build:** [PROJECT_INTENT_Q2 verbatim]

## Emotional Core

[Phase 5 writes the section heading only. Phase 5b's muse session fills in the four fields below.]

**Emotional Job:** [filled by muse session]
**Identity Question:** [filled by muse session]
**Killer Moment:** [filled by muse session]
**Share Trigger:** [filled by muse session]

## Tech Stack

- **Runtime:** [Node.js/Python/etc]
- **Language:** [TypeScript/JavaScript/etc] ([percentage]%)
- **Framework:** [Next.js/Express/etc or "None"]
- **Package manager:** [pnpm/npm/yarn/bun]
- **Testing:** [Vitest/Jest/etc or "None configured"]

## Architecture

[From agent's architecture discovery]

### Directory Structure
```
[Agent's directory tree]
```

### Entry Points
| Type | Path | Purpose |
|------|------|---------|
[Agent's entry points table]

## Conventions

### Naming
[From agent's convention extraction]

### Organization
[From agent's pattern discovery]

### Code Style
[From agent's style detection]

## File Counts

[From agent's file inventory]

## Energy Level

**[Selected energy]** — [Description from Phase 2]

## Quality Philosophy

[Based on energy level selection]
```

#### locked.md (or design/locked.md)

**Populate with patterns the agent discovered:**

```markdown
# Locked Patterns

Approved patterns for [Project Name]. Follow these exactly.

---

[For each pattern the agent discovered in Phase P5:]

## [Pattern Name]

**Location:** [example file path from agent findings]

**Description:** [what the pattern is]

**Key elements:**
- [element 1]
- [element 2]

**Example:**
[Code snippet or reference from agent findings]

---

[Continue for all significant patterns...]
```

#### tokens.yaml

This is the single write site for extraction-path tokens: Phase 2's mid/mature branches decide WHAT gets locked; the write happens here. Branch on two live facts - were values locked this run, and does `.craft/design/tokens.yaml` exist right now:

**If nothing was locked this run (from-scratch, early UI, or the user chose Skip):** write nothing. An existing tokens.yaml (mockup-born, prior init) stands exactly as it is; an absent one stays absent. Tokens can be added later via `/craft:init` with inspiration, or by creating tokens.yaml manually.

**If values were locked and `.craft/design/tokens.yaml` exists:** run the **Keyed tokens.yaml merge** script (the only writer - the Write tool is denied on this file):

```bash
echo "$LOCKED_VALUES" | python3 ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/merge-tokens.py merge .craft/design/tokens.yaml \
  --template ${CLAUDE_PLUGIN_ROOT}/templates/craft/design/tokens.yaml \
  [--resolve section.key=incoming ...for each Phase 2 "Review each" take-scanned choice]
```

`$LOCKED_VALUES` = one `section.key=value|provenance comment` line per value the user locked in Phase 2. Default precedence (existing wins) is correct here. Echo the script's summary line to the user. On a non-zero exit the merge did NOT happen - report the script's error; never fall back to the Write tool.

**Whether the `--resolve` flags ride along depends on `INSPIRATION_WROTE_TOKENS` (set by Phase 3's Lock step):**
- **Unset or false (Phase 3 never ran, or ran without locking - the file predates this run, mockup-born or prior init):** include every Phase 2 "take scanned" choice as a `--resolve` flag, as shown above.
- **True (the Lock step wrote or merged the file this session):** omit ALL `--resolve` flags. Phase 2's conflict answers were given against the pre-inspiration file and must not override a value the user locked from inspiration afterward. Inspiration keeps every conflicting key; extraction fills only keys inspiration never set.

**If values were locked and no tokens.yaml exists (UI mid/mature extraction):** CREATE the file with the Write tool - creation on a missing file is always allowed. Read `${CLAUDE_PLUGIN_ROOT}/templates/craft/design/tokens.yaml` as the target structure and fill it with the extracted values the user locked; note provenance in comments (`# from codebase scan`). The template stays in the plugin - never copy it verbatim; every value in the written file is a real extracted value or a deliberately kept structural default.

**For CLI projects (Full setup reaches this phase):** same two live facts. No file → CREATE via Write: read `${CLAUDE_PLUGIN_ROOT}/templates/craft/design-cli/tokens.yaml` as the target structure, fill its sections with the scanner's convention findings, and add project-specific sections on top (layering, wire formats, whatever the scan surfaced - the file describes THIS project, not the template). File exists (re-init): update with targeted Edits on specific keys/sections - never a whole-file Write, which the hook denies.

**For CLI projects, the convention content** - this fills the create-via-Write or the targeted Edits described in the branch above, never a whole-file Write onto an existing file:

```yaml
# Conventions for [Project Name]
# Detected from codebase analysis

naming:
  files_components: "[detected]"    # e.g., "PascalCase"
  files_utilities: "[detected]"     # e.g., "kebab-case"
  functions: "[detected]"           # e.g., "camelCase"
  types: "[detected]"               # e.g., "PascalCase"
  constants: "[detected]"           # e.g., "SCREAMING_SNAKE"

file_structure:
  [from agent's directory organization findings]

code_style:
  semicolons: [detected]
  quotes: "[detected]"
  trailing_commas: [detected]
```

#### schemas.md (CLI projects only)

If the project has frontmatter-based files (like this plugin), document schemas found.
Otherwise, provide a template for future use.

#### settings.yaml and .learnings.yaml

These are standard templates — no customization needed from agent findings.

---

### Phase 5b: Muse Session (Optional)

If `INTENT_CAPTURED=true` from Phase 0.5, run a muse session now to capture the Emotional Core. The user has just seen Phase 5 generate project.md, tokens.yaml is locked (if Full setup with inspiration), and PROJECT_INTENT_Q1/Q2 are in memory. This is the moment with maximum substrate for muse.

If `INTENT_CAPTURED=false`, skip this phase entirely and continue to Phase 6.

**If `INTENT_CAPTURED=true`:**

⛔ **DO NOT invoke muse via the Skill tool (chain break - no return-to-caller).** Instead, Read and execute the logic inline:

```
Read "${CLAUDE_PLUGIN_ROOT}/commands/references/muse-inline.md"
Execute the muse interrogation logic against:
  - PROJECT_INTENT_Q1 (from Phase 0.5)
  - PROJECT_INTENT_Q2 (from Phase 0.5)
  - .craft/project.md (just generated)
  - .craft/design/tokens.yaml (if Full setup with inspiration)
```

The muse-inline reference handles:
- 4-turn capped session (cannot extend beyond turn 4)
- Pushing past surface answers toward emotional substrate
- Synthesizing into a four-field Emotional Core (Emotional Job / Identity Question / Killer Moment / Share Trigger)
- Writing the `## Emotional Core` section into project.md

After muse completes, continue to Phase 6 (First Cycle Kickoff). The first cycle's planning will have access to the Emotional Core via project.md.

**Skip option mid-session:** If the user signals "wrap" before turn 4, muse synthesizes from what's available and locks early. This is normal — not all projects need 4 turns.

---

### Phase 6: First Cycle Kickoff

On the Full-setup path, mark Scaffold complete (Quick setup has no rail), then show the recap first (Quick setup shows its own recap before arriving here):

> "**Project:** [name]
> **Type:** [ui/cli]
> **Energy:** [selected energy]
>
> I've documented [X] patterns in locked.md and captured your conventions."

Then ask the first-move question. This kickoff is DETERMINISTIC: present the AskUserQuestion below exactly as written - never a free-text "what are we tackling" prompt, never an improvised option set.

**Read the empty/has-code signal first:** Read `.craft/design/.confidence-signals.yaml` and take its `total_files` key (written at Phase 0a). Do not recompute the count, do not rely on conversation memory, and do not substitute `visual_file_count` - it measures something narrower. If the file or key is absent (Quick setup never writes it), no option carries (Recommended).

Use **AskUserQuestion**:
```
question: "Craft's ready. What's the first move?"
header: "First move"
options:
  - label: "Mock up a screen"
    description: "Three live options in your browser, before a line of code. React your way to the one that clicks - it becomes your first story."
  - label: "Describe a feature"
    description: "Tell me what we're building. We shape it into a story and get to work."
  - label: "I'll take it from here"
    description: "You're set up. Run `/craft` whenever you're ready to start."
```

**Option rules (deterministic - no judgment calls):**
- "Mock up a screen" renders ONLY when `PROJECT_TYPE` is `ui` or `hybrid`. For `cli`, `api`, or any other value (including free-text types from Phase 0b such as "static site" or "library"), omit that option entirely.
- Append `(Recommended)` to exactly one label:
  - `PROJECT_TYPE` ui/hybrid and `total_files == 0` -> "Mock up a screen (Recommended)"
  - `PROJECT_TYPE` ui/hybrid and `total_files > 0` -> "Describe a feature (Recommended)"
  - `PROJECT_TYPE` cli/api or any non-enum value -> "Describe a feature (Recommended)"
  - `total_files` absent (Quick setup) -> no option carries (Recommended)
  - "I'll take it from here" NEVER carries (Recommended)
- Option labels and descriptions are verbatim - regular dashes only, no rewording.

**Routing:**
- **"Mock up a screen"** -> invoke `/craft:mockup`
- **"Describe a feature"** -> [User describes it] -> creates first cycle -> enters Creative Phase -> starts riffing on stories
- **"I'll take it from here"** -> clean exit; init is complete

Whichever option resolves, complete the Kickoff task first (Full setup only) - the rail ends here; the destination flow (mockup, cycle creation) creates its own tasks.

---

## Existing Codebase (Special Handling)

If user selected "Existing codebase" in Phase 2, the agent has already analyzed patterns.

After Phase 5 file generation:

> "I've extracted [X] patterns from your existing code and documented them in locked.md.
>
> Want to review what I captured before we continue?"

Use **AskUserQuestion**:
```
question: "Review captured patterns?"
header: "Review"
options:
  - label: "Show me what you found"
    description: "Review and approve patterns before continuing"
  - label: "Looks good, continue"
    description: "Trust the extraction, move to first cycle"
  - label: "I'll review later"
    description: "Continue now, I'll check locked.md myself"
```

**If "Show me what you found":**
Display the locked.md contents, walk through each pattern, allow edits.

---

## Energy Adaptations

| Energy | CLAUDE.md Tone | Validation | Checkpoints |
|--------|----------------|------------|-------------|
| **Move fast** | Minimal, momentum | Light | Ask when weird |
| **Steady solid** | Thorough | Full + tests | Every chunk |
| **Learning** | Educational | Full + explain | Every step |

---

## Remember

- **Quick setup** for projects with strong CLAUDE.md — just scaffolds `.craft/`, start building
- **Full setup** for deep analysis — agent scans, extracts patterns, populates rich files
- **Run once per project** — sets the foundation for everything
- **Can be updated later** — `/craft:update-docs` re-scans and creates/updates project.md
- **Can be adjusted later** — via `/craft:reflect`
