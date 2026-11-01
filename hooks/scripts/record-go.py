#!/usr/bin/env python3
"""Re-resolve the newest Go on a tracker issue and record it in cycle.yaml.

Usage: record-go.py <cycle-dir> [<delta-comments-file>]

The delta is the comments copy a refresh just wrote, named
<slug>-comments-<stamp>.md. Every comment in it is newer than every comment
copied before, so a Go found there is the newest Go on the issue. It is
resolved by resolve-go.py, which runs on the delta alone.

  found       the record becomes the resolver's stage, author and date
  unreadable  the record becomes plan with an empty author and date: a Go
              that cannot be read must never keep an older build open
  none        the record stands (no delta means none)

The record is the three one-line single-quoted keys authorized_stage,
go_author and go_date in cycle.yaml. A cycle made from an issue with no Go has
none of the three lines; found and unreadable insert them right after
source_issue. Only when the record changes is cycle.yaml opened for writing,
and then only those three lines change. A found Go also writes
context/<slug>-go-<stamp>.md with the delta's stamp and one README row.

Output: exactly four lines, in order
  changed=<yes|no>
  old_stage=<the stage before, empty when no stage was recorded>
  stage=<the stage now, empty when no stage is recorded>
  say=<the line to show the user>

The say is built by substituting into the resolver's own stage_line, never
composed from parts. Exit 1, with one line on stderr and nothing written, when
the cycle has no cycle.yaml or no source_issue, when only some of the three
keys are present, or when the delta cannot be read or resolved.
"""
import datetime
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from annotate_write import write_atomic  # noqa: E402
from tracker_comments import read_key, slug, stamp_of  # noqa: E402

KEYS = ('authorized_stage', 'go_author', 'go_date')
MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
          'August', 'September', 'October', 'November', 'December']
GO_HEADING = re.compile(r'^## Go - .+ \((.+), (' + '|'.join(MONTHS) + r') ([0-9]{1,2}), [0-9]{4}\)\s*$')
NOW_FORMAT = '%Y-%m-%dT%H:%M:%SZ'


class RecordError(Exception):
    pass


def read_text(path):
    try:
        with open(path, encoding='utf-8', newline='') as handle:
            return handle.read()
    except (OSError, UnicodeDecodeError) as err:
        raise RecordError('cannot read %s: %s' % (path, err))


def quoted(value):
    return "'%s'" % value.replace("'", "''")


def has_line(yaml_text, key):
    return re.search(r'^%s:' % key, yaml_text, re.MULTILINE) is not None


