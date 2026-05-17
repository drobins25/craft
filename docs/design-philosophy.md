# Craft Design Philosophy — Reference Material

> **Note:** This is a historical record from February 2026. For the current active design specification, see `DESIGN.md`. For command and skill details, see `CLAUDE.md`.

> This is reference material extracted from DESIGN.md. For active instructions, see CLAUDE.md.

---

## Core Principles — Extended Examples

### Suggestions with Reasoning (Example)

```
"For the settings page layout, I see three approaches:

1. **Tabbed sections** (Profile | Billing | Security)
   - Familiar pattern from Linear, Notion
   - Works well for 4-7 sections

2. **Single scroll with anchored nav** ← I'd recommend this
   - Matches your Stripe inspiration
   - Better for forms that span sections
   - Mobile-friendly

3. **Modal-based** (click setting → modal opens)
   - Good for complex individual settings
   - Can feel slow for bulk changes

I'd go with #2 because your inspiration sites use this
pattern and you have cross-section form fields.

Which direction feels right?"
```

### Locked Patterns (Example)

```markdown
# .craft/design/locked.md

## Locked Patterns

### Settings Page Layout (locked 2024-01-31)
- Single scroll with sticky nav
- Section cards with 24px gap
- Form fields use 16px spacing
- Save button fixed bottom on mobile
- Approved screenshot: settings-v1.png

### Button Hover State (locked 2024-01-31)
- Scale: 1.02
- Shadow: elevate from sm to md
- Transition: 150ms ease
- Never change background on hover for primary
```

**Rules:**
- New work must match or exceed locked patterns
- Changing a locked pattern requires explicit story
- Hooks enforce locked patterns automatically

### Quality Evolves Upward (Example)

```yaml
# Story can add, never remove
quality_override:
  additional_gates:
    - payment_security_audit
  additional_polish:
    - animations: required  # Was optional, now required
```

After each cycle, Claude suggests locking improvements:

```
"I noticed we always add loading skeletons even though
it's optional. Lock this in as required?

○ Yes, lock it in
○ Keep optional
○ Required for user-facing only"
```

### Self-Critique (Example)

```
"Here's the preview. Self-critique against our standards:

┌────────────────────────────────────────┐
│ ✓ Layout matches inspiration           │
│ ✓ Colors using tokens                  │
│ ✓ Typography scale correct             │
│ ⚠ Shadow slightly heavier than Stripe  │
│ ⚠ Button hover feels sluggish (200ms)  │
│ ✓ Mobile responsive                    │
│ ✓ Loading skeleton present             │
└────────────────────────────────────────┘

Two things don't match our bar:
1. Shadow: using 'md' but Stripe uses lighter
2. Hover: 200ms feels slow, Stripe uses 150ms

Should I fix these before we continue?

○ Yes, fix both
○ Fix shadow only
○ It's fine, continue"
```

---

## Cycle File Structure

Cycle metadata is pure YAML (no markdown). Stories are discovered by scanning the `stories/` directory.

```yaml
# cycle.yaml
name: auth
title: Authentication System
status: active
created: 2024-01-30
updated: 2024-01-31
target: Ship magic link authentication by Friday
focus: Login, registration, session management

goals:
  - Magic link as primary auth method
  - 5-minute expiry for security
  - Integrate with existing design system

notes: |
  Using existing design system components.
  No social login for MVP.
```

**Stories are NOT listed in cycle.yaml.** They're discovered by scanning `.craft/cycles/[name]/stories/*.md`.
Order is determined by filename prefix: `1-login.md`, `2-registration.md`, `3-sessions.md`.

### Cycle Statuses

| Status | Meaning |
|--------|---------|
| `planning` | Pulling stories in, not yet started |
| `active` | Currently working on stories |
| `paused` | Work paused, can resume |
| `complete` | Done, ready for analysis |
| `archived` | Old cycle, kept for reference |

## Project File Structure (Optional)

Projects group related stories across multiple cycles (like Linear projects).

```markdown
---
name: auth-revamp
status: active
created: 2024-01-15
lead: # optional
---

# Project: Auth Revamp

## Vision
Make authentication feel effortless. Magic link primary, password fallback.

## Stories
| Story | Cycle | Status |
|-------|-------|--------|
| Login Flow | 1-auth | ✓ complete |
| Registration | 1-auth | ◐ active |
| Password Reset | 2-polish | ○ backlog |
| 2FA Setup | — | ○ backlog |

## Decisions
- [x] Magic link as primary auth method
- [x] 5-minute link expiry
- [ ] Mobile deep link support (TBD)

## Notes
Long-running project spanning multiple cycles.
```

---

## Story File Structure

Stories are first-class — create anytime, assign to cycle when ready.

**Backlog story** (minimal, just the idea):
```markdown
---
name: update-modal
status: ready
created: 2024-01-31
project: auth-revamp       # optional: links to larger initiative
priority: medium           # optional: low, medium, high, urgent
---

# Story: Update Login Modal

## Spark
Add password requirements to the login modal.

## Notes
User feedback: "I don't know what password format you need"
```

