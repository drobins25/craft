"""Mockup parser: mockups/<date-slug>/record.md.

graduated_to is polymorphic and 1:N in practice (a single mockup has
graduated to a tweak AND a story); the raw value is emitted whole and the
assembler extracts every resolvable target. solidify_outcome names
tokens.yaml sections in prose - always an annotation, never a link.
"""

import os

from . import body as body_mod
from . import identity
from . import resolve
from . import sentinels
from .parse_fix import field_link


def parse(path, craft_rel, fields, body):
    stem = os.path.basename(os.path.dirname(craft_rel)) or os.path.splitext(
        os.path.basename(craft_rel)
    )[0]
    nid = identity.node_id("mockup", craft_rel)
    node = {
        "id": nid,
        "type": "mockup",
        "title": body_mod.humanize(fields.get("name") or stem),
        "date": fields.get("created") or None,
        "status": fields.get("status") or None,
        "tags": [],
        "surface": None,
        "_path": craft_rel,
        "_name": fields.get("name", ""),
        "_warnings": [],
    }
    links = []
    annotations = []
    field_link(nid, fields, "mockup", "graduated_to", links, annotations)
    field_link(nid, fields, "mockup", "origin", links, annotations)

    solidify = fields.get("solidify_outcome")
    if solidify is not None and not sentinels.is_sentinel(solidify):
        annotations.append(
            resolve.annotation(
                nid, "solidify_outcome", solidify, "out-of-scope-type"
            )
        )
    return node, links, annotations
