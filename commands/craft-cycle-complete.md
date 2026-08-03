---
name: cycle-complete
description: "Complete a cycle. Triggers reflection if pending learnings, then archives."
---

# Cycle Complete

Complete and archive a cycle. Ensures learnings are reflected before archiving.

## When to Use

- All stories in the cycle are complete
- User explicitly ends cycle early
- Cycle has been abandoned and needs archival

## Flow

### Step 1: Verify Cycle State

Set `cycle_dir` to `.craft/cycles/${ACTIVE_CYCLE}`.

Use **Grep** with pattern `^status: complete`, path `$cycle_dir/stories/`, glob `*.md`, output_mode `files_with_matches` → count results → `stories_complete`.

Use **Glob** with pattern `$cycle_dir/stories/*.md` → count results → `stories_total`.

**If stories incomplete:**
Use **AskUserQuestion**:
```yaml
question: "[N] of [M] stories complete. End cycle anyway?"
header: "Cycle"
options:
  - label: "Complete cycle"
    description: "Archive incomplete stories to backlog"
  - label: "Continue working"
    description: "Finish remaining stories first"
```

---

### Step 2: Check for Pending Learnings & Ungraduated Fixes

Use **Grep** with pattern `status: pending`, path `.craft/.learnings.yaml`, output_mode `count` → `pending_count`. If file doesn't exist, `pending_count = 0`.

Also count ungraduated fix records and the rule-pass threshold:

```bash
FIX_COUNT=$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/count-ungraduated-fixes.sh")
THRESHOLD=$(grep -m1 '^rule_pass_threshold:' "${CRAFT_PROJECT_ROOT:-.}/.craft/settings.yaml" 2>/dev/null | sed 's/^rule_pass_threshold:[[:space:]]*//')
THRESHOLD=${THRESHOLD:-10}
```

**If `pending_count > 0` OR `FIX_COUNT >= THRESHOLD`:**

Name the reason(s) that apply:

> "There are [N] pending learnings that haven't been converted to harness yet."
> "[FIX_COUNT] fixes have accumulated since the last rule pass - reflect can mine them for graduation-worthy rules."
>
> "Reflect before archiving?"

Use **AskUserQuestion**:
```yaml
question: "Reflect before archiving?"
header: "Reflect"
options:
  - label: "Yes, reflect now"
    description: "Run /craft:reflect (learnings drain and/or rule pass), then archive"
  - label: "Skip reflection"
    description: "Keep everything pending, just archive cycle"
```

**If "Yes, reflect now":** Run `/craft:reflect`, then continue to Step 3. Reflect owns the rule-pass offer - this step only routes into it, never presents the pass itself.

**If "Skip reflection":** Learnings remain in `.craft/.learnings.yaml` with `status: pending` and the fix watermark is untouched — both will be available for the next reflection.

---

### Step 2b: Walkthrough Check (UI Cycles)

Check if the cycle has UI stories that should be walked through before archiving.

Use **Grep** with pattern `^type: ui`, path `$cycle_dir/stories/`, glob `*.md`, output_mode `files_with_matches` → count → `ui_stories`.

**If ui_stories > 0:**

> "This cycle has [N] UI stories. Running a walkthrough to check the live experience before archiving."

**Assemble the walkthrough brief** from what the orchestrator already knows:

1. **Dev server**: Read `project.md` for `package_manager` and dev scripts. Build the start command (e.g., `npm run dev`). Check common ports (5173, 3000, 8080) or parse from project config.
2. **URL**: Infer from project type. Static HTML → `file://` path or localhost. Next.js → `localhost:3000`. Vite → `localhost:5173`. Check project.md for hints.
3. **Test plan**: For each `type: ui` story, read the story file and extract:
   - Feature name (from title)
   - How to trigger it (from acceptance criteria or spark - e.g., "click Command 1 button")
   - What should happen (from acceptance criteria - e.g., "recipe card appears with image and ingredients")
4. **Story context**: Include each UI story's spark (1-2 sentences) so the agent understands what was built.

**Pass the brief to the walkthrough-analyzer agent via Task:**

```
Brief:
  Dev server: [command to start, e.g., "npm run dev"]
  URL: [e.g., "http://localhost:5173"]

  Test plan:
    1. [Feature name]
       Trigger: [how to activate it]
       Expected: [what should happen]
    2. [Feature name]
       Trigger: [how to activate it]
       Expected: [what should happen]
    ...

  Story context:
    - [Story 1 title]: [spark]
    - [Story 2 title]: [spark]
```

**After the walkthrough agent returns:**

Write findings to `.craft/analysis/pending/walkthrough.yaml` using the template format.

**If blocks-ship findings > 0:**

