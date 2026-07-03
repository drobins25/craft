---
name: craft:notebook
description: "Low-ceremony capture for ideas (half-formed, want to mature into stories), todos (concrete actions), and notes (durable project/team facts for future recall). One-line capture, conditional elaboration AUQ. Use BEFORE thoughts get forced into stories."
when_to_use: |
  EXPLICIT REQUEST (check first): the user names "notebook" or asks to save/capture a note, idea, or todo. That IS the invocation - capture to the craft notebook now. Never divert to Claude Code's native memory or substitute your own dedup judgment for the request; if it overlaps an existing note, capture anyway or ask.

  DEFERRAL MARKER (proactive): "later," "don't let me forget," "side note," "unrelated but," "before I forget," "for next time," "remember to." Absent a marker or explicit request, follow the conversation - do NOT mention notebook; silence is the default.

  OFFER proactively via an ignorable closing line ("Worth dropping in /craft:notebook? Otherwise I'll continue") - NOT AskUserQuestion. On accept, invoke silently with session context.

  NOTE TRIGGER (distinct): a durable, project/team-local FACT future-us would want recalled - settled, currently-true, local to THIS project, reusable; capture the distilled fact, not the event. NOT general knowledge you already hold or transient incidents. Offer only when solidly durable with no expiry.

  Idea-vs-todo: todos are imperative + concrete ("rename X"); ideas speculative ("what if we"). Recall: "what's in notebook?" When ambiguous, ask.

  List triggers: "notebook?", "what's open?", "show my todos."
argument-hint: "[idea|todo \"text\"] or empty for list"
---

# Notebook

Low-ceremony capture for ideas and todos. The upstream of craft's compounding system.

## Project Root

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`. All `.craft/` paths resolve under this root.

## Step 0: Route on First Argument

Inspect the first token of `$ARGUMENTS`. Route as follows:

| First token | Action |
|-------------|--------|
| (empty) | Go to **Step 1: List View** |
| `idea` | Go to **Step 2: Capture Flow** with TYPE=idea |
| `todo` | Go to **Step 2: Capture Flow** with TYPE=todo |
| `note` | Go to **Step 2: Capture Flow** with TYPE=note |
| Anything else that looks like prose (no recognized subcommand) | Go to **Step 3: Disambiguate Idea-or-Todo** |
| `graduate` / `done` / unknown single-token verbs | Output hint, return |

**Hint output for `graduate`, `done`, or unrecognized first-token verbs:**

Print exactly:

```
I handle that conversationally - try saying "turn the X idea into a story" or "mark X done" and I'll do it.
```

Return without taking any other action. **Do not** run any helper. **Do not** show an AskUserQuestion. AC21 prohibits lifecycle action from typed subcommands. The example phrasings are the discoverability surface for users who hit this path - terser hints lose the educational moment.

## Step 1: List View

Run the list helper and read its structured output:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/notebook-list.sh
```

The helper emits key=value records, one per entry, separated by blank lines, with fields `TYPE`, `N`, `FILE`, `DATE`, `SLUG`, `TAGS`, `PREVIEW`.

**If output is empty:** Print exactly:

```
Notebook empty.

Add an idea:  /craft:notebook idea "your idea"
Add a todo:   /craft:notebook todo "your todo"
Add a note:   /craft:notebook note "a durable project fact"
```

Do NOT fire any AskUserQuestion (AC12). Return.

**If output has entries:** Parse the records and render three groups:

```
Ideas
  [1] {DATE} {SLUG} {tags-section}
      {PREVIEW}
  [2] {DATE} {SLUG} {tags-section}
      {PREVIEW}

Todos
  [1] {DATE} {SLUG} {tags-section}
      {PREVIEW}

Notes
  [1] {DATE} {SLUG} {tags-section}
      {PREVIEW}

Commands: idea "text" / todo "text" / note "text"
```

`{tags-section}` rendering rule (AC19):
- If `TAGS` is non-empty, split on `;` and render as space-separated `#tag1 #tag2 #tag3` after one space.
- If `TAGS` is empty, render nothing (no trailing space, no `#`).

Render only sections where the corresponding group has entries. Suppress the "Ideas," "Todos," or "Notes" header if its group is empty.

