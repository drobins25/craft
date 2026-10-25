# The question card

A question card is for a question the user has to think about. "Yes" or a
letter applies that option; other words that pick an outcome apply it; a
question gets an assessment and the same card back. The examples below are
invented and own nothing in this codebase: mirror the shape, not the content.

## The card, in order

The header is `**Question N of M:**` alone on its line. M counts the cards
known when the card renders; a later round that adds a card raises M on the
cards that follow.

The next line is the question in one sentence, in inline code: it names the
ways and ends in a question mark, nothing else. Facts go in Today, the stake
goes in the close.

Then a `**Today.**` paragraph: what exists now, in what the user sees. Every
sentence changes the pick or comes off. No file paths or line numbers, since
the user never opens them. A claim you could not check says "unverified" in
the same sentence as the claim.

Then the options in one plain three-backtick fence, lettered `a.` `b.` inline,
and `c.` only when a third real outcome does something different; a question
with more than three outcomes is split into cards. The proposed option's title
is followed by `(proposed)`. Each option is written as what the user sees
afterward, in as many short lines as that takes, and may end with one sentence
on when it is the right pick. A way-out that is a real outcome stays, written
as what happens; a pure escape goes, since the reply line already takes any
words.

Then the close: `My pick is a. <what the user sees>.` then, on its own line,
`**Question:** Go with a?` then, on its own line, `**Why:** <one sentence on
why a fits this user's situation and the other ways do not, grounded in a fact
from Today>`, with a blank line before each. With three options, the Why rules
out both other ways, one clause each. "Yes" is a complete answer. The pick and
the Why are each one line of explanation, never a transcript of reasoning.

## Around the card

Before Question 1, one list headed
`Settled without asking - say which to reopen` names every call made without a question, so the user sees every
decision before the first one they are asked. Each item leads with the
behavior in product words, then an indented line of code facts, the only
place paths appear; every line the same shape. The list prints once, before
the first card; when the flow asks no card, it prints where the first card
would have rendered; when no call was made without asking, it is omitted.
When the user names a settled item, it is asked on a card in the flow's
normal order.

After each answer, one line reads the ruling back in product words and
confirms the write: `Ruled (a): <behavior>. In the story.` after the edit has
landed in the story file, or `Ruled (a): <behavior> - kept as planned.` when
the answer changes nothing in the file. The read-back prints only after the
write lands, and the next card renders only after that, so an answer survives
a session that dies mid-flow.

A card closes only on the user's explicit answer: a letter, a yes, or words
that pick an outcome. It is never withdrawn, never moved to the settled list,
and never decided by the agent, because the user is the only one who can
close it. A question from the user is answered in full and never with a
question; the agent's job at that moment is to show the thing clearly, in
plain words, and then put the same card back, with nothing between the answer
and the card. A second question on the same card means the card failed: redraw
it plainer and say so. When the user asks about a card instead of answering
it, the answer is an assessment and the same card comes back unchanged.

A card is redrawn only on a fact, the user's or the agent's own finding, and
the redrawn card names that fact. A clarifying question is not a fact.

## What makes the pick

The pick serves the intent already on the page: the story's Spark, or the
user's research query when there is no story. It rests on something checked
this session; an unchecked claim says "unverified" in the same sentence as
the claim, in Today. It holds when challenged, and moves when someone points
out a problem, the user or the agent itself; then the card names the fact
that moved it.

## Examples

<examples>
<example>
Settled without asking - say which to reopen

- Plan citations are scanned at story completion, not at each chunk.
    `complete-story.sh` already walks every changed file once
- A hit names the file and line in the user's words, no path.
    the scan's output line is reformatted, not the scan itself

**Question 1 of 4:**

`Fail the story on a plan-citation hit before it is marked complete, or withhold the commit after?`

**Today.** The story is marked complete first. Then the commit step runs, and if it backs out, the list of files it was about to commit is thrown away. The only thing that backs it out today is a file list from the wrong story, which is rare. A comment that cites the plan would not be rare.

