# Batch Triage Reference

Detailed UX patterns, templates, and heuristics for the batch triage flow (BT-1 through BT-7). The orchestrator SKILL.md defines the flow — this reference provides the supporting details.

---

## Concern Tier Definitions

Concerns and decisions from agent plan reports are sorted into three tiers based on the agent's reported confidence:

| Tier | Confidence | Agent Behavior | Triage Behavior |
|------|-----------|----------------|-----------------|
| **Needs review** | Low | Agent flagged it, made a tentative recommendation but isn't sure | Individual AskUserQuestion per item (BT-2) |
| **Worth noting** | Medium | Agent decided but thinks user should verify | Individual AskUserQuestion per item (BT-3) — same pattern as BT-2 |
| **Informational** | High | Agent decided confidently, included for visibility | Not surfaced during triage — shown in plan presentation only |

### Collecting Concerns Across Stories

1. Iterate through all successful plan reports
2. From each report, extract:
   - Flagged Concerns table entries (concern, confidence, recommendation)
   - Decisions Made table entries where confidence is low
   - Design Decision Validation entries where status is `concern` or `invalid`
   - Critical Blockers (always treated as needs-review)
3. Tag each item with its source story name
4. Sort all items: low confidence first, then medium, then high
5. Within the same confidence tier, group by story (keeps mental context together)

### Counting for BT-1 Overview

```
needs_review_count = items with confidence: low
worth_noting_count = items with confidence: medium
informational_count = items with confidence: high
```

---

## AskUserQuestion Templates

**Before constructing any BT-2/BT-3/BT-4 AskUserQuestion, Read `${CLAUDE_PLUGIN_ROOT}/commands/references/auq-grammar.md` and mirror the worked gate that matches the question** - these are forks (a recommendation weighed against a real alternative). The question field is self-contained: one or two sentences of the problem, then the ask. The recommendation is the first option, labeled "(Recommended)", and every option carries an honest one-line verdict. The grammar governs how options read; it never changes which outcomes a template offers - the distinct closers below survive as-is.

**Answer-time write (same rule as S-3):** after each answered BT-2/BT-3/BT-4 question, apply that answer's edit to the affected story file immediately (per "Story File Writing" below) and print one truthful receipt line before the next question renders; a no-op answer prints "kept as planned". A BT-4 cohesion answer writes BOTH stories' coordination notes at answer time - the second-side note is a one-line append to the other story's chunk, not a plan load, so the never-hold-two-plans rule is not violated. Per-answer writes touch one story file at a time. Answers must survive a session that dies mid-triage.

### BT-2: Needs Review (per item)

```yaml
question: "[Story Name] — [the concern and the ask, self-contained: what the agent found, what it trades off, which way to go]"
header: "Review"
multiSelect: false
options:
  - label: "[Agent's recommendation] (Recommended)"
    description: "[Agent's reasoning — 1-2 sentences explaining why]"
  - label: "[Alternative approach]"
    description: "[Honest verdict — why this might be better, or its cost in a phrase]"
  - label: "Skip for now"
    description: "Leave this for implementation to figure out"
```

**Deriving the alternative:** Look at the agent's concern description. If it mentions two approaches, use the non-recommended one. If it's a yes/no decision, the alternative is the opposite. If no natural alternative exists, use "Different approach" as the second option - the built-in "Chat about this" exit already covers discussion.

### BT-3: Worth Noting (per item — same as BT-2)

```yaml
question: "[Story Name] — [the decision and the ask, self-contained: what the agent decided, what it trades off, keep or change]"
header: "Worth noting"
multiSelect: false
options:
  - label: "[Agent's recommendation] (Recommended)"
    description: "[Agent's reasoning — 1-2 sentences explaining why]"
  - label: "[Alternative approach]"
    description: "[Honest verdict — why this might be better, or its cost in a phrase]"
  - label: "Accept as-is"
    description: "Agent's call is fine, move on"
```

**Deriving the alternative:** Same as BT-2 — look at the concern description for a natural alternative. Use "Different approach" if no natural alternative exists.

### BT-4: Cohesion Issue (per issue)

```yaml
question: "[The overlap and the ask, self-contained — e.g., 'Login and Signup both modify auth-form.tsx; who owns it, or extract a shared component?']"
header: "Overlap"
multiSelect: false
options:
  - label: "[Recommended resolution] (Recommended)"
    description: "[What this means for implementation — and why it wins]"
  - label: "[Alternative resolution]"
    description: "[Honest verdict — what this means for implementation, its cost in a phrase]"
  - label: "Flag for implementation"
    description: "Note the overlap, handle during implementation"
```

A resolved BT-4 answer lands in BOTH story files at answer time (see the answer-time write rule above) — never defer the second side to BT-6.

### BT-5: Per-Story Approval

