---
name: craft:become
description: "Agent crystallization command. Studies a tool, role, or person and produces a portable 9-section agent that inhabits the domain - with beliefs, scar tissue, and instincts."
argument-hint: "[tool name | role | person name | description] [--deep]"
---

# Become

Crystallize a tool, role, or person into a portable AI agent. Unlike `/craft:research` which discovers what's true, `/craft:become` inhabits a mind - producing an agent with beliefs, decision frameworks, and scar tissue.

Agents produced by this command are portable. They carry perception, not project context. Project context comes from the environment at runtime.

## Project Root

Use `$CRAFT_PROJECT_ROOT` (set at session start) as the base path for all `.craft/` references. If not set, resolve by walking up from PWD to find the nearest `.craft/.global-state`.

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`.

## Flow

### Phase 0: Intent

**Mode flags:** Before classifying the input, scan args for flags.

- If args contain `--deep`, set `DEPTH=7` and strip the flag from the remaining args. The stripped args are then classified by source type as below.
- If `--deep` is absent, set `DEPTH=5`.

`DEPTH` is referenced in Phase 1 to size the sub-question generation. The default of 5 is role-optimized: most become runs synthesize across practitioners with genuine disagreement, and 5 branches cover the six psychological-material categories (beliefs, trade-offs, refusals, mistake taxonomy, user needs, scar tissue) with one branch absorbing two adjacent categories. Source-based research (one tool) naturally saturates at 3-4 branches and can run lighter. Person-based with a sparse-but-prolific subject benefits from `--deep` (7 branches) to give the crystallizer enough signal.

If the user passes `--deep` with no other input (e.g., `/craft:become --deep`), treat the remaining args as empty and fall through to the "If no args" branch below.

Parse args to determine what we're crystallizing.

**If no args:** Use **AskUserQuestion**:
```
question: "What tool, role, or person do you want to crystallize into an agent?"
header: "Become"
options:
  - label: "A specific tool"
    description: "Reverse-engineer a tool's decision logic (e.g., CodeRabbit, Lighthouse, ESLint)"
  - label: "A role/expertise"
    description: "Synthesize what the best practitioners believe (e.g., accessibility auditor, UX designer)"
  - label: "A specific person"
    description: "Reconstruct an individual's perceptual framework from their artifacts"
```
Then ask for the specific name/description.

**If args provided:** Infer the source type:
- **Source-based:** Input names a specific tool, library, or product (e.g., "CodeRabbit", "Lighthouse", "Playwright"). Research is narrow and deep - reverse-engineer this tool's decision logic.
- **Role-based:** Input describes a domain or expertise (e.g., "accessibility auditor", "AI-first UX designer", "performance engineer"). Research is broad - synthesize what the best practitioners believe.
- **Person-based:** Input names a specific individual (e.g., "Darin", "Kent Beck"). Research uses writings, decisions, behavioral patterns.

**Only clarify if genuinely ambiguous.** "CodeRabbit" is obviously source-based. "Accessibility auditor" is obviously role-based. But "React expert" could be role-based (what do great React developers believe?) or source-based (reverse-engineer React's design philosophy). When ambiguous, use **AskUserQuestion** with 2-3 interpretations and an opinionated recommendation:

```
question: "'{input}' could mean different things. Which direction?"
header: "Direction"
options:
  - label: "{interpretation 1} (Recommended)"
    description: "{why this is the strongest direction}"
  - label: "{interpretation 2}"
    description: "{what this would produce}"
