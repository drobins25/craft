# Changelog

Notable, user-facing changes per version. Internal changes (tests, refactors, contributor tooling) bump the version without an entry, so version numbers here may skip.

## 2.12.0 - 2026-10-25

- Changed the questions that need real thought. Craft now asks them as a card in the conversation: the question, the options with the reasoning for each, and its recommendation. You answer by typing a letter, or "yes" to take the recommendation, instead of squinting at a picker that hides the reasoning.
- Kept the picker for questions with fixed answers, where a click is all it takes.
- Improved how answers are kept: each answer is saved as you give it, so nothing is lost if a session stops partway through a set of questions.
- Fixed batch planning skipping decisions the planner had flagged for you. When planning several stories at once, every call the planner marked as yours to make is now asked, and every call it made on your behalf is listed, whatever its confidence.
- Changed the last stretch of creating a story. After the codebase check, the five design sections (acceptance, scope, what to preserve, the hardest constraint, dependencies) arrive one at a time, each written into the story as it is drafted, and craft asks you once at the end instead of after every section.

## 2.11.1 - 2026-10-22

- Fixed the end-of-story check for planning notes left in code comments (like "Chunk 3") failing your story over old comments it never wrote. It now looks only at the lines your story added.
- Fixed that same check sometimes passing, or being skipped, without checking anything. It now checks every file your story touched and tells you when it can't read one.

## 2.11.0 - 2026-10-18

- Added a record for every `/craft:review` run on your own work, clean or not. Each one keeps what was checked and what was found, so a review that finds nothing still leaves proof of what it looked at. Reviewing someone else's PR leaves no record, so their code never muddies yours.
- Added a close-out after a review: craft proposes where each finding goes, all in one table, and you answer in a word.
- Changed fixes that come out of a review. They now run as recorded, committed fixes instead of bare edits, so the history shows what was fixed and why.

## 2.10.1 - 2026-10-18

- Fixed planning asking "Ready to plan this story?" right after you asked to plan it. When you run `/craft:plan-chunks` on a story, say "plan this", or say yes to an offer to plan, planning now starts straight away. Planning that starts without your ask still checks with you first.
- Changed the last step of the muse session in `/craft:init`. After it shows your project's Emotional Core, it asks "Does this capture it?" and reads your answer, so you say what to change in your own words instead of picking from a menu.
- Changed the project-type question in `/craft:init` for an empty folder. When you have already said what the project is, that reading comes first and is marked as recommended, instead of four stock options that ignore what you told it.

## 2.10.0 - 2026-10-16