**Cycle story** (full detail when implementing):
```markdown
---
name: login-flow
status: active
created: 2024-01-30
updated: 2024-01-31
cycle: 1-auth              # which cycle this belongs to
project: auth-revamp       # optional: links to larger initiative
chunks_total: 3
chunks_complete: 2
current_chunk: 3
---

# Story: Login Flow

## Spark
Quick, polished login with magic link as primary, email/pass as fallback.

## Decisions
- [x] Magic link primary (2024-01-30)
- [x] 5-minute expiry (2024-01-30)
- [x] Use existing Button/Input components

## Design
- Layout: Centered card, max-w-md
- Primary action: "Email me a link" button
- Secondary: "Use password instead" text link
- States: loading, success, error with toast

## Chunks
- [x] Chunk 1: LoginPage + route (2 files)
- [x] Chunk 2: Magic link API (2 files)
- [ ] Chunk 3: Fallback form + session (3 files) ← current

## Acceptance
- [x] Can log in via magic link
- [ ] Can fall back to password
- [ ] Session persists across refresh
- [ ] Error states handled gracefully

## Notes
<!-- Implementation notes, learnings, issues encountered -->
```

### Story Statuses

| Status | Meaning |
|--------|---------|
| `backlog` | In backlog, not assigned to cycle |
| `planning` | In cycle, needs plan-chunks before implementation |
| `ready` | In cycle, chunks planned, ready to implement |
| `active` | Currently being implemented |
| `complete` | All chunks done, acceptance met |

---

## Inspiration System

The difference between "AI-generated" and "this is actually good" is inspiration. The Creative Phase pulls from your reference library.

### Sites File (`.craft/inspiration/sites.md`)

```markdown
---
updated: 2024-01-31
---

# Inspiration Sites

## Stripe
- URL: https://stripe.com
- What I like: Clean forms, subtle animations, trust-building copy
- Screenshots: checkout.png, pricing.png

## Linear
- URL: https://linear.app
- What I like: Keyboard-first, information density, dark mode done right
- Screenshots: dashboard.png, issue-view.png

## Vercel
- URL: https://vercel.com
- What I like: Bold typography, gradient usage, deployment flow
- Screenshots: homepage.png
```

### Patterns File (`.craft/inspiration/patterns.md`)

```markdown
# UI Patterns We Follow

## Forms
- Single column, generous spacing
- Inline validation (not on submit)
- Clear error states with recovery hints
- Success = subtle animation + clear next step

## Navigation
- Persistent sidebar for main nav
- Breadcrumbs for deep pages
- Command palette (Cmd+K) for power users

## Empty States
- Never show blank screens
- Illustration + helpful copy + primary action
- Examples: "No projects yet. Create your first one →"

## Loading States
- Skeleton screens, not spinners
- Optimistic updates where possible
- Never leave user wondering "did it work?"
```

### How the Creative Phase Uses Inspiration

```
User: "Build a settings page"

Claude (reading inspiration/):
"Looking at your references...

From Linear: I see you like dense information layouts with
clear section headers.

From Stripe: Clean form patterns with inline validation.

Here's how I'd approach settings:

1. **Sidebar sections** (Profile, Billing, Team, Integrations)
2. **Card-based groups** within each section
3. **Auto-save** with subtle success indicator (like Linear)
4. **Danger zone** at bottom for destructive actions (like GitHub)

Want to riff on any section first, or should I plan chunks?"
```

---

## Design Tokens

Visual consistency enforced via hooks. No more "blue here, green there."

### Tokens File (`.craft/design/tokens.yaml`)

```yaml
# Design tokens - all code must use these
# Hooks will warn on hardcoded values

colors:
  # Primary palette
  primary: "#0066FF"
  primary-hover: "#0052CC"
  primary-light: "#E6F0FF"

  # Neutrals
  background: "#FFFFFF"
  surface: "#F9FAFB"
  border: "#E5E7EB"
  text-primary: "#111827"
  text-secondary: "#6B7280"
  text-muted: "#9CA3AF"

  # Semantic
  success: "#10B981"
  warning: "#F59E0B"
  error: "#EF4444"
  info: "#3B82F6"

spacing:
  unit: 4px
  xs: 4px      # 1 unit
  sm: 8px      # 2 units
  md: 16px     # 4 units
  lg: 24px     # 6 units
  xl: 32px     # 8 units
  2xl: 48px    # 12 units

radius:
  sm: 4px
  md: 8px
  lg: 12px
  full: 9999px

typography:
  font-sans: "Inter, -apple-system, sans-serif"
  font-mono: "JetBrains Mono, monospace"

  # Scale (px)
  text-xs: 12
  text-sm: 14
  text-base: 16
  text-lg: 18
  text-xl: 20
  text-2xl: 24
  text-3xl: 30

  # Weights
  weight-normal: 400
  weight-medium: 500
  weight-semibold: 600
  weight-bold: 700

shadows:
  sm: "0 1px 2px rgba(0,0,0,0.05)"
  md: "0 4px 6px rgba(0,0,0,0.07)"
  lg: "0 10px 15px rgba(0,0,0,0.1)"

transitions:
  fast: "150ms ease"
  normal: "200ms ease"
  slow: "300ms ease"
```

### Components File (`.craft/design/components.md`)

```markdown
# Component Patterns

## Buttons

### Primary
- Background: primary
- Text: white
- Padding: sm horizontal, xs vertical
- Radius: md
- Hover: primary-hover
- Disabled: 50% opacity, no pointer

### Secondary
- Background: transparent
- Border: 1px border color
- Text: text-primary
- Hover: surface background

### Sizes
- sm: text-sm, padding xs/sm
- md: text-base, padding sm/md (default)
- lg: text-lg, padding md/lg

## Inputs

- Border: 1px border
- Radius: md
- Padding: sm
- Focus: 2px primary ring
- Error: error border + error text below
- Disabled: surface background

## Cards

- Background: background
- Border: 1px border
- Radius: lg
- Padding: lg
- Shadow: sm (hover: md)
```

