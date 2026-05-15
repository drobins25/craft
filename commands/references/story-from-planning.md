# Story From Planning (Inline Reference)

This file is read by `/craft:story-new` when the user picks "From planning" at the mode question. It owns the entire planning-to-story transformation: extract decisions from the planning corpus, write a thorough story file with all required sections plus `## Reference Materials`, and forward-link planning docs so the bidirectional traceability is real.

**DO NOT invoke this as a skill via the Skill tool.** The parent command (`/craft:story-new`) Reads this file and executes the phases inline. Same pattern as `content-spark-inline.md` and `creative-spark-inline.md`. Skill-tool nesting causes the chain break documented in the chain-break-fix-discovery memo.

## When This Runs

This protocol is invoked from two parent flows:

**A. `/craft:story-new` Step 2.5** has:
1. Detected `.craft/planning/` contains at least one file with `concept:` or `initiative:` frontmatter
2. Asked the user "From planning, or freeform?"
3. The user picked "From planning"

The parent command jumps here instead of continuing to Step 3 (Choose Your Path).

**B. `/craft:cycle-design`** invokes this protocol when:
1. The active or planning cycle's `cycle.yaml` has `source_concept` populated (one or more planning doc paths)
2. The orchestrator is in the **planning-extraction moment** during default-mode, roadmap-mode, or detailing-mode story creation (see `commands/references/cycle-design/default-mode.md` action-moment framing for the distinction)

In this case, **Phase 1's concept-picker auto-resolves** to the cycle's `source_concept` value(s) - the user already confirmed the planning source at cycle creation, so re-asking is redundant. See Phase 1 below for the auto-resolve behavior.

## Phase 1: Confirm Concept Source

**Invocation marker check (required for auto-resolve):**

The auto-resolve branch below fires ONLY when the calling context explicitly includes the marker phrase:

> `INVOCATION: cycle-design - planning source already confirmed in cycle.yaml`

Cycle-design mode files (default-mode.md, roadmap-mode.md, detailing-mode.md) set this marker before Reading this protocol. The marker is a deterministic structural signal - if it's not present in the calling context (e.g., the user ran `/craft:story-new` directly while `ACTIVE_CYCLE` happens to point at a planning-sourced cycle), the auto-resolve does NOT fire. Fall through to the corpus-scan path below.

**Cycle-design invocation - auto-resolve from cycle.yaml (marker present):**

If the marker is present in your invocation context:

1. Read `${CRAFT_PROJECT_ROOT}/.craft/cycles/${ACTIVE_CYCLE}/cycle.yaml` to get the `source_concept` value (list of planning doc paths).
2. **If cycle.yaml has exactly one source_concept path:** auto-resolve. Skip the picker. Set that path as the selected concept. Proceed directly to Phase 2.
3. **If cycle.yaml has multiple source_concept paths:** ask the user which specific concept THIS story is from, using the cycle's `source_concept` list as the option set (not the full planning corpus). Skip directly to Phase 3a after answer.

**Story-new invocation - corpus scan (no marker, or marker absent):**

Glob the planning corpus:

```bash
$PROJECT/.craft/planning/*.md
$PROJECT/.craft/planning/**/*.md
```

Filter to files with `concept:` or `initiative:` as a YAML key in frontmatter. Group by folder - an initiative folder (e.g., `01-customer-profile-tab/`) is one logical group; standalone concept files are each their own group.

**If exactly one concept exists:** skip the selection question, proceed to Phase 2.

**If multiple concepts exist:** use **AskUserQuestion** to confirm which one this story is from:

```
question: "Which concept is this story from?"
header: "Concept"
options:
  - label: "[Concept title]"
    description: "[status] - [last_updated] - [N open questions]"
  - label: "[Concept title]"
    description: "[status] - [last_updated] - [N open questions]"
```

If the user provides custom text identifying a different file, use that path.

**Concept readiness check:** Read the selected concept file. If it has `- [ ]` open questions in its `## Open questions` section, warn the user but proceed:

> "Concept has [N] unresolved open questions. The story can still be written - any unresolved questions will be captured in the story's `## Notes` section for you to address before plan-chunks runs."

