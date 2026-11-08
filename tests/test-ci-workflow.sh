#!/bin/bash
# test-ci-workflow.sh — Structural assertions over .github/workflows/ci.yml,
# plus agreement checks between the workflow's job ids and the
# branch-protection runbook (docs/ci-branch-protection.md).
#
# HONEST CEILING: these are text assertions in the house style of
# test-dashboard-template.sh - they prove the file's SHAPE (trigger, job ids,
# flags), never that GitHub accepts it. Live validity is settled by the first
# real PR. Python stdlib has no YAML parser, and adding one would spend the
# no-dependencies asset the CI story protects.
#
# The group-job half is DERIVED from run-suite-group.sh --list-groups, so
# renaming a group surfaces as a real failure here, not a stale-but-passing
# assertion.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WF="$ROOT/.github/workflows/ci.yml"
RUNNER="$ROOT/scripts/ci/run-suite-group.sh"
RUNBOOK="$ROOT/docs/ci-branch-protection.md"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Detail: $2"; return 0; }

echo "=== test-ci-workflow.sh ==="
echo ""

# The body of one job: from its id line to the next 2-space-indented key.
job_block() {
  awk -v job="$1" '
    $0 == "  " job ":" { f=1; print; next }
    /^  [a-zA-Z0-9_-]+:$/ { f=0 }
    f { print }
  ' "$WF"
}

# Test: the workflow file exists and is non-empty
if [ -s "$WF" ]; then
  pass "the workflow file exists and is non-empty"
else
  fail "workflow file missing or empty" "$WF"
  echo ""; echo "-- Summary --"; echo "Total:  $TOTAL"; echo "Passed: $PASS_COUNT"; echo "Failed: $FAIL_COUNT"; exit 1
fi

# Test: the trigger is pull_request restricted to main
if grep -q '^  pull_request:$' "$WF" && grep -q '^    branches: \[main\]$' "$WF"; then
  pass "the trigger is pull_request restricted to main"
else
  fail "trigger is not pull_request on main"
fi

# Test: the workflow contains no push: trigger key
if ! grep -qE '^\s*push:' "$WF"; then
  pass "the workflow contains no push: trigger key"
else
  fail "a push: key is present" "$(grep -nE '^\s*push:' "$WF")"
fi

# Test: every group from run-suite-group.sh --list-groups appears as a job id,
# and each group job invokes run-suite-group.sh with its own name
GROUP_LIST=$(bash "$RUNNER" --list-groups)
while IFS= read -r g; do
  if grep -q "^  $g:$" "$WF"; then
    pass "group '$g' appears as a job id"
  else
    fail "group '$g' is not a job id in the workflow"
  fi
  if job_block "$g" | grep -q "run: bash scripts/ci/run-suite-group.sh $g\$"; then
    pass "job '$g' invokes run-suite-group.sh $g"
  else
    fail "job '$g' does not invoke run-suite-group.sh with its own name"
  fi
done <<EOF
$GROUP_LIST
EOF

# Test: exactly nine jobs, the five groups plus doc-drift, template-stamp, annotate-browser, browser
JOB_IDS=$(awk '/^jobs:$/{f=1;next} f && /^  [a-zA-Z0-9_-]+:$/{gsub(/^  |:$/,""); print}' "$WF")
EXPECTED_JOBS=$(printf '%s\ndoc-drift\ntemplate-stamp\nannotate-browser\nbrowser\n' "$GROUP_LIST" | sort)
if [ "$(echo "$JOB_IDS" | sort)" = "$EXPECTED_JOBS" ]; then
  pass "the workflow defines exactly the nine expected jobs"
else
  fail "job list mismatch" "got: $(echo "$JOB_IDS" | tr '\n' ' ')"
fi

# Test: doc-drift and template-stamp both set fetch-depth: 0 (they read git history)
for j in doc-drift template-stamp; do
  if job_block "$j" | grep -q 'fetch-depth: 0'; then
    pass "job '$j' sets fetch-depth: 0"
  else
    fail "job '$j' does not set fetch-depth: 0"
  fi
done

# Test: doc-drift passes the PR range; template-stamp passes base and head
if job_block doc-drift | grep -q -- '--range "${{ github.event.pull_request.base.sha }}..${{ github.event.pull_request.head.sha }}"'; then
  pass "doc-drift runs check-doc-drift.sh with the PR's base..head range"
else
  fail "doc-drift does not pass the PR range"
