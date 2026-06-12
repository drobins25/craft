---
name: craft:story-implement
description: "Implement a story through the Implement Phase. Stories must be fully designed with chunks before implementation."
argument-hint: "[story-name]"
---

# Story Implement

⛔ **CRITICAL: YOU ARE THE ORCHESTRATOR, NOT THE IMPLEMENTER**

You must NOT write implementation code directly. For EVERY chunk, you MUST use the Task tool to invoke the implementer agent:

```
Task tool:
  subagent_type: "craft:implementer"
  description: "Implement chunk N of [story]"
  prompt: [chunk details, story context, TDD requirement]
```

If you find yourself about to write code → STOP → use Task tool instead.

---

⛔ **CRITICAL: VALIDATION CHAIN IS INLINE**

Do NOT invoke the validate-chunk skill (`craft:validate-chunk`) during the implementation loop. The validate-chunk skill exists for manual user invocation only. story-implement owns the validation chain directly:
- Invoke chunk-validator agent via Task tool
- Route PASSED/PARTIAL inline
- Route FAILED via Read [references/validate-fix-loop.md](references/validate-fix-loop.md)

---

⛔ **CRITICAL: ALL VALIDATION RUNS SYNCHRONOUSLY**

**NEVER** use `run_in_background: true` for test, typecheck, lint, or build commands. All validation must complete synchronously — results confirmed before marking any chunk or story done. This applies to:
- Per-chunk validation (Step 4)
- Quality gates (Step 5)
- Any "verify nothing broke" test runs

Background test runs cause orphaned failure notifications that appear after stories are already marked complete. If a command is slow, wait for it.

---

Implement a story that's already been designed. This is pure Implement Phase — chunks exist, decisions are locked, just execute.

## Project Root

All `.craft/` paths in this command are relative to `$CRAFT_PROJECT_ROOT` (set at session start). Use `${CRAFT_PROJECT_ROOT:-.}` as prefix when constructing paths. Pass the project root to all subagents.

## Prerequisites & Status Guards

Before implementation, **validate story location and status**:

**Location check:**
- If story is in `.craft/backlog/` → BLOCK:

Use **AskUserQuestion**:
```
question: "This story is in the backlog. Assign it to a cycle first?"
header: "Assign"
options:
  - label: "Assign to [active cycle] (Recommended)"
    description: "Add to current cycle and implement"
  - label: "Create new cycle for it"
    description: "Start a new cycle with this story"
  - label: "Cancel"
    description: "Go back"
```

If no `ACTIVE_CYCLE` exists: omit the "Assign to [active cycle]" option. Only show "Create new cycle" and "Cancel".

**If user selects "Assign to [active cycle]":**
→ invoke `craft:craft-cycle-assign` with the story path. After assignment completes, return to story-implement for the same story.

**If user selects "Create new cycle for it":**
→ invoke `craft:craft-cycle-design` with the story as context. After cycle creation completes, invoke `craft:craft-cycle-start` to activate the new cycle, then return to story-implement for the same story.

**If user selects "Cancel":**
→ end, do not proceed

**Cycle check:**
- Extract the cycle name from the story path (e.g., `.craft/cycles/[cycle-name]/stories/[story].md` → `[cycle-name]`)
- Read `ACTIVE_CYCLE` from `.global-state`
- If story is in a cycle AND that cycle is NOT the current `ACTIVE_CYCLE`:
  → BLOCK: Do NOT proceed. Do NOT attempt to manually activate the cycle by editing state files.
  → Route to `craft:cycle-start` to properly activate the cycle first.

Use **AskUserQuestion**:
```
question: "This story is in cycle '[cycle-name]' which isn't the active cycle. Activate it first?"
header: "Cycle"
options:
  - label: "Activate [cycle-name] (Recommended)"
    description: "Use craft:cycle-start to properly activate this cycle"
  - label: "Pick a story from the active cycle"
    description: "Choose a story from [ACTIVE_CYCLE] instead"
  - label: "Cancel"
    description: "Go back"
```

⛔ **NEVER manually edit `.global-state` or `.state` files to activate a cycle.** Always use `craft:cycle-start` which runs the proper transition scripts (`start-cycle.sh`), updates cycle.yaml status, and handles the active cycle switch cleanly.

If user selects "Activate": invoke `craft:cycle-start` with the cycle name. After activation completes, return to story-implement for the original story.

If user selects "Pick a story from the active cycle": → invoke `craft:craft-story-implement` with no args (triggers Step 1 story picker filtered to active cycle)

If user selects "Cancel": → end, do not proceed

**Status check:**

| Status | Action |
|--------|--------|
| `ready` | OK: Proceed to implementation |
| `active` | OK: Resume from current chunk |
| `complete` | BLOCK: "Story already complete. Pick another?" |

**Also check story has:**
- Chunks defined (from plan-chunks)
- Acceptance criteria

**If story is missing chunks:**
Use **AskUserQuestion**:
```
question: "This story doesn't have chunks planned. How do you want to proceed?"
header: "Plan"
options:
  - label: "Design it now (Creative Phase)"
    description: "Explore options, then plan chunks"
  - label: "Plan chunks directly (skip creative-spark)"
    description: "I know what I want, just break it down"
  - label: "Pick a different story"
    description: "Choose another story to implement"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their preferred approach.

**If user selects "Design it now (Creative Phase)":**
→ invoke `craft:craft-story-new` with args "[story path] — Existing story needs creative exploration. SKIP_STEP_1: true USER_PREFERS: creative"
After story-new completes (story will have chunks), return to story-implement for the same story.

**If user selects "Plan chunks directly (skip creative-spark)":**
→ invoke `craft:plan-chunks` with args "[story path]"
After plan-chunks completes (story will have chunks, status: ready), return to story-implement for the same story.

**If user selects "Pick a different story":**
→ invoke `craft:craft-story-implement` with no args (triggers Step 1 story picker)

## Flow

### Step 1: Select Story

If no story specified:

> "Which story do you want to implement?"

Use **AskUserQuestion** (options based on available stories):
```
question: "Which story do you want to implement?"
header: "Story"
options:
  - label: "[Story 1] (in cycle)"
    description: "ready, 4 chunks"
  - label: "[Story 2] (in cycle)"
    description: "ready, 3 chunks"
  - label: "[Story 3] (backlog)"
    description: "ready, 5 chunks — will need cycle assignment"
