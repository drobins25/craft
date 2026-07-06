# Mockup Funnel (reference - read inline by the craft:mockup shell)

<!-- DO NOT SIMPLIFY THIS SCHEMA. Mockup records anchor agent recovery, graduation
     backlinks, and status surfacing. Every frontmatter field below is read by name
     somewhere (status, craft:status; agent_session, recovery; graduated_to, ramps).
     Verbatim reactions are the convergence history - paraphrasing destroys them. -->

A converged mockup is design truth the user approved in their browser. This flow gets there through three rounds of real reactions - diverge, refine, polish - then solidifies new design values to tokens.yaml BEFORE any destination artifact exists, so every downstream gate (binding contracts, chunk-validator, style-analyzer) enforces the mockup because the bible already agrees with it. The shell has already parsed the subject and run the single-session guard - this file owns everything else.

**Exactly three AskUserQuestion calls exist in this flow: vibe (Brief), solidify (acceptance), destination (fork).** Round picks and reactions are conversational text - a widget between the user and their taste kills the funnel. Never add a fourth.

All writes live under `.craft/` - the write gate never opens for a mockup.

## Step 1: Brief

Create the artifact folder and record first - it is the durable anchor for everything after:

```bash
mkdir -p "${CRAFT_PROJECT_ROOT:-.}/.craft/mockups/$(date +%Y-%m-%d)-[slug]/rounds"
```

Write `record.md` in the mockup folder:

```markdown
---
name: [YYYY-MM-DD-slug]
status: converging
created: [YYYY-MM-DD]
project: [project name]
agent_session: [filled when the alchemist spawns]
solidify_outcome: [filled at the solidify beat]
graduated_to: [filled at the destination fork]
---

## Brief
[vibe answer, constraints loaded, mobile verdict]

## Reactions
[verbatim, per round - filled as rounds close]

## New Values
[used-as-is / broken old->new / net-new - tracked as rounds introduce them]

## Polish Ledger
[currently-unsettled live injections ONLY - self-pruning, normally empty
 outside an active polish loop; each line: target selector + exact change]
```

Then assemble the brief:

1. **Load the constraints** - `.craft/design/tokens.yaml` and `.craft/design/locked.md` (which carries any design-vibe soul statement). These are think-with, not bible: deliberate breaks are licensed, announced when crossed, and tracked toward `## New Values` for the solidify beat.
2. **Detect mobile - never ask.** Breakpoints in tokens.yaml, media queries in existing components, project.md signals. When detected, every option in every round ships a mobile layout, and verification covers both viewports.
3. **The vibe question** - the flow's first AskUserQuestion:

```
question: "What should this feel like? Name a vibe, an inspiration, a mood - it seeds how different the three options dare to be."
header: "Vibe"
options:
  - label: "[2-3 vibe directions inferred from the subject + session context]"
    description: "[one line each]"
  - label: "Include the muse"
    description: "Have the muse interrogate the emotional job first - its briefing becomes the divergence north star"
```

**If "Include the muse":** invoke the muse via Task (`subagent_type: "craft:muse"`) using creative-spark's interrogation prompt shape (skills/creative-spark/SKILL.md Step 1.6): pass the subject + session context, demand the structured briefing (Stated Problem / Underlying Emotional Job / Mechanic That Carries Feeling / Constraints for Option Generation), and forbid option generation. The briefing enriches the brief only - the muse never builds, and the budget stays three AUQs because this rides inside the vibe answer.

Write the brief (vibe answer, constraints, mobile verdict) into `## Brief`. Create the task rail - six TaskCreate tasks, blockedBy-chained in order: **Brief -> Diverge -> Refine -> Polish -> Save (mockup + solidify tokens) -> Choose destination**. Substeps never become tasks. Skipped rounds complete-with-note. Polish holds ONE task across all its attempts. The rail ENDS at Choose destination - destination flows create their own tasks. Mark Brief complete.

## Step 2: The Alchemist (spawned once)

Spawn the alchemist ONCE via the Agent tool (`subagent_type: "craft:alchemist"`), passing: the brief, the mockup folder path, the living-page rules below, and the round protocol. Write its agent id to record.md `agent_session` immediately. Every subsequent round is a SendMessage to that same agent - never a fresh spawn per round.

**Recovery (designed, not hoped):** if the agent dies or the session breaks mid-funnel, re-anchor a fresh agent from record.md (brief, reactions so far, `## New Values`, any pending `## Polish Ledger` lines) + the current mockup.html - NEVER from transcript continuity alone. Update `agent_session` to the new id. This is why the record is written before anything else exists.

**The living page:** the mockup is ONE page - `mockup.html`. Each round REPLACES its content, so the page only ever shows the current decision: all options at Diverge, the pick's variations at Refine, the finalist at Polish. Before each round transition, the outgoing round is archived to `rounds/round-N.html` (kept for resurrection, never rendered or linked); the new round is then EDITED into the living page, never rewritten from scratch. Presentation adapts to scope: component-scale options stack in real surrounding context (scroll to compare); page-scale options each fill the viewport behind a thin fixed top toggle bar (A/B/C). Toggle, replay buttons, and round label are visually distinct dev chrome - never part of the design, never ported.

