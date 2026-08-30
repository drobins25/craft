"""Tweak parser: adhoc tweak records, current spec plus the legacy shape.

source_story is the messiest link field in any corpus - roughly half slug,
half free prose. Prose values become annotations, never dropped and never
guessed into edges. The legacy record generation (heading title, `date:`
field, no `name:`) parses best-effort with a warning.
"""

import os
import re

from . import body as body_mod
from . import identity
from .parse_fix import field_link

_LEGACY_TITLE_RE = re.compile(r"^# Tweak: (.+)$", re.M)


def parse(path, craft_rel, fields, body):
    stem = os.path.splitext(os.path.basename(craft_rel))[0]
    nid = identity.node_id("tweak", craft_rel)
    warnings = []

    if fields.get("name"):
        title = body_mod.humanize(fields["name"])
        date = fields.get("created") or None
    else:
        heading = _LEGACY_TITLE_RE.search(body_mod.strip_fenced(body))
        title = heading.group(1).strip() if heading else body_mod.humanize(stem)
        date = fields.get("date") or fields.get("created") or None
        warnings.append(
            "legacy tweak shape (no name field): %s" % craft_rel
        )

    node = {
        "id": nid,
        "type": "tweak",
        "title": title,
        "date": date,
        "status": fields.get("status") or None,
        "tags": [],
        "surface": fields.get("surface") or None,
        "_path": craft_rel,
        "_name": fields.get("name", ""),
        "_warnings": warnings,
    }

    links = []
    annotations = []

    field_link(nid, fields, "tweak", "source_story", links, annotations)
    field_link(nid, fields, "tweak", "mockup", links, annotations)
    field_link(nid, fields, "tweak", "dial", links, annotations)
    field_link(nid, fields, "tweak", "reapplies", links, annotations)
    field_link(nid, fields, "tweak", "grew_from", links, annotations)
    field_link(nid, fields, "tweak", "satisfied_todo", links, annotations)
    return node, links, annotations
