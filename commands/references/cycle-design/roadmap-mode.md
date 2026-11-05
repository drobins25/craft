# Roadmap Mode Reference

Quick-sketch flow for capturing multiple cycles with story titles only - no sparks, no details. Fires when the user picks "Quick sketch (Roadmap)" at Step 1b, or loops back via Step R3 for additional cycles.

The orchestrator command (`commands/craft-cycle-design.md`) defines the routing - this reference contains the full mode flow.

---

## Roadmap Mode (Quick Sketch)

Entered when user selects "Quick sketch (Roadmap)" in Step 1b. Creates a lightweight cycle with just story titles — no sparks, no details.

### Step R1: Capture Story Titles

> "List out the stories for **[cycle name]**. Just titles — we'll flesh them out later."

Capture story titles conversationally. The user can list them all at once or one by one. When the list feels complete, confirm:

Include inferred type tags where possible. If there's enough context to classify a story (from the title and any brief description), tag it. If not, leave the type out — it will be set during Detailing Mode when the spark is captured.

> "Here are the stories for **[cycle name]**:
>
> 1. [Title 1] `ui`
> 2. [Title 2] `technical`
> 3. [Title 3]
>
> Save these? Or tell me what to add, change or remove. (Check the type tags - correct any that are wrong.)"

What each reply does:

- **A yes** creates the cycle with these titles: continue to Step R2.
- **Adding, changing or removing titles** edits the list and shows it again, ending on the same question.
- **A reply that is none of these** gets the same question back, with the list unchanged. Never assume what it means.

### Step R2: Create Cycle and Story Files

1. **Create cycle** using `create-cycle.sh`. If the cycle was inferred from a planning concept (verbatim-quote rule per craft-cycle-design.md Step 1), pass the planning doc path(s) as the 5th positional arg:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/create-cycle.sh "[cycle-slug]" "[Cycle Title]" "[Goal]" "." "[source-concept-paths]"
```
   - **`cycle-slug`** = kebab-case slug for the directory (e.g., `auth-flow`). The script auto-numbers it (creates `3-auth-flow/`).
   - **`Cycle Title`** = human-readable name shown in status line and context (e.g., `"Auth Flow"`). Always provide this.
   - **`source-concept-paths`** = comma-separated planning doc paths, or empty string. Written to cycle.yaml's `source_concept` field.

2. **Before writing story files, apply planning-source routing.** Read cycle.yaml. If `source_concept` is populated, apply the **action-moment framing** per story:

   - **Planning-extraction moment** (story is being sketched from the planning concept's content): Read `${CLAUDE_PLUGIN_ROOT}/commands/references/story-from-planning.md` and execute its phases against the cycle's source_concept for that story. The protocol writes the story file with planning-derived spark + `source_concept` + `source_concept_last_updated` frontmatter.

     **CRITICAL: include the invocation marker** when executing the protocol. State explicitly in your context before running Phase 1:

     > `INVOCATION: cycle-design - planning source already confirmed in cycle.yaml`

     This marker is required for Phase 1's auto-resolve to fire. Without it, Phase 1 falls back to corpus-scan and asks the user to pick a concept.

   - **Add-a-separate-story moment** (story is freeform, not from the planning): Continue with the roadmap-mode flow below - title + spark from conversation, no source_concept fields.

   ⛔ Use the Read tool, not the Skill tool, when invoking story-from-planning.md inline.

3. **Create story files** (for freeform stories, after planning-extracted stories have been handled by the protocol above). The orchestrator generated sparks during the story breakdown — they MUST be written into the files, not discarded.

Write to `.craft/cycles/[cycle-dir]/stories/[N]-[slug].md`:
```markdown
---
name: [slug]
title: "[Story Title]"
type: [ui/technical/content — from confirmed tags, omit if unclassified]
status: planning
priority: medium
created: [date]
updated: [date]
cycle: [cycle-name]
story_number: [N]
decisions: []
alignment: pending
chunks_total: 0
chunks_complete: 0
current_chunk: 0
---

# Story: [Story Title]

## Spark
[Write the spark description that was discussed and approved during the story breakdown. This content already exists in the conversation — re-read it and transcribe it here. Never use a placeholder.]

## Dependencies
**Blocked by:** [from discussion and file-overlap check — leave empty if not yet determined, write "none" only if explicitly confirmed]
**Blocks:** [from discussion — leave empty if not yet determined]

## Chunks
<!-- Added via plan-chunks -->
```

The `decisions:` line holds only the approved decision records the user named for this story in the conversation, each as its full dated slug (the record's file name without `.md`): never add a record by tag, by topic, or by judged relevance, and never scan the store for candidates - any record the user did not name is NOT LAW for this story - it is history; write `[]` when the user named none.

3. **Clear PLANNING_CYCLE** — the cycle shell is done:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh PLANNING_CYCLE ""
```

### Step R3: Roadmap Loop

> "**[Cycle Name]** created with [N] story titles.
>
> Want to sketch another cycle?"

Use **AskUserQuestion**:
```
question: "Cycle saved. Create another?"
header: "Next"
options:
  - label: "Yes, another cycle"
    description: "Sketch the next cycle in the roadmap"
  - label: "No, I'm done"
    description: "Show roadmap summary and exit"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their intent.

**If "Yes, another cycle":**
- Go back to **Step 1: Name & Goal** (start a fresh cycle)
- PLANNING_CYCLE is already cleared — the new cycle gets its own

**If "No, I'm done":**
- Show summary of all cycles created:

> "**Roadmap Summary**
>
> | Cycle | Stories | Status |
> |-------|---------|--------|
> | [Cycle 1] | [N] stories | planning |
> | [Cycle 2] | [M] stories | planning |
>
> Use `/craft` to detail or activate these cycles when ready."

---

