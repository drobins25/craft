# Mockup Into the Story Being Built (reference - read inline by the mockup flow's destination step)

A mockup made while a story is being built settles how part of that story looks. This puts the look into the story, so the chunks still to build carry it over. The user approved the mockup moments ago and is in the conversation, so anything the files cannot settle is asked, in conversation. This flow uses no AskUserQuestion: the mockup flow has already spent its question budget.

Every value you write into the story is copied from the mockup file at its anchor, never described from how the page looks, because the builder takes its expected values from what you wrote.

## 1. Find what changes (write nothing yet)

- **The story file** is the one in the active cycle's `stories` folder whose name contains `CURRENT_STORY`. Its title is the name the card showed.
- **The accepted option:** the record's `## Reactions` holds the user's accepting words and the option they were for. Work from that option only. The mockup file can be very large and hold inlined images, so search it for anchors and read only the matching ranges.
- **The parts:** a part is something the user would point at and name on the page: a region or a control (the panel, its title, the reading well, the work list, a toggle), or a state of one that the user gets to by doing something (hover, selected, open, empty, error). The pieces that make it up ride with it, their anchors listed beside its own: its dots, glyphs, ticks, dividers and scrollbars, the overlays drawn with `::before` or `::after`, and the type inside it. A variant that only adjusts one effect of a part (an edge fade that changes with scroll position, a reduced-motion version of an entrance) stays with that part, named in its Role/State, and an entrance or a reveal is named there and on the story's Motion line, never as a part of its own. The builder copies every value from the mockup at those anchors, so the job here is to name each thing once, not to list every rule: one panel or screen comes to about a dozen parts, and several dozen means pieces have been split out. The mockup's own scaffolding (labels, replay buttons, staging behind the design) is not a part. For each part note its anchors (mockup `#id`, mockup `[data-section="name"]`, or mockup `.class` where it has neither) and its token: the project token the record's `## New Values` gives it, when the record's `solidify_outcome` says those values were solidified; otherwise `-`, and the mockup's own value is what the plan carries.
- **The chunks:** chunks 1 through `chunks_complete` are complete and are never edited. Every later chunk is still to build. For each part, find every chunk still to build that builds any of it; its Goal, Files and Contracts say. That sorts the parts three ways: built by a chunk still to build (these get rows and contract lines), already built, and built by no chunk (these get neither, and step 4 tells the user about each). When the story has no `### Chunk` headings yet there are no chunks to bind: every part gets a row in step 3 and you stop there, because planning binds them.
- **What only the user can settle:**
  - a part where a row already in the table, or a Contracts, Done When or Acceptance line that a chunk still to build answers to, says something different from the mockup;
  - a part that two chunks still to build could each be the one to build;
  - a part whose token is described in the project's tokens as something the mockup does not show (a highlight the mockup took out, a size it changed), since the builder builds the token;
  - the chunk in progress (number `chunks_complete + 1`), when its build has already started: its builder has not seen this look.

## 2. Ask once, if anything is unsettled

Ask one question in conversation that lists everything from the last bullet: for each conflicting part, both values and which holds; for each part two chunks could build, which one; for a chunk already under way, whether it is rebuilt with the look or left as built. The plan was approved before this mockup existed, and only the user can say what the mockup replaces. With nothing unsettled, ask nothing.

Where the user says the mockup holds, replace that row's value or that contract's value in place, so the story never carries two values for one part. Where the existing one holds, that part gets no new row or line.

## 3. Write

Edit the story in place with targeted edits, in this order, and skip anything that is already there, so a second pass after a session that died adds nothing twice.

- **The story's header:** `mockup:` names this record. When it already names others, put this one on the same line after them, separated by a space (a comma breaks the lookup), and replace an empty value or `none`.
- **`## Visual Direction`** (add the heading directly above `## Acceptance` when the story has none):
  - the source line, unless the story already has one for this mockup: `**Source mockup:** .craft/mockups/[name]/mockup.html - NORMATIVE. Port CSS values, keyframes, and easing verbatim; never reinterpret from appearance.`
  - a `**Motion:**` line naming the mockup's keyframes and transitions with their timing, when the mockup has any and the story has no Motion line;
  - one row under `| Part | Role/State | Token | Value/Source |` for each part a chunk still to build builds, in place of the template's bracketed placeholder row when that is all the table holds. Every row written here has a contract line below, which is what the plan check expects of a row.
- **Each chunk still to build,** for each part it builds:
  - one line in its **Contracts**, shaped like the lines already there: `- [Part], [Role/State]: [the token, or where the row has none the declarations copied from the mockup at the part's own anchor]; pieces at [the anchors of the pieces that ride in the row] - new [visual-source: mockup <anchor>]`. One line a part, not one a rule: the builder is handed the mockup and copies the pieces from their anchors.
  - one item in its **Done When**: `- [ ] [Part] matches the mockup at <anchor>`
  - one entry for the chunk, not one a part, under an `**Amendments:**` heading at its end, naming the parts: the date, "bound to mockup [name], approved while the story was being built", and that the plan as written did not carry this look.
- **Materials:** when the record's `## Materials` is non-empty, carry the material into the story as a spec, the way `story-from-mockup.md` says ("Materials port as a spec, never as bytes").
- **The record, last:** `graduated_to: [story name]` and `status: graduated-story`. Last, so a session that dies partway leaves the record as it was and this step can run again.

## 4. Tell the user what changed

In plain words, in this order:

- The rows added, and the line added to each chunk still to build for each.
- A chunk that now carries more than about ten contract lines, since the plan's own limit says that chunk may want splitting.
- Each part the mockup settles that is already built. It stays as built, and nothing here restyles it. Say in one line that restyling built parts is a separate change they can ask for, a tweak with this mockup as its settled direction, and do not start it.
- Each part the mockup settles that no chunk builds, so the user can decide whether the story grows.
- Anything on today's page that the accepted option no longer shows, when the record says it was taken out: nothing here removes it.

## 5. Return to the build

The story carries on from the chunk it was at: in this conversation when the build is running here, otherwise the next time the story is continued. The builder of every later chunk is handed the mockup because the story's header now names it.