### Token Enforcement (Hook)

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{
        "type": "prompt",
        "prompt": "Check if this code uses hardcoded colors (hex/rgb), spacing (px values), or font sizes instead of design tokens from .craft/design/tokens.yaml. If found, suggest the correct token. Only flag clear violations, not edge cases. Respond with JSON: {\"decision\": \"allow\"} if no violations, or {\"decision\": \"block\", \"reason\": \"Found hardcoded [value] — use token [name] instead\"} if violations found."
      }]
    }]
  }
}
```

---

## Locked Patterns — Detailed Examples

### Locked Patterns File (`.craft/design/locked.md`)

```markdown
---
updated: 2024-01-31
total_patterns: 5
---

# Locked Patterns

These patterns have been approved as "perfect" and are now the standard.
Changing a locked pattern requires an explicit story.

---

## Settings Page Layout
**Locked:** 2024-01-31 | **Story:** 1-settings-page

### Pattern
- Single scroll with sticky section nav
- Section cards with `spacing.lg` (24px) gap
- Form fields use `spacing.md` (16px) internal spacing
- Save button fixed to bottom on mobile
- Section headers use `text-xl` + `weight-semibold`

### Screenshot
![Settings approved](screenshots/settings-v1-approved.png)

### Code Reference
`src/app/settings/page.tsx`

---

## Button Hover State
**Locked:** 2024-01-31 | **Story:** 1-login-flow

### Pattern
- Transform: scale(1.02)
- Shadow: elevate from `shadows.sm` to `shadows.md`
- Transition: `transitions.fast` (150ms)
- Primary buttons: NEVER change background color on hover
- Secondary buttons: background → `surface`

### Code Reference
`src/components/ui/button.tsx:42-58`

---

## Toast Notifications
**Locked:** 2024-01-31 | **Story:** 2-registration

### Pattern
- Position: bottom-right (desktop), bottom-center (mobile)
- Duration: 4s default, 6s for errors
- Animation: slide up 16px + fade in
- Always include dismiss button
- Success: include subtle checkmark icon
- Error: include retry action when applicable

### Code Reference
`src/components/ui/toast.tsx`

---

## Empty States
**Locked:** 2024-02-01 | **Story:** 3-dashboard

### Pattern
- Centered vertically in container
- Illustration: 120px max height, muted colors
- Headline: `text-lg` + `weight-medium`
- Description: `text-secondary`, max 2 lines
- Primary action button below (not link)
- Never show "No data" — always explain + guide

### Example Copy
```
[illustration]
No projects yet
Projects help you organize related work.
[Create your first project →]
```

### Code Reference
`src/components/ui/empty-state.tsx`
```

### How Locking Works

**During implementation:**
```
Claude: "This settings layout looks great. Ready to lock
this as the standard for future settings pages?

○ Yes, lock it
○ Not yet, might iterate more
○ Lock with modifications"
```

**Enforcement via hook:**
```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{
        "type": "prompt",
        "prompt": "Check if this code creates UI that should follow a locked pattern from .craft/design/locked.md. If a locked pattern applies (e.g., creating a settings page, button, toast, empty state), verify the implementation matches. Respond with JSON: {\"decision\": \"allow\"} if no locked pattern applies or implementation matches, or {\"decision\": \"block\", \"reason\": \"Deviates from locked pattern [name] — see .craft/design/locked.md\"} if deviations found."
      }]
    }]
  }
}
```

**Changing a locked pattern:**
```
User: "I want to change how button hovers work"

Claude: "Button hover is a locked pattern (locked 2024-01-31).
To change it, we should:

1. Create a story: 'Update button hover pattern'
2. Design the new pattern together
3. Update all existing buttons
4. Lock the new pattern

Want me to create that story in the backlog?"
```

---

## Project DNA

Every agent reads this. Consistency across all stories.

### Project File (`.craft/project.md`)

```markdown
---
name: MyApp
updated: 2024-01-31
---

# Project DNA

## Tech Stack

### Frontend
- **Framework**: Next.js 14 (App Router)
- **Styling**: Tailwind CSS + shadcn/ui
- **State**: Zustand for client, React Query for server
- **Forms**: react-hook-form + zod validation

### Backend
- **API**: Next.js API routes (REST)
- **Database**: Postgres via Prisma
- **Auth**: NextAuth.js with magic link
- **Storage**: Vercel Blob

### Infrastructure
- **Hosting**: Vercel
- **CI/CD**: GitHub Actions
- **Monitoring**: Sentry

## Code Patterns

### File Organization
```
src/
├── app/                 # Next.js app router
├── components/
│   ├── ui/              # shadcn components
│   └── [feature]/       # Feature-specific
├── lib/                 # Utilities
├── hooks/               # Custom hooks
└── types/               # TypeScript types
```

### Naming Conventions
- Components: PascalCase (`UserProfile.tsx`)
- Hooks: camelCase with `use` prefix (`useAuth.ts`)
- Utilities: camelCase (`formatDate.ts`)
- Types: PascalCase with suffix (`UserDTO`, `AuthState`)

### API Patterns
- All routes return: `{ data, error, meta }`
- Use Zod for request validation
- Wrap handlers with error boundary
- Log errors to Sentry

### Component Patterns
- Server components by default
- 'use client' only when needed
- Colocate styles, tests, stories
- Extract hooks for complex logic

## Voice & Copy

### Tone
- Friendly but professional
- Clear, not clever
- Helpful, not condescending

### Error Messages
- Say what happened
- Say why (if known)
- Say how to fix it
- Example: "Couldn't save changes. You're offline. We'll retry when you're back."

### Empty States
- Acknowledge the emptiness
- Explain the benefit of adding content
- Provide clear action
- Example: "No projects yet. Projects help you organize your work. Create your first one →"

