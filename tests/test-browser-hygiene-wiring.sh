#!/bin/bash
# test-browser-hygiene-wiring.sh - Doc-grep coverage for browser hygiene
#
# Section 1: every evaluate_script snippet in init and the walkthrough is a
# function expression handed over uncalled. evaluate_script calls what it is
# given, so a self-invoking snippet runs but the tool reports
# `fn is not a function` and the returned data is lost.
#
# Later sections append below, above the Summary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/.."

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Expected: $2"; [ -n "${3:-}" ] && echo "    Got:      $3"; return 0; }
skip() { TOTAL=$((TOTAL+1)); echo "  SKIP: $1"; }


INIT="$REPO/commands/craft-init.md"
WALK="$REPO/agents/walkthrough-analyzer.md"

echo "-- Section 1: evaluate_script snippets are uncalled functions --"

FENCE_DIR="$(mktemp -d)"
trap 'rm -rf "$FENCE_DIR"' EXIT
python3 -I - "$INIT" "$WALK" "$FENCE_DIR" <<'PY'
import re, sys
n = 0
for path in sys.argv[1:3]:
    text = open(path, encoding="utf-8").read()
    for m in re.finditer(r"^```javascript\n(.*?)^```", text, re.S | re.M):
        n += 1
        open(f"{sys.argv[3]}/{n:02d}.js", "w", encoding="utf-8").write(m.group(1))
PY

COUNT=$(ls "$FENCE_DIR" | wc -l | tr -d ' ')
[ "$COUNT" = "7" ] && pass "seven evaluate_script fences across init and the walkthrough" || fail "seven evaluate_script fences across init and the walkthrough" "7" "$COUNT"

SELF_CALLED=""
for f in "$FENCE_DIR"/*.js; do
  last=$(grep -v '^[[:space:]]*$' "$f" | tail -1)
  case "$last" in *')()'*|*')();') SELF_CALLED="$SELF_CALLED $(basename "$f")";; esac
done
[ -z "$SELF_CALLED" ] && pass "no fence ends in a self-call" || fail "no fence ends in a self-call" "no fence ending in )()" "$SELF_CALLED"

if command -v node >/dev/null 2>&1; then
  NOT_FN=""
  for f in "$FENCE_DIR"/*.js; do
    t=$(node -e 'const s=require("fs").readFileSync(process.argv[1],"utf8"); console.log(typeof eval("(" + s + ")"))' "$f" 2>/dev/null || echo "ran-or-threw")
    [ "$t" = "function" ] || NOT_FN="$NOT_FN $(basename "$f"):$t"
  done
  [ -z "$NOT_FN" ] && pass "every fence evaluates to a function without running" || fail "every fence evaluates to a function without running" "typeof function" "$NOT_FN"
else
  skip "every fence evaluates to a function without running (node absent)"
fi

for pair in "init:$INIT" "walkthrough:$WALK"; do
  grep -qF 'fn is not a function' "${pair#*:}" && pass "${pair%%:*} states the function rule" || fail "${pair%%:*} states the function rule" "phrase 'fn is not a function'" "absent"
done

echo ""
echo "-- Section 2: every reviewer runs the annotate clear gate --"

REVIEWERS=(
  agents/qa-analyzer.md agents/ux-analyzer.md agents/style-analyzer.md
  agents/creative-analyzer.md agents/walkthrough-analyzer.md
  skills/adhoc/references/tweak.md skills/adhoc/references/fix.md
)
for f in "${REVIEWERS[@]}"; do
  if grep -qF 'annotate-run.sh" review-clear' "$REPO/$f" && grep -qF 'OPEN' "$REPO/$f"; then
    pass "$f runs review-clear and handles OPEN"
  else
    fail "$f runs review-clear and handles OPEN" 'annotate-run.sh" review-clear and OPEN' "missing"
  fi
  if grep -qF 'ca-strip' "$REPO/$f"; then
    fail "$f carries no copy of the clear" "no ca-strip literal" "ca-strip present"
  else
    pass "$f carries no copy of the clear"
  fi
done

for f in commands/craft-analyze.md commands/craft-cycle-complete.md; do
  grep -qF 'PLUGIN_ROOT:' "$REPO/$f" && pass "$f passes the plugin root" || fail "$f passes the plugin root" "a PLUGIN_ROOT: line" "absent"
done

echo ""
echo "-- Section 3: the fallback notice and the docs --"

NOTICE_CMD='node "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/devtools-launch.cjs" notice'
for f in commands/references/annotate-inline.md commands/references/mockup-inline.md skills/adhoc/references/tweak.md skills/adhoc/references/fix.md; do
  if grep -qF "$NOTICE_CMD" "$REPO/$f" && ! grep -qF "$NOTICE_CMD --quiet" "$REPO/$f"; then
    pass "$f runs notice without --quiet"
  else
    fail "$f runs notice without --quiet" "$NOTICE_CMD" "absent or quiet"
  fi
done

grep -qF "$NOTICE_CMD --quiet" "$REPO/commands/references/dial-inline.md" && pass "dial marks the notice quietly" || fail "dial marks the notice quietly" "$NOTICE_CMD --quiet" "absent"

COPY_HITS=""
for f in commands/references/annotate-inline.md commands/references/dial-inline.md commands/references/mockup-inline.md skills/adhoc/references/tweak.md skills/adhoc/references/fix.md README.md; do
  grep -qF "gets a fresh window" "$REPO/$f" && COPY_HITS="$COPY_HITS $f"
done
[ -z "$COPY_HITS" ] && pass "no flow or README retypes the fallback copy" || fail "no flow or README retypes the fallback copy" "none" "$COPY_HITS"

DIAL="$REPO/commands/references/dial-inline.md"
grep -qF "so this costs at most one login" "$DIAL" && ! grep -qF "one login per session at most" "$DIAL" && pass "dial login wording reads at most one login" || fail "dial login wording reads at most one login" "so this costs at most one login" "old or missing wording"

ANN="$REPO/commands/references/annotate-inline.md"
STEP1=$(awk '/^## Step 1/{f=1;next} /^## Step 2/{f=0} f' "$ANN")
echo "$STEP1" | grep -qF "This window has none of your pages open - what address should I open?" && echo "$STEP1" | grep -qF "new_page" && pass "annotate opens a page in an empty window" || fail "annotate opens a page in an empty window" "question copy and new_page in Step 1" "absent"

for f in commands/references/dial-inline.md commands/references/mockup-inline.md; do
  if grep -q 'chrome-devtools' "$REPO/$f" || grep -q '—' "$REPO/$f"; then fail "$f has no chrome-devtools string or em dash" "neither" "found"; else pass "$f has no chrome-devtools string or em dash"; fi
done

grep -qF "devtools-launch.cjs" "$REPO/DESIGN.md" && pass "DESIGN lists the launcher" || fail "DESIGN lists the launcher" "devtools-launch.cjs" "absent"
README_MCP=$(awk '/^## MCP Integration/{f=1;next} /^## /{f=0} f' "$REPO/README.md")
echo "$README_MCP" | grep -qi "saved browser profile" && echo "$README_MCP" | grep -qi "pinned" && pass "README describes the shared profile and pinned server" || fail "README describes the shared profile and pinned server" "profile and pinned paragraph" "absent"

# --- append new sections above this line ---

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
