#!/bin/bash
# test-secret-deny-patterns.sh — Tests for the shared secret-shaped deny list
# High-precision principle: real key material matches, lookalike names do not.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

DENY_SCRIPT="$SCRIPTS_DIR/secret-deny-patterns.sh"

echo "=== test-secret-deny-patterns.sh ==="
echo ""

# Helper: assert a path matches (or not) via the sourced function
check_match() {
  local path="$1" expected="$2"   # expected: match | no-match
  set +e
  bash "$DENY_SCRIPT" "$path" >/dev/null 2>&1
  local code=$?
  set -e
  if [ "$expected" = "match" ] && [ "$code" = "0" ]; then
    echo "  PASS: $path matches"
    PASS=$((PASS + 1))
  elif [ "$expected" = "no-match" ] && [ "$code" != "0" ]; then
    echo "  PASS: $path does not match"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $path - expected $expected, exit code $code"
    FAIL=$((FAIL + 1))
  fi
}

# Test 1: Secret-shaped paths match
begin_test "Deny list matches real secret shapes"

check_match ".env" "match"
check_match ".env.local" "match"
check_match ".env.production" "match"
check_match "config/app.pem" "match"
check_match "secret.key" "match"
check_match "release.keystore" "match"
check_match "trust.jks" "match"
check_match "bundle.p12" "match"
check_match "cert.pfx" "match"
check_match "id_rsa" "match"
check_match ".ssh/id_ed25519" "match"
check_match "putty.ppk" "match"
check_match "credentials.json" "match"
check_match "gcp-service-credentials.json" "match"
echo ""

# Test 2: Lookalike names do NOT match (high-precision principle)
begin_test "Deny list does not match lookalikes"

check_match "keyboard.ts" "no-match"
check_match "key-utils.sh" "no-match"
check_match "monkey.png" "no-match"
check_match "api-keys-doc.md" "no-match"
check_match "src/hotkeys.json" "no-match"
check_match "id_rsa.pub" "no-match"
echo ""

# Test 3: Env-template negations win over .env.*
begin_test "Safe env templates are excluded by negation"

check_match ".env.example" "no-match"
check_match ".env.sample" "no-match"
check_match ".env.template" "no-match"
echo ""

# Test 4: Claim hard-stop sequence — secret-shaped path refused before any git add
begin_test "Claim hard-stop refuses secret-shaped path before staging"

TEST_DIR=$(mktemp -d)
(
  cd "$TEST_DIR"
  git init -q
  git config user.name "craft-test"
  git config user.email "craft-test@example.com"
  echo "x" > keep.txt
  git add -A && git commit -q -m init --no-verify
)
echo "API_KEY=hunter2" > "$TEST_DIR/.env.local"

# Mirror the documented claim sequence: pattern check gates the add
set +e
(
  cd "$TEST_DIR"
  source "$DENY_SCRIPT"
  if matches_secret_pattern ".env.local"; then
    exit 3   # hard stop - the add below must never run
  fi
  git add -- ".env.local"
)
CLAIM_EXIT=$?
set -e

assert_eq "claim path hard-stopped (exit 3)" "3" "$CLAIM_EXIT"
STAGED=$(cd "$TEST_DIR" && git diff --cached --name-only)
assert_eq "nothing staged" "" "$STAGED"

rm -rf "$TEST_DIR"
echo ""

# --- Summary ---
finish_tests