fi
if job_block template-stamp | grep -q -- '--base "${{ github.event.pull_request.base.sha }}" --head "${{ github.event.pull_request.head.sha }}"'; then
  pass "template-stamp runs check-template-stamp.sh with the PR's base and head"
else
  fail "template-stamp does not pass base/head"
fi

# Test: the browser job is non-blocking and runs last
if job_block browser | grep -q '^    continue-on-error: true$'; then
  pass "the browser job sets continue-on-error: true"
else
  fail "browser job is not continue-on-error"
fi
NEEDS_LINE=$(job_block browser | grep '^    needs:' || true)
# Exact match, derived: the five groups (in --list-groups order) plus the two
# git-range jobs, and NOTHING else - a substring check would still pass with
# an extra job smuggled into the list.
EXPECTED_NEEDS="    needs: [$(printf '%s\ndoc-drift\ntemplate-stamp\n' "$GROUP_LIST" | paste -sd, - | sed 's/,/, /g')]"
if [ "$NEEDS_LINE" = "$EXPECTED_NEEDS" ]; then
  pass "the browser job declares needs on exactly the seven suite and git-range jobs"
else
  fail "browser job's needs line is wrong" "got: '$NEEDS_LINE' expected: '$EXPECTED_NEEDS'"
fi

# Test: annotate-browser is blocking, standalone, and fails (not skips) without a browser
AB=$(job_block annotate-browser)
if echo "$AB" | grep -q '^    env:$' && echo "$AB" | grep -q '^      CRAFT_CI_REQUIRE_BROWSER: "1"$' \
  && echo "$AB" | grep -q '^      CRAFT_CI_LIVE: "1"$' \
  && echo "$AB" | grep -q 'run: bash tests/test-ci-annotate-check.sh$' \
  && ! echo "$AB" | grep -qE 'continue-on-error|needs:'; then
  pass "annotate-browser is blocking, has no needs, and runs the annotate check's tests live with CRAFT_CI_REQUIRE_BROWSER"
else
  fail "annotate-browser job is missing, non-blocking, has needs, or lacks CRAFT_CI_REQUIRE_BROWSER" "$AB"
fi
# A required check needs a bounded runtime: without timeout-minutes a hung
# step holds every PR on a pending check for GitHub's 360-minute default.
if echo "$AB" | grep -qx '    timeout-minutes: 10'; then
  pass "annotate-browser sets timeout-minutes: 10"
else
  fail "annotate-browser does not set timeout-minutes: 10" "$AB"
fi
if ! job_block browser | grep -q 'annotate-check' && job_block browser | grep -q '^      CRAFT_CI_LIVE: "1"$' \
  && job_block browser | grep -q 'run: bash tests/test-ci-browser-check.sh$'; then
  pass "browser runs no annotate check and runs the browser check's tests live"
else
  fail "browser job runs an annotate check or lost the live browser check tests"
fi

# Test: every job runs on ubuntu-latest
N_JOBS=$(echo "$JOB_IDS" | grep -c .)
N_UBUNTU=$(grep -c '^    runs-on: ubuntu-latest$' "$WF")
if [ "$N_JOBS" = "$N_UBUNTU" ]; then
  pass "every job runs on ubuntu-latest ($N_JOBS jobs)"
else
  fail "runs-on mismatch" "$N_JOBS jobs but $N_UBUNTU ubuntu-latest lines"
fi

# Test: no job step installs anything (the no-package-manager asset)
# Word-boundary matching: a trailing-space pattern would let a line ENDING in
# npm or pip escape; \b catches tool names at any word edge.
PM_PATTERN='\b(apt-get|apt|npm|pnpm|yarn|pip3|pip|brew)\b'
if ! grep -qE "$PM_PATTERN" "$WF"; then
  pass "no job step contains apt-get, npm, pip or brew"
else
  fail "a package-manager invocation appears in the workflow" "$(grep -nE "$PM_PATTERN" "$WF" | tr '\n' ' ')"
fi

# Test: actionlint passes if present, skipped otherwise
if command -v actionlint > /dev/null 2>&1; then
  set +e
  LINT_OUT=$(actionlint "$WF" 2>&1)
  LINT_RC=$?
  set -e
  if [ "$LINT_RC" -eq 0 ]; then
    pass "actionlint accepts the workflow"
  else
    fail "actionlint rejects the workflow" "$(echo "$LINT_OUT" | head -5 | tr '\n' ' ')"
  fi
else
  pass "actionlint not on PATH (skipped - never required)"
fi

