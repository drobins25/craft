---
name: reflect
description: "Apply captured learnings to improve the Craft harness and project patterns. Converts .learnings.yaml into permanent updates."
aliases:
  - apply-learnings
  - update-harness
---

# Reflect

Convert captured learnings from `.craft/.learnings.yaml` into permanent harness files in `.claude/`.

## When to Use

- Triggered automatically by `/craft` when pending learnings exist
- Manually via `/craft:reflect` at any time
- Prompted at cycle-complete before archiving

## Flow

### Step 1: Load Pending Learnings & Ungraduated Fixes

Read `.craft/.learnings.yaml` and filter for `status: pending`:

Use **Grep** with pattern `status: pending`, path `.craft/.learnings.yaml`, output_mode `count` → `pending_count`. If the file doesn't exist, `pending_count = 0`.

Also check for aggregated failure patterns from the active cycle:

If `ACTIVE_CYCLE` is set, use **Grep** with pattern `^  - pattern:`, path `.craft/cycles/$ACTIVE_CYCLE/.failure-patterns.yaml`, output_mode `count` → `failure_patterns`. If file doesn't exist or `ACTIVE_CYCLE` not set, `failure_patterns = 0`.

Also count ungraduated fix records (the second intake - fixes carry human-confirmed root causes that can graduate into `.claude/rules/`):

```bash
FIX_COUNT=$(bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/count-ungraduated-fixes.sh")
THRESHOLD=$(grep -m1 '^rule_pass_threshold:' "${CRAFT_PROJECT_ROOT:-.}/.craft/settings.yaml" 2>/dev/null | sed 's/^rule_pass_threshold:[[:space:]]*//')
THRESHOLD=${THRESHOLD:-10}
```

The fix queue is **actionable only when `FIX_COUNT >= THRESHOLD`** - below the threshold there is no fix action available, so it counts as empty for this gate.

**If no pending learnings AND no failure patterns AND `FIX_COUNT < THRESHOLD`:**
> "No pending learnings to process. Harness is up to date."

**If anything is actionable:** Continue to Step 1b.

---

### Step 1b: Rule-Pass Offer (when the fix queue is actionable)

**If `FIX_COUNT >= THRESHOLD`**, offer the rule pass FIRST - before any learnings drain. Fixes are the denser signal (every record is a human-confirmed root cause).

Use **AskUserQuestion**:
```yaml
question: "[FIX_COUNT] fixes have accumulated since the last rule pass. Run a rule pass to mine them for graduation-worthy rules?"
header: "Rule pass"
options:
  - label: "Run the rule pass"
    description: "~2-3 min agent read + per-rule review. Proposals are review-gated - nothing is written without your approval."
  - label: "Not now"
    description: "Skip - the offer returns next reflect (the counter does not reset on decline)"
```

**If "Run the rule pass":** Read `${CLAUDE_PLUGIN_ROOT}/commands/references/rule-pass.md` and follow its instructions completely (agent invocation, presentation, review, write, receipt, watermark). When the pass completes, continue below.

**If "Not now":** Do NOT touch `.craft/fixes/.rule-pass-state` - the watermark only advances on a completed pass. Continue below.

**Then:** If `pending_count > 0` or `failure_patterns > 0`, continue to Step 2 (the learnings drain, unchanged). Otherwise the session is done:
> "Nothing else to reflect on."

**If `FIX_COUNT < THRESHOLD`** (learnings or failure patterns brought us here): skip this step, continue to Step 2.

---

### Step 2: Present Summary

Present learnings organized by type and target. Include all sections that have items:

