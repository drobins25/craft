# Rules for a story built from a mockup

`hooks/scripts/story-rules.sh` prints one part of this file to the planner or the builder when a story's frontmatter names a mockup. `story-from-mockup.md` writes such a story and marks the mockup NORMATIVE; these are the rules that line depends on. Each part is addressed to one reader and is printed without its heading.

## planner

The user approved this mockup as working code in their browser, so the mockup file is the look and the motion, and the plan's job is to carry it over unchanged. A plan that describes the look in its own words gets rebuilt from appearance, and that has shipped the wrong page before.

- **The mockup is the visual contract.** Layout, order, values and motion come from its markup and CSS at the anchors the story cites. Where the story and the mockup disagree and the story has not said which wins, pin the mockup's value, rate the decision `ask` and name both, so the user sees the choice.
- **Bind to the anchor.** Each binding contract's `[visual-source:]` receipt names the mockup anchor (an id, a selector or a line range), so the builder knows where to copy from. When the story has no binding table the mockup is still the contract: pin each element it settles the same way, and say in your concerns that the table was missing.
- **Motion is ported, not designed.** Take timing, easing and keyframes from the mockup and write the values into the contract. Where a keyframe sequence or an SVG path cannot be given as values, copy that code into the chunk exactly; this is a case where the exact code is the decision. Motion goes in the chunk that builds its element, never in a chunk that only adds motion, because the element is not finished without it. When the mockup has no `prefers-reduced-motion` rule, pin one: it changes nothing the user approved.
- **An empty project starts from the mockup.** When the project root has no manifest, build config or entry file (check with Glob, not from an impression), the first chunk brings in the mockup's markup and CSS as the base page in the project's framework, values untouched, so the approved page is the starting point and not a retyped copy. A project that already has a skeleton never gets this chunk.

## builder

The user approved this mockup as working code in their browser. For everything it settles, your job is to carry it over, not to redesign it.

- **Copy from the file, never from how it looks.** Open the mockup at the anchor each contract cites and take from its text whatever the contract does not state. Where the contract states a value or a token, build the contract's and say in your report where it differs from the mockup, because the difference may be the user's ruling.
- **Tokens first, the mockup's value otherwise.** Where a copied value equals a token's value, write the token. Where none equals it, keep the mockup's value and list it under Deviations as "no token", because the user chose it on screen and the nearest token would change what they approved.
- **Reduced motion.** Honor `prefers-reduced-motion` on everything that moves.
- **Harden around the look, not through it.** Guards for real inputs (empty, long, hostile, missing) add markup and declarations and never alter a ported value.
- **Check before you report.** For each element your chunk binds, compare what you built with the mockup at its anchor, and under Proof list each anchor compared and any value that differs.
