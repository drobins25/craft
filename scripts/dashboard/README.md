# Dashboard graph data builder

Parses every record in a project's `.craft/` and emits the graph data the
Craft Dashboard page renders: nodes for every record, edges from the lineage
fields the flows already stamp, and stats.
Python 3.9+ stdlib only - no dependencies, no network, no AI tokens.

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

> **Expected console noise on `file://`.** Chrome logs `Unsafe attempt to load
> URL <page> from frame with URL <page>. 'file:' URLs are treated as unique
> security origins.` once per load. It is not caused by this page: a file
> containing a single character reproduces it, and adding a favicon (data URI
> or a real adjacent `.ico`) does not suppress it. It is a long-standing
> Chromium defect where a generic origin-check message is printed for `file:`
> origins, naming the frame's own URL on both sides -
> https://issues.chromium.org/issues/41189947 (open since 2015). Nothing to
> fix here; the only workarounds are browser launch flags, which this design
> deliberately does not require.

- **`graph.js`** assigns `window.CRAFT_GRAPH`:
  `{version, nodes, edges, annotations, stats, build, vocabulary}`.
  - `version` (integer, currently 1) exists for the page template to gate
    on. On a mismatch, handling - defensive read or prompting a rebuild -
    is the TEMPLATE's job, never this builder's.
  - `nodes` are sorted by `(date, id)` ascending - replay in creation order
    reads node order directly. Envelope: `id, type, title, date, status,
    tags, surface` (+ `chunks` on stories, `subtype` on notebook records,
    `kind` on dials, optional `summary` on any type with an extractable
    source section - absent, never empty or null, when the record has none).
  - `edges` are `{source, target, kind}`, sorted by `(kind, source,
    target)`. The twelve kinds: `belongs_to, blocks, dial, graduated_to,
    grew_from, mockup, origin, reapplies, references, satisfied_todo,
    source_cycle, source_story`. `blocked_by` is NOT among them: a story's
    `**Blocked by:**` marker is a `blocks` FIELD carrying `invert=True`, so it
    becomes one `blocks` edge pointing the other way, never a thirteenth kind.
  - `annotations` hold every reference-shaped value that did NOT become an
    edge, with a reason - one of the eight: `sentinel`, `unresolved`,
    `out-of-scope-type`, `prose`, `container`, `not-a-record`, `wrong-type`,
    `self-reference`. Nothing is silently dropped.
  - `vocabulary` carries the display words the page prints, so the page holds
    no second copy of the rules: `statuses`, `dial_outcomes`, `types`, and
    `membership` (the kinds that mean containment - still emitted, but the
    page now clusters records by type and no longer reads it). Relationship
    verbs are deliberately absent - nothing reads them.
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
- **`insights.js`** (optional, AUTHORED - the one file in `.craft/graph/`
  the builder neither writes, validates, nor deletes; `sweep_orphans` is
  scoped to `records/` and never touches a graph-root sibling) assigns
  `window.CRAFT_INSIGHTS` on a single line:
  `window.CRAFT_INSIGHTS = {"version":1,"generated_at":"<ISO8601>","graph_sha":"<sha256 of graph.js at authoring time>","cards":[{"body":"<string>","witness":"<attribution string, e.g. the muse>","evidence_node_ids":["<node id>"]}],"history":["<prior card body>"]};`
  - `version` (integer, currently 1) - the page gates on it exactly the way
    it gates on `graph.js`'s version; a mismatch renders no cards.
  - `cards` holds 3-4 entries. Each carries content and evidence ONLY:
    `body` (the insight prose), `witness` (an attribution voice string the
    page renders verbatim after `witnessed by `), and `evidence_node_ids`
    (node ids present in `graph.js` at authoring time). The sidecar carries
    NO hue, NO pin/corner, NO eyebrow text and NO record type - the page
    derives all chrome from the live graph, so a card can never cite a type
    the graph disagrees with.
  - `history` holds at most 8 prior card bodies, most recent first, so a
    regeneration can avoid repeating itself.
  - Freshness is a sha question, never a clock one:
    `insights-check.sh --check --root <r>` prints
    `VERDICT=missing|stale|fresh` by comparing `graph.js`'s sha256 against
    the receipt at `.craft/graph/.insights.sha256` (written by `--stamp`
    after authoring). Both modes exit 0 on every path.

## Layout

- `build.py` - CLI entry (`--root`)
- `src/` - frontmatter reader, identity, resolver, registry, one parser per
  record type, assembler, stats, emitters
- `__tests__/` - python unittest suites (run via `tests/test-dashboard.sh`)
- `__fixtures__/corpus/` - neutral-placeholder fixture corpus (no `.craft`
  directory name inside - this repo gitignores that name at any depth)