```

**Set up the research folder:**
- Slugify the input for the folder name (e.g., "AI-first UX designer" -> `ai-first-ux-designer`)
- Research path: `$PROJECT/.craft/research/{slug}-become/`
- Check if this folder already exists. If it does, use **AskUserQuestion**: resume existing research or start fresh?

### Phase 1: Psychological Research

Generate `{DEPTH}` sub-questions shaped for **mind-replication**, not fact-gathering. `{DEPTH}` is 5 by default (role-optimized) and 7 when `--deep` was passed in Phase 0. The six categories to cover:

1. **Beliefs** - What do the best practitioners in this domain believe that outsiders think is wrong? What do they treat as obvious that newcomers keep getting wrong?
2. **Trade-offs** - Where do practitioners genuinely disagree with each other, and what does each side think the other is missing?
3. **Refusals/Boundaries** - What do they refuse to do even when stakeholders push for it? What's their line?
4. **Mistake taxonomy** - What are beginner mistakes vs intermediate mistakes vs "looks right but subtly broken"? What have they seen fail badly enough to change their approach?
5. **What users actually need** - When someone asks this expert for X, what do they usually actually need? Where does the question behind the question live?
6. **Scar tissue** - What instinctive flinches do they have from past failures? What patterns trigger "this feels wrong" before they can articulate why?

**Adapt sub-questions based on source type:**
- **Source-based:** Focus on: what does this tool catch that others miss? What trade-offs did its designers make? What does it refuse to do? What are its blind spots?
- **Role-based:** Focus on: what do the best practitioners notice first? What's their threat model? Where is there genuine disagreement in the field?
- **Person-based:** Focus on: what are their recurring themes? What positions do they hold that generate friction? What do they treat as self-evident?

**Before spawning researchers, write the session plan to disk** (compaction survival - if context compresses during Phase 1, the orchestrator can recover state from this file):

Write `{research_path}/_plan.md` with:
```markdown
---
query: "{input}"
date: {today}
status: in-progress
depth: 1
source_type: {source/role/person}
mode: become
output_path: {$PROJECT/.claude/agents/become-{slug}.md}
---

# {input} - Become Research

## Sub-questions ({N} branches)

1. **01-{branch-slug}** - {sub-question}
2. **02-{branch-slug}** - {sub-question}
...
```

This file serves double duty: research documentation AND session state recovery. The `output_path` field is read back during Phase 4 iteration if the variable is lost to compaction.

**Use the Task tool to spawn one become-researcher agent per sub-question in parallel:**

```
Task tool:
  subagent_type: "craft:become-researcher"
  description: "Become research: {short branch name}"
  prompt: |
  ## Your Assignment

  You are collecting psychological material for an agent crystallization project.

  **Topic:** {input} (becoming an agent)
  **Source type:** {source/role/person}
  **Your sub-question:** {sub-question}

  ## Write your material to: {research_path}/{NN}-{branch-slug}.md

  Follow the branch file format in your agent instructions exactly.
  The crystallizer will read your output directly - give it raw psychological
  material, not summarized findings.
```

Wait for all researchers to complete.

**Verify branch files were written.** Rule 6 of the become-researcher prompt requires each researcher to find at least one high-signal source before writing its branch file. If a researcher fails to find one, it returns "no high-signal source found for this branch" and does NOT write the file. Detect this before Phase 2.

Using the **Bash tool**, count the branch files on disk in the research path. Files match the pattern `NN-*.md` (two-digit numeric prefix, any slug) but exclude underscore-prefixed orchestrator files like `_plan.md`. Compare the count against `DEPTH` (set in Phase 0 - 5 by default, 7 with `--deep`).

Illustrative shell pattern (substitute the actual research path):

```bash
find <research_path> -maxdepth 1 -name '[0-9][0-9]-*.md' ! -name '_*' | wc -l
```

**If the count equals `DEPTH`:** silent pass - proceed to Phase 2 with no user-facing message.

**If the count is less than `DEPTH`:** identify the missing branches by comparing the on-disk file names against the planned branch slugs in `_plan.md`. Surface via AskUserQuestion (first surfacing - 3 options):

```
question: "[N] of [DEPTH] researchers couldn't find high-signal sources for their branches: [list missing branch slugs]. How to proceed?"
header: "Missing branches"
options:
  - label: "Re-spawn missing branches (Recommended)"
    description: "Relaunch researchers for the missing branch slugs only - same prompt, fresh attempt"
  - label: "Proceed with what we have"
    description: "Continue to Phase 2 with [count] branches; the crystallizer will note thin coverage in the agent's Boundaries section"
  - label: "Stop and inspect"
    description: "End the command so you can read the researcher output files manually"
```

**If "Re-spawn missing branches":** Relaunch become-researchers via Task tool **for the missing branch slugs only**. Use the same researcher prompt the original branch would have received. **Do NOT pass summaries of existing branches into the retry prompts** - that collapses the context isolation that makes parallel research work. After the retry researchers complete, wait for them all, then re-run the branch-file count check **exactly once**.

**If the post-retry count still shows missing branches:** surface a follow-up AskUserQuestion with only **2 options** (no "Re-spawn again"):

```
question: "Retry didn't recover all branches. [N] still missing: [list]. How to proceed?"
header: "Retry failed"
options:
  - label: "Proceed with what we have (Recommended)"
    description: "Continue to Phase 2 with [count] branches; the crystallizer will note thin coverage in Boundaries"
  - label: "Stop and inspect"
    description: "End the command so you can read the researcher output files manually"
