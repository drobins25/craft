---
name: craft:analyze
description: "Post-cycle analysis — QA, UX, Creative, and Style audits using MCP browser tools."
---

# Analyze

Run comprehensive analysis on what you've built. Findings persist between sessions — nothing gets lost.

## Analysis Types

| Type | Agent | Finds |
|------|-------|-------|
| **QA** | qa-analyzer | Bugs, errors, edge cases |
| **UX** | ux-analyzer | Friction, accessibility, heuristic violations |
| **Creative** | creative-analyzer | Delight opportunities, feature ideas |
| **Style** | style-analyzer | Token violations, pattern drift |
| **Walkthrough** | walkthrough-analyzer | "Does it actually work for a human?" - clicks everything, checks every state |

## Flow

### Step 1: Check Pending Findings

Before any new analysis, check for existing pending findings of the requested type.

**If pending findings exist:**

> "You have [N] pending [type] findings from [date]:
>
> **Critical/High:** [count]
> **Medium:** [count]
> **Low:** [count]
>
> What would you like to do?"

Use **AskUserQuestion**:
```
question: "What would you like to do with pending findings?"
header: "Pending"
options:
  - label: "Review pending findings now"
    description: "Go through existing findings before new analysis"
  - label: "Continue analysis (keep pending)"
    description: "Run new analysis, existing findings stay queued"
  - label: "Clear pending and start fresh"
    description: "Dismiss old findings, start new analysis"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion before proceeding.

**If user chooses "Review pending"** → Go to Step 5 (Review Findings)

**If user chooses "Continue" or "Clear"** → Proceed to Step 2

### Step 2: Select Analysis Type

> "What kind of analysis?"

Use **AskUserQuestion**:
```
question: "What kind of analysis?"
header: "Type"
options:
  - label: "QA Pass"
    description: "Find bugs and errors"
  - label: "UX Insights"
    description: "Usability and accessibility review"
  - label: "Creative Exploration"
    description: "Find delight opportunities"
  - label: "Style Audit"
    description: "Design consistency check"
  - label: "Walkthrough"
    description: "Click everything in the live app, report what doesn't feel right"
```

**Note:** "Full Analysis" runs all types sequentially. If user selects "Other" and mentions "full" or "all", run all types.

**If user provides custom text:** Ask a clarifying AskUserQuestion to confirm which analysis type(s) they want.

### Step 3: Select Scope

> "What should I analyze?"

Use **AskUserQuestion**:
```
question: "What should I analyze?"
header: "Scope"
options:
  - label: "Current cycle"
    description: "All stories in active cycle"
  - label: "Specific story"
    description: "Pick one story from the cycle"
  - label: "Specific pages"
    description: "I'll specify which pages/URLs"
  - label: "Whole application"
    description: "Full app analysis"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to confirm the scope.

**If user selects "Specific pages":**

Use **AskUserQuestion**:
```
question: "Which pages should I analyze?"
header: "Pages"
options:
  - label: "[Known page 1]"
    description: "Based on project structure"
  - label: "[Known page 2]"
  - label: "[Known page 3]"
```

**If scope is ambiguous or Claude is unsure:**

Use **AskUserQuestion**:
```
question: "I want to make sure I analyze the right things. Can you confirm?"
header: "Clarify"
options:
  - label: "[Option based on understanding]"
  - label: "[Alternative interpretation]"
  - label: "Let me explain differently"
```

**IMPORTANT:** Always confirm scope before running analysis. If uncertain about:
- Which URLs to visit
- Which components to inspect
- What user flows to test
- What the acceptance criteria mean

Ask first. Don't assume.

### Step 4: Run Analysis

**Check MCP availability first.** Chrome-devtools MCP should be available — the Craft plugin bundles it automatically.

If chrome-devtools MCP tools are not available:

> "Chrome DevTools MCP should be available through the Craft plugin, but I'm not seeing it.
>
> Try restarting Claude Code (`exit` then `claude`) to reload the plugin's MCP servers.
>
> Then run `/craft:analyze` again."

**If MCP is available**, **INVOKE the appropriate analyzer agent using the Task tool**:
- QA analysis: `craft:qa-analyzer`
- UX analysis: `craft:ux-analyzer`
- Creative analysis: `craft:creative-analyzer`
- Style analysis: `craft:style-analyzer`
- Walkthrough: `craft:walkthrough-analyzer`

Pass the confirmed scope and any relevant context to the agent.