### Success Messages
- Confirm the action
- Subtle celebration
- Clear next step (if any)
- Example: "Saved! ✓" or "Welcome aboard! Let's set up your workspace →"

## Preferences

### Do This
- Use existing shadcn components before creating new ones
- Prefer server components
- Use `cn()` for conditional classes
- Handle loading, error, empty states for every async operation

### Don't Do This
- Don't use inline styles
- Don't create new color variables (use tokens)
- Don't skip TypeScript types
- Don't leave console.logs in production code
```

---

## Quality Profiles

What "complete" actually means. **Pristine by default** — industry-leading, not "good enough."

### Quality File (`.craft/quality.yaml`)

```yaml
# Quality philosophy - sets the bar
philosophy: pristine
# pristine = industry-leading (Stripe, Linear, Vercel level)
# This is the ONLY default. We don't ship mediocre.

# Visual standards (all required)
standards:
  visual:
    pixel_perfect_alignment: true
    consistent_spacing: true        # Tokens only, no magic numbers
    smooth_animations: true         # 60fps, 150ms default
    responsive: true                # Mobile-first, all breakpoints

  interaction:
    loading_feedback: skeleton      # Skeletons, not spinners
    optimistic_updates: true        # Where safe
    error_recovery: true            # Help fix, not just display
    keyboard_navigable: true
    touch_targets: 44px             # Minimum

  performance:
    core_web_vitals: green
    bundle_size: monitored
    lazy_loading: below_fold

  accessibility:
    wcag_level: AA
    screen_reader_tested: true
    color_contrast: verified
    focus_indicators: visible

# Gates - all must pass
gates:
  typecheck:
    enabled: true
    command: "npm run typecheck"

  lint:
    enabled: true
    command: "npm run lint"
    fix_automatically: true

  format:
    enabled: true
    command: "npm run format:check"
    fix_automatically: true

  tests:
    enabled: true
    scope: "affected"
    command: "npm run test -- --changed"
    coverage_threshold: 80          # High bar

  accessibility:
    enabled: true
    tool: "axe-core"
    level: "AA"

  build:
    enabled: true
    command: "npm run build"

# Polish requirements - ALL required for pristine
polish:
  loading_states:
    required: true
    style: skeleton                 # Not spinners

  error_handling:
    required: true
    style: recovery                 # Help user fix, not just show error

  empty_states:
    required: true
    style: helpful                  # Illustration + action + copy

  keyboard_navigation:
    required: true

  responsive:
    required: true
    breakpoints: ["mobile", "tablet", "desktop"]

  animations:
    required: true                  # YES required for pristine
    style: subtle                   # Micro-interactions, not flashy

# Approval model - nothing happens without user consent
approval:
  before_implementation: true
  after_each_chunk: true
  before_complete: true
  before_locking_pattern: true

# Claude self-critique before complete
self_critique:
  enabled: true
  compare_against:
    - inspiration_sites
    - locked_patterns
    - design_tokens
  must_acknowledge_gaps: true       # Can't hide issues

# Preview before complete
preview:
  enabled: true
  generate_url: true
  capture_screenshot: true
  responsive_check: ["mobile", "desktop"]

# Human review
review:
  required_for: ["complete"]
  checklist:
    - "Matches design intent"
    - "Matches or exceeds locked patterns"
    - "Works on mobile"
    - "Error states tested"
    - "Copy is clear and helpful"
    - "Would I be proud to show this?"
```

### Quality Check Flow

```
Story implementation done
         ↓
┌─────────────────────────────┐
│  QUALITY GATES              │
│                             │
│  ✓ Typecheck passing        │
│  ✓ Lint passing             │
│  ✓ Tests passing (82%)      │
│  ✓ Accessibility (0 issues) │
│  ✓ Build successful         │
└─────────────────────────────┘
         ↓
┌─────────────────────────────┐
│  POLISH CHECK               │
│                             │
│  ✓ Loading states           │
│  ✓ Error handling           │
│  ⚠ Empty state missing      │  ← Blocks completion
│  ✓ Keyboard nav             │
│  ✓ Responsive               │
└─────────────────────────────┘
         ↓
     Fix empty state
         ↓
┌─────────────────────────────┐
│  PREVIEW                    │
│                             │
│  URL: https://preview.vercel│
│  Screenshot saved           │
└─────────────────────────────┘
         ↓
     Human review
         ↓
   Story → complete
```

---

## Terminal Experience

### Status Display (Rich)

```
/craft status

┌─────────────────────────────────────────────────────────────┐
│  CRAFT                                               $2.47  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ● Cycle 1: Auth                                   active   │
│  ├── ✓ Login Flow                               complete    │
│  ├── ◐ Registration                      chunk 2/3  ███░░   │
│  └── ○ Session Management                     ready         │
│                                                             │
│  ○ Cycle 2: Dashboard                          planning     │
│  └── 2 stories planned                                      │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  Backlog: 4 stories                                         │
│  ├── update-modal (high priority)                           │
│  ├── refactor-api                                           │
│  └── +2 more                                                │
└─────────────────────────────────────────────────────────────┘
```

### Quick Commands

```bash
# Status
/s              # Current story details
/c              # Current cycle overview
/b              # Backlog list
/status         # Full dashboard (above)

# Navigation
/next           # Move to next story
/pick [story]   # Pick specific story from backlog/cycle
/pause          # Pause current story, save state

# Preview
/preview        # Open preview URL in browser
/screenshot     # Capture current state

# Quick actions
/chunk done     # Mark current chunk complete
/story done     # Mark story complete (runs quality gates)
/cycle done     # Complete cycle (runs analysis prompt)

