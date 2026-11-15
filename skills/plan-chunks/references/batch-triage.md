# Batch Triage Reference

The batch triage flow (BT-1 through BT-7): what runs after every story in a batch has a plan. The planning skill hands off here at the end of Batch Planning; this file owns the flow, its cards and its edge cases.

**Every item that is asked gets its own card.** Never fold items into one list with a single "All good?", because a folded list gets approved without being read. Five items across three stories is five cards.

## The flow

| Phase | What | Key behavior |
|-------|------|-------------|
| **BT-1** | Overview | Write stage `triage` for each planned story. Count items by tier; the batch settled list prints before Question 1. |
| **BT-2** | Needs review | One card per item, grouped by story. |
| **BT-3** | Worth noting | One card per item, grouped by story, with keeping the plan as written as an outcome. |
| **BT-4** | Cohesion | File overlaps, duplicate components, conflicting decisions. One card per issue. |
| **BT-5** | Per-story approval | Read each story file fresh with the Read tool, never from memory or a summary. Present one story, wait for the answer, then read the next: never hold two plans in context. Each gets Approve, Adjust or Reject. |
| **BT-6** | Finalize | Triage answers already landed at answer time; verify nothing is missing and mark approved stories ready. Queue adjusted stories for re-planning. |
| **BT-7** | Summary | Report counts and offer what comes next. |

The progress band reads each story's planning stage, so keep it true through triage:

- **BT-1:** `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/planning-stage.sh [story-file] triage` for each planned story as triage begins.
- **BT-5 Reject, and BT-5 Adjust:** `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/planning-stage.sh [story-file] clear` for that story. An adjusted story's queued re-plan writes its stages again from S-1.
- **BT-6 Approve:** `update-story-status.sh [story-file] ready` (see Status Script below), which also clears the stage.

---

## Concern Tier Definitions

Concerns and decisions from agent plan reports are sorted into three tiers based on the agent's reported confidence:

| Tier | Confidence | Agent Behavior | Triage Behavior |
|------|-----------|----------------|-----------------|
| **Needs review** | Low | Agent flagged it, made a tentative recommendation but isn't sure | One question card per item (BT-2) |
| **Worth noting** | Medium | Agent decided but thinks user should verify | One question card per item (BT-3), with keeping the plan as written as an outcome |
| **Informational** | High | Agent decided confidently, included for visibility | Never asked: joins the batch settled list with the mention-tier decisions |

### Collecting Concerns Across Stories

1. Iterate through all successful plan reports
2. From each report, extract:
   - Flagged Concerns table entries (concern, confidence, recommendation)
   - Decisions Made table entries routed by the Product-stake column as S-3's Decisions Made step does: `ask` rows are BT-2 items regardless of confidence, `mention` rows join the batch settled list; with no Product-stake column, low-confidence rows are BT-2 items
   - Design Decision Validation entries where status is `concern` or `invalid`
   - Critical Blockers (always needs-review). In batch the planner cannot stop for a plan fork or a research request, so it decides down its recommended branch and lists the decision here; the card is where the user gets that decision back.
   - Not Covered table entries: every risk the planner named and left out joins the batch settled list by name with its reason, so nothing is dropped unseen. A row marked as one a user would see is a BT-2 item: accept it as it stands (proposed), or adjust this story, which queues it through "Adjusted Story Re-Planning". Never re-launch a planner from inside triage, because it rewrites the story file and the answers already applied would be lost.
   - Plan checks that still fail: when batch step 7 found a failed check on a story and the story went on to triage anyway, each failure still standing is printed at the top of that story's group in the batch settled list.
   - Cycle Impact rows that are not `none` (story size, new dependencies, scope creep, new story needed): BT-2 items, one card per row with the two outcomes S-3's Cycle Impact step gives that row
3. Tag each item with its source story name
4. Sort BT-2 items first, then BT-3 items, then settled-list items
5. Within each group, group by story (keeps mental context together)

### Counting for BT-1 Overview

```
needs_review_count = BT-2 items (ask-tier rows, low-confidence decisions from a summary without a Product-stake column, low-confidence concerns, blockers, Not Covered rows a user would see, design checks marked concern or invalid, Cycle Impact rows that are not none)
worth_noting_count = BT-3 items (medium-confidence concerns)
informational_count = settled-list items (mention-tier rows, high-confidence concerns, Not Covered rows a user would not see, plan checks still failing)
```

---

## Question Templates

**Before asking any BT-2, BT-3 or BT-4 card, or printing the batch settled list, Read `${CLAUDE_PLUGIN_ROOT}/commands/references/question-card.md` once.** The reference owns the card and the list; the sections below choose which items reach a card and what each outcome does.

