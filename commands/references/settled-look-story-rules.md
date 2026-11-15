# Rules for a story whose look is settled and whose binding table is missing

`hooks/scripts/story-rules.sh` prints one part of this file to the orchestrator (the plan-chunks skill) before it plans, when a story came from a mockup, an annotate run or a dial and its `## Visual Direction` has no binding table. A story that has its table prints nothing. Each part is printed without its heading, under the facts the script checked.

## orchestrator, mockup

The user approved this story's look in the mockup named above. The binding table is how that look reaches the planner, and this story has none.

- **Build the table before you launch the planner.** Read the file named above and follow its Element Binding Table step against this story and this mockup: one row for each element the mockup settles, its source the mockup anchor. Write the table into the story's `## Visual Direction` and change nothing else in the story.
- **Never offer to explore visual options for this story.** The look is settled, and an offer to riff invites the user to redo what they already approved.
- **Tell the user in one line** that the table was missing, that you built it from the mockup, and how many rows it has.

## orchestrator, annotate

The user approved this story's look on a live page, in the annotate run named above. The binding table is how that look reaches the planner, and this story has none.

- **Build the table before you launch the planner.** Read the file named above and follow its Element Binding Table step against this story and the run's sheet: one row for each change that carries a look, its value the rule the sheet holds. That file says which changes stand in for content and get a Scope line and no row. Write the table into the story's `## Visual Direction` and change nothing else in the story.
- **Never offer to explore visual options for this story.** The look is settled, and an offer to riff invites the user to redo what they already approved.
- **Tell the user in one line** that the table was missing, that you built it from the annotate run, and how many rows it has.

## orchestrator, dial

The user settled part of this story's look on a dial, on the live page. A dial record holds which position they chose and what they said. It does not hold the values behind the position, so no table can be built from it.

- **Never offer to explore visual options for this story.** The look is settled, and an offer to riff invites the user to redo what they already chose.
- **Where the story's own text gives the chosen values, plan from them as written.** Where it gives only the position letter, tell the user in one line that the values are not written down, so they can supply them. Never work a value out from the letter.