# Creative
/riff           # Enter Creative Phase for current story
/inspire        # Show relevant inspiration

# Meta
/cost           # Session cost breakdown
/time           # Time spent on current story
```

### Status Line (Always Visible)

```
[auth] ◐ Registration | chunk 2/3 | $1.42
```

Format: `[cycle] status story | progress | cost`

Status indicators:
- `○` ready
- `◐` in progress
- `✓` complete
- `⚠` blocked
- `✗` failed

### Progress Notifications

```
──────────────────────────────────────────────
  ✓ Chunk 2 complete: Magic link API

  Quality: ✓ types ✓ lint ✓ tests

  Next: Chunk 3 - Fallback form + session

  Continue? (Y/n/riff/pause)
──────────────────────────────────────────────
```

### Preview Integration

```
/preview

  Opening preview...

  ┌────────────────────────────────────┐
  │  ┌──────────────────────────────┐  │
  │  │                              │  │
  │  │   [Login Page Preview]       │  │
  │  │                              │  │
  │  └──────────────────────────────┘  │
  │                                    │
  │  URL: https://myapp-git-auth.vercel│
  │  Mobile: ✓  Tablet: ✓  Desktop: ✓  │
  └────────────────────────────────────┘

  Looks good? (y/n/notes)
```

---

## Mode Transitions (via AskUserQuestion)

**After `/craft` or starting a conversation:**
```
"What are we working on?"
[User describes task]

→ Creates story in backlog

"Work on it now or save for later?"
○ Work on it now — assign to Cycle 1 (active)
○ Save in backlog — I'll get to it later
○ Start a new cycle for this
```

**After assigning to cycle:**
```
"How much detail do you have?"
○ Just the idea — let's riff (With Creative-Spark)
○ I know what I want — plan the chunks (Skip Creative-Spark)
```

**After completing a story:**
```
"Story done! What's next?"
○ Next story in cycle
○ Pull something from backlog
○ Analyze what we built
○ Take a break
```

**After completing a cycle:**
```
"Cycle complete! What's next?"
○ Start a new cycle
○ Run analysis (QA, UX, Creative, Style)
○ Review backlog
```

**Commands as shortcuts:**
- `/craft:story-new` → Create story (lands in backlog)
- `/craft:story-implement` → Pick story and implement
- `/craft:cycle-assign` → Move backlog story to cycle
- `/craft:analyze` → Jump to Analysis Phase

---

## MCP Integration

### Servers

| Server | Purpose |
|--------|---------|
| `chrome-devtools` | Inspection, accessibility audits, Lighthouse, console logs |
| `playwright` | Browser automation, screenshots, E2E testing |

### Chrome DevTools MCP (26 tools)

- `navigate`, `screenshot`, `get_console_logs`
- `inspect_element`, `accessibility_audit`, `lighthouse`
- `get_network_requests`, `evaluate`

### Analysis Phase Use Cases

| Analysis | MCP Tools Used |
|----------|----------------|
| QA Pass | `get_console_logs`, `screenshot`, form testing |
| UX Insights | `accessibility_audit`, `lighthouse`, viewport testing |
| Creative Explore | `screenshot` references, competitor analysis |
| Style Audit | `inspect_element`, computed styles |

---

## Reflection System

Continuously improve the project's Claude harness as we learn.

### What Gets Reflected

- CLAUDE.md updates (patterns discovered, conventions established)
- New rules (from repeated mistakes)
- Hook improvements (common validations)
- Skill refinements (better prompts)

### When Reflection Happens

- After each cycle completes
- When human corrects something
- When validation catches repeated issues
- On explicit `/reflect` command

### Reflection Output

```markdown
## Suggested Harness Updates

### CLAUDE.md
+ Add: "Always use absolute imports (@/...)"
+ Add: "Toast errors go through useToast hook"

### New Rule
- "API routes must have error boundary"

### Hook Improvement
- Add eslint --fix to post-edit hook
```

---

## Post-Cycle Analysis Details

### QA Pass

```markdown
## QA Report: Auth Revamp

### Bugs Found
1. **Magic link expires silently** - No user feedback when link expires
   - Severity: Medium
   - Repro: Wait 6 minutes, click link

2. **Password field autocomplete broken** - Safari doesn't suggest saved passwords
   - Severity: Low
   - Repro: Use Safari, focus password field

### Suggested Cycle
"Auth Polish" - 2 stories to fix above
```

### UX Insights (Nielsen + Industry Standards)

```markdown
## UX Insights: Auth Revamp

### Nielsen Heuristics
| Principle | Score | Issue |
|-----------|-------|-------|
| Visibility of system status | ⚠️ | No loading indicator on magic link send |
| Error prevention | ✓ | Good email validation |
| Recognition over recall | ⚠️ | "Check your email" could show which email |

### Mental Model Check
- Login page clear without header? ⚠️ Needs visual hierarchy
- Is magic link concept obvious? ❌ "Email me a link" clearer than "Magic link"

### Interaction Opportunities
- Swipe between login/register tabs instead of clicking
- Subtle success animation on login
- "Login with face" prompt on supported devices

### Suggested Cycle
"Auth UX Polish" - 4 micro-stories
```

### Creative Exploration

```markdown
## Creative Ideas: Post Auth-Revamp

### Viral/Social Potential
- "Share your profile setup" moment after registration
- Referral code integration at signup
- "X just joined!" social proof

### Delight Moments
- Confetti on first successful login
- Personalized welcome based on signup source
- "You're user #1,247" badge

