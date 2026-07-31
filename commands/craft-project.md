---
name: project
description: "Switch between projects in a monorepo, or show a cross-project dashboard."
---

# Craft Project

Manage which project is active in a multi-project monorepo.

## Behavior

### No arguments: Show dashboard

Run the `discover-projects.sh` script to list all projects:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/discover-projects.sh"
```

This returns `name|path|status|package_manager` lines.

Display a dashboard like:

```
┌──────────────────────────────────────────────────────┐
│  PROJECTS                                             │
├──────────────┬──────────┬───────────┬────────────────┤
│ Project      │ Cycle    │ Progress  │ Status         │
├──────────────┼──────────┼───────────┼────────────────┤
│ ● craftsman  │ 7-ext    │ 4/5 done  │ active-dev     │
│ ○ you-coded  │ —        │ —         │ pre-dev        │
│ ○ master     │ —        │ —         │ planning       │
└──────────────┴──────────┴───────────┴────────────────┘
Currently pinned: craftsman
```

For each project, read its `.craft/.global-state` to get ACTIVE_CYCLE, then read cycle state for progress. Mark the currently pinned project (from `$CRAFT_PROJECT_ROOT` env var) with a bullet.

### With project name argument: Switch project

When the user provides a project name (e.g., `/craft:project craftsman`):

1. Validate the project exists in the registry (or is "root"/"master" for the monorepo root)
2. Resolve its absolute path
3. Update the session env via `$CLAUDE_ENV_FILE`:
   ```bash
   echo "export CRAFT_PROJECT_ROOT=\"/absolute/path/to/project\"" >> "$CLAUDE_ENV_FILE"
   echo "export CRAFT_PROJECT_NAME=\"craftsman\"" >> "$CLAUDE_ENV_FILE"
   ```
4. Write the persistent pin file (so hooks can resolve without env vars):
   ```bash
   repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
   printf '%s\n%s\n' "/absolute/path/to/project" "project-name" > "$repo_root/.craft/.pinned-project"
   ```
5. Show a mini status summary for the new project (backlog count, active cycle, etc.)

## Important

- This command only applies to monorepo setups with multiple `.craft/` directories
- In single-project repos, inform the user there's only one project and no switching needed
- The project registry lives at the git repo root: `.craft/projects/*.md`
- Each registry file has YAML frontmatter with `name`, `path`, `status`, `package_manager`
