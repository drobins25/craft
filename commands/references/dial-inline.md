# Dial Flow

The full dial session: offer through teardown. Injection payloads (MEASURE, INJECT, TOGGLE, CLEAR) are defined in `${CLAUDE_PLUGIN_ROOT}/commands/references/dial-inject.md` - read it before Step 4 and hold it for the session.

Two shapes, both first-class, neither the default:

- **Magnitude** - one property, different amounts. Ordered: current / conservative / reach. Spacing, size, weight, timing. ("The gaps are too loose.")
- **Approach** - one goal, different treatments. Unordered - there is no "more" between positions, and a position may ADD an element (a badge, an accent bar, a button) as long as the surface it lands on already renders. ("How should an invalid card read?")

The approach shape is the reason dial exists. Dial is not a tight/tighter widget, and the approach shape must not collapse into magnitude.

**No AskUserQuestion anywhere in this flow - never, at any step, including every exit.** Dial's entire conversation is inline prose and the user clicking letters in their own browser.

## Step 0: The degradation ladder

Five rungs, checked in order. The session runs on the first rung that matches:

- **(a) No dev server and no discoverable way to start one** -> NO offer is made at all; the conversation continues normally. Dial without a live surface is a contradiction.
- **(b) Runnable but not running** -> starting it folds into the offer line itself ("I'll start the dev server and open it in a separate window") - never a separate question.
- **(c) Running** -> proceed.
- **(d) No `.craft/` directory** -> full dial, no detents: candidates come without token names, `dials-capture.sh` is NEVER called, and init is mentioned only after the user has landed on a choice - never before, never as a precondition.
- **(e) `.craft/` present but no visual values in `tokens.yaml`** -> candidates derive from live computed styles (Step 5's fallback), and the exit offers to write the implicit scale into `tokens.yaml`.

## Step 1: The offer

The offer is ONE ignorable inline line, spoken only AFTER the substantive answer the user actually asked for. It names the candidates in dial's own idiom and carries the mechanics in the same breath:

> "I can dial that in live - gap-md, gap-lg, or gap-xl. I'll open it in a separate window - you may need to sign in there once. Otherwise moving on."

Rules:

- Answer first. "Why does that pill look so loud?" gets the mechanism explained, THEN the offer. An offer that preempts the reply makes the tool feel like it is hunting for reasons to run.
- An already-decided value ("make that gap 24") is a tweak, permanently - no dial offer at any point.
- The mechanics clause ("separate window... sign in once") is said BEFORE the browser opens, so the fresh-profile window and any login wall are expected beats, not surprises.
- Ignoring the offer is an answer. Continue the conversation; never re-offer the same dial.

## Step 2: Open the surface

Open the surface in the dial browser (rung (b): start the server first, as promised in the offer). The browser craft drives is a fresh Chrome with its own profile - it carries none of the user's cookies.

## Step 3: The login beat

On any surface behind auth, the fresh profile lands on a login screen. This is a NUMBERED STEP, not an error branch: detect it, name it plainly, and wait -

> "That's the login screen - sign in there and tell me when you're through."

The session persists for the rest of the dial, so this costs one login per session at most. Dial never requires a remote-debugging port or any browser setup from the user - one login is the whole price.

## Step 4: Measure

Run CLEAR first, unconditionally - a stale dial from an earlier session may have left residue, and CLEAR is idempotent on a clean page. Then MEASURE the surface (both operations from `dial-inject.md`): current computed values for the property in question, bounding rect of the first visible match. The visibility rule applies - never read the hidden face of a responsive page.

## Step 5: Derive the candidates

Read `.craft/design/tokens.yaml` when it exists and carries relevant visual values; positions that land on the scale get their token name as metadata. When tokens are absent or silent on this property (rungs (d)/(e)), derive from the live computed styles - the page itself is the scale.

**The candidate rules. These are the deliverable - state them to yourself and obey them:**

- **Never let every position be timid.** On a magnitude dial, the last position is a reach that COMMITS to the change rather than nudging it - moving margins AND shrinking the search field AND quieting the loud pill, not two margins moved by 4px. On an approach dial, at least one treatment is genuinely louder or more structural than the safe one - a ring plus a left bar next to a lone asterisk. A dial where every option is a small variation on the current state is the failure mode that makes the user pick nothing and feel the tool wasted their time.
- **The approach shape is first-class and must not collapse into magnitude.** "How should this read?" gets four different ideas, not four sizes of one idea.
- **A position is never blunted just to keep every value named.** On-scale or off-scale is downstream of what the position needs - the rule is deliberately NOT "always include an off-scale option," and never "trim the reach to the nearest token."
- **2-4 positions, letters running as far as they need.** Four is real - a four-treatment dial has shipped and the user chose D.
- **Letters are the handle; token names and pixels are metadata.** The user says "C, but a little looser" - nobody says "option gap-xl."

Per-position hierarchy, strongest to weakest: letter -> intent word -> token name -> measured px.

## Step 6: Inject

Run INJECT from `dial-inject.md`: candidate CSS keyed off `html[data-craft-dial]`, the panel as body's last child, position A active. Tell the user ONCE, when the panel lands:

> "Changes are live in the page only - don't refresh until we're done."

A refresh mid-session discards the injection; if it happens, re-inject and continue - a record read from the re-injected page is an honest record of the interrupted session.

## Step 7: The react loop

The user clicks letters in their own browser and reacts in chat; the orchestrator TOGGLEs or re-injects. No per-toggle screenshots - the user's own screen is the display; pixels are reserved for viewports they can't see or their explicit request.

- After every toggle, re-MEASURE before reporting any number - the readout is the receipt that the CSS landed, never the injected intent.
- New-position requests ("try between A and B") are in-loop re-injections that EXTEND the letter set. Positions are never removed once injected; the letter set only grows.
- Reactions are conversational. When the user lands - "C", "keep it as it is", "B but on the cards too" - the loop ends and the exit routes.

## Step 8: Close and route the exit

**First, read the session facts from the live page, not from memory.** Before CLEAR runs, one `evaluate_script` enumerates the letters keyed in `#craft-dial-style`'s rules (`offered` - the set is monotonic and complete) and reads `documentElement.dataset.craftDial` (`chose`); `passed` is offered minus chose. The DOM does not degrade under compaction; only the model's account of it does. The one conversational field is the verbatim reaction - it can live nowhere else.

**Then teardown, on EVERY exit path including abandonment and error.** Run CLEAR, and say the confirmation:

> "Cleared - the page is showing real code again."

**Then route the exit and file the record - ordering per exit, and the capture ALWAYS runs** (rungs (c)/(e); NEVER on rung (d)):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/dials-capture.sh" "<subject>" \
  --surface=<surface> --kind=<kind> --scope=<magnitude|approach> \
  --offered="<letters>" --chose=<letter|none> --passed="<letters>" \
  --outcome=<nothing|tweak|story|todo> [--graduated-to=<artifact>] --reaction="<verbatim>"
```

`graduated_to` records graduation intent - the destination artifact's own status is the truth of what shipped. How it gets filled depends on the exit:

- **nothing** - file immediately, `--graduated-to` empty.
- **story / todo** - run the exit script FIRST (`create-story.sh` / `notebook-capture.sh` print the created artifact's path), then file with the printed slug as `--graduated-to`. The capture is NEVER gated on the exit script's success: if the script fails, file anyway with `--graduated-to` empty - a failed exit must not cost the corpus the record.
- **tweak** - pre-mint the destination: the handoff brief states the literal target path (`.craft/tweaks/tweak-<slug>.md`) and adhoc uses that name verbatim (its dial-sourced branch). File the record with that pre-minted name as `--graduated-to` BEFORE the handoff, so the brief can also name the dial record's path.

`surface` and `kind` reuse the tweak vocabulary - grep existing `.craft/tweaks/` records for a matching surface slug before minting a new one. A dial record is born closed: no status, no follow-up, no nag - a session that ended in "keep it" is as complete as one that shipped.

**The four exits - all conversational, never a widget, never a question block:**

1. **Nothing** - the current value won. Speak the keep-current close BEFORE the teardown line, naming what the user now knows:
   > "Current holds - you've now seen it against B and C and it's still the one."
   Then teardown, then file with `outcome: nothing`, exactly as faithfully as any other outcome. This ending is an earned decision, never a shrug.
2. **Tweak** - hand to `craft:adhoc` with a dial-sourced brief: "direction pre-settled, dial record at [path], record name: tweak-<slug> (use verbatim), chosen position [letter]: [values]" - the brief's literal target path is the name adhoc MUST use for its record, and the Fit Check verifies the PORT, not the idea. The chosen values are normative; port them verbatim. A locked-decision conflict still routes through tweak's existing pre-edit branch - dial never overrides a lock.
3. **Story** - story-new, with the dial record path and chosen direction passed as the spark's source material.
4. **Todo** - a notebook todo naming the dial record and the chosen position; pick it up whenever.

On rung (e), fold one more line into the exit: offer to write the implicit scale (the computed values the candidates were derived from) into `tokens.yaml`. On rung (d), mention init here - after the choice, with the artifact in hand - and only here.

**Cold-path exits (rung (d)):** all four exits stay available. Script-backed exits pass the resolved root explicitly - `CRAFT_PROJECT_ROOT="$DIAL_ROOT"` prefixed on `create-story.sh` / `notebook-capture.sh` - and the tweak handoff brief names the root and instructs adhoc to prefix it on every bash command it runs. Each destination creates only its own subdirectory on demand (`.craft/backlog/`, `.craft/notebook/`, `.craft/tweaks/`); NOTHING writes `.craft/.global-state` or `project.md` - their absence keeps the init offer alive, and a later `/craft:init` discovers these artifacts and never deletes them. `dials-capture.sh` still never runs cold.
