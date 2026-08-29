#!/bin/bash
# validate-chunk.test.sh — Output contract tests for the chunk-validator agent
#
# Usage: bash hooks/scripts/__tests__/validate-chunk.test.sh
#
# These tests validate that the chunk-validator agent's output format
# matches the contract expected by the validate-chunk skill. Tests use
# mocked output strings — no API calls.

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

# ── Helpers ──────────────────────────────────────────────────────

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  TOTAL=$((TOTAL + 1))
  echo "  ✓ $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  TOTAL=$((TOTAL + 1))
  echo "  ✗ $1"
  if [ -n "${2:-}" ]; then
    echo "    Expected: $2"
    echo "    Got:      $3"
  fi
}

assert_contains() {
  local output="$1" expected="$2" label="$3"
  if echo "$output" | grep -qF -- "$expected"; then
    pass "$label"
  else
    fail "$label" "$expected" "(not found in output)"
  fi
}

assert_not_contains() {
  local output="$1" unexpected="$2" label="$3"
  if echo "$output" | grep -qF -- "$unexpected"; then
    fail "$label" "(should not contain)" "$unexpected"
  else
    pass "$label"
  fi
}

# Parse a field value from structured agent output
parse_field() {
  local output="$1" field="$2"
  echo "$output" | sed -n "s/.*\*\*${field}:\*\* //p" | head -1
}

# ── Mock Agent Outputs ───────────────────────────────────────────

# All checks passed — per-chunk mode
MOCK_PASSED=$(cat <<'EOF'
## Validation Result

**Status:** PASSED
**Chunk:** 2/4: API routes
**Mode:** per-chunk

| Check | Result |
|-------|--------|
| TypeScript Strict | PASS |
| Lint | PASS |
| No Any Types | PASS |
| Build | PASS |
| Tests + Coverage | PASS |
| Design Tokens | SKIP |

**Fix count:** 0 | No fixes required
EOF
)

# Partial — warnings only, non-final chunk
MOCK_PARTIAL=$(cat <<'EOF'
## Validation Result

**Status:** PARTIAL
**Chunk:** 2/4: API routes
**Mode:** per-chunk

| Check | Result |
|-------|--------|
| TypeScript Strict | PASS |
| Lint | WARN |
| No Any Types | WARN |
| Build | PASS |
| Tests + Coverage | PASS |
| Design Tokens | WARN |

**Fix count:** 0 | No fixes required
**Warnings:**
- **Check:** Lint
- **Type:** lint-warning
- **File:** src/api/routes.ts
- **Line:** 12
- **Message:** Unexpected any value

- **Check:** No Any Types
- **Type:** any-type-warning
- **File:** src/api/routes.ts
- **Line:** 8
- **Message:** any type found: handler(req: any)

- **Check:** Design Tokens
- **Type:** token-warning
- **File:** src/components/Card.tsx
- **Line:** 5
- **Message:** Hex color values found — consider using design tokens
EOF
)

# Failed — test failure
MOCK_FAILED_TEST=$(cat <<'EOF'
## Validation Result

**Status:** FAILED
**Chunk:** 2/4: API routes
**Mode:** per-chunk

| Check | Result |
|-------|--------|
| TypeScript Strict | PASS |
| Lint | PASS |
| No Any Types | PASS |
| Build | PASS |
| Tests + Coverage | FAIL |
| Design Tokens | SKIP |

**Fix count:** 0 | No fixes required
**Errors:**
- **Check:** Tests + Coverage
- **Type:** test-failure
- **File:** src/api/__tests__/routes.test.ts
- **Line:** 15
- **Message:** Expected 200 but received 404
- **Pattern:** Test assertion mismatch
EOF
)

# Failed — build error
MOCK_FAILED_BUILD=$(cat <<'EOF'
## Validation Result

**Status:** FAILED
**Chunk:** 1/3: Components
**Mode:** per-chunk

| Check | Result |
|-------|--------|
| TypeScript Strict | PASS |
| Lint | PASS |
| No Any Types | PASS |
| Build | FAIL |
| Tests + Coverage | SKIP |
| Design Tokens | SKIP |

**Fix count:** 0 | No fixes required
**Errors:**
- **Check:** Build
- **Type:** build-error
- **File:** src/components/Card.tsx
- **Line:** 42
- **Message:** Property 'onClick' does not exist on type 'CardProps'
- **Pattern:** Missing prop definition
EOF
)

