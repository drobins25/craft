# Chunk Format Guide

This is the required format for planned stories: the Investigation, the Pitch, and the chunk specs produced during Phase 3 (Chunk Planning).

**The standard:** A plan locks the **seams** - contracts between chunks, between layers, and with existing code - and leaves the **interiors** to the implementer. Every binding claim carries evidence. The plan is done when a skeptical reviewer probes it and walks away with "...that's all."

**The litmus test:** Could two competent implementers build from this plan independently and not conflict at the seams? Seams are what plans must lock. Interiors are what implementers own.

---

## Story-Level Sections

A planned story adds two sections beyond the chunks. Both are required.

### `## The Pitch` (replaces `## Delivery`)

Placed directly after `## Spark`. Two parts:

1. **The sell** (2-4 sentences): why this plan works - mechanically, not aspirationally. A pitch you wouldn't buy is a plan that shouldn't be approved, before anyone reads a single chunk.
2. **The conditions table**: every load-bearing assumption the guarantee stands on, each tagged with how it's secured.

```markdown
## The Pitch

Ship this and the countdown can't lie and the button can't betray - not because
we were careful, but because we made other systems responsible: the date is
ILS-owned so drift is impossible by construction, "once" is ILS-enforced so we
can't fork its truth, and auth is the existing middleware so there is no new
surface.

**This plan stands on:**

| Condition | Secured by |
|-----------|-----------|
| `holdDeadline` is ILS-owned; local writes would be overwritten | verified - traced all writes, only `jobs/ils-sync.ts` touches it |
| ILS API accepts `PATCH /holds/{id}/pickup-by` | unverifiable by reading - becomes Chunk 1's FIRST test |
| Auth middleware covers account mutations | verified - `requirePatron` guards all 3 existing PUTs in `routes/account.ts` |
```

**Rules for the conditions table:**
- Every condition is tagged `verified - <evidence>`, `system-owned - <who>`, or `unverifiable by reading - becomes Chunk N's FIRST test`.
- A condition that can't carry one of those tags is not a condition - it's a hole. Go back.
- An unverifiable condition MUST become the named chunk's first test, before anything is built on it. The plan's weakest point gets attacked first, by construction.
- **The conditions table is the implementer's tripwire watchlist.** The implementer doesn't watch everything; it watches these.

### `## Investigation` (the planner's narrative)

Placed directly before `## Chunks`. The causal record of how the plan was found - the planner's headspace, so the implementer (and any future re-planner) inherits the reasoning, not just the conclusions. First person is fine. Write it as it happened:

```markdown
## Investigation

Read the ticket as possibly-a-bug - "show a countdown" sounds like it might
already exist. Searched the repo for "Pick up by" - nothing. Searched for
hold-related UI - found AccountPage.tsx, renders hold rows, no deadline. So:
new feature, existing surface.

AccountPage gets data from UserAccountService.getHolds(). Read it - already
returns holdDeadline. But the service is GET-only. Asked WHY before planning a
PUT: traced writes to holdDeadline - nothing in this repo writes it - found
jobs/ils-sync.ts, a nightly mirror from the library's ILS. This repo does not
own this date. A local PUT would be silently overwritten by tomorrow's sync.
Ruled out: writing holdDeadline locally.

Asked the user: hardcode the 2 days? -> Yes, hardcoded. Button placement? ->
In the hold row, site-standard secondary button.

Dead ends kept: searched for an existing countdown component - none, but
RelativeDate at components/shared/RelativeDate.tsx is 80% of it. No test
patterns in jobs/ - out of scope, the ILS client tests are the pattern to mirror.
```

**Rules for the Investigation:**
- **Causal, not inventory.** Each step motivates the next ("found X, which raised Y, so read Z"). A list of files read is not an investigation.
- **Dead ends stay in.** "Searched for it, found nothing" is load-bearing - it records what was ruled out. A suspiciously clean narrative with no wrong turns is itself a fabrication signal.
- **Absence is evidence.** Every missing thing the plan builds (endpoint, column, config) needs a stated theory of why it's missing. "Nobody needed it yet" is acceptable; "it's a fence" changes the plan.
- **Ownership is the floor.** "The field exists" is never the bottom of an investigation. "I know who writes it, and what happens to my write tomorrow" is.
- User questions asked during planning and their answers are recorded here.
- **Size: typically 10-30 lines.** A narrative that outgrows ~40 lines is usually a story that should split - the sprawl is the signal, not a writing problem.

---

## Required Chunk Template

