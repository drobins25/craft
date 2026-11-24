# Fix Hand-off (reference - read by the craft:adhoc shell at Step 4 for a fix)

For the orchestrator holding a fix. The smith agent runs the fix flow in `references/fix.md`, because a fix proposed from the lines you were pointed at tends to change once the callers are read, and an agent whose whole job is that reading does it where the orchestrator does not. You keep everything around the fix: the guards, the sort, the write gate and safety marker, every decision Smith passes up, the todo match, the lesson question, the commit and the done message. Every card is rendered as `${CLAUDE_PLUGIN_ROOT}/commands/references/question-card.md` says; read it once before the first card.

## H-1 Launch

Steps 1 to 3 of the shell have run, so the gate is open and the marker is written. First snapshot the working tree and keep the id it prints for H-4, because the tree may already hold the user's own uncommitted work and H-4 must tell it apart from Smith's:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/fix-checks.sh" snapshot "<PROJECT_ROOT>"
```

If the script exits non-zero or prints no id, go on with `-` in place of the snapshot id, because checks 1, 2, 4 and 5 still run without it. Run `git status --porcelain` now and keep its output as the list of what the user had already changed, for the hand comparison H-4's unnumbered note asks for: a path off the Files lines that is on that list is the user's and stays out of the commit, and any other path off the Files lines is ruled as a `3 undeclared path:` line. Say in the done message that this check could not run. Take the snapshot once per fix; a re-launch or a resumed Smith keeps the first id.

Then **INVOKE the smith agent using the Task tool** in the foreground with `subagent_type: "craft:smith"`. It cannot resolve plugin variables or the project root, so the prompt carries literal paths:

- `SYMPTOM:` what is broken, as the user described it and as you observed it at classification.
- `APPROVED_FIX:` only when the user approved a specific fix in this conversation, pasted word for word with nothing added, reworded or softened, because Smith judges what was approved by its exact words. A test or check you want run belongs nowhere in it.
- `POINTED_AT:` only the files and lines the user named or classification found; Smith reads around on its own, and a widened list hides which lines were the user's.
- `PROJECT_ROOT:` the absolute path from `cd "${CRAFT_PROJECT_ROOT:-.}" && pwd`.
- `PLUGIN_ROOT:` the resolved `${CLAUDE_PLUGIN_ROOT}`.
- `EVIDENCE:` output kept at Step 2 as text, or the absolute path of a saved screenshot, because the launch prompt is text and an image that exists only in your conversation never reaches Smith. With neither, write `EVIDENCE: none, take your own`.
- `EARLIER_FIXES:` the records and causes of fixes already done in this thread, when there are any.
- `REVIEW:` only when a review handed the fix over: the review record's name, the finding's number, and the earlier source story when the defect predates the reviewed change.
- `BUG:` only when the request pointed at a bug record in `.craft/bugs/` (its file, its slug or its line in the open pile): that record's file name without `.md`, for the fix record's `bug:` line. A bug that only looks like this defect is not named.

Note the agent ID if the launch result shows one. If the agent cannot start at all, run `references/fix.md` yourself and say so in one line; a missing or malformed report is not that case (H-2).

## H-2 What came back

Act on the first heading of Smith's reply. You decide what Smith passes up and what the H-4 checks find, working from the record and the report, because you hold the conversation and Smith's evidence, and a card puts a judgment in front of a user who may not be able to make it. Of those, only two reach the user as a question: a taste choice (H-3) and the story question under `## ESCALATION`. Every call made without asking, yours and the report's Settled lines, reaches the user as a report: listed before a card when one comes first (under `question-card.md`'s "Settled without asking - say which to reopen"), otherwise in the done message, each with what was chosen and why.

