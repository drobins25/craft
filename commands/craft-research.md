---
name: craft:research
description: "Ad-hoc research command. Parallel researcher agents investigate sub-questions, write branch files to disk, orchestrator ranks and synthesizes. Resumable across sessions."
argument-hint: "[query | topic-slug | continue | --quick | --deep]"
---

# Research

Ad-hoc research tool. Not part of the craft pipeline - use it whenever you want to understand something. Phase 1 produces comprehensive research most users never need to go beyond. Phase 2 is the optional "go deeper" layer.

## Project Root

Use `$CRAFT_PROJECT_ROOT` (set at session start) as the base path for all `.craft/` references. If not set, resolve by walking up from PWD to find the nearest `.craft/.global-state`.

**Cold fallback (uninitialized project):** if neither resolves, anchor to the git toplevel (`git rev-parse --show-toplevel`) when in a repo, else PWD - never a subdirectory. Research runs fine before `/craft:init`; artifacts land under the repo-root `.craft/research/`, not wherever the shell happens to sit.

Set `PROJECT` to the resolved root - env var, then walk-up, then git toplevel, then PWD, in that order. Never default to bare `.`.

## Flow

### Step 0: Determine Invocation Mode

Parse args to determine routing:

**Mode A - New research query:** Args contain a natural language query (not a known topic slug or "continue").
→ Jump to **Step 2** (Discover).

**Mode B - Existing topic slug:** Args match an existing folder name in `$PROJECT/.craft/research/`.
→ Jump to **Step 1b** (Browse Topic).

**Mode C - "continue" keyword:** Args are exactly `continue`.
→ Jump to **Step 1c** (Resume).

**Mode D - Quick flags:** Args contain `--quick` or `--deep` or `--exhaustive` after the query.
→ Extract the query and depth flag. Jump to **Step 2** with depth preset.

**Mode E - No args:** Jump to **Step 1** (Dashboard).

### Step 1: Research Dashboard

List existing research topics and their status.

Use **Glob** with pattern `$PROJECT/.craft/research/*/_plan.md` to find all research topics.

For each topic found:
- Use **Read** with `limit: 20` to extract frontmatter (query, date, status, depth)
- Check staleness: if `stale_after` exists and is past today's date, mark as `STALE`
- Check for pending elaboration: look for branch files with `status: complete` in frontmatter vs branches in `_plan.md`

**If no research exists:**
> "No research yet. What would you like to research?"
>
> [Wait for user input, then jump to **Step 2**]

**If research exists:**

Use **AskUserQuestion**:
```
question: "You have [N] research topics. What would you like to do?"
header: "Research"
options:
  - label: "Start new research"
    description: "Research a new topic from scratch"
  - label: "Browse existing"
    description: "[list: topic1 (complete), topic2 (STALE), topic3 (depth 1 - can go deeper)]"
  - label: "Go deeper on existing"
    description: "Pick a topic and elaborate on specific branches"
    → only show if any topics have branch files eligible for Phase 2
```

**If "Start new research"** → Ask "What would you like to research?", then jump to **Step 2**.
**If "Browse existing"** → Jump to **Step 1b** with topic picker.
**If "Go deeper"** → Jump to **Step 1b** with intent to elaborate.
**If user provides custom text** → Treat as a new research query, jump to **Step 2**.

### Step 1b: Browse Topic

If multiple topics, use **AskUserQuestion** to pick one. If already selected (from Mode B), skip the picker.

Use **Read** to read the topic's `_plan.md`. Display the ranked overview to the user.

Use **AskUserQuestion**:
```
question: "What would you like to do with this research?"
header: "Topic"
options:
  - label: "Go deeper on a branch"
    description: "Pick a branch to elaborate further (Phase 2)"
  - label: "Verify findings"
    description: "Challenge claims against independent primary sources (runs /craft:research-verify)"
  - label: "Crystallize into an expert"
    description: "Create a reusable expert agent from this research"
  - label: "Re-research (refresh)"
    description: "This topic may be stale - run fresh research"
  - label: "Done browsing"
    description: "Back to what I was doing"
```

**If "Go deeper"** → Show ranked branches from `_plan.md`, let user pick one or more. Jump to **Step 4** (Deeper Research).
**If "Verify findings"** → Invoke `/craft:research-verify {topic-slug}`.
**If "Crystallize"** → Jump to **Step 6** (Crystallize Expert).
**If "Re-research"** → Jump to **Step 2** with the original query from the topic's frontmatter. Existing folder gets archived to `{slug}--archived-{date}/`.
**If "Done"** → End.
**If custom text** → Treat as clarification or new query in context of this topic.