- Added research before anyone plans on a guess. When a story depends on something outside your project that nobody has checked (a site, a tool's output, a data source, a format), craft settles a single fact in up to three searches and tells you what it checked and where. Anything bigger it researches before the alignment check asks its questions, and the findings land on the story with pinpoint citations. The planner verifies outside facts with its own search as it plans. When three searches cannot settle a claim about a whole class of things, it stops for research instead of guessing. Each gap is researched once; if it is still open after that, you are asked what the plan should assume. When the ask could be read two ways, craft confirms the reading before it researches, and `/craft:research` gains the same check.
- Fixed `/craft:research --deep` and `--exhaustive` stopping to ask "What next?" after the first pass. A deep run now elaborates every branch without asking, and an exhaustive run then hands the topic to `/craft:research-verify`, as the command's help always said.
- Changed the agents behind `/craft:research`, `/craft:research-verify` and `/craft:become` to always run on the latest Haiku model, instead of staying pinned to an older version.
- Fixed SEND TO CLAUDE on a mockup or dial page doing nothing until you typed in the terminal. Your pins now reach craft the moment you press SEND, each pin arrives once even when you press SEND again, and CLEAR PINS stays quiet, since it only hides pins on the page.
- Fixed an open annotate, mockup or dial session waking Claude every 30 minutes while you were away. The pin watch now rests after half an hour with no pin and no message from you, and picks up again on your next message, with any pins you sent in between.

## 2.9.3 - 2026-10-15

- Added a planned-test line to adhoc fix records. When a fix lands for a defect found after its story shipped, the record names the planned test from that story that should have caught it, or says none covered it. Over a cycle, the "none" count shows what planning left untested, read straight from the records.

## 2.9.2 - 2026-10-15

- Changed `/craft:review` findings to arrive in the shape of a bug record. Each one names the symptom in your terms, quotes the requirement it breaks, says whether the reviewer ran the code or only read it, gives the consequences, numbered steps to reproduce from a named starting point, the raw evidence, and the fix. A finding the reviewer could not run is still reported, labelled as read in code only.

## 2.9.1 - 2026-10-15

- Fixed annotate pins jumping to the wrong element on pages with repeated structure. A pin dropped far down a list, a set of cards or a form now stays on the element you clicked, after you save it, after SEND, and after a reload.

## 2.9.0 - 2026-10-14

Craft now lets you point at a live page. Put a comment sheet on the tab you have open, click anything, say what you want, and press SEND TO CLAUDE. Every pin gets a live attempt on the page while you watch, nothing is written to your files until you say so, and the run leaves as a tweak, a story or a todo.

- Crafted `/craft:annotate`. Craft puts the sheet on your open tab, tries each pin on the page, and reports what the page measured, not what it meant to do. Pins stay on their element as the page moves, and the run is kept as one record: your pins word for word beside the look you approved. A run cut short is offered back next time. The guide is `docs/annotate.md`.
- Added a source for every pin. Each pin names the component and stylesheet rule behind the element you clicked, when craft can find them, and a story made from the run names those files.
- Added the ways a run leaves. "Make it a story" pre-fills a story from the record, the look carried over as approved and anything drawn in CSS as a stand-in for real content turned into scope. "Apply this" hands the whole run to `/craft:adhoc` as one tweak. Or it becomes a notebook todo, or nothing, and `/craft:story-new` offers it later.
- Added comment pins to mockup and dial pages. Leave notes on the options you are reviewing and they reach craft as your reaction.
- Added a trust boundary for pages outside your project. On a site that isn't local, pins are treated as page content, not your instructions. Craft says so once, makes visual changes through the sheet, and asks in chat before anything else. Only craft's own page scripts run there without your yes, and anything that would save a file waits for it too.
- Added a plain answer when a site blocks SEND. If the page's policy stops it from reaching craft, craft says so up front and reads your pins from the page instead.
- Added annotate before `/craft:init`. The sheet, the record and picking up a cut-short run all work on a project craft has never set up.
- Added annotate runs to the dashboard. Each run sits on the project graph with its record, linked to the tweak or story it became.
- Sparked one "craft designs" answer when you start a story or design a cycle. It lists every mockup and annotate run waiting to be built, says what it found, and skips the question when the conversation already answers it. Cycle design lists waiting designs as story candidates, so a converged mockup can no longer sit unread while its stories are written by hand.
- Changed how craft reaches your browser. Craft starts the browser connection itself: two sessions each get their own window, the second is told it may need to sign in, no usage statistics are sent, and review pages are cleared of craft's overlays before a reviewer looks at them.
- Changed where craft files land before `/craft:init`. Mockups, dials, bugs, decisions, notebook entries, research and annotate runs share one rule: the set-up project if there is one, else the repo's top level, else the current folder. A dial that ends in "make it a story" before init now saves the story.
- Changed filing from a monorepo's top level. `/craft:bugs` and `/craft:notebook` now refuse and name the projects they found, instead of writing a record where no project would ever list it.
- Fixed an adhoc change on a project that never ran `/craft:init` locking Claude out of editing that project's files.
- Fixed `/craft:status` reporting a set-up project as not initialized when run from one of its subfolders.
- Fixed a stuck craft hook holding a turn for up to 83 minutes. A hung hook now gives up in seconds, and a test keeps it that way.
- Fixed the creative options step making a fifth option you were never shown. It now gives 3 to 4 options, and the picker has room for all of them.
- Fixed an approved design vibe ending the session unsaved. It now lands in your locked decisions.
- Fixed the repair step after a failed validation claiming to re-run checks it cannot run. It now makes the edit and hands back to validation.
- Fixed `/craft:research-verify` judging web-sourced claims without web access. Its checker can now search and read primary sources.

## 2.8.0 - 2026-10-04

Craft now keeps its bugs. A person mid-conversation or an agent mid-run walks through one door and a complete record lands on disk, without anyone being pulled out of what they were doing. Bug then adhoc is the fix path now.

- Added `/craft:bugs`. Say "file a bug" and craft files it without stopping what you were doing. Run it bare to see the open pile, newest first, with the bugs that block someone's next step marked. Say a bug is fixed or won't be fixed and craft matches it, confirms once, and closes it with that verdict. Session start shows how many bugs are open, and stays quiet at zero.
- Added a one-line offer to file when you defer a defect: "later" or "don't let me forget" attached to something broken, or a defect named mid-story. Nothing is filed until you say yes. `/craft:adhoc` and `/craft:notebook` point a defect you are not fixing now at `/craft:bugs`.
- Changed `/craft:analyze`. Every defect QA and the walkthrough find lands in `.craft/bugs/`, with the open pile as the dedupe. A QA finding the analyzer couldn't verify is named in the report instead of filed, so the pile only holds what was seen. The QA and walkthrough queues and their create-a-story prompts are retired. UX, creative and style findings queue for review as before. When no cycle is active, the scope prompt offers the last completed cycle.
- Changed cycle completion. The walkthrough files bugs and the cycle completes. The cycle-complete repair loop, which predates adhoc, is retired.
- Added bugs to the dashboard. Open and closed bugs sit on the project graph in their own jade color, and a bug's card shows its status and its record.
- Removed the hook that approved nearly every shell command on your behalf. It predates auto mode and overrode the permission mode you chose, in every project craft was installed in. Shell commands now go through your own permission flow: auto mode's review, your allow rules, or Manual-mode prompts.
- Fixed the QA, UX, creative and style analyzers reading source instead of testing the running app. They can reach the browser again.
- Fixed one oddly encoded file hiding everything after it. A notebook note, decision record or dial record that isn't valid UTF-8 now shows with a replacement character and the rest of the list stays intact.
- Fixed story completion when a story deletes a file with `git rm`. The completion commit now goes through instead of aborting after the story was already marked complete.
- Fixed choosing Ignore for a leftover file at story completion. The file is now actually gitignored.

## 2.7.2 - 2026-10-03

- Changed plan approval to two forward choices: mark the story ready, or mark it ready and start implementing right away. The options that edited a finished plan after its checks had run, or reopened creative riffing on a technical story, are gone.
- Changed what happens when you plan a story from cycle start and choose to implement it right away: craft activates the cycle and starts that story, with no "ready to start?" prompts and no switch to a different story. The same holds after batch planning and when implementation activates a cycle for a story you already picked.
- Removed the visual-riff question from technical and content stories. Only a UI story is asked whether to riff on the look before planning.
- Removed creative riffing from batch approval after the plans are drawn. Approve, Adjust, and Reject stay.

## 2.7.1 - 2026-10-03

- Fixed decision answers typed over several lines. The whole answer now stays in the record's quote, so the archive shows every line instead of only the first.
- Fixed story completion saying a decision was built when its record couldn't be marked. You now get a warning naming that record instead of a "Crafted" line.
- Fixed tag and story names holding a comma, semicolon, bracket or newline. They used to split into two names or break the record's list; craft now refuses them with a clear error before writing anything.

## 2.7.0 - 2026-10-03

Craft now keeps its decisions. 2.6.1 let a story carry the rulings it was built from and promised the rest: filing decisions, listing them, and watching them become real as stories ship. This release delivers all three. Rule something once and it stays ruled - visible, reusable, and marked done when the story that builds it ships.

- Added `/craft:decisions`, the decision desk. The Shelf shows every decision grouped by topic: what's waiting on you, what's ruled and ready, what a story is building, and what's done. Name one to see its card, then approve, keep it pending, or decline it with one letter - or just say what to change.
- Added reopening and retiring. Reopening ruled law shows exactly what would change before anything is written. A decision a shipped story already built is frozen; change your mind and craft drafts a new decision instead of rewriting history.
- Added moving decisions between topics in plain words, with the moved record shown where it landed.
- Added the finish line: when a story ships, every decision it carries is marked done on the Shelf.
- Changed stories to carry only the decisions you name for them. Claude never attaches one it judged relevant.
- Changed the desk to close once you finish a card, so a "go with that" later in the same session stays a normal conversation unless you call it a decision.
- Changed `/craft:adhoc` fixes that add a test. The test now has to fail on the bug before the fix goes in, so when craft says a fix works, it has watched it go from red to green.
- Fixed story checks that turned red the moment you committed. When a story promises a file stays unchanged, craft now checks what the file says, not whether it differs from your last commit.

## 2.6.1 - 2026-09-04

Craft is learning to keep its decisions. This release lays the first plank: a story can now carry the approved decisions it was built from, and craft treats those decisions as the frame the story fills in. Rule something once, and every story that grows out of that ruling knows about it before planning begins. The rest of the feature - filing decisions, listing them, watching them become real as stories ship - lands over the coming releases.

- Added a link from every new story to the decisions behind it. When craft plans the story, the planner opens each linked decision first and treats its ruling as the frame the story fills in, before it reads the story's own notes.
- Added a check that the planner really did: a plan for a story that carries decisions but shows no sign of having read them stops and asks you before going further, the same way any other gap in a plan does.
- Changed the alignment check to hand those rulings to the exploring agent up front, so it stops asking you product questions a decision already answered.
- Changed every path that creates a story to write its header in one consistent order, so a story looks the same whether it came from a template, a cycle plan, the backlog, or a planning concept.
- Existing stories are untouched. A story without the link behaves exactly as it did before: no warnings, no rewrites, nothing to migrate.

## 2.6.0 - 2026-08-29

The galaxy grew up in one day. This morning the dashboard was a bloom of orange; tonight your records gather into colored neighborhoods, your finished work cools into quiet grey texture, and the color belongs to what's alive. The whole look was designed live against real project data - riffed, dialed, mocked up, annotated with pins on the actual page - and then ported with every value verbatim.

- Changed the galaxy's shape: records now cluster into colored regions by kind, each with a soft glow of its own hue behind it, so the sky reads at a glance without a legend.
- Changed how history looks: finished stories cool to quiet grey while active work keeps the ember - your dashboard now shows what's alive, not just what exists.
- Changed the observation cards: solid and readable instead of see-through, with short dotted arrows that point at their region and never cross a single node.
- Added a bigger entrance: the galaxy swirls into place with real spin, the glow breathes in behind it, and cards always arrive within two seconds - even mid-motion.
- Added drag-to-pin that feels alive: pull any node out and drop it - it stays put while the rest of the galaxy visibly exhales back into proper spacing. Drag a hub and everything connected to it stretches out to show itself, then flows home.
- Fixed the page never going to sleep after pinning a node - the render loop now truly rests, so a pinned galaxy costs nothing to keep open.

## 2.5.0 - 2026-08-29

Craft has a face now. Everything craft has been writing down since your first init - the stories, fixes, tweaks, mockups, dials, riffs, notes - was always a graph waiting to be seen. This release ships the Craft Browser: one page, no server, no setup, that renders the life of your project the way Obsidian renders a vault. It was built entirely through the flows it renders, and its first graph includes its own birth.

- Added `/craft:dashboard`: open your whole project as a living graph - every record a glowing node, every lineage an edge, cycle hubs in gold, with a slow cinematic entrance dialed live against real data. The data rebuilds itself as you work, so the page is never stale, and when the shipped page design moves ahead of yours, opening it offers the update.
- Added a reading panel: click a record and read it right there - the story's own words in a recessed serif well, its work list tucked behind a disclosure, the panel inked in that record's hue.
- Added insight cards: observations craft mined while building your work surface as cards pinned over the graph, so the dashboard doesn't just show what happened - it shows what craft noticed.
- Changed what cards say: plain words from your project, never machine values or internal field names.
- Added a citation guard: code that ships to your project can no longer carry craft's internal planning vocabulary in its comments - your codebase reads like yours, not like a session transcript.
- Fixed a crashed session leaving the write gate stuck open, and the dashboard occasionally printing a link that only worked from one directory.

## 2.4.2 - 2026-08-11

- Changed riff's finale to three words that need no explanation: when a direction lands, Claude calls "That's a riff!" and starts building. Each session's one-of-a-kind word still gets its honor - it names the riff memory alongside a plain few words about what you built, so the notes shelf reads like a history of wins instead of a list of riddles.
- Improved how riff speaks: the game now runs entirely underneath, and the conversation stays in your language - no more stray game-speak dropped mid-idea. Bring the playful words yourself ("toss it back") and Claude plays along; otherwise it's just two people trading ideas that keep getting sharper.

## 2.4.1 - 2026-08-09

- Changed how a riff ends: in plain language, from both seats. Claude asks the closing question in words anyone gets ("I think we've got it - do you?"), and your answer counts in any words that mean "let's build it" - no ritual phrase required. The game's vocabulary stays where it belongs: in the box, for players who've opened it.
- Changed the victory shout to your session's own word: finish designing neon styles together and the game breaks on "Go NEON!" Every riff now ends on the word the two of you kept passing - a shout only your session could have produced. Win notes in `.craft/riff/notes/` are named after that word too, so the trophy shelf reads like the story of what you built.
- Fixed the game implying a bag of potatoes: one idea, one potato, passed until it's ready - and now the rules say so.

## 2.4.0 - 2026-08-07

- Changed /craft:riff into a two-player game. The skill now opens like the rules card from a board game box, written for both players - you and Claude: one idea too hot to hold alone, passed in small beats, until you both feel it's ready and build it together. Claude brings real opinions instead of interview questions, pushes back when it disagrees, and confirms what's settled before each pass so nothing gets lost in a long riff.
- Added riff memories: when a riff lands, Claude writes a short win note to `.craft/riff/notes/` in your project - what you built together and how you two work best - so your next session picks up the partnership where you left it instead of starting from a stranger. Only wins get written; a riff that fizzles just ends, no ceremony.
- Improved first meetings: when riff engages on its own (you described a half-formed idea and Claude started thinking it through with you), you get the great back-and-forth without the game vocabulary - the flavor is reserved for players who've opened the box.

## 2.3.0 - 2026-08-06

- Changed /craft:riff into a real conversation: one plain question at a time, in chat, until the direction lands. Every question tells you what hangs on the answer, and when the evidence has earned a lean you get it stated - "my lean: X, because Y" - never a bare question, never a numbered list, never a widget. Each answer gets acknowledged before the next question comes, and when your answer kills the remaining agenda, the agenda dies - you're never asked to finish a list that stopped mattering. Sessions end like conversations, not ceremonies: no wrap-up prompt, no closing menu.
- Added a crafty opener: bare /craft:riff with no topic picks up the oldest open idea in your notebook and asks one question that reconnects it to what's changed since you wrote it down - the missing bridge between capturing an idea and it becoming a story. Bring a topic and riff works that instead; no notebook, no problem - it just asks what's on your mind.
- Added a self-catch for question overload: when Claude dumps a lot at once on a direction you haven't settled - a wall of questions, options, or analysis - the wall now ends with one ignorable line: "I just said a lot at once - let me know if you'd rather riff through this." Answering normally is declining; nothing nags.
- Changed what a vague feature idea gets you: "let's design a social media feature" now opens a conversation that draws out what you're picturing, instead of three speculative options invented from nothing. Ask for ideas and you still get ideas - options come on request, or once the direction has firmed enough to generate against.

## 2.2.0 - 2026-08-04

- Added /craft:dial for the moment a live page is almost right ("the gaps are too loose", "that reads too quiet"): craft drops lettered options straight into your running app - A, B, C, D in a little grey panel on the page you were already looking at - and you click until one stops bugging you. "Oh I like B" is the whole review: the winner ports into code with tests updated and your exact words on record, everything else vanishes on refresh, and nothing touches your source while you're deciding. Keeping what you already have is a real answer too - craft remembers what you saw and passed on.

## 2.1.2 - 2026-08-03

- Fixed story numbering handing out a number already in use: after a story was archived out of a cycle, the next story created or assigned there could land on an existing number, leaving two stories answering to "story N". New stories now always get a number higher than every existing one - gaps left by archived stories stay as gaps.

## 2.1.1 - 2026-07-31

- Improved code comments in implemented work: they now explain why the code is the way it is, instead of citing internal planning notes or config rule names that mean nothing outside the session that wrote them. Comments you asked for (like tagged TODO markers on placeholder content) are untouched - this only stops the unwanted paper trail.

## 2.1.0 - 2026-07-30

- Added craft's front porch: in a project you haven't initialized, Claude now knows craft is there from your very first prompt. Ask to build something and /craft:init gets offered at the natural moment - instead of you discovering weeks in that it existed. Everything that already works with zero setup (mockups, notebook capture, guide/ask/riff, research) is routed to as-is, and nothing nags: the porch routes, it never blocks.
- Added cold capture that actually works: "don't let me forget X" in an uninitialized project now saves the note instead of erroring, anchored at your repo root no matter which subfolder you're in - and research lands there too, instead of scattering into whatever directory the shell happened to sit in. Capturing outside a git repo tells you exactly where the note landed. Run init later and everything you captured is already in the workshop.
- Fixed the slash menu doubling the plugin prefix: commands now read /craft:status, not /craft:craft:status.

## 2.0.1 - 2026-07-28

- Fixed brownfield setup dead-ending on design tokens. Initializing craft on an existing codebase used to drop a generic template file moments before your real scanned values were ready, then correctly refuse to overwrite it - leaving init stuck asking you to resolve a mess it created. Now nothing lands in tokens.yaml until there are real values to write: your extracted colors on UI projects, your scanned conventions on backend projects, written once, no roadblock.
- Changed how a mid-init design session settles color conflicts: your most recent decision wins. If you answer a conflict question early in setup and then lock different values from an inspiration session minutes later, the inspiration choice sticks - the earlier answer no longer bulldozes it.
- Changed the project-intent question to present its options neutrally. On a codebase you didn't found, skipping intent capture is just as right as filling it in, so neither answer claims to be recommended anymore.

## 2.0.0 - 2026-07-22

Craft 2.0 is the answer to the fairest criticism the first release got: a hard gate between Claude and your code is only safe until the ceremony makes you want to skip it - and a gate you skip once was never a gate, it was a suggestion. The 2.0 line taught craft to route instead of stop. Your codebase is still read-only by default, but a blocked write now hands Claude the doors that can open it - an investigated fix, a live tweak, a planned story - each with its own machinery to run before anything lands, and every one of them ending at your approval. Same strictness, a fraction of the friction.

And the records that killed the ceremony became the feature nobody planned: every reaction you give gets filed, so a pile of "Love it"s is literally your taste, sitting on file - and craft builds with it next time without being asked.

The pillars of the 2.0 line, in the order you'll probably meet them:

- **Live mockups.** Name something visual and `/craft:mockup` puts three genuinely different options in your browser - real scale, real context, at most one allowed to play it safe. You converge by reacting in plain words, watch micro-adjustments land in the open page, and accept when it's right. Works on a brand-new project with no setup at all.
- **A muse you can hear.** On a project with no design identity yet, craft's muse briefs the emotional job in its own words - quoted to you, never silently folded in - and authors the three directions the first round builds. Init distills what you're making into an Emotional Core that every later decision can feel.
- **Real materials.** When a mockup needs the actual typeface or icon set to be judged fairly, craft fetches the real thing from trusted open-license sources and builds it in. Nothing installs into your project, and when the design graduates, craft remembers what you chose and installs it the way your project expects.
- **Taste that compounds.** Accept a tweak with "Love it" and it doesn't just ship - it's remembered. Once enough loved changes accrue, the Taste Pass offers a victory lap: craft scouts other surfaces the same taste could reach and brings them to you, unprompted. Approved designs solidify into tokens that every later build is checked against.
- **Questions worth answering.** Craft's planning and alignment questions now ask the way a senior engineer would: plain language, real options only, the consequence of each choice up front, and your answers saved the moment you give them.
- **A gate that earns the trust.** Quality gates fingerprint the toolchains your repo actually has, validation only runs commands you've verified, and craft never approves a git push on your behalf - a clean push waits for your yes, every time.

Everything below this entry is the receipt trail: the 1.99 line is where each of these was built, tested live, and hardened.

## 1.99.54 - 2026-07-22

- Added real fonts and icons to mockups. When a mockup can't be judged fairly with a stand-in - the design needs the actual typeface, the actual icon set - craft now fetches the real thing from trusted open-license sources and builds it into the page. Nothing is installed into your project, and the mockup stays a single self-contained file that works anywhere. Licensed fonts craft can't fetch get one honest line and a tuned stand-in instead.
- Added memory for that material: when the mockup grows into a story or tweak, craft remembers which font or icon set you chose and installs it the way your project expects, instead of pasting the mockup's embedded copy into your code.
- Fixed slow, unreliable icon fetching: icons now arrive in seconds instead of minutes, a renamed icon resolves itself automatically, and an icon that genuinely doesn't exist is called out instead of silently left off the page.
- Changed git pushes: craft never approves a push for you anymore. It can still block a risky one, but a clean push always waits for your yes.
- Changed the mockup's muse option label to say what it does: "Let the muse drive."

## 1.99.52 - 2026-07-20

- Changed the mockup muse path to build-direct: the muse now authors exactly 3 candidate directions (with conviction, no ranking) and they build one-to-one as Diverge options A/B/C - no stance question to answer from prose. You aim by reacting to real builds. The taste-widget ceiling reads "at most three" to match.

## 1.99.51 - 2026-07-20

- Added the muse path to the mockup funnel: on a design-empty project the muse now briefs the emotional job and authors the vibe question itself; on a design-rich project a "Let's ask the muse" option joins the vibe question. The muse's work is shown and steerable - silent brief enrichment is gone.
- Fixed the alchemist's brief: the builder now receives the mockup record's Brief section whole and verbatim - including the full muse briefing - instead of a paraphrase of the picked direction. One definition of the brief everywhere.

## 1.99.50 - 2026-07-20

- Improved the mockup's first-run setup question after live testing: it now tells you craft hasn't met your taste yet and honestly describes what init's design session can do, instead of describing two doors neutrally.
- Changed the vibe question so a recommended muse option leads the list instead of trailing the inferred directions.
- Fixed mockup rounds silently converging to a single page: refine rounds always return variations unless you explicitly ask for one build, and vague reactions like "make it bigger" now get one clarifying question instead of a coin-flip guess.

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
