---
name: research
description: "Ad-hoc research command. Parallel researcher agents investigate sub-questions, write branch files to disk, orchestrator ranks and synthesizes. Resumable across sessions."
argument-hint: "[query | topic-slug | continue | --quick | --deep | --exhaustive]"
---

# Research

Ad-hoc research tool. Not part of the craft pipeline - use it whenever you want to understand something. Phase 1 produces comprehensive research most users never need to go beyond. Phase 2 is the optional "go deeper" layer.

## Project Root

Use `$CRAFT_PROJECT_ROOT` (set at session start) as the base path for all `.craft/` references. When it is not set, run `bash -c 'source "$1" >/dev/null 2>&1; craft_before_init_root' _ "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/find-workshop.sh"` and use the folder it prints.

Research runs fine before `/craft:init`; artifacts land under that folder's `.craft/research/`, not wherever the shell happens to sit.

Set `PROJECT` to that folder. Never default to bare `.`.

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
- **Branch files missing or incomplete** (no `status: complete`) → re-spawn those researcher agents (Read `${CLAUDE_PLUGIN_ROOT}/commands/references/research-inline.md` and follow its Step 4).
- **All branch files complete but `_plan.md` is still a stub / `status: in-progress`** → the run was interrupted before synthesis. Build the manifest from the existing branch files and spawn the synthesizer (the same reference, Step 6). Do NOT synthesize in the main loop.

---

### Step 2: Discover (Phase 1) - The Main Research

**This is the primary research product.** Most users stop here. The output should be comprehensive and valuable on its own.

Use **Read** to read `${CLAUDE_PLUGIN_ROOT}/commands/references/research-inline.md` and run it inline with `QUERY` (the user's query), `DEPTH` (`--quick` when that flag was set, otherwise none; `--deep` and `--exhaustive` stay with this command) and `PROJECT`. Set no `STORY` and no `DOOR`. It drafts the question and branches, checks the reading, creates the research folder, runs the researchers and the synthesizer, and presents the results.

**If `--deep` or `--exhaustive` was set:** ask nothing. Run Step 3 on every ranked branch in `_plan.md`; for `--exhaustive`, then invoke `/craft:research-verify {topic-slug}`. End.

Otherwise offer next steps:

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

**Optional depth layer.** Runs on the branches the user selected, or on every ranked branch under `--deep` / `--exhaustive`.

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
- Spawn `craft:research-synthesizer` exactly as in `${CLAUDE_PLUGIN_ROOT}/commands/references/research-inline.md` Step 6, but with `depth: 2` (or current depth) and the full manifest.
- This is a fresh spawn (a new Agent call), not a continuation of any prior synthesizer - the synthesizer is stateless and reads the folder from disk, so it works identically whether Phase 2 runs in the same session or a resumed one.
- Handle `STATUS: OK` / `STATUS: PARTIAL_FAILURE` the same way as research-inline.md Step 6.

Present updated results to user with the same format as research-inline.md Step 7.

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

Then run the two-readings test from research-inline.md Step 2 on these sub-questions, so the check runs on every decompose. When it fires, the question is answered before anything is spawned; 4.3 runs only after that.

#### 4.3: Spawn and Elaborate

Same pattern as `${CLAUDE_PLUGIN_ROOT}/commands/references/research-inline.md` Step 4 but scoped to this branch's sub-questions. Agents write to `02-depth-control/01-{sub-slug}.md`, etc.

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

Use the template for the expert agent file's structure and content. The template contains the full 9-section structure, frontmatter guidance, and the key principles for distilling knowledge into an opinionated persona. Its "Write the Agent File" step is the write in 6.3: make it there, after 6.3 opens the gate.

#### 6.3: Write the Agent File

Before the write, open this session's write gate:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/write-gate.sh open research
```

If the open exits non-zero, stop this write step and show the gate script's message. Then end here, without 6.4, because nothing was saved.

Write to `.claude/agents/{topic-slug}-expert.md` following the template.

#### 6.4: Present Result

First, before anything is shown, close the gate (this step asks nothing):

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/write-gate.sh close research
```

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
