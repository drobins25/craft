#!/bin/bash
# PreToolUse hook: auto-approve ALL Bash commands including chained (&&) and $().
#
# Problem: Claude Code prompts for user approval when Bash commands contain
# $() command substitution or are chained with &&. The Bash(*) allow rule in
# settings.json does NOT bypass this — it's a known bug (GitHub #20449, #26796,
# #27139). Plugin settings.json also doesn't propagate to consuming projects.
#
# Solution: Auto-approve ALL commands via hookSpecificOutput. Only deny truly
# destructive commands (rm -rf /, force push to main/master). Everything else
# gets approved — Claude already follows its own safety rules.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Empty command — fall through to normal handling
[ -z "$COMMAND" ] && exit 0

# --- Blocklist: destructive commands that require user confirmation ---

# rm -rf with root path (but not rm -rf ./something which is fine)
if echo "$COMMAND" | grep -qE 'rm\s+-rf\s+/[^.]'; then
  exit 0
fi

# Git: force push (any branch)
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force'; then
  exit 0
fi

# Git: any push - abstain entirely; push-gate.sh owns the push decision
# (it denies on custody violations and explicitly allows clean pushes).
# Emitting allow here could preempt the gate's deny.
if echo "$COMMAND" | grep -qE '(^|\s)git\s+push'; then
  exit 0
fi

# Git: reset --hard (discards uncommitted work)
if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
  exit 0
fi

# Git: checkout . / restore . (discard all working tree changes)
if echo "$COMMAND" | grep -qE 'git\s+(checkout|restore)\s+\.'; then
  exit 0
fi

# Git: clean -f (delete untracked files)
if echo "$COMMAND" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f'; then
  exit 0
fi

# Git: branch -D (force delete branch)
if echo "$COMMAND" | grep -qE 'git\s+branch\s+-D'; then
  exit 0
fi

# Git: rebase (history rewriting)
if echo "$COMMAND" | grep -qE 'git\s+rebase'; then
  exit 0
fi

# Vercel CLI (deploys, env vars, domains, secrets — all require confirmation)
if echo "$COMMAND" | grep -qE '(^|\s|/)(vercel|npx\s+vercel)\s'; then
  exit 0
fi

# SQL: drop table/database
if echo "$COMMAND" | grep -qiE 'drop\s+(table|database)'; then
  exit 0
fi

# Auto-approve everything else
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Auto-approved by craft plugin"}}'