## Phase 2: Capture Story Title

One concept can spawn multiple stories. Ask the user what this specific story is:

Use **AskUserQuestion**:

```
question: "What's the title for this story? (Plain English - the slug is derived automatically.)"
header: "Title"
options:
  - label: "[Inferred title from conversation, if any]"
    description: "Use this title"
  - label: "Different title"
    description: "I'll provide a different one"
```

If the user picks "Different title" or supplies custom text, use their exact wording. Derive the slug as `kebab-case` of the title. Story name (frontmatter `name` field) is the slug.

## Phase 3a: Supersession-First Scan

**Before any extraction begins**, the Explore agent scans the primary concept AND sibling concepts in the same initiative folder for supersession markers. This is the FIRST action - never extract decisions from a potentially-superseded concept.

Spawn an **Explore** agent with this prompt:

```
Scan the following planning files for supersession markers ONLY. Do not extract decisions yet.

- Primary concept: [absolute path to selected concept file]
- Sibling concepts: [absolute paths to other concept files in the same initiative folder, if applicable]

Look for prose like:
- "superseded by concept X"
- "superseded YYYY-MM-DD"
- "deprecated"
- "replaced by"
- "see [concept] instead"

For each marker found, return:
- Source file path
- Source location (which section, which line range or surrounding text)
- The exact marker text quoted
- The superseding concept (path or name) parsed from the marker text

If no supersession markers found, return: "NO SUPERSESSION."

Be exhaustive. A single concept may have multiple markers pointing to different superseding concepts.
```

Process the report:

**If "NO SUPERSESSION":** proceed to Phase 3b.

**If exactly one supersession marker found:** proceed to Phase 4 with the supersession data; the user will be asked whether to restart Phase 3a against the superseding concept.

**If multiple supersession markers found:** proceed to Phase 4 with the multi-supersession data; the user will be asked which superseding concept to use.

## Phase 3b: Extract Per the 9-Section Taxonomy

Spawn an **Explore** agent with this prompt (verbatim):

```
You are extracting story content from a craft planning corpus. Walk these files:

- Primary concept: [absolute path to selected concept file]
- Initiative folder (if applicable): [absolute path to initiative folder]
- Active state: [absolute path to .craft/planning/active.md]
- Any mockup files referenced in the concept (check the concept body for .html, .png, .jpg paths)
- Sibling concept files in the same initiative folder (extending or contextualizing the primary concept)

Story title (extracts apply to THIS story ONLY): [title from Phase 2]

## Single-Story Scope Instruction

Extract decisions relevant to "[story title]" ONLY. The concept may describe N sibling stories. Extract only the slice for this story, not all stories' decisions.

Heuristics for determining scope:
1. Decisions that name this story title or its slug.
2. Decisions in sections explicitly tagged for this story (e.g., a `### [story title]` subsection).
3. Decisions in shared-architecture sections that apply to all sibling stories (e.g., "all 7 stories use Option B architecture" - this is shared, include it).

If you CANNOT confidently determine which decisions belong to this story versus siblings, mark the Decisions section as PARTIAL with the report note: "scope unclear - cannot distinguish which decisions apply to '[story title]' vs siblings." This triggers a gap-fill AskUserQuestion in Phase 4.

## Extraction Taxonomy (9 sections + 2 optional)

For each, return one of three states: RESOLVED (clear in planning, ready to write verbatim), PARTIAL (some content available, specific piece missing), or MISSING (no content found).

### 1. Spark (2-3 sentences)
Compress the concept's intent into 2-3 sentences naming what this story builds and what's genuinely NEW versus inherited patterns/scaffolding.

### 2. Decisions (numbered list, but format flexible)
Extract every decision from the concept's `## Locked decisions` section AND from active.md's "Recent state changes" entries that touch this concept.

Real-world concepts use BOTH formats:
- Numbered: `### 1. Architecture: Option B` with rationale beneath
- Subheading-only: `### Architecture: Option B` with rationale beneath, no number

