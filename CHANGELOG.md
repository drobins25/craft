# Changelog

Notable, user-facing changes per version. Internal changes (tests, refactors, contributor tooling) bump the version without an entry, so version numbers here may skip.

## 1.99.49 - 2026-07-17

- Added a first-run pre-flight to the mockup funnel: on a cold project's first-ever mockup, craft now asks up front whether to run the init design session first or build from the code already on disk. The question disappears on its own once a first mockup record exists.

## 1.99.48 - 2026-07-17

- Fixed the alignment check's scope-expansion follow-up: a synchronous agent spawn exposes no address to message, so the follow-up now re-spawns a fresh investigator seeded with the prior findings and the scope change - and never guesses at an address (a send to the agent's name fails). Warm-context reuse via background spawns is captured as a designed follow-up.
- Fixed alignment answers being written to the story twice: an answer whose reasoning already lives in the section it affects no longer gets a duplicate one-word stub in the Decisions section, and reasoning never hides in HTML comments.
- Removed the hand-authored "Let's discuss" option from every decision question - Claude Code's built-in "Chat about this" already provides that exit on every widget, so gates now offer only real options. Meaningful closers like "Accept as-is" and "Skip for now" are unchanged.
- Fixed decision-question header chips drifting from position counters ("1 of 3") to topic labels: the worked example now states the chip's job in prose, and the plan-chunks instructions point at the worked example instead of re-summarizing it.
- Improved decision-question answers: each option's description now opens with the consequence - what picking it does to the story and what happens next - before its honest verdict, and the label is the decision in plain words. One-sided questions (where no honest case exists for the runner-up) are decided and narrated instead of asked.
- Fixed decision questions flattening to exactly two options: the option count now follows how many real alternatives exist - a genuine middle path gets its own option instead of being dropped.

## 1.99.47 - 2026-07-16

- Changed plan-chunks' decision questions - the plan fork, all five triage questions, and batch triage - to mirror the same worked question grammar the alignment gate uses: self-contained questions in plain language, the recommended option first and labeled, honest one-line verdicts, no filler options. The carrier-less "A design decision needs revisiting:" question is gone.
- Added answer-time saving during plan triage: each answered question is written to the story file immediately with a visible receipt line ("kept as planned" when nothing changes), in both single-story and batch triage - so answers survive an interrupted session instead of living only in the conversation. Batch's end-of-flow write is now a consistency check, and re-planning an adjusted story treats already-answered decisions as binding.

## 1.99.46 - 2026-07-16

- Changed the alignment check to ask the way you'd want a senior engineer to: findings arrive in plain language with a title naming the problem, only genuine product decisions reach you (engineering calls and already-settled items are decided and narrated for veto), one decision per question in sequence, the recommended option first and labeled, no filler options. The gate now mirrors one of two worked examples - a fork for real decisions, a dead end for stories whose premise is already built or void - so a three-sentence fact never arrives as a six-paragraph essay.
- Added a position counter to every gate question's header chip ("1 of 2") and made the question text stand alone - one or two sentences of the problem, then the ask - so the question is fully answerable even on models that don't display the reasoning prose.
- Fixed craft's reference docs failing to load silently: every runtime doc Read is now anchored to the plugin root, every prompt states that root, and a failed Read is disclosed and retried instead of the flow improvising from memory. A new suite test verifies every anchored path resolves.

## 1.99.45 - 2026-07-13

- Added todo satisfaction detection to adhoc work: when a quick fix or tweak does what an open notebook todo asked for, craft now notices and offers to close the todo with a link to the fix/tweak record - no more todos that quietly stay open after the work already happened. Tweaks fold the close into the existing "How does it look?" acceptance (one consent, both effects); fixes ask only when a match is found, so the common no-match case adds zero friction. Every record now carries a `satisfied_todo:` receipt showing the check ran.

## 1.99.43 - 2026-07-12

