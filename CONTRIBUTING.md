# Contributing to Craft

Craft is built incrementally through cycles of small stories. Contributors are welcome.

This file covers the practical workflow for working on craft itself. For what craft IS, see README.md. For architecture, see DESIGN.md.

## Prerequisites

- Claude Code installed
- This repo cloned locally
- Read the README and skim DESIGN.md to understand the harness

## Setup

The repo's `.claude/commands/` and `.claude/agents/` directories ship project-local commands and agents that load automatically when you open Claude Code inside the repo. No marketplace install needed for development.

If you want craft installed as a plugin in another project to dogfood it, point the marketplace at your local clone:

```
/plugin marketplace add ~/path/to/craft
/plugin install craft@craft
```

## Implementing a story (manual procedure)

Craft can't be developed via `/craft:story-implement` - that would invoke the implementer agent against the plugin's own files, which is self-modification mid-work. Instead, you (or your Claude session) implement stories manually using the harness scripts.

The `/implement` command in `.claude/commands/implement.md` encodes this procedure as an interactive workflow. The steps below are the same flow done by hand.

### 1. Activate the cycle

Read `.craft/.global-state`. If `ACTIVE_CYCLE` is empty, activate the cycle containing your story:

```
bash hooks/scripts/start-cycle.sh <cycle-dir-name>
```

### 2. Start the story

```
bash hooks/scripts/start-story.sh <story-file-path>
```

This sets the story to `active`, initializes chunk state in `.craft/cycles/<cycle>/.state`, and enables the write gate via `CRAFT_WRITE_ENABLED` in `.craft/.global-state`.

### 3. Read the story spec

Open the story file in `.craft/cycles/<cycle>/stories/`. Each story has chunks numbered 1..N. Each chunk lists files to touch, implementation details, and done-when criteria.

### 4. Implement each chunk

For each chunk:

- Read the chunk's file list and implementation details
- Make the changes directly (Edit, Write, Bash). Do NOT invoke the implementer agent
- Verify the done-when criteria
- Mark the chunk complete:

```
bash hooks/scripts/complete-chunk.sh
```

This increments `CURRENT_CHUNK` and updates the story frontmatter.

### 5. Complete the story

After the final chunk:

```
bash hooks/scripts/complete-story.sh <story-file-path>
```

This sets the story status to `complete` and clears `CURRENT_STORY`.

### 6. Commit

One commit per chunk is typical for review clarity; one commit per story is also fine for small stories. Follow the commit conventions below.

## Commit conventions

- Use conventional prefixes: `feat:` / `fix:` / `chore:` / `refactor:` / `docs:` / `test:`
- Bump `.claude-plugin/plugin.json` in the same commit as plugin file changes. One version per commit
- Translate internal jargon to what the change DOES. Public craft terms (skills, agents, commands, hooks, cycles, stories, backlog, phases) are fine. Internal mechanism names need explanation
- Regular dashes only, never em dashes (they read as AI-generated)

Example:

- Bad: `fix: chain break when content-spark invokes via Skill tool`
- Good: `fix: prevent skill nesting from breaking control flow back to caller`

## Testing

The bash test suite covers hook scripts, state management, and lifecycle operations:

```
./tests/run-all.sh
```

Run before opening a PR. All commits should pass.

## PR conventions

- One concern per PR. Small PRs review faster
- If the PR implements a planned story, link the story file in the description
- Include a brief test plan in the description if the change isn't covered by automated tests
- The PR title follows the same conventions as commit messages

## Questions

Open an issue on the repo. For broader discussion, the README points to the main entry points.
