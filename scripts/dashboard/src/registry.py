"""Record discovery and parser dispatch.

Classification is by path, first pattern wins. Everything under .craft/ that
matches no pattern is skipped silently - the build never crashes on a future
record shape, and a new record type is one dict entry plus one module.
"""

import os
import re

from . import body as body_mod
from . import frontmatter
from . import identity
from . import parse_cycle
from . import parse_dial
from . import parse_fix
from . import parse_mockup
from . import parse_notebook
from . import parse_planning
from . import parse_riff
from . import parse_story
from . import parse_tweak
from . import summary as summary_mod
from . import vocabulary


_RULES = [
    ("cycle", "cycles/*/cycle.yaml"),
    ("story", "cycles/*/stories/*.md"),
    ("story", "backlog/*.md"),
    ("fix", "fixes/*.md"),
    ("tweak", "tweaks/*.md"),
    ("mockup", "mockups/*/record.md"),
    ("dial", "dials/*.md"),
    ("notebook", "notebook/ideas/*.md"),
    ("notebook", "notebook/todos/*.md"),
    ("notebook", "notebook/todos/done/*.md"),
    ("notebook", "notebook/notes/*.md"),
    ("riff", "riff/notes/*.md"),
    ("planning", "planning/**/*.md"),
]


def _compile(pattern):
    escaped = re.escape(pattern)
    escaped = escaped.replace(re.escape("**/"), r"(?:[^/]+/)*")
    escaped = escaped.replace(re.escape("*"), r"[^/]*")
    return re.compile("^" + escaped + "$")


_COMPILED = [(record_type, _compile(pattern)) for record_type, pattern in _RULES]


_PARSER_FUNCS = {
    "story": parse_story.parse,
    "cycle": parse_cycle.parse,
    "planning": parse_planning.parse,
    "fix": parse_fix.parse,
    "tweak": parse_tweak.parse,
    "notebook": parse_notebook.parse,
    "riff": parse_riff.parse,
    "mockup": parse_mockup.parse,
    "dial": parse_dial.parse,
}

# Keyed by the definition's record types, not a second hand-kept literal -
# a record type the definition does not know cannot get a parser slot.
PARSERS = {
    record_type: _PARSER_FUNCS[record_type]
    for record_type in vocabulary.RECORD_TYPES
}


def classify(craft_rel):
    """Record type for one .craft-relative path, or None (skip silently)."""
    for record_type, rx in _COMPILED:
        if rx.match(craft_rel):
            return record_type
    return None


def discover(root):
    """Walk <root>/.craft and classify -> sorted [(record_type, craft_rel)]."""
    craft = os.path.join(root, ".craft")
    found = []
    for dirpath, dirnames, filenames in os.walk(craft):
        dirnames[:] = sorted(
            d for d in dirnames if d not in ("graph", "dashboard")
        )
        for filename in filenames:
            rel = os.path.relpath(
                os.path.join(dirpath, filename), craft
            ).replace(os.sep, "/")
            record_type = classify(rel)
            if record_type is not None:
                found.append((record_type, rel))
    found.sort(key=lambda item: item[1])
    return found


def parse_file(record_type, craft_rel, text, path=None):
    """Parse one record's text through its type's parser, never raising.

    cycle.yaml has no frontmatter fence, so cycle fields come from the whole
    file; fenced text still parses through the normal reader.
    """
    if record_type == "cycle" and not text.startswith("---"):
        fields = frontmatter.parse_mapping(text.split("\n"))
        body = ""
    else:
        fields, body = frontmatter.parse(text)
    parser = PARSERS[record_type]
    try:
        node, links, notes = parser(path, craft_rel, fields, body)
    except Exception as exc:  # noqa: BLE001 - the never-crash contract
        return _minimal_node(record_type, craft_rel, exc), [], []
    _attach_summary(node, record_type, fields, body)
    return node, links, notes


def _attach_summary(node, record_type, fields, body):
    """Never lets a summary-extraction bug take down the whole build."""
    try:
        value = summary_mod.extract(record_type, fields, body)
    except Exception:  # noqa: BLE001 - the never-crash contract
        return
    if value:
        node["summary"] = value


def _minimal_node(record_type, craft_rel, exc):
    stem = os.path.splitext(os.path.basename(craft_rel))[0]
    return {
        "id": identity.node_id(record_type, craft_rel),
        "type": record_type,
        "title": body_mod.humanize(stem),
        "date": None,
        "status": None,
        "tags": [],
        "surface": None,
        "_path": craft_rel,
        "_name": "",
        "_warnings": [
            "parser for %s failed on %s: %s" % (record_type, craft_rel, exc)
        ],
    }
