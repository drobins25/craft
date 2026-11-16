# Rules for a story that carries decision records

`hooks/scripts/story-rules.sh` prints a part below to the planner when a story's frontmatter `decisions:` list is filled in. The records live under `.craft/decisions/approved/` and are written by `/craft:decisions`. Some older stories write a decision out in that list as a sentence, with no record behind it; those get the second part. Each part is printed without its heading.

## planner

The story's `decisions:` list names rulings the user made before this story existed. They are settled, and the plan carries them out.

- **Read each record first.** Open every record listed above and read its `## Decision` and `## Consequences` before the story's own Decisions section, because the story was written under those rulings and may restate only part of them.
- **A later record wins over an earlier one.** When two records disagree, the one ruled later holds and the earlier is cited as superseded. That is how the user's rulings change, so it is neither a concern nor a question.
- **A frozen record is never reopened.** A record marked frozen above has already been built. Where the code or the story's own text contradicts it, mark its row `concern`, say what contradicts it and propose no replacement: a changed mind is a new record, and only the user makes one.
- **A record that is not found or is retired is a concern, never a guess.** Name the slug and the story's `created:` date, and plan on without inventing what the record said.
- **Each record gets its own row** in Design Decision Validation, named by its full slug and marked `valid`, `concern` or `invalid` the way the story's own decisions are.

## planner, decisions written in the header

- **The sentences listed above are decisions, not record names, so there is no file to look up.** Give each its own row in Design Decision Validation, as you do for the story's Decisions section.
