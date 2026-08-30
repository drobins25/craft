"""Riff-note parser: session memories with no structured link fields.

Body paths and wikilinks still yield reference candidates - riff notes
narrate real records.
"""

import os

from . import body as body_mod
from . import identity
from . import resolve


def parse(path, craft_rel, fields, body):
    stem = os.path.splitext(os.path.basename(craft_rel))[0]
    nid = identity.node_id("riff", craft_rel)
    node = {
        "id": nid,
        "type": "riff",
        "title": fields.get("riff") or body_mod.humanize(stem),
        "date": fields.get("date") or None,
        "status": None,
        "tags": [],
        "surface": None,
        "_path": craft_rel,
        "_name": "",
        "_warnings": [],
    }
    links = []
    stripped = body_mod.strip_fenced(body)
    for raw_path in body_mod.craft_paths(stripped):
        rel = body_mod.craft_relative(raw_path)
        if rel:
            links.append(resolve.raw_link(nid, "riff", "body_path", rel))
    for inner in body_mod.wikilinks(stripped):
        links.append(resolve.raw_link(nid, "riff", "body_wikilink", inner))
    return node, links, []
