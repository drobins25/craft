#!/bin/bash
# SessionEnd hook: remove the ending session's write gate file.
#
# Claude Code gives a plugin's SessionEnd hook a 1.5 s budget that a hook's own
# timeout cannot raise, so this does the least it can: read the session id,
# find the places a gate file may sit, remove that one file name in each. It
# never sources session-start.sh and never runs discover-projects.sh or the
# dashboard. It prints nothing and always exits 0 - a session ending must not
# fail on cleanup.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT=$(cat 2>/dev/null) || INPUT=""

# The id and the session's folder come from the stdin JSON through a parser,
# never a pattern match: the input can quote text that looks like an id. Line 1
# is the id when it is valid (1 to 128 of A-Za-z0-9_-, so it can never name a
# path), the rest is the folder.
PARSED=$(printf '%s' "$INPUT" | python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
sid = data.get("session_id")
if not (isinstance(sid, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,128}", sid)):
    sys.exit(0)
cwd = data.get("cwd")
sys.stdout.write(sid + "\n" + (cwd if isinstance(cwd, str) else ""))
' 2>/dev/null) || PARSED=""

SID="${PARSED%%$'\n'*}"
[ -n "$SID" ] || exit 0
SESSION_CWD="${PARSED#*$'\n'}"
[ "$SESSION_CWD" = "$PARSED" ] && SESSION_CWD=""

if [ -n "$SESSION_CWD" ] && [ -d "$SESSION_CWD" ]; then
  cd "$SESSION_CWD" 2>/dev/null || true
fi

# Every place the status line looks for the gate: the root the hooks resolve,
# the git top level, and each sub-project the top level registers.
ROOTS=()
RESOLVED=$(unset PROJECT_ROOT; . "$SCRIPT_DIR/find-workshop.sh" >/dev/null 2>&1; printf '%s' "${PROJECT_ROOT:-}")
RESOLVED="${RESOLVED%/}"
[ -n "$RESOLVED" ] && ROOTS+=("$RESOLVED")

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || TOP=""
if [ -n "$TOP" ]; then
  ROOTS+=("$TOP")
  for REG in "$TOP"/.craft/projects/*.md; do
    [ -f "$REG" ] || continue
    SUB=$(sed -n '/^---$/,/^---$/{s/^path:[[:space:]]*//p;}' "$REG" | head -1 | tr -d "\"'\r")
    [ -n "$SUB" ] && ROOTS+=("$TOP/$SUB")
  done
fi

for R in "${ROOTS[@]}"; do
  GATE_FILE="$R/.craft/.gate/$SID"
  # Only a plain gate file goes; a folder or anything else of that name stays.
  if [ -f "$GATE_FILE" ] && [ ! -d "$GATE_FILE" ]; then
    rm -f "$GATE_FILE" 2>/dev/null || true
  fi
done

exit 0