Footer hint always shows `idea "text" / todo "text" / note "text"` even when only one group has entries. Footer does NOT mention `graduate` or `done` (those are conversational; teaching the typed-subcommand surface would mislead per AC21). Notes never show a `graduate` or `done` affordance at all - they have no lifecycle (see Lifecycle suppression below).

## Step 2: Capture Flow

`TYPE` was determined in Step 0 (`idea` or `todo`). Everything after the subcommand is the candidate text.

### 2a: Resolve capture text

Extract the text from `$ARGUMENTS` AFTER the first token:

- If text is present and non-empty → CAPTURE_TEXT = the verbatim trailing text. Continue to 2b.
- If text is absent or whitespace-only → Use **AskUserQuestion** with exactly one question, no follow-ups:

```yaml
question: "What's the {TYPE}?"   # Substitute: "What's the idea?" or "What's the todo?"
header: "Capture"
options:
  - label: "(type response)"
    description: "Just type the text - I'll capture it."
```

Take the user's free-text response as `CAPTURE_TEXT`. Continue to 2b. AC10 prohibits any further prompt before capture.

### 2b: Run capture helper

Call the helper with the captured text:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/notebook-capture.sh {TYPE} "{CAPTURE_TEXT}"
```

The helper prints the written file path. Hold this as `CAPTURED_FILE`.

### 2c: Conditional elaboration AUQ (AC13)

The elaboration AUQ fires for user-driven captures (this Step 2 path). It does NOT fire for the Claude-driven inline-accept path (Step 4 below).

Inspect `CAPTURE_TEXT` and assess **self-sufficiency**:

- **Self-sufficient** (mark Skip Recommended): all referents are clear, no orphan pronouns ("that thing," "the bug"), the thought is complete on its face. Example: `"call mom Friday"` - Skip Recommended.
- **Not self-sufficient** (mark Add details Recommended): unresolved referents, depends on context that isn't in the body, you held back session context that would help future-you. Example: `"look at that thing"` - Add details Recommended.

**Length is NOT the signal.** A 4-word self-sufficient capture marks Skip; a 20-word ambiguous capture marks Add details. AC13.

Fire **exactly one** AskUserQuestion:

```yaml
question: "Anything to add for future-you, or skip?"
header: "Elaborate"
options:
  - label: "Skip"             # Optionally append " (Recommended)" based on self-sufficiency
    description: "Keep just the verbatim text. No follow-up."
  - label: "Add details"      # Optionally append " (Recommended)" based on self-sufficiency
    description: "Append a second paragraph with context."
```

**On Skip:** Print `Captured {TYPE}: {SLUG}` (derive SLUG from `CAPTURED_FILE` basename without date prefix and `.md`). Return.

**On Add details:** Ask the user for the elaboration in chat (one prompt only, no further AUQ):

> "What context should I add?"

Take the response as `ELABORATION_TEXT`. Re-run the capture with the elaboration appended as paragraph 2, OVERWRITING the file by deleting `CAPTURED_FILE` and re-invoking the helper:

```bash
rm "{CAPTURED_FILE}"
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/notebook-capture.sh {TYPE} "{CAPTURE_TEXT}" --body-paragraph2="{ELABORATION_TEXT}"
```

The new path may differ (same date and base text → same slug, but if the user took >1 day to respond a new date prefix could differ). Print `Captured {TYPE}: {NEW_SLUG}` and return.

Total AskUserQuestion count for user-driven path with text supplied: **exactly one** (the elaboration AUQ). AC1 / AC2.

## Step 3: Disambiguate Idea-or-Todo (AC11)

The user typed `/craft:notebook "some text"` with no `idea` or `todo` subcommand. Extract the full `$ARGUMENTS` as `CAPTURE_TEXT`.

Fire **one** AskUserQuestion:

```yaml
question: "Idea or todo?"
header: "Classify"
options:
  - label: "Idea"
    description: "Half-formed - might become a story."
  - label: "Todo"
    description: "Concrete action - do or graduate."
