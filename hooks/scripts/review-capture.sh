#!/bin/bash
# review-capture.sh - Write one review record into .craft/reviews
# Usage: review-capture.sh --mode=branch|story|project --strategy=standard|maze
#          --reviewed="<branch name | story name | audited path>"
#          --ref="<base7>..<head7> | <head7>" --focus="<csv>" --files=<N>
#          [--lines=<N>] --reviewer="<agent name[, agent name]>"
#          --gates="<what ran - result | none | not reported>"
#          [--craft-version=<X>] --stdin
#   The body arrives on stdin: a `## Verified` list, then `## Findings` holding
#   either `None.` or findings under `### N. (<category>): <title>` headings,
#   numbered 1..N. Capture derives the file name, craft version, the findings
#   count and outcome, and stamps a blank `graduated_to:` line under every
#   finding heading, whatever its category.
#   --lines is required for branch and story runs and refused for project runs.
#
# A problem prints `missing required field: <name>` or `invalid <thing>: <value>`
# to stderr (one line each) and exits 2 with nothing written - no file and no
# directory.
#
# Output (stdout): the absolute path of the written record as the last line
# Exit: 0 on success, 2 on refusal, 1 when the record cannot be written

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "$CRAFT_PROJECT_ROOT" ]; then
  ROOT="${CRAFT_PROJECT_ROOT%/}"
else
  source "$SCRIPT_DIR/find-workshop.sh" >/dev/null 2>&1 || true
  # A monorepo's top level is no project: refuse before anything is read or written.
  if craft_refuse_monorepo_top "a review"; then exit 2; fi
  craft_before_init_root >/dev/null
  ROOT="$CRAFT_BEFORE_INIT_ROOT"
fi

MODE=""
STRATEGY=""
REVIEWED=""
REF=""
FOCUS=""
FILES=""
LINES=""
REVIEWER=""
GATES=""
CRAFT_VERSION_OVERRIDE=""
HAVE_STDIN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mode=*) MODE="${1#*=}" ;;
    --strategy=*) STRATEGY="${1#*=}" ;;
    --reviewed=*) REVIEWED="${1#*=}" ;;
    --ref=*) REF="${1#*=}" ;;
    --focus=*) FOCUS="${1#*=}" ;;
    --files=*) FILES="${1#*=}" ;;
    --lines=*) LINES="${1#*=}" ;;
    --reviewer=*) REVIEWER="${1#*=}" ;;
    --gates=*) GATES="${1#*=}" ;;
    --craft-version=*) CRAFT_VERSION_OVERRIDE="${1#*=}" ;;
    --stdin) HAVE_STDIN=1 ;;
  esac
  shift
done

if [ "$HAVE_STDIN" -ne 1 ]; then
  echo "missing flag: --stdin (the body arrives on stdin)" >&2
  exit 2
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cat > "$WORK_DIR/body.txt"