**For walkthrough analysis**, assemble a structured brief before invoking the agent (the agent does NOT read story files - it only interacts with the browser):

1. Read `project.md` for dev server command and port
2. For each `type: ui` story in scope, extract: feature name, trigger, expected behavior
3. Pass the brief with dev server command, URL, test plan, and story context
4. The agent returns findings - you write them to `.craft/analysis/pending/walkthrough.yaml`

**After the agent completes, YOU (the orchestrator) must write findings to disk.**
The analyzer agents have Write/Edit disabled — they return findings in their output text only.

**Write findings to** `.craft/analysis/pending/[type].yaml`:
1. Create `.craft/analysis/pending/` directory if it doesn't exist: `mkdir -p .craft/analysis/pending`
2. Read the existing pending file (if any) to preserve prior findings
3. Parse the agent's output for findings (bugs, issues, opportunities)
4. Append new findings to the YAML file using the template format from `${CLAUDE_PLUGIN_ROOT}/templates/analysis/pending/[type].yaml`
5. Set `updated:` to current date and `scope:` to what was analyzed

**This is critical.** If you don't write findings to disk, they exist only in conversation context and will be lost on compaction.

User can **stop at any time** — write all findings discovered so far before stopping.

**During analysis, Claude should:**
- Narrate what it's checking
- Ask if something unexpected comes up
- Confirm before testing destructive/stateful actions

### Step 5: Review Findings (Two-Phase Triage)

Use a funnel approach: batch filter first, then detailed review only for selected items.

---

#### Phase 1: Batch Filter (Fast)

Show all findings, then use multiSelect in batches of 4 to quickly filter which ones deserve detailed review.

> "**[Type] Analysis Complete — 12 Findings**
>
> | # | Priority | Finding |
> |---|----------|---------|
> | 1 | High | Form accepts invalid email |
> | 2 | High | No loading state on checkout |
> | 3 | Medium | First task completion feels flat |
> | 4 | Low | Button hover state inconsistent |
> | 5 | Medium | Missing skip link for a11y |
> | ... | ... | ... |
>
> Let's quickly filter which ones to review in detail."

**Batch 1/3:**

Use **AskUserQuestion** with `multiSelect: true`:
```
question: "Which findings need detailed review? (1-4)"
multiSelect: true
options:
  - label: "1. Form accepts invalid email (High)"
  - label: "2. No loading state on checkout (High)"
  - label: "3. First task completion flat (Medium)"
  - label: "4. Button hover inconsistent (Low)"
```

**Batch 2/3, 3/3:** Same pattern for remaining findings.

**After all batches, handle unselected:**

```
question: "What about the 7 unselected findings?"
options:
  - label: "Dismiss all"
    description: "Won't come back"
  - label: "Keep for later"
    description: "Stay in pending queue"
```

---

#### Phase 2: Detailed Review (Thorough)

Now go through only the selected findings one-by-one for actual decisions.

> "**5 findings selected for detailed review.**"

**For QA findings:**
> "[1/5] QA Finding: Form accepts invalid email
>
> **Priority:** High
> **Found at:** /login
> **Repro:** Enter 'test' → click submit → form submits
> **Expected:** Validation error
>
> Create story for this?"

Use **AskUserQuestion**:
```
question: "Create story for this QA finding?"
header: "QA"
options:
  - label: "Yes, create story"
    description: "Add to backlog for fixing"
  - label: "Skip (keep for later)"
    description: "Stay in pending queue"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their intent.

**For UX findings:**
> "[2/5] UX Finding: No loading state on checkout
>
> **Priority:** High
> **Heuristic:** Visibility of System Status
> **Problem:** Users click multiple times, causing duplicate orders
>
> **Recommendation:** Add spinner + disable button
> **Alternatives:**
> - A: Optimistic UI with rollback
> - B: Full-page loading overlay
>
> Which approach?"

Use **AskUserQuestion**:
```
question: "Which approach for this UX issue?"
header: "UX"
options:
  - label: "Use recommendation (Recommended)"
    description: "Add spinner + disable button"
  - label: "Alternative A"
    description: "Optimistic UI with rollback"
  - label: "Alternative B"
    description: "Full-page loading overlay"
  - label: "Skip (keep for later)"
    description: "Stay in pending queue"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their preferred approach.