- **`## FIX REPORT`:** H-4, then H-5.
- **`## PRODUCT DECISION`:** H-3.
- **`## ESCALATION`:** confirm the record's status reads `escalated`, then ask on a card: create a story, with Why as the reason. Commit nothing, name any files Work state lists as left in the tree, and close the gate.
- **`## BLOCKED`:** quote the refusal whole, word for word, never cut with an ellipsis. A missing brief field: launch again once with it filled. The write gate (message begins `BLOCKED: No active story or workflow session`): send the same Smith back once with the record path (H-2a), which re-opens the gate first. Any other refused write: stop the fix without retrying it, because a refusal is a limit you cannot lift, and one from the user's own permission prompt is already their answer. Commit nothing, name any files Work state lists as left in the tree, and close the gate.
- **No reply, an empty reply, or text beginning with none of these headings:** say in one line that Smith returned no report, or text that is not a report, and state only what you can read: the record under `.craft/fixes/` and `git status --porcelain`. Launch Smith again once with `RECORD:` set to that record's path (H-2a), or with the brief alone when there is no record, because a resumed Smith re-reads the record and the tree. A second reply that is not a report stops the fix: commit nothing and close the gate.

## H-2a Sending anything to a Smith that has stopped

For every message after a card or a report (an answer, a send-back, a launch with `RECORD:`):

1. Run the gate call and the marker write from the Bash block in Step 3 of the shell again. They are idempotent, and every session start clears the gate and `.craft/.active-fix`, so either may be gone while a card was open; the edit that follows has to land under an open gate.
2. Send it: SendMessage to the agent ID if the launch result showed one, otherwise launch H-1 again with `RECORD:` and `ANSWER:`. Never guess an address. SendMessage resumes Smith in the background, so wait for its reply and act on it under H-2. Until then do not run H-4, do not treat silence as no reply, and do not close the gate.

Make no code write yourself while a card is open or Smith is running. If the user drops the fix, run Step 6 of the shell.

## H-3 A product decision

Decide it from the block and the record. Drop every way that leaves the defect in place, breaks a rule the project or the user stated, or breaks something that works today, because offering one only invites a wrong pick. When no way is left, the fix cannot be made cleanly: ask on a card whether to make it a story, with what each way would break as the reason, then go on as `## ESCALATION` does after its card. Of the ways left, take one that keeps what works today as it is, or else one that does what the surrounding code already does. When neither decides it, and the ways left each work and differ only in how something looks or reads to the user (which color, which word), with nothing the user has said settling it, that is a taste choice: render one card with only those ways as options and your pick as `a.`. Otherwise take Smith's pick. Send the ruling to the same Smith (H-2a) saying whose it is (yours, or the user's with their words), so the record's `decided:` shows who made the call; the gate stays open until Step 6 of the shell closes it.

## H-4 Checks before any commit

