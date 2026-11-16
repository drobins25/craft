# Research Integration

How to gather context before planning begins. This covers sibling story analysis and the plan-chunks-agent launch.

---

## Sibling Context Gathering (Phase 0)

**Skip if:** Story is in backlog (no cycle context).

**If story is in a cycle:**

1. **Scan sibling stories:**
   Use **Glob** `"[cycle_directory]/stories/*.md"` → list of story files.
   Exclude the current story from the list.

2. **Quick relevance check** for each sibling:
   - Read sibling's frontmatter + first 50 lines (spark, scope)
   - Check for keyword overlap with current story (e.g., both mention "auth", "user", "form")
   - Check for file path overlap in scope sections
   - Check if sibling has `status: ready` or `complete` (planned work)

3. **Relevance heuristics:**
   | Signal | Weight |
   |--------|--------|
   | Same file paths in scope | High — definitely related |
   | Same domain keywords (auth, api, dashboard) | Medium — likely related |
   | Same component types (form, modal, table) | Medium — may share patterns |
   | Different domains entirely | Low — probably unrelated |
   | Sibling is `planning` with no chunks | Medium — read spark, check for keyword/file overlap. Planning siblings are the MOST important to check because they're about to plan against the same codebase. Do NOT skip them. |

4. **If related siblings found**, extract from each:
   - Story name and status
   - Files mentioned in scope (included section)
   - Files in chunks (if chunks exist)
   - Key decisions locked

5. **Build sibling context block:**
   ```markdown
   **Sibling story context:**

   ### [Sibling Name] (status: ready)
   - **Files:** src/components/Auth/, src/hooks/useAuth.ts
   - **Decisions:** React Hook Form for forms, JWT in cookies
   - **Overlap:** Both touch src/components/Auth/

   ### [Another Sibling] (status: complete)
   - **Files:** src/lib/api.ts, src/types/user.ts
   - **Decisions:** Zod for validation
   - **Overlap:** Both modify src/lib/api.ts
   ```

6. **If no relevant siblings:** Set context to `"No relevant siblings — stories appear unrelated."`

**Efficiency note:** This is a quick scan, not deep extraction. Read only what's needed to determine relevance. If a sibling is clearly unrelated (different domain, no file overlap), skip detailed extraction.

---

## Agent Launch Prompt — Single Story (Phase S-1)

**INVOKE the plan-chunks-agent using the Task tool:**

```
Task tool:
  subagent_type: "craft:plan-chunks-agent"
  description: "Plan [story title]"
  prompt: "Research and plan this story.

  **Story file:** [full path to story .md file]
  **Cycle directory:** [path to cycle dir, or 'backlog' if not in cycle]
  **Project root:** [derived from story path — parent directory of .craft/]
  **PLUGIN_ROOT:** [resolved ${CLAUDE_PLUGIN_ROOT} — the subagent cannot resolve it itself; it needs this to reach plugin-internal scripts like the Living Map runner]

  **FIRST ACTION — before reading any source file, pull your read plan:**
  [one literal command per scope directory, pre-computed from the story's Likely Files / KEY_FILES — resolved paths, ready to run; omit the block only if the story names no files:]
  [resolved PLUGIN_ROOT]/scripts/map/map-run.sh assemble [dir] --root [project root]
  Each slice line ends in [off=N,lim=M] — issue those ranged Reads at the narrowest useful span; never open a whole annotated file. An empty or floored slice for a directory = orient that area normally.

  CRITICAL: SCOPE ALL SEARCHES to the project root above.
  Do NOT search the monorepo root or parent directories.
  Use the project root as the `path` parameter for ALL Glob and Grep calls.

  **Cycle goal:** [goal from cycle.yaml, or 'N/A' if backlog]

  [SIBLING CONTEXT FROM PHASE 0.1b]

  [OPTIONAL: Starting context from orchestrator — validate it THROUGH the map slice's ranged reads, then deepen. Provided context means read NARROWER, never skip orientation — the FIRST ACTION above still runs first:
    APPROACH: [value]
    DECISIONS: [value]
    KEY_FILES: [value]]

  Read the story, understand what it needs, then research the codebase and plan chunks.
  If the story's `## Visual Direction` has an Element Binding Table, verify each row's token against tokens.yaml and bind every row a chunk builds as a `[visual-source:]` Contract; route TBD rows to the Pitch conditions table.
  Return findings in your structured output format."
```

**Include sibling context:** Paste the sibling context block from Phase 0 directly into the prompt. If no relevant siblings, include: `"**Sibling context:** No relevant siblings — stories appear unrelated."`

**Include orchestrator context:** If args include `APPROACH:`, `DECISIONS:`, or `KEY_FILES:`, add the optional starting context block.

---

## Agent Launch Prompt - Multi-Story Batch (Batch Planning, step 5)

For batch planning, each agent receives all sibling names/sparks plus predecessor context for dependent stories:

```
Task tool:
  subagent_type: "craft:plan-chunks-agent"
  description: "Plan [story-name]"
  prompt: "Research and plan this story.

  **Story file:** [full path]
  **Cycle directory:** [path]
  **Project root:** [derived path]
  **PLUGIN_ROOT:** [resolved ${CLAUDE_PLUGIN_ROOT} — the subagent cannot resolve it itself]

  **FIRST ACTION — before reading any source file, pull your read plan:**
  [one literal command per scope directory, pre-computed from the story's Likely Files — resolved paths, ready to run; omit only if the story names no files:]
  [resolved PLUGIN_ROOT]/scripts/map/map-run.sh assemble [dir] --root [project root]
  Each slice line ends in [off=N,lim=M] — issue those ranged Reads at the narrowest useful span; never open a whole annotated file. An empty or floored slice for a directory = orient that area normally.

  CRITICAL: SCOPE ALL SEARCHES to the project root above.
  Do NOT search the monorepo root or parent directories.
  Use the project root as the `path` parameter for ALL Glob and Grep calls.

  **Cycle goal:** [goal from cycle.yaml]

  **All stories in cycle (for sibling awareness):**
  [story-name-1]: [spark first sentence]
  [story-name-2]: [spark first sentence]
  ...

  [PREDECESSOR CONTEXT - if this story has in-set dependencies, include here.
  See SKILL.md Batch Planning, step 6 "Pass contracts forward" for the exact format:
  Goal + Files + Contracts from each predecessor chunk,
  with CRITICAL alignment instructions.]

  Read the story, understand what it needs, then research the codebase and plan chunks.
  If the story's `## Visual Direction` has an Element Binding Table, verify each row's token against tokens.yaml and bind every row a chunk builds as a `[visual-source:]` Contract; route TBD rows to the Pitch conditions table.
  Return findings in your structured output format."
```

**Key differences from single-story:**
- Batch mode provides ALL story names/sparks (not filtered by relevance) so the agent can detect file overlap and coordination needs with any sibling
- **Dependent stories include predecessor context** - the Goal, Files, and Contracts from each chunk of the story they depend on, with explicit instructions to align contracts (IDs, file paths, exports, naming conventions). See SKILL.md Batch Planning, step 6 "Pass contracts forward" for the full format.

