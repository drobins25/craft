#!/bin/bash
# test-portability-idioms.sh — Guard: shell idioms that break under GNU userland
# must not reappear anywhere under tests/, hooks/ or scripts/.
#
# Two banned idioms, both found live in this repo and both silent on macOS:
#
#   1. sed with an empty -i suffix argument (two separate words). BSD sed
#      reads the empty string as the backup suffix; GNU sed reads it as the
#      script and hard-errors. The house idiom is:
#
#        sed -i.bak <expr> <file> && rm -f "<file>.bak"
#
#      (see hooks/scripts/complete-chunk.sh for the canonical form).
#
#   2. A bare BSD `md5` piped in the middle of a command, with a `||`
#      fallback after it. A pipeline's exit status is its LAST command's,
#      so when `md5` is missing (every Linux box) the trailing `cut` still
#      exits 0, the `||` never fires, and the variable silently becomes
#      empty. The fallback is decorative. Reachable forms: try the Linux
#      tool (md5sum) first, or use single-command `md5 -q FILE || ...`,
#      or an explicit empty-check fallback.
#
# The scan skips full-line comments and this guard file itself (its header
# and seed fixture legitimately spell out the banned idioms).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Detail: $2"; }

echo "=== test-portability-idioms.sh ==="
echo ""

# Scanner: prints one line per violation, "<tag> <path>:<line>".
# Tags: sed-i-empty, piped-md5-fallback.
run_scan() {
  python3 - "$ROOT" <<'PYEOF'
import os, re, sys
root = sys.argv[1]
SELF = "test-portability-idioms.sh"
SED_BAD = "sed -i '" + "'"  # split so this scanner never matches its own source
# A bare BSD md5 (not md5sum) receiving piped input, with a || fallback
# later on the same line. The || can never fire, so the fallback is dead.
PIPED_MD5 = re.compile(r"(?<!\|)\|(?!\|)\s*md5\b")
violations = []
for sub in ("tests", "hooks", "scripts"):
    base = os.path.join(root, sub)
    if not os.path.isdir(base):
        continue
    for dirpath, dirnames, filenames in os.walk(base):
        for fname in sorted(filenames):
            if not fname.endswith(".sh") or fname == SELF:
                continue
            path = os.path.join(dirpath, fname)
            rel = os.path.relpath(path, root)
            try:
                lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
            except OSError:
                continue
            for i, line in enumerate(lines, 1):
                if line.lstrip().startswith("#"):
                    continue
                if SED_BAD in line:
                    violations.append(f"sed-i-empty {rel}:{i}")
                for m in PIPED_MD5.finditer(line):
                    if "||" in line[m.end():]:
                        violations.append(f"piped-md5-fallback {rel}:{i}")
                        break
print("\n".join(violations))
PYEOF
}

LIVE=$(run_scan)

# Test 1: no empty-suffix sed -i remains on the live tree
if ! echo "$LIVE" | grep -q '^sed-i-empty '; then
  pass "no empty-suffix 'sed -i' remains under tests/, hooks/, scripts/"
else
  fail "empty-suffix 'sed -i' found" "$(echo "$LIVE" | grep '^sed-i-empty ' | tr '\n' ' ')- use sed -i.bak + rm -f (see this file's header)"
fi

# Test 2: no piped-md5-with-dead-fallback remains on the live tree
if ! echo "$LIVE" | grep -q '^piped-md5-fallback '; then
  pass "no piped-md5 dead fallback remains under tests/, hooks/, scripts/"
else
  fail "piped-md5 dead fallback found" "$(echo "$LIVE" | grep '^piped-md5-fallback ' | tr '\n' ' ')- try md5sum first or use an empty-check (see this file's header)"
fi

# Test 3: the single-command `md5 -q FILE || ...` form is NOT flagged
# (test-merge-tokens.sh uses it correctly: a single command's exit reaches ||)
if ! echo "$LIVE" | grep -q 'test-merge-tokens\.sh'; then
  pass "single-command 'md5 -q FILE || ...' form is not flagged"
else
  fail "guard wrongly flags test-merge-tokens.sh" "$(echo "$LIVE" | grep 'test-merge-tokens\.sh' | tr '\n' ' ')"
fi

# Test 4: a seeded violation of each idiom is reported with file:line
SEED="$ROOT/scripts/zz-portability-seed-$$.sh"
cleanup_seed() { rm -f "$SEED"; }
trap cleanup_seed EXIT
{
  echo '#!/bin/bash'
  printf 'sed -i %s%s '\''s/a/b/'\'' somefile\n' "'" "'"
  echo 'X=$(echo hi | md5 2>/dev/null | cut -c1-8 || echo hi | md5sum | cut -c1-8)'
} > "$SEED"

SEEDED=$(run_scan)
SEED_REL="scripts/$(basename "$SEED")"

if echo "$SEEDED" | grep -q "^sed-i-empty ${SEED_REL}:2$"; then
  pass "seeded empty-suffix sed is reported with file:line"
else
  fail "seeded empty-suffix sed not reported" "expected 'sed-i-empty ${SEED_REL}:2' in: $(echo "$SEEDED" | tr '\n' ' ')"
fi

if echo "$SEEDED" | grep -q "^piped-md5-fallback ${SEED_REL}:3$"; then
  pass "seeded piped-md5 dead fallback is reported with file:line"
else
  fail "seeded piped-md5 dead fallback not reported" "expected 'piped-md5-fallback ${SEED_REL}:3' in: $(echo "$SEEDED" | tr '\n' ' ')"
fi

cleanup_seed
trap - EXIT

# Test 5: the rewritten stop-hook-guard test still passes on this machine
set +e
OUT=$(bash "$SCRIPT_DIR/test-stop-hook-guard.sh" 2>&1)
RC=$?
set -e
if [ "$RC" -eq 0 ]; then
  pass "tests/test-stop-hook-guard.sh still passes after the rewrite"
else
  fail "tests/test-stop-hook-guard.sh failed (exit $RC)" "$(echo "$OUT" | tail -5 | tr '\n' ' ')"
fi

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
