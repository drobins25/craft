# Mockup Funnel (reference - read inline by the craft:mockup shell)

<!-- DO NOT SIMPLIFY THIS SCHEMA. Mockup records anchor agent recovery, graduation
     backlinks, and status surfacing. Every frontmatter field below is read by name
     somewhere (status, craft:status; agent_session, recovery; graduated_to, ramps).
     Verbatim reactions are the convergence history - paraphrasing destroys them.
     One sanctioned exception: a labeled `Settled:` sub-line beneath a verbatim
     reaction (see the settle gate) - explicitly derived, marked as derived, and
     never replacing or rewording the verbatim line above it. -->

A converged mockup is design truth the user approved in their browser. This flow gets there through three rounds of real reactions - diverge, refine, polish - then solidifies new design values to tokens.yaml BEFORE any destination artifact exists, so every downstream gate (binding contracts, chunk-validator, style-analyzer) enforces the mockup because the bible already agrees with it. The shell has already parsed the subject and run the single-session guard - this file owns everything else.

**Exactly three taste AskUserQuestion calls exist in this flow: vibe (Brief), solidify (acceptance), destination (fork). One first-run pre-flight AUQ (Setup - Step 1) may precede them, on a project's first-ever mockup only.** Round picks and reactions are conversational text - a widget between the user and their taste kills the funnel. The taste budget is exactly three, permanently: pre-flight is logistics, not taste, and deletes itself once a mockup record exists; nothing else may add a widget to this flow.

All writes live under the project's own `.craft/` (cold path: `$MOCKUP_ROOT/.craft/` - see Step 1) - the write gate never opens for a mockup.

## Step 1: Brief

**Cold-start determination - runs FIRST, before anything is created.** Ask whether this project is onboarded, using find-workshop.sh's exact semantic: `CRAFT_PROJECT_ROOT` is set, OR a walk-up from PWD finds `.craft/.global-state` or `.craft/project.md`.

- **Warm (a craft root resolves):** everything below runs exactly as written - the cold-start machinery does not exist on this path.
- **Cold (no root resolves):** run one cheap visual-file check - a Glob pass over `.tsx .jsx .vue .svelte .css .scss .sass .less`, excluding `.craft/`, `node_modules`, `.git`, `dist`, `build`, `.next`. Never invoke the project-scanner for this.
  - **Zero visual files -> route to `/craft:init`.** No confirmation AskUserQuestion (invoking the command is consent - the same rule /craft itself uses to route to init) and no auto-resume: the funnel STOPS here and init takes over. The user re-invokes `/craft:mockup` after init completes. If they already gave rich mockup detail before the gate, capture it to the notebook AFTER init exists (notebook needs a resolvable root) - never at the gate itself.
  - **Visual files present -> the cold path.** Set `MOCKUP_ROOT` to the git toplevel (`git rev-parse --show-toplevel`) when in a repo, else PWD - never a subdirectory. Every mockup write lives under `$MOCKUP_ROOT/.craft/`, created on demand - only the subdirectories the mockup itself needs. The cold path NEVER writes `.craft/.global-state` or `.craft/project.md`: their absence is craft's "not yet onboarded" signal, and writing either would silently kill the init offer. Run the funnel below reading `${CRAFT_PROJECT_ROOT:-.}` as `$MOCKUP_ROOT`.

**Pre-flight copy rules (locked).** The pre-flight question below is transcribed copy - never re-voiced, never "improved". No pre-flight string may contain "guess" or "guessing": the alchemist reads real code on both paths (the never-fabricate rule below - "no default palette ever reaches a brief"), and guess-language is the generic-AI framing this funnel is not. Never escalate: this is one honest ask, all options stay first-class permanently, and no future pass may add urgency, warn harder about what is "lost", re-order or re-weight options, or otherwise tune this beat to drive init adoption. The one sanctioned weight is the "(Recommended)" marker on "Init first" - owner-locked copy (2026-07-17), not a later escalation; no pass may remove it. Init is never pitched as a feature list, and "Go from what's on disk" is never written as the lesser option - for someone whose shipped code already is what they want, it is the right call. The pre-flight is a substep of Brief: substeps never become tasks, so it gets no entry on the task rail.

