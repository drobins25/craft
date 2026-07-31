---
name: guide
description: "Ask the craft guide how craft works or how to use it on your project. Read-only - it explains how craft's commands, skills, agents, and lifecycle work, and diagnoses your actual .craft/ setup. It never changes anything."
argument-hint: "[your question about using craft]"
---

# Guide

The explicit front door to the **craft guide** - an educated, read-only guide to using craft itself. It also auto-triggers on craft how-to questions; this command is the guaranteed way to reach it on purpose.

The guide reads craft's real source files and your project's `.craft/` state to answer accurately. It explains and diagnoses; it never writes, edits, or runs anything.

## Flow

### Step 1: Get the question

**If args provided:** the args are the question.

**If no args:** Use **AskUserQuestion** with one free-text question - "What do you want to understand about craft?" - and a single "(type response)" option. Take the user's typed text as the question. Examples to set expectation in the option description: "how does plan-chunks work", "what should I use - a fix or a story", "why isn't my story implementing".

### Step 2: Delegate to the guide agent

Invoke the **`guide`** subagent (via the Agent/Task tool). The prompt MUST contain two things:

1. The user's question.
2. The resolved plugin root, on its own line: `PLUGIN_ROOT: ${CLAUDE_PLUGIN_ROOT}` - inject the resolved value. This command body resolves `${CLAUDE_PLUGIN_ROOT}`; the subagent CANNOT (it is empty in a Task shell). Without it the guide has no trustworthy path to craft's source and is instructed to say so rather than hunt the filesystem - so omitting it degrades every answer.

The guide is read-only (Read, Glob, Grep): it reads craft's source under the injected `PLUGIN_ROOT` and the user's `./.craft/` state, grounds its answer in the actual files, and hands off any pure Claude Code parts to claude-code-guide.

Do **not** answer the craft how-to question yourself from memory - route it to the guide so the answer is source-grounded, not recalled.

### Step 3: Relay

Present the guide's answer as given. If the guide flagged something it noticed while answering (a messy `.craft/`, several near-identical fixes that smell like a missing rule, an orphaned story), surface that aside exactly as the guide framed it - and leave the decision to the user. The guide advises; it never acts.
