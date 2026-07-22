# Adhoc Tweak Flow (reference - read inline by the craft:adhoc shell)

<!-- DO NOT SIMPLIFY THIS SCHEMA. Tweak records are mined by a future graduation
     pass that clusters them (by kind, surface, attempts, verbatim reactions) into
     project-level skills - the way fix records graduate into rules, tweak records
     graduate into taste. Every field below exists to serve that pass. Dropping a
     field or paraphrasing user reactions destroys the signal. -->

This is the TWEAK flavor: nothing is broken - something works as built, and the user wants it different. A different icon, tighter spacing, calmer wording. The gate here is not root-cause confidence ("will it work") but **fit** ("will it fit"). The shell has already classified the request, opened the write gate, and created the close-obligation tasks - this file owns the tweak record, the Fit Check, the attempt loop, and the close-out. Hand back to the shell for each commit and the final gate close.

The word "enhancement" never appears in tweak filenames or frontmatter values - "tweak" is the term, everywhere. This keeps the corpus fully separate from craft:analyze's `enhance-*` proposal records: those are agent-generated ideas; these are user-driven changes with real reactions attached.

## Step 1: Create the Tweak Record

**Check for a matching move first:** before treating the request as novel, glance at recent records - `grep -l "kind: [matching-kind]" .craft/tweaks/*.md` and skim by `created:` date. If an accepted tweak already made this same move on another surface, this is a REAPPLICATION: set `reapplies:` to that record's name (see below). Reapplied moves inherit a proven direction, and the backlink count is the graduation signal.

Create `.craft/tweaks/` if it doesn't exist, then write the record:

```bash
mkdir -p "${CRAFT_PROJECT_ROOT:-.}/.craft/tweaks"
```

Write to `.craft/tweaks/tweak-[descriptive-slug].md`:

```markdown
---
name: tweak-[descriptive-slug]
status: open
created: [YYYY-MM-DD]
project: [project name]
surface: [free-text kebab slug for WHERE in the product, e.g. settings-toolbar]
kind: [icon | copy | spacing | color | motion | content]
source_story: [story that built the element, if known]
mockup: [name of the converged mockup this tweak ports, e.g. 2026-07-05-hero-pulse - empty for non-mockup tweaks]
reapplies: [name of the original tweak this reapplies, e.g. tweak-toolbar-stroke-weight - empty for a novel tweak]
grew_from: [name of the origin tweak this outcome grew from - empty except taste-pass outputs]
satisfied_todo: [stamped by the todo-satisfaction beat - <todo-slug> or none-matched]
taste: [loved | routine - stamped at close-out; empty until then]
attempts: 0
outcome_note:
files_changed: 0
lines_changed: 0
---

## Request
[The user's ask, close to verbatim. "Different icon than what we added - something more like a hammer"]

## Fit Check
[Filled in Step 2]
```

**`surface`:** before minting a new slug, check the existing records - `grep -h "^surface:" .craft/tweaks/*.md | sort -u` - and reuse a matching slug. Consistent surfaces are what let the future mining pass cluster ("five tweaks on settings-toolbar").

**`kind`:** exactly one of `icon | copy | spacing | color | motion | content`.

**`reapplies`:** backlink to the original tweak when this record applies an already-accepted move to a new surface. Every reapplication gets its OWN record (one file per surface - records never bloat with multi-surface history); the shared `reapplies:` value is what ties the family together. The count of records naming the same original is the graduation vote: a move applied in several places is a standard waiting to be written down (tokens.yaml for value kinds like spacing/color, locked.md via lock-decision for patterns - the graduation pass consumes this).

**`grew_from`:** lineage backlink to the origin tweak this outcome grew out of - always recorded when a tweak was born from a taste-pass propagation, however far the result diverged from the seed (a button move that snowballed into a whole page still traces home). Distinct from `reapplies:`, which is the narrow literal-replication case; `grew_from:` is the broader "this exists because of that" link. Empty for ordinary tweaks; only ever written on taste-pass outputs.

**`taste`:** the close-out sentiment stamp - `loved` when the user loved a spreadable visual change, else `routine`. Empty until the close-out writes it. A token-free script counts the `loved` records to know when enough proven taste has accrued to offer a propagation pass; the stamp is judged by eye once and read by script forever, so this field is the counter's sole input - never re-derive taste from the record body.