**Pre-flight (first mockup only) - Setup.** One conditional question that teaches what the funnel never says out loud: init is a design session this mockup could grow from. It gates on one check - `.craft/mockups/` holds no `*/record.md`, resolved against the funnel's own root (`$MOCKUP_ROOT` on the cold path, `${CRAFT_PROJECT_ROOT:-.}` warm), never PWD-relative and never the shell's Step 2 idiom, which resolves before `MOCKUP_ROOT` exists. The `mkdir` + `record.md` write below is what deletes it: a project that has mocked before never sees it, and an answered-and-entered run is never re-asked.

**Setup** - fires on the cold path's visual-files-present branch only (the zero-visual-files branch above keeps its hard route to `/craft:init` - nothing on disk to go from, no question to ask), and only while the record check above is empty:

```
question: "Craft hasn't met your taste yet. Init is a short design session - sites you love, colors from one, type from another - and this mockup grows out of it. Or build from the code you already have."
header: "Setup"
options:
  - label: "Init first (Recommended)"
    description: "The full session - pull colors from one site, type from another, riff until it's right. The mockup grows out of that."
  - label: "Go from what's on disk"
    description: "Reads your actual code, no reference brought in. Fast, and still real - just working from what you've already made, not what you're chasing next."
```

**If "Init first":** the funnel STOPS here and `/craft:init` takes over, under the zero-visual-files branch's exact rules: no confirmation AskUserQuestion (invoking the command is consent), no auto-resume - the user re-invokes `/craft:mockup` after init completes - and any rich mockup detail already given is captured to the notebook AFTER init exists, never at the gate itself. This exit happens BEFORE the record is created, so a user who returns still-cold (init never ran) is offered Setup again - deliberately: a still-cold return means they changed their mind, and the re-ask is the only door back to "Go from what's on disk". No marker is ever written on this exit.

**If "Go from what's on disk":** continue - the funnel below proceeds as written.

**Forbidden locations - both paths, no exceptions:** mockup artifacts never go to `.scratch/`, the session scratchpad, `/tmp`, or any other improvised location. If `.craft/mockups/` does not exist, CREATE it at the anchor above - a missing `.craft/` is never license to divert; diverting is a broken run, not a judgment call.

Create the artifact folder and record first - it is the durable anchor for everything after:

```bash
mkdir -p "${CRAFT_PROJECT_ROOT:-.}/.craft/mockups/$(date +%Y-%m-%d)-[slug]/rounds"
```

On the cold path the anchor is explicit - same folder shape, rooted at `$MOCKUP_ROOT`:

```bash
mkdir -p "$MOCKUP_ROOT/.craft/mockups/$(date +%Y-%m-%d)-[slug]/rounds"
```

Write `record.md` in the mockup folder:

```markdown
---
name: [YYYY-MM-DD-slug]
status: converging
created: [YYYY-MM-DD]
project: [project name]
agent_session: [filled when the alchemist spawns]
solidify_outcome: [filled at the solidify beat]
graduated_to: [filled at the destination fork]
origin: [origin tweak name when launched from a taste-pass todo - empty otherwise]
---

## Brief
[vibe answer, constraints loaded, mobile verdict]

## Reactions
[verbatim, per round - filled as rounds close]

## New Values
[used-as-is / broken old->new / net-new - tracked as rounds introduce them]

## Polish Ledger
[currently-unsettled live injections ONLY - self-pruning, normally empty
 outside an active polish loop; each line: target selector + exact change]
```

**`project`:** the project name from `.craft/project.md` when it exists; when it is absent (cold path, or a warm quick-setup project that never writes project.md), use the basename of the resolved root.