Run on the record from the report, with the snapshot id from H-1, before staging anything:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/fix-checks.sh" run "<PROJECT_ROOT>" "<snapshot id>" "<record path from the report>"
```

It prints one line per finding, then `checks run: N found`. Every numbered line trips, and so does a missing `checks run:` line (the checks did not run; H-5 says what follows). When one trips, commit nothing yet, leave the gate open, and rule on each trip as below, one ruling per trip. Send a trip back to Smith at most once; a trip still printed after its send-back keeps your ruling, so the fix never loops:

- **`1 undecided reader:`** decide that row as H-3 does, from its today and after in the record, and send the ruling to Smith to record.
- **`2 wrong hit outside Files:` or `2 wrong hit names no file:line:`** send it back to be fixed too, because a wrong hit is this same defect in another place. A hit Smith could not run: read it, and send it back to be fixed too when it does what the fixed line did to the same kind of input, otherwise send a ruling to leave it, with why, to be recorded; it never goes to Left alone.
- **`3 undeclared path:`** a path on the Files line of another fix in this thread, whose record you hold and which is not yet committed, is that fix's: leave it for that fix's commit. Send any other back so Smith adds it to Files if its own edit made it; one Smith still does not claim stays in the tree as it is and out of this commit, because Smith is the one who knows what it edited and an untouched path loses nothing. Name each in the done message.
- **`4 status not validated: <status>`** leave the edits uncommitted, so a fix commit always means the symptom was seen gone; the edits stay in place, and the done message names the check that did not run, from Checked.
- **`5 staged outside Files: <path>`** the user staged it before the fix; nothing to rule, because H-5's commit leaves it staged and out of the fix.

Then review the fix yourself, because Smith wrote it and a reader who did not write the code catches what its writer reasoned past. From the project root, run H-1's snapshot command again and read `git diff <first id> <new id> -- <the Files paths>`, which shows only what changed since launch, new files included; with no snapshot, read `git diff HEAD -- <the Files paths>` and each new file whole, where a file on H-1's list also holds the user's own earlier edits, which are not findings. Check it against the record's Change and Mechanism for correctness only: an edit the record does not describe, a described change the diff lacks, or a line that would not do what Mechanism says. Skip style, because a review asked to find problems always finds something. Send findings back once, in the same message as the checks' send-backs; a finding still standing after Smith's next report, or a new one in it, leaves the edits uncommitted and is named in the done message.

A send-back asks Smith to run a hit, record a ruling, add a file, or settle a review finding. It never asks Smith to move a hit or change its mark, because the checks read those lines.

## H-5 Bug, commit, todo, lesson, close

- **Bug:** when a review finding is left standing (one still standing after Smith's next report, or a new one in it) and the fix was started from a bug record (you sent `BUG:`, or the record's `bug:` line names one), the bug stays open and the done message says why: the fix was not accepted. When no send-back to Smith is waiting for a reply, no review finding is left standing, and the record reads `status: validated`: if you sent `BUG:` and the record's `bug:` line is empty or names another, write the name you sent on it first. Then, when its `bug:` line names a bug record, close that bug, whether or not the fix is committed, because nothing returns to this step when a later commit lands. The line decides the close, not your memory of the brief, because a long fix or a context summary can drop the brief from this conversation. Read `.craft/bugs/<the name on that line>.md` under the project root first. When it is not there, the bug is already closed: run nothing, because the close command given a name it cannot find closes an open bug whose name contains it. One that gives its layer as `judgment` stays open, because only the user's eye on the result closes that kind, and the done message says it is fixed and theirs to close. Otherwise run `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/bugs-close.sh" "<the bug record's path>" --status=fixed --fixed-by="fix record <the record's name>"` once and name the closed bug in the done message. Ask nothing. `already closed` means nothing is left to do; any other refusal leaves the bug open and goes in the done message.
- **Commit:** when the checks ran (their `checks run:` line printed), every numbered line has its H-4 ruling, check 4 did not trip, and no review finding is left standing. When the checks did not run, leave the edits uncommitted, because they are what tell the fix's files from the user's own work. The user's own request to commit wins over any of these. Stage the paths on the record's Solution Files lines and nothing else, then commit with `git commit --only --no-verify -m "<message>" -- <the Files paths>`, the message `fix:` and a short description from Broke, so anything the user staged stays staged and out of the fix.
- **If no commit happened,** whatever the reason: skip Todo and Lesson, leave `satisfied_todo` empty because no todo check ran, close no todo (a todo must not close against uncommitted edits), and go to Close.
- **Todo (after a commit):** Smith skips the todo check, so run the shell's todo detection yourself, then `references/fix.md` Step 7 for what it found.
- **Lesson (after a commit):** a drafted lesson in the report is the one question after the done message, asked as `references/fix.md` Step 6 asks it; on yes, write `## Lesson` to the record from the three lines. When the report says `See <record>.`, Smith already wrote it: write and ask nothing. `none` asks nothing.
- **Close:** Step 6 of the shell on every way out, last: after the lesson answer when one follows the done message, otherwise after the done message.

## H-6 The done message

Write it yourself from the report, in plain prose for a reader on the run, saying who did what: Smith found and made the fix; you decided what it passed up and made any commit. Cover what was broken, what changed, what was checked and its result, what changed from the approved fix when anything did, each call made without asking (the report's Settled lines and your own rulings, with what was chosen and why) that no card's settled list already showed, any edits left uncommitted and why, and anything on Left alone. When something is on Left alone or an obvious follow-up exists, end with one `Next:` line phrased as an offer the user can say yes to, such as "Next: fix the tooltip too?"; with nothing to offer, write no `Next:` line. When a lesson question follows, it is the only question at the close, and the `Next:` offer comes after its answer.
