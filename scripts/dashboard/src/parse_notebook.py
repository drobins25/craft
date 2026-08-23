"""Notebook parser: ideas, todos (open and done), and notes.

Subtype derives from the PATH segment, not the `type:` field - todos/done/
records keep `type: todo` while living in a different directory. The title
is the first non-blank body line; notebook records have no title field.

graduated_to may point at a fix, tweak, story, or dial - never constrained
to stories. `source` is a link only when its value is a wikilink; the
`session YYYY-MM-DD` provenance form stays an annotation.
"""

import re

from . import identity
from . import resolve
from . import sentinels
from .parse_fix import field_link

_WIKILINK_VALUE_RE = re.compile(r'^"?\[\[([^\]]+)\]\]"?$')

_TITLE_LIMIT = 120


def parse(path, craft_rel, fields, body):
    nid = identity.node_id("notebook", craft_rel)
    parts = craft_rel.split("/")
    subtype = {"ideas": "idea", "todos": "todo", "notes": "note"}.get(
        parts[1] if len(parts) > 1 else "", "note"
    )

    node = {
        "id": nid,
        "type": "notebook",
        "subtype": subtype,
        "title": _first_body_line(body),
        "date": fields.get("created") or None,
        "status": fields.get("status") or None,
        "tags": _tags(fields),
        "surface": None,
        "_path": craft_rel,
        "_name": "",
        "_warnings": [],
    }

    links = []
    annotations = []
    field_link(nid, fields, "notebook", "graduated_to", links, annotations)

    source = fields.get("source")
    if source is not None:
        wikilink = _WIKILINK_VALUE_RE.match(str(source).strip())
        if wikilink:
            links.append(
                resolve.raw_link(
                    nid, "notebook", "source", wikilink.group(1).strip()
                )
            )
        elif not sentinels.is_sentinel(source):
            annotations.append(
                resolve.annotation(nid, "source", source, "prose")
            )
    return node, links, annotations


def _first_body_line(body):
    for line in body.split("\n"):
        line = line.strip()
        if line:
            return line[:_TITLE_LIMIT]
    return "(empty note)"


def _tags(fields):
    tags = fields.get("tags")
    if isinstance(tags, list):
        return tags
    if tags:
        return [tags]
    return []
