#!/usr/bin/env python3
"""Tell a planning flow whether a tracker cycle still matches its issue.

Usage: follow-issue.py check <cycle-dir> (--issue <staged-issue-file> --tool <text>
                                          | --unreadable <no-tools|read-failed|not-found>)
                                         [--now <YYYY-MM-DDTHH:MM:SSZ>]
       follow-issue.py keep <cycle-dir>
       follow-issue.py update <cycle-dir> --values <file> [--now <time>]

check prints exactly ten lines, in order:
  verdict=<none|current|changed|unreadable>, key=, cycle=, old_title=,
  new_title=, changed_lines=, first_changed=, as_of=, issue_type=, say=
A cycle with no source_issue is `none`: nothing is read or written. A staged
issue whose title or description differs from the newest copy
(tracker_issue.same_issue) is written as a new dated copy with one README row,
and the difference is recorded in cycle.yaml as `issue_changed`. While that
line is present the verdict is `changed`, however the issue was read.

keep and update answer the card check showed. Both need the `issue_changed`
line, mark the README's issue rows (the copy the line names is current, the
rest superseded), and clear the line. update also replaces the cycle's title,
target, focus, updated date and goals block with targeted line edits; no other
cycle.yaml line is touched. The target, focus and goals come from the values
file (see cycle_values.py, which does the writing and quotes every value the
same way). It must carry target, focus and at least one goal. The title is the
values file's `title:` when it has one, else the title of the issue copy the
recorded change names, with the cycle's `Cycle NN: ` label kept. Issue copies
are never opened for writing.

Exit 1, with one line on stderr and nothing written, on bad arguments, a
missing cycle.yaml or README table, or an input that cannot be read.
"""
import datetime
import difflib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from annotate_write import write_atomic  # noqa: E402
import cycle_values  # noqa: E402
import tracker_comments  # noqa: E402
from tracker_comments import (  # noqa: E402
    NOW_FORMAT, month_day, newest_stamp, next_stamp, read_key, slug, split_lines, stamp_of)
from tracker_issue import (  # noqa: E402
    CHANGE_KEY, issue_copies, issue_text, issue_type, mark_rows, reconciled_copy,
    record_change, same_issue)

PASTE_TOOL = 'pasted into the session'
FIELDS = ('verdict', 'key', 'cycle', 'old_title', 'new_title', 'changed_lines',
          'first_changed', 'as_of', 'issue_type', 'say')
UNREADABLE_SAY = {
    'no-tools': "I can't reach %s from here, so I can't tell whether cycle %s still matches it.",
    'read-failed': "Reading %s failed, so I can't tell whether cycle %s still matches it.",
    'not-found': "%s isn't on the tracker anymore, so I can't tell whether cycle %s still matches it.",
}


class FollowError(Exception):
    pass


def read_text(path):
    try:
        with open(path, encoding='utf-8', newline='') as handle:
            return handle.read()
    except (OSError, UnicodeDecodeError) as err:
        raise FollowError('cannot read %s: %s' % (path, err))


one_line = cycle_values.one_line


def parse_now(value):
    try:
        return tracker_comments.parse_now(value)
    except ValueError:
        raise FollowError('--now must look like 2026-10-31T18:40:00Z')


def parse_options(args, with_value, repeated=()):
    """(positional, options): options map name -> value, or list for repeated names."""
    positional = []
    options = {name: [] for name in repeated}
    queue = list(args)
    while queue:
        arg = queue.pop(0)
        if arg in with_value:
            if not queue:
                raise FollowError('%s needs a value' % arg)
            value = queue.pop(0)
            if arg in repeated:
                options[arg].append(value)
            else:
                options[arg] = value
        elif arg.startswith('--'):
            raise FollowError('unknown option %s' % arg)
        else:
            positional.append(arg)
    return positional, options


class Cycle:
    """A cycle directory with a source issue, read once."""

    def __init__(self, cycle_dir):
        self.dir = cycle_dir.rstrip('/') or cycle_dir
        self.yaml_path = os.path.join(self.dir, 'cycle.yaml')
        if not os.path.isfile(self.yaml_path):
            raise FollowError('no cycle.yaml in %s' % cycle_dir)
        self.yaml = read_text(self.yaml_path)
        self.key = read_key(self.yaml, 'source_issue')
        digits = re.match(r'\d*', os.path.basename(self.dir))
        self.number = digits.group(0) if digits else ''
        self.context = os.path.join(self.dir, 'context')
        self.readme_path = os.path.join(self.context, 'README.md')

    def readme(self):
        """The README text, which must carry a table."""
        if not os.path.isfile(self.readme_path):
            raise FollowError('no context/README.md in %s' % self.dir)
        text = read_text(self.readme_path)
        if not any(line.startswith('|') for line in text.split('\n')):
            raise FollowError('context/README.md has no table to add rows to')
        return text

    def recorded(self):
        return read_key(read_text(self.yaml_path), CHANGE_KEY)