- Added hunch settling to the mockup funnel: when your reaction to a round is a feeling without a nameable fix ("B is close but something's off"), craft now riffs it into a sharp direction with you - one concrete interpretation at a time, you correct it - before rebuilding, instead of burning a whole revision on its own guess about what you meant. Clear reactions ("header's too heavy, lighten it", "B with C's cards", "just try something") proceed exactly as fast as before, and the mockup record keeps your words verbatim with the settled direction noted beneath them.

## 1.99.42 - 2026-07-12

- Added a live progress checklist to /craft:init's Full setup - six beats (Intent, Scan, Shape, Design, Scaffold, Kickoff) shown as tasks in the terminal, the same rail pattern /craft:mockup uses: beats the flow skips complete with a note instead of disappearing, the whole inspiration session lives in one Design task however many sources and riffs it takes, and resuming a saved inspiration session rebuilds the rail with earlier beats marked done. Quick setup stays checklist-free - it's seconds long.
- Changed the init muse session to lead every turn with prose in the message body - the widget below only collects your answer, and the Emotional Core synthesis is presented as formatted prose instead of being crammed into the question line as an unreadable wall.
- Added the horizon line: after your Emotional Core locks during init, the muse closes with one forward-looking image drawn from your killer moment - never a feature list, never a commitment, just a door left ajar on the way into your first move.
- Changed muse and alchemist briefings in creative-spark and the mockup flow to be quoted to you verbatim ("Muse's take: ...") before they enrich the brief - previously the agents you invoked were consumed silently and you never read a word they said.
- Improved init's intent question to say what saying yes gets you: the muse distills your two answers into the project's Emotional Core that every later cycle reads. The muse is no longer introduced only by the option that skips it.
- Added a conditional recommendation for "Include the muse" in the mockup vibe question: recommended when the project has no design constraints yet (no tokens.yaml, no locked.md), unmarked once a design language exists.

## 1.99.41 - 2026-07-12

- Fixed notebook todos that graduate into a story being left open forever - graduating a todo now closes it as done in the same confirmation and records the story it's tracked by, so your open-todo list only shows work that still needs a home.

## 1.99.40 - 2026-07-12

- Added intent-seeded inspiration suggestions to /craft:init: the inspiration question now offers "Suggest some for me (Recommended)" when you described your project earlier in init - craft searches the live web for up to 3 reference sites in genuinely different directions (at least one outside the obvious category), verifies every link actually loads before showing it, and presents them as starting points to react to in plain conversation. Pick one and the existing extraction flow pulls its colors and typography; reject all three and you get exactly one smarter re-roll before falling back to the usual "give me a URL" prompt. Users who skipped the intent questions see the same two options as before.

## 1.99.39 - 2026-07-12

