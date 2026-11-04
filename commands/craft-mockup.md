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

### Step 2: Open mockups

A mockup left open by an earlier session never blocks a new one: nothing of it is still running, since its pin listener ends with that session and its alchemist is re-anchored from the record on resume. Only the mockup this conversation is running keeps a new one waiting, because its pin listener, browser tab and round tasks cannot be shared with a second.

Find the project folder first - `$CRAFT_PROJECT_ROOT` when it is set, else the folder this prints: `bash -c 'source "$1" >/dev/null 2>&1; craft_before_init_root' _ "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/find-workshop.sh"` - so a mockup started before `/craft:init` is not missed. Then list the open ones:

```bash
grep -l "^status: converging" "<project folder>"/.craft/mockups/*/record.md 2>/dev/null
```

- **One of them is the mockup this conversation is running** (this conversation ran its funnel, so its record path is already in hand): say so in one line and offer three ways on - finish it, abandon it, or start the new mockup in a fresh session, where this one will not block it. Start nothing until the user picks.
- **Otherwise:** every open mockup was left by an earlier session. In one line, before the funnel starts, name the newest by its folder name and add `, and <m> more` when there are others: "There's a mockup still open from before - <name><, and <m> more>. Ask to resume or abandon it by name any time; starting the new one now." Say it once per conversation, never as a widget, then continue to Step 3. Resuming one re-anchors it from its record, as the funnel's Recovery describes, never a new Brief; abandoning one runs the funnel's abandon on that record.

Converged and parked records are not open mockups and are never named here.

### Step 3: Run the funnel

Read `${CLAUDE_PLUGIN_ROOT}/commands/references/mockup-inline.md` and execute it inline, from Step 1 (Brief), with the subject and session context in hand.

**Never invoke the funnel via the Skill tool** - a Skill-tool call ends the turn and control never comes back for the next round; inline execution is the contract (see .claude/rules/skill-invocation-chain-breaks.md).