DATE=$(date +%Y-%m-%d)
CAPTURED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Craft version: the override wins, else plugin.json (installed copy first, then
# this script's own plugin), else unknown.
CRAFT_VERSION="$CRAFT_VERSION_OVERRIDE"
if [ -z "$CRAFT_VERSION" ]; then
  PLUGIN_JSON=""
  if [ -n "$CLAUDE_PLUGIN_ROOT" ] && [ -f "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" ]; then
    PLUGIN_JSON="$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
  elif [ -f "$SCRIPT_DIR/../../.claude-plugin/plugin.json" ]; then
    PLUGIN_JSON="$SCRIPT_DIR/../../.claude-plugin/plugin.json"
  fi
  if [ -n "$PLUGIN_JSON" ]; then
    CRAFT_VERSION=$(grep '"version"' "$PLUGIN_JSON" 2>/dev/null | head -1 \
      | sed -E 's/.*"version": *"([^"]+)".*/\1/' || true)
  fi
fi
[ -n "$CRAFT_VERSION" ] || CRAFT_VERSION="unknown"

# Validate and assemble in one pass; nothing touches the project until it
# succeeds. The file-name slug comes back through a file.
python3 - "$WORK_DIR/body.txt" "$WORK_DIR/record.md" "$WORK_DIR/slug.txt" \
  "$DATE" "$CAPTURED_AT" "$MODE" "$STRATEGY" "$REVIEWED" "$REF" "$FOCUS" \
  "$FILES" "$LINES" "$CRAFT_VERSION" "$REVIEWER" "$GATES" <<'PYEOF'
import re
import sys

(body_path, out_path, slug_path, date, captured_at, mode, strategy, reviewed,
 ref, focus, files, lines_flag, craft_version, reviewer, gates) = sys.argv[1:16]

HEADING = re.compile(
    r'^### ([0-9]+)\. '
    r'\((security|logic|performance|consistency|doc-drift)\): \S')
FENCE = re.compile(r'^ {0,3}(`{3,}|~{3,})')

problems = []


def one_line(text):
    return re.sub(r'\s+', ' ', text).strip()


# ── Flags ─────────────────────────────────────────────────────────────
if mode not in ('', 'branch', 'story', 'project'):
    problems.append('invalid mode: ' + mode)
if strategy not in ('', 'standard', 'maze'):
    problems.append('invalid strategy: ' + strategy)
for name, value in (('mode', mode), ('strategy', strategy), ('ref', ref),
                    ('focus', focus), ('files', files), ('reviewer', reviewer),
                    ('gates', gates)):
    if not one_line(value):
        problems.append('missing required field: ' + name)
if mode != 'project' and not one_line(reviewed):
    problems.append('missing required field: reviewed')
if files and not re.fullmatch(r'[0-9]+', files):
    problems.append('invalid files: ' + files)
if mode in ('branch', 'story'):
    if not lines_flag:
        problems.append('missing required field: lines')
    elif not re.fullmatch(r'[0-9]+', lines_flag):
        problems.append('invalid lines: ' + lines_flag)
elif mode == 'project' and lines_flag:
    problems.append('invalid lines: ' + lines_flag + ' (project mode records no line count)')

# ── Body ──────────────────────────────────────────────────────────────
with open(body_path, encoding='utf-8', errors='replace', newline='') as f:
    raw = f.read()

body_lines = raw.replace('\r\n', '\n').split('\n')
while body_lines and not body_lines[0].strip():
    body_lines.pop(0)
while body_lines and not body_lines[-1].strip():
    body_lines.pop()

# Mark every line that sits inside a fenced block (fence lines included) so a
# quoted diff never counts as a heading or a stamped line.
in_fence = []
marker = None
for line in body_lines:
    m = FENCE.match(line)
    if marker is None:
        if m:
            marker = m.group(1)
            in_fence.append(True)
        else:
            in_fence.append(False)
    else:
        in_fence.append(True)
        if m and m.group(1)[0] == marker[0] and len(m.group(1)) >= len(marker) \
                and not line.strip()[len(m.group(1)):].strip():
            marker = None


def find_heading(name):
    for i, line in enumerate(body_lines):
        if not in_fence[i] and re.match(r'^## ' + re.escape(name) + r'[ \t]*$', line):
            return i
    return None


verified_at = find_heading('Verified')
findings_at = find_heading('Findings')

if verified_at is None:
    problems.append('missing required field: Verified')
else:
    end = next((j for j in range(verified_at + 1, len(body_lines))
                if not in_fence[j] and body_lines[j].startswith('## ')), len(body_lines))
    if not any(l.strip() for l in body_lines[verified_at + 1:end]):
        problems.append('missing required field: Verified')

if findings_at is None:
    problems.append('missing required field: Findings')

for i, line in enumerate(body_lines):
    if not in_fence[i] and line.startswith('graduated_to:'):
        problems.append('invalid body: graduated_to line (capture stamps it)')
        break

findings = []  # (line index, number)
if findings_at is not None:
    for i in range(findings_at + 1, len(body_lines)):
        line = body_lines[i]
        if in_fence[i] or not line.startswith('### '):
            continue
        m = HEADING.match(line)
        if not m:
            problems.append('invalid finding heading: ' + line)
            continue
        findings.append((i, int(m.group(1))))
    for position, (_, number) in enumerate(findings, start=1):
        if number != position:
            problems.append('invalid finding number: %d (expected %d)' % (number, position))
            break
    if not findings and not problems:
        section = [l for l in body_lines[findings_at + 1:] if l.strip()]
        if section != ['None.']:
            problems.append('invalid Findings: expected None. when there are no findings')

if problems:
    for p in problems:
        sys.stderr.write(p + '\n')
    sys.exit(2)

# ── Assemble ──────────────────────────────────────────────────────────
stamps = {i: 'graduated_to:' for i, _ in findings}
out_body = []
for i, line in enumerate(body_lines):
    out_body.append(line)
    if i in stamps:
        out_body.append(stamps[i])

def field(key, value):
    value = one_line(value)
    return key + ':' + (' ' + value if value else '')


front = [
    '---',
    'type: review',
    'created: ' + date,
    'captured_at: ' + captured_at,
    'mode: ' + mode,
    'strategy: ' + strategy,
    field('reviewed', reviewed),
    field('ref', ref),
    field('focus', focus),
    'files: ' + files,
]
if mode != 'project':
    front.append('lines: ' + lines_flag)
front += [
    field('craft_version', craft_version),
    field('reviewer', reviewer),
    field('gates', gates),
    'findings: %d' % len(findings),
    'outcome: ' + ('findings' if findings else 'clean'),
    '---',
    '',
]

with open(out_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(front) + '\n'.join(out_body) + '\n')

# ── Slug: <mode>-<reviewed> through the notebook slug rule ────────────
if mode == 'project' and reviewed.strip() in ('', '.'):
    slug = 'project'
else:
    slug = re.sub(r'[^a-z0-9]+', '-', (mode + '-' + reviewed).lower()).strip('-')
    if len(slug) > 50:
        trunc = slug[:50]
        cut = trunc.rsplit('-', 1)[0]
        slug = cut if cut != trunc and len(cut) >= 20 else trunc
with open(slug_path, 'w', encoding='utf-8') as f:
    f.write(slug)
PYEOF
RC=$?
if [ "$RC" -ne 0 ]; then
  exit "$RC"
fi

SLUG=$(cat "$WORK_DIR/slug.txt")

# ── Folder on demand, collision suffix ────────────────────────────────
TARGET_DIR="$ROOT/.craft/reviews"
mkdir -p "$TARGET_DIR"

# Create the file with noclobber (an exclusive open), so two runs racing for the
# same name never overwrite each other: the loser bumps the suffix and retries.
TARGET_FILE="$TARGET_DIR/${DATE}-${SLUG}.md"
COUNTER=2
until ( set -C; cat "$WORK_DIR/record.md" > "$TARGET_FILE" ) 2>/dev/null; do
  if [ ! -e "$TARGET_FILE" ]; then
    echo "cannot write: $TARGET_FILE" >&2
    exit 1
  fi
  TARGET_FILE="$TARGET_DIR/${DATE}-${SLUG}-${COUNTER}.md"
  COUNTER=$((COUNTER + 1))
done

echo "$TARGET_FILE"