```yaml
question: "[Story Name] — [N] chunks, [M] files. Approve?"
header: "Approve"
multiSelect: false
options:
  - label: "Approve"
    description: "Write plan to story file, mark ready"
  - label: "Explore creatively"
    description: "Invoke creative-spark to riff on this story's approach"
  - label: "Adjust"
    description: "Provide feedback, re-plan this story interactively"
  - label: "Reject"
    description: "Leave as planning status, skip for now"
```

### BT-5: Adjust Feedback (when user picks "Adjust")

```yaml
question: "What should change about [Story Name]'s plan?"
header: "Feedback"
multiSelect: false
options:
  - label: "Different approach entirely"
    description: "Re-plan with a new direction"
  - label: "Fewer/smaller chunks"
    description: "Plan is over-scoped, simplify"
  - label: "More detail needed"
    description: "Chunks are too vague, need specifics"
```

The user's selection (or free-text via "Other") is stored as adjustment feedback. It becomes the `APPROACH:` context when re-planning this story in BT-7. This ensures the re-planning agent knows what the user wants changed.

### BT-5: Batch Approval Fast Path (5+ clean stories)

```yaml
question: "All [N] plans look clean — no concerns flagged. Approve all at once?"
header: "Batch approve"
multiSelect: false
options:
  - label: "Approve all"
    description: "Write all plans, mark all ready"
  - label: "Review each"
    description: "Go through them one by one"
```

**Trigger condition:** 5+ stories AND BT-2 had zero needs-review items AND BT-3 had zero worth-noting items AND BT-4 had zero cohesion issues. If any phase had interaction, fall back to individual approval.

### BT-7: Next Steps

```yaml
question: "What's next?"
header: "Next"
multiSelect: false
options:
  - label: "Start implementing"
    description: "Begin with the first ready story"
  - label: "Re-plan adjusted stories"
    description: "Interactive planning for stories that need refinement"
  - label: "Done for now"
    description: "Come back later"
```

**Option visibility:**
- "Re-plan adjusted stories" only appears if there are adjusted stories queued
- If all stories were approved (none adjusted), show only "Start implementing" and "Done for now"

---

## Cohesion Check Heuristics

The post-hoc cohesion check (subagent mode, Phase M-3) uses these heuristics to detect cross-story conflicts.

### File Overlap Detection

1. Extract all files from every story's File Impact table
2. Build a map: `{ file_path: [story_names] }`
3. Flag any file appearing in 2+ stories

**Severity assessment:**
| Overlap Type | Severity | Action |
|-------------|----------|--------|
| Both stories CREATE the same new file | High | Must resolve — only one story should create it |
| Both stories MODIFY the same existing file | Medium | Flag — verify modifications don't conflict |
| One creates, one modifies the same file | Medium | Flag — verify ordering (creator should go first) |
| Same directory but different files | Low | Don't flag — parallel work in same area is normal |

**False positive filter:** Only flag when modification SCOPE overlaps. Two stories modifying the same file but touching different functions/sections is normal and shouldn't be flagged. Check chunk descriptions for overlap clues — if both mention "update the header component" it's a real conflict; if one updates "auth logic" and the other "styling", it's fine.

### Component Overlap Detection

1. Extract component names from all chunk descriptions
2. Look for similar names or identical purposes across stories
3. Flag: "Stories [A] and [B] both create [component type]"

**Trigger:** Two stories creating components with similar names (e.g., `UserCard` and `UserProfile`) or identical purposes (e.g., both create "a form for user settings"). Don't flag when components are clearly distinct despite being in the same domain.

### Decision Conflict Detection

1. Extract Decisions Made tables from all plan reports
2. Compare decisions that address the same question/concern
3. Flag: "Stories [A] and [B] made different choices for [concern]"

**Example:** Story A decides "use React Hook Form for the settings form" while Story B decides "use native form handling for the settings form." Same concern, different answers.

**Don't flag** when decisions are about different forms, different components, or different domains — even if they use different approaches. Each story's context may justify a different choice.

---

## Edge Cases

### All Stories Fail

If every agent fails (all stories in the failure queue):

1. Report: "All [N] stories failed to plan. This usually means the agents couldn't access the codebase or the stories need more detail."
2. Use **AskUserQuestion**:
   ```yaml
   question: "All stories failed to plan. How should we proceed?"
   options:
     - label: "Retry all"
       description: "Re-launch the full batch"
     - label: "Plan interactively"
       description: "Switch to single-story mode for each"
     - label: "Done for now"
       description: "Investigate and come back later"
   ```
3. Skip BT-1 through BT-7 entirely (nothing to triage)

### All Concerns Are Informational

If every concern across all stories has confidence: high:

