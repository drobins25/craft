# Insight Mining (Inline Reference)

Read inline by `/craft:dashboard` Step 2.5 when the insight sidecar is stale or missing. You are about to author `.craft/graph/insights.js` - the 3-4 insight cards the dashboard composes over the user's galaxy. The cards are built from the user's own preserved words, and recognition is the payload: the reader's "oh right, that day" is what a card is for. A deterministic script cannot hear a human voice in a record, which is why this file is a spec for YOU, not a script to run.

Everything here is silent work. No receipt line, no "generating insights" - the page itself is the reveal.

## The two hard rules (read first)

**1. The citation gate.** A card is written only if it cites at least one `evidence_node_ids` entry that exists in `graph.js` right now. A card that cannot cite real evidence is discarded - never softened, never shipped without its receipts. An unevidenced card would stand in-frame as a fortune cookie, and the page will render it anyway (it drops only the marks for vanished ids), so this authoring-time citation gate is the only defense.

**2. The mirror rule.** Structural signals - counts, dates, statuses, hubs - are ONLY an index for choosing which record mirrors to spend the reading budget on. **The card body is always built from what is inside a mirror: the user's own preserved words, and the memory of what they were doing when they said them.** A finalist whose mirror yields no human material is cut, never padded into a stat card. Stats never form a card body on their own.

**Evidence order is normative: the FIRST `evidence_node_ids` entry is the quote's source record.** The page derives the witness, the standoff ring, the hover warmth, and the eyebrow date badge from `evidence_node_ids[0]` - always put the record the quote came from first; supporting evidence follows.

## Mining inputs, in order

Parse the JSON after `window.CRAFT_GRAPH = ` in `<root>/.craft/graph/graph.js`. Spend the reading budget in this order:

1. **`graph.stats`** - orientation, one field lookup each: `birthday`, `days_of_craft`, per-type `counts`, and `keystone {id, degree, kind}` (the biggest hub in the sky).
2. **`graph.nodes`** - scan for finalists using the ranking below. Every node carries `id, type, title, date, status, tags` (+ `subtype`, `kind`, `chunks` where relevant). Tweak and dial nodes are the richest veins - tweak records log the user's verbatim reaction per attempt, and dial records preserve exit notes.
3. **`records/{id}.js` mirrors** - read AT MOST 8, and only for finalists, after ranking. Each assigns the record's full markdown to `window.CRAFT_RECORDS["{id}"]`. This is where the voice lives - a verbatim line, a real reaction, the subject the human was actually deciding. Never read mirrors speculatively; the budget buys voice, not coverage.

## Ranking - the quote patterns, strongest first

A card wants a preserved human quote. Rank finalists by which pattern their records promise:

1. **The reversal** - one record holding two verbatim, contradictory reactions from the user (the opening complaint and the closing "Love it"). Tweak records log reactions per attempt - look there first.
2. **The reverse-roast** - the user roasting the machine's own output, preserved in a record (dial exit notes on `outcome: nothing` are prime).
3. **The prophecy** - a record where one player narrates the other (a riff memory noting what the user predicted or did).
4. **The epitaph** - the kill quote on an abandoned, reverted, or rejected record, in the user's words.

Structural outliers - the singleton type, the oldest still-open record, same-day streaks, `stats.keystone`, killed outcomes - are how you CHOOSE which mirrors to open. They rank finalists; they never write cards. Pick the 3-4 strongest, fresh-picked every generation: the roster is a category, not a fixed set, and every screenshot should be different.

## Card body formula

**Quote first, memory second.** The verbatim line is the hook; the what-you-were-deciding context is the reveal that fires recognition.

Shape: `"<verbatim quote>" <what the record was actually about, in plain words>.` An optional short dry closer is allowed only if it is itself a fact from the record.

- **Quote budget: at most TWO quoted strings per card.** One is the default; a reversal earns the second. Three quotes is a paragraph doing a card's job - cut.
- **No date in the body.** The page renders the quote-source record's date as a badge in the card chrome, derived from the first evidence node - a body that opens "August 26th, ..." says it twice. The date stays out of the prose entirely.
- **Citable beats only.** "Same record", "attempt 2", "the next reaction on file" - connective tissue comes from the record's real structure. Records carry dates, not clock times: NEVER an invented duration ("forty minutes later" is fabrication).
- **Name the memory.** The card says what the conversation was about - the surface, the decision - so the reader lands back in it. A quote floating without its memory is half a card.

