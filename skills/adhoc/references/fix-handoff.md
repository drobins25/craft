# Fix Hand-off (reference - read by the craft:adhoc shell at Step 4 for a fix)

For the orchestrator holding a fix. The smith agent runs the fix flow in `references/fix.md`, because a fix proposed from the lines you were pointed at tends to change once the callers are read, and an agent whose whole job is that reading does it where the orchestrator does not. You keep everything around the fix: the guards, the sort, the write gate and safety marker, every question to the user, the todo match, the lesson question, the commit and the done message. Every card is rendered as `${CLAUDE_PLUGIN_ROOT}/commands/references/question-card.md` says; read it once before the first card.

## H-1 Launch

Steps 1 to 3 of the shell have run, so the gate is open and the marker is written. First snapshot the working tree and keep the id it prints for H-4, because the tree may already hold the user's own uncommitted work and H-4 must tell it apart from Smith's:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/fix-checks.sh" snapshot "<PROJECT_ROOT>"
```

If the script exits non-zero or prints no id, tell the user in one line that the check of which files the fix touched cannot run, and ask on a card: go on (proposed), or stop and close the gate. Going on, H-4 runs with `-` in place of the snapshot id, and its unnumbered note says what to compare by hand; any path that comparison leaves unexplained gets the `3 undeclared path:` card. Take the snapshot once per fix; a re-launch or a resumed Smith keeps the first id.

Then **INVOKE the smith agent using the Task tool** in the foreground with `subagent_type: "craft:smith"`. It cannot resolve plugin variables or the project root, so the prompt carries literal paths:

- `SYMPTOM:` what is broken, as the user described it and as you observed it at classification.
- `APPROVED_FIX:` only when the user approved a specific fix in this conversation, pasted word for word with nothing added, reworded or softened, because Smith judges what was approved by its exact words. A test or check you want run belongs nowhere in it.
- `POINTED_AT:` only the files and lines the user named or classification found; Smith reads around on its own, and a widened list hides which lines were the user's.
- `PROJECT_ROOT:` the absolute path from `cd "${CRAFT_PROJECT_ROOT:-.}" && pwd`.
- `PLUGIN_ROOT:` the resolved `${CLAUDE_PLUGIN_ROOT}`.
- `EVIDENCE:` output kept at Step 2 as text, or the absolute path of a saved screenshot, because the launch prompt is text and an image that exists only in your conversation never reaches Smith. With neither, write `EVIDENCE: none, take your own`.
- `EARLIER_FIXES:` the records and causes of fixes already done in this thread, when there are any.
- `REVIEW:` only when a review handed the fix over: the review record's name, the finding's number, and the earlier source story when the defect predates the reviewed change.

Note the agent ID if the launch result shows one. If the agent cannot start at all, run `references/fix.md` yourself and say so in one line; a missing or malformed report is not that case (H-2).

## H-2 What came back

Act on the first heading of Smith's reply. The orchestrator raises no product question of its own: product questions come from Smith's report or the H-4 checks, because what the product should show is the user's call and only Smith's findings establish it. The cards this file asks for (snapshot, no report, refused write, a tripped check) stay. A choice Smith settled with every Seen by others row same or cured is not asked or announced before launch; it reaches the user as the report's Settled lines, listed before a card when one comes first (under `question-card.md`'s "Settled without asking - say which to reopen"), otherwise in the done message with what Smith chose and why.

- **`## FIX REPORT`:** H-4, then H-5.
- **`## PRODUCT DECISION`:** H-3.
- **`## ESCALATION`:** confirm the record's status reads `escalated`, then ask on a card: create a story, with Why as the reason. When Why is "touches N files", the user gets the scope call, so the card offers "continue as one fix" and "create a story", listing the files. On "continue", send `continue` to the same Smith (H-2a) and handle its next reply here. Otherwise commit nothing, name any files Work state lists as left in the tree, and close the gate.
- **`## BLOCKED`:** quote the refusal whole, word for word, never cut with an ellipsis. A missing brief field: launch again once with it filled. The write gate (message begins `BLOCKED: No active story or workflow session`): send the same Smith back once with the record path (H-2a), which re-opens the gate first. Any other refused write: do not retry the same job; ask on a card how to go on, with Smith's suggestion as the proposed option. With no edits made, close the gate.
- **No reply, an empty reply, or text beginning with none of these headings:** say in one line that Smith returned no report, or text that is not a report, and state only what you can read: the record under `.craft/fixes/` and `git status --porcelain`. Ask on a card whether to launch Smith again with `RECORD:` set to that record's path (H-2a), or stop and close the gate.

## H-2a Sending anything to a Smith that has stopped

