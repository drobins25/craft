"""Dial parser: live calibration records from dials/.

Discriminated by `source: dial`, identified by `slug:` not `name:`. The
`offered` value is a comma STRING of candidate values, not a list of links.
surface and kind are envelope attributes shared with the tweak vocabulary -
deliberately duplicated per the one-parser-per-grammar rule, never nodes.
"""

import os

from . import body as body_mod
from . import identity
from . import resolve
from .parse_fix import field_link


def parse(path, craft_rel, fields, body):
    stem = os.path.splitext(os.path.basename(craft_rel))[0]
    nid = identity.node_id("dial", craft_rel)
    warnings = []
    if fields.get("source") != "dial":
        warnings.append(
            "dial record without source: dial discriminator: %s" % craft_rel
        )
    slug = fields.get("slug") or stem
    node = {
        "id": nid,
        "type": "dial",
        "title": body_mod.humanize(slug),
        "date": fields.get("created") or None,
        "status": fields.get("outcome") or None,
        "tags": [],
        "surface": fields.get("surface") or None,
        "kind": fields.get("kind") or None,
        "_path": craft_rel,
        "_name": slug,
        "_warnings": warnings,
    }
    links = []
    annotations = []
    field_link(
        nid, fields, "graduated_to", "graduated_to", links, annotations,
        expect={"tweak", "story", "notebook"},
    )
    return node, links, annotations