def tool_cell(readme_text, name):
    """The Tool cell of the README row for a copy, or ''."""
    for line in readme_text.split('\n'):
        cells = line.split('|')
        if line.startswith('|') and len(cells) > 4 and cells[1].strip() == name:
            return cells[4].strip()
    return ''


def description_change(old_text, new_text):
    """(changed line count, first changed line) between two copies' descriptions."""
    old = issue_text(old_text)[1].split('\n')
    new = issue_text(new_text)[1].split('\n')
    count = 0
    first = ''
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes():
        if tag == 'equal':
            continue
        if count == 0:
            first = new[j1] if j1 < j2 else old[i1]
        count += max(i2 - i1, j2 - j1)
    return count, first


def empty_result(**given):
    result = {name: '' for name in FIELDS}
    result.update(given)
    return result


def changed_result(cycle):
    """The card fields for a cycle whose issue_changed line is present."""
    copies = issue_copies(cycle.context, cycle.key)
    basis = reconciled_copy(cycle.context, cycle.key)
    if not copies or not basis:
        raise FollowError('%s records a change but has no issue copy to show' % cycle.dir)
    old_text, new_text = read_text(basis), read_text(copies[-1])
    count, first = description_change(old_text, new_text)
    stamp = stamp_of(os.path.basename(copies[-1])) or ''
    return empty_result(
        verdict='changed', key=cycle.key, cycle=cycle.number,
        old_title=issue_text(old_text)[0], new_title=issue_text(new_text)[0],
        changed_lines=count, first_changed=first,
        as_of=month_day(stamp) if stamp else '', issue_type=issue_type(new_text))


def write_issue_copy(cycle, staged_text, tool, now):
    """Write the staged text as a new dated copy with its README row."""
    readme = cycle.readme()
    previous = newest_stamp(cycle.context) or now.strftime('%Y-%m-%dT%H%MZ')
    stamp = next_stamp(cycle.context, now)
    name = '%s-issue-%s.md' % (slug(cycle.key), stamp)
    row = '| %s | Issue text changed since %s | %s | %s |' % (
        name, previous, now.strftime(NOW_FORMAT), tool.replace('|', '\\|').replace('\n', ' '))
    lines = readme.split('\n')
    at = [i for i, line in enumerate(lines) if line.startswith('|')][-1] + 1
    updated = '\n'.join(lines[:at] + [row] + lines[at:])
    if not write_atomic(os.path.join(cycle.context, name), staged_text, mode=0o644, exclusive=True):
        raise FollowError('%s already exists and was left as it was' % name)
    write_atomic(cycle.readme_path, updated, mode=os.stat(cycle.readme_path).st_mode & 0o777)


def check(args):
    positional, options = parse_options(args, ('--issue', '--tool', '--unreadable', '--now'))
    if len(positional) != 1:
        raise FollowError('Usage: follow-issue.py check <cycle-dir> '
                          '(--issue <file> --tool <text> | --unreadable <reason>) [--now <time>]')
    issue_path, reason = options.get('--issue'), options.get('--unreadable')
    if (issue_path is None) == (reason is None):
        raise FollowError('check needs exactly one of --issue and --unreadable')
    if reason is not None and reason not in UNREADABLE_SAY:
        raise FollowError('--unreadable must be no-tools, read-failed or not-found')
    if issue_path is not None and not options.get('--tool'):
        raise FollowError('--issue needs --tool')
    now = parse_now(options['--now']) if '--now' in options else \
        datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)

    cycle = Cycle(positional[0])
    if not cycle.key:
        return empty_result(verdict='none')

    if issue_path is not None:
        staged = read_text(issue_path)
        copies = issue_copies(cycle.context, cycle.key)
        if not copies or not same_issue(staged, read_text(copies[-1])):
            write_issue_copy(cycle, staged, options['--tool'], now)
    # The copies on disk decide whether the cycle still matches its issue, whether or
    # not this check could read the tracker.
    record_change(cycle.dir)
    if cycle.recorded():
        return changed_result(cycle)

    basis = reconciled_copy(cycle.context, cycle.key)
    if reason is not None and not (basis and os.path.isfile(cycle.readme_path) and
                                   tool_cell(read_text(cycle.readme_path),
                                             os.path.basename(basis)) == PASTE_TOOL):
        return empty_result(verdict='unreadable', key=cycle.key, cycle=cycle.number,
                            say=UNREADABLE_SAY[reason] % (cycle.key, cycle.number))
    return empty_result(verdict='current', key=cycle.key, cycle=cycle.number)


