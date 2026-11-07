"""Shared reading of a copied tracker issue: comment blocks, times, stamps.

The comments-file grammar matches resolve-go.py: optional preamble lines, then
blocks. A block opens with a line matching
"## (Comment|Reply|Inline) <n> - <author> - <timestamp>" (author is the greedy
middle, timestamp is the tracker's own string). The body is every line up to
the next header, with leading and trailing blank lines stripped. Only that
strict header form opens a block, so a "## " line inside a comment body never
splits it.

Timestamps are parsed with a pattern, never datetime.fromisoformat, which
rejects "Z" and "+0000" before Python 3.11.

Imports only the standard library.
"""
import datetime
import os
import re
from typing import List, NamedTuple, Optional

HEADER = re.compile(r'^## (Comment|Reply|Inline) ([0-9]+) - (.+) - (\S+)$')
TIME = re.compile(
    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})'
    r'(?:\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})$')
STAMP_FORMAT = '%Y-%m-%dT%H%MZ'
STAMP_IN_NAME = re.compile(r'([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}Z)\.md$')


class Block(NamedTuple):
    kind: str
    n: int
    author: str
    ts_raw: str
    ts_utc: Optional[datetime.datetime]
    body: str


def parse_ts(raw: str) -> Optional[datetime.datetime]:
    """UTC datetime for a tracker timestamp, or None when it is not one."""
    m = TIME.match(raw)
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


def parse_blocks(text: str) -> List[Block]:
    """Every comment block in the text, in file order, bodies blank-edge cut."""
    raw = []
    for line in text.split('\n'):
        m = HEADER.match(line)
        if m:
            raw.append([m.group(1), m.group(2), m.group(3), m.group(4), []])
        elif raw:
            raw[-1][4].append(line)
    blocks = []
    for kind, number, author, ts_raw, lines in raw:
        while lines and not lines[0].strip():
            lines.pop(0)
        while lines and not lines[-1].strip():
            lines.pop()
        blocks.append(Block(kind, int(number), author, ts_raw, parse_ts(ts_raw),
                            '\n'.join(lines)))
    return blocks


def read_key(yaml_text: str, key: str) -> str:
    """A flat top-level key written as a one-line scalar, decoded like the shell
    read_key: '...' loses its quotes and reads each '' as ', "..." loses its
    quotes with the inside verbatim, anything else is returned as written."""
    match = re.search(r'^%s:[ \t]*(.*?)[ \t\r]*$' % re.escape(key), yaml_text, re.MULTILINE)
    if not match:
        return ''
    value = match.group(1)
    if len(value) >= 2:
        if value[0] == "'" and value[-1] == "'":
            return value[1:-1].replace("''", "'")
        if value[0] == '"' and value[-1] == '"':
            return value[1:-1]
    return value


def split_lines(text: str) -> List[str]:
    """Lines with their endings; splits only on \\n, never on the other
    separators str.splitlines knows, so a value holding one stays one line."""
    return re.findall(r'[^\n]*\n|[^\n]+', text)


def slug(key: str) -> str:
    """The key lowercased, each run of characters outside a-z0-9 one dash."""
    return re.sub(r'[^a-z0-9]+', '-', key.lower())


def stamp_of(name: str) -> Optional[str]:
    """The stamp a copied file's name carries, or None."""
    m = STAMP_IN_NAME.search(name)
    return m.group(1) if m else None


def stamp_time(stamp: str) -> datetime.datetime:
    return datetime.datetime.strptime(stamp, STAMP_FORMAT)


def newest_stamp(context_dir: str) -> Optional[str]:
    """The latest stamp on any file in the folder, or None when none carries one."""
    try:
        names = os.listdir(context_dir)
    except OSError:
        return None
    stamps = [s for s in map(stamp_of, names) if s]
    return max(stamps) if stamps else None


def next_stamp(context_dir: str, now: datetime.datetime) -> str:
    """A stamp strictly later than every stamp in the folder.

    Stamps have minute resolution, so a refresh and a story-start re-check in
    the same minute would collide. A suffix would sort before the bare name
    and break "the last copy is the newest", so the stamp moves a minute past
    the newest one instead.
    """
    mine = now.strftime(STAMP_FORMAT)
    newest = newest_stamp(context_dir)
    if newest is not None and newest >= mine:
        return (stamp_time(newest) + datetime.timedelta(minutes=1)).strftime(STAMP_FORMAT)
    return mine