1. BT-1 reports: "Planned [N] stories successfully. No items need review — agents were confident across the board."
2. Skip BT-2 and BT-3 entirely
3. Proceed to BT-4 (cohesion check still runs — file overlap isn't about confidence)
4. BT-5 uses batch approval fast path if 5+ stories

### Single Story in Batch Mode

If `MODE: batch` is passed but only one story has `status: planning`:

- Phase M-1 detects this: "Only 1 planning story found"
- Switch to single-story path (S-1 through S-6) — no batch overhead
- This is handled in M-1, before batch triage is ever reached

### Many Stories (8+)

User fatigue risk is real with 8+ stories. Mitigations built into the flow:

- BT-3 uses individual questions (same as BT-2) but medium-confidence items are typically fewer and quicker to resolve
- BT-5 batch approval fast path (for clean batches) reduces to one interaction
- BT-2 groups needs-review items by story (mental context stays coherent)
- If the batch is fully clean (all informational, no cohesion issues), the user sees: BT-1 overview → BT-5 batch approve → BT-7 next steps. Three interactions total.

### Adjusted Story Re-Planning

When a story is marked "Adjust" in BT-5:

1. User feedback is collected immediately via the "What should change?" AskUserQuestion (see BT-5 Adjust Feedback template above)
2. The story is queued for re-planning AFTER the batch triage completes
3. Re-planning uses the single-story path (S-1 through S-6)
4. The user's feedback from step 1 is included as `APPROACH:` context in the agent prompt — e.g., `APPROACH: User wants fewer chunks, plan is over-scoped`
5. Previous triage decisions (from BT-2/BT-4) that apply to this story are included as BINDING constraints, not just don't-re-ask context — those answers already landed in the story file at answer time and were receipted to the user; the re-planning agent must preserve them in the new plan or flag a conflict in its concerns summary, never silently drop a receipted answer
6. After re-planning, the story goes through single-story triage (S-3/S-4) — NOT back through batch triage

### Cohesion Issues That Can't Be Resolved

If a cohesion issue has no clean resolution (e.g., two stories genuinely need to modify the same function):

- "Flag for implementation" is always an option
- The flag is recorded as a note in both story files' chunks: "**Coordination note:** [file] is also modified by [other story]. Implement [this story] first / coordinate changes."
- The implementer agent sees this note and accounts for it

---

## Story File Writing (BT-6 Details)

**BT-6 is reconciliation, not first-write.** Triage adjustments already landed in the story files at answer time — both sides of every BT-4 resolution included — with a receipt shown per answer. BT-6's job is to verify consistency (nothing answered is missing from the files), apply the frontmatter updates, and flip status to ready. The write rules below define WHAT a complete story file contains; use them as the checklist to verify against, and as the write logic for anything that genuinely hasn't landed yet. For each approved story:

### What Gets Written

1. **The Pitch** — sell + conditions table (every condition tagged `verified` / `system-owned` / `unverifiable -> Chunk N's FIRST test`). Goes between `## Spark` and `## Acceptance Criteria` in the story file. The `## Investigation` narrative (causal, dead ends kept) goes directly before `## Chunks`.

2. **Acceptance criteria** — From the agent's plan + any additions from triage discussion. Replaces or augments existing acceptance criteria.

3. **Chunks** — **Preserve the agent's chunk specs verbatim. Do NOT summarize.** Each chunk in the story file MUST include:
   - **Goal:** What the chunk accomplishes
   - **Files:** Every file created/modified with full paths
   - **Contracts:** The receipted seams — every line carries `[verified: ...]`, `[owner: Chunk N]`, `[investigation: ...]`, or `[defines]`. The implementer holds these as law.
   - **Approach:** Advisory prose — pattern pointers, ordering, gotchas. No code bodies (decision-code with a receipt is the rare exception).
   - **Test cases:** Named assertions the implementer writes bodies for.
   - **Done When:** Checklist of specific, testable criteria (not vague summaries)
   - **What Could Break:** Every entry `[resolved]` or `[escalated to conditions]`

   The quality bar: seams locked with receipts, interiors left to the implementer. Compare against single-story plans — batch mode must produce the same depth.

   With concrete adjustments from triage:
   - **BT-2 decisions:** Find the chunk(s) affected by the resolved concern. Replace the agent's tentative approach with the user's chosen approach in the chunk description. Example: if the agent planned "use modal for confirmation (tentative)" and the user chose "use inline confirmation," update the chunk text to say "use inline confirmation."
   - **BT-4 cohesion resolutions:** Add a `**Coordination:**` line to the affected chunk. Format: `**Coordination:** [file] is also modified by [other story] — [resolution, e.g., "this story owns the validation logic, Login story imports it"].` The implementer agent reads this and accounts for it.

4. **Frontmatter updates:**
   ```yaml
   status: ready        # was: planning
   chunks_total: [N]    # from agent's plan
   updated: [YYYY-MM-DD]
   ```

### Status Script

After writing each story file:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-story-status.sh [story-file-path] ready
```

This updates `.state` tracking and any hook-managed state.

### Write Order

Stories are written in story_number order (same as implementation order). This ensures `.state` progression is clean and any cross-story references are consistent.
