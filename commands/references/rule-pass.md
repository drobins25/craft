# Rule Pass

You are running a rule pass: mining accumulated fix records in `.craft/fixes/` for patterns worth graduating into `.claude/rules/`. This file is the single source of truth for the procedure - reflect points here; nothing inlines it.

**The design principle is THIN.** All judgment (pattern detection, one-off filtering, knowledge of the live `.claude/rules/` spec) lives inside the `claude-code-guide` agent. Your job is to invoke it, translate its proposals into plain English, take one organic approval reply, write what was approved, and advance the watermark. Do not add clustering, pre-filters, or per-proposal question chains.

## Constraint: Main Loop Only

**This procedure runs from the main conversation loop, never delegated to a Task subagent.** Subagents cannot spawn other subagents, so a delegated pass could not reach `claude-code-guide`. If you are reading this file as a subagent, stop and report back that the pass must run from the main loop.

## The Threshold and the Watermark

- **Threshold:** read `rule_pass_threshold` from `.craft/settings.yaml` via grep. If the file or key is absent, default to **10**. The file is allowed not to exist - never error on a missing settings.yaml.

  ```bash
  THRESHOLD=$(grep -m1 '^rule_pass_threshold:' "${CRAFT_PROJECT_ROOT:-.}/.craft/settings.yaml" 2>/dev/null | sed 's/^rule_pass_threshold:[[:space:]]*//')
  THRESHOLD=${THRESHOLD:-10}
  ```

- **Count:** `hooks/scripts/count-ungraduated-fixes.sh` outputs a bare integer - the number of fix records whose frontmatter `created:` is strictly after `last_pass_at` in `.craft/fixes/.rule-pass-state`. A missing state file means the corpus has never been mined: every record counts.

- **The watermark gates the OFFER, never the agent's input.** The agent always reads the FULL fix corpus. Old fixes are never used up - a one-off correctly rejected in one pass can combine with newer fixes into a pattern in a later pass, and updates to existing rules may cite evidence from any era.

## Step 1: Invoke the Agent

Invoke `claude-code-guide` (built into Claude Code) via the Agent tool with this prompt - it is the validated prompt from the proven run; adapt paths only:

> Read every `.craft/fixes/*.md` and every `.claude/rules/*.md` in this project. Verify the live `.claude/rules/` frontmatter and `paths:` spec against the official Claude Code docs before proposing any format. Find patterns where 2-3+ fixes point the same causal direction. Ruthlessly reject one-offs (a prior calibration run found ~41% of fix records rule-worthy and ~59% correctly rejected - expect to reject most). For each pattern, propose either UPDATE-existing (preferred - quote the loose part of the current rule and the tightened wording) or NEW (complete spec-correct file content, with `paths:` glob-scoping if the rule is file-type-specific). Cite the supporting fix names for every proposal. Output proposals only - write nothing.

While the agent runs, tell the user what is happening (it reads the whole corpus; expect a couple of minutes).

## Step 2: Present Proposals in Plain English

Translate the agent's proposals before presenting - the agent may be technical in its analysis; the user gets plain English. Number each proposal so the user can reply with numbers. Each proposal gets:

1. A number and a plain-English name, tagged **(update to existing rule)** or **(new rule)**
2. One to two sentences: what kept going wrong, and what the rule would prevent
3. The supporting fix names as evidence

Format:

```
**Rule pass complete. [N] proposals from [M] fixes:**

**1. [Plain-English name] (update to existing rule)**
[What went wrong across the cited fixes. What the tightened rule prevents.]
*Evidence: [fix-name], [fix-name], [fix-name]*

**2. [Plain-English name] (new rule)**
[What went wrong. What the rule prevents.]
*Evidence: [fix-name], [fix-name]*

...

Which should I write? (e.g. "1 and 3", "all", "none", or ask me about any of them)
```

If the agent rejected everything (zero proposals), say so plainly, note roughly how many records it reviewed, and skip to Step 5 - the pass still completes and the watermark still advances.

## Step 3: The Review Guardrail

**Only write rules the user explicitly named or clearly approved.** "1 and 3", "all", "the first two" are approvals. An ambiguous reply about a proposal ("hmm, the third one is interesting") is NOT approval - ask about that specific proposal instead of guessing. If the user asks to modify a proposal's wording, apply their modification and confirm it landed in the written rule.

This is one organic conversation reply - never a chain of per-proposal AskUserQuestion prompts.

## Step 4: Write Approved Rules

Start this step only when every proposal has a clear yes or no from Step 3, including any you asked about there, so nothing in this step waits on the user. Before the first write, open this session's write gate:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/write-gate.sh open rule-pass
```

If the open exits non-zero, stop this write step and show the gate script's message. Then end the pass here, with no receipt and no watermark, so the offer returns next time.

Write each approved rule to the current project's `.claude/rules/`. Updates edit the existing rule file; new rules create a new file with the agent's spec-verified content.

That is the entire write surface. No commit, no gitignore check, no tracking caveat - committing is the user's normal git life.

## Step 5: Receipt, Then Watermark

First, before the receipt line or anything else, close the gate:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/write-gate.sh close rule-pass
```

Print one unambiguous closing statement:

```
Rule pass receipt: wrote [N] rules ([filenames]), skipped [M], modified [K] per your notes. Watermark advanced.
```

Then - and only then - advance the watermark by writing today's date:

```bash
printf 'last_pass_at: %s\n' "$(date +%Y-%m-%d)" > "${CRAFT_PROJECT_ROOT:-.}/.craft/fixes/.rule-pass-state"
```

**Advance rules:**
- Pass completed, some or all proposals approved -> advance.
- Pass completed, every proposal rejected (or zero proposals) -> still advance. The corpus was reviewed; re-offering the same evidence next time is the nag this design avoids.
- The user declined the OFFER (the pass never ran) -> do NOT advance. The caller handles this case; if you are reading this file, the offer was accepted.

The state file is durable - it survives sessions and is only ever written by this step.