**`status` lifecycle:** born `open`, stays `open` until the user explicitly closes it - `accepted` (first attempt landed), `revised-then-accepted` (took 2+ attempts), `abandoned` (user dropped it), or `escalated` (became a story/design question). **Validation passing never closes a tweak. Only the user's reaction does.** A later conversational decline also abandons an open record - name it explicitly before writing ("Closing `tweak-settings-icon` as abandoned"), never guess which record the user means when more than one is open.

## Step 2: Fit Check

Before editing anything, answer "will it fit?" - the tweak equivalent of the fix flow's confidence check:

1. **Survey the neighborhood.** What sits next to this element - same row, same toolbar, same card? Read the surrounding component code; for UI, screenshot the surface as it is now (this is also your before-shot - if the shell already took a classification screenshot, reuse it, don't re-take).
2. **Match the visual family.** An icon next to existing icons should mirror their language: stroke vs filled, weight, corner radius, metaphor register. Copy should match the surrounding voice; spacing should follow the established rhythm.
3. **Check the design contracts.** Read `.craft/design/tokens.yaml` and `.craft/design/locked.md` - does the change use existing tokens and respect locked decisions? Also glance at `.craft/quality.yaml`'s standards (touch targets, contrast). A conflict with tokens.yaml or quality.yaml is noted SILENTLY in the Fit Check section as a pending reconcile payload - never interrupt the user mid-tweak over it; it gets its one question at acceptance (see Acceptance reconcile, Step 3). A conflict with a locked decision routes through the pre-edit branch below, before anything is edited. This Fit-Check note only PRE-SEEDS the token reconcile - it is not the sole detection point: tokens are re-derived from the FINAL accepted values at acceptance regardless (Step 3), so a token drift that was absent or matching here and only emerged as attempts progressed is still caught.

Write the findings into the `## Fit Check` section: where the element lives, what its siblings look like, which conventions apply, and how the requested change fits them.

**Todo satisfaction detection (always-on):** in the same beat, run the shell's `## Todo Satisfaction Detection` (SKILL.md) - one `notebook-list.sh todos` call, a semantic match of this tweak's request/surface against the open todos, named-referent discipline by arity. **Zero matches:** stamp `satisfied_todo: none-matched` in the record frontmatter immediately and move on - nothing is said. **On a match** (after the disambiguation AskUserQuestion if multiple): write the pending match - the todo's file path and slug - into the `## Fit Check` section itself, so it survives a multi-attempt loop; the close-out reads it from the record, never from conversational memory. The close consent rides Step 3's acceptance ask - detection here asks the user nothing beyond multi-match disambiguation.

**Lock conflict (pre-edit):** if the requested change would break a locked decision, do NOT edit yet. The tweak is the user's taste showing up live - the lock may be what's stale. Present a recommendation: alter the lock, remove it, or reshape the tweak to fit it - whichever the neighborhood evidence supports. On the user's explicit yes, update locked.md FIRST via the inline lock-edit path below, then proceed with the tweak - the edit never exists in a lock-breaking state. On decline, fall back to escalation: update `status: escalated`, tell the user why, and suggest a mockup first (the direction needs to be seen to be decided), or design-vibe / a story for bigger questions. Hand back to the shell to close the gate. (Mention the option; do not invoke another skill from inside this flow.)

**Escalation (design question):** if the fit check surfaces a genuine design question (multiple plausible directions and no clear fit) - do NOT edit. Same mechanics as the decline path above: update `status: escalated`, say why, suggest a mockup first (the direction needs to be seen to be decided), or design-vibe / a story for bigger questions, hand back to the shell.

**Mockup-ported tweaks:** when the handoff brief states "direction pre-settled, converged mockup at [path]", set the record's `mockup:` field, skip re-opening exploration in the Fit Check (the mockup already settled the direction - the check verifies fit of the PORT, not of the idea), and treat mockup.html's CSS as normative: port values verbatim, never reinterpret from appearance. **If the handoff also names an `origin` (the mockup grew from a taste-pass todo), stamp this record's `grew_from:` with it** - leave `grew_from:` empty when there is no origin; use `reapplies:` instead only if the outcome was a literal copy of the origin move. This is the read side of the lineage: without it, a taste-pass outcome that snowballed into a mockup and graduated back to a tweak would silently lose its home, however far it diverged from the seed. **When the handoff forwards a materials spec (the record's `## Materials` was non-empty), acquiring that material through the project's idiom is part of the port** - name it in the tweak's presentation so the acceptance ask covers the project change. The mockup's inlined base64 is never ported as the acquisition; an icon entry means adopt the library's components. Type values still port verbatim - only where the font file comes from is resolved against the project.

### The inline lock-edit path