**Answer-time write (same rule as S-3):** after each answered BT-2/BT-3/BT-4 card, apply that answer's edit to the affected story file immediately (per "Story File Writing" below) and print the read-back the reference gives before the next card renders; a no-op answer reads "kept as planned". A reopened settled item is written the same way. A BT-4 cohesion answer writes BOTH stories' coordination notes at answer time - the second-side note is a one-line append to the other story's chunk, not a plan load, so the never-hold-two-plans rule is not violated. Per-answer writes touch one story file at a time. Answers must survive a session that dies mid-triage.

**Under a Go run** (only when `${CLAUDE_PLUGIN_ROOT}/commands/references/go-run.md` is in force for this conversation; otherwise the cards below apply unchanged): items that are not product forks are applied and logged as go-run.md's `## Planning` says, with no card. Critical Blockers and any item that passes the fork test are asked as below, so a decision only the user can make is never made for them.

### BT-2: Needs Review (per item)

One card per item. The first words of the question paragraph name the story, then the concern and the ask, self-contained: what the agent found, what it trades off, which way to go. The agent's recommendation is the proposed option; the other option is the honest alternative from the concern description (a yes/no decision's alternative is the opposite).

### BT-3: Worth Noting (per item)

One card per item, the same shape as BT-2: the first words of the question paragraph name the story, then the decision and the ask, self-contained: what the agent decided, what it trades off, keep or change. The agent's decision is the proposed option, beside the honest alternative, and a third outcome keeps the plan as the agent wrote it.

### The batch settled list

The mention-tier decisions, the high-confidence concerns and the Not Covered rows a user would not see are never asked. They join the batch settled list, grouped by story. An entry is the story name, then the call in product words, then an indented line of code facts - the same shape as the reference's settled list. The list prints once under `Settled without asking - say which to reopen`, before Question 1, or, when BT-2, BT-3 and BT-4 ask no card, at the top of BT-5: above the batch-approve question when that fires, otherwise above the first story's presentation. A listed item is accepted by not reopening it; when the user names one, it is asked on a card in the normal order.

### BT-4: Cohesion Issue (per issue)

One card per issue. The first words of the question paragraph name the stories and the overlap, self-contained (for example, Login and Signup both modify the auth form: who owns it, or extract a shared component?). Outcomes: the recommended resolution (proposed), an alternative resolution, and "Flag for implementation", which writes a coordination note to both stories and leaves the overlap to the implementer.

A resolved BT-4 answer lands in BOTH story files at answer time (see the answer-time write rule above) — never defer the second side to BT-6.

### BT-5: Per-Story Approval

```yaml
question: "[Story Name] — [N] chunks, [M] files. Approve?"
header: "Approve"
multiSelect: false
options:
  - label: "Approve"
    description: "Write plan to story file, mark ready"
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
question: "All [N] plans look clean - nothing above needs your answer. Approve all at once?"
header: "Batch approve"
multiSelect: false
options:
  - label: "Approve all"
    description: "Write all plans, mark all ready"
  - label: "Review each"
    description: "Go through them one by one"
```

**Trigger condition:** 5+ stories AND BT-2 had zero needs-review items AND BT-3 had zero worth-noting items AND no settled item was reopened AND BT-4 had zero cohesion issues. If any phase had interaction, fall back to individual approval.

The settled list prints directly above this question. A reply that names a listed item reopens it on a card, and approval falls back to one story at a time.

### BT-7: Next Steps

```yaml
question: "What's next?"
header: "Next"
multiSelect: false
options:
  - label: "Start implementing"
    description: "Begin with the first ready story (hands back to cycle-start when it is waiting)"
  - label: "Re-plan adjusted stories"
    description: "Interactive planning for stories that need refinement"
  - label: "Done for now"
    description: "Come back later"
```

**Option visibility:**
- "Re-plan adjusted stories" only appears if there are adjusted stories queued
- If all stories were approved (none adjusted), show only "Start implementing" and "Done for now"

**What each answer does:**
- **Start implementing** applies the planning skill's hand-back rule (S-6): when story-implement or cycle-start is up the call chain, say in one line that the stories are ready and return to it with the first ready story. With nothing waiting, invoke the Skill tool with `skill: "craft:craft-story-implement"` and the first ready story's path. Never implement directly.
- **Re-plan adjusted stories** runs each queued story through "Adjusted Story Re-Planning" below, one at a time.
- **Done for now** ends the flow; every approved story is already marked ready.

---

## Cohesion Check Heuristics

