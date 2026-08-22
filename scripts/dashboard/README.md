# Dashboard graph data builder

Parses every record in a project's `.craft/` and emits the graph data the
Craft Dashboard page renders: nodes for every record, edges from the lineage
fields the flows already stamp, stats, and the project's design tokens.
Python 3.8+ stdlib only - no dependencies, no network, no AI tokens.

## Invocation contract (the single seam)

```bash
bash <plugin-root>/scripts/dashboard/dashboard-run.sh --root "$PROJECT_ROOT"
```

- `--root` is optional: falls back to `$CRAFT_PROJECT_ROOT`, then
  `hooks/scripts/find-workshop.sh`.
- **Always exits 0.** Every failure path (missing root, missing `.craft/`,
  missing python3, builder crash, concurrent build) prints one JSON line and
  degrades. No craft flow can ever be blocked by the dashboard.
- Degrade paths never write, truncate, or delete `graph.js` or `records/` -
  stale-but-valid beats absent.
- Single-flight: concurrent invocations skip with reason
  `build-skipped-concurrent` rather than interleaving.
- Success stdout: `{"status":"ok","nodes":N,"edges":N,"annotations":N,"warnings":N,"written":N}`.

The builder reads nothing outside `<root>/.craft/` and writes nothing
outside `<root>/.craft/graph/` (enforced, tested).

## Output contract (what the page loads)

All output lands in `<root>/.craft/graph/`, loadable from `file://` via
`<script src>` (no fetch needed):

- **`graph.js`** assigns `window.CRAFT_GRAPH`:
  `{version, nodes, edges, annotations, stats, tokens, build}`.
  - `version` (integer, currently 1) exists for the page template to gate
    on. On a mismatch, handling - defensive read or prompting a rebuild -
    is the TEMPLATE's job, never this builder's.
  - `nodes` are sorted by `(date, id)` ascending - replay in creation order
    reads node order directly. Envelope: `id, type, title, date, status,
    tags, surface` (+ `chunks` on stories, `subtype` on notebook records,
    `kind` on dials, optional `summary` on any type with an extractable
    source section - absent, never empty or null, when the record has none).
  - `edges` are `{source, target, kind}`, sorted by `(kind, source,
    target)`. Kinds: `belongs_to, blocked_by, blocks, graduated_to,
    grew_from, reapplies, satisfied_todo, source_story, source_cycle,
    mockup, dial, origin, references`.
  - `annotations` hold every reference-shaped value that did NOT become an
    edge, with a reason (`sentinel`, `unresolved`, `out-of-scope-type`,
    `prose`). Nothing is silently dropped.
  - `tokens` is a flat dotted-key fold of `.craft/design/tokens.yaml`
    (empty object when absent - never assume visual keys exist).
  - `graph.js` carries NO timestamp: an unchanged corpus produces
    byte-identical output and the second build writes zero files.
- **`records/{id}.js`** (one per record) assigns
  `window.CRAFT_RECORDS["{id}"]` = the record's full markdown as a string.
- **`.gitignore`** (one line: `*`) is seeded by the wrapper on the run that
  CREATES the folder - the pytest/ruff convention for regenerable output, so
  the timestamped build-status.js never dirties a project that commits
  `.craft/`. Deleting it opts the folder back into commits permanently; the
  wrapper never recreates it for an existing folder.
- **`build-status.js`** assigns `window.CRAFT_BUILD`:
  `{status: "ok"|"degraded", reason, at}`. Written by the WRAPPER in pure
  bash on every invocation - including on a machine with no python3 - so a
  staleness banner is always renderable. This is the only output that
  carries a timestamp.

## Layout

- `build.py` - CLI entry (`--root`)
- `src/` - frontmatter reader, identity, resolver, registry, one parser per
  record type, assembler, stats, tokens fold, emitters
- `__tests__/` - python unittest suites (run via `tests/test-dashboard.sh`)
- `__fixtures__/corpus/` - neutral-placeholder fixture corpus (no `.craft`
  directory name inside - this repo gitignores that name at any depth)