**Verification is orchestrator-owned.** The alchemist builds and self-reports; reports never count as verification. After every handoff, the orchestrator loads the page and verifies in TEXT - console errors listed, one evaluate_script assertion pass (expected sections/ids present, body has height, option count matches the brief) - before pointing the user at it. Screenshots are NOT the verification medium when the user is watching a headed browser: the user's own screen is the display, and pixels are reserved for what they can't see - mobile emulation, unattended sessions (no visible browser) - or their explicit request (including disambiguating a reaction the DOM can't resolve from words).

## Step 3: Diverge (Round 1)

Brief the alchemist: 3 genuinely different options - stances, not variations - each embedded in real surface context, seeded by the vibe answer (or muse briefing) as the divergence axis. Verify, show the user, collect the reaction **conversationally** - which one pulls, what's wrong with the others, hybrids welcome.

Write the verbatim reaction to `## Reactions`. Mark Diverge complete. If the user's pick is already final-grade ("that's exactly it, don't touch it"), Refine and Polish may complete-with-note - acceptance still runs Step 5's beats.

## Step 4: Refine (Round 2)

The pick becomes the base; brief the alchemist with variations of it. Hybrids are legal briefs ("B with C's cards"). Same mechanics: archive the outgoing round, then EDIT the living page toward the new round - never a from-scratch rewrite; the surrounding context and base CSS that didn't change are not regenerated - then verify, show, collect the reaction conversationally, record verbatim. Mark Refine complete.

**Mid-round lock crossings (any round):** when a direction crosses a locked.md decision, say ONE ignorable line - "that crosses the [X] lock; trying it anyway - we'll settle the lock if this is what you accept" - and proceed. No question, no AUQ, no locked.md write mid-round. The lock settles once, at the solidify beat.

## Step 5: Polish (Round 3) - the live loop

The finalist iterates until explicit acceptance. This round runs differently: the ORCHESTRATOR drives micro-adjustments live via `evaluate_script` on the loaded page (CSS/style/class injection) - try/see/discard in seconds, the user watches the change land in their own browser and reacts, next adjustment. No per-injection screenshots - the user's screen is the display; pixels only for viewports they can't see or on request. The alchemist re-enters only for structural work (new sections, choreography), which follows the same archive-then-edit discipline as any round.

**Tell the user ONCE when the loop starts:** "Changes are live in the page only - don't refresh until they're written."

**The ledger discipline (never conversation memory):**
- **Inject** -> append one line to record.md `## Polish Ledger`: target selector + exact change
- **User keeps it** -> write mockup.html (one write per settled change - the file never churns through failed attempts), delete the ledger line
- **User discards it** -> delete the line, nothing written
- **Any refresh or recovery** -> re-inject every line still in the ledger, from the file

**Acceptance is explicit** - "that's it", "done", "ship it". Typed criticism loops another adjustment. On acceptance: write any remaining settled state, confirm the ledger is empty, record the verbatim acceptance in `## Reactions`, and proceed immediately to the solidify beat - it fires BEFORE the destination choice, always.

### The solidify beat (one AskUserQuestion)

Re-derive the payload from the FINAL accepted page - never from memory of the rounds: scan mockup.html's design values against tokens.yaml (new values, overridden values) and collect any locks crossed en route that the finalist still breaks. Update `## New Values` to match. Include only the questions with pending payload, in ONE AskUserQuestion:

```
question (if new/changed values): "This mockup introduced [values] - solidify to tokens.yaml?"
header: "Solidify"
options:
  - label: "Solidify"
    description: "Written now with provenance: '# Locked: [date] - from mockup [slug]'"
  - label: "Keep mockup-local"
    description: "tokens.yaml untouched; a story built from this will surface these as known drift"

question (if a crossed lock is unsettled): "The accepted mockup crosses the [X] lock - settle it?"
header: "Lock"
options:
  - label: "Update the lock"
    description: "Alter/remove [X] in locked.md to match - explicit yes, per the inline lock-edit rules"
  - label: "Conform the mockup"
    description: "Rework the finalist to respect the lock as written, then re-accept"
```

Lock edits follow the tweak flow's inline lock-edit rules (skills/adhoc/references/tweak.md): explicit yes only, edited in place in locked.md's existing format, at most ONE lock write per mockup, and no third door - a mockup never closes in a lock-breaking state. Write the outcome to `solidify_outcome` (a decline is recorded there too - values stay mockup-local, no silent drift). No payload -> skip the beat entirely, nothing asked.

Set `status: converged`. Mark Polish and Save complete.

## Step 6: Choose Destination (the flow's last act)

The third AskUserQuestion:

```
question: "The mockup is converged and saved. Where does it go?"
header: "Destination"
options:
  - label: "Tweak it in now"
    description: "Hand to craft:adhoc - direction is pre-settled, this is a port"
  - label: "Make it a story"
    description: "story-new's 'From mockup' source pre-fills the story from this record"
  - label: "Park it"
    description: "A notebook todo holds the pointer; pick it up whenever"
```

The fork records the graduation, writes BOTH backlinks - record.md `graduated_to:` + the destination artifact's `mockup:` field - updates `status` (`graduated-tweak` / `graduated-story` / `parked`), completes Choose destination, and ENDS. The destination flow (adhoc, story-new, notebook) runs as its own thread with its own tasks:

- **Tweak:** the handoff brief states "direction pre-settled, converged mockup at [path]" so adhoc's classification doesn't re-open exploration.
- **Story:** story-new's "From mockup" source (commands/references/story-from-mockup.md) does the pre-fill. The mockup's CSS is NORMATIVE there - ported, never reinterpreted.
- **Park:** capture a notebook todo naming the mockup path. Pickup = todo done, then re-enter THIS destination choice against the still-converged record. Graduating a long-parked mockup first re-verifies the target surface still exists as mocked - structural drift is surfaced before porting.

No choice ("Choose destination" pending) leaves the record converged and the task open - never nag; the record's openness is independent bookkeeping. An explicit drop ("abandon it") sets `status: abandoned` and completes the task with a note. Abandoned mockups stay on disk; cleanup is manual.
