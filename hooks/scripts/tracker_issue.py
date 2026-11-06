"""One comparison of tracker issue copies, and the record of a rewritten issue.

An issue copy is `# <KEY>: <title>`, a few header lines (`Source:`,
`Status at retrieval:`, `Type:`), then the description. Only the title and the
description say what the issue is, so only they are compared: a header line
changing, or a tool adding one, is never a change to the issue.

A cycle follows the copy its context README marks ` (current)`; when nothing is
marked it follows the oldest copy. When the newest copy differs from that one,
cycle.yaml carries `issue_changed: '<stamp of the newest copy>'` until someone
updates the cycle to the new text or keeps it as it is.
"""
import glob
import os
import re
import sys
from typing import List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from annotate_write import write_atomic  # noqa: E402
from tracker_comments import read_key, slug, stamp_of  # noqa: E402

HEADING = re.compile(r'^# [^\s:]+: (.*)$')
HEADER_PREFIXES = ('Source:', 'Status at retrieval:', 'Type:')
TYPE_PREFIX = 'Type:'
CHANGE_KEY = 'issue_changed'
ANCHOR_KEYS = ('source_issue', 'authorized_stage', 'go_author', 'go_date')
CURRENT = ' (current)'
SUPERSEDED = ' (superseded)'
MARK = re.compile(r' \((?:current|superseded)\)$')


def issue_text(text: str) -> Tuple[str, str]:
    """(title, description) of an issue copy, header lines and padding dropped."""
    lines = text.replace('\r\n', '\n').split('\n')
    heading = HEADING.match(lines[0]) if lines else None
    if heading:
        title = heading.group(1).strip()
        at = 1
        while at < len(lines) and (not lines[at].strip()
                                   or lines[at].startswith(HEADER_PREFIXES)):
            at += 1
        body = lines[at:]
    else:
        title = ''
        body = lines
    body = [line.rstrip() for line in body]
    while body and not body[0]:
        body.pop(0)
    while body and not body[-1]:
        body.pop()
    return title, '\n'.join(body)


def same_issue(a: str, b: str) -> bool:
    return issue_text(a) == issue_text(b)


def issue_type(text: str) -> str:
    """The Type header value, or '' when the copy has none."""
    lines = text.replace('\r\n', '\n').split('\n')
    for line in lines[1:]:
        if line.startswith(TYPE_PREFIX):
            return line[len(TYPE_PREFIX):].strip()
        if line.strip() and not line.startswith(HEADER_PREFIXES):
            break
    return ''


def issue_copies(context: str, key: str) -> List[str]:
    return sorted(glob.glob(glob.escape(os.path.join(context, slug(key))) + '-issue-*.md'))


def _cells(line: str) -> List[str]:
    return line.split('|')


def _is_issue_row(line: str) -> bool:
    if not line.startswith('|'):
        return False
    cells = _cells(line)
    return len(cells) > 2 and '-issue-' in cells[1] and cells[1].strip().endswith('.md')


def reconciled_copy(context: str, key: str) -> Optional[str]:
    """The copy the cycle is reconciled with: the one marked current, else the oldest."""
    copies = issue_copies(context, key)
    if not copies:
        return None
    readme = os.path.join(context, 'README.md')
    if os.path.isfile(readme):
        by_name = {os.path.basename(path): path for path in copies}
        with open(readme, encoding='utf-8', newline='') as handle:
            for line in handle.read().split('\n'):
                if _is_issue_row(line):
                    cells = _cells(line)
                    if cells[2].rstrip().endswith(CURRENT) and cells[1].strip() in by_name:
                        return by_name[cells[1].strip()]
    return copies[0]


def mark_rows(readme_text: str, current_name: str) -> str:
    """Mark each issue-copy row's What cell current or superseded."""
    out = []
    for line in readme_text.split('\n'):
        if _is_issue_row(line):
            cells = _cells(line)
            what = cells[2]
            padding = what[len(what.rstrip()):]
            bare = MARK.sub('', what.rstrip())
            mark = CURRENT if cells[1].strip() == current_name else SUPERSEDED
            cells[2] = bare + mark + padding
            line = '|'.join(cells)
        out.append(line)
    return '\n'.join(out)


def _read(path: str) -> str:
    with open(path, encoding='utf-8', newline='') as handle:
        return handle.read()


def _ending(line: str) -> str:
    return line[len(line.rstrip('\r\n')):]


def _with_change(yaml_text: str, stamp: str) -> str:
    """The yaml carrying exactly one issue_changed line, other lines untouched."""
    lines = yaml_text.splitlines(True)
    new_value = "%s: '%s'" % (CHANGE_KEY, stamp)
    for i, line in enumerate(lines):
        if line.startswith(CHANGE_KEY + ':'):
            lines[i] = new_value + _ending(line)
            return ''.join(lines)
    anchor = -1
    for i, line in enumerate(lines):
        if any(line.startswith(k + ':') for k in ANCHOR_KEYS):
            anchor = i
    if anchor < 0:
        raise ValueError('no source_issue line to record after')
    ending = _ending(lines[anchor]) or '\n'
    lines[anchor] = lines[anchor].rstrip('\r\n') + ending
    lines.insert(anchor + 1, new_value + ending)
    return ''.join(lines)


def _without_change(yaml_text: str) -> str:
    return ''.join(line for line in yaml_text.splitlines(True)
                   if not line.startswith(CHANGE_KEY + ':'))


def record_change(cycle_dir: str) -> str:
    """Make cycle.yaml say whether the newest copy differs from the reconciled one.

    Returns the stamp recorded, or '' when the copies agree (any record is removed).
    """
    yaml_path = os.path.join(cycle_dir, 'cycle.yaml')
    yaml_text = _read(yaml_path)
    key = read_key(yaml_text, 'source_issue')
    context = os.path.join(cycle_dir, 'context')
    copies = issue_copies(context, key) if key else []
    basis = reconciled_copy(context, key) if copies else None
    stamp = ''
    if copies and basis and not same_issue(_read(copies[-1]), _read(basis)):
        stamp = stamp_of(os.path.basename(copies[-1])) or ''
    updated = _with_change(yaml_text, stamp) if stamp else _without_change(yaml_text)
    if updated != yaml_text:
        write_atomic(yaml_path, updated, mode=os.stat(yaml_path).st_mode & 0o777)
    return stamp
