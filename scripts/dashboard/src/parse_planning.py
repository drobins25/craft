"""Planning-doc parser: title from the first heading, date from frontmatter.

Planning docs join the graph as citation targets (source_concept, Reference
Materials); their own bodies cite records via paths and wikilinks, which
yield reference candidates per the resolve-or-annotate rule.
"""

import os
import re

from . import body as body_mod
from . import identity
from . import resolve

_H1_RE = re.compile(r"^# (.+)$", re.M)


def parse(path, craft_rel, fields, body):
    stem = os.path.splitext(os.path.basename(craft_rel))[0]
    nid = identity.node_id("planning", craft_rel)
    warnings = []
    stripped = body_mod.strip_fenced(body)

    heading = _H1_RE.search(stripped)
    title = heading.group(1).strip() if heading else body_mod.humanize(stem)
    date = fields.get("last_updated") or fields.get("created") or None
    if heading is None and date is None:
        warnings.append(
            "planning doc %s has neither a heading nor a date" % craft_rel
        )

    node = {
        "id": nid,
        "type": "planning",
        "title": title,
        "date": date,
        "status": None,
        "tags": [],
        "surface": None,
        "_path": craft_rel,
        "_name": fields.get("name", ""),
        "_warnings": warnings,
    }

    links = []
    for raw_path in body_mod.craft_paths(stripped):
        rel = body_mod.craft_relative(raw_path)
        if rel:
            links.append(resolve.raw_link(nid, "references", rel, "body_path"))
    for inner in body_mod.wikilinks(stripped):
        links.append(
            resolve.raw_link(nid, "references", inner, "body_wikilink")
        )
    return node, links, []
