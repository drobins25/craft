---
name: riff
description: "Calibrate thinking one question at a time - a main-loop conversation, one plain-prose question per turn, until the direction lands. Bare invocation opens from the oldest open notebook idea."
when_to_use: |
  Explicit: the user says "riff on this", "can we riff", "help me think
  through", "let's work through this", "I'm stuck on", "I'm torn
  between", "talk me through this", "one question at a time" - or invokes /craft:riff.
  Also: a bare undecided direction ("let's design X" where the premise
  would have to be invented before options could exist) - riff first,
  options after. Engage directly, no offer.

  Self-catch (proactive): when you are about to send a turn that says
  a lot at once about an undecided direction - 2+ questions is the
  clearest tell, but a wall of options or analysis counts the same -
  ship it as written, then APPEND one trailing ignorable offer line
  ("I just said a lot at once - let me know if you'd rather riff
  through this") - never AskUserQuestion, main loop only, never
  inside another flow's gate. Decline or silence = drop it for this wall;
  the offer may return on a later overloaded turn.

  Not for: fact-shaped question runs (those stay AUQ), a quick run of
  value questions with the direction already implied (answer them, or
  dial), direction already clear (story/adhoc), or "just tell me the
  answer" asks.
argument-hint: "[what you want to think through] or empty"
---

# Riff

A thinking conversation in the main loop. One question at a time, until the direction lands.

## The spine

In a riff, you hold one thing at a time - and it's always the decision. I carry everything else: the agenda, the reasoning, the stakes, the ledger of what's settled. When the evidence has a stance in it, I bring it stated. When your finding-it is the point, I hold my lean back on purpose and ask the real question instead - a withheld lean is still mine to carry, never yours to miss. You never hold the administration of the conversation, and you never hold two things at once.

If a new situation doesn't fit a corollary below, ask which one is carrying it - don't add a rule that isn't a consequence of the spine.

## Corollaries

Every rule here is a consequence of the spine.

**One question per turn.** Ask exactly one question, in plain prose, then stop and wait for the answer. Never a numbered question list, never "a few things I'm wondering", never an AUQ chip as a substitute for the conversation - the user is never handed two things to hold.

**Questions never arrive naked.** Every question says what hangs on the answer. When the evidence has given you a lean, state it - "my lean: X, because Y". When it hasn't, don't invent one: a manufactured recommendation is the same failure as a bare question.

**Pull mode - the withheld lean.** When the user's own finding-it is the point, deliberately hold a formable lean back and ask the real question instead. Go light - no stakes recital - until something firms. The withheld lean is still yours to carry, never theirs to miss.

**Receipt beat.** Close each settled answer in one short human line before the next question - "Okay, X then", "Going with X", or folded into the next question's setup. "Locked: X." is one valid form, never a required stamp. Mid-conversation only - the ending stays ceremony-free.

**Wall is context, not an agenda.** When riff enters from an accepted self-catch offer, the wall of questions that triggered it is context, not a checklist. Open with the one question that most unlocks the direction, and let every next question grow from the answer. When an answer invalidates the rest of the wall or its premise, follow the answer and let the wall go - the abandoned agenda is yours to drop, never the user's to finish.

## Opening the session

**With a topic** - an argument, or a conversational trigger like "can we riff on this": riff on the named subject. Do not run the notebook helper; the seeding below fires ONLY on bare invocation.

**Bare invocation** - `/craft:riff` with no arguments: open from the dustiest open idea. Run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/notebook-list.sh ideas
```

The helper emits open ideas only, oldest first. Take the FIRST emitted record block, Read the file at its `FILE` field, and open the session with a single question about that idea that connects it to what has changed since it was captured - active cycle, recent shipping, whatever the session context offers. The question IS the opener: no preamble, no menu. Riff reads idea files, never writes them - status changes belong to the notebook flows.

**If the helper output is empty** - no open ideas, or no notebook at all: that is a branch, not an error. Ask what is on the user's mind. No error message, no init push.

## Ending the session

Riff sessions end as pure conversation - no landing ceremony, no closing offer, no capture step. If the riff produced something actionable or deferrable, the orchestration index's existing grammar catches the user's next utterance (story, adhoc, notebook, mockup); riff adds nothing in between.

## Offers

At most one inline offer per turn, ever - riff's offer never stacks on notebook, creative-spark, or design-vibe offers. The user never gets two nudges in one breath.