def settle(cycle, stamp, edit=None):
    """Mark the README rows for the recorded copy, apply an optional yaml edit, clear the record."""
    readme = cycle.readme()
    name = next((os.path.basename(p) for p in issue_copies(cycle.context, cycle.key)
                 if stamp_of(os.path.basename(p)) == stamp), None)
    if name is None:
        raise FollowError('no issue copy carries the recorded stamp %s' % stamp)
    marked = mark_rows(readme, name)
    new_yaml = edit(cycle.yaml) if edit else None
    if marked != readme:
        write_atomic(cycle.readme_path, marked, mode=os.stat(cycle.readme_path).st_mode & 0o777)
    if new_yaml is not None and new_yaml != cycle.yaml:
        write_atomic(cycle.yaml_path, new_yaml, mode=os.stat(cycle.yaml_path).st_mode & 0o777)
    record_change(cycle.dir)


def open_cycle_with_record(args, with_value=(), repeated=()):
    positional, options = parse_options(args, with_value, repeated)
    if len(positional) != 1:
        raise FollowError('expected one <cycle-dir>')
    cycle = Cycle(positional[0])
    if not cycle.key:
        raise FollowError('%s records no source_issue' % cycle.dir)
    stamp = cycle.recorded()
    if not stamp:
        raise FollowError('%s has no recorded issue change to answer' % cycle.dir)
    if not any(stamp_of(os.path.basename(p)) == stamp
               for p in issue_copies(cycle.context, cycle.key)):
        # The copy the record pointed at is gone: let the copies on disk decide again.
        stamp = record_change(cycle.dir)
        if not stamp:
            raise FollowError('%s recorded a change for an issue copy that is gone; '
                              'the record is cleared and there is nothing to answer' % cycle.dir)
    return cycle, stamp, options


def keep(args):
    cycle, stamp, _ = open_cycle_with_record(args)
    settle(cycle, stamp)
    return empty_result(say="Planning against cycle %s as it is. I'll ask again only if %s changes again."
                        % (cycle.number, cycle.key))


def replace_line(lines, name, new_text):
    for i, line in enumerate(lines):
        if line.startswith(name + ':'):
            lines[i] = new_text + (line[len(line.rstrip('\r\n')):] or '')
            return
    raise FollowError('cycle.yaml has no %s: line to update' % name)


def recorded_title(cycle, stamp):
    """The title of the issue copy whose stamp is the recorded change."""
    for path in issue_copies(cycle.context, cycle.key):
        if stamp_of(os.path.basename(path)) == stamp:
            title = one_line(issue_text(read_text(path))[0])
            if not title:
                raise FollowError('the issue copy %s has no title' % os.path.basename(path))
            return title
    raise FollowError('no issue copy carries the recorded stamp %s' % stamp)


def update(args):
    cycle, stamp, options = open_cycle_with_record(args, ('--values', '--now'))
    if '--values' not in options:
        raise FollowError('update needs --values <file>')
    try:
        values = cycle_values.read_values(options['--values'])
        cycle_values.check_values(values, ['target', 'focus', 'goal'])
    except cycle_values.ValuesError as err:
        raise FollowError(err)
    values = {name: [one_line(v) for v in text] if isinstance(text, list) else one_line(text)
              for name, text in values.items()}
    if not values.get('title'):
        values['title'] = recorded_title(cycle, stamp)
    now = parse_now(options['--now']) if '--now' in options else \
        datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)

    def edit(yaml_text):
        try:
            new_yaml = cycle_values.apply(yaml_text, values)
        except cycle_values.ValuesError as err:
            raise FollowError(err)
        lines = split_lines(new_yaml)
        replace_line(lines, 'updated', 'updated: %s' % now.strftime('%Y-%m-%d'))
        return ''.join(lines)

    settle(cycle, stamp, edit)
    return empty_result(say='Cycle %s now follows %s as of %s.' % (cycle.number, cycle.key, month_day(stamp)))


COMMANDS = {'check': check, 'keep': keep, 'update': update}


def main(argv):
    try:
        if len(argv) < 2 or argv[1] not in COMMANDS:
            raise FollowError('Usage: follow-issue.py check|keep|update <cycle-dir> ...')
        result = COMMANDS[argv[1]](argv[2:])
    except (FollowError, ValueError) as err:
        sys.stderr.write('follow-issue.py: %s\n' % err)
        return 1
    names = FIELDS if argv[1] == 'check' else ('say',)
    for name in names:
        sys.stdout.write('%s=%s\n' % (name, one_line(str(result[name]))))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