```

**Note:** Prioritize cycle stories over backlog stories in the options.

**If user provides custom text:** Ask a clarifying AskUserQuestion to confirm which story.

If story specified: proceed directly.

### Step 2: Check Story State

Read the story file and determine state:

**If status = `ready` or `active`:**
> Proceed to implementation

### Step 3: Review Before Starting

> "Ready to implement **[Story Name]**
>
> **Chunks:** [N] total
> **Decisions locked:**
> - [Decision 1]
> - [Decision 2]
>
> **Acceptance criteria:**
> - [ ] [Criterion 1]
> - [ ] [Criterion 2]
>
> Start with Chunk 1?"

### Step 3a: Detect Package Manager

Before test infrastructure check, ensure we know which package manager to use:

```
# 1. Check project.md for documented package manager
Read .craft/project.md → parse package_manager from frontmatter → PM

# 2. If not documented, auto-detect from lockfiles
if PM is empty:
  Glob "pnpm-lock.yaml" → if found: PM = "pnpm"
  else Glob "yarn.lock" → if found: PM = "yarn"
  else Glob "bun.lockb" → if found: PM = "bun"
  else Glob "package-lock.json" → if found: PM = "npm"
```

**If PM still unknown:**

Use **AskUserQuestion**:
```yaml
question: "Which package manager does this project use?"
header: "Package Manager"
options:
  - label: "pnpm"
    description: "Fast, disk-efficient package manager"
  - label: "npm"
    description: "Node's default package manager"
  - label: "yarn"
    description: "Facebook's package manager"
  - label: "bun"
    description: "Fast all-in-one JavaScript runtime"
```

**After detection/selection, save to project.md** (if not already there):

Use **Grep** with pattern `^package_manager:`, path `.craft/project.md`, output_mode `count`. If count is 0, use the **Edit** tool to add `package_manager: [PM]` to the frontmatter.

This ensures all subsequent commands use the correct package manager.

### Step 3b: Verify Test Infrastructure

Before starting implementation, verify test infrastructure exists:

Use **Glob** with pattern `{jest,vitest}.config.{js,ts}` to check for test config files.

Use **Grep** with pattern `vitest|jest`, path `package.json`, output_mode `count` to check for test dependencies.

If no config files found AND no test dependencies → "No test infrastructure detected".

**If test infrastructure missing:**

> "This project doesn't have test infrastructure set up. TDD is required for quality.
>
> Set up testing now?"

Use **AskUserQuestion**:
```yaml
question: "Set up test infrastructure?"
header: "Tests"
options:
  - label: "Yes, set up Vitest (Recommended)"
    description: "Fast, modern test runner for Vite projects"
  - label: "Yes, set up Jest"
    description: "Traditional test runner, wide ecosystem"
  - label: "I'll set it up manually"
    description: "Pause implementation until tests are ready"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their preference.

**If "Yes, set up Vitest":**

```bash
$PM install -D vitest @testing-library/react @testing-library/jest-dom @testing-library/user-event jsdom
```

Create `vitest.config.ts`:
```typescript
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./test/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
    },
  },
})
```

Create `test/setup.ts`:
```typescript
import '@testing-library/jest-dom'
```

Add to `package.json` scripts:
```json
{
  "scripts": {
    "test": "vitest",
    "test:coverage": "vitest --coverage"
  }
}
```

**Then proceed with implementation.**

**If "Yes, set up Jest":**

```bash
$PM install -D jest @testing-library/react @testing-library/jest-dom @testing-library/user-event jest-environment-jsdom ts-jest @types/jest
```

Create `jest.config.ts`:
```typescript
import type { Config } from 'jest'

const config: Config = {
  testEnvironment: 'jsdom',
  transform: { '^.+\\.tsx?$': 'ts-jest' },
  setupFilesAfterSetup: ['<rootDir>/test/setup.ts'],
}

export default config
```

Create `test/setup.ts`:
```typescript
import '@testing-library/jest-dom'
```

Add to `package.json` scripts:
```json
{
  "scripts": {
    "test": "jest",
    "test:coverage": "jest --coverage"
  }
}
```

**Then proceed with implementation.**

**If "I'll set it up manually":**
→ BLOCK: "Implementation paused. Run /craft:story-implement again after test infrastructure is set up."
→ end, do not proceed

**"Skip tests" is NEVER an option.**

### Step 3c: Initialize Story State

