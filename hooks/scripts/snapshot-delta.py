#!/usr/bin/env python3
"""Copy only what changed on a tracker issue since the cycle's last copy.

Usage: snapshot-delta.py <cycle-dir> <staged-comments-file>
                         [--issue <staged-issue-file>] --tool <text>
                         [--now <YYYY-MM-DDTHH:MM:SSZ>]

The staged files are a fresh full read of the issue, in the same grammar the
first copy used. Earlier copies in <cycle-dir>/context are never rewritten:
every file this writes is new, created exclusively.

A staged comment is new when its time is later than the latest time in every
earlier comments copy. A comment whose time equals that latest time, or is not
a time at all, is new only when no earlier copy has its exact header (kind,
author, timestamp). New comments keep their order and are numbered on from the
earlier maximum, so each comment keeps one number for life. Comments edited or
deleted on the tracker after being copied are not detected.

The staged issue is copied only when it differs from the newest earlier issue
copy once the "Status at retrieval:" line is dropped from both: status is
never authority, so a status-only change is not a change.

Output: exactly five lines, in order
  comments_file=<path written, or empty>
  new_comments=<count>
  issue_file=<path written, or empty>
  stamp=<stamp the new files carry, or empty when nothing was written>
  say=<the line to show the user>

Each written file adds one row to context/README.md after its table's last
line. Exit 1, with one line on stderr and nothing written, when the cycle has
no cycle.yaml or no source_issue, when context/README.md is missing or has no
table, or when an input cannot be read.
"""
import datetime
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from annotate_write import write_atomic  # noqa: E402
from tracker_comments import (  # noqa: E402
    newest_stamp, next_stamp, parse_blocks, read_key, slug, stamp_time)

MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
STATUS_LINE = 'Status at retrieval:'
NOW_FORMAT = '%Y-%m-%dT%H:%M:%SZ'


class RefreshError(Exception):
    pass


def read_text(path):
    try:
        with open(path, encoding='utf-8', newline='') as handle:
            return handle.read()
    except (OSError, UnicodeDecodeError) as err:
        raise RefreshError('cannot read %s: %s' % (path, err))


def parse_args(argv):
    """(cycle_dir, comments_file, issue_file or None, tool, now)."""
    positional = []
    options = {}
    args = list(argv[1:])
    while args:
        arg = args.pop(0)
        if arg in ('--issue', '--tool', '--now'):
            if not args:
                raise RefreshError('%s needs a value' % arg)
            options[arg] = args.pop(0)
        elif arg.startswith('--'):
            raise RefreshError('unknown option %s' % arg)
        else:
            positional.append(arg)
    if len(positional) != 2 or not options.get('--tool'):
        raise RefreshError('Usage: snapshot-delta.py <cycle-dir> <staged-comments-file> '
                           '[--issue <staged-issue-file>] --tool <text> [--now <time>]')
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    if '--now' in options:
        try:
            now = datetime.datetime.strptime(options['--now'], NOW_FORMAT)
        except ValueError:
            raise RefreshError('--now must look like 2026-10-31T18:40:00Z')
    return positional[0], positional[1], options.get('--issue'), options['--tool'], now


def new_blocks(staged, earlier):
    """The staged blocks created after everything in the earlier copies.

    A block timestamped before the latest earlier time is never new: it was
    already on the tracker when that later comment was copied. A block at the
    latest time, one with no readable time, or any block when no earlier copy
    has a readable time is new only when its exact header was not copied.
    """
    times = [b.ts_utc for b in earlier if b.ts_utc is not None]
    latest = max(times) if times else None
    copied = {(b.kind, b.author, b.ts_raw) for b in earlier}
    fresh = []
    for block in staged:
        if latest is not None and block.ts_utc is not None and block.ts_utc > latest:
            fresh.append(block)
        elif latest is not None and block.ts_utc is not None and block.ts_utc < latest:
            continue
        elif (block.kind, block.author, block.ts_raw) not in copied:
            fresh.append(block)
    return fresh


def issue_signature(text):
    """The issue text without its status line, for comparing two copies."""
    lines = [line for line in text.replace('\r\n', '\n').split('\n')
             if not line.startswith(STATUS_LINE)]
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


def month_day(stamp):
    when = stamp_time(stamp)
    return '%s %d' % (MONTHS[when.month - 1], when.day)


