# Plan: TDD Enforcement & Quality Gates

> **Status: Implemented.** This was a planning document written before the TDD enforcement changes shipped. The changes described below have been applied to `agents/implementer.md`, `skills/validate-chunk/SKILL.md`, and `commands/craft-story-implement.md`. This file is a completed-decision record, not a description of planned work.
>
> **Superseded in 2.19.0.** The test-first workflow recorded below no longer runs. The implementer now follows The Proof Posture in `agents/implementer.md`: tests written from the plan, each named test seen failing once, every pass quoted. This file stays as history.

## Summary

Add strict TDD enforcement and quality gates to prevent edge case bugs and runtime errors from reaching production.

**Problem:**
- Edge cases being missed during implementation
- Frontend syntax/runtime errors in production
- Tests being skipped when "no test setup" exists
- Not actually following TDD (tests written after, not before)

**Solution:**
- Enforce TDD workflow in implementer agent (test-first)
- Add edge case checklist requirement
- Never skip tests — set up infrastructure if missing
- Enhanced validation in validate-chunk

---

## Files Updated

1. `agents/implementer.md` — TDD workflow + enforcement
2. `skills/validate-chunk/SKILL.md` — Enhanced validation
3. `commands/craft-story-implement.md` — Test infrastructure check

---

## 1. agents/implementer.md

### Previous State
The implementer agent has basic implementation guidance but no TDD enforcement.

### Changes Applied

**Add after the frontmatter/description section:**

```markdown
## Test-Driven Development (Required)

### TDD Categories

**Category 1: Strict TDD (Logic Layer)**

Applies to: `utils/`, `lib/`, `services/`, `hooks/`, `api/`, any pure functions

Workflow:
1. **RED** — Write test file first with all cases:
   - Success case
   - Error/failure case
   - Edge cases (empty, null, boundary values)
2. **Run tests** — They MUST fail (if they pass, tests are wrong)
3. **GREEN** — Write minimal implementation to pass tests
4. **Run tests** — They MUST pass
5. **REFACTOR** — Clean up while keeping tests green

**Category 2: Interaction-First (UI Layer)**

Applies to: Components, pages, layouts in `components/`, `app/`, `pages/`

Workflow:
1. Identify critical interactions:
   - Form submission → validation + success/error
   - Data loading → loading/error/success states
   - User actions → expected outcomes
2. Write tests for critical interactions FIRST
3. Run tests → MUST fail
4. Implement component
5. Run tests → MUST pass
6. Visual styling can proceed without tests

**Required UI State Tests:**
- Loading state renders correctly
- Error state renders correctly
- Empty state renders correctly
- Primary user action works

### Test Infrastructure Requirement

**NEVER skip tests.** If project has no test setup:

1. Check for test config:
   ```bash
   ls jest.config.* vitest.config.* 2>/dev/null
   ```

2. If missing, SET UP before implementing:
   ```bash
   # For Vite/React projects
   npm install -D vitest @testing-library/react @testing-library/jest-dom

   # Create vitest.config.ts
   # Create test setup file
   ```

3. Then proceed with TDD

**"No test setup, skipping tests" is NEVER acceptable.**

### No Any Types

Never use `any` type in TypeScript without explicit user approval.

Instead:
- Use `unknown` with type guards
- Define proper interfaces/types
- Use generics where appropriate

If you feel `any` is needed, ASK the user first:
> "I'm considering using `any` for [reason]. This reduces type safety. Approve, or should I define a proper type?"

### Edge Case Checklist

Before marking ANY implementation complete, verify handling for:

**All Code:**
- [ ] Empty/null input — returns sensible default or error?
- [ ] Error/failure state — caught and handled gracefully?
- [ ] Boundary values (0, 1, max, negative) — behaves correctly?
- [ ] Concurrent/duplicate calls — safe? (no race conditions)
- [ ] Missing/malformed data — validated at boundary?
- [ ] Type coercion edge cases — "0", "", false, null, undefined?

**UI Components:**
- [ ] Loading state — shows skeleton/spinner?
- [ ] Error state — shows error message + retry?
- [ ] Empty state — shows helpful empty message?
- [ ] Overflow/long content — truncates or scrolls?
- [ ] Rapid clicks — debounced or disabled during action?

**API Routes:**
- [ ] Invalid input — returns 400 with message?
- [ ] Unauthorized — returns 401?
- [ ] Not found — returns 404?
- [ ] Server error — returns 500, logs error, doesn't leak details?
- [ ] Rate limiting — considered?

### Strict TypeScript

Verify project has strict TypeScript. If `tsconfig.json` doesn't have these, ADD them:

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true
  }
}
```

