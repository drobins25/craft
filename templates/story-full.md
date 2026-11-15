---
name: {{STORY_NAME}}
title: "{{STORY_TITLE}}"
status: ready
priority: {{PRIORITY}}
created: {{DATE}}
updated: {{DATE}}
cycle: {{CYCLE_NAME}}
story_number: {{STORY_NUMBER}}
decisions: []
alignment: pending
chunks_total: 0
chunks_complete: 0
current_chunk: 0
---

# Story: {{STORY_TITLE}}

## Spark
{{STORY_DESCRIPTION}}

## The Pitch
<!-- Written during plan-chunks: the plan's sell + conditions table (every load-bearing assumption tagged verified / system-owned / unverifiable -> chunk-first-test) -->

## Content Direction
<!-- Written by content-spark: resolved content dimensions and assumptions -->

## Risk Tags
<!-- Written by content-spark: implementation risk classification -->
```yaml
risk_tags: []
```

## Scope

**Included:**
- {{INCLUDED_1}}
- {{INCLUDED_2}}

**Excluded:**
- {{EXCLUDED_1}}
- {{EXCLUDED_2}}

## Preserve
<!-- Things that MUST remain working. DO NOT touch these. -->
- {{PRESERVE_1}}
- {{PRESERVE_2}}

## Hardest Constraint
<!-- The biggest risk or challenge for this story -->
{{HARDEST_CONSTRAINT}}

## Dependencies
<!-- What this story depends on, and what depends on it -->
**Blocked by:**
- {{DEPENDS_ON_1}}

**Blocks:**
- {{BLOCKS_1}}

## Decisions
<!-- Locked decisions for this story -->

## Visual Direction
<!-- For UI stories only -->
**Vibe:**
**Feel:**
**Inspiration:**
**Motion:**

**Element Binding Table** <!-- UI source of truth: per-element visual intent. plan-chunks fills/verifies; each chunk binds the rows it builds as [visual-source:] Contracts. See chunk-format-guide "Visual Contracts". -->
| Part | Role/State | Token | Value/Source |
|------|------------|-------|--------------|

## Wireframe
<!-- For UI stories - ASCII art of chosen layout -->
```

```

## Likely Files
<!-- Scanned at story creation: file paths with create/modify/read-only action tags.
     Format: `path/to/file.ext` - [action] - [reason]
     Action tags: modify, create, read-only. Only modify/create count for dependency overlap detection.
     Read-only entries are how shipped sibling files reach plan-chunks-agent without nesting. -->

## Reference Materials
<!-- Pinpoint citations for files plan-chunks-agent must read. Anchors by file type:
     - Planning files: `## Section` + `### Subheading` or `Decision #N` or `[YYYY-MM-DD entry]` (NEVER line numbers)
     - Mockups: line ranges OR HTML id/data-section attributes
     - locked.md: Pattern N
     - tokens.yaml: token name
     - Code: function/class name preferred over line numbers
     - active.md dated entries: `## Recent state changes -> [YYYY-MM-DD entry]`
     Multi-anchor per file is the norm. Absolute paths only (wrapper-vs-nested rule). -->

## Chunks
<!-- Implementation chunks: Goal / Files / Contracts / Not covered / Approach / Test cases / Run / Done When -->

## Acceptance
<!-- Given/When/Then format for testable criteria -->
- [ ] Given {{CONTEXT_1}}, when {{ACTION_1}}, then {{OUTCOME_1}}
- [ ] Given {{CONTEXT_2}}, when {{ACTION_2}}, then {{OUTCOME_2}}
- [ ] Given {{CONTEXT_3}}, when {{ACTION_3}}, then {{OUTCOME_3}}

## Definition of Done
- [ ] All chunks complete
- [ ] All acceptance criteria verified
- [ ] Tests written and passing
- [ ] Preserve list confirmed intact
- [ ] No regressions in related features
- [ ] Build passes

## Notes
<!-- Implementation notes, learnings, issues -->
