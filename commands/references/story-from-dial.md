# Story From Dial (reference - read inline by the dial flow's story exit)

Turns a dial's outcome into a story. The user chose one position on their own page, against real data, so what the page showed for that position is settled. Nothing else becomes a requirement: not the positions they passed, not a value the page never showed them, not anything you would add to round the look out. The user judged only what was on their screen.

You arrive with the story (the path of one that already exists, or the name for a new one; either way it is already filed on the dial record), the record's path, the chosen letter, the user's verbatim words, and the result of the dial flow's READ: what that position put on the page and what the page showed for it. This flow asks nothing through a widget: the dial flow allows none at any exit. For the story's frontmatter, Read only the frontmatter block of Step 10 in `${CLAUDE_PLUGIN_ROOT}/commands/craft-story-new.md`, and take `priority: medium`.

## The rows

Every value in the table comes from READ's result. Never work a value out from the letter, the record, the CSS you remember injecting or your memory of the session: a value arrived at that way would be a guess presented as their choice.

One row for each entry in `rules`, under `| Part | Role/State | Token | Value/Source |`:

- **Part** - what the rule styles, in plain words. Start it with a word, never a bracket. A `::before` or `::after` in the selector is a piece of its own ("label in front of the filter row"), not a state.
- **Role/State** - `default`, or the state the selector names (`:hover`). When the rule has a `condition`, the condition goes here too, as written: `default, under @media (max-width: 600px)`.
- **Value/Source** - `` `[selector] { [declarations] }` - dial [LETTER] ``, on every row including a `TBD` one, and nothing else in the cell: planning pins this cell's value exactly as written. The selector is an anchor that helps the builder find the element in source; it was written against the live page and is never ported as structure. Write a `|` inside this cell as `\|`.
  - **Write the declarations as injected,** in their short form. `showed` is how you check them, property by property (it names properties in their long form: `padding` comes back as its four sides).
  - **A value lost** when the injected value is a plain one (a pixel length, a color, a number, a keyword) and the page showed a different plain value: injected `padding: 22px`, showed `8px`. The page's own styles won, so the position changed nothing there and the user never saw 22px. Leave that declaration out of the row (and leave the row out when nothing else is in it): there is nothing to build. List it under the table (below), so the user knows the dial tried it.
  - **A value did not lose** when the page showed the same thing in another form. An injected `1.5rem` or `var(--gap-md)` that showed as `24px`, a color given as `#eee` that showed as `rgb(238, 238, 238)`, and any length the layout works out (`50%`, `auto`, `calc(...)`, `1fr`, `normal`) that showed as pixels: all are written as injected. The pixels are only what that window came to.
  - **`showed` is null:** nothing could be read back. Mark the row `TBD` in the Token cell and write the injected declarations. One exception: when `visible` is 0, `matched` is above 0 and the rule itself hides the element (`display: none`, `visibility: hidden`), the user saw it hidden, and the row is written as injected.
  - **`applies` is false or null:** the rule sits under a condition that was not in force at the size the user chose on, or one the page could not be asked about, so nobody can say they saw it. Mark the row `TBD` and write the injected declarations.
- **Token** - the project token whose value equals the row's, or `-`; never the nearest one. `TBD` in the cases above and for a qualified choice (below).

Under the table, when any row needs it, one line each:

- `**Tried and never shown:** [Part] - the dial injected [property: value]; the page kept [value].`
- `**To settle:** [Part] - [not read back | not shown at the size chosen on | could not tell whether it applied | their words, quoted].` Planning takes each `TBD` row to the user.

**An element the position added** (`added`) gets a row when it could be `seen`: Part names it, Role/State says what it is for, and Value/Source quotes its markup and names where it sat (`inside`). Its look is in the rules that style it, which have rows of their own. What it does when used is not in its markup: take that from the user's own words, and where they said nothing, write nothing. An added element that could not be seen gets no row.

**Keyframes** in `keyframes` go on one line above the table, quoted whole: `**Motion:** [the @keyframes text]`.

**When the user qualified the choice.** Their landing words are part of what they chose.
- A qualifier on a value ("C, but a little looser"): the row for that property is marked `TBD`, and its `**To settle:**` line quotes their words. They did not choose that value. When you cannot tell which rows their words reach ("C, but calmer"), every row is `TBD`: a guess at which ones would settle part of the look for them.
- A qualifier that widens where it applies ("B, but on the cards too"): the table keeps only what the page showed. Add a line under `## Scope` quoting their words, so planning carries the wider ask without a value nobody saw there.