If enabling strict mode causes errors in existing code, fix them — don't disable strict mode.
```

**Add to the implementation workflow section:**

```markdown
## Implementation Workflow Per Chunk

### Before Writing Any Code

1. **Verify test infrastructure exists**
   - If missing → set up first

2. **Identify code category**
   - Logic layer → Strict TDD
   - UI layer → Interaction-first

3. **Verify TypeScript strict mode**
   - If not enabled → enable it, fix any errors

### During Implementation

**For Logic Layer (Strict TDD):**

```
┌─────────────────────────────────────────┐
│ 1. Create test file                     │
│    __tests__/[name].test.ts             │
├─────────────────────────────────────────┤
│ 2. Write test cases:                    │
│    - describe('[FunctionName]')         │
│    - it('returns X when given Y')       │
│    - it('throws when given invalid')    │
│    - it('handles empty input')          │
│    - it('handles boundary values')      │
├─────────────────────────────────────────┤
│ 3. Run tests → MUST FAIL                │
│    npm test [file]                      │
│    (If tests pass, they're wrong)       │
├─────────────────────────────────────────┤
│ 4. Write implementation                 │
│    Minimal code to pass tests           │
├─────────────────────────────────────────┤
│ 5. Run tests → MUST PASS                │
│    npm test [file]                      │
├─────────────────────────────────────────┤
│ 6. Refactor if needed                   │
│    Keep tests passing                   │
├─────────────────────────────────────────┤
│ 7. Edge case checklist                  │
│    Verify all cases handled             │
└─────────────────────────────────────────┘
```

**For UI Layer (Interaction-First):**

```
┌─────────────────────────────────────────┐
│ 1. Identify critical interactions       │
│    - What user actions matter?          │
│    - What states must render?           │
├─────────────────────────────────────────┤
│ 2. Create test file                     │
│    __tests__/[Component].test.tsx       │
├─────────────────────────────────────────┤
│ 3. Write interaction tests:             │
│    - it('renders loading state')        │
│    - it('renders error state')          │
│    - it('renders empty state')          │
│    - it('handles submit click')         │
├─────────────────────────────────────────┤
│ 4. Run tests → MUST FAIL                │
├─────────────────────────────────────────┤
│ 5. Implement component                  │
│    - States first (loading/error/empty) │
│    - Then happy path                    │
│    - Then interactions                  │
├─────────────────────────────────────────┤
│ 6. Run tests → MUST PASS                │
├─────────────────────────────────────────┤
│ 7. Add styling/polish                   │
│    (No tests needed for visual-only)    │
├─────────────────────────────────────────┤
│ 8. Edge case checklist                  │
└─────────────────────────────────────────┘
```

### Chunk Completion Criteria

A chunk is NOT complete until:

- [ ] Tests written FIRST (TDD verified)
- [ ] All tests pass
- [ ] Edge case checklist reviewed
- [ ] No `any` types (or approved by user)
- [ ] TypeScript strict mode passes
- [ ] Code handles loading/error/empty states (if UI)
```

---

## 2. skills/validate-chunk/SKILL.md

### Previous State
Basic validation (typecheck, lint, build, tests).

### Changes Applied

**Update the validation steps to include:**

```markdown
## Validation Checks

### 1. TypeScript Strict Mode (Required)

```bash
# Verify strict mode is enabled
grep -q '"strict": true' tsconfig.json || echo "FAIL: strict mode not enabled"

# Run type check
npx tsc --noEmit
```

**If strict mode not enabled:** FAIL the validation. Implementer must enable it.

### 2. Lint Check

```bash
npm run lint
```

### 3. Build Check

```bash
npm run build
```

**Check for:**
- No TypeScript errors
- No build warnings about missing dependencies
- Bundle size within limits (if configured)

### 4. Test Check

```bash
npm test -- --coverage
```

**Requirements:**
- All tests pass
- New code has minimum 80% coverage
- Critical paths (error handling) covered

**If no tests exist:** FAIL. Implementation should have included tests.

### 5. TDD Verification

Verify tests were written before/with implementation:

```bash
# Check git history - test file should be committed with or before implementation
git log --oneline --name-only -10 | grep -E "\.test\.(ts|tsx)$"
```

Or verify test file exists for each new implementation file:
- `utils/foo.ts` → `__tests__/foo.test.ts` must exist
- `components/Bar.tsx` → `__tests__/Bar.test.tsx` must exist