The cohesion check (the comparison at the end of Batch Planning step 7) uses these heuristics to detect cross-story conflicts.

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

If no item is a BT-2 or BT-3 item (no `ask` row, no low-confidence decision in a summary without a Product-stake column, no low- or medium-confidence concern, no blocker, no Not Covered row a user would see, no design check marked concern or invalid, no Cycle Impact row that is not none):

1. BT-1 reports: "Planned [N] stories successfully. No items need review - agents were confident across the board."
2. Skip BT-2 and BT-3 entirely; the settled list heads the BT-5 presentation
3. Proceed to BT-4 (cohesion check still runs — file overlap isn't about confidence)
4. BT-5 uses batch approval fast path if 5+ stories

### Single Story in Batch Mode

If `MODE: batch` is passed but only one story has `status: planning`:

- Batch Planning step 1 detects this and plans it as a single story (S-1 through S-6), with no batch overhead
- Batch triage is never reached

### Many Stories (8+)

User fatigue risk is real with 8+ stories. Mitigations built into the flow:

- BT-3 asks one card per medium-confidence concern; these are usually fewer than BT-2 items, and each carries the agent's pick
- BT-5 batch approval fast path (for clean batches) reduces to one interaction
- BT-2 groups needs-review items by story (mental context stays coherent)
- If the batch is fully clean (all informational, no cohesion issues), the user sees: BT-1 overview → BT-5 batch approve → BT-7 next steps. Three interactions total.

### Adjusted Story Re-Planning

When a story is marked "Adjust" in BT-5:

1. User feedback is collected immediately via the "What should change?" AskUserQuestion (see BT-5 Adjust Feedback template above)
2. The story is queued for re-planning AFTER the batch triage completes
3. Re-planning uses the single-story path (S-1 through S-6)
4. The user's feedback from step 1 is included as `APPROACH:` context in the agent prompt — e.g., `APPROACH: User wants fewer chunks, plan is over-scoped`
5. Previous triage decisions (from BT-2/BT-3/BT-4) that apply to this story are included as BINDING constraints, not just don't-re-ask context — those answers already landed in the story file at answer time and were receipted to the user; the re-planning agent must preserve them in the new plan or flag a conflict in its concerns summary, never silently drop a receipted answer
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

1. **The Pitch** - the sell plus the conditions table, every condition tagged `verified`, `system-owned` or `unverifiable - becomes Chunk N's first test`. It sits right after `## Spark`.

2. **Acceptance** - from the agent's plan plus any additions from triage. Specific, checkable criteria.

3. **Chunks** - **keep the agent's chunks exactly as written. Do NOT summarize.** Each chunk has what `chunk-format-guide.md` shows:
   - **Goal:** the one outcome the chunk delivers
   - **Files:** one line per file, `` `path` - create ``, `modify` or `read-only`
   - **Contracts:** each with its source in a few words (`checked: ...`, `new`, or `from Chunk N`); a binding table row ends in its `[visual-source: ...]` receipt. The implementer matches these exactly.
   - **Not covered:** optional; a risk the plan leaves open on purpose, with its reason
   - **Approach:** optional advice in prose
   - **Test cases:** each named for a behavior and what it proves
   - **Run:** the commands that show the chunk left the project building and tested
   - **Done When:** checkable items, including that every Run command passes

   A chunk that changes only docs or prompts needs no Test cases or Run. Batch plans are held to the same depth as single-story plans.

   With concrete adjustments from triage:
   - **BT-2 decisions:** Find the chunk(s) affected by the resolved concern. Replace the agent's tentative approach with the user's chosen approach in the chunk description. Example: if the agent planned "use modal for confirmation (tentative)" and the user chose "use inline confirmation," update the chunk text to say "use inline confirmation."
   - **BT-4 cohesion resolutions:** Add a `**Coordination:**` line to the affected chunk. Format: `**Coordination:** [file] is also modified by [other story] — [resolution, e.g., "this story owns the validation logic, Login story imports it"].` The implementer agent reads this and accounts for it.

4. **Frontmatter updates:**
   ```yaml
   status: ready        # was: planning
   chunks_total: [N]    # the number of chunks in the plan
   updated: [YYYY-MM-DD]
   ```

**Never touch `## Reference Materials`.** Edit the sections listed above in place. If the file is written whole, copy `## Reference Materials` over verbatim, including any `**Tracker context (copied from <KEY>):**` group.

### Status Script

After writing each story file:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-story-status.sh [story-file-path] ready
```

This updates `.state` tracking and any hook-managed state.

### Write Order

Stories are written in story_number order (same as implementation order). This ensures `.state` progression is clean and any cross-story references are consistent.
