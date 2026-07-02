# Living Map - Format & Anchor Contract

> **STATUS: FROZEN.** This is the canonical on-disk spec for the Living Map's structural layer. It was co-designed and locked 2026-06-22, with two authorized additions locked 2026-06-23 (area-key, build/inject trigger + clock note), and an authorized additive reopen 2026-07-02 for Story 5 read-targets (per-anchor spans + slice range annotations in 8a/8c, index schema version 2). It is the cross-story contract: the per-area context deriver (Story 3) and the consumer pilot (Story 4) plan and build strictly against this document and do NOT revise it. Any change here is a deliberate re-open, not an edit.

This document defines three things:

1. **The anchor** - the deterministic string that identifies a symbol or file across all three extraction tiers.
2. **The index** - the source-of-truth key store the generator writes to disk.
3. **The slice** - the token-efficient view a consumer reads.

There is no generator code here; this is the format contract only. The generator that produces conforming output is built in later chunks.

---

## 1. Anchor string grammar

```
ANCHOR := <relpath>                       # file-level - the universal floor
        | <relpath> "#" <symbol-path>      # symbol-level

<relpath>      := POSIX relative path from repo root, forward slashes, C/POSIX-locale sort
<symbol-path>  := <code-fqn> | <heading-path>
<code-fqn>     := <segment> ("." <segment>)* <overload>?   # tiers 1-2, "." separator
<heading-path> := <slug> ("/" <slug>)*                     # tier 3 (markdown), "/" separator
<overload>     := "(" <type> ("," <type>)* ")"             # only where the language allows overloading
```

- The separator is **per-tier**: `.` for code scope (namespaces / classes / functions), `/` for markdown heading hierarchy. The consumer knows the tier from the file extension, so there is no ambiguity.
- File-level `path` is always valid; symbol anchors strictly **refine** it.

### Backend-stability invariant (language-aware floor rule)

The same symbol must produce a compatible anchor regardless of which tier extracted it. Where a tier cannot resolve scope, it degrades to a strictly **coarser, stable** anchor (file-level), never a flat name a parser would later contradict.

- **Non-nesting languages** (shell) -> the floor emits a flat `path#name`; a real grammar would agree, so there is no contradiction.
- **Nesting languages without a bundled grammar** (Rust, Swift, SQL today) -> the floor degrades to **file-level `path`**, never a flat symbol guess (`path#foo` would contradict a future `path#mod.foo`).

Consequence: upgrading a language from floor -> grammar later never invalidates stored keys. File-level stays valid; symbol anchors are purely additive. The contract must survive being pointed at a real polyglot repo unchanged.

---

## 2. Markdown heading slug pipeline

Each heading segment is slugified; the full ancestor chain is then joined with `/`. Exact order - two machines must produce identical slugs:

1. **Strip** every character that is not an ASCII letter, digit, space, or hyphen - delete `[^A-Za-z0-9 -]` (case-insensitive so letters survive to step 2). Deleted, **not** replaced - so `/` in heading text vanishes (`I/O Operations` -> `IO Operations`, never `i-o-...`, so it cannot collide with a real `i/o` hierarchy).
2. **Lowercase** under the **POSIX/C locale** (never locale-dependent - avoids the Turkish-dotless-I class of cross-machine divergence).
3. **Spaces -> hyphen** (the only character-to-hyphen mapping).
4. **Collapse** consecutive hyphens to one.
5. **Strip** leading / trailing hyphens.

- **Empty-slug fallback:** a heading that strips to nothing (`## ---`, `## ***`) gets a positional slug `section-<ordinal>`, where `<ordinal>` is the heading's document-order index (deterministic).
- **In-file collision:** identical slugs within one file get a `-N` suffix in **document order**. NOTE: `-N` is **document-order deterministic, not rename-stable** - reordering or inserting a same-named heading above shifts suffixes.
- Example: `### Loop` under `## Routing` -> `commands/craft.md#routing/loop`.

---

## 3. Overload type rendering

For overloadable languages, the `<overload>` disambiguator renders from **what the parser literally spans, not what it resolves** - the determinism pin:

- Each parameter type = its **source-span text, whitespace-stripped**. Grammar versions rarely change which *bytes* are "the type," so this is byte-stable by construction and needs no per-language semantic normalization (which would itself be a drift source).
- **Parameter names and default values are excluded** (a param rename or default edit is the *same* overload - the anchor must not move).
- **Modifiers are included** (`ref` / `out` / `in` / `params` genuinely distinguish overloads).
- Comma-separated, no spaces. Examples: `GenerateIds(int,string)`, `Foo(ref int,string)`.

The per-language mechanics of extracting the type sub-node from the param node live in extraction (a later chunk); this contract pins only the rendering rule.

---

## 4. Anchor granularity

Definition-level, taken from each language's `tags.scm` `@definition.*` captures **as-is, no override** (honors catalog-not-custom-code) - typically types + callables, sometimes properties, per the catalog. Markdown = every heading depth. Shell floor = function definitions.

