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

### 5. Audit your completion claims

After the final chunk, verify the suite is green (`./tests/run-all.sh`), then audit your completion claims before completing the story - the audit verifies the narrator, not the code:

- Persist the verification results to `.craft/.validation-receipt.md`, opening with a `story: <name>` header line
- Reduce every completion statement you intend to report ("all tests pass", "acceptance criteria met") to a bare claim with no justification attached
- Invoke the `craft:claims-auditor` agent (Task tool, haiku) with the claim list, the receipt path, and the story file path - never your narrative or reasoning
- An unsupported claim means fix the underlying issue or correct the claim before completing; the audit itself never blocks completion

The canonical flow with all result branches is `commands/craft-story-implement.md` Step 5.1b; the `/implement` command carries the same flow for this repo.

### 6. Complete the story

```
bash hooks/scripts/complete-story.sh <story-file-path>
```

This sets the story status to `complete` and clears `CURRENT_STORY`. The story commit is staged from `.craft/.commit-manifest` (a validated file list with a `story:` identity header) - never from a working-tree sweep, so leftover untracked files stay out of the commit.

**Self-hosting note:** the manifest-write sub-step lives in `commands/craft-story-implement.md` (7b), which is never run in this repo (see the safety rule above). `/implement` has no manifest-write step, so `complete-story.sh` here takes the absent-manifest path by design: it logs "no manifest found, no commit made" and makes NO commit. Commit your story changes manually per the conventions below (or write a manifest yourself before running the script if you want it to create the commit).

### 7. Commit

`complete-story.sh` commits only what the manifest lists - in this repo, with no manifest, you commit manually. Manual commits (stories, fixes, docs) follow the commit conventions below; stage the files your change touched explicitly rather than `git add -A`.

## Commit conventions

- Use conventional prefixes: `feat:` / `fix:` / `chore:` / `refactor:` / `docs:` / `test:`
- Bump `.claude-plugin/plugin.json` once per feature or fix - one bump per logical change, in its final commit. Never per chunk
- Notable changes add a `CHANGELOG.md` entry in that same final commit: a `## <version> - <YYYY-MM-DD>` heading with verb-first, user-facing bullets ("Added...", "Fixed...", "Changed..."). Features always count as notable; fixes only when a user would notice. Internal changes (tests, refactors, contributor tooling) bump with no entry. The doc-drift check blocks a changelog ahead of plugin.json and blocks pushing `feat:` commits with no changelog change
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

## Documentation integrity

Craft's reference docs (`docs/agent-catalog.md`, `reference/decision-tree.md`, `README.md`, `DESIGN.md`) must stay in sync with the source they describe - agent/command/skill counts, the catalog tables, the orchestration map. A deterministic check enforces this:

```
bash scripts/check-doc-drift.sh   # exit 0 = clean, exit 1 = drift (prints exactly what to fix)
```

It derives every expected value from source (`ls agents/*.md`, etc.) and never hardcodes a count. Run it after any change that adds, renames, or removes a command, skill, or agent. It also sanity-checks `CHANGELOG.md` (the newest entry can't be ahead of the plugin version) and, when there are unpushed `feat:` commits, requires a changelog change in that range - a feature can't ship without release notes.

Maintainers can wire it as a local pre-push gate so a drifted `git push` is blocked in-session: add a `PreToolUse` hook (matcher `Bash`, `if: "Bash(git push *)"`) to your local, gitignored `.claude/settings.local.json` pointing at `scripts/pre-push-gate.sh`. That registration stays local; the check script is the shared, version-controlled piece (and drops into CI unchanged).

This is contributor tooling for developing craft itself - it has no role in projects built *with* craft.

## PR conventions

- One concern per PR. Small PRs review faster
- If the PR implements a planned story, link the story file in the description
- Include a brief test plan in the description if the change isn't covered by automated tests
- The PR title follows the same conventions as commit messages

## Questions

Open an issue on the repo. For broader discussion, the README points to the main entry points.
