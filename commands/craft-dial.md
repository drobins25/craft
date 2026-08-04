---
name: dial
description: "Live value calibration - 2-4 lettered candidates injected into the running app; click through them against real data, nothing written to source."
when_to_use: |
  Use when a visual question can only be settled on the real page: the surface
  already renders in a browser, there is a bounded set of candidates (2-4
  amounts of one property, or 2-4 treatments of one goal), and the answer
  depends on real neighbors, real data, real viewport. Strongest tell:
  adjectives are being traded ("too loose", "reads too quiet"). Not for
  surfaces that don't exist yet (mockup), values already decided ("make it 24"
  - tweak, permanently), open-ended redesigns (mockup or creative-spark), a
  single candidate (that's a screenshot), or anything non-visual.
argument-hint: "[what to dial]"
---

# Dial

Settle a visual question on a surface that already renders, by putting the candidates on the real page instead of describing them. Craft measures the live surface, injects 2-4 lettered positions plus a small control panel, and you click through A/B/C in your own browser - against real data, real neighbors, real viewport. Nothing is ever written to source; a refresh discards everything. Every session files a record, including the ones where the current value wins.

This shell owns only routing. The flow lives in one reference file.

## Flow

### Step 1: Parse the subject

**If args provided:** the args are the subject - what to dial, on which surface.

**If no args:** take the subject from the session context (the conversation that led here names it). If nothing in context names a visual question with a bounded candidate set, ask conversationally - "What are we dialing, and on which surface?" - no AskUserQuestion, never; the flow asks nothing through widgets end to end.

### Step 2: Degradation preflight

Establish which rung this session runs on before opening anything. The ladder is defined in the flow reference (Step 0 there); the short form: no reachable dev server and no discoverable way to start one means dial cannot run - say so plainly and stop. Runnable-but-not-running folds the server start into the flow's opening move, never a separate question.

### Step 3: Run the flow

Read `${CLAUDE_PLUGIN_ROOT}/commands/references/dial-inline.md` and execute it inline, from Step 0, with the subject and session context in hand.

**Never invoke the flow via the Skill tool** - a Skill-tool call ends the turn and control never comes back for the react loop and the four exits; inline execution is the contract (see .claude/rules/skill-invocation-chain-breaks.md).
