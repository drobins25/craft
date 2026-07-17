# Alignment Check

**Before reading further, print this status line so the user sees a progress signal during the upcoming reasoning pass:**

> *Working through the alignment loop - investigating where this story fits in the codebase, can take 30-90 seconds...*

You are running the codebase alignment check for a story. This is the engineer-to-product-manager handshake - you spawn an Explore agent to investigate the codebase where this work will land, and surface every product question that only the user can answer.

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

### Step 0: Empty-Codebase Short-Circuit

Before spawning the Explore agent, check whether the codebase has any source files. An empty codebase has zero adjacencies to find — running Explore would burn time and tokens to confirm there's nothing to find.

**Check (rough):** Look for any files outside `.craft/`, `.claude/`, `node_modules/`, `.git/`, and root-level dotfiles. Bash one-liner option:

```bash
find . -type f \
  -not -path './.craft/*' \
  -not -path './.claude/*' \
  -not -path './node_modules/*' \
  -not -path './.git/*' \
  -not -name '.*' \
  | head -1
```

If the result is empty: **skip Step 1 entirely.** There's no codebase to investigate.

**Where product questions come from on an empty codebase:**

Read the story's `## Notes` section (populated during cycle-design Phase 2a's brainstorm). Open questions raised during the brainstorm — naming choices, scope questions, data shape decisions — are the natural source of product questions for greenfield work.

After harvesting questions from the Notes section, **skip ahead to Step 3 (Surface Gaps via AskUserQuestion)** to surface them to the user.

If the codebase has any source files: continue to Step 0.5 as normal.

### Step 0.5: Planning Context Injection (Planning-Sourced Stories Only)

Before spawning the Explore agent, check whether this story was created from a planning concept. If so, build a Planning Context block from the story's Reference Materials so the agent doesn't surface false-positive product questions for decisions already captured in planning.

**Detection:** Read the story frontmatter. If `source_concept:` is populated, this is a planning-sourced story - continue with the injection. If not, skip directly to Step 1 with the existing prompt unchanged.

**Build the Planning Context block (orchestrator-level work, NOT delegated to the Explore agent):**

1. Read the story's `## Reference Materials` section.

2. Parse each citation: extract the file path + anchor(s). Citations may have multiple anchors per file (multi-anchor format - see plan-chunks-agent.md section 1.3.5 for the contract).

3. For each cited file + anchor, use **Read** with the anchor to extract the excerpt. Apply the same anchor-aware reading rules from plan-chunks-agent's Reference Materials contract:
   - Planning files: locate `## Section` + `### Subheading` / `Decision #N` / dated entry, read that section only
   - Mockups: read the cited line range or HTML id
   - locked.md: read Pattern N's section
   - tokens.yaml: look up the token name
   - active.md: read the dated entry within `## Recent state changes`
   - Code files: read the cited function/class or line range

4. **Stale-anchor handling during injection (MANDATORY):** If a cited anchor cannot be resolved (section heading no longer exists, line range out of bounds, Pattern N missing from locked.md), do NOT silently omit. Surface the stale anchor BEFORE spawning the Explore agent via **AskUserQuestion**:

   ```
   question: "Reference Materials cites '[file path] -> [anchor]' but the anchor doesn't resolve in the current file. The story may have been written against an older version. How should we proceed?"
   header: "Stale Anchor"
   options:
     - label: "Skip this citation"
       description: "Proceed with alignment-check using the resolved citations only. This citation's content won't reach the agent."
     - label: "Re-extract from current planning"
       description: "Restart story creation flow (re-run /craft:story-new From planning) to refresh citations - alignment-check will run afterward."
     - label: "Provide replacement anchor"
       description: "Type the correct section/subheading/range manually."
   ```

   "Skip" -> proceed without that excerpt; "Re-extract" -> exit alignment-check with instruction to re-run story-from-planning; "Provide replacement anchor" -> capture user's input, retry the Read, continue.

5. Concatenate resolved excerpts into the Planning Context block.

6. **Hard 2000-token cap.** If excerpts would exceed 2000 tokens, prioritize in this order and drop lowest-priority until under cap:
   1. active.md dated entries (highest authority - current state)
   2. Concept Locked Decisions sections
   3. Sibling story precedents
   4. Mockups (visual contracts, less critical for product-question evaluation)
   
   If citations are dropped, note this in the Planning Context block so the agent knows content was elided.

**Format of the Planning Context block:**

```
PLANNING CONTEXT (from story Reference Materials, capped at 2000 tokens):

=== From [file basename] ([anchor]) ===
[excerpt text]

=== From [next file basename] ([anchor]) ===
[excerpt text]

...

[If cap was reached: "NOTE: [N] citation(s) dropped due to token cap: [list]. The agent may flag a CONCERN to re-run with narrower Reference Materials."]
```

Pass this Planning Context block into the Explore agent's prompt in Step 1 (see updated prompt template below).

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

    [PLANNING-SOURCED STORIES ONLY - include the Planning Context block built in Step 0.5 here, BEFORE the Investigate instructions:]
    [PLANNING CONTEXT block from Step 0.5]

    **When evaluating whether the story specifies a product question, FIRST check the Planning Context above (if present). Decisions captured in planning are NOT product questions - do NOT surface them. If the Planning Context note says citations were dropped due to token cap, you may flag a CONCERN that some planning content wasn't injected - the user can address by re-running with narrower Reference Materials.**

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

    Write every finding in plain language the user can read cold: no terms coined
    during your investigation, and never a bare file path, line number, or symbol
    name standing in for an explanation - say what the thing IS in words from the
    story or the user's own request, then cite the location once.

    If you find nothing noteworthy, say so. Don't manufacture findings.
    Report in under 500 words."
