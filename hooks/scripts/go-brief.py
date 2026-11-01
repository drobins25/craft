#!/usr/bin/env python3
"""Read a copied Go into the pickup brief and say whether Craft answers its own prompts.

Usage: go-brief.py <go-file | cycle-dir>

A file is read as a copied Go. A directory is a cycle: its newest copied Go
is read, but only for a tracker cycle that recorded a Go (source_issue and
go_author set, stage plan, build or build and open the PR). Anything else
about a cycle is "none".

Output: exactly five lines, in order
  prompts=<answer|bring|none>
  scope_line=<the Go's first "Scope: " line, or empty>
  rules_line=<the Go's "Run rules: " line as written, "Run rules: none in this Go" when absent, or empty>
  questions_line=<Questions go to: the issue|here, or empty>
  answer_line=<the autonomy line when prompts=answer, else empty>

The prompts verdict is the last "Workflow prompts: answer them yourself." or
"Workflow prompts: bring them to me." anywhere in the Go, so a per-Go delta
placed after the copied rules overrides them. Neither phrase, no Go heading
or a hold Go gives "none" with the four brief values empty.

Errors (wrong arguments, an unreadable path, a directory without cycle.yaml)
exit 1 with one line on stderr and nothing on stdout. Never writes.
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from tracker_comments import read_key, slug  # noqa: E402

PHRASES = re.compile(
    r'Workflow prompts: (answer them yourself|bring them to me)\.')
SCOPE = re.compile(r'^Scope: \S.*$', re.MULTILINE)
RULES = re.compile(r'^Run rules: .*$', re.MULTILINE)
HEADING = '## Go - '
BUILD_STAGES = ('plan', 'build', 'build and open the PR')
QUESTIONS_HERE = 'Questions go to: here'
QUESTIONS_ISSUE = 'Questions go to: the issue'
QUESTIONS_PERMISSION = 'Questions and decisions: comments on this issue'
ANSWER_LINE = "I'll answer Craft's own prompts and stop only for product forks."
NO_RULES_LINE = 'Run rules: none in this Go'
KEYS = ('prompts', 'scope_line', 'rules_line', 'questions_line', 'answer_line')


class BriefError(Exception):
    """A condition that ends the run with one stderr line."""


def empty_brief():
    return dict.fromkeys(KEYS, '')


def read_text(path):
    try:
        with open(path, encoding='utf-8', newline='') as handle:
            return handle.read()
    except (OSError, UnicodeDecodeError) as err:
        raise BriefError('cannot read %s: %s' % (path, err))


def rules_line(text):
    match = RULES.search(text)
    if not match:
        return NO_RULES_LINE
    return match.group(0).rstrip()


def questions_line(text):
    """The issue only when a whole line of the Go grants it, else here.

    Posting to the tracker is a shared write, so the permission is the Go's own
    Questions line and nothing looser.
    """
    for line in text.split('\n'):
        line = line.rstrip()
        if line.endswith('.'):
            line = line[:-1]
        if line == QUESTIONS_PERMISSION:
            return QUESTIONS_ISSUE
    return QUESTIONS_HERE


def parse_go(text):
    """The brief for one copied Go; the "none" brief when there is nothing to read."""
    text = text.replace('\r', '')
    brief = dict(empty_brief(), prompts='none')
    first = next((line for line in text.split('\n') if line.strip()), '')
    if not first.startswith(HEADING):
        return brief
    if first[len(HEADING):].partition(' (')[0].strip() == 'hold':
        return brief
    found = PHRASES.findall(text)
    scope = SCOPE.search(text)
    brief.update(
        prompts={'answer them yourself': 'answer', 'bring them to me': 'bring'}[found[-1]]
        if found else 'none',
        scope_line=scope.group(0).rstrip() if scope else '',
        rules_line=rules_line(text),
        questions_line=questions_line(text))
    if brief['prompts'] == 'answer':
        brief['answer_line'] = ANSWER_LINE
    return brief


def newest_go_file(cycle_dir):
    """Path of the newest copied Go for the cycle's tracker issue, or None."""
    yaml_text = read_text(os.path.join(cycle_dir, 'cycle.yaml'))
    issue = read_key(yaml_text, 'source_issue')
    if (not issue or not read_key(yaml_text, 'go_author')
            or read_key(yaml_text, 'authorized_stage') not in BUILD_STAGES):
        return None
    pattern = os.path.join(glob.escape(os.path.join(cycle_dir, 'context')),
                           glob.escape(slug(issue)) + '-go-*.md')
    matches = sorted(glob.glob(pattern))
    return matches[-1] if matches else None


def brief_for(path):
    if os.path.isdir(path):
        if not os.path.isfile(os.path.join(path, 'cycle.yaml')):
            raise BriefError('no cycle.yaml in %s' % path)
        go_file = newest_go_file(path)
        if go_file is None:
            return dict(empty_brief(), prompts='none')
        return parse_go(read_text(go_file))
    if os.path.isfile(path):
        return parse_go(read_text(path))
    raise BriefError('%s is neither a file nor a directory' % path)


def main(argv):
    if len(argv) != 2:
        sys.stderr.write('Usage: go-brief.py <go-file | cycle-dir>\n')
        return 1
    try:
        brief = brief_for(argv[1])
    except BriefError as err:
        sys.stderr.write('go-brief.py: %s\n' % err)
        return 1
    for key in KEYS:
        sys.stdout.write('%s=%s\n' % (key, brief[key]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