**For Creative findings:**
> "[3/5] Creative Opportunity: First task completion feels flat
>
> **Options:**
> 1. Confetti animation (small effort, high impact) — Recommended
> 2. Achievement badge popup (medium effort)
> 3. Toast message (small effort)
>
> Which approach?"

Use **AskUserQuestion**:
```
question: "Which approach for this delight opportunity?"
header: "Creative"
options:
  - label: "Confetti animation (Recommended)"
    description: "Small effort, high impact"
  - label: "Achievement badge popup"
    description: "Medium effort"
  - label: "Toast message"
    description: "Small effort"
  - label: "Skip (keep for later)"
    description: "Stay in pending queue"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their creative direction.

**For Style findings:**
> "[4/5] Style Violation: Hardcoded colors in Header
>
> **Files:** src/components/Header.tsx (lines 42, 58)
> **Found:** #6B7280, #1F2937
> **Should be:** text-secondary, text-primary
>
> **Fix options:**
> 1. Replace with Tailwind classes — Recommended
> 2. Extract to CSS variables
>
> Which fix?"

Use **AskUserQuestion**:
```
question: "Which fix for this style violation?"
header: "Style"
options:
  - label: "Replace with Tailwind classes (Recommended)"
    description: "Use design system tokens"
  - label: "Extract to CSS variables"
    description: "Create custom properties"
  - label: "Skip (keep for later)"
    description: "Stay in pending queue"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their preferred fix approach.

**For Walkthrough findings:**
> "[5/5] Walkthrough: No toggle on command re-press
>
> **Severity:** feels-off
> **Element:** Command 1 button
> **Steps:** Click Command 1 → card appears. Click Command 1 again → nothing happens.
> **Expected:** Card toggles off or button shows active state
> **Actual:** No visible response on second press
> **Screenshots:** [before, after, re-press]
>
> Create story?"

Use **AskUserQuestion**:
```
question: "Create story for this walkthrough finding?"
header: "Walkthrough"
options:
  - label: "Yes, create story"
    description: "Add to backlog for fixing"
  - label: "Skip (keep for later)"
    description: "Stay in pending queue"
  - label: "Dismiss"
    description: "Not worth fixing"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their intent.

---

**Result:** 12 findings → 5 detailed reviews → stories created for chosen ones.

### Step 6: Create Stories

**6a. Offer story drafting from findings:**

After detailed review, offer batch story creation from accepted findings:

Use **AskUserQuestion**:
```
question: "Draft backlog stories from accepted findings?"
header: "Stories"
options:
  - label: "Draft from high-severity (Recommended)"
    description: "Auto-create stories for high/critical findings"
  - label: "Let me pick"
    description: "Choose which findings become stories"
  - label: "Skip story creation"
    description: "Keep findings pending, no stories"
