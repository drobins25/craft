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
  PLUGIN_ROOT: [resolved ${CLAUDE_PLUGIN_ROOT} - the agent cannot expand it]
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

Read `${CLAUDE_PLUGIN_ROOT}/commands/references/analysis-bug-filing.md` and follow it inline, with `found_during` = `craft cycle-complete walkthrough: <title>`. `<title>` is the title in `$cycle_dir/cycle.yaml`, falling back to the cycle directory name when the title is missing.

Print the reference's report-back line (or "Walkthrough clean." when nothing was found) and remember how many bugs were filed for Step 5. Filing never pauses the run. Proceed to Step 3.

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

First, turn autonomous mode off. An unattended run ends with its cycle, and Step 3c was the last step that reads the mode. In an attended run it is already off and this changes nothing:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh RUN_MODE ""
```

> "**Cycle Complete: [Name]**
>
> **Stories:** [N] completed, [M] returned to backlog
> **Duration:** [start] → [end]
> Bugs filed: <N> (include this line only when the walkthrough filed any)
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
- **The walkthrough files bugs and never fixes; bug then /craft:adhoc is the fix path.**