### Step 1c: Resume In-Progress

Use **Glob** to find topics where `_plan.md` has `status: in-progress`.

If one topic → auto-select it. Check what phase it's in based on which files exist.
If multiple → use **AskUserQuestion** to pick which topic to continue.

Resume from where it left off based on which files exist:
- **Branch files missing or incomplete** (no `status: complete`) → re-spawn those researcher agents (Step 2.2).
- **All branch files complete but `_plan.md` is still a stub / `status: in-progress`** → the run was interrupted before synthesis. Build the manifest from the existing branch files and spawn the synthesizer (Step 2.4). Do NOT synthesize in the main loop.

---

### Step 2: Discover (Phase 1) - The Main Research

**This is the primary research product.** Most users stop here. The output should be comprehensive and valuable on its own.

#### 2.1: Create Research Folder

Create `$PROJECT/.craft/research/{topic-slug}/` using Bash `mkdir -p`.

Write initial `_plan.md` stub with `status: in-progress`:

```markdown
---
query: "original query"
date: {today}
status: in-progress
depth: 1
stale_after: {today + 3 months}
---

# Research: {Topic}

> In progress - agents researching...
```

#### 2.2: Decompose and Dispatch

Break the query into 3-5 sub-questions that cover the topic from different angles. Use your own knowledge to decompose - no searching needed. Think about:
- What is X? (fundamentals)
- How does X work? (mechanics)
- What are the alternatives? (landscape)
- What are the trade-offs? (decision support)
- What do practitioners report? (real-world experience)
- What's the current state of the art? (freshness)

Not every query needs all angles. A focused query ("best auth library for Next.js") might need 3 sub-questions. A broad query ("how should we architect real-time sync") might need 5.

**Spawn one researcher agent per sub-question in parallel** via the Agent tool:

```
subagent_type: "craft:researcher"
description: "Research: {short branch name}"
prompt: |
  ## Your Assignment

  **Topic:** {full research topic}
  **Branch:** {branch name}
  **Question:** {specific sub-question}
  **Write findings to:** {$PROJECT/.craft/research/{topic-slug}/{NN}-{branch-slug}.md}
  **Branch template (read and follow exactly):** {CLAUDE_PLUGIN_ROOT}/commands/references/research-branch-template.md

  Extract findings for this question. Read the branch template first and follow its
  format and producer rules exactly. Write your branch file to the path above. Return
  only your lightweight summary to me.
```

Assign branch numbers (01, 02, 03...) in the order you decomposed them - order is just a label; the synthesizer re-ranks. Resolve `{CLAUDE_PLUGIN_ROOT}` to the actual plugin path before passing it (so the haiku researcher, which may not inherit the env var, gets a usable path).

**Launch ALL agents simultaneously.** Do not wait for one to finish before launching the next.

**If `--quick` flag was set:** Still spawn parallel agents, but add to each prompt: "Limit to 3-5 searches. Focus on the top 2-3 most authoritative sources. Be concise."

#### 2.3: Collect and Build the Manifest

As agents complete, collect their lightweight summaries (branch name, file path, source counts, finding counts, conflict counts). **Do NOT rank, synthesize, or write `_plan.md` yourself** - that is the synthesizer's job, and keeping it out of this main loop is the entire point of the refactor.

Build a **manifest**: the list of branch file paths you dispatched researchers to write (e.g. `01-foo.md, 02-bar.md, 03-baz.md`). You pass this to the synthesizer so it can detect missing or malformed branches rather than silently synthesizing a partial set.

#### 2.4: Spawn the Synthesizer

Spawn the **research-synthesizer** agent (once) via the Agent tool. It reads every branch file and writes `_plan.md` + `_sources.md` directly to disk:

```
subagent_type: "craft:research-synthesizer"
description: "Synthesize: {topic}"
prompt: |
  ## Your Assignment

  **research_folder:** {$PROJECT/.craft/research/{topic-slug}/}
  **manifest:** {comma-separated branch file paths you dispatched, e.g. 01-foo.md, 02-bar.md, 03-baz.md}
  **query:** {original query}
  **topic:** {topic display name}
  **depth:** 1
  **Branch template:** {CLAUDE_PLUGIN_ROOT}/commands/references/research-branch-template.md

  Verify the manifest, read every branch file, and write _plan.md + _sources.md per the
  template's Consumer Notes. Preserve conflicts - do not reconcile. Return only your
  lightweight summary.
```

