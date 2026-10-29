#!/bin/bash
# self-update.sh - SessionStart hook: craft keeps itself current.
#
# Claude Code refreshes only Anthropic's own marketplaces on its own, so craft
# does it for the craft marketplace: once a day, in the background, through the
# two commands a user would otherwise run by hand:
#   claude plugin marketplace update craft
#   claude plugin update craft@craft
# The new version loads in the user's next session.
#
# Two modes.
#   no args    The hook entry. Never slow: prints at most one JSON line with a
#              systemMessage for the user (a first-run disclosure, or a notice
#              that an update landed), spawns the worker detached when a check
#              is due, exits 0.
#   --worker   Runs the two commands, logs, and leaves a one-line notice for
#              the next session start when the files changed.
#
# Silent exits, in order: self-update is off (CRAFT_AUTO_UPDATE=0 or a
# no-auto-update file in the data dir, or Claude Code's own DISABLE_AUTOUPDATER,
# DISABLE_UPDATES or CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC); the claude CLI
# is not on PATH; this copy is not the marketplace install under
# plugins/cache/craft/craft/ (a --plugin-dir checkout, a local-path marketplace,
# or a copy synced from claude.ai, none of which `claude plugin update
# craft@craft` could touch); there is no data directory for the stamp.
#
# State lives in CLAUDE_PLUGIN_DATA, which survives updates (the cache directory
# does not):
#   self-update.stamp      epoch seconds of the last check
#   self-update.disclosed  exists once the one-time disclosure has been shown
#   self-update.notice     one line to show the user at the next session start
#   self-update.log        last 50 lines of what the worker saw
#   no-auto-update         create this file to turn self-update off
#
# Stdout is parsed as JSON by Claude Code, so nothing here prints anything
# except the one systemMessage line. A nested run (the claude plugin commands
# can fire SessionStart hooks in a child) exits at the first guard.
set -uo pipefail

MODE="${1:-}"
DATA="${CLAUDE_PLUGIN_DATA:-}"
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
INTERVAL="${CRAFT_SELF_UPDATE_INTERVAL:-86400}"
MARKETPLACE="craft"
PLUGIN_ID="craft@craft"

flag_on() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
  esac
  return 1
}

# A worker spawned by this script carries the marker; a hook entry that sees it
# is the nested run and leaves.
if [ "$MODE" != "--worker" ] && [ -n "${CRAFT_SELF_UPDATE_RUNNING:-}" ]; then exit 0; fi

flag_on "${DISABLE_AUTOUPDATER:-}" && exit 0
flag_on "${DISABLE_UPDATES:-}" && exit 0
flag_on "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}" && exit 0
case "$(printf '%s' "${CRAFT_AUTO_UPDATE:-}" | tr '[:upper:]' '[:lower:]')" in
  0|false|off|no) exit 0 ;;
esac
[ -n "$DATA" ] || exit 0
[ -f "$DATA/no-auto-update" ] && exit 0
command -v claude >/dev/null 2>&1 || exit 0
case "$ROOT" in
  */plugins/cache/craft/craft/*) ;;
  *) exit 0 ;;
esac
mkdir -p "$DATA" 2>/dev/null || exit 0

STAMP="$DATA/self-update.stamp"
DISCLOSED="$DATA/self-update.disclosed"
NOTICE="$DATA/self-update.notice"
LOG="$DATA/self-update.log"

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOG" 2>/dev/null || true
  lines=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
  if [ "${lines:-0}" -gt 50 ]; then
    tail -n 50 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null || true
  fi
}

# Messages contain no quotes or backslashes, so this is valid JSON as printed.
say() {
  printf '{"systemMessage": "%s"}\n' "$1"
}

worker() {
  export CRAFT_SELF_UPDATE_RUNNING=1
  out=$(claude plugin marketplace update "$MARKETPLACE" 2>&1); rc=$?
  log "marketplace update rc=$rc: $(printf '%s' "$out" | tail -n 1)"
  [ "$rc" -eq 0 ] || return 0
  out=$(claude plugin update "$PLUGIN_ID" 2>&1); rc=$?
  log "plugin update rc=$rc: $(printf '%s' "$out" | tail -n 1)"
  [ "$rc" -eq 0 ] || return 0
  if ! printf '%s' "$out" | grep -qi "already at the latest"; then
    printf '%s\n' "craft updated itself; the new version loads in your next session." > "$NOTICE" 2>/dev/null || true
  fi
}

if [ "$MODE" = "--worker" ]; then
  worker
  exit 0
fi

# --- hook entry ---
msg=""
if [ -f "$NOTICE" ]; then
  msg=$(head -n 1 "$NOTICE" 2>/dev/null || true)
  rm -f "$NOTICE"
fi

last=0
if [ -f "$STAMP" ]; then
  last=$(tr -dc '0-9' < "$STAMP" 2>/dev/null || true)
  [ -n "$last" ] || last=0
fi
now=$(date +%s)
if [ $((now - last)) -ge "$INTERVAL" ]; then
  printf '%s\n' "$now" > "$STAMP" 2>/dev/null || true
  if [ ! -f "$DISCLOSED" ]; then
    : > "$DISCLOSED"
    [ -n "$msg" ] || msg="craft checks for its own update once a day and installs it in the background. Set CRAFT_AUTO_UPDATE=0 to stop."
  fi
  if [ "${CRAFT_SELF_UPDATE_SYNC:-}" = "1" ]; then
    worker
  else
    (CRAFT_SELF_UPDATE_RUNNING=1 nohup "$0" --worker >/dev/null 2>&1 </dev/null &)
  fi
fi

[ -n "$msg" ] && say "$msg"
exit 0