Locals, parameters, imports, and individual enum members are **NOT anchorable** (they are absent from the catalog's definition captures).

Granularity defines what is *addressable*; the token-budget trim separately decides which anchors *surface* in a given slice. Finer granularity does not mean a heavier slice - it means finer pointers are possible (for Story 5).

---

## 5. Rename semantics

A rename produces a **NEW anchor and drops the old** - a new-anchor event, not an updated-anchor. craft does NOT track renames: the map is recomputed, so a rename is indistinguishable from (delete old + add new), and the map simply reflects current symbols. No primary source documents FQN rename behavior, so this is craft's declared contract.

Consequence (recorded for Story 5 / concept 05): pointer staleness must do **anchor-existence checking**, since churn never flags the orphaned old key.

---

## 6. Tier-2 / tier-3 identity mapping

Follows directly from the language-aware floor rule (section 1):

- **Tier-2 floor** symbol extraction applies ONLY to a small, explicit **known-flat-language allowlist** (shell today) -> `path#name`. Every other grammarless language is treated as potentially-nested and degrades to **file-level `path`** (never a flat guess a future grammar would contradict). The allowlist is an explicit implementation list, not a regex heuristic.
- **Tier-3 markdown** -> `path#slug/slug...` via the slug pipeline (section 2).
- **File-level `path`** is the universal degradation form for any unresolvable scope.

---

## 7. Token budget

Per-area-slice ceiling (craft's model is per-area slices, not aider's whole-repo injection). Default = aider's formula:

```
max(1024, min(max_input_tokens / 8, 4096))
```

This resolves to **4096 for craft's large-context models** and auto-scales down if ever run on a small model. Overridable via a `map.token_budget` config key. The trim binary-searches the ranked definitions to fit this ceiling.

---

## 8. On-disk serialization: slice vs index

### 8a. Slice grammar (consumer-facing, frozen - Stories 3/4 parse this)

Aider-style **compact indented outline**. Indentation encodes scope; the anchor is reconstructable by walking the indent stack; signatures ride inline; no repeated FQN; **100-char line truncation**; definition-level only. Within a file: source order (deterministic). Cross-file inclusion: rank-determined under the token budget.

JSON / YAML are ruled out for the slice (the ~69% token tax contradicts the map's reason to exist).

```
src/Data/LoadOrders.cs
  Acme.Data.LoadOrders  [off=8,lim=140]
    GenerateIds(int,string)  [off=45,lim=83]
    GenerateIds(int)  [off=129,lim=6]
    LoadAsync(int)  [off=136,lim=11]
commands/craft.md
  routing  [off=12,lim=30]
    loop  [off=18,lim=9]
```

In the example, the anchor for line 3 is `src/Data/LoadOrders.cs#Acme.Data.LoadOrders.GenerateIds(int,string)`, rebuilt from the indent stack.

**Ranged-read annotation (additive, 2026-07-02 reopen for Story 5).** A symbol whose span is known carries a trailing `  [off=<N>,lim=<M>]`: `N` = the symbol's 1-indexed start line, `M` = its line count (`endLine - startLine + 1`). These are paste-ready parameters for a targeted `Read(file, offset=N, limit=M)` - the Read tool's `offset` starts AT line `N` (1-indexed), so no conversion is ever required of the consumer. A symbol with no reliable span (tier-2 shell, any floor case) renders bare - no annotation, never an error - and bare path segments (scope components with no backing definition) carry no annotation. **Truncation rule:** the 100-char line cap truncates the symbol NAME to make room; the annotation is always preserved intact. Enclosing scopes overlap their children by design (a class span includes its methods; a `##` section includes its `###` subsections) - the consumer picks its granularity.

### 8b. Index is the source of truth for anchor keys; the slice is a VIEW

The served indented slice is a token-efficient view for LLM / agent **reading**. The **canonical anchor keys** that stored consumers persist (Story 3 per-area attach, Story 5 pointers) come from the map **INDEX**, never from re-parsing or reconstructing the served outline.

Rationale: reconstructing an anchor by walking the indent stack is fine for an LLM reading for context, but deriving a *stored* key that way reintroduces a mis-key surface (wrapped signatures, 100-char truncation mid-line, tab/space ambiguity) - the exact coherence failure the orphan-detection rule guards against.

**Index = keys; slice = view.** This ties to the locked Story 5 rule: anchor-existence is checked against the INDEX, not the slice.

### 8c. Index schema (the source-of-truth key store)

The index is internal (not consumer-facing, not token-budgeted). Its on-disk encoding is the generator's choice in a later chunk; the **four required fields are locked**:

| Field | Role |
|-------|------|
| **files** | the set of files covered, by `<relpath>` (POSIX, forward slashes, C/POSIX-locale sort) |
| **content hashes** | per-file content hash - the structural-layer staleness key (a slice is valid while its file's content hash is unchanged) |
| **canonical anchor keys** | the authoritative anchor strings (per the grammar in section 1) that stored consumers persist against - the source of truth, never the reconstructed slice |
| **reference graph** | who-references-what edges, the input to reference-frequency (PageRank-style) ranking |

`.craft/map/` holds the per-file extraction cache and this index. It is created on first write; craft imposes no git treatment on it (it inherits the user's existing `.craft/` handling).

**Per-anchor spans (additive, 2026-07-02 reopen for Story 5).** Each stored anchor additionally carries `startLine` (integer, 1-indexed) and `endLine` (integer 1-indexed, or `null` where no reliable end exists - the never-lie floor applied to spans: tier-2 shell, any extraction gap). The span covers the whole declaration (grammar tiers) or the heading's section including its subsections (markdown). These fields feed the slice's ranged-read annotations (section 8a); they are metadata ON an anchor, not a new anchor form - the four required fields above, the anchor grammar (section 1), and the backend-stability invariant are unchanged.

**Schema version (2026-07-02).** The index carries a top-level `version` field, now **2** (v2 = anchors carry spans). The migration rule: a reader treating any version other than its own current schema treats the file as NO INDEX and fully re-derives the area (first-build cost). A version-mismatched entry must never be served on a content-hash match - a pre-span v1 entry would otherwise pin span-less anchors forever on unchanged files.

---

## 9. Area-key

A cross-story primitive that sits **ALONGSIDE** the anchor grammar - NOT an extension of it. The area-key is the stable identity an area slice (Story 2) and per-area context (Story 3) cache and invalidate under.

- **area-key = a directory relpath** from repo root, forward slashes, POSIX/C-locale sort.
- **Non-hierarchical, non-overlapping:** a consumer requests exactly one directory path and gets THAT directory's files only - no implicit parent/child expansion. "Which area to request" is the consumer's job (Story 4), not the generator's.
- **Do NOT add a directory-level anchor.** A directory anchor would break the file-level-floor directionality of the backend-stability invariant. The anchor schema (section 1) is unchanged. The per-area cache entry is keyed by **directory path + HEAD SHA** and is ATTACHED AT the file-level anchors that fall inside that directory; there is no area-level anchor.
- Rationale: trivially stable cache key, no prefix-tree invalidation, avoids the silent subtree-missing bug.

---

## 10. Build / inject trigger

- **INJECT = pull on demand** - a craft agent reads the cached area slice / calls the map when IT decides it needs orientation (the model drives retrieval).
- **PLUS cold-start push** - when an agent is spawned with a known primary file/area in its spec, that area slice is prepended once at spawn.
- **BUILD = lazy on request**, content-hash / HEAD-keyed freshness.
- **EXPLICITLY REJECTED: per-file-access hook auto-injection** (intercepting Read/Grep/Glob to splice in a map). No surveyed production tool does per-tool-call injection; the only injection patterns in the wild are per-user-turn push, pull-on-invocation, and implicit agentic retrieval. Claude Code `PreToolUse` cannot return a synthetic result to satisfy a Read, per-call hooks are latency death, and `additionalContext` is only a weak system-reminder.

> **Note (2026-06-29):** the **cold-start push** half above is **superseded by pull-only**. The consumer-wiring design settled on pull-everywhere, no-push: a consumer fetches its own slice when it needs orientation, and the content-hash cache makes repeat pulls cheap, so "who already has the slice" stops mattering. Push only works when a launcher already knows the area (true for a single agent, impossible for the orchestrator, which roams), so it does not generalize. Decided in the Living Map consumer-wiring story (source concept `planning/living-project-map/04-consumer-wiring.md`, DESIGN CALL A). The pull-on-demand bullet and the per-file-access rejection both still stand.

---

## 11. Clock note (cross-layer)

The two map layers run on **different staleness clocks by design** (different inputs):

- **Structural layer (Story 2)** invalidates on **per-file content hash** (tracks the working tree).
- **Signal layer (Story 3)** invalidates on **HEAD commit SHA** (history-derived; correctly lags uncommitted edits).

The slice-assembly logic must know both.

---

## Rejected alternatives (recorded)

- **Positional / LSP `line:col` anchors - RULED OUT.** Position-unstable under any insertion above the symbol (every line below shifts). The slug-of-text scheme is, in effect, a **legible content-hash** of the symbol's identity: stable under unrelated edits, human-readable, diffable. (LSIF opaque numeric IDs were already ruled out in the format research for the same incrementality reason.)
- **JSON / YAML slice serialization - RULED OUT** for the consumer-facing slice (~69% token tax). The index, being internal and not token-budgeted, may use any encoding.

## Boundaries (recorded)

- **Story 23 `[[wikilinks]]` do NOT target map heading-anchors.** Cross-system linking is OUT OF SCOPE - the wiki-backlink slug regime and the map heading-anchor slug regime stay **independent**. They may look similar but are not interoperable by design; do not unify them.

---

_Provenance: transcribed verbatim-faithfully from the FROZEN `## Locked anchor contract (chunk 1)` in the Story 2 spec (`map-structural-generator`, Cycle 10 / Living Project Map), frozen 2026-06-22 with area-key + trigger + clock-note added 2026-06-23. This file is the tracked, citable home of that contract for Stories 3 and 4._