Resolve `{CLAUDE_PLUGIN_ROOT}` to the actual plugin path before passing it.

**Handle the synthesizer's return:**
- If it returns `STATUS: OK` → proceed to Step 2.5 (read `_plan.md` for present-results).
- If it returns `STATUS: PARTIAL_FAILURE` → do NOT present a partial result. Re-spawn the researcher(s) named in `MISSING:` (one retry), then re-invoke the synthesizer with the same manifest. If the second pass still returns `PARTIAL_FAILURE`, report to the user which branches failed and why, and stop.

The synthesizer wrote `_plan.md` and `_sources.md` - you do NOT write them. Read `_plan.md` when you need its content for the next step.

#### 2.5: Present Results

Display to the user:

> **Research complete: {Topic}**
>
> {TL;DR from plan}
>
> **Confidence:** {aggregate} | **Branches:** {N} | **Sources:** {total cited}
>
> {If convergence points exist:}
> **High confidence (multiple branches agree):**
> - {convergence point 1}
> - {convergence point 2}
>
> {If conflicts exist:}
> **Heads up - conflicts found:**
> - {conflict 1 summary}
>
> **Saved to:** `.craft/research/{topic-slug}/`

Then offer next steps:

Use **AskUserQuestion**:
```
question: "Research saved. What next?"
header: "Next"
options:
  - label: "Go deeper on specific branches"
    description: "Pick branches to elaborate further (Phase 2)"
  - label: "Crystallize into an expert"
    description: "Create a reusable expert agent from this research"
  - label: "Done"
    description: "Research is sufficient"
```

**If "Go deeper"** → Show ranked branches, let user pick. Jump to **Step 3**.
**If "Crystallize"** → Jump to **Step 6** (Crystallize Expert).
**If "Done"** → End.
**If custom text** → Interpret (e.g., "go deeper on 1 and 3", "actually research X too", "make me an expert from this").

---

### Step 3: Elaborate (Phase 2) - Go Deeper

**Optional depth layer.** User selected specific branches to elaborate on.

For each selected branch, spawn a **researcher agent**:

```
subagent_type: "craft:researcher"
description: "Deep dive: {branch name}"
prompt: |
  ## Your Assignment - Phase 2 (Go Deeper)

  **Topic:** {full research topic}
  **Branch:** {branch name}
  **Existing research file:** {path to existing branch file}
  **Write deeper findings to:** {path - see below for naming}

  Read the existing branch file first. Then research the GAPS, CONFLICTS, and
  AREAS THAT NEED MORE DEPTH. Do not re-research what's already well-covered.

  Focus on:
  - Resolving any conflicts noted in the existing file
  - Filling gaps in the existing findings
  - Finding primary sources for claims marked INSUFFICIENT_EVIDENCE
  - Practitioner experience and edge cases
```

**Phase 2 file naming:** The deeper findings get written alongside the original:
- If elaborating branch `02-depth-control.md`, the deeper file goes to `02-depth-control--deep.md`
- If going EVEN deeper later, the branch graduates to a folder (Step 4 pattern)

**After agents complete, re-invoke the synthesizer fresh** to regenerate `_plan.md` + `_sources.md` over the FULL branch set (original branches + new `--deep` files). The synthesizer is the sole writer of `_plan.md` in both phases - do NOT patch `_plan.md` inline from the main loop.

- Build an updated manifest including the original branch files AND the new `--deep` files.
- Spawn `craft:research-synthesizer` exactly as in Step 2.4, but with `depth: 2` (or current depth) and the full manifest.
- This is a fresh spawn (a new Agent call), not a continuation of any prior synthesizer - the synthesizer is stateless and reads the folder from disk, so it works identically whether Phase 2 runs in the same session or a resumed one.
- Handle `STATUS: OK` / `STATUS: PARTIAL_FAILURE` the same way as Step 2.4.

Present updated results to user with same format as Step 2.5.

---

### Step 4: Deeper Research (Graduate to Folder)

When a branch has both its original file AND a `--deep` file and the user wants to go EVEN deeper:

#### 4.1: Graduate File to Folder

Save existing `02-depth-control.md` content.
Create `02-depth-control/` folder.
Move original to `02-depth-control/README.md` (becomes the parent synthesis).
Move `02-depth-control--deep.md` into the folder as well.

#### 4.2: Decompose for Deeper Discovery