- Added a deterministic first-move menu to /craft:init: every init now ends with the same three options (Mock up a screen / Describe a feature / I'll take it from here) instead of an open-ended prompt the model improvised around - the mockup option appears only for visual projects, and craft recommends a mockup on empty projects or a feature when code already exists
- Fixed Quick setup ending in its own improvised kickoff - both setup paths now land on the same first-move menu
- Added a greenfield floor for first stories: when a story is planned on a project with no runnable skeleton, its first chunk scaffolds the framework - and when the story came from a mockup, the approved mockup.html is ported in verbatim as the base route, so the design approved in the browser becomes the foundation instead of getting reinterpreted

## 1.99.38 - 2026-07-12

- Added tokens.yaml merging to /craft:init: when a mockup (or you) already created tokens.yaml, init merges extracted values into it instead of skipping extraction or overwriting the file - your approved values always win by default, and same-key conflicts are listed per-key for you to resolve explicitly
- Added merge-tokens.py, a deterministic merge engine behind that behavior: it diffs extracted values against your file before you're asked anything, writes surgically (untouched lines and their provenance comments cannot change), backfills missing sections from template defaults, and verifies its own result - restoring your original file if anything is off
- Added a write-gate guard for tokens.yaml: whole-file rewrites of an existing tokens.yaml are blocked at the tool level with a pointer to the merge engine - targeted single-key updates and first-time creation are unaffected
- Fixed the project scanner counting a mockup's own HTML toward the visual-file count and reading design values from it - .craft/ is now excluded from scans
- Fixed setup preserving an existing tokens.yaml on CLI and hybrid projects instead of replacing it with the conventions template

## 1.99.37 - 2026-07-10

- Added cold-start support to /craft:mockup: a project with real UI code runs the full mockup funnel without ever running /craft:init - records persist under the project's own .craft/mockups/, accepting solidify creates tokens.yaml from the values you approved, and all three destinations (tweak / story / park) work cold with a gentle init reminder instead of a forced setup
- Added an empty-folder route: /craft:mockup in a folder with no visual code hands off to /craft:init directly - init's inspiration session is where an empty project's taste is born
- Fixed the write gate wrongly arming itself in never-inited projects: a bare .craft/ left by a cold mockup no longer counts as a craft project root, so source edits stay unblocked
- Renamed the project-root resolver to find-workshop.sh - it answers "is there a craft workshop here?", and the mockup's cold path is literally its no

## 1.99.36 - 2026-07-08

- Added stack-aware quality gates: craft fingerprints which toolchains your repo actually has (.NET, Go, Python, Rust, Make, and more) and every validation report carries one honest coverage line - "full coverage", or exactly which toolchain no gate measures
- Added the gate reconcile beat: when a chunk passes while a toolchain sits unmeasured, craft asks (a real question dialog) whether to wire a gate - it proposes a command as an editable draft, runs it once to prove it works, surfaces pre-existing failures with a non-blocking option, and writes it to quality.yaml with a verified stamp; declining is confirmed once with its risk spelled out, then that toolchain is never asked about again - it stays visible in the coverage row and /craft:status as "(declined)" so waived-by-choice never reads as missed-by-accident, and autonomous runs ask at launch (pre-flight) instead of mid-run so hands-off cycles never validate toolchains nobody agreed to leave unmeasured
- Changed quality.yaml command execution to the verified path: a gate command only runs once it carries a verified: stamp (hand-written stamps count), and a verified command that stops starting reports broken verification with a re-verify offer instead of failing your chunk
- Removed the orphaned run-gates.sh script and the template's dormant command fields - dead config that advertised customization the harness never read

## 1.99.35 - 2026-07-07

- Added the Taste Pass: once several tweaks you loved have accrued, craft offers a "victory lap" that scouts other surfaces the same taste could spread to and hands each one to /craft:mockup to make - surfaced as one ignorable line at session start or a tweak close-out, never a popup, and self-silencing if you never take it
- Added taste lineage: a loved tweak that grows into a mockup and graduates into a story or another tweak now records where it came from, so a button that snowballs into a whole page still traces back to where the taste started
- Changed the tweak close-out to a feeling gradient (Love it / Looks good / Good enough / Not quite); "apply elsewhere" is now a follow-on offer instead of a button

## 1.99.34 - 2026-07-06

- Improved mockup Diverge rounds: options are style-isolated (no more overlap between them), render at real scale, and at least one option must break past the project's current design language - safe-times-three now counts as a failed round

## 1.99.32 - 2026-07-05

- Changed mockup rounds to edit the living page instead of regenerating it, and to verify handoffs with console/DOM checks - screenshots now happen only for viewports you can't see (mobile emulation, unattended sessions) or on request

## 1.99.31 - 2026-07-05

- Changed the changelog to notable-only: features and user-visible fixes get entries, internal fixes bump the version silently

## 1.99.29 - 2026-07-05

- Added /craft:mockup: a live HTML mockup funnel - a persistent alchemist builds 3 genuinely different options, you converge by reacting through diverge/refine/polish rounds, and new design values solidify to tokens.yaml at acceptance
- Added three graduation ramps for a converged mockup: port it now as a tweak, create a pre-filled story (mockup CSS is normative - ported, never reinterpreted), or park it as a notebook todo
- Added mockup visibility: a Mockups section in /craft:status and a session-start segment when mockups await a destination
- Changed story creation: the source question now also offers "From mockup" when converged mockup records exist

## 1.99.28 - 2026-07-05

- Added this changelog: notable user-facing changes land here with every release, enforced by the doc-drift push gate
