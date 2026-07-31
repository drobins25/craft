---
name: mockup
description: "Live HTML mockup funnel - 3 options, converge by reacting, graduate to tweak/story/todo."
when_to_use: |
  Use on an explicit ask to mock something up or see visual options live
  ('mock up X', 'create a mockup for X', 'show me options for X'). Unsettled
  direction is the point - if the look is already decided, route to tweak or
  story instead. Not for non-visual uncertainty. On invoke, seed the brief
  from the session context.
argument-hint: "[what to mock up]"
---

# Mockup

A persistent alchemist builds 3 genuinely different live HTML options of a visual/interaction idea. You converge by reacting - diverge, refine, polish - new design values solidify to tokens.yaml at acceptance, and the converged mockup graduates on your choice: an immediate tweak, a story, or a parked notebook todo.

This shell owns only routing. The funnel lives in one reference file.

## Flow

### Step 1: Parse the subject

**If args provided:** the args are the subject - what to mock up.

**If no args:** take the subject from the session context (the conversation that led here names it). If nothing in context names a visual subject, ask conversationally - "What are we mocking up?" - no AskUserQuestion; the flow's question budget belongs to the funnel.

### Step 2: Single-session guard

One mockup session at a time. Check for an open one:

```bash
grep -l "^status: converging" "${CRAFT_PROJECT_ROOT:-.}"/.craft/mockups/*/record.md 2>/dev/null
```

If a record with `status: converging` exists, DECLINE the new invocation and point at the open record: name its path and offer to resume it instead. Converged/parked records don't block - only an actively converging one.

### Step 3: Run the funnel

Read `${CLAUDE_PLUGIN_ROOT}/commands/references/mockup-inline.md` and execute it inline, from Step 1 (Brief), with the subject and session context in hand.

**Never invoke the funnel via the Skill tool** - a Skill-tool call ends the turn and control never comes back for the next round; inline execution is the contract (see .claude/rules/skill-invocation-chain-breaks.md).
