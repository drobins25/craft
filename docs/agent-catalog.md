# Agent Catalog

> Reference for all 27 agents in the Craft plugin. Agents run in isolated context - they receive only what you pass in their prompt.

*Last reviewed: 2026-06-08 - current as of plugin v1.89.x.*

Craft agents fall into four categories based on when you encounter them and what invokes them. The first question to ask is always: does this need to be an agent at all, or can a skill or hook do the job deterministically?

---

## Core Workflow Agents

These agents run inside the implementation pipeline. The orchestrator invokes them via the Task tool. You rarely interact with them directly - they're invoked by skills like `plan-chunks` and `validate-chunk`.

| Agent | Model | Purpose |
|-------|-------|---------|
| `implementer` | sonnet | Owns the implement-validate-refine loop per chunk. Full write access within the active story scope. The workhorse of the pipeline. |
| `tester` | sonnet | Integration tests and E2E after all chunks complete. Runs the full test suite, fixes failures. |
| `chunk-validator` | haiku | Runs quality checks (typecheck, lint, no-any, build, tests, design tokens) and returns a structured validation report. Reports only - never fixes. Haiku keeps this fast and cheap. |
| `plan-chunks-agent` | opus | Autonomous chunk planning for a single story - researches the codebase, writes receipted contracts + Investigation + Pitch into the story file. Used by `plan-chunks` for single and batch planning. |
| `project-scanner` | sonnet | Full project analysis for documentation updates. Invoked by `/craft:update-docs`. |
| `claims-auditor` | haiku | Verifies the orchestrator's completion claims against on-disk artifacts (git diff, validation receipt, story file) once per story at story-final, before complete-story.sh. Audits the narrator, not the code. |

**Key constraint:** `implementer` and `tester` receive full write access. `chunk-validator` and `claims-auditor` are read-only. `plan-chunks-agent` writes only the story file it plans (never source code). `project-scanner` writes only to `.craft/`.

---

## Analysis Agents

Post-cycle agents that inspect the live app. Invoked by `/craft:analyze` and automatically at cycle completion for UI cycles. All analysis agents use `chrome-devtools` MCP except `playwright-browser`, which uses `playwright-cli`.

| Agent | Model | Purpose |
|-------|-------|---------|
| `qa-analyzer` | sonnet | Bug hunting via browser inspection. Finds functional errors, broken states, console errors. |
| `ux-analyzer` | sonnet | Nielsen heuristics, accessibility, mental models. Evaluates the user experience against usability principles. |
| `creative-analyzer` | sonnet | Delight moments, viral potential, "beautiful wrong" patterns. Evaluates emotional resonance. |
| `style-analyzer` | sonnet | Design token compliance, pattern consistency, visual system integrity. |
| `walkthrough-analyzer` | sonnet | Interactive first-time user simulation. Clicks everything, tests every state transition. Chrome DevTools MCP only - never reads source code. 45 tool-call budget with structured preflight checklist. Auto-triggers at cycle completion for UI cycles. |

**Walkthrough vs QA analyzer distinction:** `walkthrough-analyzer` acts as a naive user and never reads source code. `qa-analyzer` uses browser inspection but can correlate findings with code patterns. Use walkthrough for user-experience issues; use QA for functional correctness.

**Quick-fix exception:** Walkthrough findings with `complexity: quick-fix` and a `fix_hint` may be applied directly by the orchestrator without spawning an implementer agent. This is the only exception to the "always use implementer" rule.

---

## Review and Research Agents

Agents that support code review, research, and verification workflows. Invoked by `/craft:review`, `/craft:research`, and `/craft:research-verify`.

| Agent | Model | Purpose |
|-------|-------|---------|
| `pr-reviewer-expert` | sonnet | PR review crystallized from CodeRabbit's architecture. Reads `locked.md` and `project.md` before forming any opinion. Two severity levels: issue (must fix) and suggestion (consider). Never comments on style if a linter exists. |
| `maze-architect` | haiku | Generates 2-4 review questions from a raw diff with zero intent context. Never sees commit messages. Used by `/craft:review --maze` to create perpendicular review routes. Haiku model because the task is pattern recognition, not judgment. |
| `researcher` | haiku | Constrained extraction for one research sub-question - verbatim quotes, source-backed findings, no synthesis. Writes a branch file, returns a lightweight summary. Used by `/craft:research`. |
| `research-synthesizer` | sonnet | Reads all branch files in a research topic and writes `_plan.md` + `_sources.md`. Preserves conflicts verbatim, re-enforces the evidence gate, runs quote-claim alignment. Replaces the orchestrator-side synthesis that used to run in the main loop. Model locked - see its rationale block. |
| `verifier` | haiku | Adversarial claim checker for `/craft:research-verify`. Takes one finding and tries to disprove it using independent primary sources. Local evidence before web search; guarded against premature UNVERIFIABLE. |
| `practitioner-reviewer` | sonnet | Challenges verified claims from practical experience. Catches "true in docs, wrong in practice." No web search - relies on practitioner knowledge. Used by `/craft:research-verify` practitioner mode. |

**Maze review flow:** `maze-architect` (haiku, no intent) generates questions → `pr-reviewer-expert` (sonnet, full context) answers them. The architect's naivety is the feature, not a limitation.

---

