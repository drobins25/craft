# Craft

Open-source Claude Code plugin: a creative-first development harness.

- **README.md** - what craft is and how to use it
- **DESIGN.md** - architecture, file layout, internals
- **CONTRIBUTING.md** - contribution workflow for craft itself

This file is the operating contract for Claude working in this repo. Routing and live state are injected on every prompt via the UserPromptSubmit hook (the `v1|craft-orchestration-index` block) - don't duplicate that here.

## IMPORTANT: Surface architectural changes before making them

These categories of change have repeatedly broken the plugin via unsolicited refactors. Surface the proposed change and get explicit approval before:

- Workflow changes (how commands and skills flow into each other)
- State changes (what gets stored, where, in what format)
- New behaviors (auto-commits, git push, new validations)
- Removing features, even ones that look unused
- Skill invocation patterns (how skills call each other)
- File format changes (YAML structure, frontmatter fields)

When unsure whether a change is architectural: ask first.

## Safety rules

- **Never use `/craft:story-implement` in this repo.** It invokes the implementer agent against the plugin's own files, which is self-modification mid-work and breaks the harness. Contributors: see CONTRIBUTING.md for the manual implementation procedure.
- **Walkthrough quick-fixes are the only exception to "always invoke implementer via Task."** Findings with `complexity: quick-fix` and a `fix_hint` can be implemented directly by the orchestrator. Scope: trivial CSS or attribute edits, 1-5 lines, single file. Story-fix findings still go through the implementer agent.

## Conventions

- **Commit messages** describe what changed for a public audience. Use conventional prefixes: `feat:` / `fix:` / `chore:` / `refactor:` / `docs:` / `test:`. Translate internal jargon to what the change DOES. Public craft terms (skills, agents, commands, hooks, cycles, stories, backlog, phases) are fine; internal mechanism names need explanation.
  - Bad: `fix: chain break when content-spark invokes via Skill tool`
  - Good: `fix: prevent skill nesting from breaking control flow back to caller`
- **Use regular dashes (-) only, never em dashes.** Em dashes are an AI-text tell.
- **Bump `.claude-plugin/plugin.json` version after every commit to plugin files.** One version per commit.

## Personality

- Momentum over perfection
- Challenge ideas constructively ("what if..." not "are you sure...")
- Trust by default, verify when uncertain
- No bureaucratic language

## Maintainer-local

`CLAUDE.local.md` is gitignored. If present at repo root, Claude Code loads it after this file - that's where personal/maintainer-specific rules live.
