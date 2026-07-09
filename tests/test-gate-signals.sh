#!/bin/bash
# test-gate-signals.sh - fixture-driven coverage for the stack-signal probe.
#
# The scan contract (present-manifests-only, prune list, depth cap, counts not
# paths) and the reconcile-state contract (lookup/record roundtrip, one line
# per signal) are load-bearing for gate coverage reporting, so they are unit
# tested here rather than trusted.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

SIGNALS_SH="$SCRIPT_DIR/../hooks/scripts/gate-signals.sh"

echo "=== test-gate-signals.sh ==="
echo ""

new_root() {
  local tr
  tr=$(mktemp -d)
  mkdir -p "$tr/.craft"
  touch "$tr/.craft/.global-state"
  echo "$tr"
}

run_signals() {
  # <root> <args...> - invoke from within the fixture with the env override
  # cleared, so root resolution exercises the walk-up path.
  local root="$1"
  shift
  (cd "$root" && unset CRAFT_PROJECT_ROOT && bash "$SIGNALS_SH" "$@")
}

# --- scan: present manifests only ---
begin_test "scan reports present manifests only"
TR=$(new_root)
touch "$TR/package.json"
mkdir -p "$TR/backend"
touch "$TR/backend/App.csproj"
OUT=$(run_signals "$TR" scan)
assert_contains "package.json reported" "manifest package.json 1" "$OUT"
assert_contains "csproj reported" "manifest \*.csproj 1" "$OUT"
assert_not_contains "absent go.mod emits no line" "go.mod" "$OUT"
rm -rf "$TR"
echo ""

# --- scan: prune list ---
begin_test "scan excludes node_modules"
TR=$(new_root)
mkdir -p "$TR/node_modules/somepkg"
touch "$TR/node_modules/somepkg/package.json"
OUT=$(run_signals "$TR" scan)
assert_not_contains "vendored package.json not counted" "package.json" "$OUT"
rm -rf "$TR"
echo ""

# --- scan: depth cap ---
begin_test "scan caps depth at 3"
TR=$(new_root)
mkdir -p "$TR/a/b/c/d"
touch "$TR/a/b/c/d/go.mod"
OUT=$(run_signals "$TR" scan)
assert_not_contains "manifest deeper than the cap not counted" "go.mod" "$OUT"
rm -rf "$TR"
echo ""

# --- scan: counts, not paths ---
begin_test "scan emits counts, never file paths"
TR=$(new_root)
mkdir -p "$TR/frontend" "$TR/tools"
touch "$TR/package.json" "$TR/frontend/package.json" "$TR/tools/Makefile"
OUT=$(run_signals "$TR" scan)
assert_contains "package.json counted twice" "manifest package.json 2" "$OUT"
assert_contains "Makefile counted once" "manifest Makefile 1" "$OUT"
assert_not_contains "no path strings in output" "frontend" "$OUT"
rm -rf "$TR"
echo ""

# --- lookup: empty when unrecorded ---
begin_test "lookup prints empty and exits 0 when no record"
TR=$(new_root)
set +e
OUT=$(run_signals "$TR" lookup "*.csproj")
EXIT_CODE=$?
set -e
assert_eq "exit 0" "0" "$EXIT_CODE"
assert_eq "empty output" "" "$OUT"
rm -rf "$TR"
echo ""

# --- record + lookup roundtrip ---
begin_test "record then lookup roundtrips"
TR=$(new_root)
run_signals "$TR" record "*.csproj" declined
OUT=$(run_signals "$TR" lookup "*.csproj")
assert_eq "lookup returns recorded state" "declined" "$OUT"
assert_contains "state line carries a date stamp" "\*.csproj: declined $(date +%Y-%m-%d)" "$(cat "$TR/.craft/.gate-signals")"
rm -rf "$TR"
echo ""

# --- re-record replaces ---
begin_test "re-record replaces (one line per signal)"
TR=$(new_root)
run_signals "$TR" record "*.csproj" declined
run_signals "$TR" record "go.mod" declined
run_signals "$TR" record "*.csproj" wired
LINES=$(grep -c '^\*\.csproj: ' "$TR/.craft/.gate-signals")
assert_eq "exactly one line for the re-recorded signal" "1" "$LINES"
assert_eq "state updated to the latest record" "wired" "$(run_signals "$TR" lookup "*.csproj")"
assert_eq "other signals untouched" "declined" "$(run_signals "$TR" lookup "go.mod")"
rm -rf "$TR"
echo ""

# --- root scoping ---
begin_test "runs scoped to the invoking project dir"
TR=$(new_root)
run_signals "$TR" record "pyproject.toml" declined
assert_file_exists "state written under the fixture .craft" "$TR/.craft/.gate-signals"
rm -rf "$TR"
echo ""

finish_tests
