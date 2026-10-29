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

### Before Step 0: Research What Nobody in the Room Knows

Read the spark. If the story's work depends on something outside the project whose behavior nobody here has checked (a site, a person, a tool's output, a data source, a format), grep the project, `.craft/research/` and the story's Reference Materials for it. If they hold nothing, settle it; if a research folder already answers it, cite it onto the story instead of researching again. No such thing named, or it is already held: print nothing and go on to Step 0.

- **One fact** (one thing, one answer): at most three web searches, then say `Checked: <fact> (<source>).` in one line as you move on - it is not a question. Step 6 records it as `- OUTSIDE FACT: <fact> - <source>`.
- **Anything bigger** (a claim about a whole class, or a fact still open after three searches): Read `commands/references/research-inline.md` (a sibling of this file - resolve it against the absolute path you Read this file from) with `QUERY` the outside premise, `STORY` the story's absolute path and `DOOR=alignment`. Pass `DEPTH=--quick` for one bounded thing with few angles, no flag for a claim about a class ("every runner", "all providers"). Continue at Step 0 with the research in hand.
- **One run per door:** if the story's Reference Materials already holds a run line with `alignment door` and the gap is still open, never run again; ask the user on a question card (Step 3) what the story should assume.

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

After harvesting questions from the Notes section, **skip ahead to Step 3 (Surface Gaps on Question Cards)** to surface them to the user.

If the codebase has any source files: continue to Step 0.5 as normal.

### Step 0.5: Planning Context Injection

Before spawning the Explore agent, check whether this story was created from a planning concept or carries approved decision records or research. If so, build a Planning Context block from the story's Reference Materials, and hand decision records to the agent as paths (see 4a - they never enter the block or its token cap), so the agent doesn't surface false-positive product questions for decisions already captured in planning.

**Detection:** Read the story frontmatter. If `source_concept:` is populated OR the story's `decisions:` list is non-empty OR its `## Reference Materials` holds at least one citation entry (a `- ` line; the template's comment alone does not count), continue with the injection below. Otherwise, skip directly to Step 1 with the existing prompt unchanged.

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
   - Research files (`.craft/research/`): the anchor is the quoted `##` heading name (`-> "Convergence Points"`); read that section only

4. **Stale-anchor handling during injection (MANDATORY):** If a cited anchor cannot be resolved (section heading no longer exists, line range out of bounds, Pattern N missing from locked.md), do NOT silently omit. Before spawning the Explore agent, ask on a question card (Read `question-card.md`, a sibling of this file) whether the story may have been written against an older version of that file. Three outcomes, each written on the card as what happens:
   - **Skip this citation** - alignment-check proceeds with the resolved citations only; this citation's content never reaches the agent.
   - **Re-run story creation from planning** - alignment-check exits with the instruction to re-run `/craft:story-new` From planning to refresh the citations; the check runs again afterward.
   - **Retry with an anchor the user types** - capture the correct section, subheading or range, retry the Read, continue.

4a. **Decision records (pointer, not extraction).** For each slug in the story's `decisions:` frontmatter list, add the path `.craft/decisions/approved/<slug>.md` (under the project root) to a DECISION RECORDS list in the agent prompt, followed by this sentence verbatim: "Read the Decision and Consequences of each record above before investigating. What they rule is settled - never surface it as a question. If the story or the codebase contradicts a ruling, or two rulings contradict each other, report it as a CONFLICT naming the record." Then add this sentence verbatim: "Two exceptions resolve without a question: when two records disagree, the newer record's Decision is the truth and the older is cited as superseded; and a record whose frontmatter reads `disposition: crafted` is frozen law - never propose reopening it, since a changed mind against frozen law is a new record." Records are not Reference Materials: they never enter the Planning Context block or its token cap, and step 3's anchor-type list gains no entry for them. A slug that does not resolve to a file in `approved/` is listed anyway with "(not found)" after it - the agent reports it - and this does NOT raise the stale-anchor question from step 4, which applies to Reference Materials anchors only. The list holds the story's own records and no others: the orchestrator never adds records from the store by tag, by topic, or by judged relevance, and never names records the story does not carry anywhere in the prompt. Then add this sentence verbatim: "Any decision record not listed above is NOT LAW for this story - it is history. Do not read one as a constraint, and do not report one as a CONFLICT."

5. Concatenate resolved excerpts into the Planning Context block.