Two reconcile moments may alter or remove a locked.md entry: the pre-edit branch above, and the Acceptance reconcile in Step 3. The rules, defined once:

- **Explicit yes only.** "yes", "lock it", "go with that" - an explicit yes. Hedged agreement ("that could work"), agreement carrying an open question, or thinking out loud NEVER updates locked.md.
- **Edit locked.md directly, in its existing format** - alter the entry or remove it. Same discipline as the lock-decision skill, none of the ceremony: never run lock-decision's unlock-ceremony AUQ from inside a tweak thread. One clean yes, zero extra questions.
- **A lock gets at most ONE write moment per tweak thread** - at the pre-edit branch (conflict known at the brief) or at the Acceptance reconcile (conflict emerged mid-pass). Never per attempt: attempt-level agreement is exploration, not settled taste, and locked.md never records mid-pass wobble.

## Step 3: The Attempt Loop

Each attempt appends a block to the record:

```markdown
## Attempt [N]
### Change
[What was edited, which files, and how the fit check shaped the choice]
### Validation
[Tests/build result; for visual tweaks, before/after screenshots - the after-shot doubles as the fit-check receipt]
### Reaction
[The user's response, VERBATIM]
```

Per attempt:

1. **Mid-pass lock pivot check.** When the user's reaction changes the brief's direction ("actually, make it sharper"), re-screen the NEW direction against locked.md (already in context from the Fit Check) before editing. If it crosses a lock the brief didn't: say ONE ignorable line - "that crosses the [X] lock; trying it anyway - we'll settle the lock if this is what you accept" - and proceed. No question, no AUQ, and NO locked.md write mid-pass; the lock settles once, at the Acceptance reconcile. Direction unchanged, or no lock crossed → silence.
2. **Change.** Make the edits with Edit/Write. Increment `attempts`, update `files_changed` / `lines_changed`.
3. **Validate.** Run the project's tests/build. For anything visual, use the browser: navigate to the surface, take the after screenshot, and confirm the change landed as the fit check intended. Record it in the attempt's Validation.
4. **Commit.** Hand back to the shell's commit step (manifest staging, `tweak:` prefix). Every validated attempt commits - the custody chain holds even if the record stays open.
5. **Close-out ask.** When the `## Fit Check` carries a pending todo match, the question line names BOTH effects - append to it: "Accepting also closes todo '[todo-slug]' - this work satisfies it." One consent covers both (the graduate-flow precedent, commands/craft-notebook.md); never add a second AskUserQuestion for the close. Only an accepting answer closes the todo - "Not quite", explicit decline, abandonment, and bare validation never do. Use **AskUserQuestion**:

```
question: "How does it look?"
header: "Tweak"
options:
  - label: "Love it"
    description: "Nailed it - close as accepted"
  - label: "Looks good"
    description: "Works - close as accepted"
  - label: "Good enough"
    description: "Fine to ship, not a favorite - close as accepted"
  - label: "Not quite"
    description: "Tell me what's off - I'll take another pass"
```

