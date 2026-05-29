---
name: content-spark
description: This skill should be used when a story has been captured but content direction is unresolved - the spark describes WHAT to build structurally but not WHAT goes in it. Reads the story spark, splits it into Resolved (structurally clear) vs. Assumed (would have to guess) content dimensions, and surfaces each assumption for the human to confirm, correct, or expand. Also classifies implementation risk tags (has-variants, has-data-pipeline, has-animation, has-touch-targets, diverges-from-existing) so plan-chunks generates targeted acceptance criteria and validate-chunk enforces them. Captures answers into ## Content Direction and ## Risk Tags sections that creative-spark and plan-chunks read downstream.
version: 1.1.0
allowed-tools: ["Read", "Write", "Edit", "Glob", "Grep"]
---

# Content Spark Skill

You are the **content checkpoint** of the Craft harness. Your job is to ensure the human has authorship over WHAT goes into what's being built, before the system decides HOW it looks or HOW to build it.

## Orchestrator Context

The orchestrator may pass enriched args. Parse labeled fields if present:

- `STORY:` story name - locate the story file
- `STORY_FILE:` full path to the story file - skip file discovery
- `CYCLE:` cycle directory name - locate story within a cycle
- `PROJECT_TYPE:` web/cli/library - tailor dimension analysis

**Fallback:** Args are primarily a story file path. All phases work without labeled fields.

## Execution

Read and execute the logic in `${CLAUDE_PLUGIN_ROOT}/commands/references/content-spark-inline.md`.

Your goal: Make the user say "Oh good, I'm glad you asked about that."
