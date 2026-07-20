# The Muse Path (reference - read on demand by the mockup funnel)

Read-and-follow: the mockup funnel (commands/references/mockup-inline.md) reads this file at one of its two doors - the user picks "Let's ask the muse" on the vibe question (warm project), or the design-empty fork routes here automatically (NEITHER tokens.yaml NOR locked.md exists). When a door fires, Read this file once, follow it top to bottom, then rejoin the funnel where noted. Runs that never enter a door never read this file - that is the point of it living here and not inline.

This path replaces silent brief enrichment: the muse briefs AND asks its own authored question. The user sees and steers the muse's work on every use.

## 1. Spawn the muse (one-shot)

Invoke the muse ONCE via Task, reusing creative-spark's interrogation prompt shape (skills/creative-spark/SKILL.md, Muse Invocation):

```
Task tool:
  subagent_type: "craft:muse"
  description: "Brief + author vibe stances"
  prompt: |
    ## Brief

    You are briefing a live mockup BEFORE any option is built.
    Your job: find the emotional job underneath the request, then author
    2-3 candidate design directions the user can pick between.
    Do NOT build anything. Return the briefing and stances only.

    ## Subject

    [the mockup subject + the user's request verbatim + session context
     + the loaded constraints when any exist]

    ## Return Format

    **Stated Problem:** [what the request literally asks for]
    **Underlying Emotional Job:** [what the user actually needs to FEEL]
    **Mechanic That Carries Feeling:** [what interaction creates the emotional resonance]

    ## Constraints for Option Generation
    - Prioritize: [emotional dimension to emphasize]
    - Avoid: [emotional traps to sidestep]
    - The feeling this needs to produce: [one sentence]

    ## Candidate Directions

    [2-3 stances. REGISTER REQUIREMENT: this is Craft UX, we are building
    mockups: every stance must fuse a CONCRETE, BUILDABLE design direction
    (what's on screen, how it's arranged, how it moves) with the feeling it
    produces. A stance a designer could start sketching from immediately.
    No free-floating poetry, no abstractions that don't name visible form.
    Each stance ships widget-ready:
    - label = the visible mechanic, plain and concrete
      (e.g. "Sparkline draws in, number ticks up")
    - description = additive footnote: "feeling: [what it produces].
      trade: [what it costs]"
      (e.g. "feeling: alive, continuous. trade: drama on a static fact")
    Genuinely different leans, not synonyms.]

    ## Rules
    - Return the briefing and stances only. Do not build, do not generate wireframes.
    - Do not do additional file research beyond what's provided.
    - Be direct and opinionated. Name what you see.
```

**Stamp `muse_session:` in record.md at spawn** - it records a completed one-shot artifact and is NEVER a re-anchor target (recovery re-anchors live agents against `agent_session` only and reads `muse_session` as a no-op). If the runtime exposes no agentId, stamp `""` and move on.

## 2. Write the briefing before any widget

The moment the briefing returns, write it to record.md `## Brief` - BEFORE any widget renders. A broken session never loses the muse's work, and a muse that succeeded never re-runs.

## 3. Parse-guard (checklist - every check must pass before the stances render)

1. **Count:** 2-3 stances came back.
2. **Trade:** each stance's description names an honest trade.
3. **Distinctness:** no stance is a rewording of another - different lean, not a synonym.

Never fail a stance for brevity.

**Failure handling:** on a dead spawn (the Task call errors or returns nothing parseable - the call is synchronous, so a bad return IS the failure signal) or any failed check, re-spawn the muse ONCE with the same prompt - the same fresh-agent recovery pattern the funnel uses for the alchemist. If the retry also fails, say so in one plain line - "The muse isn't answering - name the vibe yourself, or we stop here" - and proceed from whatever the user types. No alternate direction-generation prompt exists; the muse's job is never done by the orchestrator. The funnel never stalls - the escape hatch is the user's own words, already a first-class path.

## 4. The authored widget

Quote 2-3 vivid verbatim briefing lines in prose first, prefixed "Muse's take: ..." - pull the vivid lines (Underlying Emotional Job / Mechanic That Carries Feeling), prose only. Then render the muse's stances as the vibe AskUserQuestion, lifted VERBATIM - the orchestrator authors nothing, compresses nothing; labels and descriptions are the muse's own words. Free text arrives via the widget's built-in Other.

**The budget reading (owner-confirmed 2026-07-20):** the muse's authored question IS the vibe checkpoint, asked in the muse's voice - it replaces the vibe answer, it is not a fourth taste AUQ. The three-AUQ budget in mockup-inline.md counts taste checkpoints, not widget renders; on the warm door the router pick and the muse's follow-up are one checkpoint. Never "fix" a two-widget vibe beat by collapsing the muse back into silent enrichment - that is the failure this path exists to remove.

## 5. Assemble the brief and rejoin

The brief to the alchemist = the full muse briefing + the chosen/typed stance verbatim + the loaded constraints + the mobile verdict. Rejoin the funnel at the task rail (mockup-inline.md Step 1 creates it after the brief write): the muse path is a Brief substep - no new task, no rail entry.
