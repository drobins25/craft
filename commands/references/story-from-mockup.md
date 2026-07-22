# Story From Mockup (reference - read inline by craft:story-new Step 2.5)

Transforms a converged mockup record into a story. The mockup IS the extraction - no Explore agent, no gap-fill interview. It settles look and motion; scope and data shape still go through the normal story machinery (content-spark and alignment run on the created story like any other).

**The mockup's CSS is NORMATIVE.** The user approved working code in their browser. Implementers PORT its values, keyframes, and easing verbatim from mockup.html - they never reinterpret from appearance. Past mockup-to-story failures were exactly that reinterpretation: the mockup entered as inspiration and the implementer rebuilt from a screenshot. This reference exists to prevent it.

## Phase 1: Select the record

If the destination fork handed a specific mockup path (the usual case - this flow was entered from a graduation), use it. Otherwise list non-abandoned records:

```bash
grep -L "^status: abandoned" "$CRAFT_PROJECT_ROOT"/.craft/mockups/*/record.md 2>/dev/null
```

One record: use it, confirm conversationally ("Building the story from [slug]"). Several: ask conversationally which one - no AskUserQuestion; the fork already spent the flow's question budget.

Read the full record: frontmatter, `## Brief`, `## Reactions`, `## New Values`, plus mockup.html itself.

## Phase 2: Surface re-check (parked mockups)

If the record's `status` is `parked` - or `created` is more than a few days old - re-verify the target surface still exists as mocked BEFORE any pre-fill: read the current component/page the mockup was built against and compare structure (sections present, element ids, surrounding context). Structural drift is surfaced to the user first ("the mockup shows a 3-item nav; the surface now has 5") - they decide whether the mockup still stands, needs a refresh round, or the story should absorb the drift. Never silently pre-fill a story against a surface that no longer matches.

Fresh graduations (converged this session) skip this phase.

## Phase 3: Write the story

Target: `.craft/backlog/[story-name].md`, standard frontmatter (see craft-story-new Step 10) plus the backlink:

```markdown
mockup: [record name, e.g. 2026-07-05-hero-pulse]
grew_from: [the record's origin tweak, when the record carries one - omit or leave empty otherwise]
```

Type is almost always `ui`. Set `alignment: pending` - the alignment check fires at implement time as usual.

**Lineage:** if the mockup record carries an `origin` (it grew from a taste-pass todo), forward it as `grew_from:` on the produced story - so a taste-pass outcome traces home even when it snowballed from a single tweak into a whole story, however far it diverged from the seed.

**Pre-filled sections:**

- **`## Spark`** - from the record's `## Brief` (what was mocked and why) + the accepted finalist's character from `## Reactions` (the user's own accepting words are the best spark material there is). Pull voice from verbatim reaction lines only - `Settled:` sub-lines are derived convergence context, never quoted as the user's words.

- **`## Visual Direction`** - cites the mockup as the authority:
  ```markdown
  **Vibe:** [from the record's Brief]
  **Source mockup:** .craft/mockups/[name]/mockup.html - NORMATIVE. Port CSS
  values, keyframes, and easing verbatim; never reinterpret from appearance.
  **Motion:** [named keyframes/transitions in mockup.html, with their timing]
  ```

- **Element Binding Table** - one row per mockup element, Value/Source = mockup anchors (HTML id or data-section attribute):
  ```markdown
  | Part | Role/State | Token | Value/Source |
  |------|------------|-------|--------------|
  | [element] | [role/state] | [token or -] | mockup `#hero-pulse` |
  ```
  Every element the mockup settles gets a row. Planning validation requires every non-TBD row bound by a `[visual-source:]` contract - partial adoption of the mockup becomes a blocked plan, not a silent omission.

- **`## Reference Materials`** - under the existing Mockup files category (anchor conventions per story-from-planning):
  ```markdown
  **Mockup files:**
  - [absolute path]/mockup.html (`#[id]` / `[data-section]` anchors per element)
  - [absolute path]/record.md (`## Brief`, `## New Values`, solidify outcome)
  ```

- **`## Likely Files`** - scan as usual (the surface the mockup targets names them).

**No token payload.** Tokens were settled at the mockup's solidify beat - the bible is already true, and plan-chunks, chunk-validator, and style-analyzer enforce it with no exceptions. If the record shows a solidify DECLINE, note it in `## Notes`: the mockup-local values will surface as known drift, user-chosen.

**Materials port as a spec, never as bytes.** Read record.md `## Materials`; when non-empty, the produced story carries the material spec as a requirement - the typeface's identity (family, weights, source) or the icon set by name - and states that acquisition is resolved at the story's own plan-chunks per the project's idiom: a package where packages are the idiom (next/font, `@fontsource/*`), a static-asset `@font-face` copy only where static assets are the idiom. The mockup's inlined base64 is never ported. This is the one stack-resolved carve inside the NORMATIVE rule: family, weight, style, and every type measurement still port verbatim - only the acquisition mechanism (where the font file comes from) is resolved against the project. An icon entry is guidance to adopt the library's components, never a verbatim SVG-blob port. Empty `## Materials`: the port behaves exactly as it always has.

## Phase 4: Backlinks and close

Write both directions: the story frontmatter carries `mockup:` and, when the record had an `origin`, `grew_from:` (both done above); the record gets `graduated_to: [story name]` and `status: graduated-story` (the destination fork may have written these already - verify, don't duplicate).

Report the created story path and its pre-filled sections. The parent flow is DONE - the story takes the normal path from here (cycle-assign, plan-chunks, implement).
