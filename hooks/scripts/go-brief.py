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
  rules_line=<the run rules header, reworded, or empty>
  questions_line=<Questions go to: here, or empty>
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

PHRASES = re.compile(
    r'Workflow prompts: (answer them yourself|bring them to me)\.')
SCOPE = re.compile(r'^Scope: \S.*$', re.MULTILINE)
RULES = re.compile(r'^Run rules: .*$', re.MULTILINE)
RULES_UPDATED = re.compile(r'^Run rules: last updated (.+) \(from your (.+)\)$')
HEADING = '## Go - '
BUILD_STAGES = ('plan', 'build', 'build and open the PR')
QUESTIONS_LINE = 'Questions go to: here'
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
    line = match.group(0).rstrip()
    updated = RULES_UPDATED.match(line)
    if updated:
        return 'Run rules: %s, last updated %s' % (updated.group(2), updated.group(1))
    return line


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
        questions_line=QUESTIONS_LINE)
    if brief['prompts'] == 'answer':
        brief['answer_line'] = ANSWER_LINE
    return brief


def read_key(yaml_text, key):
    """A flat top-level key written as a one-line single-quoted scalar."""
    match = re.search(r'^%s:[ \t]*(.*?)[ \t]*$' % re.escape(key), yaml_text, re.MULTILINE)
    if not match:
        return ''
    value = match.group(1)
    quoted = re.match(r"^'(.*)'$", value)
    if quoted:
        value = quoted.group(1)
    return value.replace("''", "'")


def newest_go_file(cycle_dir):
    """Path of the newest copied Go for the cycle's tracker issue, or None."""
    yaml_text = read_text(os.path.join(cycle_dir, 'cycle.yaml'))
    issue = read_key(yaml_text, 'source_issue')
    if (not issue or not read_key(yaml_text, 'go_author')
            or read_key(yaml_text, 'authorized_stage') not in BUILD_STAGES):
        return None
    slug = re.sub(r'[^a-z0-9]+', '-', issue.lower())
    pattern = os.path.join(glob.escape(os.path.join(cycle_dir, 'context')),
                           glob.escape(slug) + '-go-*.md')
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