```
a. Fail before complete (proposed)
   The scan runs before the story is marked complete. A hit looks
   like any other failed check: you see the line, the fix loop
   runs, completion runs again.

b. Withhold the commit after complete
   The story is marked complete, then the commit is withheld. You
   see "complete" on the story, nothing in git, the file list gone,
   and no line telling you what to do next.
```

My pick is a. A hit fails the story before it's marked complete, same as a failed test, and you fix it and finish.

**Question:** Go with a?

**Why:** A plan citation would not be rare the way a wrong-story file list is, so b would show you "complete" with nothing in git on a hit you will actually see, where a treats it like any other failed check.
</example>
<example>
**Question 1 of 1:**

`Close this story as already built, or re-scope it to the part that is missing?`

**Today.** The saved-cart reminder this story asks for is already built and
running. Checkout builds it and sends it on the schedule the story describes;
I read the reminder job end to end to confirm. The only gap is that no test
covers it.

```
a. Close it as already built (proposed)
   The story is marked done. The missing test lands as a
   quick fix, not a story.

b. Re-scope to the unbuilt part
   The story stays open and its Spark is rewritten around
   what is missing. Right pick if you had more in mind than
   the reminder.
```

My pick is a. You get a closed story and a one-line fix for the test.

**Question:** Go with a?

**Why:** The reminder already sends on the story's schedule, so there is
nothing left to build and b would reopen work that is done.
</example>
<example>
**Question 2 of 3:**

`Dedupe rows in the export job, or at the point the rows are written?`

**Today.** The CSV export writes every order row it reads, and the orders
table holds the same order twice when a payment retries. Whether the retry
path can be changed is unverified; I did not read the payment code.

```
a. Dedupe in the export job (proposed)
   The export drops repeat orders before writing the file.
   The orders table keeps its duplicates.

b. Dedupe where rows are written
   The payment retry stops writing a second row. Every
   report downstream gets clean data, not only this export.
```

My pick is a. The export is clean next run and nothing else changes.

**Question:** Go with a?

**Why:** The duplicates come from payment retries I have not read, so a fixes
the export you asked for and b reaches into code this story does not own.

The user replies: "The retry path already dedupes. The double rows are from
the nightly import."

**Question 2 of 3:**

`Dedupe rows in the export job, or in the nightly import?`

**Today.** You said the payment retry already dedupes, and the double rows
come from the nightly import. That changes the pick: the import is this
story's own file list. The CSV export writes every order row it reads.

```
a. Dedupe in the nightly import (proposed)
   The import stops writing repeat orders. The export and
   every other reader get clean rows.

b. Dedupe in the export job
   The export drops repeat orders before writing the file.
   The import keeps writing duplicates for other readers.
```

My pick is a. Clean rows everywhere from the next import.

**Question:** Go with a?

**Why:** The import is where the duplicates are made and it is already in
this story's files, so a fixes the cause and b patches one symptom.
</example>
<example>
**Question 3 of 3:**

`Send the digest at the user's local 8am, or at a fixed 8am UTC?`

**Today.** The digest job runs once a day at a fixed hour. Users are in four
time zones, and the sign-up form stores a time zone for each.

```
a. Local 8am per user (proposed)
   Each user gets the digest at 8am their time. The job
   runs hourly and sends to whoever's hour it is.

b. Fixed 8am UTC
   Everyone gets the digest at the same moment. West coast
   users get it at midnight. Right pick if you want one
   predictable send for support to reason about.
```

My pick is a. Every user sees the digest at breakfast.

**Question:** Go with a?

**Why:** The time zone is already stored per user, so a costs one hourly
schedule and b throws away data you already collect.

The user replies: "b. Support needs one send time."

Ruled (b): the digest sends at a fixed 8am UTC for everyone. In the story.
</example>
</examples>
