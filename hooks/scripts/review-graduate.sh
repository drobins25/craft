#!/bin/bash
# review-graduate.sh - Fill a finding's graduated_to: line in a review record
# Usage: review-graduate.sh <record path | record name> <N[,N...]> <value>
#          [--by=user|reviewer] [--reason="<text>"]
#   A review record is immutable after capture. This is the one edit allowed: the
#   graduated_to: line under each named finding, plus - on a dismissal - one
#   `dismissed: <by> - <reason>` line directly under it. Every other byte of the
#   file is preserved.
#
#   value is `docs`, `dismissed`, or the name of an existing craft artifact
#   (fix, tweak, bug, story or notebook todo). `dismissed` requires --by and
#   --reason; any other value refuses them. A comma list fills several findings
#   in one write, all or nothing.
#
# A problem prints one line to stderr and exits 2 with the record untouched.
# Output (stdout): the record's absolute path
# Exit: 0 on success, 2 on refusal, 1 when the record cannot be written

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "$CRAFT_PROJECT_ROOT" ]; then
  ROOT="${CRAFT_PROJECT_ROOT%/}"
else
  source "$SCRIPT_DIR/find-workshop.sh" >/dev/null 2>&1 || true
  if craft_refuse_monorepo_top "a review"; then exit 2; fi
  craft_before_init_root >/dev/null
  ROOT="$CRAFT_BEFORE_INIT_ROOT"
fi

POSITIONAL=()
BY=""
REASON=""
HAVE_BY=0
HAVE_REASON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --by=*) BY="${1#*=}"; HAVE_BY=1 ;;
    --reason=*) REASON="${1#*=}"; HAVE_REASON=1 ;;
    *) POSITIONAL+=("$1") ;;
  esac
  shift
done

if [ "${#POSITIONAL[@]}" -ne 3 ]; then
  echo "usage: review-graduate.sh <record path | record name> <N[,N...]> <value> [--by=user|reviewer] [--reason=<text>]" >&2
  exit 2
fi
TARGET="${POSITIONAL[0]}"
NUMBERS="${POSITIONAL[1]}"
VALUE="${POSITIONAL[2]}"

