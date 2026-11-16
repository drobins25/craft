# Dial Flow

The full dial session: offer through teardown. Injection payloads (MEASURE, INJECT, TOGGLE, READ, CLEAR) are defined in `${CLAUDE_PLUGIN_ROOT}/commands/references/dial-inject.md` - read it before Step 4 and hold it for the session.

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

Open the surface in the dial browser (rung (b): start the server first, as promised in the offer). The browser craft drives is a fresh Chrome with its own profile - it carries none of the user's cookies. Once the surface is open, run `node "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/devtools-launch.cjs" notice --quiet` - it marks the session's fallback notice as said without printing, because the clause in the offer already covers it.

## Step 3: The login beat

On any surface behind auth, the fresh profile lands on a login screen. This is a NUMBERED STEP, not an error branch: detect it, name it plainly, and wait -

> "That's the login screen - sign in there and tell me when you're through."

The session persists for the rest of the dial, so this costs at most one login. Dial never requires a remote-debugging port or any browser setup from the user - one login is the whole price.

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
- **Comment mode, on request.** When the user asks to mark up the page (or says they want to point at something), arm the session listener lazily, as `## Starting the listener` in `${CLAUDE_PLUGIN_ROOT}/commands/references/annotate-overlay.md` says (read it first; it is the only text that starts a listener). When `CRAFT_PROJECT_ROOT` is not set, pick the folder once before the first arm: run `bash -c 'source "$1" >/dev/null 2>&1; craft_refuse_monorepo_top "an annotate session" && exit 1; craft_before_init_root' _ "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/find-workshop.sh"` and hold the folder it prints as `<cold root>`; a `nothing written:` line is said to the user verbatim, no `arm` runs, and comment mode stops, the dial carries on. Every annotate-run command in this mode adds `--root "<cold root>"` when it is held. With no session id held in this conversation run `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/annotate-run.sh" arm --background --root "<cold root>"` (no `--root` when `CRAFT_PROJECT_ROOT` is set); the port is the `SESSION <id> PORT <port>` line. With one held, read it back with `annotate-run.sh" status --session "<id>"`; a `no such session: <id>` answer means drop the held id and arm a new session, and a listener that is not answering is restarted by the read beat's `ensure`, never by hand. Then inject the overlay alongside the dial injection and not instead of it. On a project surface (localhost, 127.0.0.1 or file://), run `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/annotate-run.sh" loader --session "<id>" --page "<surface url>"` and pass the one line it prints to `evaluate_script` verbatim: it stamps the port and the session token and loads the overlay the listener serves, and returns `LOADED` or `SCRIPT-BLOCKED`. On `EXTERNAL`, if the loader also prints a `NOTICE` line, say that line to the user verbatim, once. On `EXTERNAL` or `SCRIPT-BLOCKED`, paste instead, two `evaluate_script` steps: first the line `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/annotate-run.sh" stamp --session "<id>" --no-run` prints (the port and the session token; never stamp the baked flag), passed verbatim, then the whole `overlay-source` fence from `${CLAUDE_PLUGIN_ROOT}/commands/references/annotate-overlay.md`, its text unchanged and inside `() => { ... }`. Either way, then stamp `window.__craftAnnotateContext = "<letter>"` - the bare candidate letter string, never an object - when the sheet goes on and at every candidate switch after it, so each pin records which candidate was on stage. A re-injection after a refresh repeats the loader (or the stamps and the source) and the context stamp. Arming is a substep, not a task.
- **Stand by for SEND.** Once the overlay is on the page, start the pin watch ONCE, under the Monitor tool: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/annotate-run.sh" watch --session "<id>" --no-run` (add `--root "<cold root>"` when held). Set its `timeout_ms` to 1800000; when the Monitor's expiry notice arrives, start the same watch again, silently - but only when a pin line arrived or the user typed a message since this watch started; a turn Claude Code started on its own (an agent finishing, an expiry notice) does not count. Otherwise let it rest, say nothing, and start it again first thing on the user's next typed message - its saved position delivers any pin sent while it rested. `--no-run` is what lets it run with no annotate run - never run `begin` in a dial. Where the Monitor tool is not available, run the same command with `--once` as a background Bash command (`run_in_background` set to true) and launch it again after acting on each wake. Every SEND arrives as a notification, so the user never has to type to be heard, and the pins are already in the chat - never open a file to read them. An `ADDED <ts> #<n> "<text>" ... candidate "<letter>"` or `EDITED ...` line is one pin, delivered once: quote its `text` as the user's exact words, take its `candidate` as the letter it was about, and treat it as the user's reaction in the loop; its `source` reads "not probed" here, ignore it. A SEND of pins already delivered, a pin the user removed, and CLEAR PINS print nothing, so none of them wakes the flow: CLEAR PINS only hides the pins on the page and never earns a reply. `UNREACHABLE`: run the read beat's `ensure` now; a restarted listener leaves the running watch alone. A `NOTICE` line is said to the user verbatim, once. On an external surface a SEND-woken turn is not a typed message, so the external-page block holds the dial's own toggles and measures on that turn: record the pin, say in one line what you would change, and make the change when the user's typed reply arrives.
- **The read beat.** At the top of every beat in this loop - each user turn - when comment mode is armed, run `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/annotate-run.sh" ensure --session "<id>"` (add `--root "<cold root>"` when held). The read beat never reads the channel: pins arrive only through the watch above, so a SEND is never acted on twice. `OK PORT <port>`: go on. `LISTEN STREAK <k>`: the listener is dead and `ensure` started nothing; start it as `## Starting the listener` says, then handle it as `REARMED PORT <port> STREAK <k>` with the new port, or as `FAILED` when it will not come up. `REARMED PORT <port> STREAK <k>`: re-run the loader (or the stamps and the source) and then the context stamp for the candidate on stage, silently at `STREAK 1`; at `STREAK 2` or more say exactly one line: "The pin listener dropped again - I restarted it; if SEND does nothing, tell me and I'll read the pins from the page." On `FAILED` or `GONE` say exactly one line: "The pin listener won't restart - keep pinning and tell me when you're done; I'll read the pins from the page." The streak is the number `ensure` prints - never count restarts yourself, and say nothing else about the listener.
- Reactions are conversational. When the user lands - "C", "keep it as it is", "B but on the cards too" - the loop ends and the exit routes.