### Suggested Cycle
"Auth Delight" - exploratory, pick 2-3
```

### Style Audit

```markdown
## Style Audit: Auth Revamp

### Inconsistencies Found
- Button padding: 12px on login, 16px on register
- Two different grays: #6b7280 and #71717a
- Old Input component on forgot-password (pre-design-system)

### Technical Debt
- Inline styles on magic-link-sent.tsx
- Duplicate validation logic (form.ts and api.ts)

### Suggested Cycle
"Auth Cleanup" - 3 small stories
```

---

## Detailed State Management

### Global State (`.craft/.global-state`)

```bash
ACTIVE_CYCLE="1-auth"
CURRENT_STORY=""
DEFAULT_MODE="creative"
LAST_ACTIVITY="2024-01-31T10:30:00Z"
BACKLOG_COUNT=3
```

### Cycle State (`.craft/cycles/{cycle}/.state`)

```bash
CYCLE_NAME="auth"
CYCLE_STATUS="active"
CURRENT_STORY="2-registration"
CURRENT_CHUNK=2
TOTAL_CHUNKS=3
LAST_VALIDATION="2024-01-31T10:25:00Z"
LAST_CHECKPOINT="2024-01-31T10:20:00Z"
```

### How State Passes Between Agents

#### 1. Explicit Handoff (Prompt)

```markdown
Task prompt to implementer:

"Implement chunk 2 of story 'login-flow'.

**Context from planning:**
- Magic link primary, password fallback
- Use existing Button/Input components

**Previous chunk completed:**
- Chunk 1 created LoginPage shell and route
"
```

#### 2. File-Based State (Primary)

```
.craft/1-auth/
├── epic.md                    ← Decisions, status, open questions
├── .state                     ← Machine-readable current state
└── stories/
    └── 1-login-flow.md        ← Story details, chunk progress
```

#### 3. CLAUDE_ENV_FILE (Session Persistence)

```bash
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'export CURRENT_STORY="1-login-flow"' >> "$CLAUDE_ENV_FILE"
fi
```

#### 4. Dynamic Skills with backticks

```yaml
---
name: craft-context
---

Current branch: !`git branch --show-current`
Craft status: !`cat .craft/.global-state 2>/dev/null`
Recent changes: !`git diff --stat HEAD~3..HEAD`
```

### State Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  ORCHESTRATOR                                                   │
│  (maintains high-level state, delegates to agents)              │
└─────────────────────────────────────────────────────────────────┘
           │
           │ Spawns with explicit context
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  IMPLEMENTER AGENT                                              │
│  (isolated context, focused on one chunk)                       │
│                                                                 │
│  On complete: writes progress to story file                     │
└─────────────────────────────────────────────────────────────────┘
           │
           │ Returns summary + updates files
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  FILE STATE (source of truth)                                   │
│  - Chunk 1: ✓ complete                                          │
│  - Chunk 2: ✓ complete  ← just updated                          │
│  - Chunk 3: ○ pending                                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Project Init Design

### Phase 1: Vibe Check

```
/project init

AskUserQuestion: "What are we working with?"
○ Fresh project with inspiration (reference site) → Phase 2
○ Fresh project from scratch → Skip to Phase 3
○ Existing codebase → Analyze mode

AskUserQuestion: "What's the energy?"
○ Move fast, break things (startup mode) → Lighter guardrails
○ Steady and solid (production mode) → More checkpoints
○ Learning/exploring (experimental mode) → Teaching mode
```

### Phase 2: Inspiration (if reference chosen)

```
[MCP chrome-devtools]
- Screenshot key pages
- Extract color palette, typography, patterns

[AskUserQuestion checkpoint]
"Here's what I found. How does it look?"
○ Looks good, continue
○ Adjust some values
○ Skip, I'll define manually

[Generate]
- .claude/skills/{project}-styles.md
- .claude/skills/{project}-patterns.md
```

### Phase 3: Harness Setup

```
[Create structure]
.claude/
├── CLAUDE.md                 ← Tailored to project energy
├── rules/
│   ├── code-style.md
│   ├── typescript.md
│   └── testing.md
├── skills/
│   └── {generated skills}
├── hooks/
│   ├── inject-context.sh
│   └── update-progress.sh
└── settings.json
    ├── statusLine config
    └── preapproved permissions

.craft/
└── (ready for first epic)
```

### Phase 4: First Epic Kickoff

```
AskUserQuestion: "What's the first thing we're tackling?"
[Free text]

→ Creates .craft/1-{epic-name}/epic.md
→ Enters Creative Phase
→ Starts riffing on first stories
```

### Harness Adapts to Energy

| Energy | CLAUDE.md Tone | Hooks | Checkpoints |
|--------|----------------|-------|-------------|
| **Move fast** | Minimal, momentum-focused | Light validation | Ask only when weird |
| **Steady solid** | Thorough, production-ready | Full validation + tests | Checkpoint each chunk |
| **Learning** | Educational, explanatory | Same + teach mode | Explain decisions |

---

## Creative Features

### Status Line Control

```json
{
  "statusLine": {
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/hooks/statusline.sh"
  }
}
```

```bash
#!/bin/bash
input=$(cat)
COST=$(echo "$input" | jq -r '.cost.total_cost_usd')

if [ -f ".craft/.global-state" ]; then
  source .craft/.global-state
  printf "[%s] Story %s | Chunk %s/%s | $%.2f" \
    "$CRAFT_NAME" "$CURRENT_STORY" "$CURRENT_CHUNK" "$TOTAL_CHUNKS" "$COST"
else
  printf "No active cycle | $%.2f" "$COST"