Based on the branch's findings, conflicts, and gaps, generate 2-5 deeper sub-questions. These should drill into specifics, not re-cover what's already known.

#### 4.3: Spawn and Elaborate

Same pattern as Step 2 but scoped to this branch's sub-questions. Agents write to `02-depth-control/01-{sub-slug}.md`, etc.

#### 4.4: Update Parent

Update `02-depth-control/README.md` with the deeper findings synthesis.
Update the top-level `_plan.md` to note that branch 02 has been expanded with a link to the subfolder.

---

### Step 6: Crystallize Expert (Optional)

**This step creates a reusable expert agent from the research.** The expert is a `.claude/agents/` file that any session on this project can invoke.

#### 6.1: Load Full Research (MANDATORY - DO NOT SKIP)

**STOP. You have NOT read the research yet.** Up to this point you have only seen agent summaries and branch file headers. That is NOT enough to crystallize an expert. You MUST read every branch file in full before writing anything.

Use **Glob** to find all branch files: `$PROJECT/.craft/research/{topic-slug}/[0-9]*.md`

**Read EVERY branch file completely using the Read tool.** Also read `_plan.md` in full. Also read any `--deep` files and verification files if they exist.

**Do not proceed to Step 6.2 until you have called Read on every single file.** The expert will be shallow and wrong if you skip this. This has happened before - twice - and produced bad experts. Read everything.

#### 6.2: Read the Crystallize Template

Use **Read** to read `${CLAUDE_PLUGIN_ROOT}/commands/references/crystallize-expert.md`.

Follow the template to write the expert agent file. The template contains the full 9-section structure, frontmatter guidance, and the key principles for distilling knowledge into an opinionated persona.

#### 6.3: Write the Agent File

Write to `.claude/agents/{topic-slug}-expert.md` following the template.

#### 6.4: Present Result

> **Expert crystallized: {topic-slug}-expert**
>
> Saved to `.claude/agents/{topic-slug}-expert.md`
>
> This agent is now available in any session on this project. Invoke it by name or let Claude Code suggest it based on the trigger conditions in the description.

**Done.**

---

## Depth Flags Reference

| Flag | Behavior |
|------|----------|
| (none) | Interactive - full Phase 1, offer Phase 2 at the end |
| `--quick` | Phase 1 with lighter agent prompts (3-5 searches each instead of 5-10) |
| `--deep` | Phase 1 + auto-elaborate ALL branches without asking |
| `--exhaustive` | Deep + auto-run `/craft:research-verify` on all high-confidence findings |

## File Structure Reference

```
.craft/research/
  {topic-slug}/
    _plan.md                   # THE research doc - ranked index, TL;DR, convergence, conflicts, all sources
    _sources.md                # Citation index - trace any claim to its source URL, type, and branch
    01-{branch-slug}.md        # Branch 1 findings (written by researcher agent)
    02-{branch-slug}.md        # Branch 2 findings
    02-{branch-slug}--deep.md  # Phase 2 deeper findings on branch 2 (optional)
    02-{branch-slug}/          # Branch graduated to folder (went even deeper)
      README.md                # Sub-synthesis for this branch
      01-{sub-slug}.md         # Deeper sub-branch
      02-{sub-slug}.md
    03-{branch-slug}.md        # Branch 3 findings
    verification-{slug}.md     # Verification verdict (written by /craft:research-verify)
    ...
```

## Agent Configuration

The research flow uses two agent types - haiku producers and a sonnet synthesizer:

**`craft:researcher`** (extraction):
- **Model:** Haiku (constrained extraction - verbatim quotes, source-backed findings, no synthesis)
- **Tools:** WebSearch, WebFetch, Read, Glob, Grep, Bash, Write
- **Writes** its branch file directly to disk per the branch template; returns a lightweight summary (~150 tokens)

**`craft:research-synthesizer`** (cross-branch synthesis):
- **Model:** Sonnet (faithful routing at volume - preserves conflicts, re-enforces the evidence gate, quote-claim alignment; model is locked, see the agent's rationale block)
- **Tools:** Read, Glob, Grep, Write, Bash (no web access - synthesizes only what the researchers found)
- **Reads** every branch file, **writes** `_plan.md` + `_sources.md` directly to disk; returns a lightweight summary (~150 tokens)

The orchestrator stays thin: it dispatches researchers, builds a manifest, spawns the synthesizer, and reads the resulting `_plan.md` - cross-branch synthesis no longer happens in the user's main conversation loop.
