#!/bin/bash
# test-dashboard-insights.sh — Tests for scripts/dashboard/insights-check.sh:
# the sha-keyed freshness verdict for the insight sidecar, and the builder's
# guarantee that a rebuild never removes an authored graph-root sibling.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

CHECK_SCRIPT="$PLUGIN_ROOT/scripts/dashboard/insights-check.sh"
WRAPPER="$PLUGIN_ROOT/scripts/dashboard/dashboard-run.sh"
CORPUS="$PLUGIN_ROOT/scripts/dashboard/__fixtures__/corpus"

echo "=== test-dashboard-insights.sh ==="
echo ""

# Builds a fresh fixture root: <tmp>/.craft/graph holds a graph.js.
make_fixture_root() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.craft/graph"
  printf 'window.CRAFT_GRAPH = {"version":1,"nodes":[],"edges":[]};\n' > "$tmp/.craft/graph/graph.js"
  echo "$tmp"
}

write_sidecar() {
  printf 'window.CRAFT_INSIGHTS = {"version":1,"cards":[]};\n' > "$1/.craft/graph/insights.js"
}

# --- Test 1: no sidecar reports missing ---
begin_test "no sidecar reports missing"

ROOT=$(make_fixture_root)

set +e
OUT=$(bash "$CHECK_SCRIPT" --check --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "exits 0" "0" "$RC"
assert_contains "VERDICT=missing" "VERDICT=missing" "$OUT"
assert_contains "SIDECAR path is printed" "SIDECAR=$ROOT/.craft/graph/insights.js" "$OUT"
assert_contains "GRAPH_SHA is a real sha, not missing" "GRAPH_SHA=[0-9a-f]\{64\}" "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 2: stamped sha matching graph.js reports fresh ---
begin_test "stamped sha matching graph.js reports fresh"

ROOT=$(make_fixture_root)
write_sidecar "$ROOT"

set +e
STAMP_OUT=$(bash "$CHECK_SCRIPT" --stamp --root "$ROOT" 2>&1)
STAMP_RC=$?
OUT=$(bash "$CHECK_SCRIPT" --check --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "stamp exits 0" "0" "$STAMP_RC"
assert_contains "stamp reports STAMPED=1" "STAMPED=1" "$STAMP_OUT"
assert_file_exists "receipt written beside the graph data" "$ROOT/.craft/graph/.insights.sha256"
assert_exit_code "check exits 0" "0" "$RC"
assert_contains "VERDICT=fresh" "VERDICT=fresh" "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 3: graph.js changed after stamping reports stale ---
begin_test "graph.js changed after stamping reports stale"

ROOT=$(make_fixture_root)
write_sidecar "$ROOT"
bash "$CHECK_SCRIPT" --stamp --root "$ROOT" > /dev/null
printf '\n' >> "$ROOT/.craft/graph/graph.js"

set +e
OUT=$(bash "$CHECK_SCRIPT" --check --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "exits 0" "0" "$RC"
assert_contains "VERDICT=stale" "VERDICT=stale" "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 4: no project reports missing and exits 0 ---
begin_test "no project reports missing and exits 0"

ROOT=$(mktemp -d)

set +e
OUT=$(bash "$CHECK_SCRIPT" --check --root "$ROOT" 2>&1)
RC=$?
STAMP_OUT=$(bash "$CHECK_SCRIPT" --stamp --root "$ROOT" 2>&1)
STAMP_RC=$?
set -e

assert_exit_code "check exits 0" "0" "$RC"
assert_contains "VERDICT=missing" "VERDICT=missing" "$OUT"
assert_exit_code "stamp exits 0" "0" "$STAMP_RC"
assert_contains "stamp declines with STAMPED=0" "STAMPED=0" "$STAMP_OUT"
assert_dir_not_exists "no .craft was created" "$ROOT/.craft"

rm -rf "$ROOT"
echo ""

# --- Test 5: a sidecar with no receipt reports stale ---
begin_test "a sidecar with no receipt reports stale"

ROOT=$(make_fixture_root)
write_sidecar "$ROOT"

set +e
OUT=$(bash "$CHECK_SCRIPT" --check --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "exits 0" "0" "$RC"
assert_contains "VERDICT=stale" "VERDICT=stale" "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 6: a rebuild does not remove the sidecar ---
begin_test "a rebuild does not remove the sidecar"

ROOT=$(mktemp -d)
cp -R "$CORPUS" "$ROOT/.craft"
mkdir -p "$ROOT/.craft/graph"
write_sidecar "$ROOT"
printf 'deadbeef\n' > "$ROOT/.craft/graph/.insights.sha256"

set +e
OUT=$(bash "$WRAPPER" --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "wrapper exits 0" "0" "$RC"
assert_contains "build succeeded" '"status": *"ok"' "$OUT"
assert_file_exists "graph.js written by the build" "$ROOT/.craft/graph/graph.js"
assert_file_exists "insights.js survives the rebuild" "$ROOT/.craft/graph/insights.js"
assert_file_exists "the receipt survives the rebuild" "$ROOT/.craft/graph/.insights.sha256"

rm -rf "$ROOT"
echo ""

finish_tests "test-dashboard-insights.sh"