# Story-final passed
MOCK_STORY_FINAL=$(cat <<'EOF'
## Validation Result

**Status:** PASSED
**Chunk:** final
**Mode:** story-final

| Check | Result |
|-------|--------|
| TypeScript Strict | PASS |
| Lint | PASS |
| No Any Types | SKIP |
| Build | PASS |
| Tests + Coverage | PASS |
| Design Tokens | SKIP |
| Citation Scan | PASS |

**Fix count:** 0 | No fixes required
EOF
)

# Final chunk — lint/any-types escalated to FAIL
MOCK_FINAL_CHUNK_FAIL=$(cat <<'EOF'
## Validation Result

**Status:** FAILED
**Chunk:** 4/4: Final polish
**Mode:** per-chunk

| Check | Result |
|-------|--------|
| TypeScript Strict | PASS |
| Lint | FAIL |
| No Any Types | FAIL |
| Build | PASS |
| Tests + Coverage | PASS |
| Design Tokens | WARN |

**Fix count:** 0 | No fixes required
**Errors:**
- **Check:** Lint
- **Type:** lint-error
- **File:** src/utils/helpers.ts
- **Line:** 23
- **Message:** Unexpected console statement
- **Pattern:** Lint rule violation

- **Check:** No Any Types
- **Type:** type-error
- **File:** src/api/handler.ts
- **Line:** 7
- **Message:** any type found: processData(data: any)
- **Pattern:** Untyped any usage

**Warnings:**
- **Check:** Design Tokens
- **Type:** token-warning
- **File:** src/components/Badge.tsx
- **Line:** 3
- **Message:** Hex color values found — consider using design tokens
EOF
)

# All checks skipped
MOCK_ALL_SKIP=$(cat <<'EOF'
## Validation Result

**Status:** PASSED
**Chunk:** 1/3: Config
**Mode:** per-chunk

| Check | Result |
|-------|--------|
| TypeScript Strict | SKIP |
| Lint | SKIP |
| No Any Types | SKIP |
| Build | SKIP |
| Tests + Coverage | SKIP |
| Design Tokens | SKIP |

**Fix count:** 0 | No fixes required
EOF
)

# Multiple errors
MOCK_MULTI_ERROR=$(cat <<'EOF'
## Validation Result

**Status:** FAILED
**Chunk:** 3/5: Integration
**Mode:** per-chunk

| Check | Result |
|-------|--------|
| TypeScript Strict | FAIL |
| Lint | PASS |
| No Any Types | PASS |
| Build | FAIL |
| Tests + Coverage | FAIL |
| Design Tokens | SKIP |

**Fix count:** 0 | No fixes required
**Errors:**
- **Check:** TypeScript Strict
- **Type:** type-error
- **File:** tsconfig.json
- **Line:** -
- **Message:** TypeScript strict mode not enabled in tsconfig.json
- **Pattern:** Missing compiler option

- **Check:** Build
- **Type:** build-error
- **File:** src/index.ts
- **Line:** 5
- **Message:** Cannot find module './missing'
- **Pattern:** Missing import

- **Check:** Tests + Coverage
- **Type:** test-failure
- **File:** src/__tests__/index.test.ts
- **Line:** 10
- **Message:** Expected true but received false
- **Pattern:** Test assertion mismatch
EOF
)


# ═══════════════════════════════════════════════════════════════════
# TESTS
# ═══════════════════════════════════════════════════════════════════

# ── Test 1: PASSED output has all required fields ─────────────────

echo ""
echo "Test 1: PASSED output contains all required fields"

assert_contains "$MOCK_PASSED" "## Validation Result" "Has header"
assert_contains "$MOCK_PASSED" "**Status:** PASSED" "Has status field"
assert_contains "$MOCK_PASSED" "**Chunk:** 2/4: API routes" "Has chunk field"
assert_contains "$MOCK_PASSED" "**Mode:** per-chunk" "Has mode field"
assert_contains "$MOCK_PASSED" "**Fix count:** 0" "Has fix count"

# ── Test 2: PASSED output has check table ─────────────────────────

echo ""
echo "Test 2: PASSED output has complete check table"

assert_contains "$MOCK_PASSED" "| TypeScript Strict | PASS |" "TypeScript row"
assert_contains "$MOCK_PASSED" "| Lint | PASS |" "Lint row"
assert_contains "$MOCK_PASSED" "| No Any Types | PASS |" "Any types row"
assert_contains "$MOCK_PASSED" "| Build | PASS |" "Build row"
assert_contains "$MOCK_PASSED" "| Tests + Coverage | PASS |" "Tests row"
assert_contains "$MOCK_PASSED" "| Design Tokens | SKIP |" "Tokens row"
assert_not_contains "$MOCK_PASSED" "**Errors:**" "No errors section"
assert_not_contains "$MOCK_PASSED" "**Warnings:**" "No warnings section"