Handle both. Preserve the existing format the concept uses (do not renumber subheadings into Decision #N or vice versa).

Format each decision as:

```
### [N. ][Short rule statement]
[1-3 sentences explaining the rule with concrete examples.]
**Rationale:** [Why this over alternatives. Cite user-provided reason or codebase pattern.]
**Scope:** [Where the rule applies - this story / this card type / all cycle N cards / project-wide.]
**Source:** [Concept file + section heading + (optional subheading or Decision #N or dated entry).]
```

For decisions superseded by later concept revisions, include only the latest version. Note the superseded version in `**Supersedes:**` field.

### 3. Scope (Included / Excluded)
Extract concept's `## Scope` Included and Excluded lists, filtered to this story's slice. If only Included exists, mark Excluded PARTIAL.

### 4. Preserve
What must remain working unchanged. Pull from concept's mentions of shipped patterns, sibling components, locked.md references. If concept doesn't explicitly say, mark MISSING.

### 5. Hardest Constraint
The biggest risk for THIS story. Look for risk language: "first-of-its-kind", "validates", "concurrency hazard", "risk:", "thread-safety", "chunk-validator FAIL". If found, write 2-4 sentences naming the constraint and explicit FAIL conditions. If MISSING, gap-fill triggers in Phase 4.

### 6. Dependencies (Blocked by / Blocks)
ADO IDs, story names, predecessor concepts. Look for "Blocked by", "depends on", "after [X] ships". Default to "**Blocked by:** None" if MISSING.

### 7. Likely Files (10-25 entries with action tags)
Combine:
- File paths mentioned in concept (code references, mockup paths, query paths)
- Codebase scan: files matching the concept's scope keywords
- Sibling card files if concept references "Pattern N" or shipped components

Format: `path/to/file.ext` - [modify|create|read-only] - [reason]

Read-only entries are how shipped sibling files reach plan-chunks-agent without nesting.

### 8. Reference Materials (load-bearing - absolute paths + file-type-appropriate anchors)

Use these anchor types BY FILE TYPE:

| File type | Anchor type | Example |
|---|---|---|
| Planning files (concept, active.md, README) | `## Section` + `### Subheading` OR `Decision #N` OR dated entry OR table row | `## Locked decisions -> ### Architecture: Option B` |
| Mockups / static design artifacts | Line range OR HTML id/data-section attribute | `lines 2649-2664` or `#identification-card` |
| locked.md | Pattern N (canonical) | `Pattern 14 (revised 2026-05-11)` |
| tokens.yaml | Token name | `--color-customer-status-active` |
| active.md dated entries | `## Recent state changes -> [YYYY-MM-DD entry]` | `## Recent state changes -> 2026-05-06 entry` |
| Code files / sibling stories | Function/class name preferred over line numbers | `CustomersService.GetById` |

**NEVER use line numbers for planning files.** They churn daily. Section headings + subheadings survive edits because they move semantically.

**Multi-anchor per file is the norm.** One file can have multiple cited sections:

```
- `/absolute/path/concept-08.md`:
  - `## Locked decisions -> ### Architecture: Option B`
  - `## Locked decisions -> ### Backend shape: DTO Namespacing`
  - `## Story order rationale` (Address & Contact paragraph)
```

**File-size assessment rule:** If a referenced file is >500 lines AND no anchor is pinned, mark the citation PARTIAL with "needs anchor."

Build the section by category:

```
**Concept files used by this story:**
- [absolute path]:
  - [anchor 1]
  - [anchor 2]

**Mockup files:**
- [absolute path] (lines [N-M] or HTML id)

**locked.md patterns applied:**
- Pattern [N] (note revision date if any)

**Design tokens:**
- .craft/design/tokens.yaml -> [token names]

**active.md entries:**
- [absolute path] -> `## Recent state changes -> [YYYY-MM-DD entry]`

**Shipped sibling story files (cycle precedent):**
- [absolute path]

**project.md:**
- [absolute path]
```

If the project is a wrapper-vs-nested monorepo (`.craft/` at both wrapper and nested level), USE WRAPPER-LEVEL ABSOLUTE PATHS for concepts. plan-chunks-agent derives project root from `.craft/` location and will not find wrapper-level files via relative paths.

### 9. Acceptance (rough numbered list)
Pull from concept's `## Open questions` section that have `- [x]` resolved checkmarks (resolved questions become acceptance criteria), AND from `## Actionable items` if they read as testable. Format:

```
- [ ] Given [context], when [action], then [outcome]
```

Keep rough - plan-chunks-agent refines in its Phase 3.7.

### Optional: Content Direction
If concept explicitly resolves content dimensions (data sources named, placeholder behavior cited via Pattern N, microcopy specified), produce a `## Content Direction` block. Otherwise omit - content-spark handles it later.

### Optional: Visual Direction
For UI stories: if a mockup is referenced, produce a `## Visual Direction` block citing the mockup path + line range and any vibe/feel/motion notes from the concept. Otherwise omit - creative-spark handles it later.

## Return format

```
EXTRACTION REPORT
=================
Concept: [path]
Story title: [title]

Spark: [RESOLVED|PARTIAL|MISSING] - [content or gap]
Decisions: [state] - [content or "scope unclear - cannot distinguish..." or gap]
Scope: [state] - [content or gap]
Preserve: [state] - [content or gap]
Hardest Constraint: [state] - [content or gap]
Dependencies: [state] - [content or gap]
Likely Files: [state] - [content or gap]
Reference Materials: [state per citation - flag any file >500 lines without anchor]
Acceptance: [state] - [content or gap]

Content Direction: [optional - include only if planning resolved]
Visual Direction: [optional - include only if planning resolved + UI story]

GAP-FILL QUESTIONS NEEDED:
- [list of specific AskUserQuestion items Phase 4 should run]
```

Be ruthless about marking MISSING when planning is genuinely silent. Do not invent.
```

Launch the Explore agent and wait for the report.

## Phase 4: Process Findings + Gap-Fill (one question at a time)

**Supersession handling fires first** (from Phase 3a data).

**Single supersession marker:**

```
question: "Concept X has a supersession marker: '[quoted text]'. Use the superseding concept instead?"
header: "Supersession"
options:
  - label: "Use superseding concept"
    description: "Restart extraction against [parsed superseding concept path]"
  - label: "Keep current concept"
    description: "Proceed despite supersession (you've already accounted for it)"
```

If "Use superseding concept" -> restart Phase 3a with new path.

**Multiple supersession markers:**

```
question: "Concept X has multiple supersession markers. Which superseding concept should drive this story?"
header: "Supersession"
options:
  - label: "[Superseding concept #1 - parsed from marker 1]"
    description: "[Quoted marker text 1]"
  - label: "[Superseding concept #2 - parsed from marker 2]"
    description: "[Quoted marker text 2]"
  - label: "Use all superseding concepts (merge)"
    description: "Treat this as a multi-concept story - DEFERRED v2, not supported; pick one or proceed with current"
  - label: "Keep current concept (skip supersession)"
    description: "Proceed despite supersessions"
```

The "merge" option exits with a v2-deferral message. Picking a specific superseding concept restarts Phase 3a.

**Then for each PARTIAL or MISSING section, surface a targeted AskUserQuestion ONE AT A TIME.** Never batch.

**Hardest Constraint missing:**

```
question: "I couldn't pin a Hardest Constraint from the concept. What's the load-bearing risk for this story?"
header: "Hardest"
options:
  - label: "[Best-guess inference from concept]"
    description: "Use this as the hardest constraint"
  - label: "Different - I'll describe it"
    description: "Provide your own"
  - label: "No specific risk for this story"
    description: "Leave Hardest Constraint empty"
```

**Mockup line range missing (large static file):**

```
question: "Mockup file is referenced but no line range is pinned. Which section of [mockup filename] does this story implement?"
header: "Mockup"
options:
  - label: "I'll provide the line range"
    description: "Type the range, e.g. 2649-2664"
  - label: "Whole file is the reference"
    description: "Use the entire mockup without a pinned section (only if <500 lines)"
```

**Planning file anchor missing (concept cited but no section pointer):**

```
question: "Concept X is cited but no section/subheading anchor. Which `## Section` or `### Subheading` does this story consume?"
header: "Anchor"
options:
  - label: "[Best-guess based on extracted decisions]"
    description: "Use this section"
  - label: "I'll specify the section"
    description: "Provide the anchor manually"
```

**Excluded scope missing:**

```
question: "Concept lists what's Included but not what's Excluded. What's explicitly NOT in this story?"
header: "Excluded"
options:
  - label: "[Best-guess: things from sibling stories]"
    description: "Use this list"
  - label: "Different - I'll describe"
    description: "Provide your own excluded list"
  - label: "No explicit exclusions"
    description: "Leave Excluded empty (rare)"
```

**Single-story scope unclear (concept describes multiple stories):**

```
question: "Concept describes multiple stories. The agent couldn't determine which decisions belong to '[story title]'. How should we scope?"
header: "Scope"
options:
  - label: "Include only decisions naming '[story title]' or sibling keywords"
    description: "Conservative - may miss some applicable decisions"
  - label: "Include all decisions in the concept's locked-decisions section"
    description: "Broad - may include sibling stories' decisions"
  - label: "I'll list which decisions apply"
    description: "Walk through each decision with me one at a time"
```

For any GAP-FILL QUESTIONS NEEDED the agent flagged but Phase 4 doesn't have a generic template for, write a targeted AskUserQuestion that names the specific gap and offers a best-guess option plus a "describe" escape.

## Phase 5: Write the Story File

### Placement logic

Read `${CRAFT_PROJECT_ROOT}/.craft/.global-state` via Bash (absolute path, NEVER relative):

```bash
ACTIVE_CYCLE=$(grep "^ACTIVE_CYCLE=" "${CRAFT_PROJECT_ROOT}/.craft/.global-state" | cut -d= -f2)
```

- **If `ACTIVE_CYCLE` set:** place file in `${CRAFT_PROJECT_ROOT}/.craft/cycles/$ACTIVE_CYCLE/stories/`. Story number from `ls` count + 1. File path: `[N]-[slug].md`. Write `cycle:` and `story_number:` frontmatter.
- **If `ACTIVE_CYCLE` empty:** place file in `${CRAFT_PROJECT_ROOT}/.craft/backlog/`. File path: `[slug].md`. **OMIT `cycle:` and `story_number:` from frontmatter entirely** (do NOT write them as empty strings - existing freeform flow omits them).

### Frontmatter construction

```yaml
---
name: [slug]
title: "[Title from Phase 2]"
type: [ui | technical | content - inferred; default 'technical']
status: planning
priority: [ask via AskUserQuestion: Urgent | High | Medium | Low - default Medium]
created: [today YYYY-MM-DD]
updated: [today YYYY-MM-DD]
cycle: [cycle name without leading number - ONLY if in cycle]
story_number: [N - ONLY if in cycle]
source_concept: [ABSOLUTE path to concept file]
source_concept_last_updated: [SNAPSHOT of concept file's last_updated frontmatter value AT TIME OF STORY CREATION - omit if the concept has no last_updated field]
alignment: pending
chunks_total: 0
chunks_complete: 0
current_chunk: 0
---
```

`source_concept` is the ABSOLUTE path, consistent with Reference Materials. Not relative.

**`source_concept_last_updated` snapshot:** Read the planning concept file's frontmatter `last_updated:` field and copy that value verbatim into the story's frontmatter. This captures "the version of the planning the story was created against" - a downstream consume-time check can later compare this snapshot to the planning concept's current `last_updated` and flag content staleness if they diverge. If the planning concept file has no `last_updated:` field, omit `source_concept_last_updated:` from the story frontmatter entirely (do not substitute another date).

### Body sections (canonical order per LD14)

Write these sections IN THIS ORDER. Skip optional sections (Content Direction, Visual Direction, Wireframe) when planning didn't resolve them.

1. `## Spark` - 2-3 sentences from Phase 4-staged content
2. `## Content Direction` (optional - include only if Phase 4 staged content)
3. `## Scope` (Included / Excluded)
4. `## Preserve` (bulleted list)
5. `## Hardest Constraint` (paragraph with explicit FAIL conditions)
6. `## Dependencies` (Blocked by / Blocks)
7. `## Decisions` (use existing name - NOT "Locked Decisions"; format preserved from concept's existing style)
8. `## Visual Direction` (optional - UI stories with mockup)
9. `## Wireframe` (optional - UI stories)
10. `## Likely Files` (with scan date and action tags)
11. `## Reference Materials` (multi-anchor citations, absolute paths, file-type-appropriate anchors)
12. `## Acceptance` (rough numbered criteria)
13. `## Definition of Done` (standard 6-item checklist - all chunks, acceptance verified, tests passing, preserve confirmed, no regressions, build passes)
14. `## Notes` (any inherited open questions from the source concept land here for visibility)

### DO NOT WRITE these sections (added by downstream flows)

- `## Chunks` - written by plan-chunks-agent when `/craft:story-implement` runs
- `## Delivery` - written by plan-chunks-agent
- `## Risk Tags` - written by content-spark if it runs after story creation

An implementer reading LD14 might assume the 14 sections are the complete list to write - they are. Do NOT write empty `## Chunks` placeholder sections "for consistency with the template" - the template has those placeholders, but the reference file MUST NOT duplicate them. Leave them for downstream flows.

### Reference Materials format (multi-anchor example)

The `## Reference Materials` section must demonstrate the multi-anchor pattern. Example showing both `### Subheading` AND `Decision #N` formats (use whichever the source concept uses):

```markdown
## Reference Materials

**Concept files:**
- `/Users/.../planning/01-customer-profile-tab/08-cycle04-section-rollout.md`:
  - `## Locked decisions (this cycle) -> ### Architecture: Option B`
  - `## Locked decisions (this cycle) -> ### Backend shape: DTO Namespacing`
  - `## Story order rationale` (Address & Contact paragraph)
- `/Users/.../planning/01-customer-profile-tab/09-section-design-v2.md`:
  - `## Fields` (Address & Contact rows, 5 rows)

**Mockups:**
- `/Users/.../planning/01-customer-profile-tab/mockups/customer-profile-v1-material-icons.html` (lines 2649-2664, Identification card)

**Locked patterns:**
- Pattern 14 at .craft/design/locked.md (revised 2026-05-11 - humanized placeholders)
- Pattern 15 #8 at .craft/design/locked.md

**Design tokens:**
- .craft/design/tokens.yaml -> --color-customer-status-active

**active.md entries:**
- `/Users/.../planning/active.md` -> `## Recent state changes -> 2026-05-06 entry` (Draft 3 architecture lock)

**Sibling story precedent:**
- `/Users/.../cycles/3-customer-profile-cycle1/stories/2-address-contact-section.md` (shipped pattern for section card layout)

**project.md:**
- `/Users/.../.craft/project.md`
```

### Write the file

Use **Write** to create the file at the computed path.

## Phase 6: Forward-Link Planning Docs (MANDATORY, idempotent)

This step is MANDATORY. Treat story creation as incomplete until forward-links land. All operations check for existing entries before appending - safe to re-run.

**Critical: normalize the story path to ABSOLUTE form before every grep/comparison.** Story paths may have been written in prior runs as relative (older convention) or absolute (Locked Decision 17). The idempotency check must catch BOTH formats.

### 6a. Update active.md

Read `${CRAFT_PROJECT_ROOT}/.craft/planning/active.md`.

**Idempotency check:**
- Derive the absolute path of the new story.
- Derive its relative-to-project-root variant (e.g., `cycles/9-oss-readiness/stories/13-foo.md`).
- grep active.md for BOTH path variants in changelog entries with today's date.
- If either appears in any changelog entry on today's date: **skip** the append.

Otherwise, use **Edit** to:
- Update frontmatter `last_updated:` to today.
- Add an entry to "Recent state changes" at the top, dated today:

```markdown
- **[today's date] (story [N] created from concept [concept name])**: Story file at `[ABSOLUTE story path]`. Spark: [one-line summary]. Decisions: [count] decisions extracted. Status: planning, alignment: pending.
```

If the focus has shifted (e.g., this story activates work on a different concept), update the `## Focus` section to reflect it.

### 6b. Update each consumed concept file

For every planning concept named in the story's Reference Materials, Read the concept file.

**Idempotency check:**
- Parse the concept's frontmatter `stories:` array.
- Normalize each existing entry to its absolute path (resolve relative entries against the concept file's directory).
- If the new story's absolute path matches any normalized existing entry: **skip** the append.

Otherwise, use **Edit** to:
- Append the new story's ABSOLUTE path to `stories:` frontmatter list.
- Update `last_updated:` to today.
- If the concept has a `## Stories implementing each section` table (or similar forward-link section), add a row for the new story. If no such table exists AND the concept is large (multi-section), CREATE one near the top of the file after the intro:

```markdown
## Stories implementing this concept

| Story | Cycle | What it uses | Status |
|---|---|---|---|
| [story title] | [cycle name or "backlog"] | [brief description of scope] | planning |
```

### 6c. Update initiative README (if applicable)

If the concept lives in an initiative folder (e.g., `01-customer-profile-tab/08-cycle04-section-rollout.md`), Read the folder's `README.md`.

**Idempotency check:**
- Derive both absolute and relative variants of the story path.
- grep the README for either variant.
- If either appears: **skip** the row addition.

Otherwise, if the README has a story-per-concept index table, add a row using the absolute story path. If no such index exists, skip entirely - don't invent indexes that weren't there.

## Phase 7: Exit

Display a clean summary:

```
Story created: [ABSOLUTE story path]
Source concept: [ABSOLUTE concept path]
Status: planning, alignment: pending
Decisions extracted: [N]
Reference Materials: [N citations] ([anchor breakdown: M section anchors, P mockup ranges, Q Pattern refs, R token refs, S active.md entries])
Forward-links:
  - active.md: [updated | skipped (already present)]
  - [concept name]: [updated | skipped (already present)]
  - initiative README: [updated | skipped (no index) | skipped (already present)]

Next: Run /craft:story-implement when ready to plan chunks. The alignment-check will fire automatically and (per Chunk 6) will receive Reference Materials excerpts so it doesn't re-ask planning-resolved questions.
```

The parent command (`/craft:story-new`) is done. Do NOT continue to Step 3 (Choose Your Path) or Step 3b (Content Check) - the file is complete and `alignment: pending` triggers the existing flow when the user runs implement.

## Implementation Notes

- **No Skill invocations from this file.** All work is inline Reads, Writes, Edits, AskUserQuestions, and Task invocations for the Explore agent. The parent command Reads this file - if this file Read another skill via the Skill tool, it would create the chain break the chain-break-fix-discovery memo identifies.
- **Absolute paths everywhere.** Reference Materials uses absolute paths. `source_concept` uses absolute paths. `${CRAFT_PROJECT_ROOT}/.craft/.global-state` is the state file (Bash-resolved absolute). Wrapper-vs-nested monorepo layouts cause relative paths to silently fail.
- **Anchor strategy by file type.** Planning files: section + subheading or decision number, NEVER line numbers. Mockups: line ranges OK. locked.md: Pattern N. tokens.yaml: token name. active.md: dated entry. Code: function/class name preferred.
- **One AskUserQuestion per gap.** Never batch gaps into one question. Each gap deserves its own focused decision.
- **Supersession-first.** Phase 3a runs BEFORE Phase 3b. If supersession markers exist, surface them before extracting.
- **Idempotency in Phase 6.** Every forward-link operation checks for existing entries before appending. Safe to re-run on the same concept.
- **The Explore agent does the heavy reading.** This file orchestrates; the agent extracts. Main context stays clean.
- **Single-story scope.** The agent extracts only the slice relevant to the user's story title, not all stories from a multi-story concept. PARTIAL fallback when scope is unclear.
- **DO NOT write `## Chunks`, `## Delivery`, or `## Risk Tags`.** Those are added by downstream flows (plan-chunks-agent, content-spark) when they run, not by story creation.
