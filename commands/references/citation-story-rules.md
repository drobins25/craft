# Rules for a story with planning sources

`hooks/scripts/story-rules.sh` prints the part below to the planner when a story was written from a planning concept (`source_concept:`), or its Reference Materials cite a planning log (`active.md`) or a research file. `story-from-planning.md` and `research-inline.md` write those citations. The part is printed without its heading.

## planner

The story's Reference Materials are how planning reached this story. Read every one, as your own instructions say; these rules say what each kind is worth when two of them disagree, and what to report when one is broken.

- **A dated entry in a planning log (`active.md`) is the current state.** Where it and the concept's own text disagree on the same decision, the log wins, because it is the later record.
- **A concept section is the reason behind a decision.** Apply the decision as written and do not work it out again.
- **A locked pattern is applied, not re-invented. A sibling story is a shape to mirror, not text to copy.**
- **A research finding is evidence from outside the project.** It ranks below locked patterns, concept decisions and the Spark, and never overrides one. Where it contradicts one, raise a low-confidence concern.
- **A citation that no longer resolves** is a concern that names the file, the anchor as cited and the story's `created:` date, and offers two ways out: create the story from planning again to refresh its citations, or go on if the decision has not changed. The date lets the user judge how stale it is.
- **A cited file over 500 lines with no anchor** is a concern too. Never read it whole on a guess.
- **A story written from a planning concept that cites nothing** has lost its hand-off. The concern names the `source_concept` value and the story's `created:` date and offers two ways out: create the story from planning again so its citations get written, or give the absolute paths of the concept and any mockup so the section can be added before planning. Never follow `source_concept` as a path or go looking for the concept, because a guessed file would be planned as if the user had cited it.