# ── Test 3: PARTIAL output has warnings section ───────────────────

echo ""
echo "Test 3: PARTIAL output has warnings, no errors"

assert_contains "$MOCK_PARTIAL" "**Status:** PARTIAL" "Status is PARTIAL"
assert_contains "$MOCK_PARTIAL" "| Lint | WARN |" "Lint shows WARN"
assert_contains "$MOCK_PARTIAL" "| No Any Types | WARN |" "Any types shows WARN"
assert_contains "$MOCK_PARTIAL" "| Design Tokens | WARN |" "Tokens shows WARN"
assert_contains "$MOCK_PARTIAL" "**Warnings:**" "Has warnings section"
assert_not_contains "$MOCK_PARTIAL" "**Errors:**" "No errors section"

# ── Test 4: PARTIAL warnings have structured blocks ───────────────

echo ""
echo "Test 4: Warning blocks have required fields"

assert_contains "$MOCK_PARTIAL" "- **Check:** Lint" "Warning check field"
assert_contains "$MOCK_PARTIAL" "- **Type:** lint-warning" "Warning type field"
assert_contains "$MOCK_PARTIAL" "- **File:** src/api/routes.ts" "Warning file field"
assert_contains "$MOCK_PARTIAL" "- **Line:** 12" "Warning line field"
assert_contains "$MOCK_PARTIAL" "- **Message:** Unexpected any value" "Warning message field"

# ── Test 5: FAILED test output has error blocks ───────────────────

echo ""
echo "Test 5: FAILED output has structured error blocks"

assert_contains "$MOCK_FAILED_TEST" "**Status:** FAILED" "Status is FAILED"
assert_contains "$MOCK_FAILED_TEST" "| Tests + Coverage | FAIL |" "Tests shows FAIL"
assert_contains "$MOCK_FAILED_TEST" "**Errors:**" "Has errors section"
assert_contains "$MOCK_FAILED_TEST" "- **Check:** Tests + Coverage" "Error check field"
assert_contains "$MOCK_FAILED_TEST" "- **Type:** test-failure" "Error type is test-failure"
assert_contains "$MOCK_FAILED_TEST" "- **File:** src/api/__tests__/routes.test.ts" "Error file field"
assert_contains "$MOCK_FAILED_TEST" "- **Line:** 15" "Error line field"
assert_contains "$MOCK_FAILED_TEST" "- **Message:** Expected 200 but received 404" "Error message field"
assert_contains "$MOCK_FAILED_TEST" "- **Pattern:** Test assertion mismatch" "Error pattern field"

# ── Test 6: FAILED build error has correct type ───────────────────

echo ""
echo "Test 6: Build error has type build-error"

assert_contains "$MOCK_FAILED_BUILD" "- **Type:** build-error" "Error type is build-error"
assert_contains "$MOCK_FAILED_BUILD" "| Build | FAIL |" "Build shows FAIL"

# ── Test 7: Story-final mode ──────────────────────────────────────

echo ""
echo "Test 7: Story-final mode has correct fields"

assert_contains "$MOCK_STORY_FINAL" "**Status:** PASSED" "Story-final passes"
assert_contains "$MOCK_STORY_FINAL" "**Chunk:** final" "Chunk is 'final'"
assert_contains "$MOCK_STORY_FINAL" "**Mode:** story-final" "Mode is story-final"
# Pins the check-8 row string for the next reader; the mock table predates the
# live agent's full row set, so this is NOT a drift guard for the validator.
assert_contains "$MOCK_STORY_FINAL" "| Citation Scan | PASS |" "Story-final carries the Citation Scan row"

# ── Test 8: Final chunk escalates WARN to FAIL ────────────────────

echo ""
echo "Test 8: Final chunk escalates lint/any-types to FAIL"

assert_contains "$MOCK_FINAL_CHUNK_FAIL" "**Status:** FAILED" "Final chunk with lint errors is FAILED"
assert_contains "$MOCK_FINAL_CHUNK_FAIL" "| Lint | FAIL |" "Lint escalated to FAIL on final chunk"
assert_contains "$MOCK_FINAL_CHUNK_FAIL" "| No Any Types | FAIL |" "Any types escalated to FAIL on final chunk"
assert_contains "$MOCK_FINAL_CHUNK_FAIL" "- **Type:** lint-error" "Lint error type"
assert_contains "$MOCK_FINAL_CHUNK_FAIL" "- **Type:** type-error" "Type error type"

