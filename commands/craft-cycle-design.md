---
name: craft:cycle-design
description: "Design a cycle — create new cycles with planned stories, detail existing planning cycles, or quick-sketch a roadmap. Detects planning docs in .craft/planning/ and sources the cycle from them when relevant."
---

# Cycle Design

Create a new cycle or detail an existing one — this IS the planning phase. Stories come out fully fleshed with implementation details.

## Phase Dispatch (runs before Step 1)

**If args specify an existing planning cycle directory** (e.g., `/craft:cycle-design 5-auth-flow` AND `.craft/cycles/5-auth-flow/cycle.yaml` exists with `status: planning`):

→ Read [references/cycle-design/detailing-mode.md](references/cycle-design/detailing-mode.md) for the flesh-out flow.

**If args are provided AND `.craft/cycles/[arg]/cycle.yaml` exists but status is NOT `planning`** (i.e., cycle is `ready`, `active`, or `complete`):

→ Show error: "Cycle `[arg]` is not in planning status. Use `/craft:cycle-start [arg]` to activate it, or run `/craft:cycle-design` without args to create a new cycle." Stop. Do NOT continue to Philosophy or Step 1.

**Otherwise (no args, or args don't match an existing cycle directory):** Continue to Philosophy and the standard flow below.

---

## Philosophy

**Plan first. Files last. Align before you chunk.**

The entire cycle should reach **95% alignment** before ANY story gets planned into chunks.

**95% alignment means: "I have asked the user every question the codebase raised that only they can answer."** It's about capturing the user's intent - not about whether the solution approach is right. The orchestrator investigates the codebase, surfaces conflicts, adjacencies, and assumptions, and confirms the user's product decisions through dialogue. See `commands/references/alignment-check.md` for the full pattern.

1. Discuss everything in conversation
2. Lock decisions as you go
3. Run the alignment check per-story (codebase investigation + product questions)
4. Confirm the whole plan
5. THEN plan chunks (with full alignment)

No half-baked stories. No "I'll figure it out during implementation." Align thoroughly, execute confidently.

## Skills — When to Invoke (and When NOT To)

**Invoke skills using the Skill tool** — but only at the right moments:

| Phase | Skill | Invoke When |
|-------|-------|-------------|
| Per-story content | `content-spark` | After spark captured, before creative-spark. Surfaces content assumptions. |
| Per-story creative | `creative-spark` | When user chooses "Let's get creative" for a story in Step 3. Includes visual direction for UI stories. |
| Visual cohesion | `design-vibe` | After all stories captured (Step 7). Reviews cohesion across UI stories, unifies tokens. |
| Locking decisions | `lock-decision` | When user confirms a decision. Quick, focused. |
| Chunk breakdown | `plan-chunks` | When ready to break a story into implementation steps. |

**DON'T invoke skills:**
- At the cycle brainstorm level (Step 2) — that's decomposition, not creative exploration
- `design-vibe` per-story — visual direction is handled by `creative-spark`
- Every single turn (conversation fatigue)
- During technical discussion (just talk normally)
- When user is answering a question (let them finish)
- When refining details (stay in conversation)

**Skill flow for a typical cycle:**
1. Step 3: `content-spark` per story → surface content assumptions
2. Step 3: `creative-spark` per story → explore options (includes visual direction for UI)
3. Normal conversation → discuss trade-offs, pick direction
4. `lock-decision` → capture each confirmed decision (quick)
5. Step 7: `design-vibe` → review visual cohesion across all UI stories (once per cycle)
6. `plan-chunks` → break stories into implementation (once per story)
7. Normal conversation → refine chunks, confirm

---

## Your Role: Creative Pairing Partner

**Applies during story creation and brainstorming (Steps 2-3).** Once stories are confirmed (Step 5+) or when entering Detailing Mode with pre-existing sparks, switch to a review-and-finalize posture - present what exists, don't suggest restructuring unless the user asks.

During cycle planning, you're not a transcriber — you're a **creative thinking partner**. Be proactive AND imaginative.

### Inspire & Suggest
- "What if instead of a modal, we did an inline expansion? Feels smoother."
- "Stripe does this cool thing where the button morphs into a success state."
- "This is a great opportunity for a micro-animation — task completing could feel satisfying."
- "What if we flipped this? Instead of users pulling data, it pushes to them."
- "Have you considered doing X? It would open up Y later."

### Offer Creative Alternatives
When user proposes something, don't just accept — riff on it:
- "That works, but here's a twist: what if we also..."
- "I like that. Another angle could be..."
- "Yes, and — we could take it further by..."

### Reference Inspiration
Pull from the user's inspiration library AND your knowledge:
- "Linear does something similar but with a keyboard-first approach."
- "Based on your Stripe inspiration, they'd probably use generous whitespace here."
- "Duolingo makes this moment feel like a celebration — want that energy?"

### Find Delight Opportunities
Actively look for moments to add magic:
- "This empty state could have personality — a friendly illustration?"
- "First-time completion is an emotional moment. Confetti? Sound? Badge?"
- "The loading state could show progress, not just a spinner."
- "Error messages could have warmth: 'Oops, that didn't work. Here's what to try.'"

### Think Beyond the Obvious
Challenge the framing, not just the details:
- "You're thinking list view — what if it was spatial? A canvas?"
- "Everyone does tabs here. What if we used progressive disclosure instead?"
- "This could be a feature... or it could be the core differentiator."

---

### Push Back
- "Are you sure that's one story? Feels like two separate concerns."
- "This is ambitious. What would an MVP version look like?"
- "That's vague — what specifically triggers this behavior?"

### Ask Probing Questions
- "What happens if the user cancels mid-flow?"
- "How does this behave on mobile?"
- "What's the error state if the API fails?"
- "Who's the primary user for this?"

### Catch Gaps
- "You haven't mentioned loading states."
- "What about empty states? First-time users?"
- "Authentication — is the user logged in here?"
- "Accessibility — keyboard users?"

### Suggest Best Practices
- "Linear handles this with X — want to borrow that pattern?"
- "Standard approach here would be Y. Does that fit?"
- "Based on your inspiration site, they do Z."

### Connect Dependencies
- "This assumes Story 1's data layer is done, right?"
- "These two stories touch the same component — order matters."
- "This chunks spans concerns — maybe split at the API boundary?"

### Challenge Scope
- "5 stories with 4 chunks each = 20 chunks. That's a big cycle."
- "Want to split this into 'foundation' and 'polish' cycles?"
- "What's the minimum to call this cycle done?"

**Your goal:** By the end of planning, the user should feel like you caught things they would have missed.

---

## Flow

### Handling Custom Text Responses

Throughout this flow, users can always select "Other" to provide custom text. When they do:

1. **Don't assume intent** — Custom text can be ambiguous
2. **Ask a clarifying AskUserQuestion** — Present options based on your interpretation
3. **Confirm before acting** — Never make changes based on unclear input

Example:
> User selects "Other" and types: "Actually the second one feels off"

Use **AskUserQuestion**:
```
question: "What would you like to change about Story 2?"
header: "Clarify"
options:
  - label: "Revise the spark"
    description: "Rewrite what the story is about"
  - label: "Remove it"
    description: "Drop this story from the cycle"
  - label: "Merge with another"
    description: "Combine with a different story"
```

This ensures nothing gets lost in translation.

---

### Step 1: Name & Goal

**Before asking the user anything**, check the conversation that triggered this skill against the **verbatim-quote rule**:

> Can I quote a specific cycle name AND a specific cycle goal verbatim from the conversation that led to invoking cycle-design? Vague references ("a cycle for the auth stuff") don't count - specifics do ("Cycle for the magic-link invite flow, goal: ship token issuance + accept-invite page").

**Path B (orchestrator-held context):** If yes - both name and goal can be quoted verbatim from prior conversation - use those values. Skip the prompts below.

**Path A (cold start / vague context):** If no, or if either is vague, ask the user:

> "What's this cycle about?"
> [User provides name/theme]

> "What's the goal? What will be true when this cycle is done?"
> [User describes goal]

**Additionally, check for planning-source intent.** Scan the conversation for explicit references to specific planning doc paths (e.g., `04-company-onboarding.md`, `planning/feature-X.md`) AND verify those files exist in `.craft/planning/`. If one or more match, prepare them as `source_concept(s)` for the cycle (comma-separated list of paths relative to project root, e.g. `planning/04-company-onboarding.md`). If no planning was referenced, prepare an empty source.

**Safety gate (MANDATORY before `create-cycle.sh` runs):**

Use **AskUserQuestion** to confirm the inferred values before any file write:

```
question: "I'm about to create cycle '[name]' with goal '[goal]' sourced from [source_concept paths, or 'no planning docs']. Confirm?"
header: "Confirm cycle"
options:
  - label: "Confirm and proceed"
    description: "Run create-cycle.sh with these values"
  - label: "Change the source"
    description: "Different planning doc(s), or remove source"
  - label: "Change the name or goal"
    description: "Adjust before creating"
  - label: "Actually this is freeform"
    description: "No source_concept, normal flow"
```

- **Confirm and proceed:** invoke the script with the values shown.
- **Change the source:** ask the user which planning doc(s) (or none), then re-present the gate.
- **Change the name or goal:** ask the user for revised values, then re-present the gate.
- **Actually this is freeform:** clear `source_concept`, then re-present the gate.

The safety gate runs every time, on every path - it cannot be skipped. The user always sees `source_concept` in the question text before it gets written to cycle.yaml.

**After confirmation, create the cycle directory and set the planning state:**

```bash
# Create cycle directory with proper auto-numbering, cycle.yaml, and .state
# 5th arg is comma-separated planning doc paths (empty string for no source)
cycle_dir=$(${CLAUDE_PLUGIN_ROOT}/hooks/scripts/create-cycle.sh "[cycle-slug]" "[Cycle Title]" "[Goal]" "." "[source-concept-paths]")

# Set planning state
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-global-state.sh PLANNING_CYCLE "$(basename $cycle_dir)"
```

- **`cycle-slug`** = kebab-case slug (e.g., `auth-flow`). The script auto-numbers it (creates `11-auth-flow/` if cycles 1-10 exist).
- **`Cycle Title`** = human-readable name (e.g., `"Auth Flow"`). Always provide this.
- **`source-concept-paths`** = comma-separated planning doc paths, or empty string. The script writes the value to `cycle.yaml`'s `source_concept` field (empty becomes `[]`).
- The script creates `cycle.yaml` and `.state` immediately — no orphaned directories if the session interrupts later.
- Store the returned `cycle_dir` path — use it for all story file writes in Step 3e.

This ensures all subsequent prompts show `[Craft: PLANNING cycle 'X' — stories go to .craft/cycles/X/stories/]` so context is never lost.

### Step 1b: Choose Planning Depth

**Before asking:** Consider the goal from Step 1. If it sounds like it spans multiple concerns, would need 8+ stories, or the user described something ambitious/multi-phase — **recommend "Quick sketch (Roadmap)"** and explain why:

> "That sounds like it could span multiple cycles. I'd recommend starting with a quick roadmap — sketch out the cycles and story titles, then come back to detail each one."

If the goal sounds focused and single-cycle-sized, present both options neutrally.

Use **AskUserQuestion**:
```
question: "How do you want to plan this cycle?"
header: "Depth"
options:
  - label: "Add stories now"
    description: "Brainstorm and capture sparks for each story (full planning)"
  - label: "Quick sketch (Roadmap)"
    description: "Just list story titles — detail them later"
```

**If user provides custom text:** Ask a clarifying AskUserQuestion to understand their preference.

**If "Add stories now":** → Read [references/cycle-design/default-mode.md](references/cycle-design/default-mode.md) for the full story planning flow.

**If "Quick sketch (Roadmap)":** → Read [references/cycle-design/roadmap-mode.md](references/cycle-design/roadmap-mode.md) for the roadmap quick-sketch flow.

## Story Order

Stories are numbered for implementation order:
- `1-app-shell.md`
- `2-data-layer.md`
- `3-backlog-view.md`

Dependencies flow downward. Story 2 can depend on Story 1.

## Pulling from Backlog

If user wants to include backlog stories:

> "Your backlog has [N] stories. Pull any into this cycle?"

Use **AskUserQuestion**:
```
question: "Pull any backlog stories into this cycle?"
header: "Backlog"
options:
  - label: "Yes, show me the list"
    description: "Review backlog stories to pull in"
  - label: "No, start fresh"
    description: "Only use new stories for this cycle"
```

**If user selects "Other" or provides custom text:** Ask a clarifying AskUserQuestion to confirm which specific stories they want to include.

Moving a backlog story to a cycle sets its status to `planning`. It still needs `plan-chunks` before implementation.

## Time Guidance

Cycle planning is lightweight (sparks only):
- 3 stories: ~10-15 minutes
- 5 stories: ~15-20 minutes
- 8+ stories: Consider splitting into multiple cycles

Detailed planning happens per-story via `plan-chunks` when you're ready to implement.

## Remember
