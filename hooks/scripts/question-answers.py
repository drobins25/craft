#!/usr/bin/env python3
"""List which questions Craft posted on an issue now have answers.

Usage: question-answers.py <cycle-dir> [--new-in <comments-file>]

Reads every context/<slug>-comments-*.md of a tracker cycle. A question is a
comment whose first body line is "## Question from Claude - <topic>". The
connector posts as the user, so author cannot tell a question from its answer,
and threading differs per tracker. Matching therefore uses the heading and the
time only:

  - a Go comment (first body line "## Go") is never an answer;
  - any other comment posted after a question answers every earlier question
    whose topic it names (case-insensitive), or else the newest earlier
    question that is still unanswered, or else nothing;
  - the first answer is the one reported.

Output: "questions=<N>", "answered=<A>", then one "line=" per answered question
in posted order ("Answered: <topic> - "<excerpt>" (<author>, <Mon D>)"), then
one per open question ("Still open: <topic> (asked <Mon D>)").
With --new-in only the Answered lines whose answer is in that file print, and
answered counts them.

Errors (wrong arguments, a directory without cycle.yaml or a source_issue)
exit 1 with one line on stderr and nothing on stdout. Never writes.
"""
import datetime
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tracker_comments as tc  # noqa: E402

QUESTION = re.compile(r'^## Question from Claude - (.+?)\s*$')
GO_CANDIDATE = re.compile(r'^##\s+Go\b')
EXCERPT_LIMIT = 80
MONTHS = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec')


class AnswersError(Exception):
    """A condition that ends the run with one stderr line."""


def read_text(path):
    try:
        with open(path, encoding='utf-8', newline='') as handle:
            return handle.read().replace('\r', '')
    except (OSError, UnicodeDecodeError) as err:
        raise AnswersError('cannot read %s: %s' % (path, err))


def first_line(body):
    return next((line for line in body.split('\n') if line.strip()), '')


def header_of(block):
    return (block.kind, block.author, block.ts_raw, block.body)


def month_day(block):
    when = block.ts_utc
    if when is None:
        return block.ts_raw
    return '%s %d' % (MONTHS[when.month - 1], when.day)


def excerpt(body):
    text = re.sub(r'^[>#\s]+', '', first_line(body))
    text = ' '.join(text.split())
    return text if len(text) <= EXCERPT_LIMIT else text[:EXCERPT_LIMIT] + '...'


def ordered_blocks(copies):
    """Every distinct block, oldest first; an unreadable time sorts last."""
    seen = set()
    entries = []
    for file_at, text in enumerate(copies):
        for at, block in enumerate(tc.parse_blocks(text)):
            if header_of(block) in seen:
                continue
            seen.add(header_of(block))
            when = block.ts_utc or datetime.datetime.max
            entries.append((when, file_at, at, block))
    entries.sort(key=lambda entry: entry[:3])
    return [entry[3] for entry in entries]


def match(blocks):
    """(questions, answers): questions as (block, topic), answers by question index."""
    questions = []
    answers = {}
    for block in blocks:
        head = first_line(block.body)
        asked = QUESTION.match(head)
        if asked:
            questions.append((block, asked.group(1)))
            continue
        if GO_CANDIDATE.match(head) or not questions:
            continue
        lowered = block.body.lower()
        named = [at for at, (_, topic) in enumerate(questions) if topic.lower() in lowered]
        if not named:
            open_ones = [at for at in range(len(questions)) if at not in answers]
            named = open_ones[-1:]
        for at in named:
            answers.setdefault(at, block)
    return questions, answers


def run(cycle_dir, new_in):
    yaml_path = os.path.join(cycle_dir, 'cycle.yaml')
    issue = tc.read_key(read_text(yaml_path), 'source_issue')
    if not issue:
        raise AnswersError('%s has no source_issue' % yaml_path)
    pattern = os.path.join(glob.escape(os.path.join(cycle_dir, 'context')),
                           glob.escape(tc.slug(issue)) + '-comments-*.md')
    copies = [read_text(path) for path in sorted(glob.glob(pattern))]
    questions, answers = match(ordered_blocks(copies))
    fresh = None
    if new_in is not None:
        fresh = {header_of(block) for block in tc.parse_blocks(read_text(new_in))}
    lines = []
    for at, (asked, topic) in enumerate(questions):
        answer = answers.get(at)
        if answer is None or (fresh is not None and header_of(answer) not in fresh):
            continue
        lines.append('Answered: %s - "%s" (%s, %s)'
                     % (topic, excerpt(answer.body), answer.author, month_day(answer)))
    if fresh is None:
        for at, (asked, topic) in enumerate(questions):
            if at not in answers:
                lines.append('Still open: %s (asked %s)' % (topic, month_day(asked)))
    answered = sum(1 for line in lines if line.startswith('Answered: '))
    out = ['questions=%d' % len(questions), 'answered=%d' % answered]
    out.extend('line=%s' % line for line in lines)
    return out


def main(argv):
    args = argv[1:]
    new_in = None
    if len(args) == 3 and args[1] == '--new-in':
        args, new_in = args[:1], args[2]
    if len(args) != 1:
        sys.stderr.write('Usage: question-answers.py <cycle-dir> [--new-in <comments-file>]\n')
        return 1
    try:
        out = run(args[0], new_in)
    except AnswersError as err:
        sys.stderr.write('question-answers.py: %s\n' % err)
        return 1
    sys.stdout.write('\n'.join(out) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
