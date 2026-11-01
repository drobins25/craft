#!/usr/bin/env python3
"""Find the newest Go on a copied tracker issue and say how far work may go.

Usage: resolve-go.py <comments-file> <KEY> [<go-file>]

Comments-file grammar: optional preamble lines, then blocks. A block opens
with a line matching "## (Comment|Reply|Inline) <n> - <author> - <timestamp>"
(author is the greedy middle, timestamp is the tracker's own string). The
body is every line up to the next header, with leading and trailing blank
lines stripped. Only that strict header form opens a block, so a "## " line
inside a comment body never splits it.

A Go candidate is a Comment block whose first non-blank body line starts
with "## Go". Replies and inline comments are never candidates. A candidate
is valid when that line reads "## Go - <stage> (<name>, <Month D, YYYY>)",
the stage is plan, build, build and open the PR or hold, the date is a real
date and the header timestamp parses. Timestamps are parsed here, not with
datetime.fromisoformat, which rejects "Z" and "+0000" before Python 3.11.

The newest candidate wins (ties go to the later block). If it is not valid
the answer is "unreadable" and no older Go is consulted: an older build Go
must never override a newer, garbled hold. A candidate whose time cannot be
parsed cannot be ranked, so it counts as the newest.

Output: exactly six lines, in order
  go=<found|none|unreadable>
  stage=<stage; plan when the newest Go is unreadable; empty when there is no Go>
  go_author=<header author, or empty>
  go_date=<header timestamp verbatim, or empty>
  go_comment=<block number, or empty>
  stage_line=<the line to show the user>

With a <go-file> and go=found, the winning Go's body is written there
exactly as it sits in the comments file, plus one trailing newline.

Errors exit 1 with one line on stderr and nothing on stdout.
"""
import datetime
import re
import sys

HEADER = re.compile(r'^## (Comment|Reply|Inline) ([0-9]+) - (.+) - (\S+)$')
CANDIDATE = re.compile(r'^##\s+Go\b')
MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
          'August', 'September', 'October', 'November', 'December']
GO_LINE = re.compile(
    r'^## Go - (.+) \((.+), (' + '|'.join(MONTHS) + r') ([1-9][0-9]?), ([0-9]{4})\)\s*$')
STAGES = ('plan', 'build', 'build and open the PR', 'hold')
TIME = re.compile(
    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})'
    r'(?:\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})$')


def parse_time(text):
    """UTC datetime for a tracker timestamp, or None when it is not one."""
    m = TIME.match(text)
    if not m:
        return None
    year, month, day, hour, minute, second = (int(g) for g in m.groups()[:6])
    zone = m.group(7)
    offset = datetime.timedelta(0)
    if zone != 'Z':
        digits = zone[1:].replace(':', '')
        offset = datetime.timedelta(hours=int(digits[:2]), minutes=int(digits[2:]))
        if zone[0] == '-':
            offset = -offset
    try:
        local = datetime.datetime(year, month, day, hour, minute, second)
    except ValueError:
        return None
    return local - offset


def parse_blocks(text):
    """Blocks as dicts: kind, number, author, stamp, lines (blank edges cut)."""
    blocks = []
    for line in text.split('\n'):
        m = HEADER.match(line)
        if m:
            blocks.append({'kind': m.group(1), 'number': m.group(2),
                           'author': m.group(3), 'stamp': m.group(4), 'lines': []})
        elif blocks:
            blocks[-1]['lines'].append(line)
    for block in blocks:
        lines = block['lines']
        while lines and not lines[0].strip():
            lines.pop(0)
        while lines and not lines[-1].strip():
            lines.pop()
    return blocks


def read_go(block):
    """(stage, name, month, day) when the block is a valid Go, else None."""
    if parse_time(block['stamp']) is None:
        return None
    m = GO_LINE.match(block['lines'][0])
    if not m or m.group(1) not in STAGES:
        return None
    try:
        datetime.date(int(m.group(5)), MONTHS.index(m.group(3)) + 1, int(m.group(4)))
    except ValueError:
        return None
    return m.group(1), m.group(2), m.group(3), m.group(4)


def newest_candidate(blocks):
    """The candidate that outranks all others; unrankable times outrank all."""
    candidates = [b for b in blocks
                  if b['kind'] == 'Comment' and b['lines'] and CANDIDATE.match(b['lines'][0])]
    newest = None
    newest_time = None
    for block in candidates:
        when = parse_time(block['stamp'])
        if when is None:
            newest, newest_time = block, None
        elif newest is None or (newest_time is not None and when >= newest_time):
            newest, newest_time = block, when
    return newest


def resolve(text, key):
    """(result lines as a dict, go body lines or None)."""
    none = {'go': 'none', 'stage': '', 'go_author': '', 'go_date': '',
            'go_comment': '',
            'stage_line': 'No Go on %s, so craft works as usual: you decide when to build.' % key}
    winner = newest_candidate(parse_blocks(text))
    if winner is None:
        return none, None
    parsed = read_go(winner)
    if parsed is None:
        result = dict(none, go='unreadable', stage='plan', go_comment=winner['number'],
                      stage_line="The newest Go on %s (comment %s) doesn't follow the Go format, "
                                 "so this run plans only." % (key, winner['number']))
        return result, None
    stage, name, month, day = parsed
    result = {'go': 'found', 'stage': stage, 'go_author': winner['author'],
              'go_date': winner['stamp'], 'go_comment': winner['number'],
              'stage_line': 'Stage: %s, per Go from %s on %s %s.' % (stage, name, month[:3], day)}
    return result, winner['lines']


def main(argv):
    if len(argv) not in (3, 4) or not argv[2]:
        sys.stderr.write('Usage: resolve-go.py <comments-file> <KEY> [<go-file>]\n')
        return 1
    try:
        with open(argv[1], encoding='utf-8', newline='') as handle:
            text = handle.read()
    except (OSError, UnicodeDecodeError) as err:
        sys.stderr.write('resolve-go.py: cannot read %s: %s\n' % (argv[1], err))
        return 1
    result, body = resolve(text, argv[2])
    if len(argv) == 4 and body is not None:
        try:
            with open(argv[3], 'w', encoding='utf-8', newline='') as out:
                out.write('\n'.join(body) + '\n')
        except OSError as err:
            sys.stderr.write('resolve-go.py: cannot write %s: %s\n' % (argv[3], err))
            return 1
    for name in ('go', 'stage', 'go_author', 'go_date', 'go_comment', 'stage_line'):
        sys.stdout.write('%s=%s\n' % (name, result[name]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