def comments_text(key, previous, fresh, first_number):
    parts = ['# %s comments added since %s, oldest first\n' % (key, previous)]
    for offset, block in enumerate(fresh):
        header = '## %s %d - %s - %s' % (block.kind, first_number + offset,
                                         block.author, block.ts_raw)
        parts.append('\n'.join([header, ''] + ([block.body] if block.body else [])) + '\n')
    return '\n'.join(parts)


def add_rows(readme_text, rows):
    lines = readme_text.split('\n')
    table = [i for i, line in enumerate(lines) if line.startswith('|')]
    if not table:
        raise RefreshError('context/README.md has no table to add rows to')
    at = table[-1] + 1
    return '\n'.join(lines[:at] + rows + lines[at:])


def refresh(cycle_dir, comments_path, issue_path, tool, now):
    yaml_path = os.path.join(cycle_dir, 'cycle.yaml')
    if not os.path.isfile(yaml_path):
        raise RefreshError('no cycle.yaml in %s' % cycle_dir)
    key = read_key(read_text(yaml_path), 'source_issue')
    if not key:
        raise RefreshError('%s records no source_issue' % cycle_dir)
    context = os.path.join(cycle_dir, 'context')
    readme_path = os.path.join(context, 'README.md')
    if not os.path.isfile(readme_path):
        raise RefreshError('no context/README.md in %s' % cycle_dir)
    readme = read_text(readme_path)
    if not any(line.startswith('|') for line in readme.split('\n')):
        raise RefreshError('context/README.md has no table to add rows to')

    staged = parse_blocks(read_text(comments_path))
    staged_issue = read_text(issue_path) if issue_path else None

    base = glob.escape(os.path.join(context, slug(key)))
    earlier = []
    for path in sorted(glob.glob(base + '-comments-*.md')):
        earlier.extend(parse_blocks(read_text(path)))
    issue_copies = sorted(glob.glob(base + '-issue-*.md'))
    newest = newest_stamp(context)
    previous = newest or now.strftime('%Y-%m-%dT%H%MZ')
    since = month_day(previous)

    fresh = new_blocks(staged, earlier)
    issue_changed = staged_issue is not None and (
        not issue_copies
        or issue_signature(staged_issue) != issue_signature(read_text(issue_copies[-1])))

    result = {'comments_file': '', 'new_comments': len(fresh), 'issue_file': '', 'stamp': ''}
    if fresh or issue_changed:
        stamp = next_stamp(context, now)
        retrieved = now.strftime(NOW_FORMAT)
        cell_tool = tool.replace('|', '\\|').replace('\n', ' ')
        rows = []
        writes = []
        if fresh:
            first = max([b.n for b in earlier], default=0) + 1
            name = '%s-comments-%s.md' % (slug(key), stamp)
            writes.append((os.path.join(context, name),
                           comments_text(key, previous, fresh, first)))
            rows.append('| %s | Comments added since %s: %d | %s | %s |'
                        % (name, previous, len(fresh), retrieved, cell_tool))
            result['comments_file'] = writes[-1][0]
        if issue_changed:
            name = '%s-issue-%s.md' % (slug(key), stamp)
            writes.append((os.path.join(context, name), staged_issue))
            rows.append('| %s | Issue text changed since %s | %s | %s |'
                        % (name, previous, retrieved, cell_tool))
            result['issue_file'] = writes[-1][0]
        for path, text in writes:
            if not write_atomic(path, text, mode=0o644, exclusive=True):
                raise RefreshError('%s already exists and was left as it was' % path)
        mode = os.stat(readme_path).st_mode & 0o777
        write_atomic(readme_path, add_rows(readme, rows), mode=mode)
        result['stamp'] = stamp

    if fresh or issue_changed:
        count = len(fresh)
        say = 'Refreshed %s: %d new comment%s since %s%s.' % (
            key, count, '' if count == 1 else 's', since,
            ', and the issue text changed' if issue_changed else '')
    else:
        say = 'Refreshed %s: nothing new since %s.' % (key, since)
    result['say'] = say
    return result


def main(argv):
    try:
        result = refresh(*parse_args(argv))
    except RefreshError as err:
        sys.stderr.write('snapshot-delta.py: %s\n' % err)
        return 1
    for name in ('comments_file', 'new_comments', 'issue_file', 'stamp', 'say'):
        sys.stdout.write('%s=%s\n' % (name, result[name]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
