---
name: plan-chunks
description: This skill should be used when the user asks to "plan chunks", "break this down", "plan the implementation", or when a story has status planning and needs implementation details before building. Required before any story can be implemented. Turns a story into a chunk-by-chunk build plan with file lists, the contracts chunks share, named tests and risks. Supports parallel planning of multiple stories via batch mode.
version: 5.0.0
allowed-tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "Task", "Skill", "SendMessage"]
---

# Plan Chunks (Orchestrator)

You coordinate planning. The plan-chunks-agent researches the codebase and writes the plan into the story file. Your job: make sure the story is fit to plan, launch the planner, check what it wrote, take the decisions that belong to the user to the user, and mark the story ready when they approve.

The user builds products from these plans and does not read them line by line, so two things matter most: the user sees every decision that was theirs to make, and nothing reaches implementation that would leave the implementer guessing.

Never start this skill on your own initiative. The user must have asked to plan, through a command, a flow that offered it, or their own words.

## Inputs

Callers may pass labeled fields; use them to skip rediscovery, and work without them when absent:

- `STORY:`, `CYCLE:`, `CYCLE_GOAL:`, `SIBLINGS:` - where the story sits and what is around it
- `APPROACH:`, `DECISIONS:`, `KEY_FILES:` - context from an earlier discussion; pass it to the agent as a starting point to check, not as settled fact
- `DEPTH:` - creative / smart / spark; how much triage to do
- `MODE: batch` - plan every planning story in the cycle (see Batch Planning)
- `DIRECTION_CONFIRMED: true` - the caller already confirmed direction with the user

**Project root** is the story file's path up to `/.craft/`. Don't use `$CRAFT_PROJECT_ROOT` for it; in a monorepo it can point at the wrong level.

**Under a Go run** (only when `${CLAUDE_PLUGIN_ROOT}/commands/references/go-run.md` is in force for this conversation): at the start run `python3 "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/go-brief.py" <cycle-dir>`. On `prompts=answer`, every prompt and card here follows go-run.md's `## Known prompts` and `## Planning`, and the implementation hand-offs go to its `## At the stage ceiling`. Any other verdict ends the Go run as go-run.md says, and this skill asks everything as written.

**Autonomous mode** (invoked from `craft:story-implement-auto`): skip the content, alignment, visual and direction checks; nobody is there to answer them.

## The planning stage

The progress band shows every terminal which planning phase a story is in, from a `planning_stage` field in the story's frontmatter. Keep it true, and only through the script, which writes the line atomically so other terminals never read a half-written file:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/planning-stage.sh [story-file] <stage>
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/planning-stage.sh [story-file] clear
```

Stages: `content-check`, `alignment-check`, `direction`, `planner`, `plan-check`, `triage`. Write a stage when its phase begins (never for a skipped phase, again on re-entry). Marking the story ready clears it. Every other way out (the user stops, a story is excluded, an error ends the flow) runs `clear` first, because a leftover stage shows a story nobody is planning. In batch, one call per story.

## Phase 0: Get the story ready

Read the story file. For a story in a cycle, read its `cycle.yaml`; if it has a non-empty `source_issue`, Read `${CLAUDE_PLUGIN_ROOT}/commands/references/tracker-follow.md` with that cycle's directory and continue only through its `## Continue`.

Sibling stories: use `SIBLINGS:` if given; otherwise look at the cycle's other stories and keep the ones that share files, components or terms with this one. Their names, files and decisions go to the agent so it reuses instead of rebuilding. (Details: `${CLAUDE_PLUGIN_ROOT}/skills/plan-chunks/references/research-integration.md`.)

### Phase 0.4: Content direction

(Skip in batch; batch checks it per story in Batch Planning.) If the story has no non-empty `## Content Direction`, write stage `content-check` and ask on a card headed `Prerequisite`: `Run content-spark first (Recommended)`, or plan anyway. To run it, Read `${CLAUDE_PLUGIN_ROOT}/commands/references/content-spark-inline.md` and follow it against this story. Never invoke it through the Skill tool, because a nested skill breaks control flow back to this one.

### Phase 0.45: Alignment

Skip when the frontmatter says `alignment: complete` and the story has an `## Alignment` section. Otherwise write stage `alignment-check`, Read `${CLAUDE_PLUGIN_ROOT}/commands/references/alignment-check.md` and run its loop: it surfaces conflicts with existing code and product questions only the user can answer, records the `## Alignment` section and sets `alignment: complete`. In batch, list the stories that need it and ask whether to run them first or let the agents use their judgment.

### Phase 0.46: Visual direction

Only for `type: ui` stories, not in batch, and only when `## Visual Direction` has no filled-in binding table (a row for each part of the wireframe). Write stage `direction` and ask on a card headed `Prerequisite`: riff visual options first (recommended), or `Skip - I know what I want`. To riff, Read `${CLAUDE_PLUGIN_ROOT}/commands/references/creative-spark-inline.md` and follow it.

