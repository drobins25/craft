---
name: approve
description: "Request write permission from the user before making file changes. MUST be invoked before any write attempt when the write gate is closed. Creates scoped approval via AskUserQuestion and a printed approval line, opens the write gate, and closes it when work is done. Triggers: write hook blocks an edit, agent is about to write files outside .craft/, agent needs to modify project source files. This skill requires user approval 100% of the time - never bypass AskUserQuestion."
allowed-tools: ["Read", "Bash", "Glob", "Grep", "AskUserQuestion"]
---

# Write Approval

You are requesting permission to write files. This skill gates ALL writes outside `.craft/` and `.claude/` directories. It requires explicit user approval every single time - no exceptions, no bypass, no auto-approve.

## When to Use

Call this skill BEFORE your first write attempt when:
- The write hook has blocked you (or will block you)
- You're about to modify project source files
- You're about to create new files outside `.craft/`
- Any workflow stage involves writing to the project

Do NOT call this for writes to `.craft/` or `.claude/` directories - those are always allowed.

## The Flow

### Step 1: Describe the Scope

Before asking for approval, gather what you're about to do. Be specific:
- Which files will be created or modified
- What changes will be made (brief, not the full diff)
- Why (what triggered this - workflow stage, fix, feature work)

### Step 2: Ask for Approval (MANDATORY)

Use **AskUserQuestion**. This step CANNOT be skipped. Ever.

```
question: "I need write access to make these changes. Approve?"
header: "Write Access"
options:
  - label: "Approve"
    description: "{summary of what will be changed}"
  - label: "Deny"
    description: "Block these changes"
  - label: "Modify scope"
    description: "I want to adjust what's allowed"
```

**If "Deny"** -> Stop. Do not open the gate. Report to the caller that writes were denied.

**If "Modify scope"** -> Let the user describe the adjusted scope. Re-present the AskUserQuestion with the new scope. Loop until approved or denied.

**If "Approve"** -> Continue to Step 3.

### Step 3: State the Approval

Print this to the user, in your reply:

```
Approved: {brief description of changes}
Files: {file list}. Scope: {what was approved}.
I open the write gate now and close it when this work is done.
```

These lines are the record of what was approved.

### Step 4: Open the Gate

Run via Bash:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/write-gate.sh open approve
```

The write gate is now open. The agent can write files.

### Step 5: Do the Work

The caller (workflow, fix skill, implementer, etc.) performs the approved changes. The gate stays open until the caller closes it in Step 6.

**This skill does NOT do the writing itself.** It opens the gate and returns control to the caller. The caller writes, then calls back to close.

### Step 6: Close the Gate

When the approved work is done, the caller MUST close the gate:

1. Close the write gate:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/write-gate.sh close approve
```

2. Print "Write gate closed." to the user.

## Safety Rules

1. **AskUserQuestion is mandatory.** Every invocation. No exceptions. If the skill is called 5 times in a session, the user is asked 5 times.
2. **Scope is enforced by visibility.** The user sees exactly what was approved in the approval question and the approval line printed in Step 3. If the agent writes files outside that scope, the difference is visible against that line.
3. **Gate closes explicitly.** The gate does not auto-close on a timer. The caller must close it. If the session ends with the gate open, the SessionEnd hook removes this session's gate file.
4. **No nesting.** If the gate is already open (from a story or another approval), this skill is not needed. Check first:
```bash
${CLAUDE_PLUGIN_ROOT}/hooks/scripts/write-gate.sh holder
```
If it prints a holder (a line not starting `write-gate:`), this session already holds a gate: skip this skill.
