"""Shared access to the fixture corpus.

The corpus lives at __fixtures__/corpus/ WITHOUT a .craft level, because this
repo's .gitignore blankets any directory named .craft at any depth - a
fixture tree named .craft would be silently untracked. Tests that need a
real on-disk root copy the corpus into <tmp>/.craft.
"""

import os
import shutil
import tempfile

FIXTURES_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "__fixtures__",
)
CORPUS_DIR = os.path.join(FIXTURES_DIR, "corpus")


def read_fixture(craft_rel):
    """Text of one fixture record by .craft-relative path."""
    with open(os.path.join(CORPUS_DIR, craft_rel), encoding="utf-8") as f:
        return f.read()


def corpus_root():
    """Copy the corpus into a fresh temp dir as <tmp>/.craft; caller removes."""
    tmp = tempfile.mkdtemp()
    shutil.copytree(CORPUS_DIR, os.path.join(tmp, ".craft"))
    return tmp


def cleanup(root):
    shutil.rmtree(root, ignore_errors=True)