### Phase 0.5: Direction confirmation

Skip when `DIRECTION_CONFIRMED: true`, or when the user's own words in this session asked to plan this story. Otherwise write stage `direction`, show the story title and Spark, and ask: plan it, explore creatively first (clear the stage and stop), or adjust the scope (discuss, update the Spark, ask again). In batch, show all sparks in one table and ask once: plan all, review individually, or exclude some.

## S-1: Launch the planner

Write stage `planner` (every launch, including re-launches). Invoke the Task tool with `subagent_type: "craft:plan-chunks-agent"`. The prompt carries:

- The story file's full path, the cycle directory (or `backlog`), and the project root.
- `PLUGIN_ROOT: <resolved ${CLAUDE_PLUGIN_ROOT}>` - the agent cannot resolve that variable itself.
- A FIRST ACTION block when the story names files (Likely Files, `KEY_FILES:`, Scope): one ready-to-run line per relevant directory, resolved, so the agent orients from the map before opening files:
  ```
  **FIRST ACTION - before reading any source file, pull your read plan:**
  [PLUGIN_ROOT]/scripts/map/map-run.sh assemble [dir] --root [project root]
  Each slice line ends in [off=N,lim=M] - issue those ranged Reads. An empty slice means orient that area normally.
  ```
- Sibling context, the cycle goal, and the story's Content Direction text if present.
- `APPROACH:`, `DECISIONS:`, `KEY_FILES:` when given, introduced as "starting context to check against the code, not settled fact".
- "Keep every Glob, Grep and Read inside the project root."
- "Write the planned story file with Write, keep status: planning, and return only your concerns summary."

## S-2: Check what came back

**A PLAN FORK** means the agent hit a decision that belongs to the user and splits the plan in two. Read `${CLAUDE_PLUGIN_ROOT}/commands/references/question-card.md` and ask it as one card. Send the answer back: SendMessage to the agent's ID if the launch result showed one; otherwise re-launch S-1 with the answer in the prompt. Never guess an address.

**A RESEARCH REQUEST** means a load-bearing outside fact three searches did not settle. If the story already has a `planner door` run line, ask the user on a card what the plan should assume. Otherwise Read `${CLAUDE_PLUGIN_ROOT}/commands/references/research-inline.md` with `QUERY` = the request's Question, `STORY`, `DOOR=planner`; then write stage `alignment-check`, run `${CLAUDE_PLUGIN_ROOT}/commands/references/alignment-check.md` from Step 0 skipping its outside-world step; then re-launch S-1 with the answer in the prompt.

**A concerns summary** means the plan is written. Write stage `plan-check` and read the story file. Check that:

1. It has `## Chunks` with at least one `### Chunk N:` heading.
2. `chunks_total` in the frontmatter matches the number of chunks, and there are no more than 7.
3. Every chunk has **Goal**, **Files** (each line `` `path` - create ``, `modify` or `read-only`), **Contracts**, **Test cases**, **Run** and **Done When**. A chunk that changes only docs or prompts needs no Test cases or Run.
4. Every chunk that changes code has a Done When item saying its Run commands pass. A chunk that leaves the project broken until the next one finishes cannot be checked on its own.
5. `## The Pitch` has a sell and a `| Condition | Secured by |` table, every row tagged `verified`, `system-owned` or `unverifiable`.
6. `## Acceptance` lists specific, checkable criteria.
7. For a UI story with a filled-in Visual Direction binding table, every non-`TBD` row is pinned in some chunk's Contracts with a `[visual-source:]` receipt.
8. Every Spark requirement has a home in some chunk. Read the Spark, list what it asks for, and find each one.
9. No **Not covered** line leaves out a risk that a file some chunk creates or modifies could guard against, or gives as its reason that another program, script or person will behave. Those are covered by a contract and a named test.

If check 1 fails, the agent did not plan: plan inline yourself, following `${CLAUDE_PLUGIN_ROOT}/agents/plan-chunks-agent.md`, rather than blocking the user. If any other check fails, show the user the numbered failures and ask on a card: `Re-plan with the failure list` (re-launch S-1 with it), fix the story file by hand (clear the stage and stop), or go on to triage with the gaps named. Re-plan is the proposed option until the planner has been re-launched once for failed checks on this story. After that, whichever check fails, the card is still asked and its proposed option is to go on to triage, with each failure still standing printed at the top of triage's settled list, so a run never loops.

## S-3: Triage with the user

Write stage `triage`. Read `${CLAUDE_PLUGIN_ROOT}/commands/references/question-card.md` once; it decides how every card reads. This step decides only which items reach a card. One card per item, never several concerns folded into one "all good?", because a folded list gets approved without being read.

In order:

1. **Critical Blockers** - one card each. If a blocker means the story cannot be planned, clear the stage, stop and say why.
2. **Flagged Concerns** - low confidence: a card with the agent's pick marked proposed and the alternative. Medium: the same plus "keep the plan as written". High: no card; it goes on the settled list.
3. **Not covered** - every risk the planner named and left out of the plan goes on the settled list by name with its reason, so nothing is dropped unseen. The planner is told to cover any risk a user would see or lose data to; if one of those is on a Not covered line anyway, it gets a card: accept it as it stands (proposed), or stop here and re-plan. Never re-launch the planner from inside triage, because it rewrites the story file and the answers already applied would be lost.
4. **Design Decision Validation** - any `concern` or `invalid` row: one card with what the story decided, what the code showed, the agent's fix (proposed) and the honest cost of keeping the original.
5. **Decisions Made** - by Product-stake: `ask` gets a card whatever the confidence; `mention` goes on the settled list; `silent` stays in the table.
6. **Cycle Impact** - one card per row that isn't "none": split the story or keep it whole; reorder the cycle or keep the order; extra work becomes its own story or stays out.

After each answer, apply its edit to the story file right away and say in one line what changed ("kept as planned" for a no-op), so answers survive a session that dies mid-triage. Edit in place, change only what the answer changes, and never touch `## Reference Materials`.

Items that reach no card are printed before the first question under `Settled without asking - say which to reopen`. When nothing reaches a card, say "No risks or concerns flagged - plan looks clean." and go straight to approval with the settled list on top.

## S-4: Approve

Read the story file fresh and present the plan: total chunks and files, the settled list if it wasn't shown yet, the File Impact table, then each chunk as written. Ask whether the plan looks complete: `Yes, mark ready` or `Mark ready and start implementing now`.

Either answer: confirm every triage answer landed, then

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/update-story-status.sh [story-file] ready
```

## S-6: Hand off

**Hand-back rule.** If story-implement or cycle-start is anywhere up the current call chain, that flow is waiting to resume: on "start implementing", say in one line that the story is ready and control returns to it, and return. Never invoke story-implement from inside a flow that is waiting on you; it would run twice.

With nothing waiting:
- `Mark ready and start implementing now` invokes the Skill tool with `skill: "craft:craft-story-implement"`, `args: "[story-file-path]"`. Never implement directly.
- `Yes, mark ready` offers: `Yes, implement now` (same Skill invocation, or the hand-back rule), plan another story, or `Come back later`.

## Batch Planning (`MODE: batch`)

1. **Find the stories.** List `[cycle]/stories/*.md` with `status: planning`. None: say so and stop. One: plan it as a single story.
2. **Content direction.** Write stage `content-check` per story; if any lack `## Content Direction`, ask once whether to run content-spark on them first (inline, as in Phase 0.4) or plan anyway.
3. **Dependencies decide the order.** Every story needs a `## Dependencies` section with a `**Blocked by:**` line and a `## Likely Files` section; if one is missing, stop and ask the user to fill it in (or scan Likely Files now) or cancel, clearing every stage on cancel. A story that says "Blocked by: None" but shares a modify/create file with another batch story gets one card: which plans first, or truly independent (record that on its Blocked by line so it isn't asked again). Then group stories into levels: level 0 has no blockers in the batch; each later level depends only on earlier ones. A circular pair is excluded and reported.
4. **Levels plan in order, never together.** Planners decide names, IDs, file ownership and formats; a planner that runs before its predecessor's plan exists invents its own versions, and the stories then disagree. Tell the user the levels and a rough time (about 8 minutes per level).
5. **Launch each level.** Write stage `planner` per story. With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, spawn teammates (details: `${CLAUDE_PLUGIN_ROOT}/skills/plan-chunks/references/team-planning.md`); otherwise launch Task agents with `run_in_background: true` so each summary is saved to disk and survives compaction, and record each story's output file path. Each prompt carries what S-1 lists, plus the other stories' names, sparks and Likely Files, plus: "Batch mode: PLAN FORK and RESEARCH REQUEST are unavailable. Decide down your recommended branch, set its product stake to ask, and list it as a Critical Blocker." Wait for the whole level before launching the next.
6. **Pass contracts forward.** For each story in the next level, read each blocker's finished story file and include its chunks' Goal, Files and Contracts only, with: "This plan comes first. Use its names and shapes, extend it rather than duplicating it, and note anything you need it to add."
7. **Check each plan, one at a time.** Read each output file and story file in turn (stage `plan-check`), run the S-2 checks, and keep only the metadata: chunks, files, concerns, File Impact. Never hold two plans in context. Then compare File Impact tables across stories for shared files, duplicate components and conflicting decisions; each is a triage item.
8. **Failures.** If any story failed, ask: retry the failed ones as single stories, skip them, or retry all (clear stages accordingly).
9. **Triage.** Read `${CLAUDE_PLUGIN_ROOT}/skills/plan-chunks/references/batch-triage.md` and run it (BT-1 to BT-7). One card per item, grouped by story; approval reads each story file fresh, one story at a time.
