#!/bin/bash
# test-write-gate-wiring.sh - Call lints: every opener and closer of the write
# gate goes through write-gate.sh, and nothing still sets the old shared value.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

REPO="$SCRIPT_DIR/.."

# Fixed-string checks (the shared helpers read the text as a regex)
has_text() { # <desc> <file> <text>
  if grep -qF -- "$3" "$2" 2>/dev/null; then echo "  PASS: $1"; PASS=$((PASS + 1))
  else echo "  FAIL: $1"; echo "    '$3' not found in $2"; FAIL=$((FAIL + 1)); fi
}
lacks_text() { # <desc> <file> <text>
  if grep -qF -- "$3" "$2" 2>/dev/null; then echo "  FAIL: $1"; echo "    '$3' should not be in $2"; FAIL=$((FAIL + 1))
  else echo "  PASS: $1"; PASS=$((PASS + 1)); fi
}
count_text() { grep -cF -- "$2" "$1" || true; }

echo "=== test-write-gate-wiring.sh ==="
echo ""

begin_test "adhoc opens and closes through write-gate.sh"
ADHOC="$REPO/skills/adhoc/SKILL.md"
has_text "adhoc opens the gate" "$ADHOC" 'write-gate.sh open adhoc'
has_text "adhoc closes the gate" "$ADHOC" 'write-gate.sh close adhoc'
echo ""

begin_test "the record's path goes on the gate from the tweak and fix hand-off flows"
has_text "tweak Step 1 puts the record on the gate" "$REPO/skills/adhoc/references/tweak.md" 'write-gate.sh open adhoc "<record path>"'
TWEAK_OPENS=$(count_text "$REPO/skills/adhoc/references/tweak.md" 'write-gate.sh open adhoc "')
assert_eq "tweak.md opens with the record path at Step 1 and at each attempt" "2" "$TWEAK_OPENS"
has_text "fix hand-off puts the record on the gate" "$REPO/skills/adhoc/references/fix-handoff.md" 'write-gate.sh open adhoc "'
HANDOFF_OPENS=$(count_text "$REPO/skills/adhoc/references/fix-handoff.md" 'write-gate.sh open adhoc "')
assert_eq "fix-handoff.md opens with the record path at H-1, H-2 and H-2a" "3" "$HANDOFF_OPENS"
echo ""

begin_test "approve opens, closes and checks through write-gate.sh"
APPROVE="$REPO/skills/approve/SKILL.md"
has_text "approve opens" "$APPROVE" 'write-gate.sh open approve'
has_text "approve closes" "$APPROVE" 'write-gate.sh close approve'
has_text "approve checks for a held gate" "$APPROVE" 'write-gate.sh holder'
echo ""

begin_test "the autonomous run closes only its own gate"
has_text "auto run closes the story's gate" "$REPO/commands/craft-story-implement-auto.md" 'write-gate.sh close story'
AUTO_CLOSES=$(count_text "$REPO/commands/craft-story-implement-auto.md" 'write-gate.sh close story')
assert_eq "stale-state row and give-up each close it" "2" "$AUTO_CLOSES"
has_text "a failed gate step stops the run" "$REPO/commands/craft-story-implement-auto.md" "stopped - <the gate script's message>"
echo ""

begin_test "smith never runs the gate script"
SMITH="$REPO/agents/smith.md"
lacks_text "smith calls no open" "$SMITH" 'write-gate.sh open'
lacks_text "smith calls no close" "$SMITH" 'write-gate.sh close'
has_text "smith is told to leave it alone" "$SMITH" 'you never run `write-gate.sh`'
echo ""

begin_test "nothing under commands, skills, agents or reference sets the old shared value or writes the fix marker"
OLD_CALLS=$(grep -rn 'update-global-state.sh[^|]*CRAFT_WRITE_ENABLED\|CRAFT_WRITE_ENABLED' "$REPO/commands" "$REPO/skills" "$REPO/agents" "$REPO/reference" || true)
assert_eq "no CRAFT_WRITE_ENABLED left" "" "$OLD_CALLS"
MARKER_USES=$(grep -rn '\.active-fix' "$REPO/commands" "$REPO/skills" "$REPO/agents" "$REPO/reference" || true)
assert_eq "no .active-fix marker left" "" "$MARKER_USES"
echo ""

