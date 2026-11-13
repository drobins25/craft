# Review Record and Close-Out

Every `/craft:review` run that reached a reviewer leaves one record in `.craft/reviews/`, clean or not. A clean record is the denominator: without it, "reviewed and fine" and "never reviewed" look the same on disk. The close-out then graduates each finding to the craft artifact that fits it, and the record points at what each finding became.

Read this file at Step 5b (to write the record) and Step 6 (to close out).

## Who writes what

- The reviewer cannot write files. The orchestrator writes the record, from the reviewer's report, in one call to `review-capture.sh`.
- `review-capture.sh` owns the grammar. It derives the file name, craft version, the findings count and outcome itself, stamps a blank `graduated_to:` line under every finding, and refuses a body with no Verified list.
- `review-graduate.sh` is the only thing that edits a record afterward.
- The record is immutable after capture. Every finding stays in full, exactly as the reviewer wrote it, forever. The only lines that ever change are a finding's `graduated_to:` line and, on a dismissal, the one `dismissed:` line under it. The record carries `outcome:` (`clean` or `findings`) and no status.

## The record

The frontmatter, in order, as capture writes it:

```
type: review
created, captured_at
mode (branch | story | project), strategy (standard | maze)
reviewed (branch name, story name, or audited path)
ref (<base>..<head> short SHAs, or the head SHA alone in project mode)
focus, files, lines (omitted in project mode)
craft_version, reviewer, gates
findings
outcome (clean | findings)
```

The body is `## Verified`, one line per check the reviewer made and found clean, then `## Findings`: `None.` when clean, otherwise each finding under `### N. (<category>): <title>`, numbered 1..N in the order Step 5 numbered them. The category is one of security, logic, performance, consistency. A finding keeps the reviewer's seven fields (Symptom, Expected, Actual, Consequences, Reproduce, Evidence, Fix) verbatim, plus `**Withdrawn.** <why>` when the reviewer raised it and then disproved it.

The record name is the file name without `.md`. It is the value every `review:` back-link and every graduate call uses.

## The capture call

One call per `/craft:review` invocation, with the body on stdin:

```
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/review-capture.sh" --mode=<branch|story|project> --strategy=<standard|maze> \
  --reviewed="<branch name | story name | audited path>" --ref="<base7>..<head7> | <head7>" \
  --focus="<csv>" --files=<N> [--lines=<N>] --reviewer="<agent name[, agent name]>" \
  --gates="<what ran - result | none | not reported>" --stdin <<'BODY'
<the body>
BODY
```

- `--lines` is required for branch and story runs and refused for project runs.
- `--gates` is `not reported` when the reviewer's report has no Gates run line. `none` means the reviewer said it ran nothing; an unknown is never written as `none`.
- When the report has no Verified list, the body carries the single line `- None reported - the reviewer's report listed no checks it found clean.` under `## Verified`. Never invent a check.
- A finding the reviewer withdrew stays in the body in full.
- The body must not already hold a `graduated_to:` line outside a fenced block: capture stamps its own.

The script prints the record's absolute path as its last line. It exits 2 and writes nothing when a flag is missing or the body breaks the grammar; fix the named problem and run it again.

A worked example body that capture accepts (finding 1 is one the reviewer withdrew, so the close-out would propose dismissing it; finding 2 is the issue that matters):

~~~review-body
## Verified
- Every caller of `parseToken` handles the new null return
- The migration is idempotent when run twice against the same database

## Findings

### 1. (consistency): Error message wording differs from the sibling handler

**Symptom:** The new handler says "Invalid token" where its sibling says "Token rejected".
**Expected:** Handlers in `api/` share one wording - "No requirement found"; looked in `locked.md` and the sibling handlers.
**Actual:** Read in the code, not run: `api/refresh.ts:31` and `api/login.ts:27` differ.
**Consequences:** A client matching on the message text would handle one route and miss the other.
**Reproduce:**
1. Check out the branch at the head commit.
2. Compare the two lines.
**Evidence:**
```
api/refresh.ts:31: throw new HttpError(401, "Invalid token")
api/login.ts:27:   throw new HttpError(401, "Token rejected")
```
**Fix:** Align the wording.
**Withdrawn.** Clients branch on the status code, and the two routes already document different messages on purpose.

### 2. (logic): Refresh path drops the session when the token is null