fi
```

### Prompt-Based Hooks (AI Decides)

Use LLM evaluation instead of bash scripts. **Critical:** Prompt hooks must explicitly require JSON response format with `ok` boolean field.

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "prompt",
        "prompt": "Session ending. Review for harness improvements.\n\nLook for:\n1. Patterns used 2+ times → add to CLAUDE.md\n2. Repeated corrections → create rule or hook\n\nRespond with JSON only:\n- If improvements found: {\"ok\": false, \"reason\": \"Before ending, run /craft:reflect to capture: [list]\"}\n- If nothing to capture: {\"ok\": true}",
        "timeout": 30000
      }]
    }]
  }
}
```

**How it works:** When `ok: false`, the `reason` becomes Claude's next instruction, triggering the workflow.

### Subagent Colors

```yaml
# creative-spark agent
color: cyan

# implementer agent
color: blue

# tester agent
color: yellow
```

### Dynamic Skill Content

Commands execute BEFORE Claude sees the skill:

```yaml
---
name: craft-context
---

Current branch: !`git branch --show-current`
Craft status: !`cat .craft/.global-state 2>/dev/null`
Recent changes: !`git diff --stat HEAD~3..HEAD`
```

### UserPromptSubmit Hook

```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "~/.claude/hooks/inject-craft-context.sh"
      }]
    }]
  }
}
```

### PostToolUseFailure Hook

```json
{
  "hooks": {
    "PostToolUseFailure": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "prompt",
        "prompt": "Command failed. Analyze the error and determine next steps. Respond with JSON: {\"decision\": \"retry\", \"command\": \"corrected command here\"} to retry with a fix, or {\"decision\": \"ask_human\", \"reason\": \"explanation of what went wrong\"} to escalate."
      }]
    }]
  }
}
```

### PreCompact Hook

```json
{
  "hooks": {
    "PreCompact": [{
      "hooks": [{
        "type": "command",
        "command": "~/.claude/hooks/export-progress.sh"
      }]
    }]
  }
}
```

### HTML Dashboards

```yaml
---
name: craft-dashboard
---

Generate interactive craft dashboard and open in browser.
```

---

## Edge Cases & Recovery

### Resume Flows

**Scenario:** User closes Claude mid-story. What happens?

**Approach:**
- Files are source of truth
- `/story continue` reads `.state` file and story file
- Reconstructs: "You were on chunk 2 of 3. Chunk 1 complete. Continue?"
- PostToolUse hooks ensure progress is always saved

**To resolve during build:**
- [ ] Define exact `.state` file format
- [ ] Implement `/story continue` command
- [ ] Test mid-chunk resume (partial file edits)

### Conflict Detection (Parallel Stories)

**Scenario:** Parallel stories 2a and 2b accidentally touch same file.

**Approach:**
- `plan-chunks` skill checks file overlap before approving parallel
- If overlap detected: "Stories 2a and 2b both touch `auth.ts`. Run sequentially or split?"
- Runtime check: if implementer tries to edit file another agent touched, warn

**To resolve during build:**
- [ ] Implement file overlap detection in plan-chunks
- [ ] Add touched-files tracking to `.state`
- [ ] Define conflict resolution UX

### Story Dependencies

**Scenario:** Story 3 depends on story 2a completing first.

**Approach:**
- Already in epic.md: "blocked by 2a" in Notes column
- `blocked` status prevents `/story implement` on blocked stories
- When 2a completes, auto-update 3 to `ready`

**To resolve during build:**
- [ ] Parse dependencies from epic.md
- [ ] Implement status auto-transitions
- [ ] Handle circular dependency detection

### Hard Failures

**Scenario:** Implementation fails completely (tests crash, build broken).

**Approach:**
- Checkpoint exists → offer rollback
- "Build is broken after chunk 2. Rollback to checkpoint? Or debug together?"
- If rollback: restore files, mark chunk as `failed`, ask human for guidance
- Never silently continue with broken state

**To resolve during build:**
- [ ] Define failure detection criteria
- [ ] Implement rollback UX
- [ ] Add `failed` chunk status

### Context Compaction

**Scenario:** Long session, context gets compacted, state lost.

**Approach:**
- PreCompact hook exports critical state to files
- Dynamic skills re-inject state on next message
- State reconstruction from files always possible

**To resolve during build:**
- [ ] Identify critical state to preserve
- [ ] Implement PreCompact export
- [ ] Test post-compaction recovery

### Stale State

**Scenario:** User manually edits files outside Claude, state file outdated.

**Approach:**
- On `/craft run` or `/story implement`, verify state matches reality
- Compare `.state` timestamps with file modification times
- "Story file was modified. Resync state? Or continue with current?"

**To resolve during build:**
- [ ] Add file modification tracking
- [ ] Implement state verification
- [ ] Define resync UX

### First-Time User

**Scenario:** New user runs plugin, unfamiliar with concepts.

**Approach:**
- `/project init` is the guided entry point
- "Learning/exploring" energy mode enables teaching mode
- Each AskUserQuestion includes brief context
- `/help` command explains concepts

**To resolve during build:**
- [ ] Write help content
- [ ] Implement teaching mode variations
- [ ] Test with fresh user perspective

---

## Hook Best Practices (from research)

