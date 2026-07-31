---
name: research-verify
description: "Verify existing research findings against independent primary sources. Upgrades confidence from 'sources agree' to 'independently verified.'"
argument-hint: "[topic-slug]"
---

# Research Verify

Verify existing research by challenging claims against independent primary sources. This is NOT "go deeper" - it's adversarial validation. The goal is to confirm or refute what the research already says.

## Project Root

Use `$CRAFT_PROJECT_ROOT` (set at session start) as the base path for all `.craft/` references. If not set, resolve by walking up from PWD to find the nearest `.craft/.global-state`.

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`.

## Flow

### Step 1: Select Topic

**If args contain a topic slug** that matches a folder in `$PROJECT/.craft/research/`:
-> Use that topic. Jump to **Step 2**.

**If no args or no match:**
Use **Glob** with pattern `$PROJECT/.craft/research/*/_plan.md` to find all topics.

For each, use **Read** with `limit: 15` to get frontmatter. Only show topics with `status: complete`.

Use **AskUserQuestion** to pick a topic.

### Step 2: Extract Findings

Read the topic's `_plan.md` in full.

Use **Glob** to find all branch files: `$PROJECT/.craft/research/{topic-slug}/[0-9]*.md`

For each branch file, use **Read** to extract:
- All `### Finding N: {title}` entries
- Their `**Confidence:**` level (HIGH/MEDIUM/LOW)
- Their `**Sources:**` references

Build a findings list:

```
| # | Branch | Finding | Confidence | Sources |
|---|--------|---------|------------|---------|
| 1 | 02-claude-code-ecosystem | PostToolUse payload uses tool_response not tool_output | HIGH | [1][2] |
| 2 | 02-claude-code-ecosystem | AskUserQuestion answers live in tool_input | HIGH | [1][2][3] |
| 3 | 01-multi-agent-frameworks | OpenHands dominates at 70.9K stars | MEDIUM | [1] |
...
```

Also check for existing `verification-*.md` files - mark already-verified findings so the user doesn't re-verify them.

### Step 3: Choose Verification Mode

Present the findings table to the user, then ask how they want to verify.

Use **AskUserQuestion**:
```
question: "How should I verify these {N} findings?"
header: "Verification Mode"
options:
  - label: "Source verification"
    description: "Check claims against independent primary sources (verifier agents)"
  - label: "Practitioner review"
    description: "Challenge claims from practical experience - catches 'true in docs, wrong in practice'"
  - label: "Both passes"
    description: "Source verification first, then practitioner review on the results"
  - label: "Cancel"
    description: "Back out"
```

**If "Source verification"** -> Jump to **Step 3b** (select findings), then **Step 4** (verifiers).
**If "Practitioner review"** -> Jump to **Step 4b** (practitioner reviewer).
**If "Both passes"** -> Jump to **Step 3b** (select findings), then **Step 4** (verifiers), then **Step 4b** (practitioner reviewer on results).
**If "Cancel"** -> End.
**If custom text** -> Interpret.

### Step 3b: Select Findings (for source verification)

Use **AskUserQuestion**:
```
question: "Which findings should I verify against sources?"
header: "Findings"
options:
  - label: "All high-confidence"
    description: "Verify all HIGH confidence findings ({N} findings) - these are most dangerous if wrong"
  - label: "All unverified"
    description: "Verify everything not yet verified ({N} findings)"
  - label: "Pick specific findings"
    description: "Choose which ones to verify"
```

**If "All high-confidence"** -> Filter to HIGH confidence findings. Jump to **Step 4**.
**If "All unverified"** -> Filter to findings without existing verification files. Jump to **Step 4**.
**If "Pick specific"** -> Show numbered list, let user pick by number or description. Jump to **Step 4**.
**If custom text** -> Interpret (e.g., "verify findings 1, 3, and 7", "verify everything from branch 02").

### Step 4: Spawn Verification Researchers

For each selected finding, spawn a **researcher agent** in parallel:

```
subagent_type: "craft:verifier"
description: "Verify: {short finding title}"
prompt: |
  ## Your Assignment

  **Claim to verify:** "{exact finding text from branch file}"
  **Original sources cited:** {list of sources from the finding}
  **Branch file:** {path to branch file} (Finding {N})
  **Write your verification to:** {$PROJECT/.craft/research/{topic-slug}/verification-{finding-slug}.md}
```

**Launch ALL verification agents simultaneously.**

### Step 4b: Practitioner Review

Spawn a single **practitioner-reviewer** agent. This agent reads all claims (or all verified claims if running after Step 4) and challenges them from practical experience.

```
subagent_type: "craft:practitioner-reviewer"
description: "Practitioner review: {topic}"
prompt: |
  ## Your Assignment

  **Topic:** {topic name}
  **Research folder:** {$PROJECT/.craft/research/{topic-slug}/}
  **Branch files to read:** {list of branch file paths}
  **Verification files (if any):** {list of verification file paths, or "none - this is the first pass"}
  **Write your review to:** {$PROJECT/.craft/research/{topic-slug}/practitioner-review.md}

  Read all branch files and any verification files. Review every claim from a
  practitioner perspective. Flag anything that doesn't match how these tools
  actually work in practice.
```

After the agent completes, read `practitioner-review.md` frontmatter to get flag counts.

**If running in "Both passes" mode:** Update any verification files where the practitioner flagged a CONFIRMED claim - add `practitioner_flag: true` to the verification file's frontmatter. These claims show as FLAGGED_BY_PRACTITIONER in the results table.

### Step 5: Verification File Format

Each verification agent writes using this format:

```markdown
---
topic: "{topic-slug}"
branch: "{branch-file-name}"
finding: "Finding {N}"
finding_title: "{finding title}"
verdict: CONFIRMED | REFUTED | PARTIALLY_TRUE | UNVERIFIABLE
original_confidence: {HIGH|MEDIUM|LOW}
verified_confidence: {0.0-1.0}
sources_checked: {count}
status: complete
---

# Verification: {finding title}

> Original: [{branch-file-name}]({branch-file-name}), Finding {N}

## Claim
> {One-line summary of the original claim - keep it short, the branch file has the full detail}

## Verdict: {CONFIRMED | REFUTED | PARTIALLY_TRUE | UNVERIFIABLE}

{2-3 sentences explaining the verdict. What confirmed it, what contradicted it,
or why it couldn't be verified.}

## Evidence

### {Source 1 title}
- **Type:** {official docs | changelog | source code | local test | API response}
- **What it shows:** {specific evidence for/against the claim}

### {Source 2 title}
- **Type:** {type}
- **What it shows:** {evidence}

## Sources
1. [{Title}]({url}) - {type} - {what it confirms/refutes}
2. ...
```

**Summary returned to orchestrator** (~150 tokens):

```
FINDING: {branch} / Finding {N}: {title}
VERDICT: {CONFIRMED | REFUTED | PARTIALLY_TRUE | UNVERIFIABLE}
CONFIDENCE: {original} -> {verified}
KEY EVIDENCE: {one-line strongest evidence}
FILE: {path written to}
```

### Step 6: Update Plan

After all verification agents complete:

**Read each verification file header** (frontmatter only, `limit: 15`) to collect verdicts.

**Update `_plan.md` frontmatter** - add or update these fields:
```yaml
verified_findings: {count of CONFIRMED + PARTIALLY_TRUE}
refuted_findings: {count of REFUTED}
unverifiable_findings: {count of UNVERIFIABLE}
practitioner_flags: {count flagged by practitioner, if practitioner review ran}
last_verified: {today's date}
```

**Update branch confidence scores in `_plan.md`:**
- For each branch that had findings verified, recalculate the branch confidence as a weighted average of original confidence and verification results
- CONFIRMED findings: confidence stays or goes up
- REFUTED findings: confidence drops significantly
- PARTIALLY_TRUE: confidence adjusts to the verified_confidence from the verification file
- Note the change in the branch summary (e.g., `[confidence: 0.92 -> 0.95, 3 verified]`)

**Update `_sources.md`** - add a "Verification Sources" section at the bottom with any new primary sources found during verification that weren't in the original research.

### Step 7: Present Results

Display a results table:

> **Verification complete: {topic}**
>
> | Finding | Branch | Verdict | Confidence |
> |---------|--------|---------|------------|
> | {title} | {branch} | CONFIRMED | 0.92 -> 0.97 |
> | {title} | {branch} | REFUTED | 0.88 -> 0.20 |
> | {title} | {branch} | PARTIALLY_TRUE | 0.85 -> 0.70 |
>
> **{N} confirmed, {N} refuted, {N} partially true, {N} unverifiable**
> {If practitioner review ran:} **{N} flagged by practitioner**
>
> {If any REFUTED:}
> **Refuted findings:**
> - {finding title} - {one-line reason it was refuted}
>
> {If any FLAGGED_BY_PRACTITIONER:}
> **Practitioner flags (true in docs, questioned in practice):**
> - {finding title} - {one-line reason from practitioner review}

Use **AskUserQuestion** (options vary based on what has run):
```
question: "Verification complete. What next?"
header: "Next"
options:
  - label: "Verify more findings"
    description: "Pick additional findings to source-verify"
  - label: "Run practitioner review"
    description: "Challenge results from practical experience"
    → only show if practitioner review hasn't run yet
  - label: "View a verification detail"
    description: "Read the full verification or practitioner review file"
  - label: "Done"
    description: "Verification is complete"
```

**If "Verify more"** -> Jump back to **Step 3b** with remaining unverified findings.
**If "Run practitioner review"** -> Jump to **Step 4b**.
**If "View detail"** -> Let user pick, Read and display the file.
**If "Done"** -> End.

---

## File Structure (additions to research folder)

```
.craft/research/
  {topic-slug}/
    _plan.md                        # Updated: verified/refuted counts, adjusted confidence
    _sources.md                     # Updated: verification sources section added
    01-{branch-slug}.md             # Unchanged - original research preserved
    02-{branch-slug}.md             # Unchanged
    verification-{finding-slug}.md  # Lean verdict + evidence, references original (one per finding)
    practitioner-review.md          # Practitioner flags - claims that don't match real-world usage
    ...
```

## Agent Configuration

Two agent types, used independently or together:

### Verifier (`craft:verifier`)
Purpose-built adversarial agent that tries to disprove claims using independent primary sources.

- **Model:** Haiku (constrained scope - one claim, structured verdict; guarded against declaring UNVERIFIABLE before 3+ genuine search attempts)
- **Tools:** Read, Glob, Grep, Bash, Write (plus WebSearch/WebFetch inherited)
- **Posture:** Adversarial - tries to break claims, not confirm them
- **Source rules:** Primary sources only, must be independent from original research sources - if the original quoted a source, re-fetch it rather than re-citing
- **Local-first:** Tests locally (files, commands, APIs) before searching the web
- **Spawning:** One per finding, all in parallel
- **Output:** `verification-{slug}.md` per finding + lightweight verdict summary

### Practitioner Reviewer (`craft:practitioner-reviewer`)
Reads claims and challenges them from practical experience. Catches "true in docs, wrong in practice."

- **Model:** Sonnet
- **Tools:** Read, Glob, Grep, Write (NO Bash, NO WebSearch - this is intentional)
- **Posture:** Practitioner lens - "would someone who uses these tools daily agree?"
- **Does NOT:** Search the web, verify sources, or run commands
- **Spawning:** Single agent, reviews all claims in one pass
- **Output:** `practitioner-review.md` + lightweight flag summary