Use **AskUserQuestion**:
```yaml
question: "Walkthrough found [N] blocks-ship issues. Review before completing?"
header: "Walkthrough"
options:
  - label: "Review findings now"
    description: "See what was found before archiving"
  - label: "Complete anyway"
    description: "Archive the cycle, fix issues later"
  - label: "Fix first"
    description: "Don't complete yet - fix the issues"
```

If "Review findings now" → Show findings inline (severity-ranked), then re-ask complete/fix.
If "Complete anyway" → Continue to Step 3.
If "Fix first" → Run the **Walkthrough Fix Loop** below.

**If no blocks-ship findings but looks-wrong or feels-off findings exist:**

> "Walkthrough found [N] minor findings (no blockers). Continuing to archive.
> Findings saved to `.craft/analysis/pending/walkthrough.yaml` for review."

Proceed to Step 3.

**If no findings at all:**

> "Walkthrough clean. Continuing to archive."

Proceed to Step 3.

---

### Walkthrough Fix Loop

**CRITICAL: Do NOT create a new cycle.** The current cycle stays active. Fix stories go into the SAME cycle directory (`$cycle_dir/stories/`). The cycle is not complete until it passes the walkthrough clean. This is part of cycle completion, not a new piece of work.

Walkthrough findings come in two complexity levels. Handle each differently:

**Step F1: Apply quick fixes (complexity: quick-fix)**

Quick fixes are trivial edits - CSS properties, missing attributes, wrong values. The walkthrough agent provides a `fix_hint` for each one.

For each `quick-fix` finding (any severity):

