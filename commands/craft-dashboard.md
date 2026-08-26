---
name: dashboard
description: "Open your project's dashboard - the whole graph of cycles, stories, and records in one page. Rebuilds the data first, offers a page update when the shipped template moved ahead, then opens it."
argument-hint: ""
---

# Dashboard

Opens `.craft/dashboard.html` - a single page rendering your project's whole graph (cycles, stories, records, and how they connect). The page is a copied artifact with its own version, independent of the plugin version; this command is what keeps it current.

## Project Root

Use `$CRAFT_PROJECT_ROOT` (set at session start) as the base path for all `.craft/` references. If not set, resolve it by walking up from PWD to find the nearest `.craft/.global-state`.

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`.

## Flow

### Step 1: Check the page

Run:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/dashboard/dashboard-page.sh --check --root "$PROJECT"
```

Read `STATE` and `COPY` from its output. Branch:

**`STATE=no-project`** - print one plain line: "No craft project found here - run `/craft:init` first." Stop. Do not rebuild, do not open.

**`STATE=missing`** - this is a first run, nothing to ask. Pull silently:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/dashboard/dashboard-page.sh --pull --root "$PROJECT"
```
No question, no extra line about it. Continue to Step 2.

**`STATE=behind`** - the shipped template moved ahead of the user's copy. Ask via **AskUserQuestion**, wording chosen by `COPY`:

- `COPY=edited`: "Your copy has local edits. Pulling replaces it - your edited version will be kept at .craft/dashboard-backup.html."
- `COPY=unknown`: "Your dashboard page looks different from what craft last delivered (or was never tracked). Pulling replaces it - your current version will be kept at .craft/dashboard-backup.html."
- `COPY=pristine`: "A newer dashboard page is available. Pull it?"

Options are "Pull the update" and "Keep my current page" (declining is always allowed). If the user accepts, run:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/dashboard/dashboard-page.sh --pull --root "$PROJECT"
```
Either way, continue to Step 2.

**`STATE=current`** - nothing to ask, nothing to print about it. Continue to Step 2.

### Step 2: Rebuild for freshness

Run once, regardless of the branch above:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/dashboard/dashboard-run.sh --root "$PROJECT"
```

This prints one JSON line on stdout. Read it directly - do not re-derive counts elsewhere:

- `"status":"ok"` - read `nodes` and `edges` from the JSON and print: `Graph rebuilt - <nodes> records, <edges> connections`
- `"status":"degraded"`, `"reason":"build-skipped-concurrent"` - print: `A rebuild is already running - showing your latest good graph.`
- `"status":"degraded"`, any other reason - print: `Showing your last good graph - the rebuild didn't finish.`

Never print the raw `reason` code - it is a machine value, not a sentence.

### Step 3: Open the page

`PAGE` is `$PROJECT/.craft/dashboard.html` (the same absolute path `--check` printed). Attempt to open it in the default browser, swallowing failure:
```
open "$PAGE" 2>/dev/null || xdg-open "$PAGE" 2>/dev/null || true
```

### Step 4: Print the link

Always print the page's `file://` path, on its own line, whether or not the open in Step 3 succeeded - it is the fallback for headless sessions, SSH, or no default browser, and the way to re-open the page later:

```
file://<PAGE>
```

This line prints on every path that reaches Step 2 (i.e. every branch except `no-project`), regardless of what Step 3 did.