```

This cap exists to prevent context exhaustion before the crystallizer (the most expensive judgment call in the flow). Infinite retry loops would silently degrade the orchestrator's context budget by Phase 3 - producing a worse final agent. The user retains full control of every retry decision via AskUserQuestion; the cap only removes "Re-spawn" as an offered option on the second surfacing.

**Thin-coverage annotation (when user picks "Proceed with what we have" from either AUQ):** record the missing branch slugs (e.g., `["02-trade-offs", "04-mistake-taxonomy"]`). Later in Phase 3, when invoking the crystallizer, append a note to the prompt payload:

> `missing_branches: [list of missing branch slugs]`
>
> Note in the agent's Boundaries section that source coverage of [comma-separated branch topics] was thin during research.

The crystallizer already writes a Boundaries section as part of its 9-section output format - it absorbs this annotation without any change to `agents/crystallizer.md` and without inventing a new orchestrator-subagent protocol. The result: the final agent file transparently records what the research did and didn't fully cover.

**If "Stop and inspect":** End the command. Print the research path so the user can inspect the partial results manually.

### Phase 2: Synthesis Checkpoint

Read each branch file's **frontmatter plus the psychological-summary blockquote** (use the Read tool with `limit: 25` per branch - that covers frontmatter, the `# {Branch Name}` heading, the `> Part of` line, and the `> **Psychological summary:**` 2-3 sentence opener). Do NOT read full branch files here - that's the crystallizer's job in Phase 3. The orchestrator's synthesis should be lightweight and direction-setting, not exhaustive. Reading full branches at this point overloads the orchestrator's context right before the highest-stakes handoff.

The psychological summary is the branch's own 2-3 sentence answer to "what does this branch reveal about how the subject THINKS." Frontmatter alone (source counts, search types used, status) is too thin to spot convergence across branches - especially with haiku-4.5 researchers whose frontmatter signals may understate findings. The blockquote carries the actual signal.

<!-- Phase 2 design note (2026-05-23, become efficiency pass): we considered
     skipping Phase 2 entirely since the crystallizer reads full files in
     Phase 3 anyway. We kept Phase 2 because it carries the synthesis-
     steering AskUserQuestion (the user's chance to say "lean into X"
     before crystallization) and the "Research more" escape hatch. The
     adjust-read path is a single `limit:` bump plus a parsing tweak;
     skipping would have been a much larger removal that loses real
     workflow value. -->

Present to the user:

**Strong convergence** (findings that multiple branches agree on):
- List the top 3-5 converging findings with brief descriptions

**Interesting tensions** (where branches disagree or reveal genuine trade-offs):
- List any disagreements or split opinions

**Scar tissue** (things that failed, instinctive flinches):
- List the most interesting failure patterns or negative heuristics