**Symptom:** A user whose token expired is signed out instead of refreshed.
**Expected:** "An expired token is refreshed once before the session is dropped" (story acceptance line 4).
**Actual:** Observed - ran `npm test auth`, got `1 failed: refresh keeps session`.
**Consequences:** Every user hitting an expired token loses their session mid-work.
**Reproduce:**
1. Check out the branch at the head commit.
2. Run `npm test auth`.
**Evidence:**
```
FAIL auth/refresh.test.ts > refresh keeps session
  expected session to exist, got null
```
**Fix:**
```diff
- if (!token) return endSession()
+ if (!token) return refreshOnce()
```
~~~

## Immutability and the one allowed edit

Graduate through the script, never by editing the file:

```
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/review-graduate.sh" <record name> <N[,N...]> <value> [--by=user|reviewer] [--reason="<text>"]
```

- `value` is the name of the artifact the finding became (a fix, tweak, bug, story or notebook todo), or `docs`, or `dismissed`.
- A comma list fills several findings in one write, all or nothing.
- `dismissed` requires `--by` and `--reason`; the script inserts `dismissed: <by> - <reason>` under the finding's `graduated_to:` line. Any other value refuses both flags.
- The script refuses a finding that is already graduated, an unknown finding number and an artifact that does not exist yet. Graduate only after the destination is written.
- Blank means nobody acted on the finding, whether the message went unanswered or the user left it. `docs` is a value only older records carry; graduate still accepts it.

## The doors

A finding graduates through one of four doors. The doors are not re-explained here; each door's own boundary sentence is quoted from its source, and the source is the authority. Read the finding against these sentences and pick.

**Adhoc** - `skills/adhoc/SKILL.md`, description:

> Acts NOW - a defect to file and fix later belongs in /craft:bugs, other deferred work in the notebook. Do NOT use for new features, design exploration, or changes requiring creative spark.

**Bug** - `commands/craft-bugs.md`, description and its "Not for" line:

> File a bug without fixing it, from a person mid-conversation or an agent mid-run.

> Not for: fixing it now (/craft:adhoc), ideas and todos (/craft:notebook).

**Notebook todo** - `commands/craft-notebook.md`, "Not to be Confused With":

> Notebook todos are deferred intent items, not act-now work.

> A todo is intent; a bug record carries the reproduce and done-when a fixer needs.

**Story** - `commands/craft-notebook.md`, the story line, and `skills/adhoc/SKILL.md`, the "No new features" guard:

> For thoughts that are already story-shape with a clear acceptance shape.

> If the solution adds something that wasn't there before (a new component, a new API endpoint, a new element on the page), it's a story.

A review finding never files a decision card.

## The message

After the findings are checked, show one message and nothing else. Nothing is created until the user answers.

This message is read by a developer who did not watch these bugs happen and must agree or disagree with each one before acting on it, so write only what helps them decide and let the command and output under each Checked show the work, since they read on the run and may stop at any line.

The message, in order:

- One bold verdict line, `Request changes: N blocking, M non-blocking.` or `Nothing blocking: M non-blocking.`, counted from the check, with `, K unresolved` before the period when the check left any unresolved. It is the first line of the message; nothing is printed before it, and the check's work is never narrated. This matters because the reader may stop at this line, and an unresolved risk it leaves out reads as a clean branch.
- One line on the state of the branch. Every test or gate result in it names who ran it and what came back, and a blocking gate nobody ran is named as not run. A result you did not run yourself is never written in your own voice. This matters because the reader may stop at this line and open the PR on it, so a reviewer's "tests pass" restated as fact reads as a green suite nobody saw.
- One line per cause for each change you made to what a reviewer read, was told or was allowed to do: the cause, what you did instead of what the step asks for, and the step numbers in parentheses. Changes with one cause share one line. Name it even when you judge it harmless. This matters because such a change can hide a finding, the reader cannot see how the review ran, and a difference you thought harmless is the one they would never think to ask about.
- Each reproduced finding under a backtick heading `N. <blocking|non-blocking>: <title>`, blocking first. Each finding the check left unresolved goes under `N. unresolved: <title>`.
- The not-real findings in one group under one backtick heading, `<numbers>. <count> findings checked and not real`. The numbers follow record order, consecutive runs as a range and the rest as a list (`4 through 10`, `1, 4 and 7`). Each item is one bold sentence naming the finding, then its reason in plain text. The group ends with one `Proposed: close.`
- `**On go:**` with numbered lines: one adhoc per fix, the closes in the record, and for each unresolved finding a line saying it stays open in the record until the user says bug or close.
- `**Question:** Go?`, the message's last line.