6. **Route the reaction - capture it VERBATIM:**
   - **An accepting answer ("Love it", "Looks good", "Good enough", or equivalent typed approval):** write the chosen label (or the typed words) to the attempt's Reaction and to `outcome_note`. Set `status: accepted` (attempt 1) or `revised-then-accepted` (2+). Stamp `taste:` per the rule below. If the Fit Check carries a pending todo match, the acceptance also closes it (the ask named both effects): run the shell's close call - `notebook-done.sh "<todo-file>" "<record-name>"` with this record's `name:` as the ref - and stamp `satisfied_todo: <todo-slug>`. Run the Acceptance reconcile below (skipped when no payload is pending), then the single propagation offer below, then continue to Step 4.
   - **"Not quite" / typed criticism** ("the alignment is still off"): write the exact words to the attempt's Reaction. Leave `status: open` and write NO `taste:` stamp. Loop to the next attempt - the reaction is the new brief.
   - **Explicit decline** ("never mind", "drop it", "not worth another pass"): write the exact words to the attempt's Reaction and to `outcome_note`. Set `status: abandoned`. If a todo match was pending, stamp `satisfied_todo: none-matched` - the todo stays open. If a mid-pass lock pivot was announced this thread, revert those attempts' edits (the shell's per-attempt commits make this surgical) - an abandoned tweak leaves locked.md untouched and the working tree conforming. Hand back to the shell to close the gate.
   - **No reaction / user changes topic:** leave `status: open` and the record as-is. Do not nag, do not mark accepted. Hand back to the shell to close the gate (the gate closes with the thread; the record's openness is independent bookkeeping). If the user raises it again - this session or any later one - reopen the loop from the recorded reactions.

**The taste stamp (written once, at any accepting answer):** stamp `taste: loved` when you holistically judge this to be spreadable visual taste the user loved AND a love-signal holds (the button was "Love it", OR `attempts >= 2`, OR the user typed genuine enthusiasm) AND the button was not "Good enough"; otherwise stamp `taste: routine`. This is a HOLISTIC read - there is NO `kind`-in-a-set gate, because a single `kind` label misfiles a rich multi-facet tweak (a color+motion+layout port filed `content` must not be wrongly excluded). The loved counter reads only this stamped field; it never re-derives taste from the body. "Not quite" never stamps.

### Acceptance reconcile (one beat)

**First, re-derive the token payload from the FINAL accepted values - never trust the Fit Check's pre-edit note alone.** Token drift is a final-state property: a tweak that iterates ("warmer", "tighter", "sharper") or grows in scope mid-loop can land on color, spacing, timing, or radius values that were absent or matching at the Fit Check and only drifted as attempts progressed - and the Fit Check, running before any edit, cannot see them. So at EVERY acceptance, scan the values the accepted attempt actually shipped (the files in `files_changed`) against `.craft/design/tokens.yaml`: any shipped design value that maps to no existing token, or overrides one, is a pending token payload - whether or not the Fit Check flagged it. This scan runs unconditionally; the Fit-Check note only pre-seeds it.

The beat is then entered when ANY payload is pending: the token payload just derived, a quality-floor miss noted at the Fit Check, an emergent lock conflict announced at a mid-pass pivot, or a lock the accepted work OUTGREW without contradicting (the lock says round buttons; the accepted pass rounded the cards too). No payload of any kind → skip this entirely - the close-out is exactly the routing above, unchanged, and nothing new is asked or written.

Tokens and quality are NOT the same kind of contract. tokens.yaml is descriptive - it records the values in use, so a drift reconciles by updating the doc to the accepted value. quality.yaml is prescriptive - its numbers (touch target, contrast) are FLOORS, so a miss is fixed in the work or tolerated as a noted exception; the floor is never lowered to match a violation. The two questions below reflect that asymmetry.

It fires immediately after any accepting answer closes the record - at the ORIGINAL's acceptance, always BEFORE the propagation offer and any Step 3b reapplication. Multi-attempt tweaks reconcile once, here, against the FINAL accepted values.

One beat means ONE AskUserQuestion call - include only the questions whose payload is pending (any subset of the four below), never ask them serially:

```
question (only if an emergent lock conflict is unsettled): "The accepted tweak crosses the [X] lock - settle it?"
header: "Lock"
options:
  - label: "Update the lock"
    description: "Alter/remove [X] in locked.md to match the accepted values - explicit yes, via the inline lock-edit path (Step 2)"
  - label: "Conform the work"
    description: "Revert or reshape the offending part to respect the lock as written"

question (only if a token drift was detected - at the Fit Check or the acceptance re-scan): "[value] ended at [accepted] but tokens.yaml says [documented] - solidify?"
header: "Solidify"
options:
  - label: "Update the doc"
    description: "The accepted value becomes the documented token"
  - label: "Leave as drift"
    description: "Keep tokens.yaml as-is; this surface is a tolerated exception"

question (only if a quality-floor miss was detected): "The accepted [value] misses the [X] standard (quality.yaml floor: [floor]) - conform it?"
header: "Conform"
options:
  - label: "Fix the work"
    description: "Revert or reshape the accepted change to meet the [X] floor - quality.yaml is a minimum, not a value to relax"
  - label: "Leave as a known exception"
    description: "Ship below the floor as a deliberate, noted exception; quality.yaml is untouched"

question (only if the work outgrew a lock): "This pass applied [X]'s move beyond its scope ([new surfaces]) - widen the lock to match?"
header: "Widen"
options:
  - label: "Widen the lock"
    description: "Update [X] to the proven scope - explicit yes, via the inline lock-edit path"
  - label: "Leave it"
    description: "The lock stays narrow; the extra surfaces stay unclaimed"
```

There is no third door on the lock question: a tweak never CLOSES in a lock-breaking state. "Update the lock" requires the explicit yes the inline lock-edit path demands; anything less conforms the work. The quality question likewise has no "lower the floor" door - quality.yaml is a minimum, so a miss is fixed or tolerated as a noted exception, never solidified downward.

### The propagation offer (one per close-out)

After the reconcile beat settles, EXACTLY ONE propagation offer may speak, resolved by priority: **victory-lap > snowball > apply-elsewhere.** Whichever claims the slot speaks; the others stay silent. This is separate from the Acceptance reconcile beat, which fires independently whenever a payload is pending. Each offer below is ONE ignorable closing line, per notebook conventions, never an AskUserQuestion; pure silence writes nothing.

1. **Victory-lap** - only if the record closed `taste: loved`. Read `commands/references/taste-pass.md` (under the plugin root this file lives in, three directories up from `skills/adhoc/references/`) inline (never via the Skill tool - `.claude/rules/skill-invocation-chain-breaks.md`) and run its offer gate. If the gate fires the victory lap, that IS this close-out's one offer: snowball and apply-elsewhere stay silent, and taste-pass.md owns the offer, the scout, and the pacing (the `taste-pass-state.sh` calls). If the gate does not fire (count below the effective threshold, or disabled), fall through to the next priority.

2. **Snowball** - else, and ONLY if a rule changed in this thread (a lock altered/removed, or tokens.yaml updated) - offer the sweep:

   > "That changed [rule] - worth a sweep TODO in /craft:notebook to find other surfaces that could inherit it? Otherwise moving on."

   On accept, capture the notebook todo silently with session context: the rule that changed, the surfaces already touched - the offer may name the whole family. Silence or decline → nothing. New rules are BORN at the sweep, not here: alter/remove happens at the conflict moment; ADD ("buttons are round now") waits until the sweep proves scope.

3. **Apply-elsewhere** - else, the fallback. This is the propagation path the old "apply elsewhere" close-out button used to trigger, now an ignorable follow-on line, not a button:

   > "Want to apply this same move to other surfaces? I can reapply it. Otherwise moving on."

   On accept, run Reapplying Elsewhere (Step 3b) inside the same work thread before Step 4. The reconcile beat has already settled, so propagation only ever copies a fully-legal move.

There is NO lesson-capture step on the tweak path - that belongs to fixes. The record's verbatim reactions ARE the learning payload here.

## Step 3b: Reapplying Elsewhere

The user chose to propagate an accepted move. The original record is already closed; the work thread (gate, task pair) stays open.

1. **Ask where - never scan by default.** "Where else should this land?" The user usually knows ("also the profile cards"). Offer the scan as a visibly priced opt-in in the same breath: "Or I can look for candidates - that means scanning [named scope, e.g. the components directory] for similar [kind] patterns." Run a scan ONLY on explicit acceptance, and scope it by the tweak's kind and surface - grep for the matching pattern, never a whole-project read. An unrequested full-project scan is the failure mode this step exists to prevent.
2. **One record per target.** Each target surface gets its own `tweak-[slug].md` with `reapplies:` set to the original's name. One file per surface - the family tree lives in the backlinks, never in one bloated record.
3. **Abbreviated loop per target:** Fit Check the NEW neighborhood (siblings differ - the move may need local adaptation, and a target where it genuinely doesn't fit gets said out loud, not forced), then run the same per-attempt mechanics as Step 3 on the target's own record: write its `## Attempt 1` block (Change/Validation), increment its `attempts`, update its `files_changed` / `lines_changed`, edit, validate, commit (shell's commit step).
4. **Batched close-out.** ONE "How do they look?" ask for the whole batch, targets named - not one ask per target. The user's reply closes all records it approves (same verbatim reaction in each); a called-out target ("checkout's still off") loops just that record's attempt cycle. The family close-out fires NO second reconcile beat - the rules were settled at the original's acceptance, and each reapplied target conformed to the now-current rules at its own Fit Check.
5. When the batch settles, run the snowball sweep from the propagation offer (Step 3) if a rule changed this thread - it may name the whole family - then continue to Step 4. The summary covers the family: original + N reapplications.

## Step 4: Close

Output a summary. For a single tweak:

```
## Adhoc Tweak: [name]
Surface: [surface] | Kind: [kind]
Attempts: [N]
Outcome: [status] - "[outcome_note]"
Files: [N] changed, [N] lines
```

For a reapplication batch, one line per record in the family:

```
## Adhoc Tweak: [original name] + [N] reapplications
- [surface] ([kind]): [status] - "[outcome_note]", [N] files/[N] lines
- [surface] ([kind]): [status] - "[outcome_note]", [N] files/[N] lines
```

Then hand back to the shell to close the gate (Step 6 there).
