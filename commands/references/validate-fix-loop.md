# Validate-Fix Loop

You are in story-implement Step 4. The chunk-validator agent returned **FAILED**. Follow this loop to fix and re-validate.

## Initialize

Read `REFINE_COUNT` from persisted state. If `.craft/.chunk-state` exists AND its `REFINE_CHUNK` matches the current chunk number, restore `REFINE_COUNT` from the file. Otherwise set `REFINE_COUNT=0`.

```bash
CHUNK_STATE="${CRAFT_PROJECT_ROOT:-.}/.craft/.chunk-state"
if [ -f "$CHUNK_STATE" ]; then
  source "$CHUNK_STATE"
  if [ "$REFINE_CHUNK" != "[current_chunk_number]" ]; then
    REFINE_COUNT=0
  fi
else
  REFINE_COUNT=0
fi
```

This counter persists across context compactions and loop iterations. It never resets within a single chunk unless `.chunk-state` references a different chunk (stale from previous chunk).

## Step 1: Classify Errors

Parse the `**Type:**` field from each error in the `**Errors:**` section of the chunk-validator output.

**Mixed error types:** If output contains BOTH `test-failure` AND non-test errors (type-error, lint-error, build-error), route to **refine-chunk first**. Type/build errors often cause test failures as a side effect - fixing code errors first may resolve tests too. If tests still fail after refine-chunk, the next loop iteration routes to test-fix.

## Step 2: Invoke Fix Skill

**Before invoking ANY fix skill**, write a continuation breadcrumb so the stop hook catches premature stops:

```bash
cat > "${CRAFT_PROJECT_ROOT:-.}/.craft/.continuation" << CRUMB
ACTION: Fix skill returned. Re-validate this chunk NOW using chunk-validator agent via Task tool. Do NOT stop.
WRITTEN_BY: validate-fix-loop
TIMESTAMP: $(date -u +%Y-%m-%dT%H:%M:%S)
CRUMB
```

**Test failures only** (`Type: test-failure`, no other error types):

Increment `REFINE_COUNT`.

Persist the counter:
```bash
cat > "${CRAFT_PROJECT_ROOT:-.}/.craft/.chunk-state" << STATE
REFINE_COUNT=$REFINE_COUNT
REFINE_CHUNK=[current_chunk_number]
STATE
```

-> **INVOKE `craft:test-fix` using the Skill tool** with args:
```
"[STORY_FILE] - Chunk [CHUNK]. Test failures detected.
  CHUNK: [CHUNK value]
  CHUNK_GOAL: [goal from chunk spec]
  FAILING_TESTS: [File and Message from error block]
  ERRORS: [full error block text]
  FILES_CHANGED: [FILES_CHANGED value]"
```

After test-fix returns:
1. If verdict is "Test stale": test-fix updated the test. Continue to Step 3 (re-validate). Do NOT increment REFINE_COUNT again.
2. If verdict is "Code wrong" or "Compile error": continue to Step 3 (re-validate). REFINE_COUNT already incremented.
3. If verdict is "Ambiguous": user decides, then route accordingly.

**All other failures** (`Type: type-error`, `lint-error`, `build-error`):

Increment `REFINE_COUNT`.

Persist the counter:
```bash
cat > "${CRAFT_PROJECT_ROOT:-.}/.craft/.chunk-state" << STATE
REFINE_COUNT=$REFINE_COUNT
REFINE_CHUNK=[current_chunk_number]
STATE
```

-> **INVOKE `craft:refine-chunk` using the Skill tool** with args:
```
"[STORY_FILE] - Chunk [CHUNK]. Validation errors need fixing.
  CHUNK: [CHUNK value]
  ERRORS: [full Errors section from agent output]
  FILES_CHANGED: [FILES_CHANGED value]
  REFINE_COUNT: [current count]"
```

## Step 3: Re-validate Immediately

After the fix skill returns (look for `>>> HAND BACK` in its output), re-invoke the chunk-validator agent **immediately**. Do not stop. Do not output a summary. Go directly back to the Task tool invocation:

```
Task tool:
  subagent_type: "craft:chunk-validator"
  model: "haiku"
  description: "Re-validate chunk [CHUNK] after fix (attempt [REFINE_COUNT])"
  prompt: "Run validation checks on this project.

    CHUNK: [CHUNK value]
    FILES_CHANGED: [FILES_CHANGED value]
    PROJECT_ROOT: [PROJECT_ROOT value]
    PM: [PM value]
    STORY_FILE: [STORY_FILE value]
    MODE: [per-chunk or story-final]"
```

Parse the output:
- **If PASSED or PARTIAL (non-final):** Clean up breadcrumb and chunk state: `rm -f "${CRAFT_PROJECT_ROOT:-.}/.craft/.continuation" "${CRAFT_PROJECT_ROOT:-.}/.craft/.chunk-state"`. Exit this loop. Return to the inline PASSED/PARTIAL handling in Step 4.
- **If FAILED:** Check escalation (Step 4 below), then loop back to Step 1.

## Step 4: Escalation Check

Before each new fix attempt, check REFINE_COUNT:

- `REFINE_COUNT >= 2`: Flag for mandatory learnings capture. In an interactive (default) run, present to the user. In an autonomous run (RUN_MODE=autonomous), try a different approach. **Continue the loop.**
- `REFINE_COUNT >= 4`: **Exit the loop.** Clean up breadcrumb and chunk state: `rm -f "${CRAFT_PROJECT_ROOT:-.}/.craft/.continuation" "${CRAFT_PROJECT_ROOT:-.}/.craft/.chunk-state"`. Offer rollback or stop.

**Before any rollback, salvage partial work:**

Use **Read** on the checkpoint file from Step 4 item 1 -> parse `git_ref:` -> `CHECKPOINT_REF`

```bash
SALVAGE_PATH=$(${CLAUDE_PLUGIN_ROOT}/hooks/scripts/salvage-partial-work.sh \
  "$CHECKPOINT_REF" "[story-name]" [chunk_number] "${CRAFT_PROJECT_ROOT:-.}")
```

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/append-recovery-log.sh \
  "${CRAFT_PROJECT_ROOT:-.}" "[story-name]" [chunk_number] \
  "[failure_type]" "$SALVAGE_PATH" "$CHECKPOINT_REF" "[error_details]"
```

## CLI Error Detection (runs alongside routing)

When chunk-validator output contains CLI/infrastructure error patterns, capture as learnings. This does NOT change the verdict.

**Detection patterns:**
- `Unknown option` or `unknown option` - wrong flag
- `missing script` or `Missing script` - package.json not configured
- `command not found` - tool not installed
- `ENOENT` - file/directory missing
- `permission denied` - filesystem issue
- `Cannot find module` in non-test context - missing dependency

**When detected:** Read `.craft/.learnings.yaml`, add/merge enforcement entry:
```yaml
enforcements:
  - pattern: "[generalized pattern]"
    evidence:
      - source: cli_error
        quote: "[raw error message]"
        story: "[story name]"
        date: [today's date]
    occurrences: 1
    status: pending
    type: infrastructure
```

## Loop Summary

After the loop exits (PASSED or escalation), output a single summary:

```
## Validation Loop: [PASSED after N refines | ESCALATED at REFINE_COUNT N] - Chunk [N/total: title]

Iterations:
1. FAILED (type-error: [detail]) -> refine-chunk -> fixed
2. PASSED

REFINE_COUNT: [final count]
[If REFINE_COUNT >= 2: "Warning: Flagged for mandatory learnings capture"]
```

Then return to the inline flow in story-implement Step 4.
