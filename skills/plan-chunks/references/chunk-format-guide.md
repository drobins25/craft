# Chunk Format Guide

The shape of a planned story. The planner writes it; the user approves it by reading it; the implementer builds one chunk at a time from it. Write for all three: short enough to read, exact wherever two pieces of code have to agree.

## The story sections planning adds

### `## The Pitch` (right after `## Spark`)

Two to four sentences on why this plan delivers the Spark, then the conditions it stands on: the things that could turn out false. The implementer watches these hardest.

```markdown
## The Pitch

Recent files show up the moment the picker opens, newest first, because the list is read
from the editor's own history file instead of being tracked a second time. Nothing new
has to stay in sync: the editor writes the history, the picker only reads it.

| Condition | Secured by |
|-----------|------------|
| The editor appends to `history.jsonl` on every open | verified - read `editor/history.ts:22`, the only writer |
| History lines can be partial while the editor is mid-write | unverifiable - becomes Chunk 1's first test |
| The picker runs once per keypress, so reads must stay fast on a large history | system-owned - picker caps input at 200 lines (`picker.ts:15`) |
```

Tag every row `verified - <what you checked>`, `system-owned - <who guarantees it>`, or `unverifiable - becomes Chunk N's first test`. In batch only, an outside fact three searches did not settle takes a fourth tag, `unverifiable class claim - research request raised`; triage turns it into `verified - research: <slug> -> "Convergence Points"` or a ruling by the user before the plan is approved. A dependency that fits none of those is a hole in the plan; go back and close it.

### `## Acceptance`

Specific, checkable, about what the user gets. "The picker lists the 10 most recent files, newest first, and opens instantly with an empty history" - not "recent files work".

### `## Chunks`

## The chunk template

```markdown
### Chunk 1: Read recent files from the editor's history

**Goal:** A `recentFiles()` function returns the newest distinct files from the editor's history, and survives whatever the history file holds.

**Files:**
- `src/picker/recent.ts` - create
- `src/picker/__tests__/recent.test.ts` - create

**Contracts:**
- `recentFiles(historyPath: string, limit: number): RecentFile[]` (new)
- `RecentFile = { path: string; openedAt: number }` (new; Chunk 2 renders this)
- History lines are JSON `{ "file": string, "ts": number }`, one per line (checked: `editor/history.ts:22` writes exactly this)
- Missing history file means "no recent files", never an error (new; first-run users have no history)
- At most `limit` entries come back however long the history is (new; the picker draws one row per entry)

**Not covered:**
- The editor never trims `history.jsonl`, so it grows without limit. Left out because the fix lives in `editor/history.ts`, outside this story's files; this chunk's own read stays fast on a long history (the 50,000-line test).

**Approach:**
- Read the file once, parse line by line, skip lines that fail to parse rather than failing the whole read.
- Follow the file-reading pattern in `src/picker/bookmarks.ts:10-30`.

**Test cases:**
- "returns newest first, one entry per file" - two opens of the same file count once, at the later time
- "missing history file returns an empty list" - the first-run state
- "skips a half-written last line" - the editor can be mid-write while we read
- "file names with spaces, unicode and newlines come back unchanged" - names come from the user's disk
- "a 50,000-line history returns in under 50 ms" - real histories grow, and the picker reads on every keypress

**Run:**
- `npx vitest run src/picker/__tests__/recent.test.ts`
- `npx tsc --noEmit`
- `npx vitest run`

**Done When:**
- [ ] All named tests written, seen failing once, and passing
- [ ] Every Run command passes
```

### What each part is for

- **Goal** - one outcome, stated so you can tell when it is true.
- **Files** - one line per file in the form `` `path` - action `` with a plain dash, because the build loop splits on it. The action is `create`, `modify` (and what changes) or `read-only` (a file to read and leave alone).
- **Contracts** - anything that has to come out one particular way: what other code has to agree on (names, signatures, shapes, formats, who owns what) and what a user or another program sees (wording, order, limits). The builder writes its tests' expected values from these lines. Each carries its source in a few words (`checked: <file:line or what you read>`, `new`, or `from Chunk N`) and its reason when that is not obvious. Interiors (function bodies, test bodies, anything only this chunk's own code touches) are the implementer's; leave them out. More than about ten lines here means the chunk should split or is dictating its interior.
  When the code can fail in a way a user or another program sees, one contract line says what failure looks like: exit status, where the message goes, and its wording if anything matches on it.
- **Not covered** - optional. A risk research found whose fix lies outside the files this story creates or modifies, or that the story itself rules out, saying which and where. A risk those files could guard against is a contract and a named test instead. It is there so the builder and the user both see it; a risk left off the page is one nobody decided about.
- **Approach** - optional advice: the local pattern to follow, an order that avoids a trap. Prose, not code.
- **Test cases** - each test named for a behavior and what it proves, one line each, with the number or the exact text when the result has one. Not only the happy path: the resting state, and every answer from research that became a test.
- **Run** - the commands that show this chunk left the project building and tested, in the order to run them: this chunk's tests; the type check, when the project has one that covers these files; and the full suite, when it finishes in a few minutes. The builder runs each and quotes the result. Nothing else runs them before the next chunk starts, so a chunk that breaks an earlier chunk's test is caught here or not until the story ends.
- **Done When** - checkable items, always including that every Run command passes. A chunk that changes only docs or prompts says what content must have landed instead, and needs no Run.

Code in a chunk is allowed only where the exact code is the decision (a regex, a format string); say why that exact form matters.

For UI stories, each element in the story's Visual Direction binding table gets its token as a Contract line in the chunk that builds it, ending in a `[visual-source: <tokens.yaml key, mockup anchor, or binding table row>]` receipt; the checker looks for that receipt.

### Risk Tag Authoring Rule

A story's `## Risk Tags` each carry a `#` comment. When you turn a tag into a criterion, name the mechanism the comment gives (or the locked rule it cites), and use any number only as the check on that mechanism. "Interactive elements extend their hit area with padding, not a min-height on the visual element; verify every computed target is at least 44px" is a criterion. "Touch targets >=44px" is not, because it tells the builder what to measure and nothing about what to build.

## When reality disagrees with the plan

If the implementer finds a contract is wrong, it stops and reports a `## CONTRACT MISMATCH`. The orchestrator records the approved fix under an `**Amendments:**` heading in that chunk (date, what changed, what the plan missed) instead of silently editing the contract line.
