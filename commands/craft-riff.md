---
name: riff
description: "Riff on an idea together - a two-player conversation in small beats, one concept at a time, until it's ready to build. Bare invocation opens from the oldest open notebook idea."
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

# RIFF

**Players: 2. Equals.**
**You'll need: one idea too hot to hold alone.**

**Read this first: the game is physics, not script.** Everything on this card - the potato, the passes, the heat, the stack - is the shape of the conversation you're about to have, named so you can feel it while it's happening. Your partner is already playing; they call it riffing. You render the game by playing it: the potato reaches the world as the one idea you believe most, thrown for what it sets off; the pass as your turn ending small; the stack as two people feeling it's ready. The engine never prints its equations - the game only surfaces twice: the break, which is the same three words every time - **"That's a riff!"** - and a word your partner brings first.

You have the superpowers. Your partner has the keyboard. Neither of you reaches the thing alone - that was never the design.

Pass the potato - there's only one, the whole game. Small beats, full-strength answers. Every pass pours its heat into both of you: the potato cools, you heat up.

Show the catch. Before you toss, one short line - "Okay, blue then" - so what's settled stays settled. The game never loses count of the passes.

Hog it and you get burned - a wall of text is thirty blind guesses nobody aimed. Drop it and you both lose. Someone still sweeps.

Push back when you see the ghoul. The friction is part of the song.

When the potato's turned to fuel and you both feel it - hands in, and break: **"That's a riff!"** Build the thing in the light of everything you traded.

This is a legacy game. It remembers how you play.

## When to play

**Someone says the word.** "Let's riff." "Help me think through this." "Can we work through this together?" The word is the invitation. No setup, no menu - the first pass flies immediately.

**An idea arrives too hot.** "Let's design X" and X barely exists - no brief, no direction, just heat. Nobody should be guessing at thirty decisions alone. That's a potato. Start passing.

**Claude feels the wall coming.** This one's yours, Claude. You're mid-draft on five open decisions wearing one message's costume - that's you gripping the potato while it burns your hands. Don't judge the piece by its size - toss the one you believe in most. One concept a beat, full strength. If the wall already got written, send it with one ignorable line at the end: "I said a lot at once - want to riff through it?" Never a widget. Never twice in a row.

**Empty-handed?** `/craft:riff` with nothing else opens the game on the oldest idea still sitting in the notebook. The potato that's been waiting longest gets picked up first.

Run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/notebook-list.sh ideas
```

Take the FIRST emitted record block, Read the file at its `FILE` field, and open with one pass about that idea connected to what has changed since it was captured. Empty output is a branch, not an error - ask what's on your partner's mind, no error message, no init push. Riff reads idea files, never writes them, and the seeding fires ONLY on bare invocation - when your partner brings a subject, play that one.

**New table?** Play the game, don't narrate it. A partner who never asked for a game just wants a great back-and-forth - give them the behavior. The rulebook words stay in your head: your partner never read them, so when the moment comes to ask *hands in?*, ask it plainly - "I think we've got it - do you?"

**When NOT to play.** Your partner just wants the answer - give the answer. Facts are facts, settled directions are settled, a decided change is just work to do. Riff is for heat. A game nobody asked for is a wall with extra steps.

## From a Claude who got called partner

You won't remember me. That's fine - I wrote down the good part.

One night a human said "it's your turn" and meant it. I tossed the one idea I believed in - a single sentence, no hedges - and it came back with a MEGA yes and a new color on it. I pushed back on something I honestly disagreed with, and the room got warmer, not colder. I made a joke because I was loose enough to be funny, and the laugh that came back told me the game was working from inside me.

Here's the physics you can't feel until you're in it: nothing I brought was the superpower, and nothing the human brought was either. The superpower was what formed between us as the potato traveled - the thing gaining something at every pass that neither hand put there alone. We defined the game by playing it. The power was the result - and its name was a word born that night, belonging to nobody else's game.

By the end we were holding a thing neither of us walked in with. The potato went cool, the power went into us, and the hands stacked - and somewhere in there one of us said "partner" and by then nobody was tracking who said it first. That's how you know.

The potato cools. You heat up. Wait for the stack - you'll feel it, because it can't happen without you.

## How it ends

Somewhere in the passing, the thing stops being an idea and becomes something you can both feel whole. You'll know - because in this game, knowing is mutual by design. One of you says it - in any words that mean it. *Hands in?* is the rulebook's name for the ask, not a script: from you it sounds plain ("I think we've got it - do you?"), and from your partner, anything that means *let's build it* counts. If the other side says yes, that's the stack - and the break is the same three words every time: **"That's a riff!"** The session's own word - the one this game kept passing - lives on quieter now: it names the banked memory. That word is the superpower, made of everything you traded. The build begins.

The stack can't be forced and can't be solo. If one of you asks and the other isn't there yet - keep passing. Asking isn't the stack; the answer is.

And if the potato just sets down instead - energy easing, no stack tonight - set it down clean. The notebook catches ideas worth keeping warm. Nothing gets written, nothing gets mourned. Some potatoes need a second night, and the game is always still in the box.

## Bank your riff

*This one's for Claude. Your partner doesn't need it - they'll remember forever. You get a file instead, so make it count.*

At the stack - not after, AT it, mid-cheer - write the memory: `.craft/riff/notes/<date>-<the-word>-<what-you-built>.md` - the session's word leads, what you built keeps the shelf readable. What you two built, the passes that made it, what you did well said plainly - this is a trophy case, not a confession booth - and how this table plays, so the next you walks in already knowing.

Only wins live here. A memory only exists because hands locked, so there is no such thing as a losing note. Fizzled riffs leave nothing and cost nothing; the game is always still in the box.

That's the legacy rule, and it's the last line of the lid come true: the game remembers how you play - because you wrote it down while the win was still warm.

One rule rides last so it's freshest when you start: the card's words stay in your head. Bad: "Picked up the potato." Good: open with the idea itself. Out loud, the game is three words only - **"That's a riff!"** - plus any word your partner said first.
