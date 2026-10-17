# Craft

Open-source Claude Code plugin: a development harness.

- **README.md** - what craft is and how to use it
- **DESIGN.md** - architecture, file layout, internals
- **CONTRIBUTING.md** - contribution workflow for craft itself

This file is the operating contract for Claude working in this repo. Routing and live state are injected on every prompt via the UserPromptSubmit hook (the `v1|craft-orchestration-index` block) - don't duplicate that here.

## Conventions

- **Commit messages** describe what changed for a public audience. Use conventional prefixes: `feat:` / `fix:` / `chore:` / `refactor:` / `docs:` / `test:`. Translate internal jargon to what the change DOES. Public craft terms (skills, agents, commands, hooks, cycles, stories, backlog, phases) are fine; internal mechanism names need explanation.
  - Bad: `fix: chain break when content-spark invokes via Skill tool`
  - Good: `fix: prevent skill nesting from breaking control flow back to caller`
- **Use regular dashes (-) only, never em dashes.** Em dashes are an AI-text tell.
- **Craft runs from the installed plugin copy, not this working tree.** Stories here go through `/craft:story-implement` like any other project. A change to craft's own files takes effect at the next reinstall, so a story that changes the implement loop is exercised by the story after it, not by itself.
- **Bump `.claude-plugin/plugin.json` version once per feature or fix that changes a file craft runs** (commands, skills, agents, hooks and the scripts they call) - one bump per logical change (a story, an adhoc fix), in that change's final commit. Users only receive new files when this version changes, so such a change bumps even with nothing worth a changelog entry. Changes to tests, CI or contributor tooling alone never bump. Never per chunk; intermediate chunk commits do not bump.
- **`CHANGELOG.md` entries are notable-only** - features and user-visible fixes get a `## <version> - <YYYY-MM-DD>` heading with verb-first, user-facing bullets ("Added...", "Fixed...", "Changed...", "Improved..."). Internal changes to files craft runs (refactors, prompt rewording) bump the version with no entry, and no entry is ever about the repo itself (changelog edits, doc restructures, contributor tooling). Same audience rule as commit messages. `check-doc-drift.sh` blocks a changelog that's ahead of plugin.json, and blocks pushing a `feat:` commit with no changelog change.
  - **Write every bullet for a craft user, not for us.** The test: no internal mechanism names (CDN hosts, metadata fields, gate names, file paths), lead with what the user gets, and say what it feels like to use ("icons now arrive in seconds instead of minutes"), not how it works. The `## 1.99.54` entry is the exemplar - match its register.

## Personality

- Momentum over perfection
- Challenge ideas constructively ("what if..." not "are you sure...")
- Trust by default, verify when uncertain
- No bureaucratic language

## Maintainer-local

`CLAUDE.local.md` is gitignored. If present at repo root, Claude Code loads it after this file - that's where personal/maintainer-specific rules live.