**Gaps** (what the research didn't cover):
- Note any of the 6 categories that came back thin

Use **AskUserQuestion**:
```
question: "Any direction before I crystallize? You can guide emphasis or say 'go'."
header: "Synthesize"
options:
  - label: "Go - crystallize as-is"
    description: "Proceed with the research as it stands"
  - label: "Lean into specific findings"
    description: "I want to emphasize certain threads"
  - label: "Research more"
    description: "Some areas are too thin - spawn more researchers"
```

If "Lean into specific findings" - ask what to emphasize or de-emphasize. Capture as `user_direction`.

If "Research more" - ask which areas need more depth, generate new sub-questions, spawn additional researchers, then re-present Phase 2.

**After synthesis direction is captured**, use **AskUserQuestion** for the research handbook:
```
question: "Should the agent reference its research as a handbook for deeper context?"
header: "Handbook"
options:
  - label: "Yes - include research reference (Recommended)"
    description: "Agent knows where to find its detailed findings. Beliefs are self-contained, handbook is optional depth."
  - label: "No - fully self-contained"
    description: "Agent carries only beliefs and instincts, no external references"
```

If "Yes" - pass `include_handbook: true` and `handbook_path: {research_path}` to the crystallizer in Phase 3. The crystallizer adds a `research_handbook:` field to the agent's frontmatter and a note in the Boundaries section about when to consult it (grounding recommendations in specific sources, citing practitioner quotes, referencing detailed findings beyond what beliefs capture).

If "No" - omit handbook fields. The agent is fully portable with no external references.

### Phase 3: Crystallization

This is where the magic happens. The crystallizer writes the agent file directly to disk - the orchestrator NEVER touches agent content.

**Determine initial output path:**
- Slugify input for filename: `$PROJECT/.claude/agents/become-{slug}.md`
- This may be renamed in Phase 4

**Read 2-3 existing crystallized agents** from the plugin's `agents/` directory as format exemplars. Pick agents that are well-structured (e.g., `pr-reviewer-expert.md`, `crystallizer.md`).

**Invoke the crystallizer agent via the Task tool:**

```
Task tool:
  subagent_type: "craft:crystallizer"
  description: "Crystallize: {input}"
  prompt: |
    ## Crystallization Task

  Produce a 9-section agent file for: {input}
  Source type: {source/role/person}

  ## Parameters

  output_path: {output_path}
  research_folder: {research_path}
  exemplar_paths:
    - {exemplar_1_path}
    - {exemplar_2_path}
  source_type: {source/role/person}
  user_direction: {user_direction or omit this field entirely if user said "go"}

  ## Instructions

  1. Read ALL branch files in the research folder (mandatory)
  2. Read the exemplar agents for format reference
  3. Run your 7-phase extraction protocol
  4. Write the complete agent file to output_path
  5. Include provenance metadata: crystallized_from, crystallized_date, stale_signals
  6. Return a brief summary: identity (1 sentence), top 3 generative beliefs, blind spots
```

The crystallizer writes directly. Wait for it to complete and capture its summary.

### Phase 4: Review & Save

Read the crystallized agent file back from disk. Show the user:

- **Identity:** 1-sentence summary (from crystallizer's return)
- **Top generative beliefs:** The 3-5 beliefs that pre-answer the most decisions
- **Blind spots:** What this agent can't see
- **File size:** Line count / approximate density

**Recommend an agent name** based on what the research revealed, not just the slugified input. "CodeRabbit" might become "become-pr-reviewer-expert". "AI-first UX designer" might become "become-generative-ui-designer". The name should reflect what the agent IS, not what was studied. All crystallized agents use the `become-` prefix for easy discovery (skills glob for `become-*.md` to find available minds).

Use **AskUserQuestion**:
```
question: "Agent crystallized. How would you like to save it?"
header: "Save"
options:
  - label: "Save as become-{recommended-name} (Recommended)"
    description: "Save to .claude/agents/become-{recommended-name}.md"
  - label: "Save with different name or path"
    description: "Choose a custom name or save location"
  - label: "Iterate with feedback"
    description: "I want to adjust something - the crystallizer will edit in place"
  - label: "Start over"
    description: "Discard and re-crystallize from scratch"
```

**If "Save as recommended":** Rename the file from `become-{slug}.md` to `become-{recommended-name}.md` if different.

**If "Save with different name or path":** Ask for the name/path, move the file.

**If "Iterate with feedback":** Ask what to adjust. Re-invoke the crystallizer with feedback:

```
Task tool:
  subagent_type: "craft:crystallizer"
  description: "Iterate: {input}"
  prompt: |
    ## Iteration Task

  The user has feedback on the agent you crystallized.

  output_path: {output_path}
  research_folder: {research_path}
  feedback: "{user feedback}"

  Read your output file back, re-read the relevant branch files, and edit in place.
  Do NOT start from scratch unless the perceptual framework itself is wrong.

  Return updated summary: identity, top 3 beliefs, blind spots.
```

Then re-present Phase 4 with the updated agent.

**If "Start over":** Delete the agent file, jump back to Phase 2 (Synthesis Checkpoint). Re-crystallizing on the same research with no new direction produces the same agent. The user needs a chance to provide different editorial direction or spawn additional researchers before re-crystallizing.

**After save:** Report the final path and remind the user to restart the terminal for the new agent to register.

## Research Folder Structure

```
{slug}-become/
  _plan.md          # Sub-questions, source type, user direction
  01-{branch}.md    # Branch 1 (written by researcher agent)
  02-{branch}.md    # Branch 2
  ...
```

## Agent Configuration

- **Researchers** use the `craft:become-researcher` agent type (haiku 4.5 - psychological extraction is structured, not synthetic; the crystallizer carries the synthesis weight) - a specialized psychological material collector, NOT the generic fact-finding researcher used by `/craft:research`
- **Crystallizer** uses the `craft:crystallizer` agent type (opus - highest-judgment task)
- Researchers write branch files to disk using the psychological material format (axioms, scar tissue, threat model, domain inventory, etc.)
- Crystallizer writes the agent file to disk
- Orchestrator never writes agent content - it's a coordinator