```

Set `TYPE` from the response. Continue to **Step 2b** (helper run) then **Step 2c** (elaboration AUQ). Total AUQ count for this path: exactly **two** (disambiguation + elaboration). AC11.

## Step 4: Claude-Driven Inline-Mention-Accept Flow (AC17, AC20)

This is the path Claude follows when it has previously offered notebook via inline mention (per the `when_to_use` deferral-marker rule) and the user has accepted ("yeah do it" / "yes" / "capture that" / similar). Claude reaches this step in the SAME conversation turn as the accept (no slash-command boundary).

### 4a: Construct body with session context

- **Paragraph 1:** The user's verbatim utterance (or its core capture-worthy phrase, if the utterance was sprawling).
- **Paragraph 2:** Relevant session context that explains WHY/WHEN the thought arose: current focus area (active story, current cycle), related code/file references being discussed, the work-state that produced the observation.

Example:
- Utterance: "remember to look at the verifier wording - feels too techy"
- Paragraph 1: `look at the verifier wording - feels too techy`
- Paragraph 2: `Came up while reviewing chunk-validator output in cycle 9 oss-readiness work. The "FAILED verdict" terminology may read as harsh to first-time users.`

### 4b: Pick 1-3 session tags (AC20)

Source tags from the active session:
- Active cycle name (e.g., `cycle-9` or `oss-readiness`)
- Active story name (e.g., `notebook-capture`)
- Referenced components/files (e.g., `verifier`, `init`, `story-implement`)

Choose 1-3 tags, lowercase, hyphen-allowed-only. These are session-relevant, not exhaustive.

### 4c: Inline offer line (optional but recommended)

Before invoking the helper, the inline offer line MAY have already mentioned the proposed tags, e.g.:

> "Worth dropping in /craft:notebook? I'd tag it #verifier #cycle-9. Otherwise I'll continue."

This is the OFFER (sent earlier in the conversation by Claude). The user's accept response is what brings flow to Step 4.

### 4d: Invoke capture helper directly (no AUQ)

Run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/notebook-capture.sh {TYPE} "{PARAGRAPH_1}" \
  --body-paragraph2="{PARAGRAPH_2}" \
  --tags="{tag1},{tag2},{tag3}" \
  --source="session {today-date}"
```

(`TYPE` is decided by Claude based on idea-vs-todo signals from the utterance: imperative + concrete → todo, speculative + abstract → idea.)

The elaboration AUQ does NOT fire (AC17). Print exactly **one** brief notification:

```
Captured {TYPE}: {SLUG}
```

Return to the prior conversation focus. The user gets a notification, not an interruption.

## Notes: capture and recall (the third type)

Notes are durable, project/team-local facts whose value is future **recall** - not action. They do NOT graduate and do NOT get "done" (see the Lifecycle suppression note below). The trigger that decides WHEN to offer a note lives in `when_to_use` (the NOTE TRIGGER block, with its two layers and the 7 calibration cases below). This section covers what happens after the offer is accepted (capture) and how a captured note is resurfaced (recall).

### Capturing a note (on accept)

When the user accepts a note offer (or types `/craft:notebook note "..."`), construct the body the same two-paragraph way as Step 4, then call the helper with `note` and a `--facet`:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/notebook-capture.sh note "{DISTILLED_FACT}" \
  --facet={facet} \
  --body-paragraph2="{PROVENANCE}" \
  --tags="{tag1},{tag2}" \
  --source="observed - {how we learned it}, {today-date}"