# ── Test 9: Final chunk can have both errors and warnings ─────────

echo ""
echo "Test 9: Final chunk has both errors and warnings"

assert_contains "$MOCK_FINAL_CHUNK_FAIL" "**Errors:**" "Has errors section"
assert_contains "$MOCK_FINAL_CHUNK_FAIL" "**Warnings:**" "Has warnings section"
assert_contains "$MOCK_FINAL_CHUNK_FAIL" "| Design Tokens | WARN |" "Tokens still WARN on final"

# ── Test 10: All checks SKIP still PASSED ─────────────────────────

echo ""
echo "Test 10: All checks skipped produces PASSED status"

assert_contains "$MOCK_ALL_SKIP" "**Status:** PASSED" "All-skip is PASSED"
assert_contains "$MOCK_ALL_SKIP" "| TypeScript Strict | SKIP |" "TypeScript SKIP"
assert_contains "$MOCK_ALL_SKIP" "| Lint | SKIP |" "Lint SKIP"
assert_contains "$MOCK_ALL_SKIP" "| Build | SKIP |" "Build SKIP"
assert_contains "$MOCK_ALL_SKIP" "| Tests + Coverage | SKIP |" "Tests SKIP"
assert_not_contains "$MOCK_ALL_SKIP" "**Errors:**" "No errors on all-skip"
assert_not_contains "$MOCK_ALL_SKIP" "**Warnings:**" "No warnings on all-skip"

# ── Test 11: Multiple errors parsed correctly ─────────────────────

echo ""
echo "Test 11: Multiple error blocks parsed correctly"

assert_contains "$MOCK_MULTI_ERROR" "**Status:** FAILED" "Status is FAILED"
# Count error blocks by checking for Type fields
type_count=$(echo "$MOCK_MULTI_ERROR" | grep -c "\- \*\*Type:\*\*" || true)
if [ "$type_count" -eq 3 ]; then
  pass "Three error blocks present"
else
  fail "Three error blocks present" "3" "$type_count"
fi
assert_contains "$MOCK_MULTI_ERROR" "- **Type:** type-error" "Has type-error"
assert_contains "$MOCK_MULTI_ERROR" "- **Type:** build-error" "Has build-error"
assert_contains "$MOCK_MULTI_ERROR" "- **Type:** test-failure" "Has test-failure"

# ── Test 12: Skill routing — test-failure routes to test-fix ──────

echo ""
echo "Test 12: test-failure type routes to test-fix"

# The skill routes based on Type field value
error_type=$(echo "$MOCK_FAILED_TEST" | sed -n 's/.*\*\*Type:\*\* //p' | head -1)
if [ "$error_type" = "test-failure" ]; then
  pass "Error type parsed as test-failure (routes to test-fix)"
else
  fail "Error type parsed as test-failure (routes to test-fix)" "test-failure" "$error_type"
fi

# ── Test 13: Skill routing — build-error routes to refine-chunk ───

echo ""
echo "Test 13: build-error type routes to refine-chunk"

error_type=$(echo "$MOCK_FAILED_BUILD" | sed -n 's/.*\*\*Type:\*\* //p' | head -1)
if [ "$error_type" = "build-error" ]; then
  pass "Error type parsed as build-error (routes to refine-chunk)"
else
  fail "Error type parsed as build-error (routes to refine-chunk)" "build-error" "$error_type"
fi

# ── Test 14: Skill routing — lint-error routes to refine-chunk ────

echo ""
echo "Test 14: lint-error type routes to refine-chunk"

error_type=$(echo "$MOCK_FINAL_CHUNK_FAIL" | sed -n 's/.*\*\*Type:\*\* //p' | head -1)
if [ "$error_type" = "lint-error" ]; then
  pass "Error type parsed as lint-error (routes to refine-chunk)"
else
  fail "Error type parsed as lint-error (routes to refine-chunk)" "lint-error" "$error_type"
fi

# ── Test 15: Status field parsing ─────────────────────────────────

echo ""
echo "Test 15: Status field parses correctly for all variants"

for mock_name in MOCK_PASSED MOCK_PARTIAL MOCK_FAILED_TEST MOCK_STORY_FINAL; do
  mock_val="${!mock_name}"
  status=$(echo "$mock_val" | sed -n 's/.*\*\*Status:\*\* //p' | head -1)
  if [ -n "$status" ]; then
    pass "Status parsed from $mock_name: $status"
  else
    fail "Status parsed from $mock_name" "(a value)" "(empty)"
  fi
done

# ── Test 16: Mode field parsing ───────────────────────────────────