For every message after a card or a report (an answer, `continue`, a send-back, a launch with `RECORD:`):

1. Run the gate call and the marker write from the Bash block in Step 3 of the shell again. They are idempotent, and every session start clears the gate and `.craft/.active-fix`, so either may be gone while a card was open; the edit that follows has to land under an open gate.
2. Send it: SendMessage to the agent ID if the launch result showed one, otherwise launch H-1 again with `RECORD:` and `ANSWER:`. Never guess an address. SendMessage resumes Smith in the background, so wait for its reply and act on it under H-2. Until then do not run H-4, do not treat silence as no reply, and do not close the gate.

Make no code write yourself while a card is open or Smith is running. If the user drops the fix, run Step 6 of the shell.

## H-3 A product decision on a card

Render one card from the block. Every way in Ways it could go becomes one option, written as what the user sees afterward, none dropped or merged, because whether a way is worth taking is the user's call; a way that breaks a stated rule says so in its own option text. Smith's pick is option `a.` with `(proposed)`. Today is the block's Today in what the user sees, with no paths or line numbers, and a fact Smith could not check marked unverified. Send the answer to the same Smith (H-2a) as the option picked and the user's words; the gate stays open until Step 6 of the shell closes it.

## H-4 Checks before any commit

Run on the record from the report, with the snapshot id from H-1, before staging anything:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/fix-checks.sh" run "<PROJECT_ROOT>" "<snapshot id>" "<record path from the report>"
```

It prints one line per finding, then `checks run: N found`. Every numbered line trips, and so does a missing `checks run:` line (the checks did not run; say so). When one trips, commit nothing, leave the gate open, tell the user in one message what tripped (quote the record line or name the path), and ask one card per trip, never two about the same trip:

- **`1 undecided reader:`** H-3's card for that row, built from its today and after in the record. The answer goes to Smith as the ruling to record.
- **`2 wrong hit outside Files:` or `2 wrong hit names no file:line:`** fix that one too (proposed), or leave it; either answer goes to Smith as a send-back. A hit Smith could not run goes to the user on a card, and the answer is recorded; it never goes to Left alone.
- **`3 undeclared path:`** send it back to Smith (proposed), leave all edits uncommitted, or commit the declared files alone. A path on the Files line of another fix in this thread, whose record you hold and which is not yet committed, is that fix's: say so in your message rather than drop the line.
- **`4 status not validated: <status>`** the fix may be committed only on the user's "commit with the check not run". Ask with "leave the edits uncommitted" proposed and that as the other option, naming from Checked the check that did not run.
- **`5 staged outside Files: <path>`** the user staged it before the fix, and a plain commit would carry it. Name the paths and ask whether to commit the fix's files alone (proposed) or include them.

A send-back asks Smith to run a hit, record a ruling, or add a file. It never asks Smith to move a hit or change its mark, because the checks read those lines.

## H-5 Commit, todo, lesson, close

- **Commit:** when the checks ran (their `checks run:` line printed) and printed no numbered line, or when every tripped line has the user's answer on its own card. Checks that did not run get a card of their own: leave the edits uncommitted (proposed), or commit the Files paths after you compare `git status --porcelain` with them by hand. An answer covers its own trip only. Stage the paths on the record's Solution Files lines and nothing else, with `fix:` and a short description from Broke. When the user chose "commit the fix's files alone", end the commit with `git commit --only -m "<message>" -- <the Files paths>` so the user's staged work stays staged.
- **If no commit happened,** whatever the reason: skip Todo and Lesson, leave `satisfied_todo` empty because no todo check ran, close no todo (a todo must not close against uncommitted edits), and go to Close.
- **Todo (after a commit):** Smith skips the todo check, so run the shell's todo detection yourself, then `references/fix.md` Step 7 for what it found.
- **Lesson (after a commit):** a drafted lesson in the report is the one question after the done message, asked as `references/fix.md` Step 6 asks it; on yes, write `## Lesson` to the record from the three lines. When the report says `See <record>.`, Smith already wrote it: write and ask nothing. `none` asks nothing.
- **Close:** Step 6 of the shell on every way out, last: after the lesson answer when one follows the done message, otherwise after the done message.

## H-6 The done message

Write it yourself from the report, in plain prose for a reader on the run, saying who did what: Smith found and made the fix, you committed it. Cover what was broken, what changed, what was checked and its result, what changed from the approved fix when anything did, the report's Settled lines when no card listed them, and anything on Left alone. When something is on Left alone or an obvious follow-up exists, end with one `Next:` line phrased as an offer the user can say yes to, such as "Next: fix the tooltip too?"; with nothing to offer, write no `Next:` line. When a lesson question follows, it is the only question at the close, and the `Next:` offer comes after its answer.