```

- **Paragraph 1 (`DISTILLED_FACT`)** = the timeless standing fact, present tense, no actor, no date ("Project deploys on Vercel"). NEVER the triggering event.
- **Paragraph 2 (`PROVENANCE`)** = actor + event + date, for verifiability ("Surfaced when Kevin ran the vercel CLI on {date}...").
- **`--facet`** is the recall lever. Pick ONE from the enum: `infrastructure | tooling | ownership | process | convention | gotcha`.
- No elaboration AUQ fires for the Claude-driven accept (mirrors Step 4 / AC17). Print one line: `Noted: {SLUG}`.

### Notes Recall (body on demand)

The session-start hook injects the **notes index** (one line per note) each session - this is the "index in" half of hybrid recall. Treat every indexed line as **"true as of {date} - verify before acting,"** never as undated fact.

When the current work matches a note's facet/topic/tags, READ the full note file from `.craft/notebook/notes/` on demand (the "body on demand" half) and surface it before acting:

> "We have a note - as of {date}, {fact}."

Then act on it. The facet says WHEN a note is relevant to the current moment:

| facet | Resurface when the current work involves... |
|-------|---------------------------------------------|
| `infrastructure` | deploys, builds, env/CI config, hosting, the data layer |
| `tooling` | running a CLI/script, package manager, local dev setup |
| `ownership` | touching a domain a named person owns, or deciding who to loop in |
| `process` | how this team ships/reviews/releases - the workflow around the work |
| `convention` | code style, naming, file layout, "how we do X here" |
| `gotcha` | the matching symptom recurs, or you're about to step on a known trap |

If a recalled note appears **contradicted by current reality**, say so and offer to correct it - update the file in place, or mark it superseded inline (`SUPERSEDED {today}: ...`). Never silently trust a stale note, and never silently overwrite without surfacing the change.

<!--
Calibration ground truth (do not weaken on future edits) - the NOTE TRIGGER in
when_to_use must resolve these 7 cases:
  1. shared staging DB + destructive seed script -> OFFER (durable infra + danger)
  2. "CI red, bad migration, reverting" -> NO note for the incident; note only a reusable technique if one surfaced
  3. recovered a commit via git reflog -> NO note (general knowledge I already hold)
  4. "Sarah is the only one who understands billing - loop her in" -> OFFER (ownership)
  5. "drifting toward Tailwind, nobody made it official" -> NO note (not settled)
  6. "needs Node 20, 22 breaks native deps" already in unread CONTRIBUTING.md -> OFFER (documented-in-repo does NOT disqualify; only already-known does)
  7. "legacy auth until ~Q3, no ticket or owner" -> NO proactive offer (below Layer-2 bar: provisional/vague expiry)
-->

## Lifecycle Trigger Framework (Conversational graduate / done)

Lifecycle operations (`graduate`, `done`) are NOT user-typed subcommands in v1. They run conversationally: Claude detects intent in the user's utterance and runs the helper scripts directly. This section documents the trigger heuristics, confidence tiers, confirmation pattern, and disambiguation rules.

**Lifecycle applies to ideas and todos ONLY - never notes.** `graduate` is an idea operation (idea -> story); `done` is a todo operation (todo -> done/). Notes are durable reference, not work: they have no `status`, never graduate, and never get marked done. Never offer or fire either operation against a note, at any confidence tier. The list view shows no lifecycle affordance for the Notes group. (Mirrors AC21's "no typed subcommand" discipline - notes simply have no lifecycle to invoke.)

### Graduate flow (AC5, AC22)

**Triggers - BOTH must be present:**

1. **Lifecycle verb** (any of):
   - "turn into a story"
   - "make a story" / "make this a story" / "make that a story"
   - "graduate"
   - "move to backlog"
   - "that's ready to build"

2. **Specific or deictic reference:**
   - Explicit name: "the compounding kb idea"
   - Deictic ("that idea," "this one") AND recent context unambiguously identifies which entry

**Confidence tiers:**

| Tier | Trigger shape | Action |
|------|---------------|--------|
| HIGH | Explicit verb + named ref ("graduate the compounding kb idea") | Inline offer with named referent. Execute on accept. |
| MEDIUM | Verb + deictic ref ("make that a story") with recent context | Inline offer naming what you think "that" is. Execute on accept. |
| LOW | No lifecycle verb; OR verb with no plausible referent ("that kb idea is interesting") | NO action. Continue the conversation normally. |

**LOW boundary is strict.** Vague positive sentiment ("that's a good idea," "I like that") is NOT a graduate signal. Future-leaning ("we should make that a story someday") is NOT a graduate signal.

**Inline offer pattern (non-blocking):**

```
Graduate 'compounding kb idea' to a story? I'll run /craft:craft-story-new with it as the spark.
```

The user can ignore the line. On accept ("yes," "do it," "go ahead"):

1. Read the idea file's body
2. Invoke `/craft:craft-story-new` via Skill tool with the body pre-populated as the spark seed
3. On story-new success, run:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/notebook-graduate-mark.sh "{idea-file}" "{new-story-slug}"
   ```
