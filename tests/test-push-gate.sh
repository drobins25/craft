#!/bin/bash
# test-push-gate.sh — Before-evals for push-gate.sh
# Fixtures mirror REAL artifact formats: real PreToolUse stdin JSON, the real
# ledger YAML shape (written by triage-ledger.sh itself), real git repos with
# upstreams. Toy fixtures pass while real ones misfire - so no toy fixtures.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/with-story.sh"

GATE_SCRIPT="$SCRIPTS_DIR/push-gate.sh"
LEDGER_SCRIPT="$SCRIPTS_DIR/triage-ledger.sh"

echo "=== test-push-gate.sh ==="
echo ""

# Helper: invoke the gate the way Claude Code does - stdin JSON, env-located root
run_gate() {
  local cwd="$1" command="$2"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$command" "$cwd" \
    | env -u CLAUDE_PROJECT_DIR bash "$GATE_SCRIPT"
}

# Helper: fixture with an upstream so @{u}..HEAD resolves
make_repo_with_upstream() {
  local dir="$1"
  git_init_repo "$dir"
  (
    cd "$dir"
    local base
    base=$(git symbolic-ref --short HEAD)
    git checkout -q -b work
    git branch -q --set-upstream-to="$base" work
  )
}

# Test 1: Denies on untriaged leftover, reason instructs triage-then-retry
begin_test "Denies on untriaged leftover with retry instruction"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"
git_init_repo "$TEST_DIR"
bash "$LEDGER_SCRIPT" append "stray-notes.txt" "pending" "36-commit-custody-chain" "$TEST_DIR"

set +e
OUT=$(run_gate "$TEST_DIR" "git push origin main")
EXIT_CODE=$?
set -e

assert_eq "exits 0 (never exit 2)" "0" "$EXIT_CODE"
assert_contains "emits deny" '"permissionDecision": "deny"' "$OUT"
assert_contains "reason names the leftover" "stray-notes.txt" "$OUT"
assert_contains "reason instructs triage retry" "retry the push" "$OUT"

rm -rf "$TEST_DIR"
echo ""

# Test 2: Denies on secret-shaped path in @{u}..HEAD
begin_test "Denies on secret-shaped path in outgoing range"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"
make_repo_with_upstream "$TEST_DIR"
(
  cd "$TEST_DIR"
  echo "API_KEY=hunter2" > .env
  git add -- .env
  git commit -q -m "oops" --no-verify
)

set +e
OUT=$(run_gate "$TEST_DIR" "git push")
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "emits deny" '"permissionDecision": "deny"' "$OUT"
assert_contains "reason names the secret path" ".env" "$OUT"

rm -rf "$TEST_DIR"
echo ""

# Test 3: Explicit allow on clean tree + triaged ledger (not silence)
begin_test "Explicit allow on clean tree and triaged ledger"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"
make_repo_with_upstream "$TEST_DIR"
bash "$LEDGER_SCRIPT" append "old-leftover.txt" "leave" "story-a" "$TEST_DIR"

set +e
OUT=$(run_gate "$TEST_DIR" "git push origin main")
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_contains "emits explicit allow (silence would prompt)" '"permissionDecision": "allow"' "$OUT"

rm -rf "$TEST_DIR"
echo ""

# Test 4: Fails open with no jq on PATH
begin_test "Fails open when jq is missing"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"

set +e
OUT=$(printf '{"tool_input":{"command":"git push"},"cwd":"%s"}' "$TEST_DIR" \
  | env -u CLAUDE_PROJECT_DIR PATH="/nonexistent-path-for-test" /bin/bash "$GATE_SCRIPT" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_eq "exits 0 without jq" "0" "$EXIT_CODE"
assert_eq "no output (no deny, no allow)" "" "$OUT"

rm -rf "$TEST_DIR"
echo ""

# Test 5: Falls open on an unparseable ledger (never deny-lockout)
begin_test "Falls open on unparseable ledger"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"
git_init_repo "$TEST_DIR"
printf '{{{ this is not the ledger yaml :::\n\tgarbage' > "$TEST_DIR/.craft/.triage-ledger"

set +e
OUT=$(run_gate "$TEST_DIR" "git push")
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
if echo "$OUT" | grep -q '"permissionDecision": "deny"'; then
  echo "  FAIL: gate denied on a parse failure (deny-lockout)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: no deny on parse failure"
  PASS=$((PASS + 1))
fi

rm -rf "$TEST_DIR"
echo ""

# Test 6: No upstream — secret scan skipped, leftover check still runs
begin_test "No upstream: secret scan skipped, leftover check still live"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"
git_init_repo "$TEST_DIR"   # no upstream configured
(
  cd "$TEST_DIR"
  echo "API_KEY=hunter2" > .env
  git add -- .env
  git commit -q -m "local only" --no-verify
)

set +e
OUT=$(run_gate "$TEST_DIR" "git push")
EXIT_CODE=$?
set -e

assert_eq "exits 0, no crash" "0" "$EXIT_CODE"
if echo "$OUT" | grep -q '"permissionDecision": "deny"'; then
  echo "  FAIL: denied despite no upstream (secret scan should be skipped)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: no deny without an upstream (documented boundary)"
  PASS=$((PASS + 1))
fi

# But a pending leftover still denies even without an upstream
bash "$LEDGER_SCRIPT" append "stray.txt" "pending" "story-x" "$TEST_DIR"
set +e
OUT=$(run_gate "$TEST_DIR" "git push")
set -e
assert_contains "leftover check still denies" '"permissionDecision": "deny"' "$OUT"

rm -rf "$TEST_DIR"
echo ""

# Test 7: Non-push command passes through silently
begin_test "Non-push command: exit 0, no output"

TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.craft"

set +e
OUT=$(run_gate "$TEST_DIR" "git status")
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_eq "no output for non-push" "" "$OUT"

# A stray "git push" inside an argument must not trigger either
set +e
OUT=$(run_gate "$TEST_DIR" "grep \\\"git pushed\\\" notes.md")
set -e
assert_eq "no output for quoted mention" "" "$OUT"

rm -rf "$TEST_DIR"
echo ""

# Test 8: auto-approve abstains on git push (carve-out)
begin_test "auto-approve no longer emits allow for git push"

AUTO_APPROVE="$SCRIPTS_DIR/auto-approve-plugin-scripts.sh"

set +e
OUT=$(printf '{"tool_input":{"command":"git push origin main"}}' | bash "$AUTO_APPROVE")
EXIT_CODE=$?
set -e

assert_eq "exits 0" "0" "$EXIT_CODE"
assert_eq "no allow JSON for git push" "" "$OUT"

# Sanity: a benign command is still auto-approved
set +e
OUT=$(printf '{"tool_input":{"command":"ls -la"}}' | bash "$AUTO_APPROVE")
set -e
assert_contains "benign command still auto-approved" '"permissionDecision":"allow"' "$OUT"

echo ""

# --- Summary ---
finish_tests
