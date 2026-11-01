#!/usr/bin/env python3
"""Find the live cycle that already records a tracker issue.

Usage: find-issue-cycle.py <KEY> [<project-root>]

Scans <root>/.craft/cycles/*/cycle.yaml for a source_issue equal to KEY
(case-insensitive) on a cycle whose status is planning, ready or active. A
complete cycle never matches, so a finished issue starts a fresh cycle.

Output: exactly three lines
  cycle_dir=<path of the match with the highest cycle number, or empty>
  status=<its status, or empty>
  matches=<how many cycles matched>

Exits 0 whether or not anything matched, and 1 only on a wrong argument
count. Never writes.
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from tracker_comments import read_key  # noqa: E402

LIVE = ('planning', 'ready', 'active')


def cycle_number(path):
    match = re.match(r'^([0-9]+)-', os.path.basename(path))
    return int(match.group(1)) if match else 0


def find(key, root):
    pattern = os.path.join(glob.escape(root), '.craft', 'cycles', '*', 'cycle.yaml')
    matches = []
    for yaml_path in glob.glob(pattern):
        try:
            with open(yaml_path, encoding='utf-8') as handle:
                text = handle.read()
        except (OSError, UnicodeDecodeError):
            continue
        issue = read_key(text, 'source_issue')
        status = read_key(text, 'status')
        if key and issue.lower() == key.lower() and status in LIVE:
            matches.append((os.path.dirname(yaml_path), status))
    matches.sort(key=lambda item: cycle_number(item[0]))
    return matches


def main(argv):
    if len(argv) not in (2, 3):
        sys.stderr.write('Usage: find-issue-cycle.py <KEY> [<project-root>]\n')
        return 1
    matches = find(argv[1], argv[2] if len(argv) == 3 else '.')
    cycle_dir, status = matches[-1] if matches else ('', '')
    sys.stdout.write('cycle_dir=%s\nstatus=%s\nmatches=%d\n' % (cycle_dir, status, len(matches)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
