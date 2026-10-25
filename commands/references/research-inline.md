# Research (Inline Reference)

This file is read by the alignment check, plan-chunks and `/craft:research` to run the discover flow inline in the current loop, never through the Skill tool. The standalone `/craft:research` command Reads this same file from its Step 2.

## Inputs

- `QUERY` - the ask: a topic when standalone, a research question from the alignment check or the planner.
- `STORY` - absolute path of the story file. Absent when standalone.
- `DOOR` - `alignment` or `planner`. Absent when standalone.
- `DEPTH` - `--quick` or none. The research command's `--deep` and `--exhaustive` never reach this file; the command acts on them itself after Step 7.
- `PROJECT` - set by the caller. With a story, it is the folder above the story's `.craft/`.

## Step 1: Draft the Question and Branches

Draft a short research question from `QUERY`. A topic typed at the standalone command is already a question; a story's outside premise is not, so state it as one.

Then break the question into 3-5 branches (sub-questions) that cover it from different angles. Use your own knowledge to decompose - no searching needed. Think about:
- What is X? (fundamentals)
- How does X work? (mechanics)
- What are the alternatives? (landscape)
- What are the trade-offs? (decision support)
- What do practitioners report? (real-world experience)
- What's the current state of the art? (freshness)

Not every question needs all angles. A focused question ("best auth library for Next.js") might need 3 branches. A broad one ("how should we architect real-time sync") might need 5.

## Step 2: The Two-Readings Test

Ask: "Would a different reading of the ask produce a different set of branches?" Run it on every decompose, standalone and refresh included.

"A website that works like a Claude Code plugin" and "a plugin published as a website" send research to two different places - that fires the test. A topic with one sensible reading does not.

**When the test does not fire:** print exactly one line and start:

`Researching: <question>. Branches: <a>, <b>, <c>.`

**When it fires:** Read `${CLAUDE_PLUGIN_ROOT}/commands/references/question-card.md` and ask one card with two options: the drafted reading, marked `(proposed)`, and the other reading the test found. Write each option as where the research goes - the branches it researches. The card names the outside thing, the reading the branches assume, and the research question. An answer in the user's own words rewrites the branches from those words and the run starts - no second ask.

## Step 3: Create the Research Folder

This runs after Step 2, so the slug follows the confirmed reading. If the slug is already taken by a different question, add a distinguishing suffix.

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

## Step 4: Dispatch Researchers

**Spawn one researcher agent per branch in parallel** via the Agent tool:

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

**If `DEPTH` is `--quick`:** Still spawn parallel agents, but add to each prompt: "Limit to 3-5 searches. Focus on the top 2-3 most authoritative sources. Be concise."

## Step 5: Collect and Build the Manifest

As agents complete, collect their lightweight summaries (branch name, file path, source counts, finding counts, conflict counts). **Do NOT rank, synthesize, or write `_plan.md` yourself** - that is the synthesizer's job, and keeping it out of this main loop is the entire point.

Build a **manifest**: the list of branch file paths you dispatched researchers to write (e.g. `01-foo.md, 02-bar.md, 03-baz.md`). You pass this to the synthesizer so it can detect missing or malformed branches rather than silently synthesizing a partial set.

## Step 6: Spawn the Synthesizer

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
- If it returns `STATUS: OK` → proceed to Step 7 (read `_plan.md` for the results display).
- If it returns `STATUS: PARTIAL_FAILURE` → do NOT present a partial result. Re-spawn the researcher(s) named in `MISSING:` (one retry), then re-invoke the synthesizer with the same manifest. If the second pass still returns `PARTIAL_FAILURE`, report to the user which branches failed and why, and stop.

The synthesizer wrote `_plan.md` and `_sources.md` - you do NOT write them. Read `_plan.md` when you need its content for the next step.

## Step 7: Present Results

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

## Step 8: Land on the Story

Run this step only when `STORY` is set; otherwise skip to Return.

Add to the story's `## Reference Materials` section, handling the three starting states:

- **Section absent:** create `## Reference Materials` directly after `## Likely Files`, or, when there is no Likely Files section, before `## Investigation` (before `## Acceptance` when neither exists).
- **Section holding only the template comment:** write the run line and entries below the comment.
- **Section with entries:** append the run line and entries below the existing ones.

Write the run line, then the entries:

```
_Research run <YYYY-MM-DD>, <DOOR> door: <question>_

- `<absolute PROJECT>/.craft/research/<slug>/_plan.md` -> "Convergence Points" (<one-line gloss>)
- `<absolute PROJECT>/.craft/research/<slug>/_plan.md` -> "Open Questions" (<one-line gloss>)
- `<absolute PROJECT>/.craft/research/<slug>/<NN>-<branch-slug>.md` -> "Findings" (<one-line gloss>)
```

Write one `"Findings"` entry per branch that answers the question. Every path is absolute. The dated run line is what tells a later caller this door already ran for the story.

## Return

With `STORY` set, return to the caller; do not ask what to do next. Without it, return to `/craft:research` Step 2.