**When user confirms, run the transition script:**
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/start-story.sh .craft/cycles/[cycle]/stories/[story].md
```

This updates:
- Global: `CURRENT_STORY` set
- Cycle: `CURRENT_STORY`, `CURRENT_CHUNK=1`, `TOTAL_CHUNKS` set
- Story: `status = active`

### Step 4: Implementation Loop

**Incremental learnings tracking:**
Track learnings during implementation. **Write to `.craft/.learnings.yaml` after each chunk** (not at story end).
This ensures learnings survive context compaction, which can happen mid-story during big cycles.

**Learning types to watch for:**

| Type | Detection Trigger | Example |
|------|-------------------|---------|
| Convention | "We use X", "In this project" | "We use Zustand for state" |
| Enforcement | "Always X", "Never Y", same correction twice | "Never use any type" |
| Behavior | "Don't skip", "Don't assume", frustrated correction | "Don't skip existing code" |
| Automation | "Run X after Y", repeated manual step | "Run prettier after editing" |
| Skill | Detailed explanation, same pattern 3+ times | "Here's how we do forms..." |
| Workflow | Repeated multi-step sequence | Create component → add export → add test |

**Signal vs Noise filter — before capturing, ask:**
1. Generalizable? (applies beyond this one spot)
2. Recurring? (happened before or will again)
3. Project-specific? (convention for THIS codebase)
4. Actionable? (can write a clear rule/skill)

If any answer is "no" → acknowledge and move on, don't capture.

For each chunk:

---

**>>> CONTINUATION CHECKPOINT — CHUNK [current]/[total]**

You are the **craft-story-implement orchestrator**. You are executing the Step 4 implementation loop. Your job is to cycle through chunks: checkpoint → implement → validate → next chunk. If you just returned from validate-chunk, test-fix, or refine-chunk — you are HERE. Read the `>>> NEXT ACTION:` from the skill output and execute it. If the action says "invoke implementer for chunk N+1", proceed to step 1 below for that chunk. If the action says "proceed to Step 5", go to Step 5 below.

**Do NOT stop. Do NOT end the conversation. The story is not done until Step 5 completes.**

**Restore REFINE_COUNT from disk (compaction recovery):**
```bash
CHUNK_STATE="${CRAFT_PROJECT_ROOT:-.}/.craft/.chunk-state"
if [ -f "$CHUNK_STATE" ]; then
  source "$CHUNK_STATE"
  if [ "$REFINE_CHUNK" != "[current_chunk_number]" ]; then
    REFINE_COUNT=0
  fi
  # Note: If REFINE_COUNT was restored, this chunk previously had validation failures.
  # The validate-fix-loop will use this count for escalation decisions.
fi
```

---

1. **Checkpoint & Snapshot**
   ```bash
   CHECKPOINT_FILE=$(bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/create-checkpoint.sh \
     "[story-name]" [chunk_number] ".craft/cycles/[cycle]" "${CRAFT_PROJECT_ROOT:-.}")
   ```
   This creates a state snapshot at `.craft/checkpoints/[story]-chunk-[N].yaml`
   (no git commit — commits happen at story completion). Remember the checkpoint
   path for potential salvage use.

2. **Implement the Chunk — MANDATORY AGENT INVOCATION**

   ⛔ **YOU MUST USE THE TASK TOOL TO INVOKE THE `implementer` AGENT.**

   Do NOT implement the chunk yourself. Do NOT write code directly.

   **Use the Task tool with these parameters:**
   ```
   subagent_type: "craft:implementer"
   description: "Implement chunk N of [story name]"
   prompt: [Include ALL context below]
   ```

   **Required context in the prompt (use canonical field names from Context Passing Standard):**
   - **STORY_FILE:** Absolute path to the story `.md` file (the implementer reads its own chunk from this)
   - **CHUNK:** Chunk number only (e.g., `3`) - the implementer extracts the chunk spec from the story file
   - **STORY:** Story name and key decisions from the story's Spark/Scope/Notes sections
   - **PROJECT_ROOT:** `$CRAFT_PROJECT_ROOT` (so the implementer scopes all work to this project)
   - **TDD REQUIREMENT: Tests MUST be written FIRST, run and fail, THEN implementation**
   - **PM:** Package manager to use
   - **NO BACKGROUND COMMANDS:** NEVER use `run_in_background: true` for test, typecheck, lint, or build commands. All validation must run synchronously. Background runs become orphaned and spam the conversation.

   **Do NOT paste chunk content (goal, files, contracts, approach) into the prompt.**
   The implementer reads its chunk spec directly from the story file on disk. This ensures
   the spec is always authoritative - even after orchestrator context compaction.

   **Do NOT paste project.md, tokens.yaml, or locked.md content into the prompt.**
   The implementer reads these files from disk itself. Pasting them duplicates context
   and bloats the orchestrator's conversation across multiple chunks.

   **Example Task invocation:**
   ```
   Task tool:
     subagent_type: "craft:implementer"
     description: "Implement chunk 2 of login-flow"
     prompt: "Implement chunk 2 of the login-flow story.

     STORY_FILE: /path/to/project/.craft/cycles/1-auth/stories/2-magic-link.md
     CHUNK: 2

     Story decisions: 5-minute expiry, use existing email service

     PROJECT_ROOT: /path/to/project/
     PM: pnpm

     TDD REQUIRED:
     - Write tests FIRST in `__tests__/` directories
     - Run tests and verify they FAIL
     - THEN write implementation
     - Run tests and verify they PASS

     NO BACKGROUND COMMANDS: NEVER use run_in_background for test/typecheck/lint/build. Run all validation synchronously."
   ```

   **If you skip this step and implement directly, you are violating the craft workflow.**

   **After agent completes — capture usage:**
   The Task tool response includes `total_tokens`, `tool_uses`, and `duration_ms`. Run:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/track-usage.sh \
     ".craft/cycles/[cycle]/stories/[story].md" \
     [chunk_number] "implementer" [total_tokens] [tool_uses] [duration_ms]
   ```
   **Note:** If the agent reports "failed" due to `classifyHandoffIfNeeded` error, this is a known Claude Code bug — the work likely completed. Check the target files before assuming failure.

   **Contract Mismatch routing:**

   If the implementer's output contains `## CONTRACT MISMATCH` instead of a completion report, the PLAN — not the code — is wrong. Do NOT route to refine-chunk or test-fix (those fix code; this is a plan defect). Do NOT re-invoke the implementer to "make it work." A pulled tripwire is a caught planning bug — treat the report as a deliverable.

   1. **Persist the report first**: write it verbatim to `.craft/checkpoints/[story]-chunk-[N]-mismatch.md`. The implementer's work state must survive the user-question gap and any session restart — orchestrator context is not durable. Then read it: contract, reality, reasoning impact, proposed amendment, work state.
   2. **Interactive (default):** Surface via **AskUserQuestion**. The question text carries the contract-vs-reality delta and the reasoning impact (self-contained — the user judges from the dialog alone). Options: "Amend: [proposed amendment]" / "Different amendment" (discuss, then amend) / "Halt story" (replan needed).
   3. **Autonomous (RUN_MODE=autonomous):** Do not guess. Park the story: emit a `contract_mismatch` event via append-event.sh, leave the story `active` at the current chunk, note it for the run summary, and continue to the next ready story. A graceful pause beats an unsupervised contract rewrite at 2am.
   4. **On approved amendment, YOU make the edit — never the implementer.** Edit the story file: update the contract line AND append an `**Amendments:**` entry to the chunk (date, what changed, what the original receipt missed). The plan artifact belongs to planning; an implementer that can amend the contract it tripped over has no tripwire at all.
   5. **Resume the SAME implementer via SendMessage** — it holds the chunk context and a green work state: "Amendment approved and recorded — the contract now reads [X]. Continue from your work state." Only if that agent is no longer reachable (session restart, compaction, or SendMessage unavailable in this environment): re-invoke a fresh implementer using the partial-chunk resume prompt from Resume Support, and include the persisted mismatch report (`.craft/checkpoints/[story]-chunk-[N]-mismatch.md`) in its prompt — a fresh agent has no other access to the prior work state.
   6. **If "Halt story":** stop, leave the story `active`, report. The user decides whether to replan.

