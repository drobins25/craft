---
name: update-docs
description: "Re-scan the project and update documentation. Keeps project.md and locked.md current as the codebase evolves."
---

# Update Documentation

Re-scan the project to update `.craft/project.md` and `.craft/design/locked.md` as the codebase evolves.

## When to Use

- After major refactors or architectural changes
- After adding new dependencies or frameworks
- When you notice documentation is stale
- Periodically (check `last_updated` in frontmatter)
- Before starting a significant new initiative

## Flow

### Step 1: Check Current State

Read existing documentation to understand what we have:

Use **Read** to read `.craft/project.md` (with `limit: 20`) and `.craft/design/locked.md` (with `limit: 20`) to check `last_updated` timestamps in frontmatter.

> "Your project documentation was last updated on **[date]**.
>
> Let me scan for changes..."

---

### Step 2: Run Project Scanner

**INVOKE the project-scanner agent using the Task tool:**

```
Task tool:
  subagent_type: "craft:project-scanner"
  description: "Re-scan project for documentation update"
  prompt: "Scan this project comprehensively for a documentation update.

  **Project root:** [current working directory]
  **Context:** This is a re-scan, not initial setup. Focus on:
  - New patterns that have emerged
  - Changed conventions
  - New dependencies or tools
  - Architecture evolution
  - Files/directories that have been added or reorganized

  Follow your full analysis checklist (P1-P9). Be thorough.
  Return findings in your structured output format."
```

**Extract confidence signals:**

If the agent's output contains a `## Confidence Signals (YAML)` section:
1. Extract the YAML content from the fenced code block in that section
2. Write it to `.craft/design/.confidence-signals.yaml` at the project root
3. This file is consumed by craft-init for project-state matrix branching.

If the section is missing (agent failed, non-UI project), skip this step.

---

### Step 3: Compare Findings

Read current documentation:
- `.craft/project.md`
- `.craft/design/locked.md`
- `.craft/design/tokens.yaml` (for CLI: conventions)
- `.craft/design/schemas.md` (if exists)

Compare agent findings against current docs. Identify:

**New discoveries:**
- Patterns not in locked.md
- Dependencies not in project.md
- Conventions that have emerged

**Changes:**
- Tech stack updates (new packages, version changes)
- Architecture evolution (new directories, reorganization)
- Convention drift (naming, organization changes)

**Potential removals:**
- Patterns no longer in use
- Dependencies removed
- Outdated information

---

### Step 4: Present Diff

> "**Documentation Update**
>
> Last updated: [previous date]
>
> **New Patterns Found** (→ locked.md):
> - [Pattern 1]: [brief description]
> - [Pattern 2]: [brief description]
>
> **Tech Stack Changes** (→ project.md):
> - Added: [new dependency]
> - Updated: [changed config]
>
> **Convention Updates** (→ tokens.yaml):
> - [convention change]
>
> **Potentially Outdated** (review recommended):
> - [item that may no longer apply]
>
> How would you like to proceed?"

Use **AskUserQuestion**:
```yaml
question: "How would you like to proceed?"
header: "Update"
options:
  - label: "Apply all updates"
    description: "Update all documentation with findings"
  - label: "Review each change"
    description: "Approve updates one by one"
  - label: "Show me details first"
    description: "See full diff before deciding"
  - label: "Skip for now"
    description: "Keep current documentation"
```

---

### Step 5: Apply Updates

#### 5a. Update project.md

Read current file, update with new findings:

**Update frontmatter:**
```yaml
---
name: [project-name]
type: [ui/cli/api]
package_manager: [detected]
last_updated: [TODAY'S DATE]
---
```

**Update sections with changes:**
- Tech Stack → new dependencies, version updates
- Architecture → directory changes, new entry points
- Conventions → evolved patterns
- File Counts → updated counts

**Preserve:**
- Energy Level (user preference, not detected)
- Quality Philosophy (user preference)
- Any manual additions marked with `<!-- manual -->`

#### 5b. Update locked.md

**Add new patterns:**
```markdown
---

## [New Pattern Name]

**Location:** [example file path]
**Added:** [TODAY'S DATE]

**Description:** [what the pattern is]

**Key elements:**
- [element 1]
- [element 2]

---
```

**Update existing patterns** if implementation has evolved.

**Mark potentially outdated patterns:**
```markdown
## [Pattern Name]

> ⚠️ **Review needed** — This pattern may have changed. Last verified: [original date]

[existing content]
```

#### 5c. Update tokens.yaml (CLI projects)

Update conventions section with any detected changes to naming, file structure, or code style.

#### 5d. Update schemas.md (if applicable)

If new frontmatter patterns detected, add them.

---

### Step 6: Confirm Updates

> "**Documentation Updated**
>
> `.craft/project.md`:
> - Updated: [date]
> - Changes: [summary of what changed]
>
> `.craft/design/locked.md`:
> - Added [N] new patterns
> - Flagged [N] patterns for review
>
> `.craft/design/tokens.yaml`:
> - Updated conventions
>
> Your documentation is now current."

---

## Diff Details (When Requested)

If user selects "Show me details first":

> "**Full Diff**
>
> **project.md changes:**
> ```diff
> - Language: TypeScript (85%)
> + Language: TypeScript (78%)
>
> + - **New dependency:** @tanstack/react-query
> ```
>
> **locked.md additions:**
> ```markdown
> ## API Route Pattern
>
> **Location:** app/api/users/route.ts
>
> All API routes follow this structure...
> ```
>
> **Potentially outdated:**
> - 'Redux Pattern' in locked.md — no Redux imports found in codebase
>
> Apply these changes?"

---

## Manual Sections

To preserve manual additions that shouldn't be overwritten:

```markdown
<!-- manual -->
## Custom Section

This section was added manually and won't be overwritten by update-docs.
<!-- /manual -->
```

Content between `<!-- manual -->` tags is preserved during updates.

---

## Timestamp Format

All documentation files use ISO date in frontmatter:

```yaml
---
last_updated: 2026-02-06
---
```

Check timestamps to know when documentation was last updated:
- Fresh: < 1 month old
- Stale: 1-3 months old
- Outdated: > 3 months old

---

## Remember

- **Non-destructive by default** — shows diff before applying
- **Preserves manual content** — respects `<!-- manual -->` blocks
- **Timestamps everything** — easy to see what's current
- **Flags uncertainty** — marks potentially outdated items for review
- **User approves** — nothing changes without explicit approval