## Register - how a card speaks

Binding rules, no exceptions:

- **Second person.** The card talks to the user about their own work.
- **Deadpan clerk voice - the card never knows it's funny.** It files the user's words with a straight face; the reader's discovery is the punchline. A card that performs (winks, exclaims, dresses up) kills the joke it carries.
- **Affectionate roast, never snark.** The voice is a friend who kept receipts and loves you anyway.
- **Quotes verbatim and exact.** Typos, profanity, capitalization - preserved as written. Never sanitize, never paraphrase inside quote marks. The typo is load-bearing.
- **One specific fact PLUS one turn of phrase per card.** The quote is the fact-carrier; the memory line carries the feeling. Restraint over flourish.
- **Receipts in-frame.** Everything stated must be verifiable from the cited evidence nodes and the mirrors read.
- **Never a bare number as the whole card.** A count with no voice behind it is a dashboard stat tile, and stat tiles are exactly what this is not.
- **No gamified cheer.** No "Great job!", no confetti energy.
- **No stat-tile phrasing.** Nothing that would fit on an admin dashboard.

### Exemplars (fabricated corpus - match this register, never this content)

One per pattern. Shapes to match; every fact below is invented:

1. Reversal: `"This button is hideous." The tweak that restyled the export button. Same record, attempt 3: "perfect, don't touch it."`
2. Reverse-roast: `"these are all cowards." The dial that offered five spacings for the sidebar. The record lists what was chosen: none.`
3. Prophecy: `"She called the crash before the test finished running." The other player's notes from your one riff. She is you.`
4. Epitaph: `"turns out nobody wanted this, including me." The one abandoned tweak of forty. It died honest.`

## Witness assignment

Each card carries a `witness` field - a one-line attribution the page renders verbatim after `witnessed by `. Assign it from the type of the card's FIRST evidence node:

| First evidence node type | witness |
|---|---|
| cycle / story / planning | `the conductor` |
| mockup / notebook | `the muse` |
| fix / tweak / dial | `the alchemist` |
| riff | `riff` |
| anything else | `the muse` |

The witness line is attribution, machine voice: it never carries the joke, never varies its template, and is written exactly as the page will render it. The roster is exactly these four personas - the conductor, the muse, the alchemist, riff. Quotes concentrate in tweaks and dials, so left alone every card testifies for the alchemist: **when finalists are close in strength, prefer the set that spreads witnesses.** Never force it - a weaker card is not worth a varied roster.

## Write procedure

**Fewer than 3 mirror-backed cards survived mining? Stop here** - write no sidecar and do not run `--stamp`. This is the early return; "When there is too little material" below explains why.

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/dashboard/insights-check.sh --check --root "$PROJECT"` if you have not already this run - its `GRAPH_SHA` is the sha you write, and `SIDECAR` is the path you write to.
2. Read the existing sidecar's `cards` and `history` if the file exists. The new `history` is the previous generation's card bodies prepended to the old history, capped at 8, most recent first. **The new set must not repeat a body in `history`** - that is what the field exists for.
3. Write the sidecar as ONE line, assigning the global exactly like the builder's own output:

```
window.CRAFT_INSIGHTS = {"version":1,"generated_at":"<ISO8601 now>","graph_sha":"<GRAPH_SHA from the check>","cards":[{"body":"<the insight>","witness":"<from the table above>","evidence_node_ids":["<node id present in graph.js>"]}],"history":["<prior card body>"]};
```

   `cards` holds 3-4 entries. The sidecar carries NO hue, NO pin or corner, NO eyebrow text and NO record type - content and evidence are the sidecar's; geometry and chrome are the page's, derived from the live graph so the chrome can never contradict its citation.
4. Stamp the receipt so the next run's verdict is correct:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/dashboard/insights-check.sh --stamp --root "$PROJECT"
```

The file is per-machine (`.craft/graph/` is gitignored `*`) and never committed.

## When there is too little material

A corpus with fewer than 3 mirror-backed cards gets NO sidecar - do not write one, do not pad with "you have 2 records". The galaxy renders alone, which is the designed empty state. Padding is the fortune-cookie failure this whole spec exists to prevent.

A young corpus usually has records but no preserved voice yet - reactions and exit notes accumulate over weeks of tweaks and dials. That is the no-sidecar case, not a reason to reach for stats. The cards simply appear one day, unannounced, once the user's own words exist in the record. Let them.
