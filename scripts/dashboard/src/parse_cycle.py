"""Cycle parser: the cycle.yaml node and its planning-doc citations.

cycle.yaml has no frontmatter fence - the caller hands this parser fields
parsed from the whole file. Stories emit membership themselves (belongs_to,
one direction only), so the cycle node emits no membership links.
"""

import os

from . import identity
from . import resolve

from . import body as body_mod


def parse(path, craft_rel, fields, body):
    nid = identity.node_id("cycle", craft_rel)
    cycle_dir = os.path.basename(os.path.dirname(craft_rel))
    node = {
        "id": nid,
        "type": "cycle",
        "title": fields.get("title") or body_mod.humanize(cycle_dir),
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
    source_concept = fields.get("source_concept")
    if isinstance(source_concept, str):
        source_concept = [source_concept] if source_concept else []
    for concept_path in source_concept or []:
        rel = body_mod.craft_relative(concept_path) or concept_path
        links.append(resolve.raw_link(nid, "cycle", "source_concept", rel))
    return node, links, annotations
