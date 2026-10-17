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

Craft stories go through `/craft:story-implement` like any other project. Craft runs from the installed plugin copy, so editing craft's own files during a story does not touch the running flow, and a change takes effect at the next reinstall. The steps below are the same flow done by hand, for when you want to drive a story manually.

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

The canonical flow with all result branches is `commands/craft-story-implement.md` Step 5.1b.

### 6. Complete the story

```
bash hooks/scripts/complete-story.sh <story-file-path>
```

This sets the story status to `complete` and clears `CURRENT_STORY`. The story commit is staged from `.craft/.commit-manifest` (a validated file list with a `story:` identity header) - never from a working-tree sweep, so leftover untracked files stay out of the commit.

**Self-hosting note:** the manifest-write sub-step lives in `commands/craft-story-implement.md` (7b), which does not run on the manual path. The manual procedure has no manifest-write step, so `complete-story.sh` here takes the absent-manifest path by design: it logs "no manifest found, no commit made" and makes NO commit. Commit your story changes manually per the conventions below (or write a manifest yourself before running the script if you want it to create the commit).

### 7. Commit

`complete-story.sh` commits only what the manifest lists - in this repo, with no manifest, you commit manually. Manual commits (stories, fixes, docs) follow the commit conventions below; stage the files your change touched explicitly rather than `git add -A`.

## Commit conventions

- Use conventional prefixes: `feat:` / `fix:` / `chore:` / `refactor:` / `docs:` / `test:`
- Bump `.claude-plugin/plugin.json` once per feature or fix that changes a file craft runs (commands, skills, agents, hooks and the scripts they call) - one bump per logical change, in its final commit. Changes to tests, CI or contributor tooling alone never bump. Never per chunk
- Notable changes add a `CHANGELOG.md` entry in that same final commit: a `## <version> - <YYYY-MM-DD>` heading with verb-first, user-facing bullets ("Added...", "Fixed...", "Changed..."). Features always count as notable; fixes only when a user would notice. Internal changes to files craft runs (refactors, prompt rewording) bump with no entry. The doc-drift check blocks a changelog ahead of plugin.json and blocks pushing `feat:` commits with no changelog change
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

CI runs these same suites on every pull request targeting `main` - the PR is
the enforcement layer, the local run is how you stay ahead of it. The suites
run as five grouped jobs (`dashboard`, `hooks`, `lifecycle`, `flows`, `misc`)
via `scripts/ci/run-suite-group.sh`; a new test file is picked up
automatically, no CI edit needed. A non-blocking `browser` job additionally
opens the built dashboard page in headless Chrome over `file://` and asserts
it renders - the only check that runs the page rather than reading it. A
second Chrome job, `annotate-browser`, is required and has a 10-minute timeout:
it runs the annotate loop in a real browser through
`scripts/ci/annotate-check.sh` and fails, rather than skips, when the runner
has no Chrome.

## Documentation integrity

Craft's reference docs (`docs/agent-catalog.md`, `docs/decision-tree.md`, `README.md`, `DESIGN.md`) must stay in sync with the source they describe - agent/command/skill counts, the catalog tables, the orchestration map. A deterministic check enforces this:

```
bash scripts/check-doc-drift.sh   # exit 0 = clean, exit 1 = drift (prints exactly what to fix)
```

It derives every expected value from source (`ls agents/*.md`, etc.) and never hardcodes a count. Run it after any change that adds, renames, or removes a command, skill, or agent. It also sanity-checks `CHANGELOG.md` (the newest entry can't be ahead of the plugin version) and, when there are unpushed `feat:` commits, requires a changelog change in that range - a feature can't ship without release notes.

Maintainers can wire it as a local pre-push gate so a drifted `git push` is blocked in-session: keep a small wrapper script in your local, gitignored `.claude/hooks/` that runs `scripts/check-doc-drift.sh` and emits a PreToolUse permission decision, and register it in `.claude/settings.local.json` as a `PreToolUse` hook (matcher `Bash`, `if: "Bash(git push *)"`). The wrapper and its registration stay local; the check script is the shared, version-controlled piece.

CI runs this same script on every pull request to `main` (the `doc-drift` job), passing the PR's commit range via `--range` so the changelog gate - a `feat:` commit must ship a `CHANGELOG.md` change - is live there too, including for contributors who never wired the local pre-push gate.

One more CI guard worth knowing before you touch the dashboard template: any edit to `scripts/dashboard/template/index.html` must also bump the `craft-template-version` stamp in its `<meta>` tag, or the `template-stamp` check fails the PR. The stamp is what tells existing users a new page is available - an unbumped edit would strand them on the old one.

This is contributor tooling for developing craft itself - it has no role in projects built *with* craft.

## PR conventions

- One concern per PR. Small PRs review faster
- If the PR implements a planned story, link the story file in the description
- Include a brief test plan in the description if the change isn't covered by automated tests
- The PR title follows the same conventions as commit messages
- Eight CI checks must be green to merge: `dashboard`, `hooks`, `lifecycle`, `flows`, `misc`, `doc-drift`, `template-stamp`, `annotate-browser` (the `browser` check reports but never blocks). See `docs/ci-branch-protection.md` for how they are enforced

## Questions

Open an issue on the repo. For broader discussion, the README points to the main entry points.