# A bare name resolves inside the reviews folder.
case "$TARGET" in
  */*|*.md) RECORD="$TARGET" ;;
  *) RECORD="$ROOT/.craft/reviews/$TARGET.md" ;;
esac
if [ ! -f "$RECORD" ]; then
  echo "no such record: $TARGET" >&2
  exit 2
fi
RECORD="$(cd "$(dirname "$RECORD")" && pwd)/$(basename "$RECORD")"

if ! [[ "$VALUE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "invalid value: $VALUE" >&2
  exit 2
fi

PROBLEMS=0
if [ "$VALUE" = "dismissed" ]; then
  if [ "$HAVE_BY" -eq 0 ] || [ -z "$BY" ]; then
    echo "missing required field: by" >&2; PROBLEMS=1
  elif [ "$BY" != "user" ] && [ "$BY" != "reviewer" ]; then
    echo "invalid by: $BY" >&2; PROBLEMS=1
  fi
  if [ "$HAVE_REASON" -eq 0 ] || [ -z "$(printf '%s' "$REASON" | tr -d '[:space:]')" ]; then
    echo "missing required field: reason" >&2; PROBLEMS=1
  elif [ "$(printf '%s' "$REASON" | wc -l | tr -d ' ')" -ne 0 ]; then
    echo "invalid reason: must be a single line" >&2; PROBLEMS=1
  fi
else
  if [ "$HAVE_BY" -eq 1 ]; then
    echo "invalid by: only a dismissal takes --by" >&2; PROBLEMS=1
  fi
  if [ "$HAVE_REASON" -eq 1 ]; then
    echo "invalid reason: only a dismissal takes --reason" >&2; PROBLEMS=1
  fi
  if [ "$VALUE" != "docs" ]; then
    # The value must name an artifact in one of the four doors' folders.
    FOUND=0
    CRAFT="$ROOT/.craft"
    for candidate in \
      "$CRAFT/fixes/$VALUE.md" "$CRAFT/tweaks/$VALUE.md" \
      "$CRAFT/bugs/$VALUE.md" "$CRAFT/bugs/closed/$VALUE.md" \
      "$CRAFT/backlog/$VALUE.md" \
      "$CRAFT"/cycles/*/stories/"$VALUE.md" "$CRAFT"/cycles/*/stories/*-"$VALUE.md" \
      "$CRAFT/notebook/todos/$VALUE.md" "$CRAFT/notebook/todos/done/$VALUE.md"; do
      if [ -f "$candidate" ]; then FOUND=1; break; fi
    done
    if [ "$FOUND" -eq 0 ]; then
      echo "no such artifact: $VALUE" >&2; PROBLEMS=1
    fi
  fi
fi
if [ "$PROBLEMS" -ne 0 ]; then
  exit 2
fi

TMP_FILE=$(mktemp "$(dirname "$RECORD")/.review-graduate.XXXXXX") || {
  echo "cannot write: $RECORD" >&2
  exit 1
}
trap 'rm -f "$TMP_FILE"' EXIT

python3 - "$RECORD" "$TMP_FILE" "$NUMBERS" "$VALUE" "$BY" "$REASON" <<'PYEOF'
import re
import sys

record_path, tmp_path, numbers, value, by, reason = sys.argv[1:7]

HEADING = re.compile(
    r'^### ([0-9]+)\. (?:(?:Issue|Suggestion|Pattern) )?'
    r'\((security|logic|performance|consistency|doc-drift)\): \S')
FENCE = re.compile(r'^ {0,3}(`{3,}|~{3,})')

wanted = []
problems = []
for part in numbers.split(','):
    if not re.fullmatch(r'[0-9]+', part):
        problems.append('invalid finding number: ' + part)
    elif int(part) not in wanted:
        wanted.append(int(part))

with open(record_path, encoding='utf-8', errors='surrogateescape', newline='') as f:
    text = f.read()
lines = text.split('\n')  # a trailing newline leaves a final empty element

# Headings outside fenced blocks and after the ## Findings line, by finding
# number - the same section rule capture applies, so a heading-shaped line in
# ## Verified is never taken for a finding.
headings = {}
marker = None
in_findings = False
for i, line in enumerate(lines):
    probe = line.rstrip('\r')
    m = FENCE.match(probe)
    if marker is None:
        if m:
            marker = m.group(1)
            continue
        if re.match(r'^## Findings[ \t]*$', probe):
            in_findings = True
            continue
        if not in_findings:
            continue
        h = HEADING.match(probe)
        if h:
            headings.setdefault(int(h.group(1)), i)
    elif m and m.group(1)[0] == marker[0] and len(m.group(1)) >= len(marker) \
            and not probe.strip()[len(m.group(1)):].strip():
        marker = None

edits = []  # (line index of graduated_to:, eol)
for n in wanted:
    if n not in headings:
        problems.append('unknown finding: %d' % n)
        continue
    at = headings[n] + 1
    current = lines[at] if at < len(lines) else ''
    if not current.rstrip('\r').startswith('graduated_to:'):
        problems.append('malformed finding: %d (no graduated_to line under its heading)' % n)
    elif current.rstrip('\r')[len('graduated_to:'):].strip():
        problems.append('already graduated: %d' % n)
    else:
        edits.append((at, '\r' if current.endswith('\r') else ''))

if problems:
    for p in problems:
        sys.stderr.write(p + '\n')
    sys.exit(2)

# Apply from the bottom so earlier indexes stay valid.
for at, eol in sorted(edits, reverse=True):
    lines[at] = 'graduated_to: ' + value + eol
    if value == 'dismissed':
        lines.insert(at + 1, 'dismissed: ' + by + ' - ' + reason.strip() + eol)

with open(tmp_path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
    f.write('\n'.join(lines))
PYEOF
RC=$?
if [ "$RC" -ne 0 ]; then
  exit "$RC"
fi

# Keep the record's mode, then swap it in whole.
chmod "$(stat -c '%a' "$RECORD" 2>/dev/null || stat -f '%Lp' "$RECORD")" "$TMP_FILE" 2>/dev/null || true
if ! mv "$TMP_FILE" "$RECORD"; then
  echo "cannot write: $RECORD" >&2
  exit 1
fi

echo "$RECORD"
