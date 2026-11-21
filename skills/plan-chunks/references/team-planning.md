# Team Planning Reference

How to orchestrate parallel story planning using Claude Code agent teams. This is the primary orchestration mode when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is enabled.

---

## Prerequisites

- **Env var:** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` must be set
- **Detection:** Check in Batch Planning step 5 of the orchestrator (SKILL.md)
- **Fallback:** If not set, use Task subagent batches (see SKILL.md Batch Planning step 5)

---

## Agent Teams vs Task Subagents

| Capability | Agent Teams | Task Subagents |
|-----------|-------------|----------------|
| Inter-agent messaging | Yes — teammates message each other | No — fully isolated |
| Idle notifications | Yes — notified when teammate finishes | No — poll or wait |
| Live coordination | Yes — detect file overlap during planning | No — post-hoc cohesion check by orchestrator |
| Batch size control | Same — dependency graph levels | Same |
| Output format | Same — plan-chunks-agent report | Same |
| Failure isolation | Per-teammate | Per-subagent |

**Why agent teams are primary:** Live coordination between planning agents means file overlap, component duplication, and decision conflicts are detected and resolved DURING planning, not after. This produces higher-quality batch plans.

---

## Spawning Teammates

For each story in a batch, create a teammate with the plan-chunks-agent's approach:

```
Task tool:
  subagent_type: "craft:plan-chunks-agent"
  description: "Plan [story-name] (team)"
  prompt: "Research and plan this story as part of a planning team.

  **Story file:** [full path]
  **Cycle directory:** [path]
  **Project root:** [derived path]
  **PLUGIN_ROOT:** [resolved ${CLAUDE_PLUGIN_ROOT} — the subagent cannot resolve it itself]

  **FIRST ACTION — before reading any source file, pull your read plan:**
  [one literal command per scope directory, pre-computed from the story's Likely Files — resolved paths, ready to run; omit only if the story names no files:]
  [resolved PLUGIN_ROOT]/scripts/map/map-run.sh assemble [dir] --root [project root]
  Each slice line ends in [off=N,lim=M] — issue those ranged Reads at the narrowest useful span; never open a whole annotated file. An empty or floored slice for a directory = orient that area normally.

  CRITICAL: SCOPE ALL SEARCHES to the project root above.
  Do NOT search the monorepo root or parent directories.
  Use the project root as the `path` parameter for ALL Glob and Grep calls.

  **Cycle goal:** [goal from cycle.yaml]

  **All stories in cycle (for sibling awareness):**
  [story-name-1]: [spark first sentence]
  [story-name-2]: [spark first sentence]
  ...

  **TEAM MODE:** You are running as part of an agent team. After completing your plan:
  1. Message teammates with: story name, files you plan to modify/create, key decisions
  2. Check teammate messages for file overlap or coordination needs
  3. Note any unresolved coordination in your Teammate Coordination Notes section

  Batch mode: nobody can answer a PLAN FORK or a RESEARCH REQUEST during this run. Your instructions for batch mode say what to do instead.

  Read the story, understand what it needs, then research the codebase and plan chunks.
  Return findings in your structured output format."
```

**Key addition for team mode:** The "TEAM MODE" paragraph tells the planner it is a teammate: before returning, it messages the team with its story's files, new components and key decisions, and records any overlap under Teammate Coordination Notes. In subagent mode, this paragraph is omitted and the agent outputs "N/A - running as isolated subagent."

---

## Batching Strategy

Stories are planned in **dependency graph levels** — not fixed-size batches:

1. Parse `## Dependencies` from each planning story (see SKILL.md Batch Planning step 3)
2. Build topological levels: Level 0 = no in-set blockers, Level 1 = blocked by Level 0 only, etc.
3. Launch all stories in Level 0 in parallel → wait for completion → launch Level 1 → ...

**Why dependency-driven:** With agent-direct story writing, agents return ~200-400 token concerns summaries (not 2000-5000 token plan reports). The orchestrator context bottleneck is gone. Independent stories can all plan in parallel. Only stories that depend on each other need sequential ordering — and the dependency graph already captures this.

**Between levels:**
- Report progress: "Level 0 complete: [story names]. Starting Level 1..."
- Carry forward file overlap findings from earlier levels to later levels' sibling context
- This way later stories are aware of earlier plans

---

## Monitoring Completion

**Agent teams mode:**
- Orchestrator receives idle notifications when teammates finish
- Wait for all teammates in the current batch before proceeding

**Task subagent mode:**
- Task tool returns when subagent completes
- Launch all subagents in a batch simultaneously via parallel Task tool calls
- All return when complete — no polling needed

---

## Collecting Results

After a batch completes:

1. Read each teammate/subagent's output (the plan report)
2. Validate: non-empty, has Implementation Plan, has chunks
3. Store in a results map: `{ story-name: plan-report }`
4. Note any failures: `{ story-name: error-reason }`

**Merge coordination findings:**
- In team mode: coordination notes are already in each agent's output
- In subagent mode: orchestrator builds coordination notes via the comparison at the end of SKILL.md Batch Planning step 7

---

## Fallback Detection

If agent teams spawn fails (env var set but feature unavailable or broken):

1. Catch the error from the first teammate spawn attempt
2. Log: "Agent teams unavailable — falling back to Task subagents"
3. Switch to subagent mode (SKILL.md Batch Planning step 5)
4. Continue with the same stories and batching strategy

**The fallback must always work independently.** Never assume agent teams are available just because the env var is set — the feature is experimental and may be unavailable in some environments.

---

## Graceful Degradation

| Scenario | Behavior |
|----------|----------|
| Agent teams available, all succeed | Best case — coordinated plans with live overlap detection |
| Agent teams available, some fail | Successful plans proceed. Failed stories offered as single-story retry |
| Agent teams unavailable | Automatic fallback to subagent batches |
| Subagent batches, all succeed | Good — post-hoc cohesion check catches overlap |
| Subagent batches, some fail | Same as above — failed stories offered for retry |
| All agents fail | Report failure. Offer single-story interactive planning for each |

The system should never be blocked. Every failure mode has a path forward.
