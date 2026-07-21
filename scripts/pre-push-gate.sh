#!/bin/bash
# pre-push-gate.sh - PreToolUse gate for `git push`: blocks on documentation
# drift, and requires an explicit human keypress on every clean push.
#
# CONTRIBUTOR TOOLING - for developing craft ITSELF. Registered only in
# contributor-local settings (gitignored, not shipped with the plugin). NOT a
# feature for projects built with craft.
#
# Registered as a PreToolUse hook (matcher Bash, if: Bash(git push *)). Reads the
# hook's stdin JSON and runs the caller-agnostic doc-drift core:
#   - drift    -> permissionDecision:deny with the findings as the reason
#   - clean    -> permissionDecision:ask listing the outgoing commits, so the
#                 native permission prompt surfaces and only a human keypress
#                 releases the push. An "ask" outranks any hook allow or
#                 allowlist entry - content approval is never push approval,
#                 and the model cannot answer the prompt for you.
# Always exit 0 + JSON, never exit 2 - exit-2 can make the model stop instead
# of acting on the message. Pairs with scripts/check-doc-drift.sh.
#
# Fails open ONLY on its own tooling: if the command is not a push, jq is
# missing, or the core is absent, it raises no objection and normal permission
# flow applies. A gate that wedged every push on a missing dependency would
# train users to bypass it.

set -uo pipefail

INPUT="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0
COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"

# The settings `if` filter already scopes this to git push; double-check defensively.
# Anchor to `git push` as a command prefix (start, or after whitespace) so the
# backstop is no wider than the filter - a stray "git push" inside an argument or
# comment (e.g. grep "git push" log) must not trigger a check run.
case "$COMMAND" in
  git\ push*|*[[:space:]]git\ push*) ;;
  *) exit 0 ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "${CLAUDE_PROJECT_DIR:-.}")"
CORE="$ROOT/scripts/check-doc-drift.sh"
[ -x "$CORE" ] || exit 0

if findings="$(bash "$CORE" 2>&1)"; then
  # Clean - but publishing still requires an explicit keypress. List the
  # outgoing commits in the prompt so the human approves THESE commits, not
  # just "a push". @{u} may not resolve (no upstream yet) - fall back to
  # naming the command itself; the ask still fires.
  outgoing="$(git -C "$ROOT" log --oneline @{u}..HEAD 2>/dev/null | head -10)"
  if [ -n "$outgoing" ]; then
    count="$(printf '%s\n' "$outgoing" | wc -l | tr -d ' ')"
    reason="Push gate: $count commit(s) outgoing - approve publishing?
$outgoing"
  else
    reason="Push gate: approve publishing? ($COMMAND)"
  fi
  jq -n --arg r "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $r
    }
  }'
  exit 0
fi

# Drift detected: deny with the findings as the reason (jq escapes it safely).
jq -n --arg r "$findings" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Push blocked - documentation drift:\n" + $r)
  }
}'
exit 0