6. **Hard 2000-token cap.** If excerpts would exceed 2000 tokens, prioritize in this order and drop lowest-priority until under cap:
   1. active.md dated entries (highest authority - current state)
   2. Concept Locked Decisions sections
   3. Sibling story precedents and research findings (`.craft/research/` citations)
   4. Mockups (visual contracts, less critical for product-question evaluation)
   
   If citations are dropped, note this in the Planning Context block so the agent knows content was elided.

**Format of the Planning Context block (Reference Materials only - decision records travel as paths, see 4a):**

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

    [STORIES CARRYING REFERENCE MATERIALS - include the Planning Context block built in Step 0.5 here, BEFORE the Investigate instructions:]
    [PLANNING CONTEXT block from Step 0.5 - Reference Materials only]

    [STORIES CARRYING DECISION RECORDS - include the DECISION RECORDS list from Step 0.5 item 4a here, with its verbatim sentence:]
    DECISION RECORDS:
    [one path per line, "(not found)" appended where the slug did not resolve]
    Read the Decision and Consequences of each record above before investigating. What they rule is settled - never surface it as a question. If the story or the codebase contradicts a ruling, or two rulings contradict each other, report it as a CONFLICT naming the record.
    Any decision record not listed above is NOT LAW for this story - it is history. Do not read one as a constraint, and do not report one as a CONFLICT.

    **When evaluating whether the story specifies a product question, FIRST check the Planning Context above (if present). Decisions captured in planning are NOT product questions - do NOT surface them. If the Planning Context note says citations were dropped due to token cap, you may flag a CONCERN that some planning content wasn't injected - the user can address by re-running with narrower Reference Materials. Research findings are evidence, not law: one that contradicts the spark, a locked pattern or a concept decision is reported as a CONFLICT, never applied silently.**

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

**A synchronous spawn's result does not expose the agent's address - you receive only the findings.** The description you typed is NOT an address - a send to the name fails. Follow-up rounds therefore re-spawn a seeded investigator (Step 4); never attempt SendMessage without an ID you can actually see.

**Do not proceed to Step 2 until you have the Explore agent's findings in hand.**

### Step 2: Filter - What Actually Deserves to Interrupt the User

This is the most important step, and the gate's whole quality lives here. A question card is for disambiguation between multiple legitimate paths - not for narrating what you found, not for permission, not for caution. Most codebase observations are NOT product questions; they are facts you act on.

**Surface a finding ONLY if BOTH are true:**
1. There are multiple legitimate paths and only the user can choose between them (a real fork in intent, not in mechanism).
2. The plan would be meaningfully worse if you decided it yourself and moved on.

**If either fails, do NOT surface it. Decide it and let the user veto later.** A fact ("there's no CLI to wire into - `index.js` is a library") is not a fork; you just don't wire a CLI that isn't there. An engineering call (test structure, key order) is yours. The bar is agent-judgment-plus-veto, not agent-question-plus-guidance.

**"Only the user can decide" means the CHOICE is theirs - not that you have no opinion on it.** When a finding DOES pass this filter, you still bring your recommendation to it. Restraint decides *whether* to ask; it never means going neutral once you do. Every surfaced fork ends on your lean and the card marks it `(proposed)` with `My pick is` (Step 3) - "here's what I'd do, your call," never a menu with no pointer.

**The removal test:** for each candidate, ask "if I delete this question, is the plan actually worse?" If not, it was overhead - cut it. (After the third or fourth question a user stops reading and starts clicking; every needless one spends that budget.)

**A finding already ruled in the story's `## Alignment` section is settled; it is never asked again.** A re-run after a dead session skips what the user already answered.

**Collapse before you surface.** Two findings that share one underlying decision are ONE question. "warn already exists" and "the CLI it names doesn't" are not two forks - they are one: "your premise is already built; what is this story now?" Fold the second into the first's options; never ask it twice.

### Step 3: Surface Gaps on Question Cards

**Before writing the question cards**, Read `agent-finding-handoff.md` (in this same directory - resolve it against the absolute path you just Read this file from) and apply the Self-Contained Test to each finding the Explore agent surfaced. The user does NOT have the Explore agent's codebase-research context. A finding that names a file path, function, locked-decision number, or pattern identifier without semantic context will force the user to re-investigate what the finding means before answering. Expand identifiers per the Translation Table in that file, then write the cards with expanded content.