echo ""
echo "Test 16: Mode field parses correctly"

mode_perchunk=$(echo "$MOCK_PASSED" | sed -n 's/.*\*\*Mode:\*\* //p' | head -1)
mode_final=$(echo "$MOCK_STORY_FINAL" | sed -n 's/.*\*\*Mode:\*\* //p' | head -1)

if [ "$mode_perchunk" = "per-chunk" ]; then
  pass "Per-chunk mode parsed"
else
  fail "Per-chunk mode parsed" "per-chunk" "$mode_perchunk"
fi

if [ "$mode_final" = "story-final" ]; then
  pass "Story-final mode parsed"
else
  fail "Story-final mode parsed" "story-final" "$mode_final"
fi

# ── Test 17: Warning type values are valid ────────────────────────

echo ""
echo "Test 17: Warning types are from the valid set"

valid_warn_types="lint-warning any-type-warning token-warning"
warn_types=$(echo "$MOCK_PARTIAL" | sed -n 's/.*\*\*Type:\*\* //p')
all_valid=true
while IFS= read -r wt; do
  found=false
  for valid in $valid_warn_types; do
    if [ "$wt" = "$valid" ]; then
      found=true
      break
    fi
  done
  if ! $found; then
    all_valid=false
    fail "Warning type '$wt' is valid" "(one of: $valid_warn_types)" "$wt"
  fi
done <<< "$warn_types"

if $all_valid; then
  pass "All warning types are valid"
fi

# ── Test 18: Error type values are valid ──────────────────────────

echo ""
echo "Test 18: Error types are from the valid set"

valid_err_types="type-error lint-error build-error test-failure"
err_types=$(echo "$MOCK_MULTI_ERROR" | sed -n 's/.*\*\*Type:\*\* //p')
all_valid=true
while IFS= read -r et; do
  found=false
  for valid in $valid_err_types; do
    if [ "$et" = "$valid" ]; then
      found=true
      break
    fi
  done
  if ! $found; then
    all_valid=false
    fail "Error type '$et' is valid" "(one of: $valid_err_types)" "$et"
  fi
done <<< "$err_types"

if $all_valid; then
  pass "All error types are valid"
fi

# ── Test 19: Graduated severity — non-final chunk ─────────────────

echo ""
echo "Test 19: Non-final chunk uses WARN for lint and any-types"

# In MOCK_PARTIAL (chunk 2/4), lint and any-types are WARN, not FAIL
assert_contains "$MOCK_PARTIAL" "**Chunk:** 2/4:" "Is non-final chunk"
assert_contains "$MOCK_PARTIAL" "| Lint | WARN |" "Lint is WARN on non-final"
assert_contains "$MOCK_PARTIAL" "| No Any Types | WARN |" "Any types is WARN on non-final"
assert_contains "$MOCK_PARTIAL" "**Status:** PARTIAL" "Status is PARTIAL (not FAILED)"

# ── Test 20: Graduated severity — final chunk ─────────────────────

echo ""
echo "Test 20: Final chunk escalates lint and any-types to FAIL"

# In MOCK_FINAL_CHUNK_FAIL (chunk 4/4), lint and any-types are FAIL
assert_contains "$MOCK_FINAL_CHUNK_FAIL" "**Chunk:** 4/4:" "Is final chunk"
assert_contains "$MOCK_FINAL_CHUNK_FAIL" "| Lint | FAIL |" "Lint is FAIL on final"
assert_contains "$MOCK_FINAL_CHUNK_FAIL" "| No Any Types | FAIL |" "Any types is FAIL on final"
assert_contains "$MOCK_FINAL_CHUNK_FAIL" "**Status:** FAILED" "Status is FAILED"

# ── Test 21: Typecheck, build, tests always FAIL regardless ───────

echo ""
echo "Test 21: Typecheck, build, tests always FAIL regardless of chunk position"

# TypeScript strict is FAIL even on non-final chunk (MOCK_MULTI_ERROR is chunk 3/5)
assert_contains "$MOCK_MULTI_ERROR" "**Chunk:** 3/5:" "Is non-final chunk"
assert_contains "$MOCK_MULTI_ERROR" "| TypeScript Strict | FAIL |" "TypeScript FAIL on non-final"
assert_contains "$MOCK_MULTI_ERROR" "| Build | FAIL |" "Build FAIL on non-final"
assert_contains "$MOCK_MULTI_ERROR" "| Tests + Coverage | FAIL |" "Tests FAIL on non-final"

# ── Summary ──────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $TOTAL total"
echo "════════════════════════════════════════"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

exit 0