1. Create a checkpoint: `create-checkpoint.sh "[cycle-name]" "walkthrough-fixes"`
   (One checkpoint for all quick fixes - they're batched.)
2. Use the `fix_hint` to locate and edit the file directly. Use Grep to find the element/class mentioned in the hint, then use Edit to make the change.
3. Run build/lint validation (synchronous) to confirm the edit doesn't break anything.
4. Update the finding in `walkthrough.yaml`: `status: fixed`

> "Applied [N] quick fixes:
> - walk-001: Added padding-bottom to recipe card
> - walk-003: Set overflow hidden on command panel
>
> Validated: build passes."

**No story file created for quick fixes.** The checkpoint captures the changes. The walkthrough.yaml records what was fixed and why.

**Step F2: Create and implement story fixes (complexity: story-fix)**

Story fixes need the implementer - they involve logic changes, multiple files, or design decisions.

For each `story-fix` finding with severity `blocks-ship` or `looks-wrong`:

1. Create a single-chunk story in the **current cycle** (NOT a new cycle):

```bash
# Next number = highest existing filename prefix + 1 (never file count + 1 -
# a gap from an archived story makes count+1 collide with an existing number)
max=$(ls "$cycle_dir/stories/" 2>/dev/null | grep -o '^[0-9]*' | sed 's/^0*//' | sort -n | tail -1)
next_num=$(( ${max:-0} + 1 ))
```

Write to `$cycle_dir/stories/[N]-fix-[slug].md`:

```markdown
---
name: fix-[slug]
title: "Fix: [finding title]"
type: ui
status: ready
priority: high
created: [date]
updated: [date]
cycle: [cycle-name]
story_number: [N]
chunks_total: 1
chunks_complete: 0
current_chunk: 0
source: walkthrough
finding_id: [walk-NNN]
---

# Story: Fix: [finding title]

## Spark
[Finding description: element, what happened, what should happen instead]

## Acceptance
- [ ] [Expected behavior from finding]
- [ ] Walkthrough re-test confirms fix

## Chunks

### Chunk 1: [Fix description]
**Files:** [inferred from element/context]
**What:** [specific fix based on expected vs actual]
**Acceptance:** Same as story acceptance above
```

2. Implement each story fix via the standard loop:
   - `create-checkpoint.sh [story] [chunk]`
   - Invoke implementer agent via Task
   - Invoke `craft:validate-chunk` via Skill
   - On pass: `complete-chunk.sh` → `complete-story.sh`

Story fixes with severity `feels-off` or `nitpick` stay in `walkthrough.yaml` as `status: pending` for the user to review later via `/craft:analyze walkthrough`. They do not block cycle completion.

> "Implemented [N] story fixes in current cycle:
> - fix-toggle-repress: Added toggle behavior to command buttons
>
> [M] minor findings saved for later review."

**Step F3: Re-run walkthrough**

After all fixes (quick and story) are applied:

> "All fixes applied. Re-running walkthrough to verify."

Re-run the walkthrough-analyzer with the same brief. Check:
1. Are the original blocks-ship/looks-wrong findings resolved?
2. Did the fixes introduce any new issues?

**If new blocks-ship findings appear:**

Use **AskUserQuestion**:
```yaml
question: "Re-walkthrough found [N] new issues. Another fix pass?"
header: "Walkthrough"
options:
  - label: "Fix again"
    description: "Apply fixes and re-test"
  - label: "Complete anyway"
    description: "Archive the cycle, address remaining issues later"
```

If "Fix again" → Loop back to Step F1 with the new findings.
If "Complete anyway" → Continue to Step 3.

**If a finding persists after the same issue was fixed in a previous pass:**

Track fix attempts per finding ID. If the same finding (or same element + same symptom) appears after 2 fix attempts, trigger the **failed-fix escalation**:

> "Finding [walk-NNN] has persisted through 2 fix attempts. Escalating with fresh context."

**Failed-fix escalation protocol:**

1. **Stop the current approach.** Do not retry the same fix or variation.

2. **Distill the root cause.** Read the original finding, the fix attempts that were made (from checkpoints/story files), and the re-walkthrough results. Write a concise root cause analysis:
   - What the symptom is (from walkthrough)
   - What was tried (from fix stories)
   - Why it didn't work (from re-walkthrough)
   - What the actual root cause likely is

3. **Spawn a fresh implementer agent** with ONLY the distilled spec - no fix history, no previous attempts, no accumulated context. The prompt should be:

   ```
   Fix this UI issue. This is a fresh attempt - previous approaches failed.

   SYMPTOM: [exact walkthrough finding - element, expected, actual, dimensions]
   ROOT CAUSE: [distilled analysis from step 2]
   DO NOT: [specific approaches that were tried and failed]
   FILES: [relevant files from the project]
   ```

   The fresh agent sees the problem without the cognitive anchoring of previous failed attempts. This is deliberate - context pollution from failed fixes often prevents seeing the real cause.

4. After the fresh agent completes, re-run walkthrough to verify.

5. If it STILL persists after the escalated fix, stop and ask the user:

   ```yaml
   question: "Finding [walk-NNN] persists after escalated fix. What should we do?"
   header: "Stuck"
   options:
     - label: "I'll fix it manually"
       description: "Skip this finding, complete the cycle"
     - label: "Show me the details"
       description: "Display root cause analysis so I can guide the fix"
   ```

**If all original findings are resolved and no new blocks-ship:**

> "All walkthrough issues resolved. Continuing to archive."

Proceed to Step 3.

---

### Step 3: Handle Incomplete Stories

If cycle ends with incomplete stories, move them back to backlog:

Use **Grep** with pattern `^status: (ready|active)`, path `$cycle_dir/stories/`, glob `*.md`, output_mode `files_with_matches` → list of incomplete story files.

For each incomplete story file:
```bash
mv "$story" .craft/backlog/
```

Note in cycle.yaml:
```markdown
## Incomplete Stories

The following stories were returned to backlog:
- story-name-1 (0/3 chunks)
- story-name-2 (1/4 chunks)
```

---

### Step 3c: Surface Unread Observations

Before archiving, surface any unread implementer observations for this cycle - cycle-complete is a human-step-in moment. This must run BEFORE Step 4 (Archive), while `ACTIVE_CYCLE` is still set (complete-cycle.sh clears it).

- **If `RUN_MODE == autonomous`:** skip - leave observations in their sidecars to accumulate; do not surface, route, or create a todo unattended.
- **Otherwise:** recompute the count:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/observations-count.sh ".craft/cycles/$ACTIVE_CYCLE"
  ```
  If it prints a non-empty `N unread / M stories`, **Read `${CLAUDE_PLUGIN_ROOT}/commands/references/observations-surfacing.md` and run it inline** (cluster -> prose digest -> route each cluster to the user's choice -> mark surfaced LAST). If empty, say nothing and continue to Step 4.

---

### Step 4: Archive Cycle

**Run the transition script:**
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/complete-cycle.sh
```

This updates:
- Cycle: `CYCLE_STATUS = complete`, `CURRENT_STORY` cleared
- cycle.yaml: `status: complete`, `updated: [date]`
- Global: `ACTIVE_CYCLE` cleared, `CURRENT_STORY` cleared

---

### Step 5: Cycle Complete Summary

> "**Cycle Complete: [Name]**
>
> **Stories:** [N] completed, [M] returned to backlog
> **Duration:** [start] → [end]
>
> **What's next?"

Use **AskUserQuestion**:
```yaml
question: "Cycle complete. What's next?"
header: "Next"
options:
  - label: "Start new cycle"
    description: "Create cycle from backlog or new work"
  - label: "Review backlog"
    description: "See what's queued up"
  - label: "Take a break"
    description: "Done for now"
```

---

## Remember

- **Reflect before archive** — prompt to convert learnings first
- **Learnings persist** — pending learnings stay in `.craft/.learnings.yaml` even if skipped
- **Incomplete stories return to backlog** — nothing gets lost
- **Cycle archival is just state change** — learning conversion is reflect's job