def resolve_delta(delta_path, key, go_copy):
    """The resolver's six fields as a dict; it writes the Go body to go_copy."""
    here = os.path.dirname(os.path.abspath(__file__))
    done = subprocess.run(
        [sys.executable, os.path.join(here, 'resolve-go.py'), delta_path, key, go_copy],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    if done.returncode != 0:
        raise RecordError('resolve-go.py failed: %s' % done.stderr.strip())
    fields = {}
    for line in done.stdout.split('\n'):
        name, sep, value = line.partition('=')
        if sep:
            fields[name] = value
    return fields


def newest_go_say(context, key, stage):
    """The say for a delta with no Go, from the newest Go copy's own heading."""
    copies = sorted(glob.glob(os.path.join(glob.escape(context), slug(key) + '-go-*.md')))
    if copies:
        first = read_text(copies[-1]).split('\n')[0]
        match = GO_HEADING.match(first)
        if match:
            return 'Stage unchanged: %s, per Go from %s on %s %s.' % (
                stage, match.group(1), match.group(2)[:3], int(match.group(3)))
    return 'Stage unchanged: plan, because %s has no readable Go.' % key


def substitute(old_stage, new_stage, stage_line, unreadable):
    """The say for a Go that was found or could not be read."""
    old = old_stage or 'none'
    if unreadable:
        if old_stage == 'plan':
            return 'Stage unchanged: plan. %s' % stage_line
        return 'Stage changed: %s to plan. %s' % (old, stage_line)
    rest = stage_line[len('Stage: '):]
    if old_stage == new_stage:
        return 'Stage unchanged: %s' % rest
    return 'Stage changed: %s to %s' % (old, rest)


def new_yaml(yaml_text, record):
    """The yaml with the three record lines replaced, or inserted after source_issue."""
    lines = yaml_text.splitlines(True)
    values = dict(zip(KEYS, record))
    if has_line(yaml_text, KEYS[0]):
        for i, line in enumerate(lines):
            for key in KEYS:
                if line.startswith(key + ':'):
                    ending = line[len(line.rstrip('\r\n')):]
                    lines[i] = '%s: %s%s' % (key, quoted(values[key]), ending)
        return ''.join(lines)
    for i, line in enumerate(lines):
        if line.startswith('source_issue:'):
            ending = line[len(line.rstrip('\r\n')):] or '\n'
            lines[i] = line.rstrip('\r\n') + ending
            block = ['%s: %s%s' % (key, quoted(values[key]), ending) for key in KEYS]
            return ''.join(lines[:i + 1] + block + lines[i + 1:])
    raise RecordError('no source_issue line to record after')


def add_readme_row(context, row):
    path = os.path.join(context, 'README.md')
    if not os.path.isfile(path):
        return
    lines = read_text(path).split('\n')
    table = [i for i, line in enumerate(lines) if line.startswith('|')]
    if not table:
        return
    at = table[-1] + 1
    write_atomic(path, '\n'.join(lines[:at] + [row] + lines[at:]),
                 mode=os.stat(path).st_mode & 0o777)


def record(cycle_dir, delta_path):
    yaml_path = os.path.join(cycle_dir, 'cycle.yaml')
    if not os.path.isfile(yaml_path):
        raise RecordError('no cycle.yaml in %s' % cycle_dir)
    yaml_text = read_text(yaml_path)
    key = read_key(yaml_text, 'source_issue')
    if not key:
        raise RecordError('%s records no source_issue' % cycle_dir)
    present = [has_line(yaml_text, k) for k in KEYS]
    if any(present) and not all(present):
        raise RecordError('%s records only some of %s' % (cycle_dir, ', '.join(KEYS)))
    recorded = all(present)
    stored = tuple(read_key(yaml_text, k) for k in KEYS)
    old_stage = stored[0] if recorded else ''
    context = os.path.join(cycle_dir, 'context')

    result = {'go': 'none'}
    scratch = None
    stamp = None
    try:
        if delta_path:
            stamp = stamp_of(os.path.basename(delta_path))
            if stamp is None:
                raise RecordError('%s does not carry a stamp in its name' % delta_path)
            read_text(delta_path)
            scratch = tempfile.mkdtemp(prefix='record-go.')
            result = resolve_delta(delta_path, key, os.path.join(scratch, 'go.md'))

        found = result['go'] == 'found'
        unreadable = result['go'] == 'unreadable'
        if found:
            new = (result['stage'], result['go_author'], result['go_date'])
        elif unreadable:
            new = ('plan', '', '')
        else:
            new = stored
        changed = (found or unreadable) and (not recorded or new != stored)

        if found or unreadable:
            say = substitute(old_stage, new[0], result['stage_line'], unreadable)
        elif not recorded:
            say = result.get('stage_line') or (
                'No Go on %s, so craft works as usual: you decide when to build.' % key)
        else:
            say = newest_go_say(context, key, old_stage) if (old_stage != 'plan' or stored[1]) \
                else 'Stage unchanged: plan, because %s has no readable Go.' % key

        if changed:
            copy_path = None
            if found:
                name = '%s-go-%s.md' % (slug(key), stamp)
                copy_path = os.path.join(context, name)
                with open(os.path.join(scratch, 'go.md'), encoding='utf-8', newline='') as handle:
                    body = handle.read()
                left_over = os.path.exists(copy_path)
                if left_over and read_text(copy_path) != body:
                    raise RecordError('%s already exists and was left as it was' % name)
            # The record goes first: a failed write then leaves nothing behind,
            # and a copy that fails after it is read as "no Go" until a retry.
            write_atomic(yaml_path, new_yaml(yaml_text, new),
                         mode=os.stat(yaml_path).st_mode & 0o777)
            if found and not left_over:
                if not write_atomic(copy_path, body, mode=0o644, exclusive=True):
                    raise RecordError('%s already exists and was left as it was' % name)
                add_readme_row(context, '| %s | Newest Go: comment %s, %s, %s | %s | resolve-go.py |' % (
                    name, result['go_comment'], new[1], new[2],
                    datetime.datetime.now(datetime.timezone.utc).strftime(NOW_FORMAT)))
    finally:
        if scratch:
            shutil.rmtree(scratch, ignore_errors=True)

    return {'changed': 'yes' if changed else 'no', 'old_stage': old_stage,
            'stage': new[0] if (recorded or changed) else '', 'say': say}


def main(argv):
    if len(argv) not in (2, 3) or not argv[1]:
        sys.stderr.write('Usage: record-go.py <cycle-dir> [<delta-comments-file>]\n')
        return 1
    try:
        result = record(argv[1], argv[2] if len(argv) == 3 and argv[2] else None)
    except RecordError as err:
        sys.stderr.write('record-go.py: %s\n' % err)
        return 1
    for name in ('changed', 'old_stage', 'stage', 'say'):
        sys.stdout.write('%s=%s\n' % (name, result[name]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
