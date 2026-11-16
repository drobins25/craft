# Rules for a story with a Motion line

`hooks/scripts/story-rules.sh` prints one part of this file to the planner or the builder when a story has a `**Motion:**` line and names no mockup. A story built from a mockup takes its motion from the mockup instead, under `mockup-story-rules.md`. Each part is printed without its heading.

## planner

The story's Motion line says what should move, in the user's words. The motion catalog named above fills in what the line leaves open, so the builder does not invent timing.

- **Map each item on the Motion line to a catalog pattern.** Read the catalog, and for each item write into the contract the pattern, its timing and easing, what triggers it, and what happens under `prefers-reduced-motion`. A duration, easing or distance the line itself states goes in unchanged, because the user wrote it. Where no catalog was found or no pattern fits an item, write the contract from the line's words and list it as a concern.
- **Motion goes in the chunk that builds its element,** never in a chunk that only adds motion, because the element is not finished without it.

## builder

- **Motion follows the chunk.** Use the pattern, timing and easing the chunk gives. Where your chunk builds something that moves and gives no timing for it, use the project's transition tokens (`tokens.yaml`), or 150ms ease for small interactions and 300ms for page transitions where it has none, so motion stays consistent across the project.
- **Honor `prefers-reduced-motion`** on everything that moves.
