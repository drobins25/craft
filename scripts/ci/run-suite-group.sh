#!/bin/bash
# run-suite-group.sh — map the live test-file glob onto five named groups and
# run one group's members sequentially, naming the first failing file.
#
# Usage:
#   run-suite-group.sh <group>        run every member of <group>, fail fast
#   run-suite-group.sh --list-groups  print the five group names, one per line
#   run-suite-group.sh --list <group> print that group's member paths
#   run-suite-group.sh --list-all     print "<group> <path>" for every file
#
# The universe is computed at run time - tests/test-*.sh plus
# hooks/scripts/__tests__/*.test.sh, the exact glob tests/run-all.sh iterates.
# Never a stored list: a hardcoded manifest would itself drift, which is the
# exact bug this partition guards against (see scripts/check-doc-drift.sh's
# iron rule). Four groups match on filename prefix; `misc` is defined by
# subtraction, so every file is covered on the day it is added and no file
# can ever be silently skipped. tests/test-ci-suite-groups.sh proves the
# partition against the live glob.
#
# CRAFT_SUITE_ROOT overrides the repo root (used by the coverage test to
# exercise the failure path against a fixture tree).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CRAFT_SUITE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

GROUP_NAMES="dashboard hooks lifecycle flows misc"

usage() {
  echo "usage: run-suite-group.sh <group> | --list-groups | --list <group> | --list-all"
  echo "groups: $GROUP_NAMES"
}

# The group a single file belongs to. Path is repo-relative.
group_for() {
  case "$1" in
    hooks/scripts/__tests__/*.test.sh) echo "hooks"; return 0 ;;
  esac
  case "$(basename "$1")" in
    test-dashboard*) echo "dashboard" ;;
    test-create*|test-start*|test-complete*|test-move*|test-delete*|test-update*|\
    test-session*|test-append*|test-read-events*|test-event-log*|test-lifecycle*|\
    test-salvage*|test-statusline*|test-export*|test-find-workshop*|test-discover*|\
    test-inject*|test-stop-hook*|test-handle-tool*|test-aggregate*|test-gate-signals*|\
    test-check-write*|test-secret-deny*|test-push-gate*|test-triage-ledger*|test-fix-commit*)
      echo "lifecycle" ;;
    test-notebook*|test-dial*|test-riff*|test-mockup*|test-muse*|test-taste*|\
    test-tweak*|test-adhoc*|test-observations*|test-init*|test-merge-tokens*|\
    test-count-loved*|test-alignment*|test-mark-observations*)
      echo "flows" ;;
    *) echo "misc" ;;
  esac
}

# Every file in the universe, repo-relative, sorted.
universe() {
  (
    cd "$ROOT" || exit 1
    for f in tests/test-*.sh hooks/scripts/__tests__/*.test.sh; do
      [ -f "$f" ] && echo "$f"
    done
  ) | sort
}

is_group() {
  for g in $GROUP_NAMES; do
    [ "$g" = "$1" ] && return 0
  done
  return 1
}

list_group() {
  universe | while IFS= read -r f; do
    [ "$(group_for "$f")" = "$1" ] && echo "$f"
  done
  return 0
}

run_group() {
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo "running $f"
    ( cd "$ROOT" && bash "$f" )
    rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "FAIL: $f (exit $rc)"
      exit "$rc"
    fi
  done <<EOF
$(list_group "$1")
EOF
  echo "group '$1' passed"
}

case "${1:-}" in
  --list-groups)
    for g in $GROUP_NAMES; do echo "$g"; done
    ;;
  --list)
    if [ -z "${2:-}" ] || ! is_group "$2"; then
      usage; exit 2
    fi
    list_group "$2"
    ;;
  --list-all)
    universe | while IFS= read -r f; do
      echo "$(group_for "$f") $f"
    done
    ;;
  "")
    usage; exit 2
    ;;
  *)
    if ! is_group "$1"; then
      usage; exit 2
    fi
    run_group "$1"
    ;;
esac
