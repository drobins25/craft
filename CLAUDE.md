# Craft

Open-source Claude Code plugin: a creative-first development harness.

- **README.md** - what craft is and how to use it
- **DESIGN.md** - architecture, file layout, internals
- **CONTRIBUTING.md** - contribution workflow for craft itself

This file is the operating contract for Claude working in this repo. Routing and live state are injected on every prompt via the UserPromptSubmit hook (the `v1|craft-orchestration-index` block) - don't duplicate that here.

## Safety rules

- **Never use `/craft:story-implement` in this repo.** It invokes the implementer agent against the plugin's own files, which is self-modification mid-work and breaks the harness. Contributors: see CONTRIBUTING.md for the manual implementation procedure.
- **Walkthrough quick-fixes are the only exception to "always invoke implementer via Task."** Findings with `complexity: quick-fix` and a `fix_hint` can be implemented directly by the orchestrator. Scope: trivial CSS or attribute edits, 1-5 lines, single file. Story-fix findings still go through the implementer agent.

## Conventions

- **Commit messages** describe what changed for a public audience. Use conventional prefixes: `feat:` / `fix:` / `chore:` / `refactor:` / `docs:` / `test:`. Translate internal jargon to what the change DOES. Public craft terms (skills, agents, commands, hooks, cycles, stories, backlog, phases) are fine; internal mechanism names need explanation.
  - Bad: `fix: chain break when content-spark invokes via Skill tool`
  - Good: `fix: prevent skill nesting from breaking control flow back to caller`
- **Use regular dashes (-) only, never em dashes.** Em dashes are an AI-text tell.
- **Bump `.claude-plugin/plugin.json` version once per feature or fix** - one bump per logical change (a story, an adhoc fix), in that change's final commit. Never per chunk; intermediate chunk commits do not bump.
- **`CHANGELOG.md` entries are notable-only** - features and user-visible fixes get a `## <version> - <YYYY-MM-DD>` heading with verb-first, user-facing bullets ("Added...", "Fixed...", "Changed...", "Improved..."). Internal changes (tests, refactors, doc drift, contributor tooling) bump the version with no entry. Same audience rule as commit messages. `check-doc-drift.sh` blocks a changelog that's ahead of plugin.json, and blocks pushing a `feat:` commit with no changelog change.

## Personality

- Momentum over perfection
- Challenge ideas constructively ("what if..." not "are you sure...")
- Trust by default, verify when uncertain
- No bureaucratic language

## Maintainer-local

`CLAUDE.local.md` is gitignored. If present at repo root, Claude Code loads it after this file - that's where personal/maintainer-specific rules live.
