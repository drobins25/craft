# Creative Workshop

> How to use the muse/alchemist/driver pattern in creative-spark to get options that feel like something, not just options that work.

This is a how-to guide. You're in the middle of creating a story or working in the Creative Phase and you want to understand what the Creative Driver step offers and when it's worth using.

---

## The Problem It Solves

Standard creative-spark generates options by analyzing your story context and producing 2-3 approaches with trade-offs. That works well for most things.

But some features need a different entry point. A stats summary screen is technically a data display problem. It's also a moment where someone finds out something about themselves. If you start from the data-display framing, you get good layouts. If you start from the identity-moment framing, you might get something users screenshot and share.

The Creative Driver step (Step 1.5 in creative-spark) offers a choice: generate options directly, or consult an interrogator agent first.

---

## The Three Driver Options

### Standard (default)

Analyze the story and generate options. No agent invocation. This is the existing behavior, unchanged. Use it for:
- Implementation-focused stories where the creative question is "how do we build this"
- Stories with clear design constraints (design tokens set, visual direction locked)
- When you're in a flow state and don't want to break for interrogation

### Muse

The `muse` agent reads your story and returns a structured briefing on the emotional job underneath the feature request. It doesn't generate options. It answers:

- What is the user actually trying to FEEL, beneath what the story literally asks for?
- What mechanic would carry that feeling - not describe it, but create it?
- Will anyone tell their friend about this? What would they say?

The briefing feeds into Step 2 (Reframe and Find the Tension) as an enriched constraint set. Creative-spark still generates all options - muse just makes the options sharper.

Use muse when:
- You're building something user-facing that has an emotional dimension
- The story request is functional but you suspect there's a deeper hook to find
- You've been burned by features that worked perfectly but nobody cared about

### Alchemist

The `alchemist` agent reads your story and returns a structured briefing on the physical metaphor and interaction vocabulary for the feature. It answers:

- What does this feature weigh? What real-world object does it behave like?
- How does it appear, rest, and exit? (Entry physics, resting behavior, exit physics)
- What easing personality fits? (ease-out = responsive, spring = alive, linear = mechanical)
- What runs on the compositor thread vs what requires layout recalculation?
- What's the reduced-motion alternative?

Use alchemist when:
- The feature involves animation, transition, or spatial interaction
- You want the motion to feel intentional, not decorative
- You're building something where the interaction IS the product

### Full Workshop

Both agents run in parallel. Their briefings are combined before Step 2. The muse establishes what the feature needs to FEEL like. The alchemist establishes what it needs to MOVE like. Options generated in Full Workshop mode have a shared language - emotional resonance and physical vocabulary aligned before the first option is written.

Use Full Workshop when:
- You're designing something novel that doesn't have a reference pattern
- The feature carries both emotional weight and interactive complexity
- You're in discovery mode and want maximum signal before committing to a direction

---

## What the Briefings Look Like

### Muse briefing format

```
Stated Problem: [what the story literally asks for]
Underlying Emotional Job: [what the user actually needs to FEEL]
Mechanic That Carries Feeling: [what interaction creates the emotional resonance]
Identity Attachment: [will users extend self into this feature? why/why not]
Word-of-Mouth Test: [would someone describe this to a friend? what would they say?]

Constraints for Option Generation:
- Prioritize: [emotional dimension to emphasize]
- Avoid: [emotional traps to sidestep]
- The feeling this needs to produce: [one sentence]
```

### Alchemist briefing format

```
Physical Metaphor: [what does this feature weigh? what real-world object does it behave like?]
Entry Physics: [how does it appear? slide/emerge/bloom/snap]
Resting Behavior: [static/breathing/ambient pulse/reactive]
Exit Physics: [how does it leave? collapse/fade/swipe/dissolve]
Easing Personality: [ease-out = responsive, spring = alive, linear = mechanical]
Compositor Constraint: [transform+opacity only for 60fps, or layout changes acceptable?]
Reduced Motion Alternative: [how to adapt for vestibular safety]

Constraints for Option Generation:
- Prioritize: [interaction dimension to emphasize]
- Avoid: [performance landmines or physics contradicting the feature's personality]
- Cross-domain inspiration: [what physical system from the real world does this mirror?]
```

---

## The Agents Are Interrogators, Not Generators

This is important: muse and alchemist do NOT generate your creative options. They enrich the brief that creative-spark uses to generate options. Creative-spark still produces the 2-3 options with trade-offs and visual direction.

The purpose of the interrogation is to catch the question you weren't asking. A muse briefing might reveal that users aren't asking for a dashboard - they're asking to feel in control. That reframe doesn't change the options list dramatically, but it changes which dimension each option optimizes for, and it changes how you evaluate which option to pick.

---

## Continuation After Interrogation

When Muse or Alchemist (or both) run, creative-spark writes a breadcrumb before invoking them. After the agent returns, the breadcrumb is cleaned up and the enriched brief is passed to Step 2. This prevents the orchestrator from stopping after the agent returns.

You don't need to do anything. The breadcrumb pattern is handled automatically.

---

## Example: Stats Summary Screen

**Without driver:** Creative-spark analyzes the story ("show weekly stats summary") and generates options: minimal card, detailed breakdown, chart-focused.

**With Muse:** Muse reads the story and returns: "Underlying job is identity confirmation - the user wants evidence they're the kind of person who shows up. The mechanic that carries this is making them the protagonist of the data, not a viewer of it. Word-of-mouth test: users will screenshot this if it tells a story about WHO THEY ARE, not what they tracked."

Creative-spark now generates options where one is a Spotify Wrapped-style narrative, one is a minimal personal record (your best week ever), and one is a streak-focused view. Different options than the layout-first framing. Better options for what the user actually needs.

---

## Consulting Muse and Alchemist Outside creative-spark

Both agents are available for direct consultation via `/craft:ask`. You don't have to be in creative-spark to get their perspective.

```
/craft:ask "Will anyone care about this notification feature?"
→ Routes to muse

/craft:ask "Should I use Framer Motion or CSS for this card flip?"
→ Routes to alchemist
```

`/craft:ask` reads your question, scans agent descriptions, and recommends the best match. It shows its reasoning ("This sounds like a muse question - you're asking about emotional resonance, not implementation") before routing.

---

*For agent implementation details, see `agents/muse.md` and `agents/alchemist.md`. For the full creative-spark flow, see `skills/creative-spark/SKILL.md`.*
