#!/bin/bash
# dials-capture.sh - Write a .craft/dials/ record for a completed dial session
# Usage: dials-capture.sh "<slug-text>" --surface=<s> --kind=<k> --scope=<magnitude|approach> \
#          --outcome=<nothing|tweak|story|todo> [--offered="<letters>"] [--chose=<letter|none>] \
#          [--passed="<letters>"] [--graduated-to=<ref>] [--source=<s>] [--reaction="<verbatim>"]
#
# surface and kind reuse the tweak-record vocabulary: they are the join key that
# lets a future pass cluster dial records against .craft/tweaks/ ("five sessions
# on settings-toolbar"). kind is validated at write time so the join key can
# never drift into free text.
#
# A dial record is born closed: no status, no attempts, no lifecycle of any
# kind. A session that ended in "keep the current value" is as complete as one
# that graduated to a tweak - the record is the value, not a work item.
#
# graduated_to records graduation intent - the artifact the session handed off
# to (same vocabulary as mockup and notebook records). It is not a shipped
# confirmation: the destination artifact's own status is the truth of what
# actually landed. Empty means the exit produced no artifact (outcome: nothing,
# a cold session, or a failed exit script).
#
# Every frontmatter key is written unconditionally (empty when unsupplied),
# so consumers can rely on the full key set being present on every record.
#
# Output (stdout): the full path to the written file
# Exit: 0 on success, non-zero on error (validation fails before any write)

set -e

# Resolve project root (same ladder as notebook-capture.sh)
if [ -n "$CRAFT_PROJECT_ROOT" ]; then
  ROOT="${CRAFT_PROJECT_ROOT%/}"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/find-workshop.sh" 2>/dev/null || true
  ROOT="${PROJECT_ROOT%/}"
fi

# Cold fallback: anchor to the git toplevel (never a subdirectory), else PWD.
# An orphaned capture must be loud - nothing recalls it until /craft:init runs.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -z "$ROOT" ]; then
    ROOT="$PWD"
    echo "not a git repo - capturing to $ROOT/.craft/dials/ (local to this directory)" >&2
  fi
fi

# Parse arguments
TEXT=""
SURFACE=""
KIND=""
SCOPE=""
OFFERED=""
CHOSE=""
PASSED=""
OUTCOME=""
GRADUATED_TO=""
SOURCE="dial"
REACTION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --surface=*)     SURFACE="${1#*=}"; shift ;;
    --kind=*)        KIND="${1#*=}"; shift ;;
    --scope=*)       SCOPE="${1#*=}"; shift ;;
    --offered=*)     OFFERED="${1#*=}"; shift ;;
    --chose=*)       CHOSE="${1#*=}"; shift ;;
    --passed=*)      PASSED="${1#*=}"; shift ;;
    --outcome=*)     OUTCOME="${1#*=}"; shift ;;
    --graduated-to=*) GRADUATED_TO="${1#*=}"; shift ;;
    --source=*)      SOURCE="${1#*=}"; shift ;;
    --reaction=*)    REACTION="${1#*=}"; shift ;;
    *)
      if [ -z "$TEXT" ]; then
        TEXT="$1"
      fi
      shift
      ;;
  esac
done

# Validate - all checks run before any mkdir or file write
if [ -z "$TEXT" ]; then
  echo "Error: slug text is required" >&2
  exit 1
fi

if [ -z "$SURFACE" ]; then
  echo "Error: --surface is required" >&2
  exit 1
fi

case "$KIND" in
  icon|copy|spacing|size|color|motion|content) ;;
  *)
    echo "Error: kind must be one of icon|copy|spacing|size|color|motion|content" >&2
    exit 1
    ;;
esac

case "$SCOPE" in
  magnitude|approach) ;;
  *)
    echo "Error: scope must be one of magnitude|approach" >&2
    exit 1
    ;;
esac

case "$OUTCOME" in
  nothing|tweak|story|todo) ;;
  *)
    echo "Error: outcome must be one of nothing|tweak|story|todo" >&2
    exit 1
    ;;
esac

# ── Slug generation (mirrors notebook-capture.sh) ────────────────────
DATE=$(date +%Y-%m-%d)

RAW_SLUG=$(printf '%s' "$TEXT" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g' \
  | sed -E 's/^-//' \
  | sed -E 's/-$//')

# Cap at 50 chars (word-boundary-friendly: cut at last hyphen <=50 if possible)
if [ ${#RAW_SLUG} -gt 50 ]; then
  TRUNC="${RAW_SLUG:0:50}"
  LAST_HYPHEN_TRUNC="${TRUNC%-*}"
  if [ -n "$LAST_HYPHEN_TRUNC" ] && [ "$LAST_HYPHEN_TRUNC" != "$TRUNC" ] && [ ${#LAST_HYPHEN_TRUNC} -ge 20 ]; then
    SLUG="$LAST_HYPHEN_TRUNC"
  else
    SLUG="$TRUNC"
  fi
else
  SLUG="$RAW_SLUG"
fi

if [ -z "$SLUG" ]; then
  SLUG="untitled"
fi

# ── Folder creation (on demand - dial has one record type, no subfolders) ──
DIALS_DIR="$ROOT/.craft/dials"
mkdir -p "$DIALS_DIR"

# ── Collision resolution ─────────────────────────────────────────────
FINAL_SLUG="$SLUG"
TARGET_FILE="$DIALS_DIR/${DATE}-${FINAL_SLUG}.md"
COUNTER=2
while [ -e "$TARGET_FILE" ]; do
  FINAL_SLUG="${SLUG}-${COUNTER}"
  TARGET_FILE="$DIALS_DIR/${DATE}-${FINAL_SLUG}.md"
  COUNTER=$((COUNTER + 1))
done

# ── Write file - every key unconditional, empty values written as empty ──
{
  echo "---"
  echo "source: $SOURCE"
  echo "slug: $FINAL_SLUG"
  echo "created: $DATE"
  echo "surface: $SURFACE"
  echo "kind: $KIND"
  echo "scope: $SCOPE"
  echo "offered: $OFFERED"
  echo "chose: $CHOSE"
  echo "passed: $PASSED"
  echo "outcome: $OUTCOME"
  echo "graduated_to: $GRADUATED_TO"
  echo "---"
  if [ -n "$REACTION" ]; then
    echo ""
    echo "$REACTION"
  fi
} > "$TARGET_FILE"

echo "$TARGET_FILE"