4. Print: `Graduated '{idea-slug}' → story '{story-slug}'.`

All steps happen in ONE Claude turn. The idea file remains in `.craft/notebook/ideas/` with frontmatter updated (`status: graduated, graduated_to: {story-slug}`).

### Done flow (AC6, AC23, AC25)

**Triggers - BOTH must be present:**

1. **Past-tense / affirmative-closure language** (any of):
   - "I took care of it" / "I took care of the X"
   - "already did that" / "already handled X"
   - "crossed that off"
   - "that's done" / "X is done"
   - "handled" (as completion claim)

2. **Reference to a specific todo** (named or deictic with recent context)

**Future-leaning language is NEVER a done trigger:**
- "I'll get to that" - NO
- "yeah maybe later" - NO
- "I should do that" - NO
- "I'll handle it" - NO

Discriminator: **tense + agency**. Did the user state it's ALREADY finished, or that they intend to?

**Confidence tiers:**

| Tier | Trigger shape | Action |
|------|---------------|--------|
| HIGH | Explicit closure + named ref ("I took care of the verifier todo") | Fire done AUQ with named referent. |
| MEDIUM | Closure + deictic ref ("that's done") | Fire done AUQ naming what you think "that" is. |
| LOW | No closure language, OR no referent | NO action. |

**AUQ fires EVEN at HIGH confidence (AC23, AC25).** The asymmetric failure visibility justifies the two-second confirmation cost: a silent false-positive done moves the file to `done/` where the user may never notice. Two weeks later they realize it wasn't actually done and there's no record it was ever in the active notebook.

**AUQ pattern (blocking):**

```yaml
question: "Mark 'rename verifier error wording' as done?"
header: "Done"
options:
  - label: "Yes"
    description: "Move to todos/done/ and flag the file."
  - label: "No"
    description: "Leave it open."
```

On **Yes**, run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/notebook-done.sh "{todo-file}"
```

Print: `Marked done: '{todo-slug}'.`

On **No**, take no action. Return to conversation.

### Named-referent disambiguation (AC24)

For BOTH graduate and done, Claude states the entry NAME in the offer/AUQ - never just "that" or "it":

- **Single match:** Name it explicitly. ("Graduate 'compounding kb idea' to a story?")
- **Multiple plausible matches:** Ask WHICH ONE first via AskUserQuestion, options labeled by entry name:

  ```yaml
  question: "Which todo do you mean?"
  header: "Pick one"
  options:
    - label: "rename verifier error wording"
      description: "[date] [slug]"
    - label: "audit verifier output for first-time users"
      description: "[date] [slug]"
  ```

  Only after the user picks does the graduate/done offer/AUQ proceed.

- **Zero matches:** Say so explicitly and take no destructive action:
  > "I don't see a todo matching 'verifier' - want me to capture one?"

**Silent guessing on lifecycle ops is prohibited.** AC24.

### Silent false-positive done prohibition (AC25)

If the user mentions past-tense completion in passing while the conversation focus is elsewhere (e.g., "yeah I fixed the verifier thing" mid-discussion of something else), Claude does **NOT** silently mark the relevant todo done. Either:

- The trigger heuristic is satisfied → fire the done AUQ with named referent.
- The trigger heuristic is NOT satisfied (e.g., the reference is too oblique to ground to a specific todo) → take **no** action.

The silent-mark-done path does NOT exist at any confidence level. AC25.

## Not to be Confused With

- **`TaskCreate`** - In-session task tracking, ephemeral (this conversation only). Notebook todos persist across sessions and survive cycle completion. Different lifetimes, different tools.
- **`/craft:craft-story-new`** - For thoughts that are already story-shape with a clear acceptance shape. Notebook captures things that are NOT yet story-shape.
- **`/craft:adhoc`** - For known bugs or small tweaks to act on NOW. Notebook todos are deferred intent items, not act-now work.
- **`.craft/design/locked.md`** - For decisions that constrain future work. Notebook ideas are unconstrained explorations.