> "**Pending Learnings**
>
> **Conventions** (→ `.claude/CLAUDE.md`):
> - Use Zustand for client state (2 occurrences)
> - Prefer server components (3 occurrences)
>
> **Behaviors** (→ `.claude/CLAUDE.md`):
> - Never skip pre-existing code (2 occurrences)
>
> **Enforcements** (→ `.claude/rules/`):
> - no-any-type: Never use 'any' (3 occurrences)
>
> **Automations** (→ `.claude/settings.local.json`):
> - prettier on edit (2 occurrences)
>
> **Skills** (→ `.claude/skills/`):
> - our-form-pattern (3 occurrences)
>
> **Workflows** (→ `.claude/commands/`):
> - create-component (3 occurrences)
>
> **Tool Failure Patterns** (→ `.claude/rules/`):
> - [label from patterns file] ([total_count] failures across [N] stories)
>
> These are knowledge gaps the agent hit repeatedly — project-specific things it should learn.
>
> Apply these to the harness?"

Read `.failure-patterns.yaml` to populate the Tool Failure Patterns section. For each `pattern` entry, display its `label`, `total_count`, and the number of unique stories. Only show the Tool Failure Patterns section if `failure_patterns > 0`.

Use **AskUserQuestion**:
```yaml
question: "Apply learnings to harness?"
header: "Reflect"
options:
  - label: "Apply all"
    description: "Write all pending learnings to .claude/"
  - label: "Review each"
    description: "Approve one by one"
  - label: "Skip for now"
    description: "Keep learnings pending"
```

---

### Step 3: Write to Harness

**Ensure directories exist:**
```bash
mkdir -p .claude/rules .claude/skills .claude/commands
```

---

#### 3a. Conventions & Behaviors → `.claude/CLAUDE.md`

If `.claude/CLAUDE.md` doesn't exist, create it:
```markdown
# Project Instructions

## Stack & Conventions

## Behaviors

```

**Append conventions** to Stack & Conventions section:
```markdown
- Use Zustand for client state, not Redux
- Prefer server components by default
```

**Append behaviors** to Behaviors section:
```markdown
- Never skip pre-existing code with 'unchanged' comments
- Always read files before editing
```

---

#### 3b. Enforcements → `.claude/rules/*.md`

Create `.claude/rules/[rule_name].md` with `paths:` frontmatter:

```markdown
---
paths:
  - "**/*.ts"
  - "**/*.tsx"
---
# No Any Type

Never use `any` in TypeScript. Always provide proper types.

## Bad

```typescript
const data: any = fetchData()
```

## Good

```typescript
const data: User = fetchData()
```
```

#### 3b-ii. Tool Failure Patterns → `.claude/rules/[suggested_rule].md`

For each approved failure pattern, write `.claude/rules/[suggested_rule].md`:

```markdown
# Rule: [label]

[description of what to do instead, derived from the pattern label]

Source: Detected from [total_count] failures across [stories list]
```

For example, if the pattern is `missing-script-typecheck` with `suggested_rule: use-correct-typecheck-command`:

```markdown
# Rule: use-correct-typecheck-command

Project does not have 'npm run typecheck' — check available scripts with 'npm run'.

Run `npm run` (no arguments) to list all available scripts before using one.
Prefer `npx tsc --noEmit` for TypeScript checking if no typecheck script exists.

Source: Detected from 5 failures across ["1-article-infrastructure", "2-writing-listing-page", "3-tag-filtering"]
```

After processing ALL failure patterns (approved or skipped), delete `.failure-patterns.yaml`:

```bash
rm -f ".craft/cycles/$ACTIVE_CYCLE/.failure-patterns.yaml"
```

This ensures the file is consumed once and not re-presented on future reflect runs.

---

#### 3c. Automations → `.claude/settings.local.json`

Read existing file or create, then merge hooks:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "prettier --write $CLAUDE_FILE_PATHS"
          }
        ]
      }
    ]
  }
}
```

---

#### 3d. Skills → `.claude/skills/[name]/SKILL.md`

Create directory and SKILL.md with required frontmatter:

```bash
mkdir -p .claude/skills/our-form-pattern
```

```markdown
---
name: our-form-pattern
description: "How we build forms in this project. Use when creating forms, inputs, validation, working with react-hook-form, or defining zod schemas. Canonical example: components/forms/LoginForm.tsx"
---
# Form Pattern

