#!/bin/bash
# push-gate.sh - PreToolUse gate for `git push` (plugin-shipped).
#
# Denies a push while either custody signal is live:
#   1. Untriaged leftovers - ledger entries with decision: pending. The deny
#      reason instructs the orchestrator to run the leftover triage and retry.
#   2. Secret-shaped paths in the outgoing range @{u}..HEAD, matched against
#      the shared deny-pattern list (secret-deny-patterns.sh).
#
# On a clean tree with a triaged ledger it emits an EXPLICIT allow: a
# PreToolUse hook that exits 0 with no output does NOT approve the call
# (verified against the hooks docs - "staying silent doesn't approve it"),
# and auto-approve-plugin-scripts.sh deliberately abstains on git push, so
# without this allow every plain push would fall to a permission prompt.
#
# Output is exit-0 JSON (hookSpecificOutput.permissionDecision) - NEVER
# exit 2, which can make the model stop instead of acting on the reason.
#
# Fails OPEN on every tooling gap: missing jq, missing helper scripts,
# unresolvable project root, no upstream (the secret scan is impossible
# without @{u} - documented boundary for local-only repos), or an
# unreadable/unparseable ledger. A custody gate that wedged every push on
# its own tooling would train users to bypass it.

set -uo pipefail

INPUT="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0
COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"

# Anchor to `git push` as a command prefix (start, or after whitespace) so a
# stray "git push" inside an argument (e.g. grep "git push" log) never triggers.
case "$COMMAND" in
  git\ push*|*[[:space:]]git\ push*) ;;
  *) exit 0 ;;
esac

# Locate the project: CLAUDE_PROJECT_DIR env var first, stdin-JSON cwd as
# fallback - never the hook process cwd.
ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
fi
{ [ -n "$ROOT" ] && [ -d "$ROOT" ]; } || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/triage-ledger.sh" ] || exit 0
[ -f "$SCRIPT_DIR/secret-deny-patterns.sh" ] || exit 0
source "$SCRIPT_DIR/triage-ledger.sh"
source "$SCRIPT_DIR/secret-deny-patterns.sh"

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# --- Check 1: untriaged leftovers (bounded query - pending entries only) ---
UNTRIAGED="$(ledger_list_untriaged "$ROOT" 2>/dev/null || true)"
if [ -n "$UNTRIAGED" ]; then
  deny "Push blocked - untriaged leftover files in the triage ledger:
$UNTRIAGED
Run the leftover triage (one AskUserQuestion per file: ignore / claim / leave - see story-implement sub-step 8b), then retry the push."
fi

# --- Check 2: secret-shaped paths in the outgoing range ---
# Requires an upstream; a local-only repo skips this scan (documented boundary).
if git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  SECRETS=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if matches_secret_pattern "$f"; then
      SECRETS="${SECRETS}${f}
"
    fi
  done < <(git -C "$ROOT" diff --name-only '@{u}..HEAD' 2>/dev/null || true)
  if [ -n "$SECRETS" ]; then
    deny "Push blocked - secret-shaped paths in outgoing commits (@{u}..HEAD):
${SECRETS}Remove these from the outgoing history before pushing. The pattern list lives in hooks/scripts/secret-deny-patterns.sh."
  fi
fi

# --- Clean: explicit allow so plain pushes stay frictionless ---
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "craft push gate: no untriaged leftovers, no secret-shaped outgoing paths"
  }
}'
exit 0