```

**If "Let me pick":** Use AskUserQuestion with `multiSelect: true` listing accepted findings. Allow user to select subset.

**If user asks to merge findings:** Combine their details (spark, files, criteria) into a single story.

**6b. Generate stories with full context:**

**Duplicate check — before creating each story:**

1. **Exact match:** Scan `.craft/backlog/*.md` frontmatter for `finding_id: [same ID]`. If found → skip: "Story already exists for finding [ID]: [story title]"
2. **Fuzzy match:** Check if any backlog story title shares 3+ keywords with the finding title. If found → warn with AskUserQuestion:
   ```
   question: "Similar story exists: '[existing title]'. Create anyway?"
   header: "Duplicate?"
   options:
     - label: "Skip (it's the same)"
       description: "Don't create duplicate"
     - label: "Create anyway"
       description: "These are different issues"
     - label: "Merge with existing"
       description: "Add finding details to existing story"
   ```
3. **No match:** Create normally.

For each selected finding (that passes duplicate check), create a story:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/create-story.sh "[name]" "[title]"
```

**Naming convention:**
- QA findings: `fix-[kebab-slug]` / `Fix: [title]`
- UX findings: `improve-[kebab-slug]` / `Improve: [title]`
- Creative findings: `enhance-[kebab-slug]` / `Enhance: [title]`
- Style findings: `fix-[kebab-slug]` / `Fix: [title]`
- Walkthrough findings: `fix-[kebab-slug]` / `Fix: [title]`

**After creation, append to the story file:**
- Frontmatter additions: `source: analysis/[type]`, `finding_id: [ID]`, `priority: [mapped]`
- **Severity→priority mapping:** critical→high, high→high, medium→medium, low→low
- Spark section: finding description + steps to reproduce
- Files involved: from finding's file references
- Acceptance criteria: from finding's expected behavior + fix suggestion

**Title integrity check:** After appending fields, verify the title line is properly quoted. Read the `title:` line from the story file. If it contains a colon and is NOT wrapped in quotes (e.g., `title: Fix: broken thing` instead of `title: "Fix: broken thing"`), fix it by wrapping the value in double quotes. This is critical because all analyzer naming conventions use colons (`Fix:`, `Improve:`, `Enhance:`).

**6c. Update finding status:**

Update each finding's status in the pending YAML file:
- `status: story_created` — Story was made
- `status: dismissed` — User chose to dismiss
- `status: pending` — Kept for later

Remove completed/dismissed findings from pending file (or archive them).

### Step 7: Summary

> "Analysis session complete:
>
> **Stories created:** [N]
> - fix-email-validation (high)
> - ux-checkout-loading (high)
> - enhance-first-task-celebration (medium)
>
> **Kept for later:** [N] findings
> **Dismissed:** [N] findings
>
> **Backlog now has [X] total stories.**
>
> What's next?"

Use **AskUserQuestion**:
```
question: "What's next?"
header: "Next"
options:
  - label: "Run another analysis type"
    description: "Continue with different analysis"
  - label: "Review remaining pending"
    description: "Go through kept findings"
  - label: "Start a new cycle"
    description: "Begin implementation planning"
  - label: "Done for now"
    description: "End the analysis run"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their intent.

## Pending Findings Storage

Findings persist in `.craft/analysis/pending/`:

```
.craft/analysis/
├── pending/
│   ├── qa.yaml           ← Bugs with repro steps
│   ├── ux.yaml           ← Suggestions + recommendations
│   ├── creative.yaml     ← Ideas with options
│   ├── style.yaml        ← Violations with fix options
│   └── walkthrough.yaml  ← Interactive usability findings with screenshots
├── screenshots/
│   └── walkthrough/      ← Before/after screenshots from walkthrough
└── reports/              ← Completed analysis reports (optional)
```

See templates in `${CLAUDE_PLUGIN_ROOT}/templates/analysis/` for file formats.

## Quick Commands

Fast analysis with defaults:

```bash
/craft:analyze qa           # QA on current cycle
/craft:analyze ux           # UX on current cycle
/craft:analyze creative     # Creative on current cycle
/craft:analyze style        # Style on current cycle
/craft:analyze walkthrough  # Interactive walkthrough of live app
/craft:analyze full         # All types on current cycle
/craft:analyze pending      # Jump straight to pending review
```

## MCP Browser Access

Analyzer agents access the browser via `chrome-devtools` MCP, declared in their frontmatter (`mcpServers: - chrome-devtools`). This gives them access to the actual chrome-devtools MCP tools:

**Navigation & Pages:**
- `navigate_page` — Go to URLs, reload, back/forward
- `list_pages` / `select_page` — Manage browser tabs
- `new_page` / `close_page` — Open/close tabs

**Interaction:**
- `click` — Click elements by uid
- `fill` / `fill_form` — Type into inputs, select options
- `press_key` — Keyboard shortcuts
- `hover` / `drag` — Mouse interactions

**Inspection:**
- `take_screenshot` — Capture evidence (page or element)
- `take_snapshot` — A11y tree text snapshot (preferred over screenshots)
- `evaluate_script` — Run JS in page context
- `list_console_messages` / `get_console_message` — Console errors/warnings
- `list_network_requests` / `get_network_request` — Network inspection

**Performance:**
- `performance_start_trace` / `performance_stop_trace` — Performance profiling
- `performance_analyze_insight` — Analyze performance insights

**Typical usage by type:**

| Analysis | Primary Tools |
|----------|---------------|
| QA | navigate_page, click, fill, list_console_messages, take_screenshot |
| UX | take_snapshot, navigate_page, click, take_screenshot |
| Creative | take_screenshot, navigate_page, take_snapshot |
| Style | take_snapshot, evaluate_script, take_screenshot |
| Walkthrough | click, take_screenshot, evaluate_script, list_console_messages, resize_page |

All analyzers have the same MCP access — any can use any tool.

## Key Principles

1. **Nothing gets lost** — Findings save as discovered
2. **User controls the pace** — Stop anytime, review anytime
3. **Ask when unsure** — Clarify scope before running
4. **Actionable output** — Each finding has clear next steps
5. **Recommendations included** — Claude suggests, user decides