3. **Validate the Chunk**

   Invoke the chunk-validator agent directly. Do NOT invoke the validate-chunk skill here - the skill is for manual use only. The command owns the validation chain.

   **Assemble FILES_CHANGED from git state:**

   After the implementer returns, compute the actual files changed using git. Run these two commands via Bash:

   ```bash
   cd ${CRAFT_PROJECT_ROOT:-.} && git diff --name-only HEAD
   ```

   ```bash
   cd ${CRAFT_PROJECT_ROOT:-.} && git ls-files --others --exclude-standard
   ```

   The first command captures all modified tracked files since the last commit. The second captures new untracked files (excluding gitignored files). Together they represent everything the implementer actually touched - including test files, index exports, and utility extractions that aren't in the chunk spec.

   **Union with spec files:** Read the current chunk's `**Files:**` section from the story file. Each line is formatted as `` `path` - action ``. Extract the file path from each line (strip backticks, take the portion before ` - `). Add any spec-listed files that aren't already in the git output. This ensures the validator checks files the implementer was supposed to touch but didn't modify.

   **Format:** Combine all paths into a single comma-separated string. Use project-relative paths (strip `${CRAFT_PROJECT_ROOT}` prefix if present). This becomes the FILES_CHANGED value below.

   **If both git commands return empty AND no spec files exist:** Set FILES_CHANGED to empty string. The chunk-validator will SKIP file-scoped checks when FILES_CHANGED is empty.

   **Invoke chunk-validator via Task tool:**
   ```
   Task tool:
     subagent_type: "craft:chunk-validator"
     model: "haiku"
     description: "Validate chunk [CHUNK]"
     prompt: "Run validation checks on this project.

       CHUNK: [N]/[total]: [chunk title]
       FILES_CHANGED: [computed FILES_CHANGED from git diff + spec union above]
       PROJECT_ROOT: ${CRAFT_PROJECT_ROOT:-.}
       PM: [package manager]
       STORY_FILE: [absolute path to story .md file]
       MODE: per-chunk"
   ```

   **NEVER use `run_in_background: true`.** Validation must run synchronously.

   **After chunk-validator returns, parse the output:**

   Look for `**Status:** PASSED|FAILED|PARTIAL` in the agent's output.

   **Emit validation event** (always, regardless of verdict):
   ```bash
   CYCLE_DIR=$(dirname "$(dirname "$STORY_FILE")")
   STORY_NAME=$(basename "$STORY_FILE" .md)
   bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/append-event.sh \
     "${CYCLE_DIR}/.events" "validation_completed" "$STORY_NAME" \
     result="[STATUS]" chunk="[CHUNK]"
   ```

   **Route by verdict:**

   **If PASSED (or PARTIAL on non-final chunk):**
   - Run complete-chunk.sh: `bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/complete-chunk.sh`
   - Write continuation breadcrumb for next chunk:
   ```bash
   cat > "${CRAFT_PROJECT_ROOT:-.}/.craft/.continuation" << CRUMB
   ACTION: Continue implementation loop - if more chunks remain: checkpoint, then implementer for next chunk, then validate. If this was the final chunk: proceed to Step 5 (Story Completion).
   SKILL: craft:craft-story-implement
   ARGS: Continue from chunk ${CHUNK} - next chunk ready
   WRITTEN_BY: story-implement
   TIMESTAMP: $(date -u +%Y-%m-%dT%H:%M:%S)
   CRUMB
   ```
   - If this was the final chunk (N == total): instead write breadcrumb for story-final, proceed to Step 5.
   - If not final: return to CONTINUATION CHECKPOINT for next chunk.
   - **Do NOT stop between chunks.**

   **If FAILED:**
   > **FAILED path:** Read [references/validate-fix-loop.md](references/validate-fix-loop.md) for the error routing loop (error classification, REFINE_COUNT tracking, fix skill invocation, re-validation, and escalation). Follow its instructions.
   - After the loop exits with PASSED, return to the PASSED path above (run complete-chunk.sh, write breadcrumb, continue).
   - After the loop exits with escalation (REFINE_COUNT >= 4), offer rollback or stop.

   **ALL tests must pass. Never dismiss failures as "unrelated to this story." FAILED means FAILED - no overrides.**

   **If user corrects approach or establishes convention:**

   Watch for these signals:
   - "No, do X instead" / "Actually use Y" → potential enforcement
   - "We always do X" / "In this project" → convention
   - "Don't skip/assume" / frustrated tone → behavior
   - "Run X after Y" → automation
   - Detailed explanation of how something works → skill

   **Apply the filter:** Is this generalizable, recurring, project-specific, actionable?

   **If yes, ask:**
   > Use **AskUserQuestion**:
   ```yaml
   question: "Should I remember '[pattern]' for this project?"
   header: "Learn"
   options:
     - label: "Yes, capture it"
       description: "Add to learnings for harness update"
     - label: "No, one-time thing"
       description: "Don't capture"
   ```

   **If capturing:** Write to `.craft/.learnings.yaml` now (don't hold in memory).
   Read the existing file first, merge new learnings (increment `occurrences` for existing patterns, add new entries).

4. **Post-Chunk Learnings Check**

   After validation passes, actively review what happened during this chunk:

   **Ask yourself these three questions:**
   1. Did the user correct my approach during this chunk? (e.g., "No, do it this way")
   2. Did validation fail and require refine-chunk? (REFINE_COUNT > 0 means yes. Check the error patterns recorded during refine. If REFINE_COUNT >= 2, this is a recurring error — capture as enforcement.)
   3. Did I discover an unexpected pattern or convention?

   **If yes to any:** Write to `.craft/.learnings.yaml` immediately. Use the existing schema (conventions, enforcements, behaviors, etc.). Keep it concise — 1-2 sentences per learning.

   **If no to all:** Skip — no forced empty entries. Move on.

   This is a quick self-check, not a lengthy analysis. Spend ~10 seconds, not minutes.

5. **Update Status Line**
   - Update status line with current progress

6. **Loop Back**
   - Return to the CONTINUATION CHECKPOINT at the top of this "For each chunk:" block.
   - Proceed with the next chunk number.
   - If there are no more chunks (current > total), proceed to Step 5.
   - **DO NOT STOP between chunks.**

### Step 5: Story Completion

---

**>>> STORY COMPLETION CHECKPOINT**

You are in Step 5. The story is NOT done. You MUST complete ALL sub-steps below (quality gates, claims audit, self-critique, usage summary, learnings, spark verification, complete-story.sh). If you stop before complete-story.sh runs, the story stays active forever and the user has to manually resume. **Do not stop until Step 5.8 (complete-story.sh) has executed.**

---

After all chunks:

1. **Run Quality Gates**

   Invoke the chunk-validator agent directly for story-final validation:

   **Assemble FILES_CHANGED for story-final:**

   Compute all files changed across the entire story implementation:

   ```bash
   cd ${CRAFT_PROJECT_ROOT:-.} && git diff --name-only HEAD
   ```

   ```bash
   cd ${CRAFT_PROJECT_ROOT:-.} && git ls-files --others --exclude-standard
   ```

   **Union with all spec files:** Read ALL chunks' `**Files:**` sections from the story file (not just the current chunk). Extract every file path. Add any spec-listed files not already in the git output.

   **Format:** Comma-separated, project-relative paths. If empty, pass empty string.

   ```
   Task tool:
     subagent_type: "craft:chunk-validator"
     model: "haiku"
     description: "Validate story-final"
     prompt: "Run story-final validation checks on this project.

       CHUNK: final
       FILES_CHANGED: [computed FILES_CHANGED from git diff + spec union above]
       PROJECT_ROOT: ${CRAFT_PROJECT_ROOT:-.}
       PM: [package manager]
       STORY_FILE: [absolute path to story .md file]
       MODE: story-final"
   ```

   **Emit validation event:**
   ```bash
   CYCLE_DIR=$(dirname "$(dirname "$STORY_FILE")")
   STORY_NAME=$(basename "$STORY_FILE" .md)
   bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/append-event.sh \
     "${CYCLE_DIR}/.events" "validation_completed" "$STORY_NAME" \
     result="[STATUS]" chunk="final"
   ```

   **If PASSED:** Clean up any breadcrumb: `rm -f "${CRAFT_PROJECT_ROOT:-.}/.craft/.continuation"`. Write story-final continuation breadcrumb:
   ```bash
   cat > "${CRAFT_PROJECT_ROOT:-.}/.craft/.continuation" << CRUMB
   ACTION: Story-final PASSED. Continue Step 5: Claims Audit (5.1b), Self-Critique, Usage Summary, Learnings, Spark Verification, then complete-story.sh. DO NOT STOP.
   SKILL: craft:craft-story-implement
   ARGS: STORY_FINAL_PASSED - Continue Step 5 completion flow.
   WRITTEN_BY: story-implement (story-final)
   TIMESTAMP: $(date -u +%Y-%m-%dT%H:%M:%S)
   CRUMB
   ```
   Continue to the Claims Audit (Step 5.1b). **Do NOT stop here.**

   **If FAILED:**
   > **FAILED path:** Read [references/validate-fix-loop.md](references/validate-fix-loop.md) for the error routing loop. Follow its instructions (pass `MODE: story-final` to re-validation). Fix must succeed before story can complete.

   **ALL tests must pass before a story completes. No exceptions.**

1b. **Claims Audit (Step 5.1b - once per story, never per chunk)**

   The audit verifies the orchestrator's completion claims against on-disk artifacts before the story can complete. Post-compact sessions have overstated "ALL PASS" - this sub-step audits the narrator, not the code.

   **Write the validation receipt.** Persist the story-final validator's structured report (the verdict table plus any Errors section) verbatim, opening with a story-identity header:
   ```bash
   cat > "${CRAFT_PROJECT_ROOT:-.}/.craft/.validation-receipt.md" << RECEIPT
   story: [story name from the story file's frontmatter]
   [the chunk-validator's structured report from 5.1, verbatim]
   RECEIPT
   ```

   **Extract bare claims.** Build CLAIMS as newline-delimited bare assertion strings: take each cashed Pitch condition, the validator's overall verdict, and every completion statement you intend to present ("all tests pass", "only touched agents/ and commands/", "acceptance criteria met"), and reduce each to its bare claim. **Strip ALL narrative justification - drop every "because..." clause.** The auditor re-derives truth from artifacts; it must not inherit your reasoning.

   **Invoke the auditor.** Pass ONLY the claim list and artifact paths - NEVER your narrative summary, self-critique, or reasoning. Including them contaminates the audit and defeats its purpose.
   ```
   Task tool:
     subagent_type: "craft:claims-auditor"
     model: "haiku"
     description: "Audit completion claims"
     prompt: "Audit these completion claims against on-disk artifacts.

       CLAIMS:
       [newline-delimited bare claim strings]

       PROJECT_ROOT: ${CRAFT_PROJECT_ROOT:-.}
       VALIDATION_RECEIPT: ${CRAFT_PROJECT_ROOT:-.}/.craft/.validation-receipt.md
       STORY_FILE: [absolute path to story .md file]"
   ```

   **Branch on the result:**
   - **Auditor errored or returned no verdict table:** log "Claims audit failed to run - skipping (optional quality layer)" and continue to Self-Critique (Step 5.2). The audit NEVER blocks complete-story.sh.
   - **RECEIPT MISMATCH:** the receipt was stale (left by a crashed prior story). Rewrite the receipt from the current 5.1 validator output and re-invoke the auditor once; if the mismatch persists, log it and continue as an audit-skip. Never accept wrong-story verdicts.
   - **`Unsupported: 0`:** emit a single line - "Claims audit: N/N supported" - and continue to Self-Critique (Step 5.2). A clean run adds no noise.
   - **`Unsupported: > 0` (interactive):** surface the auditor's `| Claim | Verdict | Evidence |` table to the user via AskUserQuestion BEFORE any later sub-step - options: fix the underlying issue, correct the claim in the completion report, or proceed acknowledging the flag. The user rules before complete-story.sh runs.
   - **`Unsupported: > 0` (RUN_MODE=autonomous):** flag and continue - write the unsupported verdict rows into the story file as a `## Claims Audit` section and include them in the end-of-run summary; no blocking prompt; the chain continues. Real code failures already halt at validation - the audit's unattended value is the durable flag.

2. **Self-Critique**
   Compare against:
   - Inspiration sites
   - Locked patterns
   - Design tokens
   - Acceptance criteria

3. **Usage Summary**

   Read the usage log and display token breakdown:
   Use **Read** to read `.craft/cycles/[cycle]/.usage/[story].log` (if the file exists).

   Display as:
   > **Token Usage:**
   > | Chunk | Agent | Tokens | Tools | Duration |
   > |-------|-------|--------|-------|----------|
   > | 1 | implementer | 45,200 | 18 | 4m 20s |
   > | 1 | validate | 3,100 | 4 | 0m 30s |
   > | 2 | implementer | 62,400 | 24 | 6m 10s |
   > | 2 | validate | 2,800 | 3 | 0m 25s |
   > | **Total** | | **113,500** | **49** | **11m 25s** |

4. **Present Results**

   > "Story implementation complete.
   >
   > [Quality report]
   > [Self-critique findings]
   > [Token usage summary]"

   Auto-mark complete if quality gates pass. Continue to next story. Only stop at end of cycle or if issues found.

5. **Verify Learnings Written**

   Learnings should already be in `.craft/.learnings.yaml` (written incrementally after each chunk).
   Verify the file exists and any final learnings from the last chunk are captured.

   > **Schema and examples:** Read [commands/references/learnings-schema.md](commands/references/learnings-schema.md) for the full `.learnings.yaml` data structure (6 categories: conventions, enforcements, behaviors, automations, skills, workflows) and merge logic.

   **If learnings captured:**
   > "Captured [N] learnings from this story.
   > Run `/craft:reflect` to convert to harness, or they'll be prompted at cycle-complete."

6. **Mandatory Story Reflection**

   Before marking complete, reflect on the whole story. This is the guaranteed capture point — it fires for every story.

   **First, present the tally summary:**
   ```
   STORY REFLECTION:
   - Validation failures this story: [N] (count of chunks where REFINE_COUNT > 0)
   - User corrections this story: [N] (count of "Learn" AskUserQuestion captures)
   - Patterns discovered: [N]
   - Total learnings written this story: [N] (count entries in .learnings.yaml for this story)
   ```

   **Zero-learnings flag:** If validation failures > 0 but total learnings written = 0, flag: "This story had [N] validation failures but zero learnings captured. Review the error patterns before completing?" This asks to review, does NOT block completion.

   **Then ask yourself:**
   - **Corrections:** Did the user correct my approach at any point? What did they prefer?
   - **Patterns:** What conventions or patterns worked well? Worth locking?
   - **Errors:** What mistakes did I make? What should I avoid next time?
   - **Conventions:** Any project-specific conventions I should remember?

   **If anything found:** Append to `.craft/.learnings.yaml` using existing schema. Merge with any learnings already written during chunks.

   **If genuinely nothing learned:** Write a brief note: `"Clean story — no new learnings"` under a `notes:` key with the story name and date. This confirms the reflection happened (vs. being skipped).

   **This step must not block story completion.** If `.learnings.yaml` write fails, log a warning and proceed to Mark Complete.

7. **Spark Verification**

   Before marking complete, verify the Spark's intent was delivered. This is YOUR job — do not ask the user. The planning step already guaranteed every Spark requirement has a home in a chunk and wrote a `## The Pitch` section staking the plan's guarantee on named conditions.

   **Steps:**
   1. Re-read the story's `## The Pitch` section (written during planning).
   2. Verify the conditions table is fully cashed: every `unverifiable -> Chunk N's FIRST test` condition had its test written and passing (the chunk validations already enforced this — this is a final confirmation, not a re-run).
   3. Present the pitch as a confident summary alongside the completion message.

   ```
   Pitch Delivered:
   [The Pitch sell]
   Conditions: [all verified/cashed — note any Amendments recorded along the way]
   ```

   **If the story has a `## Delivery` section instead** (older stories planned before the Pitch format): present that as the summary. **If it has neither:** Self-verify by re-reading the Spark, confirming each intention was addressed by a chunk, and present a brief summary. Do not ask the user.

   **If a Spark intention genuinely has no implementation** (should not happen if planning was correct): Stop. Flag the gap. Plan an additional chunk. Do not mark complete.

7b. **Write the Commit Manifest - REQUIRED**

   `complete-story.sh` stages ONLY what this manifest lists. If the manifest is absent it makes NO commit - there is no fallback. Write it now, after Spark Verification, immediately before Mark Complete.

   Build the manifest from the story-final FILES_CHANGED value (computed in sub-step 1) plus the standing include set:

   ```bash
   cat > .craft/.commit-manifest << 'MANIFEST'
   story: [story file basename without .md, e.g. 3-user-auth]
   [one project-relative path per line]
   MANIFEST
   ```

   - The `story:` header MUST be the story file's basename without `.md` - complete-story.sh compares it against the file it was invoked with and aborts the commit on mismatch.
   - **One path per line.** FILES_CHANGED is a comma-separated string - split it. complete-story.sh treats any comma in a body line as a malformed manifest and makes no commit.
   - **Standing include set:** append `.craft/.learnings.yaml` and `.craft/.validation-receipt.md` to the manifest if the files exist. They are story output and ride the receipt. In projects that gitignore `.craft/`, complete-story.sh skips them with a warning - expected, not an error.
   - Gitignored manifest entries are skipped with a warning; any OTHER staging failure aborts the commit entirely (a receipt with failures is no receipt).
   - The manifest is consumed (deleted) by complete-story.sh on every path, including aborts.

8. **Mark Complete - REQUIRED**

   **YOU MUST RUN THIS.** Story is not complete until this runs:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/complete-story.sh .craft/cycles/[cycle]/stories/[story].md
   ```

   This updates:
   - Story status → `complete`
   - Cycle progress counts
   - Cycle.yaml stories table

   **Do not skip this step.** Without it, the story stays `active` forever.

8b. **Surface and Triage Leftovers**

   The completion commit staged only the manifest. Anything else still sitting in the tree is a leftover - it is NEVER swept into a commit, and it gets exactly one triage decision, recorded in the ledger.

   **Compute the leftover set:**

   ```bash
   cd ${CRAFT_PROJECT_ROOT:-.} && git ls-files --others --exclude-standard
   ```

   From that list, drop paths that were in the manifest (the FILES_CHANGED set from sub-step 1) and paths the ledger has already decided:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/triage-ledger.sh lookup [path]
   ```

   A non-empty lookup result other than `pending` means the path was decided in a previous story - do NOT re-ask, ever. The never-re-ask check is this script lookup, not your memory of the session.

   **Queue new leftovers as pending**, then surface them in the completion report:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/triage-ledger.sh append [path] pending [story-name]
   ```

   > "Leftover files not included in the story commit:
   > - [path] (pending triage)
   > ..."

   **Interactive mode - one AskUserQuestion per pending leftover** (never batch them into one question):

   ```
   question: "Leftover file `[path]` was not part of the validated story commit. What should happen to it?"
   header: "Leftover"
   options:
     - label: "Ignore"
       description: "Append it to .gitignore with a provenance comment - never asked again"
     - label: "Claim"
       description: "Stage and commit it explicitly - secret-shaped files are refused"
     - label: "Leave"
       description: "Keep it untracked, recorded in the ledger - never asked again"
   ```

   - **Ignore:** append the path to `.gitignore` with a provenance comment, then record it:
     ```bash
     printf '%s  # craft: ignored during [story-name]\n' "[path]" >> .gitignore
     ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/triage-ledger.sh append [path] ignore [story-name]
     ```
   - **Claim:** check the shared deny-pattern list FIRST - this is a hard stop, not a warning:
     ```bash
     source ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/secret-deny-patterns.sh
     matches_secret_pattern "[path]" && echo "REFUSED: secret-shaped path"
     ```
     If it matches: refuse the claim, tell the user which pattern matched, and leave the entry pending (they can `leave` or `ignore` it instead). If it does not match: `git add -- [path]`, commit it separately with a clear message, and record `claim` in the ledger.
   - **Leave:** record `leave` in the ledger. The file stays untracked and is never asked about again.

   **Autonomous mode (RUN_MODE=autonomous): leave-and-report.** Record `leave` for every new leftover, include the list in the final report, and continue. Never ask, never block, never sweep.

9. **Check for Cycle Completion**

   After marking complete, check if all stories in the cycle are done:

   Use **Glob** with pattern `.craft/cycles/[cycle]/stories/*.md` → count → `total`.

   Use **Grep** with pattern `^status: complete`, path `.craft/cycles/[cycle]/stories/`, glob `*.md`, output_mode `files_with_matches` → count → `complete`.

   **If all stories complete ($complete == $total):**

   > "All [N] stories complete! Running cycle-complete..."
   → **INVOKE `craft:craft-cycle-complete` using the Skill tool**

   **If stories remain:**

   Find the next story to implement:
   ```
   # Find next ready story (by story number order)
   cycle_dir = ".craft/cycles/$ACTIVE_CYCLE"
   Glob "$cycle_dir/stories/*.md" → story_files (sorted by name)

   next_story = ""
   for each story_file in story_files:
     Read story_file (limit: 15) → parse status from frontmatter
     if status == "ready":
       next_story = filename without .md extension
       break
   ```

   **If next_story found:**
   > "Story complete. Continuing to **[next story title]**..."
   → **INVOKE `craft:craft-story-implement` using the Skill tool** with args `$next_story`

   **If no ready stories but planning stories exist:**
   > "No ready stories left. [N] stories still need plan-chunks."

   ⛔ **DO NOT plan chunks directly. You MUST invoke the skill:**
   ```
   Skill tool:
     skill: "craft:plan-chunks"
     args: "[next planning story file path] — Mid-cycle planning: previous story just completed.
  DIRECTION_CONFIRMED: true
  STORY: [story-name]
  CYCLE: [cycle-dir-name]
  CYCLE_GOAL: [cycle goal]"
   ```
   This hands off to `plan-chunks` for detailed implementation planning. Do NOT plan inline. Re-check for ready stories after planning completes.

   **If no stories left at all (shouldn't happen — cycle completion check above should catch this):**
   → **INVOKE `craft:craft-cycle-complete` using the Skill tool**

## Parallel Stories (Max 2)

### Before Starting Second Story

**MANDATORY conflict check** - extract files from both stories' chunks:

Use **Read** to read both story files. Extract file paths from each story's `**Files:**` sections across all chunks. Compare the two file lists to find overlap.

**If overlap detected:**
> "These stories both modify the same files:
> - `auth.ts` (Story A chunk 2, Story B chunk 1)
> - `types.ts` (Story A chunk 3, Story B chunk 2)"

Use **AskUserQuestion**:
```
question: "How do you want to handle the file overlap?"
header: "Conflict"
options:
  - label: "Work on [Story A] first (Recommended)"
    description: "Complete A before starting B"
  - label: "Work on [Story B] first"
    description: "Complete B before starting A"
  - label: "Continue anyway"
    description: "Risk merge conflicts"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their strategy.

**If user selects "Work on [Story A] first":**
→ Set Story A as the current implementation target. Queue Story B to start after A completes.

**If user selects "Work on [Story B] first":**
→ Set Story B as the current implementation target. Queue Story A to start after B completes.

**If user selects "Continue anyway":**
→ Proceed with both stories. Flag overlapping files for extra attention during validation.

**If no overlap** - allow parallel work.

### During Implementation

Re-check before each chunk if parallel stories exist. Files may have been added.

## Resume Support

If story has `status: active` (partially implemented):

### Show Progress

> "Resuming **[Story Name]**
>
> **Progress:**
> - Chunk 1: ✓ Complete
> - Chunk 2: ✓ Complete
> - Chunk 3: ◐ In progress ← you are here
> - Chunk 4: ○ Pending
>
> **Last checkpoint:** [snapshot timestamp]
>
> Continue with Chunk 3?"

### Verify State

Check if files match expected state:

```bash
git diff [checkpoint-hash]
```

**If changes detected since checkpoint:**
> "Files have changed since last checkpoint:
> - `auth.ts` — modified
> - `login.tsx` — modified"

Use **AskUserQuestion**:
```
question: "What happened with these changes?"
header: "Changes"
options:
  - label: "Part of my progress"
    description: "Keep changes and continue"
  - label: "External changes"
    description: "Review before continuing"
  - label: "Accidental"
    description: "Rollback to checkpoint"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand what happened.

**If user selects "Part of my progress":**
→ Keep all changes, proceed to Step 4 (Implementation Loop) for the current chunk.

**If user selects "External changes":**
→ Show git diff since checkpoint. Let user review. Then proceed to Step 4 for the current chunk.

**If user selects "Accidental":**
→ Run `salvage-partial-work.sh` to preserve partial work, then `git restore` to checkpoint. Re-start the current chunk from Step 4.

### Handle Stale State

If significant time has passed (> 1 day):

> "It's been [X days] since you worked on this.
>
> Quick refresh:
> - **Story:** [Name]
> - **Goal:** [Brief summary]
> - **Current chunk:** [Description]
>
> Still want to continue, or pick something else?"

### Resume Into Step 4

⛔ **After showing progress and getting confirmation, resume enters the Step 4 Implementation Loop above.** The `craft:implementer` agent handles the chunk — the orchestrator does NOT implement directly.

For partially-completed chunks, include in the Task tool prompt to the implementer agent:
> "This chunk was partially implemented. Review what exists in the target files, identify remaining work from the Done When criteria, and complete only what's missing."

This ensures the same `⛔ CRITICAL` agent delegation path is followed whether starting fresh or resuming.

### State Recovery

If `.state` file is corrupted or missing:

> "State file is missing. Reconstructing from story file...
>
> Based on chunk markers:
> - Chunks 1-2 are marked complete
> - Chunk 3 is unmarked
>
> Start from Chunk 3?"

## Remember

- Stories must have chunks before implementing
- State snapshot before every chunk; at story completion, one commit staged from the validated manifest (write it in sub-step 7b - no manifest means no commit), leftovers surfaced for triage
- Validate after every chunk
- Nothing ships without approval
- Quality is pristine by default
- **TDD is required** — tests first, then implementation
- **Never skip tests** — set up infrastructure if missing
- **Edge cases matter** — implementer checks the checklist before marking complete
- **Strict TypeScript** — enable and fix errors, don't disable
- **ALL tests must pass** - never dismiss test failures as "unrelated to this story." FAILED means FAILED.
- **No any types** — use proper types or get explicit approval
- **NEVER directly edit `.state` or `.global-state` files** — always use the transition scripts (`start-story.sh`, `complete-chunk.sh`, `complete-story.sh`, `update-cycle-state.sh`). Direct edits corrupt state and skip stories/chunks.
- **NEVER manually activate a cycle** — if a story's cycle isn't active, use `craft:cycle-start` to activate it. Do not edit `.global-state` to set `ACTIVE_CYCLE` yourself.
- **The implementer may report "diagnostic issues"** - these are stale IDE diagnostics from the Task tool, not real errors. Only chunk-validator agent results determine pass/fail.
- **zsh compatibility** — Never use `status` as a bash variable name. It is read-only in zsh (alias for `$?`). Use `st`, `story_status`, `exit_code`, etc. instead.
- **Use create-checkpoint.sh** for chunk state snapshots (git commits happen via complete-story.sh)
- **Always salvage before rollback** — run `salvage-partial-work.sh` before any `git restore`/`git checkout` to preserve partial work
- **After chunk-validator returns, parse `**Status:**` and route immediately.** PASSED -> complete-chunk.sh -> next chunk. FAILED -> Read references/validate-fix-loop.md -> fix -> re-validate. Do not stop between steps.
- **The story is not done until Step 5 completes.** Chunk validation passing is a gate to the NEXT chunk, not the end. Only Step 5 (story completion) marks the story done.