A reproduced finding's body is:

- one bold sentence for a developer who did not watch this bug happen and must agree or disagree with it before acting on it: a readable, clear and direct version of what is broken, missing or wrong, where, and why it's wrong (the rule or expectation it breaks, not the code cause), in 30 words or less, with no severity and no fix, because this might be the only line they read about this finding;
- how the code produces it, in one or two plain sentences, leaving where to change it to the Fix line, and how someone reaches it when the bold line leaves that unclear, so the reader can believe it without opening the code;
- a blockquote with a bold "Checked." lead-in, then the command and its output on their own backticked lines, then a bold "Not run." lead-in naming each path read but not run;
- one bold sentence opening "Fix:" with one file:line and its size, then why any other fix shown was not taken;
- a last line `Proposed: <route>`.

The route is `fix now, adhoc`, `story`, `bug` or `close`. An unresolved finding shows the attempt (the command run and what came back) and ends `Proposed: your call, bug or close.` The check never proposes `todo`, though a reply may set it, and the re-shown line then reads `Proposed: todo`.

The message holds no table, no lettered options, no pick line and no quoted source lines. The only code lines are the command and output under each Checked; backticks elsewhere mark only headings, file paths and flags.

An outside review shows the same message without any `Proposed:` line, `On go:` block or `**Question:** Go?`, and ends after the last finding, followed by one line naming the file the message was saved to. Nothing graduates and nothing is written in the project.

The example is invented and owns nothing in this codebase: mirror the shape, not the content.

```
**Request changes: 2 blocking, 1 non-blocking.**

First review of this branch. Six findings: two are bugs a customer hits, one is leftover code, two do not reach a user and one has the same cause as the first.

`1. blocking: a refund larger than the invoice goes through`

**Your customer can get back more than they paid.** On a 40 dollar invoice, a 35 dollar refund was accepted twice, 70 dollars in all. The form checks each refund against the invoice total, never against what is left after earlier refunds.

> **Checked.** I ran it twice on this branch and both refunds went through.
> `python -m billing.refund --invoice 40-paid --amount 35`
> `refund 71 accepted`
> `python -m billing.refund --invoice 40-paid --amount 35`
> `refund 72 accepted`
>
> **Not run.** The CSV import. I read the code; it calls the same refund service without the form. Likely affected, not run.

**Fix: one check in the refund service, `billing/refunds.py:88`, about four lines.** The review suggested capping the form field instead. That leaves the CSV path open, so skip it. Saying go sends the fixer to the service only.

Proposed: fix now, adhoc.

`2. blocking: a paid invoice shows Unpaid for up to an hour`

**Your customer pays and the invoice still says Unpaid until the next hourly sync.** The payment webhook writes the payment but never updates the invoice status, so the status waits for the sync job to notice.

> **Checked.** I replayed a test webhook on this branch and the status did not move.
> `python -m billing.webhooks.replay --fixture payment-succeeded --invoice 71`
> `payment recorded; invoice 71 status: unpaid`
>
> **Not run.** The hourly sync. I read it; it does set the status, which is why the invoice corrects itself an hour later.

**Fix: set the status in the webhook handler, `billing/webhooks.py:41`, one line.** The sync job stays as it is.

Proposed: fix now, adhoc.

`3. non-blocking: the old receipt builder still runs on every payment`

**Every payment builds its receipt twice, and the second copy is thrown away.** This branch adds the new receipt builder and sends its output, but the call to the old builder was left in place and still runs, though the customer gets one correct receipt.

> **Checked.** I recorded one test payment on this branch with the receipt log on.
> `python -m billing.payments.record --fixture card-ok --log receipts`
> `receipt built (new), sent; receipt built (old), discarded`

**Fix: remove the old builder's call in `billing/payments.py:112`, two lines.**

Proposed: fix now, adhoc.

`4 through 6. three findings checked and not real`

**4. Tax rounding drifts by a cent.** Only with a rate below one cent, and the admin form refuses one.

**5. Export fails past ten thousand rows.** The export caps at ten thousand and the button says so.

**6. The CSV import skips the refund cap.** Same cause as 1 and closes with it.

Proposed: close.

**On go:**

1. Fix 1, 2 and 3 through adhoc, one at a time.
2. Close 4, 5 and 6 in the record.

**Question:** Go?
```