## Browser Automation Agent

| Agent | Model | Purpose |
|-------|-------|---------|
| `playwright-browser` | sonnet | Owns a live browser session via `playwright-cli`. Navigates, clicks, fills forms, reads accessibility snapshots. Invoked by the `browser` skill (`/craft:browser`). ~4x cheaper than Chrome DevTools MCP in token cost (snapshots saved to disk as YAML, not streamed into context). 60 tool-call budget. |

**Session name rule:** Names must be 12 characters or fewer, lowercase alphanumeric only. macOS has a 104-char Unix socket path limit. Long names silently overflow and spawn duplicate browsers instead of erroring.

**playwright-browser vs walkthrough-analyzer:** `playwright-browser` is interactive - you steer it via SendMessage across turns. `walkthrough-analyzer` runs autonomously with a structured test plan. Use `playwright-browser` for exploration and targeted testing; use `walkthrough-analyzer` for systematic post-cycle review.

---

## Crystallized Expert Agents

These agents were built using `/craft:become` - a psychological research process that reconstructs how a domain expert thinks, not just what they know. Each carries beliefs, scar tissue, and instincts from their source research. They're designed for consultation, not pipeline execution.

Invoke via `/craft:ask` for intelligent routing, or directly via the Agent tool in skills and commands.

```mermaid
graph LR
    Q[Your question] --> A[/craft:ask]
    A --> M[muse\nemotional job]
    A --> AL[alchemist\ninteraction physics]
    A --> C[conductor\norchestration]
    A --> PR[pr-reviewer-expert\ncode review]
    A --> DW[doc-writer\ndocumentation]
    A --> PA[product-anthropologist\nuser truth]
```

| Agent | Model | Crystallized From | Consult When |
|-------|-------|-------------------|--------------|
| `muse` | sonnet | `.craft/research/product-intuition-become/` | Evaluating whether a feature will generate word-of-mouth, translating user requests into emotional jobs, "nobody will tell their friend about this" gut checks |
| `riff` | sonnet | `.craft/research/riff-become/` | Brainstorming, half-formed ideas, "is this stupid?" gut-checks - a thinking partner for the moment between draft 11 and draft 12, not an instructor |
| `alchemist` | sonnet | `.craft/research/css-interaction-alchemist-become/` | Building UI that needs to feel alive - scroll-driven reveals, morphing transitions, spatial animation. Sees CSS as a physics engine, not a styling language. |
| `conductor` | sonnet | `.craft/research/conductor-become/` | Designing agent workflows, choosing between skill/hook/agent/rule, diagnosing why an agentic system is failing silently |
| `doc-writer` | sonnet | `.craft/research/technical-documentation-writer-become/` | Writing or reviewing any documentation - README files, architecture docs, API references, tutorials, decision records |
| `product-anthropologist` | sonnet | (role-based crystallization) | Diagnosing why users aren't adopting, interpreting user feedback, evaluating whether a product solves a real problem |
| `crystallizer` | opus | `.craft/research/expert-cognition-transfer/` | Synthesizing research branch files into a 9-section agent persona. Invoked by `/craft:become` Phase 3. Opus because this is the highest-judgment task in the system. |
| `become-researcher` | sonnet | (role-based crystallization) | Collecting psychological material for `/craft:become`. Gathers beliefs, scar tissue, axioms - NOT facts. One per sub-question, runs in parallel. |

**Stale signals:** Each crystallized agent's frontmatter includes `stale_signals` - specific conditions that would make the agent's beliefs outdated. Check these before trusting the agent in changed environments.

**Handbook references:** Some agents reference their research folder via `research_handbook:` in frontmatter. When you need citations or deeper context, the handbook points you to the raw branch files.

---

## The Craft Guide

A standalone, read-only help agent - the analog of Claude Code's docs agent, for craft itself. Auto-triggers on craft how-to and diagnostic questions, or reach it explicitly via `/craft:guide`. Educated about craft (NOT crystallized): it reads craft's real source files and your `.craft/` state to explain how things work and diagnose your setup. Grounds behavioral answers in source (docs are a subordinate map). Read-only - it never changes anything.

| Agent | Model | Purpose |
|-------|-------|---------|
| `guide` | sonnet | Explains how craft works and how to use it on your project; diagnoses your `.craft/` state; hands off pure Claude Code questions to `claude-code-guide`. Read-only (Read / Glob / Grep). Reactive - answers when asked, never barges in. |

---

## How to Choose

```
Need to do implementation work?  → skill + pipeline agents (implementer, tester, etc.)
Need to inspect a live app?      → analysis agents (walkthrough, QA, UX, style, creative)
Need to review code?             → /craft:review (standard) or /craft:review --maze (perpendicular)
Need to research a topic?        → /craft:research (researcher + verifier + practitioner-reviewer)
Need expert judgment?            → /craft:ask (routes to crystallized experts)
Need to build a new expert?      → /craft:become (become-researcher + crystallizer)
```

`/craft:ask` scans agent descriptions and recommends the best match. It skips operational agents (implementer, tester, chunk-validator, etc.) and routes to consultable agents only.

---

*For full agent implementation details, see individual files in `plugins/craft/agents/`. For orchestration design patterns, see `docs/decision-tree.md` and consult the `conductor` agent.*