## Step 8: Close and route the exit

**First, read the session facts from the live page, not from memory.** When the user's landing words name a letter and the page shows another, TOGGLE to the named letter first, as a call of its own, so the page and their words agree. When they name a letter the dial never offered, ask which they mean before anything is read. Then, before CLEAR runs, run READ from `dial-inject.md` for the letter on the page; it reads the rules in `#craft-dial-style` and what the page rendered for them. Its `offered` is the letter set (monotonic and complete), its `active` is `chose`, and `passed` is offered minus chose. When the user kept what they had ("keep it as it is"), `chose` is `none` whatever letter the page happens to show. The DOM does not degrade under compaction; only the model's account of it does. The one conversational field is the verbatim reaction - it can live nowhere else. READ's `rules`, `added` and `keyframes` are the `chosen rules`: what that position put on the page and what the page showed for it. The page is cleared next, so they cannot be read later; hold the result as returned and never rebuild any of it from the CSS you injected. With no letter chosen, READ still runs for `offered`, and there are no chosen rules. When READ says `readable: false`, there are no chosen rules either: every exit that would carry values says they could not be read, and none is filled in from memory.

**Then teardown, on EVERY exit path including abandonment and error.** Run CLEAR - and, when comment mode was armed, stop the pin watch (TaskStop on its Monitor, or on the background `--once` command where that is what runs), then the annotate clear (the `annotate-clear` fence of the overlay reference) followed by the tombstone, `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/annotate-run.sh" clear --session "<id>"`; the listener lives until the session ends and teardown never shuts it down - and say the confirmation:

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
- **todo** - run the exit script FIRST (`notebook-capture.sh` prints the created artifact's path), then file with the printed slug as `--graduated-to`. The capture is NEVER gated on the exit script's success: if the script fails, file anyway with `--graduated-to` empty - a failed exit must not cost the corpus the record.
- **story** - file the record BEFORE the story is touched, with the story's name as `--graduated-to`, so the story can name the dial record. For a story that already exists, the name is its file name without `.md`. For a new story, pre-mint it: kebab-case, from what the user asked the story to be, or from the dial's subject when all they said was "make that a story"; when a story file of that name already exists under the resolved root, in `.craft/backlog/` or in any cycle's `stories` folder, add `-2` (then `-3`) so nothing is overwritten. The record goes first here, where the mockup flow writes its record last, because a dial's record is the one thing that must never be lost and its `graduated_to` records intent: if the session dies before the story is written, the record still reads true. Never on rung (d), where no record is filed.
- **tweak** - pre-mint the destination: the handoff brief states the literal target path (`.craft/tweaks/tweak-<slug>.md`) and adhoc uses that name verbatim (its dial-sourced branch). File the record with that pre-minted name as `--graduated-to` BEFORE the handoff, so the brief can also name the dial record's path.

`surface` and `kind` reuse the tweak vocabulary - grep existing `.craft/tweaks/` records for a matching surface slug before minting a new one. A dial record is born closed: no status, no follow-up, no nag - a session that ended in "keep it" is as complete as one that shipped.

**The four exits - all conversational, never a widget, never a question block:**

1. **Nothing** - the current value won. Speak the keep-current close BEFORE the teardown line, naming what the user now knows:
   > "Current holds - you've now seen it against B and C and it's still the one."
   Then teardown, then file with `outcome: nothing`, exactly as faithfully as any other outcome. This ending is an earned decision, never a shrug.
2. **Tweak** - hand to `craft:adhoc` with a dial-sourced brief: "direction pre-settled, dial record at [path], record name: tweak-<slug> (use verbatim), chosen position [letter]: [values]" - where [values] are READ's rules for that position, each with its selector, its condition and what the page `showed`, never the CSS as you remember injecting it, and where a qualifier in the user's landing words ("C, but a little looser") is quoted beside them as theirs to apply - the brief's literal target path is the name adhoc MUST use for its record, and the Fit Check verifies the PORT, not the idea. The chosen values are normative; port them verbatim. A locked-decision conflict still routes through tweak's existing pre-edit branch - dial never overrides a lock.
3. **Story** - the choice goes into a story. Most dials that end this way belong to a story that already exists: the one this conversation has been working on, the one being built (`${CRAFT_PROJECT_ROOT:-.}/.craft/.global-state` names a `CURRENT_STORY`), or one the user names. Put it there. Write a new story only when the user asks for one or no story is in play, and when you cannot tell which they mean, ask in one line. A story whose status is `complete` is not a destination: the part is shipped, so this is the tweak exit. Read `${CLAUDE_PLUGIN_ROOT}/commands/references/story-from-dial.md` inline with the Read tool (never via the Skill tool) and follow it with the story (the existing file's path, or the pre-minted name), the record's path, the chosen letter, READ's result as returned, and the user's verbatim words. On rung (d) pass the cold root and no record path.
4. **Todo** - a notebook todo naming the dial record and the chosen position; pick it up whenever.

On rung (e), fold one more line into the exit: offer to write the implicit scale (the computed values the candidates were derived from) into `tokens.yaml`. On rung (d), mention init here - after the choice, with the artifact in hand - and only here.

**Cold-path exits (rung (d)):** all four exits stay available. At the first cold exit, unless comment mode already holds `<cold root>` (then reuse it, no second call), run `bash -c 'source "$1" >/dev/null 2>&1; craft_before_init_root' _ "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/find-workshop.sh"` once and hold the folder it prints as `<cold root>` for the rest of the flow. Script-backed exits pass that folder explicitly - `CRAFT_PROJECT_ROOT="<cold root>"` prefixed on `create-story.sh` / `notebook-capture.sh` - and the tweak handoff brief names `<cold root>` and instructs adhoc to prefix it on every bash command it runs. Each destination creates its own subdirectory on demand (`.craft/backlog/`, `.craft/notebook/`, `.craft/tweaks/`; the dashboard refresh may also add `.craft/graph/`); NOTHING writes `.craft/.global-state` or `project.md` - their absence keeps the init offer alive, and a later `/craft:init` discovers these artifacts and never deletes them. `dials-capture.sh` still never runs cold.
