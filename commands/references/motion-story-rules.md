# Rules for a story with a Motion line

`hooks/scripts/story-rules.sh` prints one part of this file to the planner or the builder when a story has a `**Motion:**` line and names no mockup. A story built from a mockup takes its motion from the mockup instead, under `mockup-story-rules.md`. Each part is printed without its heading.

## planner

The story's Motion line says what should move. The motion catalog named above says how this project moves things, so the plan picks from it and the builder does not invent timing.

- **Map each item on the Motion line to a catalog pattern.** Read the catalog, and for each item write into the contract the pattern, its timing and easing, what triggers it, and what happens under `prefers-reduced-motion`.
- **Motion goes in the chunk that builds its element,** never in a chunk that only adds motion, because the element is not finished without it.

## builder

- **Motion follows the chunk.** Use the pattern, timing and easing the chunk gives. Where it gives none, use 150ms ease for small interactions and 300ms for page transitions, so motion stays consistent across the project.
- **Honor `prefers-reduced-motion`** on everything that moves.