- Keep hooks fast and scoped (don't slow down agent loop)
- Exit code 2 to block with message to Claude
- PreToolUse can modify tool inputs (v2.0.10+)
- Use matchers: `"Edit|MultiEdit|Write"` for file modifications
- Store hooks in `.claude/hooks/` as standalone scripts

---

## Research Findings

### Claude's Current Capabilities (2025-2026)

- Claude Opus 4.5 maintains focus for 30+ hours on complex tasks
- Near-zero navigation errors in autonomous development
- Extended thinking + tool use (System 2 reasoning)
- Subagents can delegate specialized tasks in parallel
- Checkpoints enable instant rollback

### Industry Innovations

- **Vibe Coding** (Karpathy): Stay in creative flow, don't fight syntax
- **Multi-Agent Parallelism**: Cursor 2.0 runs 8 concurrent agents
- **Git Worktrees**: Prevent conflicts in parallel agent work
- **Accessibility Gap**: Senior+ engineers use parallel agents well—opportunity to make approachable

### MCP Ecosystem

- Chrome DevTools MCP: 26 specialized tools for debugging/analysis
- Adopted by OpenAI, donated to Linux Foundation
- De-facto standard for connecting agents to tools
- 2025 spec: servers can ask users for input mid-session

---

## Open Questions

- [x] Project init: What scaffolding approach? → Designed (see Project Init Design section)
- [ ] Git worktrees for parallel stories? (Future enhancement)
- [ ] Voice input for creative mode? (Superwhisper integration - future)
- [ ] Background agents while reviewing? (Future enhancement)

---

## Implementation Checklist

### Phase 0: Foundation
- [ ] Plugin scaffold (plugin.json, directory structure)
- [ ] `/project init` command (vibe check, harness setup)
- [ ] `/craft` command (main entry point with AskUserQuestion routing)
- [ ] `/craft status` command (rich dashboard display)
- [ ] Status line configuration (always visible)
- [ ] Base hooks (inject-context, update-progress)
- [ ] `.global-state` and `.state` file management
- [ ] Backlog folder setup
- [ ] Quick commands (`/s`, `/c`, `/b`, `/next`)

### Phase 1: Core Loop
- [ ] Story file structure (backlog and cycle stories)
- [ ] Cycle file structure
- [ ] `/story new` command (create story in backlog)
- [ ] `/cycle new` command (create new cycle)
- [ ] `/cycle assign` command (move story to cycle)
- [ ] Creative mode skills (creative-spark, design-vibe, lock-decision)
- [ ] `plan-chunks` skill
- [ ] Implementer agent (owns chunk loop)
- [ ] `/story implement` command
- [ ] `/story continue` command
- [ ] Mode transition prompts (AskUserQuestion flows)
- [ ] Progress notifications between chunks

### Phase 2: Project DNA & Design System
- [ ] `project.md` template and setup during init
- [ ] Design tokens (`tokens.yaml`) setup
- [ ] Components patterns (`components.md`) setup
- [ ] Locked patterns (`locked.md`) setup
- [ ] Token enforcement hook (PreToolUse)
- [ ] Locked pattern enforcement hook (PreToolUse)
- [ ] Project DNA injection into agent context
- [ ] Pattern locking flow (approval → lock → enforce)

### Phase 3: Inspiration System
- [ ] `inspiration/` folder structure
- [ ] `sites.md` for reference URLs
- [ ] `patterns.md` for UI patterns
- [ ] Screenshot capture via MCP
- [ ] Creative Phase reads inspiration for context
- [ ] `/inspire` command

### Phase 4: Quality Gates & Approval Model
- [ ] `quality.yaml` configuration (pristine default)
- [ ] Gate runner (typecheck, lint, tests, a11y, build)
- [ ] Polish checker (loading states, errors, empty states, animations)
- [ ] Claude self-critique system (compare against inspiration + locked patterns)
- [ ] Preview generation (URL + screenshot)
- [ ] Approval checkpoints (before impl, after chunk, before complete)
- [ ] Human review checklist
- [ ] Quality report display
- [ ] Block completion if gates fail
- [ ] Per-story quality overrides (can only ADD requirements)

### Phase 5: Polish & Parallel
- [ ] Project file structure (optional multi-cycle grouping)
- [ ] Tester agent
- [ ] Parallel story execution (max 2)
- [ ] Conflict detection
- [ ] Full hooks (validate, progress, failure recovery)
- [ ] Story move between backlog/cycles
- [ ] `/preview` command

### Phase 6: Analysis
- [ ] MCP integration (chrome-devtools, playwright)
- [ ] `/analyze` command
- [ ] QA Pass mode
- [ ] UX Insights mode
- [ ] Creative Exploration mode
- [ ] Style Audit mode
- [ ] Analysis outputs → new backlog stories

### Phase 7: Reflection
- [ ] `/reflect` command
- [ ] Reflection system (prompt-based hook on Stop)
- [ ] CLAUDE.md auto-update suggestions
- [ ] Rule suggestions
- [ ] Hook improvement suggestions

---

## Plugin Directory Structure

```
craft-plugin/
├── plugin.json
├── CLAUDE.md
├── DESIGN.md                    ← Actionable summary
├── reference/
│   ├── design-philosophy.md     ← This file (detailed reference)
│   ├── decision-tree.md         ← Routing logic
│   └── plan-tdd-enforcement.md  ← TDD enforcement details
├── commands/
├── skills/
├── agents/
├── hooks/
│   ├── inject-context.sh
│   └── update-progress.sh
└── settings.json
```

---

## Inspiration Sources

- **Code Captain**: Contract-first, structured specs (too heavy, but good patterns)
- **Project Scaffold**: Reference-based initialization, MCP browser analysis
- **Vibe Coding**: Flow-preserving creative development
- **Cursor 2.0**: Multi-agent orchestration patterns
- **RIPER Workflow**: Research → Innovate → Plan → Execute → Review phases
- **Agentic Design Patterns**: Progressive disclosure, confidence visualization, mixed-initiative controls
