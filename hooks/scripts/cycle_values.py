#!/usr/bin/env python3
"""The one writer for the ticket-derived fields of cycle.yaml.

Usage: cycle_values.py check <values-file> [--need <field>]...
       cycle_values.py write <cycle-dir> <values-file>

The values file holds one field per non-blank line, `<field>: <text>`, where
field is title, target, focus or goal. The text is everything after the first
`: `, with a trailing CR dropped and surrounding whitespace stripped; it is
never unquoted or unescaped, so a quote typed into the file is part of the
text. title, target and focus appear at most once; goal repeats, in order.

write replaces each present field in <cycle-dir>/cycle.yaml as a one-line
single-quoted scalar with each ' doubled (goals become a `goals:` key followed
by one `  - '<goal>'` line each). A block value (`target: |`) is replaced
whole, with its continuation lines. A new title keeps the cycle's existing
`Cycle NN: ` label. Every other line stays byte-identical, and status:,
updated: and notes: are never touched.

check validates the values file alone; --need names a field that must be
present. Success prints nothing. Any error prints one line,
`cycle_values.py: <reason>`, on stderr, exits 1, and writes nothing.
"""
import os
import re
import sys
from typing import Dict, List, Union

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from annotate_write import write_atomic  # noqa: E402
from tracker_comments import read_key  # noqa: E402

Values = Dict[str, Union[str, List[str]]]

SINGLE_FIELDS = ('title', 'target', 'focus')
FIELDS = SINGLE_FIELDS + ('goal',)
LABEL = re.compile(r'^Cycle [0-9]+: ')


class ValuesError(Exception):
    """A values file or cycle.yaml the writer refuses; nothing is written."""


def quoted(value: str) -> str:
    """The one-line single-quoted YAML scalar for value."""
    return "'" + value.replace("'", "''") + "'"


def read_values(path: str) -> Values:
    """The fields of a values file; goals come back as a list under `goal`."""
    try:
        with open(path, encoding='utf-8') as handle:
            text = handle.read()
    except OSError as err:
        raise ValuesError('cannot read values file %s: %s' % (path, err.strerror or err))
    except UnicodeDecodeError:
        raise ValuesError('values file %s is not UTF-8' % path)
    values = {}  # type: Values
    goals = []  # type: List[str]
    for number, raw in enumerate(text.split('\n'), 1):
        line = raw.rstrip('\r')
        if not line.strip():
            continue
        field, sep, rest = line.partition(': ')
        if not sep:
            raise ValuesError('values file line %d has no "<field>: <text>"' % number)
        if field not in FIELDS:
            raise ValuesError('values file line %d names unknown field "%s"' % (number, field))
        content = rest.strip()
        if not content:
            raise ValuesError('values file line %d: %s has no text' % (number, field))
        if field == 'goal':
            goals.append(content)
        elif field in values:
            raise ValuesError('values file line %d repeats %s' % (number, field))
        else:
            values[field] = content
    if goals:
        values['goal'] = goals
    if not values:
        raise ValuesError('values file %s holds no fields' % path)
    return values


def _split_lines(text: str) -> List[str]:
    """Lines with their endings; splits only on \\n, never on other separators."""
    return re.findall(r'[^\n]*\n|[^\n]+', text)


def _ending(line: str) -> str:
    return line[len(line.rstrip('\r\n')):]


def _value_end(lines: List[str], start: int) -> int:
    """Index just past the key line at start and its indented continuation.

    Blank lines count only when an indented line follows them."""
    end = start + 1
    probe = start + 1
    while probe < len(lines):
        line = lines[probe]
        if line[:1] in (' ', '\t'):
            end = probe + 1
        elif line.strip():
            break
        probe += 1
    return end


def _find(lines: List[str], key: str) -> int:
    for index, line in enumerate(lines):
        if line.startswith(key + ':'):
            return index
    raise ValuesError('cycle.yaml has no %s: line to update' % key)


def _labeled_title(yaml_text: str, text: str) -> str:
    match = LABEL.match(read_key(yaml_text, 'title'))
    if match and not text.startswith(match.group(0)):
        return match.group(0) + text
    return text


def apply(yaml_text: str, values: Values) -> str:
    """yaml_text with each present field replaced; raises before changing anything."""
    lines = _split_lines(yaml_text)
    for field in SINGLE_FIELDS:
        if field not in values:
            continue
        text = values[field]
        if not isinstance(text, str):
            raise ValuesError('%s must be one line of text' % field)
        if field == 'title':
            text = _labeled_title(yaml_text, text)
        start = _find(lines, field)
        lines[start:_value_end(lines, start)] = ['%s: %s%s' % (field, quoted(text), _ending(lines[start]))]
    goals = values.get('goal')
    if goals:
        if isinstance(goals, str):
            goals = [goals]
        start = _find(lines, 'goals')
        end = _value_end(lines, start)
        head = _ending(lines[start]) or '\n'
        tail = _ending(lines[end - 1]) if end > start + 1 else head
        block = ['  - %s%s' % (quoted(goal), head) for goal in goals]
        block[-1] = block[-1][:-len(head)] + tail
        lines[start:end] = ['goals:' + head] + block
    return ''.join(lines)


def write(cycle_dir: str, values_path: str) -> None:
    values = read_values(values_path)
    path = os.path.join(cycle_dir, 'cycle.yaml')
    try:
        with open(path, encoding='utf-8', newline='') as handle:
            before = handle.read()
        mode = os.stat(path).st_mode & 0o7777
    except OSError as err:
        raise ValuesError('cannot read %s: %s' % (path, err.strerror or err))
    except UnicodeDecodeError:
        raise ValuesError('%s is not UTF-8' % path)
    after = apply(before, values)
    try:
        write_atomic(path, after, mode=mode)
    except OSError as err:
        raise ValuesError('cannot write %s: %s' % (path, err.strerror or err))


def check(values_path: str, needs: List[str]) -> None:
    values = read_values(values_path)
    for field in needs:
        if field not in FIELDS:
            raise ValuesError('--need names unknown field "%s"' % field)
        if field not in values:
            raise ValuesError('values file has no %s' % field)


def main(argv: List[str]) -> int:
    try:
        args = argv[1:]
        if len(args) >= 2 and args[0] == 'check':
            needs = []  # type: List[str]
            rest = args[2:]
            while rest:
                if rest[0] != '--need' or len(rest) < 2:
                    raise ValuesError('Usage: cycle_values.py check <values-file> [--need <field>]...')
                needs.append(rest[1])
                rest = rest[2:]
            check(args[1], needs)
        elif len(args) == 3 and args[0] == 'write':
            write(args[1], args[2])
        else:
            raise ValuesError('Usage: cycle_values.py check <values-file> [--need <field>]... '
                              '| write <cycle-dir> <values-file>')
    except ValuesError as err:
        sys.stderr.write('cycle_values.py: %s\n' % err)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
