---
name: craft:ask
description: "Consult a craft agent. Routes your question to the best mind in the workshop - not a menu, a recommendation."
argument-hint: "[your question]"
---

# Ask

Consult a craft agent. The skill reads your question, scans the available agents, and recommends who to talk to - like a bartender who knows your order before you say it.

## Project Root

Use `$CRAFT_PROJECT_ROOT` (set at session start) as the base path for all `.craft/` references. If not set, resolve by walking up from PWD to find the nearest `.craft/.global-state`.

Set `PROJECT` to `${CRAFT_PROJECT_ROOT:-.}`.

## Flow

### Step 1: Get the Question

**If args provided:** Use the args as the question.

**If no args:** Use **AskUserQuestion**:
```
question: "What do you want to ask?"
header: "Ask"
options:
  - label: "Feature gut check"
    description: "Will anyone care about this? Is it compelling or just useful?"
  - label: "Design direction"
    description: "Does this feel right? What's the visual/emotional read?"
  - label: "Decomposition review"
    description: "Is this story scoped right? Where are the natural seams?"
  - label: "QA adversary"
    description: "Where will this break? What am I not testing?"
```

If user picks an option, ask a follow-up: "Give me the details - what specifically are you working on?"

Store the full question as `{QUESTION}`.

### Step 2: Gather Context

Read project context to enrich the agent prompt. Do this silently - no user interaction.

- Read `$PROJECT/.craft/project.md` (first 30 lines - stack, conventions)
- Read `$PROJECT/.craft/.global-state` (active cycle, current story)
- If CURRENT_STORY is set, read the story file frontmatter

Store as `{CONTEXT}`.

### Step 3: Discover Agents

Use **Glob** to find all agents: `${CLAUDE_PLUGIN_ROOT}/agents/*.md`

For each agent file, read the first 15 lines (frontmatter only). Extract:
- `name:` field
- `description:` field (contains trigger conditions and consulting guidance)

Skip agents that are purely operational (chunk-validator, implementer, tester, plan-chunks-agent, project-scanner, verifier, practitioner-reviewer). These are internal to the craft pipeline and not designed for consultation.

**Consultable agents** are those whose descriptions include phrases like "Consult when", "Trigger conditions", or are crystallized workshop agents.

Build a list of consultable agents with their names and descriptions.

### Step 4: Route (The Bartender Moment)

Read the user's question against the agent descriptions. Pick the **best match** and optionally a **second opinion** agent.

Present the recommendation. Do NOT show a full list of agents - show your read of the situation:

> "This sounds like a **{Agent Name}** question - {one sentence explaining WHY this agent fits, drawn from its beliefs or trigger conditions}."
>
> If a second agent is relevant:
> "The **{Agent 2 Name}** might also have a take - {one sentence on the different angle}."

Use **AskUserQuestion**:
```
question: "Who do you want to hear from?"
header: "Consult"
options:
  - label: "{Agent 1 Name} (Recommended)"
    description: "{Why this agent fits}"
  - label: "{Agent 2 Name}"
    description: "{The different angle}"
  - label: "Both"
    description: "Get both perspectives"
  - label: "Someone else"
    description: "I have a different agent in mind"
```

**If "Someone else":** Show the full list of consultable agents. Let user pick.

### Step 5: Invoke

For each selected agent, invoke via the **Agent** tool:

```
Agent tool:
  subagent_type: "craft:{agent-name}"
  description: "Consult: {agent-name}"
  prompt: |
    ## Question

    {QUESTION}

    ## Project Context

    {CONTEXT}

    ## Instructions

    Answer the question from your perspective. Draw on your beliefs,
    scar tissue, and instincts. Be direct and opinionated. If the
    question is outside your domain, say so and suggest who would
    be better suited.

    Keep your response focused - no preamble, no hedging.
```

**If "Both":** Run both agents (can be parallel). Present responses with clear attribution:

> **{Agent 1 Name}:**
> {response}
>
> ---
>
> **{Agent 2 Name}:**
> {response}

### Step 6: Continue or Done

After showing the response:

Use **AskUserQuestion**:
```
question: "Helpful? Want another perspective?"
header: "Next"
options:
  - label: "Another perspective"
    description: "Ask a different agent the same question"
  - label: "Follow up"
    description: "Ask this agent a follow-up question"
  - label: "Done"
    description: "Got what I needed"
```

**If "Another perspective":** Go back to Step 4 with the remaining agents (exclude already consulted).

**If "Follow up":** Ask for the follow-up question. Use **SendMessage** to continue the same agent conversation (preserves context). Then re-present this AskUserQuestion.

**If "Done":** End.

## Quick Usage

```
/craft:ask "Will anyone care about this notification feature?"
/craft:ask "Is this story too big? Should it be two stories?"
/craft:ask "Where will this auth flow break?"
```

## Rules

- The routing recommendation is the feature. Lead with WHY this agent fits, not a menu.
- Never show the full agent list upfront. Recommend first, list on request.
- Project context is gathered silently - the user just asks a question.
- Agents answer from their beliefs, not generic best practices. That's the point.
- The "Both" option runs agents in parallel and presents side-by-side.
- Follow-ups continue the same agent conversation via SendMessage.
