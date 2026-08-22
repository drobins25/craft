#!/bin/bash
# test-dashboard-wrapper.sh — Tests for scripts/dashboard/dashboard-run.sh:
# degradation paths, root resolution, single-flight lock, and the
# real-corpus smoke (node count, timing, idempotent second run).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

WRAPPER="$PLUGIN_ROOT/scripts/dashboard/dashboard-run.sh"
CORPUS="$PLUGIN_ROOT/scripts/dashboard/__fixtures__/corpus"

echo "=== test-dashboard-wrapper.sh ==="
echo ""

# Builds a fresh fixture root: <tmp>/.craft is a copy of the corpus.
make_fixture_root() {
  local tmp
  tmp=$(mktemp -d)
  cp -R "$CORPUS" "$tmp/.craft"
  echo "$tmp"
}

# A PATH that has every tool the wrapper needs EXCEPT python3.
make_no_python_path() {
  local stub
  stub=$(mktemp -d)
  local tool
  for tool in bash sh dirname basename mkdir printf date find rm cp mv cat grep sed ls touch; do
    local src
    src=$(command -v "$tool" 2>/dev/null) || continue
    ln -s "$src" "$stub/$tool" 2>/dev/null || true
  done
  echo "$stub"
}

# --- Test 1: no python3 on PATH -> degraded, graph.js untouched (FIRST) ---
begin_test "no python3: exits 0, status python-missing, graph.js untouched"

ROOT=$(make_fixture_root)
mkdir -p "$ROOT/.craft/graph"
echo "pre-existing graph" > "$ROOT/.craft/graph/graph.js"
STUB_PATH=$(make_no_python_path)