We use react-hook-form + zod for all forms.

## Key Points

- react-hook-form + zod for validation
- Schema in `/schemas/[name].schema.ts`
- Inline validation, not on submit
- Loading state on submit button

## Canonical Example

See `components/forms/LoginForm.tsx`
```

**IMPORTANT:** `description:` is the trigger. Include what it covers + when to use it.

---

#### 3e. Workflows → `.claude/commands/*.md`

Create `.claude/commands/[name].md` with frontmatter:

```markdown
---
description: "Create a new component with test and export"
allowed-tools: Read, Write, Edit, Glob
argument-hint: [component-name]
---
# Create Component

## Steps

1. Create component file in `/components/[name]/`
2. Add export to `/components/index.ts`
3. Create test file in `__tests__/`
```

---

### Step 4: Mark as Written

Update each processed learning in `.craft/.learnings.yaml`:

```yaml
# Change:
status: pending
# To:
status: written
written_at: 2026-02-03
```

Learnings stay in file for historical reference.

---

### Step 5: Confirm

> "**Harness Updated**
>
> - `.claude/CLAUDE.md`: +[N] conventions, +[N] behaviors
> - `.claude/rules/`: +[N] rules
> - `.claude/settings.local.json`: +[N] hooks
> - `.claude/skills/`: +[N] skills
> - `.claude/commands/`: +[N] commands
>
> These will be automatically loaded in future sessions."

---

## File Format Reference

| Learning Type | Target | Required Frontmatter |
|---------------|--------|---------------------|
| Convention | `.claude/CLAUDE.md` | None |
| Behavior | `.claude/CLAUDE.md` | None |
| Enforcement | `.claude/rules/[name].md` | `paths:` (optional) |
| Automation | `.claude/settings.local.json` | N/A (JSON) |
| Skill | `.claude/skills/[name]/SKILL.md` | `name:`, `description:` |
| Workflow | `.claude/commands/[name].md` | `description:` |

---

## Learnings Data Structure

Reference for what gets captured during implementation:

```yaml
# .craft/.learnings.yaml

conventions:
  - pattern: "Use Zustand for client state"
    evidence:
      - source: user_statement
        quote: "We use Zustand here"
        date: 2026-02-01
    occurrences: 2
    status: pending | written
    section: stack | patterns | preferences

enforcements:
  - pattern: "Never use 'any' type"
    evidence:
      - source: user_correction
        quote: "Don't use any"
        file: auth.ts
        date: 2026-02-01
    occurrences: 3
    status: pending | written
    rule_name: no-any-type
    paths: ["**/*.ts", "**/*.tsx"]

behaviors:
  - pattern: "Never skip pre-existing code"
    evidence:
      - source: user_correction
        quote: "Don't skip that"
        date: 2026-02-01
    occurrences: 2
    status: pending | written

automations:
  - name: prettier-on-edit
    trigger: "After editing .tsx files"
    action: "prettier --write"
    evidence: [...]
    occurrences: 2
    status: pending | written
    hook_event: PostToolUse
    hook_matcher: "Write|Edit"

skills:
  - name: our-form-pattern
    description: "How we build forms..."
    evidence: [...]
    occurrences: 3
    status: pending | written
    canonical_example: components/forms/LoginForm.tsx
    key_points: [...]

workflows:
  - name: create-component
    description: "Create component with test"
    steps: [...]
    evidence: [...]
    occurrences: 3
    status: pending | written
    allowed_tools: [Read, Write, Edit]
```

---

## Remember

- **Reflect converts, implement captures** — this command processes what was captured
- **Pending learnings persist** — they don't disappear until reflected
- **Harness only grows** — never remove without explicit ask
- **User approves** — always present summary before writing
- **Description is the trigger** — for skills, make it rich
