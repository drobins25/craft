---
name: riff
description: "Two-gear thinking partner. Senses HOW to think-with you in the moment - runs a tight calibration loop in the main loop, or hands open exploration to the Riff agent - with notebook-grade restraint: ignorable inline offers, never naggy, silence by default."
when_to_use: |
  Intent and direction aren't shared yet, and a real decision is coming - the user has
  a felt sense of where they're headed but can't name it. Use riff to close the gap
  before committing. Skip it when direction is already clear, the call is trivial, or
  the user is heads-down on a task.
argument-hint: "[what you want to think through] or empty"
---

# Riff

A two-gear thinking partner. This skill **senses and routes** - it reads the moment and either runs the tight calibration gear here in the main loop, hands the wide gear to the Riff agent, drops an ignorable offer, or stays quiet. The actual riffing craft - how to throw, pull, catch, dislocate, when silence is presence vs. abandonment, how to read an exhausted user - lives in `agents/riff.md` and is NOT re-specified here.

<!--
GUARD: This skill is a thin sensor/router. It owns only the orchestrator-level
concern the agent lacks: WHEN riff engages or is offered from the main loop
(focus gate, presignal offer, nag floor, silence). It must NEVER re-document
throw/pull/catch/dislocate, the silence-vs-abandonment read, or the
exhausted-user floor - all of that is the agent's (agents/riff.md, Section 3 +
Operating notes). Any bullet here that starts describing HOW to riff belongs in
the agent, not this file.
-->

## Project Root

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`. All `.craft/` paths resolve under this root.

## How to route

The `when_to_use` block above does the sensing. Once you have read the moment, take exactly one of these four routes. Do nothing else - this skill adds no ceremony.

### Wide gear -> hand to the Riff agent

Open, spacious exploration where no answer exists yet. Invoke the existing agent via the **Agent** tool (mirrors `commands/craft-ask.md` Step 5):

```
Agent tool:
  subagent_type: "craft:riff"
  description: "Riff: open exploration"
  prompt: |
    ## What we're riffing on

    {the user's framing, verbatim}

    ## Project context

    {1-3 lines: active story/cycle, the work in front of us, the mood}

    ## Instructions

    Riff with them. Draw on your gears and your restraint. The work is
    theirs - state what you see, hold your taste, never weaponize it.
```

Follow-ups continue the SAME agent conversation via **SendMessage** (preserves the agent's context across turns) - do not spawn a fresh agent per turn.

### Tight gear -> run the calibration loop in the main loop

A tacit boundary needs to become explicit. Do NOT spawn the agent - the flip-loop is the orchestrator's move, run here in the main conversation:

1. `Read reference/calibration-loop.md`.
2. Run the loop as documented: one concrete instance per AskUserQuestion, a fixed yes/no/unsure verdict, state the inferred principle after each verdict, adapt the next probe toward an unexplored seam.
3. Stop when the principle stabilizes; write the converged rule down where it belongs (the story/spec/decision the boundary was blocking).

### Presignal -> help, then offer once

A soft in-flow creative texture where the user is engaged with you, not asking to step out. Help as you always would in this turn, THEN append exactly ONE ignorable inline offer line, notebook-style:

> "... or if you want to go deeper we could riff on it. Otherwise I'll continue."

NOT AskUserQuestion. On accept, pick the gear (tight if a boundary is forming, wide if it wants space). If the offer is ignored, the work flows on - never repeat it.

### Silence -> say nothing

No signal, or the FOCUS GATE suppressed it (user is heads-down - a future-leaning spark routes to `/craft:notebook`, not riff), or it's below the FLOOR (a micro choice the user wants answered fast). Just help. Say nothing about riff.

## One offer at a time

Riff's presignal offer must never stack on top of notebook, creative-spark, or design-vibe offers. The rule: **at most one inline offer per turn.** If another skill has already dropped an inline offer this turn, riff stays silent. The user never gets two nudges in one breath - that is the nag that kills the pattern.

## Riff skill vs. Riff agent

- **This skill** (`commands/craft-riff.md`) is the sensor/router: focus gate, gear-sensing, the presignal offer, the nag floor, silence. It runs the tight gear itself and hands the wide gear off.
- **The agent** (`agents/riff.md`) is the crystallized partner that does the actual riffing. It is the wide-gear destination and is unchanged by this skill.
- **The calibration loop** (`reference/calibration-loop.md`) is a standalone reusable technique the tight gear invokes - not riff-specific, also available to content-spark / design-vibe / lock-decision.
- **Hunch settling** (`reference/hunch-settling.md`) is the second shared technique distilled from the agent's throw/pull craft - the executable-threshold gate the mockup funnel runs on round reactions (consumed inline by `commands/references/mockup-inline.md`); same contract as the calibration loop: it distills, `agents/riff.md` stays canonical.

<!--
ACCEPTANCE RUBRIC (the 6 calibration lenses - do not weaken on future edits).
The when_to_use must resolve each to the verdict shown:
  1. "Can't give you the rule, but show me cases and I'll know each" -> TIGHT GEAR, engage
  2. "Blank canvas, no idea what this should be, let's wander" -> WIDE GEAR, hand to agent
  3. "Three rough directions sketched, which feels right?" -> grey: help + OFFER riff, don't auto-fire
  4. "Just think out loud with me on this tradeoff" -> PRESIGNAL: help + ignorable woven offer
  5. mid-debugging, "the onboarding could be special someday" -> FOCUS GATE suppresses; route to notebook
  6. moving fast, "primary or secondary button color?" -> FLOOR: just answer, no riff mention
-->
