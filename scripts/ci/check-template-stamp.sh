#!/bin/bash
# check-template-stamp.sh — Guard: a diff that touches the dashboard template
# must also move its craft-template-version stamp.
#
# Story 6's pull offer only fires when the stamp value changes, so a template
# edit that ships without a bump silently strands every existing user on the
# old page. The guard is strict by design: a whitespace-only or comment-only
# edit still requires a bump - the cost of a false positive is one integer,
# the cost of a false negative is silent.
#
# Usage: check-template-stamp.sh --base <ref> --head <ref>
#
# Runs against the git repo in the current working directory (in CI, the
# checkout root). Uses `git show <ref>:<path>` rather than checking anything
# out, so it is safe against a dirty working tree.
#
# Exit codes:
#   0  template untouched by the diff, or touched with a changed stamp
#   1  template touched and the stamp value did not change
#   2  usage error, or the refs/files cannot be read at all

set -uo pipefail

WATCHED="scripts/dashboard/template/index.html"

usage() {
  echo "usage: check-template-stamp.sh --base <ref> --head <ref>"
}

BASE=""
HEAD_REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base)
      BASE="${2:-}"
      shift 2 || { usage; exit 2; }
      ;;
    --head)
      HEAD_REF="${2:-}"
      shift 2 || { usage; exit 2; }
      ;;
    *)
      echo "unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

if [ -z "$BASE" ] || [ -z "$HEAD_REF" ]; then
  usage
  exit 2
fi

# Mirrors extract_stamp in scripts/dashboard/dashboard-page.sh:72-88: first 10
# lines, capture the meta value, and anything that is not a plain non-negative
# integer reads as "none". Reads the file at a ref via `git show`; an absent
# file at that ref also reads as "none" (a PR that creates the template).
stamp_at_ref() {
  local ref="$1" content line value
  if ! content="$(git show "$ref:$WATCHED" 2>/dev/null)"; then
    printf 'none\n'
    return
  fi
  line="$(printf '%s\n' "$content" | head -10 | grep -o 'craft-template-version" content="[^"]*"' | head -1)"
  if [ -z "$line" ]; then
    printf 'none\n'
    return
  fi
  value="$(printf '%s' "$line" | sed -E 's/.*content="([^"]*)"/\1/')"
  case "$value" in
    ''|*[!0-9]*) printf 'none\n' ;;
    *) printf '%s\n' "$value" ;;
  esac
}

CHANGED="$(git diff --name-only "$BASE..$HEAD_REF" 2>&1)"
DIFF_RC=$?
if [ "$DIFF_RC" -ne 0 ]; then
  echo "ERROR: git diff --name-only $BASE..$HEAD_REF failed:"
  echo "$CHANGED"
  exit 2
fi

if ! printf '%s\n' "$CHANGED" | grep -qx "$WATCHED"; then
  echo "OK: diff does not touch $WATCHED"
  exit 0
fi

# Fail loudly rather than silently passing when neither side is readable -
# the diff says the file changed, so at least one ref must yield it.
if ! git show "$BASE:$WATCHED" > /dev/null 2>&1 && ! git show "$HEAD_REF:$WATCHED" > /dev/null 2>&1; then
  echo "ERROR: $WATCHED is listed in the diff but unreadable at both $BASE and $HEAD_REF"
  exit 2
fi

BASE_STAMP="$(stamp_at_ref "$BASE")"
HEAD_STAMP="$(stamp_at_ref "$HEAD_REF")"

if [ "$BASE_STAMP" = "$HEAD_STAMP" ]; then
  echo "FAIL: $WATCHED changed but craft-template-version is still '$BASE_STAMP'"
  echo "      Any edit to the template must bump the stamp, or story 6's pull"
  echo "      offer never fires and existing users stay on the old page."
  exit 1
fi

echo "OK: $WATCHED changed and craft-template-version moved ($BASE_STAMP -> $HEAD_STAMP)"
exit 0
