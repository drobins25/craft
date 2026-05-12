# Alignment Check

**Before reading further, print this status line so the user sees a progress signal during the upcoming reasoning pass:**

> *Working through the alignment loop — this can take a minute on a fresh codebase...*

You are running the codebase alignment check for a story. This is the engineer-to-product-manager handshake - you investigate the codebase where this work will land and surface every product question that only the user can answer.

## Definition: 95% Alignment

**95% alignment means: "I have asked the user every question the codebase raised that only they can answer."**

It is NOT about:
- Whether the solution approach is right (that's your job as the engineer)
- Whether the chunks will work (that's plan-chunks' job)
- Whether the code will compile (that's validation's job)

It IS about:
- **Conflicts discovered** - "Found existing X - replace, update, or coexist?" → asked
- **Adjacencies & suggestions** - "This pattern exists in N other places - apply there too?" → asked
- **Assumptions surfaced** - "You said X but the codebase implies Y - which is it?" → asked
- **Scope implications confirmed** - "Your answers expanded this - split or keep?" → asked

**The gate is not "do I feel confident?" It's "do I have zero unasked product questions?"**

Product questions go to the user. Engineering questions you solve yourself. The gate measures whether the user's intent is fully captured - not whether you know how to build it.

## When This Runs

- During `craft-story-new` Step 8 (when user chose "Keep designing", before acceptance criteria)
- During `craft-cycle-design` per-story (before plan-chunks)
- During `plan-chunks` Phase 0 (if `alignment: pending` in story frontmatter - catches stories that skipped the check during creation)

## Prerequisites

Before starting, you need:
1. The story file path (to read the spark, decisions, scope)
2. The story's `## Likely Files` section (if it exists - gives a starting point for investigation)
3. Any decisions captured so far

## The Loop

### Step 1: Spawn Explore Agent

Spawn an Explore agent to investigate the codebase. The agent's job is to find things that only the user can clarify - not to solve engineering problems.

```
Agent tool:
  subagent_type: "Explore"
  description: "Codebase alignment investigation for [story name]"
  prompt: "I'm about to implement a story. I need you to investigate the codebase
    and find anything that raises a PRODUCT question - something only the user
    (acting as product manager) can answer.

    STORY: [story name]
    SPARK: [paste spark text]
    SCOPE: [paste scope if exists]
    DECISIONS: [paste decisions if exist]
    LIKELY FILES: [paste likely files if exist]

    Investigate:
    1. Read the files this story will touch and their surrounding context
    2. Look for EXISTING code that does something similar or overlapping
    3. Look for PATTERNS this work should follow or could extend to other places
    4. Look for NAMING, STRUCTURE, or CONVENTION conflicts
    5. Check if the described work would affect other parts of the codebase

    For each finding, categorize it:
    - CONFLICT: Existing code that overlaps, contradicts, or would be replaced
    - ADJACENCY: Related code/patterns where the user might want the same change applied
    - ASSUMPTION: Something the story implies that the codebase contradicts or doesn't support

    Report format (keep it concise):
    ## Findings
    ### [CONFLICT/ADJACENCY/ASSUMPTION]: [one-line summary]
    **Where:** [file path + line range]
    **What I found:** [2-3 sentences]
    **Product question:** [the specific question only the user can answer]

    If you find nothing noteworthy, say so. Don't manufacture findings.
    Report in under 500 words."
```

**Save the agent's ID** - you will use SendMessage for follow-up rounds.

### Step 2: Process Findings

Read the Explore agent's findings. For each finding, decide:
- Is this a genuine product question? (Surface it)
- Is this an engineering question you can answer yourself? (Don't surface it)
- Is this informational with no ambiguity? (Don't surface it)

Filter to only genuine product questions.

### Step 3: Surface Gaps via AskUserQuestion

**Group related findings in a single message.** Don't pepper the user with one-at-a-time questions. Present them conversationally:

> "Before I plan the chunks, I looked at the codebase where this work lands. A few things came up:"

Then list findings with context:

> "1. **[Finding type]:** [What you found in file X]. [Product question]"
> "2. **[Finding type]:** [What you found in file Y]. [Product question]"

Use **AskUserQuestion** with options that map to the product questions. If findings are independent, you can use multiple AskUserQuestions. If they're interrelated (answer to Q1 affects Q2), ask them together or sequentially.

### Step 4: Reassess After Answers

After the user answers:

**Check if answers expanded scope:**
- Did the user say "yes, apply that everywhere"?
- Did the user add new requirements?
- Did the user reveal something the story didn't capture?

**If scope expanded:**

Use **SendMessage** to the same Explore agent (do NOT spawn a new one):

```
SendMessage:
  to: [agent ID from Step 1]
  message: "The user's answers changed the scope. Here's what changed:
    [Summarize what the user decided]

    Investigate the implications:
    - What additional files does this touch?
    - Any new conflicts or adjacencies from the expanded scope?
    - Does this create any new product questions?

    Same report format. Only report NEW findings - don't repeat what you already found."
```

Process the new findings (Step 2) and surface any new product questions (Step 3).

**If scope grew significantly** (story went from touching 3 files to 8+, or now spans two distinct concerns):

> "Based on your answers, this story grew from [original scope] to [new scope]. I'd suggest splitting:"
>
> "- **This story:** [focused scope A]"
> "- **New story:** [focused scope B]"
>
> "Split or keep as one?"

Use **AskUserQuestion** with split/keep options. If splitting, create the new story file and adjust the current story's scope.

### Step 5: Confirm Alignment

The loop exits when:
- All product questions from the investigation have been asked and answered
- No new findings emerged from the latest round
- Scope changes (if any) have been confirmed

**You do NOT need explicit confirmation from the user that alignment is complete.** The loop is complete when you have no more product questions to ask. The confidence is earned through the dialogue, not declared.

### Step 6: Update Story

After the loop completes:

1. Update the story's frontmatter: `alignment: complete`
2. Update `## Scope` section if the user's answers changed what's included/excluded
3. Update `## Decisions` if new decisions were made during the dialogue
4. Update `## Likely Files` if the investigation revealed additional files
5. If a story split occurred, create the new story file

## Batch Planning (plan-chunks MODE=batch)

In batch mode, the plan-chunks-agent runs autonomously per story. It cannot ask the user questions during its run. For stories with `alignment: pending`:

The plan-chunks orchestrator should flag these during triage:

> "These stories haven't been through the alignment check:"
> - [Story A]
> - [Story B]
>
> "Want me to run the alignment check interactively first, or let the planning agents use their best judgment?"

Use **AskUserQuestion** with options:
- "Run alignment check first" - orchestrator runs the alignment loop per story before launching agents
- "Proceed with best judgment" - agents plan without alignment check, but flag assumptions in their output for the user to review during triage

## What This Is NOT

- Not a code review (that's pr-reviewer-expert)
- Not a technical feasibility check (the orchestrator handles that during engineering)
- Not a checklist to rubber-stamp (it's an investigation that may find nothing)
- Not a blocker if the codebase is empty/new (no existing code = no conflicts to surface)

If the investigation reveals zero product questions, that's a valid outcome. Set `alignment: complete` and move on. The check is fast when there's nothing to find.