**When nothing could be read** (`readable` is false, or `rules` and `added` are both empty), write no table and say so in one line at the close.

## Into a story that already exists

The usual case: the dial settled one part of a story that is already written, and often already planned. Change only what the dial settled. Every other line of the story stays as it is.

1. **The header.** `dial:` names the record (its file name, without `.md`). When the header already names other dials, put this one on the same line after them, separated by a space.
2. **`## Visual Direction`** (add the heading directly above `## Acceptance` when the story has none). Add the `**Source dial:**` line as shown below, one line for each dial the story carries, and the Motion line when there are keyframes and the story has none.
3. **Sort the rows by where the story stands.**
   - **No `### Chunk` headings yet:** every row goes in the table. Planning binds them.
   - **Planned:** chunks 1 through `chunks_complete` are complete and are never edited. A row goes in the table only when a chunk still to build builds that part (its Goal, Files and Contracts say). When two of them touch one part, the row belongs to the earlier one, the chunk that first makes the part. A part a complete chunk already built is shipped work: it gets no row, and the close says that porting it is a tweak. A part no chunk builds gets no row either, and the close says so, so the user can decide whether the story grows.
4. **A part the table already has a row for.** The user just chose on the live page, so their choice is the newer one: replace that row's value in place, never add a second row for the same part in the same state, and say so in the close. The same goes for a Contracts line in a chunk still to build that states a different value for that part.
5. **Each chunk still to build,** for each row it builds that is not `TBD`:
   - one line in its **Contracts**, shaped like the lines already there: `- [Part], [Role/State]: [the token, or the row's declarations] - new [visual-source: binding table row "[Part]", dial [LETTER]]`
   - one item in its **Done When**: `- [ ] [Part] is built as dial [LETTER] showed it`
   - one entry under an `**Amendments:**` heading in that chunk: the date, "bound to dial [record name], position [LETTER], chosen while the story was being built", and that the plan as written did not carry this value.
6. **`TBD` rows on a planned story** have no planning step ahead of them to settle them, so the close asks: list each one with its `**To settle:**` line and ask the user for the value. When they answer, fill the row and add its contract line the same way.
7. **`## Reference Materials`** - add `**Dial record:**` and the record's absolute path, when a record exists.

Edit in place with targeted edits, skipping anything already there, so a second pass after a session that died adds nothing twice.

## A new story

Target: `.craft/backlog/[story name].md` under the project root the dial exit resolved (the cold root on a project not yet onboarded), under the name you were given. Frontmatter as above plus `dial: [dial record's file name, without .md]`, left out when no record was filed. Type is `ui`. Set `alignment: pending`.

- **`## Spark`** - what the user asked this story to be, in their words, then their reaction at the choice. Quote; never paraphrase. When all they said was "make that a story", the Spark is the dial's subject and their reaction, and nothing wider.
- **`## Visual Direction`** - one line, the Motion line when there is one, then the table:
  ```markdown
  **Source dial:** [dial record's file name, without .md], position [LETTER] - chosen on the live page; build these values as written.

  | Part | Role/State | Token | Value/Source |
  |------|------------|-------|--------------|
  | Filter row | default | - | `.filter-row { gap: 22px }` - dial C |
  ```
  With no record filed (a project not yet onboarded), the line reads: `**Source dial:** position [LETTER], chosen on the live page; no dial record was kept, because this project is not set up yet. Build these values as written.`
- **`## Scope`** - only when a qualifier widened the ask (above).
- **`## Reference Materials`** - `**Dial record:**` and the record's absolute path, when a record exists.
- **`## Likely Files`** - scan as usual; the selectors in the rows name the surface.

## Close

Say where the story is and how many rows it carries; for a new story, that it was filed at medium priority; for a story that already existed, which chunks got a line. Then one line for each thing the user should know and would not otherwise see:

- each value the dial tried that the page never showed, which is left out of the story;
- each `TBD` row and why;
- an added element that got no row: it could not be seen, or it carried no letter (`unlettered`);
- elements of other positions that were on screen at the choice (`strays`), since the user may have judged them too;
- part of the position that could not be read (`nested` above zero);
- a row whose value replaced one the story already had;
- a part that is already built (porting it is a tweak) or that no chunk builds;
- that no table was written, when nothing could be read.

A new story takes the normal path from here, and a story that was being built carries on from the chunk it was at. Planning offers no visual options on a story that carries a dial, so any part of its look beyond the table comes from what the story's text says, or from a mockup or another dial when the user asks for one.