```

**The spawn result includes the agent's ID - repeat it in your next visible status line ("Explore agent: <id>") so it survives the distance to Step 4.** The description you typed is NOT an address - a send to the name fails. Follow-up rounds use SendMessage with this ID.

**Do not proceed to Step 2 until you have the Explore agent's findings in hand.**

### Step 2: Filter - What Actually Deserves to Interrupt the User

This is the most important step, and the gate's whole quality lives here. AskUserQuestion is for disambiguation between multiple legitimate paths - not for narrating what you found, not for permission, not for caution. Most codebase observations are NOT product questions; they are facts you act on.

**Surface a finding ONLY if BOTH are true:**
1. There are multiple legitimate paths and only the user can choose between them (a real fork in intent, not in mechanism).
2. The plan would be meaningfully worse if you decided it yourself and moved on.

**If either fails, do NOT surface it. Decide it and let the user veto later.** A fact ("there's no CLI to wire into - `index.js` is a library") is not a fork; you just don't wire a CLI that isn't there. An engineering call (test structure, key order) is yours. The bar is agent-judgment-plus-veto, not agent-question-plus-guidance.

**"Only the user can decide" means the CHOICE is theirs - not that you have no opinion on it.** When a finding DOES pass this filter, you still bring your recommendation to it. Restraint decides *whether* to ask; it never means going neutral once you do. Every surfaced fork ends on your lean and marks the recommended option `(Recommended)` in the widget (Step 3) - "here's what I'd do, your call," never a menu with no pointer.

**The removal test:** for each candidate, ask "if I delete this question, is the plan actually worse?" If not, it was overhead - cut it. (After the third or fourth question a user stops reading and starts clicking; every needless one spends that budget.)

**Collapse before you surface.** Two findings that share one underlying decision are ONE question. "warn already exists" and "the CLI it names doesn't" are not two forks - they are one: "your premise is already built; what is this story now?" Fold the second into the first's options; never ask it twice.

### Step 3: Surface Gaps via AskUserQuestion

**Before constructing the AskUserQuestion(s)**, Read `agent-finding-handoff.md` (in this same directory - resolve it against the absolute path you just Read this file from) and apply the Self-Contained Test to each finding the Explore agent surfaced. The user does NOT have the Explore agent's codebase-research context. A finding that names a file path, function, locked-decision number, or pattern identifier without semantic context will force the user to re-investigate what the finding means before answering. Expand identifiers per the Translation Table in that file, then construct the question(s) with expanded content.

**Then Read `commands/references/auq-grammar.md`** (resolve it against the absolute path you Read this file from - it is a sibling of this file) and mirror the worked gate that matches your finding. That file holds two: a **fork** (a real decision between live alternatives - brief, short airy prose ending on a bold lean, recommended option first with `(Recommended)`, honest one-line verdicts) and a **dead end** (the story's premise is already built or void - a few sentences of fact, then only the story-fate question). Match on substance: weighing alternatives is a fork; reporting a fact that decides itself is a dead end. Mirror the shape, never the content.

**One finding per AskUserQuestion, sequenced.** Present a finding, ask its one question, and record the answer before surfacing the next finding - an answer often changes what the next question should be (that reassessment is Step 4). Never stack multiple decisions into one widget.

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
  to: [the agentId from the spawn result - never the description]
  message: "The user's answers changed the scope. Here's what changed:
    [Summarize what the user decided]

    Investigate the implications:
    - What additional files does this touch?
    - Any new conflicts or adjacencies from the expanded scope?
    - Does this create any new product questions?

    Same report format. Only report NEW findings - don't repeat what you already found."
```

Process the new findings (Step 2) and surface any new product questions (Step 3).

If the agent is unreachable, spawn a fresh Explore agent seeded with the original findings and what changed - and say so in one line. Never guess at an address.

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

1. Add a `## Alignment` section to the story - the receipt that the check ran:
   - `_Checked: YYYY-MM-DD_`
   - One line per finding: type, what it was, how the user resolved it
   - If the investigation found nothing: `No findings - investigation returned clean.`
   Keep it a receipt, not a transcript - detailed outcomes belong in the sections below.
2. Update the story's frontmatter: `alignment: complete`
3. Update `## Scope` section if the user's answers changed what's included/excluded
4. Update `## Decisions` if new decisions were made during the dialogue - unless the decision's reasoning already lives in the section it affects (Scope, Content Direction, a chunk). Then a one-line pointer in `## Decisions` is enough; don't duplicate the reasoning, and never demote it to an HTML comment
5. Update `## Likely Files` if the investigation revealed additional files
6. If a story split occurred, create the new story file

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

If the investigation reveals zero product questions, that's a valid outcome. Write the `## Alignment` receipt (`No findings - investigation returned clean.`), set `alignment: complete`, and move on. The check is fast when there's nothing to find.