```markdown
### Chunk [N]: [Descriptive Name]

**Goal:** [Specific outcome - not vague]

**Files:**
- `src/routes/account.ts` - modify (new PUT route)
- `src/services/UserAccountService.ts` - modify
- `src/services/__tests__/UserAccountService.test.ts` - create

**Contracts:** (binding - these are the seams; match exactly)
- `IlsClient.extendHoldPickup(holdId: string, newDate: IsoDate)` [owner: Chunk 1 - cite its real signature at implement time, not this line]
- New route `PUT /api/account/holds/:holdId/extension` [verified: read routes/account.ts - all four existing routes use plural/:id shape]
- Auth via existing `requirePatron` middleware [verified: it guards the 3 existing account mutations; no new auth surface]
- Response is the refreshed hold from the ILS payload - never locally computed [investigation: ILS owns this data; local math is the silent-failure trap this plan routes around]
- 409 when ILS reports `extensionCount >= 1` [investigation: "once" is ILS-enforced; we translate, never track]

**Approach:** (advisory - the interior is yours)
- Service method beside getHolds(), same DI pattern
- +2 days via addDays from lib/dates.ts, library-local timezone

**Test cases:** (write these, assert this - bodies are yours)
- "returns refreshed hold on success" - deadline comes from the ILS response, not local math
- "surfaces 409 when already extended"
- "rejects unauthenticated with 401"
- "ILS failure -> 502, no local state change"

**What Could Break:**
- [resolved] Route collision with /holds/:id - checked, no existing extension route
- [escalated to conditions] ILS PATCH availability - Chunk 1's first test

**Done When:**
- [ ] Endpoint live behind auth
- [ ] Build passes and all tests pass
```

### Section rules

**Contracts** - the binding section. Each line is a seam: a signature, a shape, a route, a name, an integration point, an invariant. Each line carries exactly one receipt:

| Receipt | Meaning |
|---------|---------|
| `[verified: <what was checked and what would have falsified it>]` | Attacked against existing code during investigation. The receipt is attack residue, not attestation - "I tried to kill this and here's what would have killed it." |
| `[owner: Chunk N]` | The contract's truth is produced by an earlier chunk. By implement time it's real, compiled code - cite IT, not this line, if they differ. |
| `[investigation: <one-line reason>]` | Backref to the narrative - the reasoning this contract protects. The implementer uses this to judge mismatches: does a deviation break the *reason*, or just the coordinates? |
| `[defines]` | A new seam this chunk creates - a name, route, or shape with no prior reality to verify. Authoritative from this chunk on; later chunks cite it via `[owner: Chunk N]`. Greenfield stories are mostly `[defines]` - that's correct, not a gap. |

A contract about *pre-existing reality* that can earn no receipt goes in the Pitch's conditions table as unverifiable - it does not ship as a bare assertion.

**Mutation contracts carry their unit and their readers.** A contract for any state-changing write declares the key it writes under ("completion is per schedule-occurrence `(workout_id, scheduled_date)`, not per workout") and receipts its read sites ("[verified: read by CalendarView.tsx:31 and AccountPage.tsx:84 - both rebuild from the refreshed payload]"). An undeclared unit is an invisible assumption - and invisible assumptions are the one thing receipts can't attack.

**Approach** - advisory prose. Pattern pointers by `file:line`, ordering, gotchas. **No code blocks** - with one exception: when the code IS the decision (an exact regex, a migration statement, a non-obvious one-liner where ambiguity is dangerous). Decision-code carries a receipt like any contract.

**Test cases** - names plus what they assert. No bodies. The implementer writes bodies during TDD, where they get verified by running - not authored as fiction in a markdown file.

**What Could Break** - every entry is `[resolved]` (checked dead during planning, say how) or `[escalated to conditions]` (now in the Pitch table). A bare risk bullet that is neither resolved nor escalated is an unfinished thought.

**Amendments** - when implement-time reality contradicts a contract and the fix is approved, the delta is recorded in the chunk under an `**Amendments:**` heading (date, what changed, what the original receipt missed) - the contract line is never silently edited. The plan stays honest about what it got wrong; the amendment trail is how future planning learns which receipts fail.

---

## Cutting Chunks: the Ladder

Navigate top-down to find the seam; build bottom-up from the furthest-upstream fact the story touches.