**Then Read `question-card.md`** (a sibling of this file, resolved the same way) and ask each surviving finding on a card. Its examples show a fork (weighing live alternatives) and a dead end (the story's premise is already built; the options are what the story becomes).

**Settled list.** Before Question 1, print the findings Step 2 decided without asking under the heading `Settled without asking - say which to reopen`, as the reference describes. If none, omit it.

**One finding per card, sequenced.** Ask one card and write its answer before the next card renders - an answer often changes what the next question should be (that reassessment is Step 4). Never stack multiple decisions into one card.

**Answer-time write.** After each answered card, append that ruling's receipt line (type, the finding in one line, the ruling) to the story's `## Alignment` section under this run's `_Checked: <date>_` block, apply any `## Scope` or `## Decisions` edit the ruling implies, then print the read-back. The run's first write creates the section or block; later writes and Step 6 append to the same block, so one run makes one block. The ruling survives a session that dies mid-check, and `alignment: complete` is still set only at Step 6.

### Step 4: Reassess After Answers

After the user answers:

**Check if answers expanded scope:**
- Did the user say "yes, apply that everywhere"?
- Did the user add new requirements?
- Did the user reveal something the story didn't capture?

**If scope expanded:**

Spawn a fresh Explore agent seeded with the original findings and what changed - and say so in one line:

```
Agent tool:
  subagent_type: "Explore"
  description: "Scope-expansion follow-up for [story name]"
  prompt: "A prior investigation of this codebase reported these findings:
    [paste the findings report]

    The user's answers changed the scope:
    [Summarize what the user decided]

    Investigate ONLY the implications of the change:
    - What additional files does this touch?
    - Any new conflicts or adjacencies from the expanded scope?
    - Does this create any new product questions?

    Same report format. Only report NEW findings - don't repeat the prior ones."
```

(A same-agent SendMessage would preserve the investigation context and is preferred whenever a visible agent ID is genuinely in hand - background spawns surface one - but a synchronous spawn exposes no address. Never guess at an address; a send to the description name fails.)

Process the new findings (Step 2) and ask any new product questions on cards (Step 3). Findings decided without asking print before the next card under the same `Settled without asking - say which to reopen` heading; a card already asked is never among them.

**If scope grew significantly** (story went from touching 3 files to 8+, or now spans two distinct concerns):

> "Based on your answers, this story grew from [original scope] to [new scope]. I'd suggest splitting:"
>
> "- **This story:** [focused scope A]"
> "- **New story:** [focused scope B]"
>
> "Split or keep as one?"

Ask it on a question card, with split and keep as the outcomes. If splitting, create the new story file and adjust the current story's scope.

### Step 5: Confirm Alignment

The loop exits when:
- All product questions from the investigation have been asked and answered
- No new findings emerged from the latest round
- Scope changes (if any) have been confirmed

**You do NOT need explicit confirmation from the user that alignment is complete.** The loop is complete when you have no more product questions to ask. The confidence is earned through the dialogue, not declared.

### Step 6: Update Story

After the loop completes:

1. Add the `## Alignment` section to the story if the run has not yet created it (Step 3 writes rulings as they are answered) - the receipt that the check ran:
   - `_Checked: YYYY-MM-DD_`
   - One line per finding: type, what it was, how the user resolved it (rulings already written at answer time are not written twice)
   - If the investigation found nothing: `No findings - investigation returned clean.`
   - A fact settled in the research step: `- OUTSIDE FACT: <fact> - <source>`
   - On a re-run, append a new `_Checked: <date>_` block under the existing `## Alignment` section instead of adding a second section
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

Ask it on a question card (Read `question-card.md`, a sibling of this file) with two outcomes:
- Run the alignment check first - the orchestrator runs the alignment loop per story before launching agents
- Proceed with best judgment - agents plan without alignment check, but flag assumptions in their output for the user to review during triage

The outside-world check runs only inside the interactive loop; "Proceed with best judgment" skips it with the rest, and the planner's research request is the backstop.

## What This Is NOT

- Not a code review (that's pr-reviewer-expert)
- Not a technical feasibility check (the orchestrator handles that during engineering)
- Not a checklist to rubber-stamp (it's an investigation that may find nothing)
- Not a blocker if the codebase is empty/new (no existing code = no conflicts to surface)

If the investigation reveals zero product questions, that's a valid outcome. Write the `## Alignment` receipt (`No findings - investigation returned clean.`), set `alignment: complete`, and move on. The check is fast when there's nothing to find.
