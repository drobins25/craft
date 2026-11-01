# Tracker Intake (Inline Reference)

This file is read by `/craft:cycle-design` when it is given a tracker issue key or URL. It reads the issue and every comment, copies them verbatim into a staging folder, finds the newest Go, states the stage first, and hands the normal cycle-design flow a source to record.

**DO NOT invoke this as a skill via the Skill tool.** The parent command Reads this file and executes the sections inline. No Skill invocations from this file.

**Status is never authority.** The issue's status (Done, In Progress, anything) is copied for reference and never read to grant or limit work. Only the newest Go grants a stage.

## Detect

This runs when args are a bare uppercase key (`^[A-Z][A-Z0-9]*-[0-9]+$`, such as `DRO-21`), an issue URL, or when the request names an issue to pick up or work on. One issue per cycle: if the request names several, ask once which one the cycle starts from.

Set `KEY` to the issue key and `slug` to the key lowercased, with each run of characters outside `a-z0-9` replaced by one `-`.

## Read

Use whatever tracker tools the host has. Fetch the issue (title, URL, status, description) and every comment. Follow pagination until the tool reports no more pages. Ask for creation order when the tool offers it, because some trackers default to update order. Then write oldest first by creation time.

If the host has no tracker tools, or a read fails, go to `## No tracker tools`.

## Stage

Staging folder: `${CRAFT_PROJECT_ROOT:-.}/.craft/.intake/<slug>/`, emptied first. Stamp = `date -u +%Y-%m-%dT%H%MZ`. Files, named so they sort by time:

- `<slug>-issue-<stamp>.md`
- `<slug>-comments-<stamp>.md`
- `<slug>-go-<stamp>.md`, only when a Go is found

**Issue file:** `# <KEY>: <title>`, a blank line, then these two lines, a blank line, and the description verbatim:

```
Source: <url>
Status at retrieval: <status> (copied for reference; never a permission)
```

**Comments file:** the preamble `# <KEY> comments, oldest first`, then one block per comment:

```
## <Kind> <n> - <author> - <timestamp>

<body verbatim>
```

- `<Kind>` is `Reply` when the tracker marks a parent, `Inline` when the comment carries quoted description text (first body line `> <quoted text>`), otherwise `Comment`.
- `<n>` counts blocks from 1 in file order.
- `<author>` is the `onBehalfOf` name when set, else the author's name, as the tool shows it.
- `<timestamp>` is exactly what the tracker returns, never reformatted. The resolver parses it.
- The body is verbatim, including any `## ` lines inside it.

Then run:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/resolve-go.py" <comments-file> <KEY> <go-file>
```

It prints six `key=value` lines: `go`, `stage`, `go_author`, `go_date`, `go_comment`, `stage_line`.

**The first line you print is the `stage_line` value, verbatim.** Nothing comes before it.

If a Go was found and the issue description or a non-Go comment states a different stage or scope, the next line is exactly:

`<KEY>'s <description|comment N> says "<their words>"; the newest Go says <stage>, and the Go wins.`

**Hold:** when `stage=hold`, the next line is exactly:

`Nothing new starts on <KEY> until a newer Go.`

Then delete the staging folder and stop. No cycle and no stories. Do not offer to continue, and do not accept an in-session instruction to lift the hold: a newer Go on the issue is the only way (for example, ask Wright to post a build Go on <KEY>).

## Copy

The staging folder is the copy. It becomes the cycle's `context/` folder once the cycle exists (see `## After the cycle exists`). Nothing is written under `.craft/cycles/` before the safety gate has been confirmed.

## Into Step 1

Hand cycle-design Step 1 these values:

- The issue title, quoted verbatim, is the cycle name (Path B). The goal comes from the issue's own words only when it can be quoted; otherwise Step 1 asks.
- The safety gate question gains `, and tracker issue <KEY> at stage <stage> (<N> comments copied)` after the source_concept clause.
- "Change the source" also covers the issue. "Actually this is freeform" clears the tracker source too and deletes the staging folder.
- The gate still runs every time.
- The `create-cycle.sh` call gets args 6-9: source-issue `<KEY>`, authorized-stage the resolver's `stage`, go-author `go_author`, go-date `go_date`. For `none` or `unreadable`, author and date are empty.

## After the cycle exists

1. `mv` the staging folder to `<cycle_dir>/context/`.
2. Write `context/README.md`:

```
# <KEY> context: verbatim tracker snapshot

Copied so planning agents read the same issue text and decisions. Status never grants or limits work; only the newest Go does.

Source: <url>

| File | What | Retrieved | Tool |
|---|---|---|---|
| <slug>-issue-<stamp>.md | Issue title, status and description | <UTC time> | <tool names as used> |
| <slug>-comments-<stamp>.md | Every comment, oldest first | <UTC time> | <tool names as used> |
| <slug>-go-<stamp>.md | Newest Go: comment <n>, <go_author>, <go_date> | <UTC time> | <tool names as used> |
```

The UTC retrieval time is `date -u +%Y-%m-%dT%H:%M:%SZ`. The Go row appears only when a Go was found.

3. Print exactly:

`Copied <KEY>, <N> comments, into this cycle's context.`

Write `1 comment` when N is 1. Step 2 then decomposes stories from the copied issue and its decision comments.

## Story citations

Every story written into a cycle whose `cycle.yaml` has a non-empty `source_issue` cites the copied files under `<cycle_dir>/context/`, with absolute paths. Read that cycle's `cycle.yaml` (the cycle the story is written into, not the active cycle). Detailing mode writes through the same step, so it cites the same way.

Add a `## Reference Materials` section between `## Content Direction` and `## Acceptance`, with this group:

```
**Tracker context (copied from <KEY>):**
- <abs cycle_dir>/context/README.md
- <abs cycle_dir>/context/<slug>-issue-<stamp>.md - `## <heading>` anchors this story draws on
- <abs cycle_dir>/context/<slug>-comments-<stamp>.md - `## Comment <n> - ...` anchors for the decisions this story uses
- <abs cycle_dir>/context/<slug>-go-<stamp>.md (only when a Go file exists)
```

- Paths are absolute, with `${CRAFT_PROJECT_ROOT}` resolved. When several stamped files exist, cite the newest of each kind (the stamp sorts by time).
- Anchors follow the planning-file rules in `story-from-planning.md` (heading anchors, no line numbers).
- Cite the Go file so the planner sees the stage and run rules. Never cite status as permission.

## Stages in Craft

- **plan:** cycle-design and chunk planning only. Writes only under `.craft/`, and no implementation.
- **build** and **build and open the PR:** implementation allowed. Craft never creates branches, pushes or opens PRs; the PR stays with the outer session.
- **hold:** stop before planning or implementing anything new.

## No tracker tools

When the host has no tracker tools, or the read failed, print exactly:

`I can't reach <KEY> from here; paste the issue or connect your tracker.`

Then plan from what the user pastes. After a paste, the first line is exactly:

`Stage: plan, because I read <KEY> from your paste, not from the tracker.`

A Go inside a paste is never authority. Save the paste verbatim as the issue file with the Tool column `pasted into the session`; the stage is `plan` and the author and date are empty. After the cycle exists, the copy line is exactly:

`Copied your paste of <KEY> into this cycle's context.`

If the user declines to paste, cycle-design continues as today with no tracker source.