set +e
OUT=$(PATH="$STUB_PATH" bash "$WRAPPER" --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_contains "stdout reports python-missing" "python-missing" "$OUT"
assert_file_exists "build-status.js written" "$ROOT/.craft/graph/build-status.js"
assert_file_contains "status is degraded" '"status":"degraded"' "$ROOT/.craft/graph/build-status.js"
assert_file_contains "reason is python-missing" '"reason":"python-missing"' "$ROOT/.craft/graph/build-status.js"
assert_eq "graph.js untouched" "pre-existing graph" "$(cat "$ROOT/.craft/graph/graph.js")"

rm -rf "$ROOT" "$STUB_PATH"
echo ""

# --- Test 2: builder error -> degraded builder-error, graph.js untouched ---
begin_test "builder raises: exits 0, status builder-error, graph.js untouched"

ROOT=$(make_fixture_root)
mkdir -p "$ROOT/.craft/graph"
echo "pre-existing graph" > "$ROOT/.craft/graph/graph.js"
FAKE_BIN=$(mktemp -d)
printf '#!/bin/bash\nexit 3\n' > "$FAKE_BIN/python3"
chmod +x "$FAKE_BIN/python3"

set +e
OUT=$(PATH="$FAKE_BIN:$PATH" bash "$WRAPPER" --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_contains "stdout reports builder-error" "builder-error" "$OUT"
assert_file_contains "reason is builder-error" '"reason":"builder-error"' "$ROOT/.craft/graph/build-status.js"
assert_eq "graph.js untouched" "pre-existing graph" "$(cat "$ROOT/.craft/graph/graph.js")"

rm -rf "$ROOT" "$FAKE_BIN"
echo ""

# --- Test 3: missing build.py -> builder-missing ---
begin_test "missing build.py: exits 0, status builder-missing"

ROOT=$(make_fixture_root)
LONELY=$(mktemp -d)
cp "$WRAPPER" "$LONELY/dashboard-run.sh"

set +e
OUT=$(bash "$LONELY/dashboard-run.sh" --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_contains "stdout reports builder-missing" "builder-missing" "$OUT"
assert_file_contains "reason is builder-missing" '"reason":"builder-missing"' "$ROOT/.craft/graph/build-status.js"

rm -rf "$ROOT" "$LONELY"
echo ""

# --- Test 4: root without .craft -> craft-missing, .craft NOT created ---
begin_test "root without .craft: exits 0, craft-missing, nothing created"

BARE=$(mktemp -d)
set +e
OUT=$(bash "$WRAPPER" --root "$BARE" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_contains "stdout reports craft-missing" "craft-missing" "$OUT"
assert_dir_not_exists ".craft was not created" "$BARE/.craft"

rm -rf "$BARE"
echo ""

# --- Test 5: nonexistent root -> root-missing ---
begin_test "nonexistent --root: exits 0, root-missing"

set +e
OUT=$(bash "$WRAPPER" --root "/nonexistent/nowhere-$$" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_contains "stdout reports root-missing" "root-missing" "$OUT"
echo ""

# --- Test 6: no --root resolves via CRAFT_PROJECT_ROOT ---
begin_test "no --root: resolves via CRAFT_PROJECT_ROOT"

ROOT=$(make_fixture_root)
set +e
OUT=$(CRAFT_PROJECT_ROOT="$ROOT" bash "$WRAPPER" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_contains "healthy build reports ok" '"status": "ok"' "$OUT"
assert_file_exists "graph.js written" "$ROOT/.craft/graph/graph.js"

rm -rf "$ROOT"
echo ""

# --- Test 7: no --root and no env resolves via find-workshop.sh ---
begin_test "no --root and no env: resolves via find-workshop.sh"

ROOT=$(make_fixture_root)
cp "$PLUGIN_ROOT/templates/craft/project.md" "$ROOT/.craft/project.md" 2>/dev/null \
  || echo "# Sample Project" > "$ROOT/.craft/project.md"

set +e
OUT=$(cd "$ROOT" && CRAFT_PROJECT_ROOT="" bash "$WRAPPER" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_contains "healthy build reports ok" '"status": "ok"' "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 8: healthy build writes graph, records, ok status ---
begin_test "healthy build: status ok, graph.js and records/ present, graph dir created"

ROOT=$(make_fixture_root)
assert_dir_not_exists "graph dir absent before build" "$ROOT/.craft/graph"

set +e
OUT=$(bash "$WRAPPER" --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_file_exists "graph.js present" "$ROOT/.craft/graph/graph.js"
assert_dir_exists "records/ present" "$ROOT/.craft/graph/records"
assert_file_contains "status ok" '"status":"ok"' "$ROOT/.craft/graph/build-status.js"

rm -rf "$ROOT"
echo ""

# --- Test 9: concurrent invocation skips, writes only build-status ---
begin_test "concurrent invocation: build-skipped-concurrent, graph untouched"

ROOT=$(make_fixture_root)
mkdir -p "$ROOT/.craft/graph/.build-lock"
echo "pre-existing graph" > "$ROOT/.craft/graph/graph.js"

set +e
OUT=$(bash "$WRAPPER" --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_contains "stdout reports build-skipped-concurrent" "build-skipped-concurrent" "$OUT"
assert_eq "graph.js untouched" "pre-existing graph" "$(cat "$ROOT/.craft/graph/graph.js")"
assert_dir_exists "foreign lock left in place" "$ROOT/.craft/graph/.build-lock"

rm -rf "$ROOT"
echo ""

# --- Test 10: stale lock from a dead holder is broken ---
begin_test "stale lock is broken and the build proceeds"

ROOT=$(make_fixture_root)
mkdir -p "$ROOT/.craft/graph/.build-lock"
touch -t 202001010000 "$ROOT/.craft/graph/.build-lock"

set +e
OUT=$(bash "$WRAPPER" --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_contains "build ran despite stale lock" '"status": "ok"' "$OUT"
assert_file_exists "graph.js written" "$ROOT/.craft/graph/graph.js"

rm -rf "$ROOT"
echo ""

# --- Test 11: real corpus smoke - count, timing, idempotent second run ---
begin_test "real corpus: node count matches filesystem, <1000ms, second run writes zero"

REPO_ROOT="$PLUGIN_ROOT"
if [ -d "$REPO_ROOT/.craft" ]; then
  # Expected count computed with the SAME predicates the builder's registry
  # uses - never a hardcoded constant.
  EXPECTED=$(find "$REPO_ROOT/.craft" \
    \( -path "*/cycles/*/stories/*.md" \
    -o -path "*/.craft/backlog/*.md" \
    -o -path "*/cycles/*/cycle.yaml" \
    -o -path "*/.craft/fixes/*.md" \
    -o -path "*/.craft/tweaks/*.md" \
    -o -path "*/.craft/mockups/*/record.md" \
    -o -path "*/.craft/dials/*.md" \
    -o -path "*/.craft/notebook/ideas/*.md" \
    -o -path "*/.craft/notebook/todos/*.md" \
    -o -path "*/.craft/notebook/notes/*.md" \
    -o -path "*/.craft/riff/notes/*.md" \
    -o -path "*/.craft/planning/*.md" \) \
    -not -path "*/.craft/backlog/*/*" \
    -not -path "*/.craft/fixes/*/*" \
    -not -path "*/.craft/tweaks/*/*" \
    -not -path "*/.craft/dials/*/*" 2>/dev/null | sort -u | wc -l | tr -d ' ')

  set +e
  TIMING=$(python3 - "$WRAPPER" "$REPO_ROOT" <<'PYEOF'
import json, subprocess, sys, time
wrapper, root = sys.argv[1], sys.argv[2]
start = time.time()
proc = subprocess.run(["bash", wrapper, "--root", root], capture_output=True, text=True)
elapsed_ms = int((time.time() - start) * 1000)
status = json.loads(proc.stdout.strip().splitlines()[-1])
start2 = time.time()
proc2 = subprocess.run(["bash", wrapper, "--root", root], capture_output=True, text=True)
status2 = json.loads(proc2.stdout.strip().splitlines()[-1])
print(json.dumps({
    "rc": proc.returncode, "elapsed_ms": elapsed_ms,
    "nodes": status.get("nodes"), "unresolved_reported": "annotations" in status,
    "second_written": status2.get("written"),
}))
PYEOF
)
  RC=$?
  set -e

  assert_exit_code "smoke harness ran" "0" "$RC"
  NODES=$(echo "$TIMING" | grep -o '"nodes": *[0-9]*' | grep -o '[0-9]*')
  ELAPSED=$(echo "$TIMING" | grep -o '"elapsed_ms": *[0-9]*' | grep -o '[0-9]*')
  SECOND_WRITTEN=$(echo "$TIMING" | grep -o '"second_written": *[0-9]*' | grep -o '[0-9]*')

  assert_eq "node count equals filesystem-computed expectation" "$EXPECTED" "$NODES"
  if [ "${ELAPSED:-9999}" -lt 1000 ]; then
    echo "  PASS: build completed in ${ELAPSED}ms (<1000ms)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: build took ${ELAPSED}ms (limit 1000ms)"
    FAIL=$((FAIL + 1))
  fi
  assert_eq "second consecutive run writes zero files" "0" "$SECOND_WRITTEN"
  assert_contains "unresolved annotations reported non-fatally" '"unresolved_reported": true' "$TIMING"
else
  echo "  PASS: no real .craft in this checkout - smoke skipped"
  PASS=$((PASS + 1))
fi
echo ""

# --- Test 12: wrapper writes nothing outside .craft/graph ---
begin_test "wrapper writes nothing outside .craft/graph"

ROOT=$(make_fixture_root)
BEFORE=$(find "$ROOT/.craft" -not -path "*/graph*" -type f | sort)

set +e
OUT=$(bash "$WRAPPER" --root "$ROOT" 2>&1)
RC=$?
set -e

AFTER=$(find "$ROOT/.craft" -not -path "*/graph*" -type f | sort)
assert_eq "no file outside graph/ was added or removed" "$BEFORE" "$AFTER"

rm -rf "$ROOT"
echo ""

# --- Test 13: first build seeds the self-ignoring .gitignore ---
begin_test "first build seeds .craft/graph/.gitignore containing *"

ROOT=$(make_fixture_root)
set +e
OUT=$(bash "$WRAPPER" --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_file_exists ".gitignore seeded" "$ROOT/.craft/graph/.gitignore"
assert_eq ".gitignore content is a single star" "*" "$(cat "$ROOT/.craft/graph/.gitignore")"

rm -rf "$ROOT"
echo ""

# --- Test 14: a deleted .gitignore is never recreated ---
begin_test "a .gitignore deleted after the first build is never recreated"

ROOT=$(make_fixture_root)
set +e
OUT=$(bash "$WRAPPER" --root "$ROOT" 2>&1)
RC=$?
set -e
rm -f "$ROOT/.craft/graph/.gitignore"

set +e
OUT=$(bash "$WRAPPER" --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "second build exits 0" "0" "$RC"
assert_file_not_exists "deleted .gitignore stays deleted" "$ROOT/.craft/graph/.gitignore"
assert_contains "second build still ok" '"status": "ok"' "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 15: a pre-existing graph folder is never seeded ---
begin_test "a graph folder that already existed is never seeded"

ROOT=$(make_fixture_root)
mkdir -p "$ROOT/.craft/graph"

set +e
OUT=$(bash "$WRAPPER" --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_file_not_exists "pre-existing folder not seeded" "$ROOT/.craft/graph/.gitignore"

rm -rf "$ROOT"
echo ""

# --- Test 16: degraded build on a fresh folder still seeds ---
begin_test "degraded build with no python3 still seeds on a fresh folder"

ROOT=$(make_fixture_root)
STUB_PATH=$(make_no_python_path)

set +e
OUT=$(PATH="$STUB_PATH" bash "$WRAPPER" --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_file_exists ".gitignore seeded on degraded path" "$ROOT/.craft/graph/.gitignore"
assert_file_contains "status is degraded" '"status":"degraded"' "$ROOT/.craft/graph/build-status.js"

rm -rf "$ROOT" "$STUB_PATH"
echo ""

finish_tests "test-dashboard-wrapper"