begin_test "annotate's flow calls no write-gate.sh"
ANNOTATE_HITS=$(grep -rln 'write-gate.sh' "$REPO/commands/references/annotate-inline.md" "$REPO/commands/craft-annotate.md" 2>/dev/null || true)
assert_eq "annotate never opens or closes the gate" "" "$ANNOTATE_HITS"
echo ""

begin_test "the story scripts call write-gate.sh and the old key is gone from every script"
has_text "start-story checks the id first" "$REPO/hooks/scripts/start-story.sh" 'write-gate.sh" --root "${PROJECT_ROOT:-.}" preflight'
has_text "start-story opens the story" "$REPO/hooks/scripts/start-story.sh" 'open story "$STORY_FILE"'
has_text "complete-story closes the story" "$REPO/hooks/scripts/complete-story.sh" 'close story "$STORY_FILE"'
has_text "delete-story closes the story" "$REPO/hooks/scripts/delete-story.sh" 'close story "$STORY_FILE"'
SCRIPT_HITS=$(grep -ln 'update-global-state.sh" CRAFT_WRITE_ENABLED' "$REPO"/hooks/scripts/*.sh || true)
assert_eq "no script still sets the shared value" "" "$SCRIPT_HITS"
lacks_text "session start never names a gate file" "$REPO/hooks/scripts/session-start.sh" '.craft/.gate/'
lacks_text "session start has no gate reset" "$REPO/hooks/scripts/session-start.sh" 'CRAFT_WRITE_ENABLED'
echo ""

begin_test "continuing a story holds this session's gate first"
IMPL="$REPO/commands/craft-story-implement.md"
has_text "Resume Support has the Hold This Session's Gate subsection" "$IMPL" "### Hold This Session's Gate"
HOLD_LINE=$(grep -nF "### Hold This Session's Gate" "$IMPL" | head -1 | cut -d: -f1)
RESUME_LINE=$(grep -nF '## Resume Support' "$IMPL" | head -1 | cut -d: -f1)
PROGRESS_LINE=$(grep -nF '### Show Progress' "$IMPL" | head -1 | cut -d: -f1)
if [ -n "$HOLD_LINE" ] && [ "$HOLD_LINE" -gt "$RESUME_LINE" ] && [ "$HOLD_LINE" -lt "$PROGRESS_LINE" ]; then echo "  PASS: the subsection is the first in Resume Support"; PASS=$((PASS + 1)); else echo "  FAIL: the subsection is not first in Resume Support"; FAIL=$((FAIL + 1)); fi
CLAIM_LINE=$(grep -nF 'write-gate.sh claim story' "$IMPL" | head -1 | cut -d: -f1)
OPEN_LINE=$(grep -nF 'write-gate.sh open story' "$IMPL" | head -1 | cut -d: -f1)
if [ -n "$CLAIM_LINE" ] && [ "$CLAIM_LINE" -lt "$PROGRESS_LINE" ]; then echo "  PASS: claim story sits above Show Progress"; PASS=$((PASS + 1)); else echo "  FAIL: claim story not above Show Progress"; FAIL=$((FAIL + 1)); fi
if [ -n "$OPEN_LINE" ] && [ "$OPEN_LINE" -lt "$PROGRESS_LINE" ]; then echo "  PASS: open story sits above Show Progress"; PASS=$((PASS + 1)); else echo "  FAIL: open story not above Show Progress"; FAIL=$((FAIL + 1)); fi
has_text "the takeover question is worded as ruled" "$IMPL" "Another session's gate names [story]. It may be building now. Take it over, or stop?"
STEP4_HOLD=$(grep -nF "run \"Hold This Session's Gate\"" "$IMPL" | head -1 | cut -d: -f1)
STEP4_LINE=$(grep -nF '### Step 4: Implementation Loop' "$IMPL" | head -1 | cut -d: -f1)
IMPLEMENTER_TASK=$(grep -nF 'subagent_type: "craft:implementer"' "$IMPL" | cut -d: -f1 | awk -v s="$STEP4_LINE" '$1 > s {print; exit}')
if [ -n "$STEP4_HOLD" ] && [ -n "$IMPLEMENTER_TASK" ] && [ "$STEP4_HOLD" -lt "$IMPLEMENTER_TASK" ] && [ "$STEP4_HOLD" -gt "$STEP4_LINE" ]; then echo "  PASS: Step 4 holds the gate before the implementer Task call"; PASS=$((PASS + 1)); else echo "  FAIL: Step 4 does not hold the gate before the implementer Task call"; FAIL=$((FAIL + 1)); fi
FIXLOOP="$REPO/commands/references/validate-fix-loop.md"
HOLD_FIX=$(grep -nF "Hold This Session's Gate" "$FIXLOOP" | head -1 | cut -d: -f1)
FIX_BREADCRUMB=$(grep -nF 'Before invoking ANY fix skill' "$FIXLOOP" | head -1 | cut -d: -f1)
if [ -n "$HOLD_FIX" ] && [ "$HOLD_FIX" -eq "$FIX_BREADCRUMB" ]; then echo "  PASS: validate-fix-loop holds the gate before invoking a fix skill"; PASS=$((PASS + 1)); else echo "  FAIL: validate-fix-loop does not hold the gate before a fix skill"; FAIL=$((FAIL + 1)); fi
has_text "story-continue holds the gate" "$REPO/commands/craft-story-continue.md" "Hold This Session's Gate"
has_text "story-implement-auto holds the gate" "$REPO/commands/craft-story-implement-auto.md" "Hold This Session's Gate"
has_text "auto run reports takeovers" "$REPO/commands/craft-story-implement-auto.md" "Write gate taken over from another session: [story names, or \"none\"]"
has_text "auto run stop line" "$REPO/commands/craft-story-implement-auto.md" "stopped - another session's gate names <story>"
echo ""

begin_test "workflow-run holds this session's gate in Step 1g and the run-all resume, and nowhere else"
WFRUN="$REPO/commands/craft-workflow-run.md"
G1G=$(grep -nF '## Step 1g: Continue Active Session' "$WFRUN" | head -1 | cut -d: -f1)
STEP2=$(grep -nF '## Step 2: Show the Stage List' "$WFRUN" | head -1 | cut -d: -f1)
CLAIM_WF=$(grep -nF 'write-gate.sh claim workflow "<session folder>"' "$WFRUN" | cut -d: -f1)
OPEN_WF=$(grep -nF 'write-gate.sh open workflow "<session folder>"' "$WFRUN" | cut -d: -f1)
if [ -n "$CLAIM_WF" ] && [ "$CLAIM_WF" -gt "$G1G" ] && [ "$CLAIM_WF" -lt "$STEP2" ]; then echo "  PASS: claim workflow sits in Step 1g"; PASS=$((PASS + 1)); else echo "  FAIL: claim workflow not in Step 1g"; FAIL=$((FAIL + 1)); fi
if [ -n "$OPEN_WF" ] && [ "$OPEN_WF" -gt "$G1G" ] && [ "$OPEN_WF" -lt "$STEP2" ]; then echo "  PASS: open workflow (takeover) sits in Step 1g"; PASS=$((PASS + 1)); else echo "  FAIL: open workflow not in Step 1g"; FAIL=$((FAIL + 1)); fi
TOTAL_CALLS=$(grep -c 'write-gate.sh' "$WFRUN" || true)
assert_eq "the file has exactly the claim and the takeover call" "2" "$TOTAL_CALLS"
lacks_text "no bare gate call" "$WFRUN" ' write-gate.sh'
has_text "the takeover question is worded as ruled" "$WFRUN" "Another session's gate names [workflow session]. It may be running now. Take it over, or stop?"
E1E=$(grep -nF '## Step 1e: Run All Sessions' "$WFRUN" | head -1 | cut -d: -f1)
F1F=$(grep -nF '## Step 1f: Mark Sessions Ready' "$WFRUN" | head -1 | cut -d: -f1)
RESUME_HOLD=$(grep -nF "run \"Hold This Session's Gate\" in Step 1g" "$WFRUN" | head -1 | cut -d: -f1)
if [ -n "$RESUME_HOLD" ] && [ "$RESUME_HOLD" -gt "$E1E" ] && [ "$RESUME_HOLD" -lt "$F1F" ]; then echo "  PASS: run-all's resume runs the gate step"; PASS=$((PASS + 1)); else echo "  FAIL: run-all's resume does not run the gate step"; FAIL=$((FAIL + 1)); fi
has_text "the takeover line for the end report" "$WFRUN" "Another session's gate named {session name}; this run took it over."
echo ""

begin_test "the SessionEnd hook is wired and the script is the only thing it runs"
assert_eq "SessionEnd runs session-end.sh" "1" "$(jq '[.hooks.SessionEnd[].hooks[] | select(.command | endswith("/hooks/scripts/session-end.sh"))] | length' "$REPO/hooks/hooks.json")"
lacks_text "session-end never runs discover-projects or the dashboard" "$REPO/hooks/scripts/session-end.sh" 'discover-projects.sh"'
lacks_text "session-end never sources session-start" "$REPO/hooks/scripts/session-end.sh" 'source "$SCRIPT_DIR/session-start.sh"'
echo ""

begin_test "reflect, rule-pass, research and docs open inside their write step and close before the next step, asking nothing between"
# line_of <file> <fixed text> [after-line] - first line number at or after after-line
line_of() { awk -v t="$2" -v a="${3:-1}" 'NR>=a && index($0,t){print NR; exit}' "$1"; }
flow_lint() { # <label> <file> <name> <write-step heading> <next-step heading> <open-must-precede text or ""> <close-must-precede text>
  local label="$1" file="$2" name="$3" write_h="$4" next_h="$5" before_open="$6" before_close="$7"
  local wh nh op cl bo bc between
  wh=$(line_of "$file" "$write_h"); nh=$(line_of "$file" "$next_h" "$wh")
  op=$(line_of "$file" "write-gate.sh open $name" "$wh")
  cl=$(line_of "$file" "write-gate.sh close $name" "$wh")
  if [ -n "$op" ] && [ "$op" -gt "$wh" ] && [ "$op" -lt "$nh" ]; then echo "  PASS: $label opens inside its write step"; PASS=$((PASS + 1)); else echo "  FAIL: $label open not inside '$write_h'"; FAIL=$((FAIL + 1)); fi
  if [ -n "$before_open" ]; then
    bo=$(line_of "$file" "$before_open" "$wh")
    if [ -n "$op" ] && [ -n "$bo" ] && [ "$op" -lt "$bo" ]; then echo "  PASS: $label opens before '$before_open'"; PASS=$((PASS + 1)); else echo "  FAIL: $label does not open before '$before_open'"; FAIL=$((FAIL + 1)); fi
  fi
  bc=$(line_of "$file" "$before_close" "$wh")
  if [ -n "$op" ] && [ -n "$cl" ] && [ "$cl" -gt "$op" ] && [ -n "$bc" ] && [ "$cl" -lt "$bc" ]; then echo "  PASS: $label closes before '$before_close'"; PASS=$((PASS + 1)); else echo "  FAIL: $label does not close before '$before_close'"; FAIL=$((FAIL + 1)); fi
  between=$(sed -n "${op:-1},${cl:-1}p" "$file" | grep -e 'AskUserQuestion' -e '?[[:space:]]*$' || true)
  assert_eq "$label asks nothing between open and close" "" "$between"
  has_text "$label open names the failure path" "$file" "If the open exits non-zero, stop this write step and show the gate script's message."
}
GATE='${CLAUDE_PLUGIN_ROOT}/hooks/scripts/write-gate.sh'
flow_lint "reflect" "$REPO/commands/craft-reflect.md" reflect "### Step 3: Write to Harness" "### Step 4: Mark as Written" "#### 3a." "### Step 4: Mark as Written"
flow_lint "rule-pass" "$REPO/commands/references/rule-pass.md" rule-pass "## Step 4: Write Approved Rules" "## Step 5: Receipt" "" "Rule pass receipt:"
flow_lint "research" "$REPO/commands/craft-research.md" research "#### 6.3: Write the Agent File" "#### 6.4: Present Result" "Write to \`.claude/agents/" "> **Expert crystallized"
flow_lint "docs" "$REPO/commands/craft-docs.md" docs "### Step 3: Dispatch Doc-Writer for Generation" "### Step 4: Report" "Dispatch the **doc-writer agent**" "DOCUMENTATION"
for F in reflect:commands/craft-reflect.md rule-pass:commands/references/rule-pass.md research:commands/craft-research.md docs:commands/craft-docs.md; do
  N="${F%%:*}"; P="$REPO/${F#*:}"
  has_text "$N open is written with the full plugin path" "$P" "$GATE open $N"
  has_text "$N close is written with the full plugin path" "$P" "$GATE close $N"
  assert_eq "$N has exactly one open and one close" "2" "$(grep -c 'write-gate.sh' "$P" || true)"
done
echo ""

begin_test "become opens before each crystallizer call, closes as it returns, and any save edit closes before the next heading"
BECOME="$REPO/commands/craft-become.md"
TASKS=$(grep -c 'subagent_type: "craft:crystallizer"' "$BECOME" || true)
assert_eq "exactly two crystallizer Task calls" "2" "$TASKS"
# For each crystallizer Task block: the nearest nonblank line above the fence opens, the nearest nonblank line below the closing fence closes.
PAIRS=$(awk '
  { lines[NR]=$0 }
  END {
    for (i=1;i<=NR;i++) if (lines[i] ~ /subagent_type: "craft:crystallizer"/) {
      f=i-1; while (f>0 && lines[f] !~ /^```/) f--
      a=f-1; while (a>0 && lines[a] ~ /^[[:space:]]*$/) a--
      c=i+1; while (c<=NR && lines[c] !~ /^```/) c++
      b=c+1; while (b<=NR && lines[b] ~ /^[[:space:]]*$/) b++
      o = (index(lines[a], "write-gate.sh open become") > 0) ? "open" : "no-open"
      k = (index(lines[b], "write-gate.sh close become") > 0) ? "close" : "no-close"
      print o "," k
    }
  }' "$BECOME")
assert_eq "both Task calls have the open right before and the close right after" "open,close
open,close" "$PAIRS"
# Every other open (the save edit): a close before the next heading.
UNCLOSED=$(awk '
  /^#/ { if (pending) bad++; pending=0 }
  { if (index($0,"write-gate.sh open become")) { lines_open=1 }
    if (index($0,"write-gate.sh close become")) { pending=0 } }
  { n=gsub(/write-gate\.sh open become/,"&"); m=gsub(/write-gate\.sh close become/,"&")
    if (n>m) pending=1 }
  END { if (pending) bad++; print bad+0 }' "$BECOME")
assert_eq "no open is left unclosed at a heading or the end of the file" "0" "$UNCLOSED"
SAVE_EDIT=$(grep -n 'Edit or Write' "$BECOME" | head -1)
case "$SAVE_EDIT" in *"write-gate.sh open become"*"write-gate.sh close become"*) echo "  PASS: the save edit opens and closes on its own line"; PASS=$((PASS + 1));; *) echo "  FAIL: the save edit has no open then close"; FAIL=$((FAIL + 1));; esac
assert_eq "become has three opens (two crystallizer calls and the save edit)" "3" "$(grep -o 'write-gate.sh open become' "$BECOME" | wc -l | tr -d ' ')"
lacks_text "become never calls the gate bare" "$BECOME" ' write-gate.sh'
echo ""

begin_test "annotate-inline and docs flows that never write keep no gate line"
lacks_text "annotate-inline has no gate line" "$REPO/commands/references/annotate-inline.md" 'write-gate.sh'
echo ""

begin_test "the docs, changelog and version describe one gate per session"
DOCS_HITS=$(grep -rn -e CRAFT_WRITE_ENABLED -e '\.active-fix' "$REPO/DESIGN.md" "$REPO/README.md" "$REPO/CONTRIBUTING.md" "$REPO/docs" || true)
assert_eq "no doc names the old shared value or the fix marker" "" "$DOCS_HITS"
has_text "DESIGN names the gate folder" "$REPO/DESIGN.md" '.craft/.gate/<session id>'
has_text "DESIGN names write-gate.sh" "$REPO/DESIGN.md" 'write-gate.sh'
has_text "DESIGN names session-end.sh" "$REPO/DESIGN.md" 'session-end.sh'
has_text "README names SessionEnd" "$REPO/README.md" 'SessionEnd'
has_text "decision-tree names the gate file" "$REPO/docs/decision-tree.md" '.craft/.gate/<session id>'
has_text "agent catalog says Smith writes while its caller holds the gate" "$REPO/docs/agent-catalog.md" 'its caller'
has_text "changelog has the 2.21.0 entry" "$REPO/CHANGELOG.md" '## 2.21.0 - 2026-11-24'
echo ""

finish_tests