### Replies

- `go` runs every proposal.
- A reply naming one finding and a different route and nothing else (`3 bug`, `4 todo`, "file 3 as a bug") changes that finding's `Proposed:` line, re-shows the whole message and runs nothing until `go`.
- `3 bug, go` changes the line and runs everything in one reply.
- No answer leaves every finding blank. The record already says it was reviewed.
- `N bug` or `N close` settles an unresolved finding, before or after `go`. An unresolved finding left open is never graduated by `go`.
- A proposed close graduates as `review-graduate.sh <record> <N[,N...]> dismissed --by=reviewer --reason="<the one-line reason shown in the message>"`, one call per distinct reason; findings sharing a reason may share a call.
- A close the user sets by reply states the reason in the user's words. With none given, record `--by=user --reason="no reason given"`; never supply a reason on the user's behalf and never ask a follow-up for one.

The message and the answers do not name a widget: show the message, read the reply.

## Running an answer

Run in this order, because the script-backed doors finish in one turn and adhoc runs carry their own questions:

1. Closes, proposed or set by reply, and findings left open. A close graduates with `dismissed`, `--by` and `--reason`.
2. Bug, todo and story doors.
3. Adhoc runs, one at a time.

After each destination exists, graduate the finding to its name through `review-graduate.sh`. All graduation writes go through that script.

### Bug door

Follow `${CLAUDE_PLUGIN_ROOT}/commands/references/bugs-record.md` and the open-pile check in `${CLAUDE_PLUGIN_ROOT}/commands/references/analysis-bug-filing.md`.

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/bugs-list.sh" --status=open` once. On an identical open bug (the same broken behavior in the same place), run `bugs-hit.sh` on its path instead of filing, and graduate to that bug's name.
2. Otherwise file it: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/bugs-capture.sh" --found-during="craft review of <reviewed> (<ref>)" --review=<record name> --stdin`.
3. The body: Symptom as the first line; Expected, Actual, Consequences, Reproduce and Evidence carried over from the finding; `## Blocks my next step` starting `no - found by craft review; nobody was mid-task on it.`; the record path, the finding number and any earlier source story in `## References`; the reviewer's Fix in `## Notes`, labelled a proposed fix.
4. A defect that belongs to an earlier story than the one under review names that story in `## References` as its source.
5. Severity does not travel: a bug record has no severity field.

### Todo door

`bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/notebook-capture.sh" todo "<imperative from the finding title>" --review=<record name> --body-paragraph2="<symptom; record path, finding N>"`, then graduate to the printed file's stem.

### Story door

1. `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/create-story.sh" "<kebab name>" "<title>"` creates it in the backlog and prints its path.
2. Append `review: <record name>` to the story's frontmatter, the Spark from the finding's Symptom and Consequences, and acceptance from Expected and the Fix.
3. Title check: read the title line of the frontmatter back. A title holding a colon must be wrapped in double quotes; wrap it if it is not.
4. Graduate to the story name.

### Adhoc door

Adhoc runs inline. Read `${CLAUDE_PLUGIN_ROOT}/skills/adhoc/SKILL.md` and follow it in this turn, never through the Skill tool: a Skill-tool call ends the turn and control does not come back to the close-out for the next finding.

Before the first run starts, create one task per pending adhoc run, so the close-out survives adhoc's own questions and its gate tasks between runs. Complete each task once its graduation is written (or once the run is known to leave the finding blank).

The brief for each run names:

- the review record's name and path;
- the finding numbers it covers, with their text verbatim;
- "set `review:` to <record name>";
- the earlier source story, when the defect predates the reviewed change;
- the fix the message showed, with its file:line and every path it must cover, not the reviewer's narrower diff.

The flow never opens or edits the review record. When a run hands back, read the record it wrote, in `.craft/fixes/` or `.craft/tweaks/`, and check its `status:`:

- A fix at `validated`, or a tweak at `accepted` or `revised-then-accepted`: graduate every covered finding to that record's `name:`.
- Any other status (escalated, failed, abandoned, not yet validated): leave the covered findings blank. A fix that fails adhoc's confidence check leaves its finding blank.

Then move on to the next pending run.