# --- Runbook / workflow agreement (added by the runbook chunk) -------------
if [ -f "$RUNBOOK" ]; then
  # The eight blocking job ids (everything except browser) must each be named
  # as a required check in the runbook - derived from the workflow, not restated.
  RB_OK=1
  while IFS= read -r j; do
    [ "$j" = "browser" ] && continue
    grep -q "\`$j\`" "$RUNBOOK" || { RB_OK=0; echo "    runbook is missing required check: $j"; }
  done <<EOF
$JOB_IDS
EOF
  if [ "$RB_OK" -eq 1 ]; then
    pass "the runbook names all eight required check ids from the workflow, annotate-browser included"
  else
    fail "runbook/workflow job-name drift"
  fi
  if grep -q '`annotate-browser`' "$RUNBOOK" && [ "$(grep -c '{"context": "annotate-browser"}' "$RUNBOOK")" = "2" ]; then
    pass "the runbook lists annotate-browser in both payloads"
  else
    fail "the runbook payloads do not both carry annotate-browser"
  fi
  if grep -qi 'browser.*not required\|browser.*NOT a required' "$RUNBOOK"; then
    pass "the runbook names browser as not required"
  else
    fail "runbook does not mark browser as not required"
  fi
  # The read command must appear before any write (--method PATCH or PUT)
  READ_LINE=$(grep -n 'gh api repos/drobins25/craft/branches/main/protection$' "$RUNBOOK" | head -1 | cut -d: -f1)
  WRITE_LINE=$(grep -nE -- '--method (PATCH|PUT)' "$RUNBOOK" | head -1 | cut -d: -f1)
  if [ -n "$READ_LINE" ] && [ -n "$WRITE_LINE" ] && [ "$READ_LINE" -lt "$WRITE_LINE" ]; then
    pass "the runbook's read command appears before any write command"
  else
    fail "runbook read/write ordering wrong" "read at line '${READ_LINE:-none}', first write at line '${WRITE_LINE:-none}'"
  fi
else
  fail "docs/ci-branch-protection.md is missing"
fi

# --- CONTRIBUTING.md keeps local-run advice and points at the runbook ------
if grep -qF './tests/run-all.sh' "$ROOT/CONTRIBUTING.md"; then
  pass "CONTRIBUTING.md still names ./tests/run-all.sh"
else
  fail "CONTRIBUTING.md lost its local-run advice"
fi
if grep -qF 'docs/ci-branch-protection.md' "$ROOT/CONTRIBUTING.md" && [ -f "$RUNBOOK" ]; then
  pass "CONTRIBUTING.md links docs/ci-branch-protection.md and the path resolves"
else
  fail "CONTRIBUTING.md does not link the runbook (or the path is dead)"
fi

# CONTRIBUTING.md's "must be green to merge" line names exactly the runbook's
# required checks (the bulleted ids under "## The checks"), and its count word
# matches - a contributor held by a red required check must find it named.
RB_REQUIRED=$(awk '/^## The checks$/{f=1;next} f && /^## /{f=0} f' "$RUNBOOK" \
  | sed -n 's/^- `\([a-z0-9_-]*\)`$/\1/p' | sort)
MERGE_LINE=$(grep 'CI checks must be green to merge' "$ROOT/CONTRIBUTING.md" || true)
CONTRIB_REQUIRED=$(printf '%s\n' "${MERGE_LINE%%(*}" | grep -o '`[a-z0-9_-]*`' | tr -d '`' | sort)
if [ -n "$RB_REQUIRED" ] && [ "$CONTRIB_REQUIRED" = "$RB_REQUIRED" ]; then
  pass "CONTRIBUTING.md names the same required checks as the runbook"
else
  fail "CONTRIBUTING.md's required checks differ from the runbook's" \
    "contributing: $(echo $CONTRIB_REQUIRED) | runbook: $(echo $RB_REQUIRED)"
fi
N_REQ=$(printf '%s\n' "$RB_REQUIRED" | grep -c . || true)
COUNT_WORDS="one two three four five six seven eight nine ten eleven twelve"
COUNT_WORD=$(echo "$COUNT_WORDS" | cut -d' ' -f"$N_REQ" 2>/dev/null || true)
if printf '%s\n' "$MERGE_LINE" | grep -qi "^- $COUNT_WORD CI checks must be green to merge"; then
  pass "CONTRIBUTING.md states the required-check count as '$COUNT_WORD'"
else
  fail "CONTRIBUTING.md's required-check count is not '$COUNT_WORD'" "$MERGE_LINE"
fi

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
