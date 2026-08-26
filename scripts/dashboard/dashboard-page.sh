#!/usr/bin/env bash
# dashboard-page.sh - the version and hand-edit guard sitting in front of the
# user's copied dashboard page. `--check` answers two independent questions:
# which stamp does the user's copy carry against the one shipped with this
# plugin, and did anything touch the copy since the last pull. `--pull`
# delivers a new copy without ever destroying the old one silently: a prior
# page always moves to a one-generation-deep backup before the shipped
# template lands, edited or not, because detection alone can't cover a
# pre-existing copy that never got a sidecar in the first place.
#
# Both modes exit 0 on every path - a version check or a page delivery must
# never be the thing that blocks a craft flow.

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SELF_DIR/template/index.html"
FRESHNESS="$SELF_DIR/../map/map-freshness.sh"

MODE=""
ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--pull)
      MODE="${1#--}"
      shift
      ;;
    --root)
      ROOT="${2:-}"
      shift 2 || shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ -z "$ROOT" ]; then
  if [ -n "${CRAFT_PROJECT_ROOT:-}" ]; then
    ROOT="$CRAFT_PROJECT_ROOT"
  else
    PROJECT_ROOT=""
    # shellcheck disable=SC1091
    source "$SELF_DIR/../../hooks/scripts/find-workshop.sh" 2>/dev/null || true
    ROOT="${PROJECT_ROOT:-}"
  fi
fi

# A relative --root (e.g. "." from a caller's cwd) would otherwise leak into
# PAGE and print as a relative file:// link with no meaning outside that
# caller's shell. Resolve to absolute here so every consumer of PAGE gets a
# path that works regardless of where it's read from.
case "$ROOT" in
  /*) ;;
  *)
    ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || ROOT=""
    ;;
esac

PAGE="$ROOT/.craft/dashboard.html"
SIDECAR="$ROOT/.craft/graph/.dashboard.sha256"

has_project() {
  [ -n "$ROOT" ] && [ -d "$ROOT/.craft" ]
}

# Reads the craft-template-version meta line from the first 10 lines of a
# file. Prints "none" when the file is unreadable, the meta line is absent,
# or the captured value is not a plain non-negative integer - the same
# extraction runs against the shipped template and the user's copy, so a
# malformed shipped file would degrade exactly the way a malformed copy does.
extract_stamp() {
  local target="$1" line value
  line="$(head -10 "$target" 2>/dev/null | grep -o 'craft-template-version" content="[^"]*"' | head -1)"
  if [ -z "$line" ]; then
    printf 'none\n'
    return
  fi
  value="$(printf '%s' "$line" | sed -E 's/.*content="([^"]*)"/\1/')"
  case "$value" in
    ''|*[!0-9]*)
      printf 'none\n'
      ;;
    *)
      printf '%s\n' "$value"
      ;;
  esac
}

# Verdict for whether the user's copy still matches what was last delivered.
# The sidecar checksum is the only possible detector once stamps diverge -
# the old shipped template is gone by then, but the receipt of what we
# handed the user survives beside the graph data.
compute_copy_verdict() {
  if [ ! -f "$SIDECAR" ]; then
    printf 'unknown\n'
    return
  fi
  local expected verdict
  expected="$(tr -d '[:space:]' < "$SIDECAR" 2>/dev/null)"
  if [ -z "$expected" ]; then
    printf 'unknown\n'
    return
  fi
  verdict="$(bash "$FRESHNESS" "$PAGE" "$expected")"
  case "$verdict" in
    fresh) printf 'pristine\n' ;;
    stale) printf 'edited\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

do_check() {
  local shipped_stamp user_stamp state copy

  shipped_stamp="$(extract_stamp "$TEMPLATE")"

  if ! has_project; then
    state="no-project"
    user_stamp="none"
    copy="unknown"
  elif [ ! -f "$PAGE" ]; then
    state="missing"
    user_stamp="none"
    copy="unknown"
  else
    user_stamp="$(extract_stamp "$PAGE")"
    if [ "$user_stamp" = "none" ]; then
      # An unreadable stamp is offered, never silently pulled - `missing`
      # would route into the silent-pull branch and eat a hand-mangled copy.
      state="behind"
    elif [ "$shipped_stamp" != "none" ] && [ "$shipped_stamp" -gt "$user_stamp" ]; then
      state="behind"
    else
      state="current"
    fi
    copy="$(compute_copy_verdict)"
  fi

  printf 'ROOT=%s\n' "$ROOT"
  printf 'PAGE=%s\n' "$PAGE"
  printf 'SHIPPED_STAMP=%s\n' "$shipped_stamp"
  printf 'USER_STAMP=%s\n' "$user_stamp"
  printf 'STATE=%s\n' "$state"
  printf 'COPY=%s\n' "$copy"
  exit 0
}

fail_pull() {
  printf 'PULLED=0\n'
  printf 'REASON=%s\n' "$1"
  exit 0
}

do_pull() {
  has_project || fail_pull "no-project"
  [ -f "$TEMPLATE" ] || fail_pull "template-missing"

  local backup="none"
  if [ -f "$PAGE" ]; then
    backup="$ROOT/.craft/dashboard-backup.html"
    mv "$PAGE" "$backup" 2>/dev/null || fail_pull "copy-failed"
  fi

  cp "$TEMPLATE" "$PAGE" 2>/dev/null || fail_pull "copy-failed"

  mkdir -p "$ROOT/.craft/graph" 2>/dev/null || fail_pull "copy-failed"
  local hash
  hash="$(bash "$FRESHNESS" "$PAGE")"
  printf '%s\n' "$hash" > "$SIDECAR" 2>/dev/null || fail_pull "copy-failed"

  printf 'PULLED=1\n'
  printf 'PAGE=%s\n' "$PAGE"
  printf 'BACKUP=%s\n' "$backup"
  exit 0
}

case "$MODE" in
  check) do_check ;;
  pull) do_pull ;;
  *)
    printf 'PULLED=0\n'
    printf 'REASON=no-mode\n'
    exit 0
    ;;
esac