**`origin`:** stamp this at record creation when the mockup was launched from a taste-pass todo - set it to the origin tweak the todo points at (the todo's `source: "[[origin-tweak]]"` carries it into the launch context). Empty for any mockup started directly. This single stamp is what lets a taste-pass outcome trace home through BOTH graduation ramps below, however far the final design diverges from the seed.

Then assemble the brief:

1. **Load the constraints** - `.craft/design/tokens.yaml` and `.craft/design/locked.md` (which carries any design-vibe soul statement). These are think-with, not bible: deliberate breaks are licensed, announced when crossed, and tracked toward `## New Values` for the solidify beat. **When either file is absent (the cold path), there are simply no constraints to load** - assemble the brief from the vibe answer, the muse briefing (if invoked), and the alchemist's own reading of the surrounding code. Never fabricate constraints or import template values; no default palette ever reaches a brief.
2. **Detect mobile - never ask.** Breakpoints in tokens.yaml, media queries in existing components, project.md signals. When detected, every option in every round ships a mobile layout, and verification covers both viewports.
3. **The vibe question** - the flow's first AskUserQuestion:

```
question: "What should this feel like? Name a vibe, an inspiration, a mood - it seeds how different the three options dare to be."
header: "Vibe"
options:
  - label: "[2-3 vibe directions inferred from the subject + session context]"
    description: "[one line each]"
  - label: "Include the muse"
    description: "Have the muse interrogate the emotional job first - its briefing becomes the divergence north star"
```

**The muse option's (Recommended) marker is conditional.** Step 1's brief-loading already established whether each constraint file exists: if NEITHER `.craft/design/tokens.yaml` NOR `.craft/design/locked.md` exists, the label becomes "Include the muse (Recommended)" - with no design constraints on disk, the emotional job is the only compass the brief has. If either file exists, the label stays "Include the muse" unmarked - the constraints already carry direction. This determination reuses the file-presence facts from step 1; do not re-scan. Position follows the marker: when the marker fires, list the muse option FIRST - a recommendation buried at the bottom reads as an afterthought; when unmarked, it stays last, after the inferred directions.

**If "Include the muse":** invoke the muse via Task (`subagent_type: "craft:muse"`) using creative-spark's interrogation prompt shape (skills/creative-spark/SKILL.md Step 1.6): pass the subject + session context, demand the structured briefing (Stated Problem / Underlying Emotional Job / Mechanic That Carries Feeling / Constraints for Option Generation), and forbid option generation. When the briefing returns, quote 2-3 verbatim lines of it to the user in the message body, prefixed "Muse's take: ..." - pull the vivid lines (Underlying Emotional Job / Mechanic That Carries Feeling), prose only, no new widget. Then the briefing enriches the brief - the muse never builds, and the budget stays three AUQs because this rides inside the vibe answer.

Write the brief (vibe answer, constraints, mobile verdict) into `## Brief`. Create the task rail - six TaskCreate tasks, blockedBy-chained in order: **Brief -> Diverge -> Refine -> Polish -> Save (mockup + solidify tokens) -> Choose destination**. Task SUBJECTS are exactly the six beat names - `Brief`, `Diverge`, `Refine`, `Polish`, `Save`, `Choose destination` - no "Mockup:" prefix, no descriptive suffix; the subject is a label, detail goes in the task description. Substeps never become tasks. Skipped rounds complete-with-note. Polish holds ONE task across all its attempts. The rail ENDS at Choose destination - destination flows create their own tasks. Mark Brief complete.

## Step 2: The Alchemist (spawned once)

Spawn the alchemist ONCE via the Agent tool (`subagent_type: "craft:alchemist"`), passing: the brief, the mockup folder path, the living-page rules below, and the round protocol. Write its agent id to record.md `agent_session` immediately. Every subsequent round is a SendMessage to that same agent - never a fresh spawn per round.

**Recovery (designed, not hoped):** if the agent dies or the session breaks mid-funnel, re-anchor a fresh agent from record.md (brief, reactions so far, `## New Values`, any pending `## Polish Ledger` lines) + the current mockup.html - NEVER from transcript continuity alone. Update `agent_session` to the new id. This is why the record is written before anything else exists.

**The living page:** the mockup is ONE page - `mockup.html`. Each round REPLACES its content, so the page only ever shows the current decision: all options at Diverge, the pick's variations at Refine, the finalist at Polish. Before each round transition, the outgoing round is archived to `rounds/round-N.html` (kept for resurrection, never rendered or linked); the new round is then EDITED into the living page, never rewritten from scratch. Presentation adapts to scope: component-scale options stack in real surrounding context (scroll to compare); page-scale options each fill the viewport behind a thin fixed top toggle bar (A/B/C). Every option is ISOLATED: its markup lives in its own container (`#option-a` / `#option-b` / `#option-c`) and every CSS selector it owns is scoped under that container's id - zero shared selectors between options beyond one common reset block. Unscoped styles bleeding across options is a broken build, not a style choice. Options render at REAL scale - never thumbnails, never zoomed-out previews, never shrunk to fit side-by-side. Toggle, replay buttons, and round label are visually distinct dev chrome - never part of the design, never ported.

**Verification is orchestrator-owned.** The alchemist builds and self-reports; reports never count as verification. After every handoff, the orchestrator loads the page and verifies in TEXT - console errors listed, one evaluate_script assertion pass (expected sections/ids present, body has height, option count matches the brief) - before pointing the user at it. Screenshots are NOT the verification medium when the user is watching a headed browser: the user's own screen is the display, and pixels are reserved for what they can't see - mobile emulation, unattended sessions (no visible browser) - or their explicit request (including disambiguating a reaction the DOM can't resolve from words).

### The settle gate (every reaction, silent)

Before ANY reaction becomes an alchemist brief, silently classify it against the executable threshold: can the one-line brief be written using only the user's words - a target and a direction? The technique lives in `${CLAUDE_PLUGIN_ROOT}/reference/hunch-settling.md` - Read it ONCE per mockup session (or after recovery) and hold it; never re-Read per reaction.

- **Above threshold** (target + direction in their words, a named donor like "B with C's cards", or explicit delegation - "just try something"): proceed full-blast exactly as today. A clear reaction is never settled, slowed, or second-guessed. Polish micro-injections never classify at all - try/see/discard in seconds IS the settle mechanism there.
- **Below threshold** (a hunch - verdict without target, a hedged attribution, conflicting pulls, a comparative with no axis, an energy drop): settle BEFORE briefing. Throw/pull conversationally in the main loop per the reference - throw a concrete interpretation, let them correct it, brief only once the direction is in their words. The gate is invisible: never announce, name, or explain it mid-funnel - the user just gets a natural throw.
- **No escalation, ever:** never spawn the riff agent and never invoke a skill via the Skill tool from inside the funnel (chain break - control never returns). If throw/pull won't settle it, say so plainly and suggest parking the mockup or riffing separately via /craft:riff.
- **Recording:** the verbatim reaction is written exactly as spoken. When a settle ran, append ONE labeled derived sub-line beneath it - `Settled: [direction]` - append, never replace; the verbatim line above stays untouched (the schema comment's sanctioned exception).

The gate covers Diverge and Refine reactions and Polish structural rebriefs - the three points below where a reaction becomes a brief.

## Step 3: Diverge (Round 1)

Brief the alchemist: 3 genuinely different options - stances, not variations - each embedded in real surface context, seeded by the vibe answer (or muse briefing) as the divergence axis. **Diverge is the licensed-to-break round.** Each option names its stance/metaphor up front; at most ONE option may stay inside the project's current design language, and at least one must go further than the brief dared. Tokens and locks discipline Refine and Polish - the user's pick and the solidify beat are where boldness gets domesticated, never here. Three safe layouts in the current palette is a failed round. Verify, show the user, collect the reaction **conversationally** - which one pulls, what's wrong with the others, hybrids welcome.

Every reaction passes the settle gate above before it becomes the next round's brief. Write the verbatim reaction to `## Reactions`. Mark Diverge complete. If the user's pick is already final-grade ("that's exactly it, don't touch it"), Refine and Polish may complete-with-note - acceptance still runs Step 5's beats.

## Step 4: Refine (Round 2)

The pick becomes the base; brief the alchemist with variations of it. Hybrids are legal briefs ("B with C's cards"). **Options are Refine's default shape - converging to one is never inferred.** The round comes back as variations of the base unless the user explicitly asked for a single build. When a reaction hints at one direction in any way ("just build C as the full page"), confirm before briefing - one conversational line, asked as if you're not certain ("One converged take this round, or options again?") - never an AskUserQuestion, never a silent assumption. A scope expansion ("do the whole page, starting with C") is not a convergence request; a new user who gets one page where options should be doesn't know to ask where the rest went. Same mechanics: archive the outgoing round, then EDIT the living page toward the new round - never a from-scratch rewrite; the surrounding context and base CSS that didn't change are not regenerated - then verify, show, collect the reaction conversationally, record verbatim - the settle gate applies here exactly as in Diverge. Mark Refine complete.

**Mid-round lock crossings (any round):** when a direction crosses a locked.md decision, say ONE ignorable line - "that crosses the [X] lock; trying it anyway - we'll settle the lock if this is what you accept" - and proceed. No question, no AUQ, no locked.md write mid-round. The lock settles once, at the solidify beat.

## Step 5: Polish (Round 3) - the live loop

The finalist iterates until explicit acceptance. This round runs differently: the ORCHESTRATOR drives micro-adjustments live via `evaluate_script` on the loaded page (CSS/style/class injection) - try/see/discard in seconds, the user watches the change land in their own browser and reacts, next adjustment. No per-injection screenshots - the user's screen is the display; pixels only for viewports they can't see or on request. The alchemist re-enters only for structural work (new sections, choreography), which follows the same archive-then-edit discipline as any round. A structural rebrief starts from a reaction too: record it verbatim to `## Reactions` first, pass it through the settle gate, then brief the alchemist - micro-injections stay outside the gate entirely.

**Tell the user ONCE when the loop starts:** "Changes are live in the page only - don't refresh until they're written."

**The ledger discipline (never conversation memory):**
- **Inject** -> append one line to record.md `## Polish Ledger`: target selector + exact change
- **User keeps it** -> write mockup.html (one write per settled change - the file never churns through failed attempts), delete the ledger line
- **User discards it** -> delete the line, nothing written
- **Any refresh or recovery** -> re-inject every line still in the ledger, from the file

**Acceptance is explicit** - "that's it", "done", "ship it". Typed criticism loops another adjustment. On acceptance: write any remaining settled state, confirm the ledger is empty, record the verbatim acceptance in `## Reactions`, and proceed immediately to the solidify beat - it fires BEFORE the destination choice, always.

### The solidify beat (one AskUserQuestion)

Re-derive the payload from the FINAL accepted page - never from memory of the rounds: scan mockup.html's design values against tokens.yaml (new values, overridden values) and collect any locks crossed en route that the finalist still breaks. Update `## New Values` to match. (On "Solidify" against an EXISTING tokens.yaml, write the accepted values with targeted Edits on the specific keys - never a whole-file Write; the write-permission hook denies Write on an existing tokens.yaml so unnamed keys and provenance comments survive.) Include only the questions with pending payload, in ONE AskUserQuestion:

```
question (if new/changed values): "This mockup introduced [values] - solidify to tokens.yaml?"
header: "Solidify"
options:
  - label: "Solidify"
    description: "Written now with provenance: '# Locked: [date] - from mockup [slug]'"
  - label: "Keep mockup-local"
    description: "tokens.yaml untouched; a story built from this will surface these as known drift"

question (if a crossed lock is unsettled): "The accepted mockup crosses the [X] lock - settle it?"
header: "Lock"
options:
  - label: "Update the lock"
    description: "Alter/remove [X] in locked.md to match - explicit yes, per the inline lock-edit rules"
  - label: "Conform the mockup"
    description: "Rework the finalist to respect the lock as written, then re-accept"
```

**When tokens.yaml does not exist (the cold path):** every design value in the accepted page is new by definition - the solidify question still fires. On "Solidify", CREATE `.craft/design/tokens.yaml` containing ONLY the accepted values, each placed under the template's section and key path (`colors.*`, `spacing.scale.N`, `radius.*`, `typography.*`, ... - the schema in `templates/craft/design/tokens.yaml`; a net-new value goes under its proper section with a new key, never flat at top level), each carrying the same provenance comment. "Keep mockup-local" leaves NO file. These key paths are the contract a later `/craft:init` merges into - the keys ARE the contract, the comments are decoration.

Lock edits follow the tweak flow's inline lock-edit rules (skills/adhoc/references/tweak.md): explicit yes only, edited in place in locked.md's existing format, at most ONE lock write per mockup, and no third door - a mockup never closes in a lock-breaking state. Write the outcome to `solidify_outcome` (a decline is recorded there too - values stay mockup-local, no silent drift). No payload -> skip the beat entirely, nothing asked.

Set `status: converged`. Mark Polish and Save complete.

## Step 6: Choose Destination (the flow's last act)

The third AskUserQuestion:

```
question: "The mockup is converged and saved. Where does it go?"
header: "Destination"
options:
  - label: "Tweak it in now"
    description: "Hand to craft:adhoc - direction is pre-settled, this is a port"
  - label: "Make it a story"
    description: "story-new's 'From mockup' source pre-fills the story from this record"
  - label: "Park it"
    description: "A notebook todo holds the pointer; pick it up whenever"
```

The fork records the graduation, writes BOTH backlinks - record.md `graduated_to:` + the destination artifact's `mockup:` field - updates `status` (`graduated-tweak` / `graduated-story` / `parked`), completes Choose destination, and ENDS. The destination flow (adhoc, story-new, notebook) runs as its own thread with its own tasks:

- **Tweak:** the handoff brief states "direction pre-settled, converged mockup at [path]" so adhoc's classification doesn't re-open exploration. When the record carries an `origin`, the brief ALSO forwards it ("grew from [origin]") so the ported tweak can stamp its `grew_from` - the read side that keeps lineage alive on the tweak ramp.
- **Story:** story-new's "From mockup" source (commands/references/story-from-mockup.md) does the pre-fill. The mockup's CSS is NORMATIVE there - ported, never reinterpreted.
- **Park:** capture a notebook todo naming the mockup path. Pickup = todo done, then re-enter THIS destination choice against the still-converged record. Graduating a long-parked mockup first re-verifies the target surface still exists as mocked - structural drift is surfaced before porting.

**Cold path (project not onboarded):** all three destinations stay available. Say ONE ignorable line before the destination question resolves into action - "Heads-up: /craft:init hasn't run here, so this lands in the project's .craft/ and gets picked up by the harness once init wires it in" - plain prose, never an extra AskUserQuestion, said once. When invoking notebook-capture.sh or create-story.sh, pass the funnel's root explicitly as a command-scoped env var - `CRAFT_PROJECT_ROOT="$MOCKUP_ROOT" ...` - so their root resolution never guesses. The Tweak destination needs the same anchoring by a different route: the handoff to adhoc is a skill session, not a single script call, and on the cold path no session-persistent `CRAFT_PROJECT_ROOT` exists for its later bash commands to fall back on. Include the resolved root in the handoff brief ("cold project, root: [$MOCKUP_ROOT]") and instruct adhoc to prefix `CRAFT_PROJECT_ROOT="$MOCKUP_ROOT"` on every bash command it runs for this invocation - otherwise its bare `${CRAFT_PROJECT_ROOT:-.}` expansions resolve to whatever directory it happens to run from. Each destination creates only its own subdirectory on demand (`.craft/backlog/`, `.craft/notebook/`, `.craft/tweaks/`) - still no `.global-state`, no `project.md`, no scaffold. A later `/craft:init` discovers these artifacts; it never deletes them.

No choice ("Choose destination" pending) leaves the record converged and the task open - never nag; the record's openness is independent bookkeeping. An explicit drop ("abandon it") sets `status: abandoned` and completes the task with a note. Abandoned mockups stay on disk; cleanup is manual.
