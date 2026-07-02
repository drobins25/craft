# Using the Living Map (for agents)

This is the how-to-use reference for an agent that orients in a codebase before
doing work. It tells you when to pull the Living Map, how to read it, and - just as
important - when NOT to. The user-facing overview is `map.md`; this doc is the
operating procedure.

Written agent-agnostic on purpose: any consuming agent reads the same rules. Today
only one agent is wired to it; wiring another is a one-line pointer, not a rewrite.

## 0. Resting state: a non-result changes nothing

This is the first rule because it is the one that must always hold. The map is an
optimization you never had to set up, and it must never block or distract you.

If the map call returns an **empty or floored slice** - `{"tier":"floor",...}`, a
`disabled` result, or an empty `slice` field - **proceed exactly as you would with no
map at all.** Do not retry, do not block, do not treat it as an error. Orient from
scratch the way you always have.

There is no "build in progress / try again later" state to wait on: the call is
synchronous and returns a complete slice in one shot, or it returns a floor. So a
non-result is final for this invocation - move on.

## 1. The slice IS your read plan - issue the ranged reads it hands you

When the map returns a real slice, anchor on it as your orientation. Each symbol
line ends in a `[off=N,lim=M]` annotation - the exact, pre-computed parameters for a
targeted ranged read. The procedure:

1. **Issue the annotated Read verbatim.** `Read(<file>, offset=N, limit=M)` with the
   slice's `off`/`lim` exactly as given. The offset is 1-indexed and Read-tool-native -
   no conversion, no arithmetic, no reason to open the whole file.
2. **Prefer the NARROWEST span that covers what you need** - the method or member
   annotation, not the enclosing class annotation. In a one-class-per-file codebase
   the class span IS effectively the file; read a class span only when you genuinely
   need the whole type.
3. **Escalate to the ADJACENT span, never the whole file.** If the span you read is
   not enough, read the sibling annotation above or below it.
4. **Header reads are allowed, bounded.** Imports/usings sit above every span: one
   `Read(<file>, offset=1, limit=<lines before the first span>)` is fine and does not
   count as a whole-file read.
5. **The floor:** a symbol with NO `[off,lim]` annotation has no reliable span - only
   those fall back to a whole-file read. Files the slice does not cover at all are
   read normally.

**A thin slice is not a missing map.** The map is structural: the file-and-symbol
skeleton plus read targets, not prose about conventions or fragile spots. That
thinness is expected - the slice is not something to trust-and-skip, it is a list of
precise read targets. Lean on it and read fewer lines, not more.

## 2. How to pull a slice

The map lives in the plugin and is reached only through its wrapper. Use the
`PLUGIN_ROOT` value injected into your prompt - you CANNOT resolve
`${CLAUDE_PLUGIN_ROOT}` yourself (it is empty in a subagent shell), so the
orchestrator passes you the resolved path. Invoke (substitute the injected
`PLUGIN_ROOT`):

```bash
<PLUGIN_ROOT>/scripts/map/map-run.sh assemble <directory> --root <project-root>
```

- `<directory>` is a directory path relative to the project root (e.g. `src/auth`).
  You get that directory's own files only - no parent or child expansion.
- `--root <project-root>` is the project root you derived for the work at hand. In a
  monorepo this is NOT your shell's current directory, so always pass it explicitly.
  (If you omit `--root`, the map targets the current working directory, which is only
  correct when cwd already is the project root.)

Read the JSON `slice` field as-is. It is a ready-to-read indented outline (file at
the left margin, symbols nested under it). Each symbol line ends in `[off=N,lim=M]` -
paste those straight into a ranged `Read(<file>, offset=N, limit=M)`, choosing the
narrowest annotation that covers your need; a line with no such annotation has no
reliable span - read that one whole. **Never parse, re-key, or reconstruct the
outline** - the slice is a view to read, not a format to interpret. The other fields
(`fileCount`, `tokenEstimate`, `cached`, `firstBuild`, `fyi`) are informational.

## 3. Translate the concept into directories - and cap how many you pull

You think in concepts ("the auth flow"); the map speaks in directories. Bridge the
two from the files your work already points at:

1. Take the files your task is about (the ones your work names or targets).
2. Collect their parent directories.
3. Pull a slice for each of the **few most relevant** directories - the ones your work
   actually clusters in - one `assemble` call per directory.

**Cap it.** If your work is scattered across many distant directories, do NOT pull a
slice for every one, and do NOT widen to a common-ancestor directory to cover them in
one call - for distant files the common ancestor degenerates to the repo root, and a
whole-repo slice is huge and useless. Past the few most relevant directories, just
research the scattered remainder the normal way. The map accelerates orientation where
your work concentrates; it is not a tool for sweeping everything.

## 4. Orientation accelerator, not a search engine

The map answers "what is in this directory I roughly know?" It does NOT answer "where
does this thing live?" Finding scattered pieces of a concept is still a grep job.

So reach for the map to read an area you can already name, not to discover a location.
If you find yourself pulling the map to locate something, stop and grep instead - the
map will come back empty and you will have spent a call learning nothing.

## 5. Kill switch

This whole behavior is opt-in per agent via the one-line pointer that brought you
here. Removing that line from an agent fully reverts it to from-scratch orientation -
no other state to unwind. If the map is not helping (no real saving, or it ever steers
you wrong), the right fix is to drop the pointer, not to work around the map.