### 6. Coverage Threshold

```bash
# Check coverage meets threshold
npm test -- --coverage --coverageThreshold='{
  "global": {
    "branches": 80,
    "functions": 80,
    "lines": 80,
    "statements": 80
  }
}'
```

**If coverage below 80%:** Warn and ask user if acceptable.

### 7. No Any Types Check

```bash
# Use FILES_CHANGED (comma-separated from orchestrator) instead of git diff
echo "$FILES_CHANGED" | tr ',' '\n' | sed 's/^ *//' | grep -E '\.(ts|tsx)$' | xargs grep -l ": any" 2>/dev/null | head -20
```

**If `any` found:** Verify it was explicitly approved by user.

## Validation Output

```
Chunk Validation: [chunk-name]
================================

TypeScript:  ✓ Strict mode enabled, no errors
Lint:        ✓ No warnings
Build:       ✓ Successful
Tests:       ✓ 12 passed, 0 failed
Coverage:    ✓ 87% (threshold: 80%)
TDD:         ✓ Test files exist for new code
Any Types:   ✓ None found

Result: PASSED
```

Or if failed:

```
Chunk Validation: [chunk-name]
================================

TypeScript:  ✓ Strict mode enabled, no errors
Lint:        ✓ No warnings
Build:       ✓ Successful
Tests:       ✗ 2 failed
Coverage:    ✗ 65% (threshold: 80%)
TDD:         ✗ Missing test for utils/auth.ts
Any Types:   ⚠ Found in services/api.ts (check if approved)

Result: FAILED

Issues to fix:
1. Fix failing tests in __tests__/login.test.ts
2. Add tests to increase coverage to 80%
3. Create test file for utils/auth.ts
4. Remove or justify 'any' in services/api.ts
```
```

---

## 3. commands/craft-story-implement.md

### Previous State
Has learning capture logic, but no test infrastructure check.

### Changes Applied

**Add to Step 3 (Review Before Starting) or create new Step 3b:**

```markdown
### Step 3b: Verify Test Infrastructure

Before starting implementation, verify test infrastructure exists:

```bash
# Check for test config
if [ ! -f "jest.config.js" ] && [ ! -f "jest.config.ts" ] && \
   [ ! -f "vitest.config.js" ] && [ ! -f "vitest.config.ts" ]; then
  echo "No test infrastructure detected"
fi

# Check for test dependencies
grep -q "vitest\|jest" package.json || echo "No test dependencies"
```

**If test infrastructure missing:**

> "This project doesn't have test infrastructure set up. TDD is required for quality.
>
> Set up testing now?"

Use **AskUserQuestion**:
```yaml
question: "Set up test infrastructure?"
header: "Tests"
options:
  - label: "Yes, set up Vitest (Recommended)"
    description: "Fast, modern test runner for Vite projects"
  - label: "Yes, set up Jest"
    description: "Traditional test runner, wide ecosystem"
  - label: "I'll set it up manually"
    description: "Pause implementation until tests are ready"
```

**If "Yes, set up Vitest":**

```bash
npm install -D vitest @testing-library/react @testing-library/jest-dom @testing-library/user-event jsdom
```

Create `vitest.config.ts`:
```typescript
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./test/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
    },
  },
})
```

Create `test/setup.ts`:
```typescript
import '@testing-library/jest-dom'
```

Add to `package.json` scripts:
```json
{
  "scripts": {
    "test": "vitest",
    "test:coverage": "vitest --coverage"
  }
}
```

**Then proceed with implementation.**

**"Skip tests" is NEVER an option.**
```

**Also add to the Remember section:**

```markdown
## Remember

- **TDD is required** — tests first, then implementation
- **Never skip tests** — set up infrastructure if missing
- **Edge cases matter** — check the checklist before marking complete
- **Strict TypeScript** — enable and fix errors, don't disable
- **No any types** — use proper types or get explicit approval
```

---

## Implementation Order

1. **First:** Update `agents/implementer.md` — This is where the core TDD workflow lives
2. **Second:** Update `skills/validate-chunk/SKILL.md` — This verifies TDD was followed
3. **Third:** Update `commands/craft-story-implement.md` — This ensures test infra exists

---

## Testing the Changes

After implementing, verify by:

1. Start a new story implementation
2. Confirm it checks for test infrastructure
3. Confirm implementer follows TDD workflow (test first)
4. Confirm validate-chunk runs all new checks
5. Confirm edge case checklist is enforced

---

## Version

Bump to **0.9.0** after implementation (significant quality enforcement change).