- **Chunk boundaries sit at layer rungs** (data -> types -> service -> endpoint -> UI, or whatever ladder this story actually has). The rung interfaces ARE the contracts - they fall out of the cut instead of being invented.
- **Later chunks cite earlier chunks' output** via `[owner: Chunk N]`. By implement time the citation points at real, tested code - the ladder is the staleness-proofing.
- **Chunk 1 sits where speculation lives.** Pre-existing code contracts and any unverifiable condition land in the earliest chunk that can test them. The plan's weakest assumption is the first thing reality gets to vote on.
- A one-rung story is fine. Discover that honestly ("where does the data come from?" -> it's all right here) and cut one or two chunks. Do not manufacture rungs.

---

## Green-Tree Requirement

Every chunk's **Done When** must include at least one criterion asserting the project compiles and all tests pass at the end of the chunk ("Build passes and all tests pass"). Plan validation rejects any chunk whose Done When lacks one.

This is a planning constraint, not a checkbox to append. Cut chunk boundaries so the criterion can actually be true: a rename or symbol removal and every reference to it - including test files, mocks, and fixtures - belong in the same chunk. A plan that defers compilation across a chunk boundary ("do not build between Chunk 1 and Chunk 2") is invalid; merge or re-cut the chunks, or flag the story for splitting.

Exempt: chunks that modify no source files (all Files entries `read-only`, or a Goal that touches only docs).

---

## Quality Gates (run before presenting the plan)

1. **The seam test** - for each chunk: could two competent implementers build this independently and not conflict at its boundaries with other chunks and with existing code? If a conflict is possible, a contract is missing. If a contract dictates an interior (HOW a function's body works, what a test body contains), it's overreach - move it to Approach or delete it.

2. **The receipt audit** - every contract line carries a receipt; every receipt-less claim is in the conditions table; every unverifiable condition is some chunk's first test. Run the narrative check: is the Investigation causal? Are the dead ends still in it? Too clean is a finding.

3. **The Miranda pass** - model the specific skeptic who receives this plan (the user at triage; the reviewer who gets sent in afterward). Write down the five questions they will ask. Each must already be answered *in the artifact* - in the Investigation, a contract receipt, or the conditions table. Not answerable: answered. The plan is done when that review walks out with "...that's all."

---

## Bad → Good Example

**BAD (old style - implementation written as fiction):**
```
**Implementation Details:**
- Import Card from src/components/ui/Card - <Card variant="outlined"> takes {title, children}
- Zod schema: z.object({ email: z.string().email(), password: z.string().min(8) })
- Submit: api.auth.register(data) - handle 409 with if (err.status === 409)
- [40 more lines of code the implementer will transcribe without verification]
```
Looks rigorous. Nothing in it was compiled, nothing was run, and the implementer is told to copy it even where it's wrong. Plausibility masquerading as verification.

**GOOD (contracts + receipts; interior left to the implementer):**
```
**Contracts:**
- `Card` from src/components/ui/Card, props {title: string, children: ReactNode, className?} [verified: read Card.tsx:8-15; no "outlined" variant exists - that was in the mockup but not the component]
- Registration via `api.auth.register(data)`, 409 = email taken [verified: read lib/api.ts:89; 409 is the only conflict the server emits]
- Reuse `PasswordStrength`, props {score: 0-4, showLabel?: boolean} [verified: read PasswordStrength.tsx:8; score is required, not optional]

**Approach:**
- Form layout follows LoginForm.tsx:45-62 (FormField -> Label -> Input -> ErrorMessage stack)

**Test cases:**
- "rejects mismatched password confirmation before submit"
- "surfaces email-taken error from 409"
- "disables submit while request is in flight"
```
Note the first receipt *caught a planning error* ("no outlined variant exists") - that's what receipts are for. The attack residue does the verifying that fake code only performed.

**The exception - code that IS the decision:**
```
**Approach:**
- Strip block comments before any parsing: `css.replace(/\/\*[\s\S]*?\*\//g, '')` [decision: comment syntax inside values would corrupt naive parsing; this exact pattern is the choice]
```
An exact regex, a migration statement, a tricky one-liner: when ambiguity is dangerous, the code is a contract and carries a receipt like one. This is rare. If most of a chunk is decision-code, the chunk is probably dictating interiors.

---

## Why This Matters

The implementer is autonomous, but it is not a transcriber - it reads the Investigation, holds the contracts as law, owns the interiors, and watches the conditions table. When reality contradicts a contract, finding that mismatch is a *deliverable*, not a failure: the plan gets amended with the delta, instead of code quietly improvised around a broken assumption.

**Planning is where the seams get locked and attacked. Implementation is where interiors get built and contracts meet reality.**

The plan failed only if the reviewer finds what the planner should have - or if two implementers could read the same chunk and ship conflicting seams.
