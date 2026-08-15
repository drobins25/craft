"""Fix parser: adhoc fix records from the flat fixes/ directory.

Fixes carry no cycle path, so era membership derives from the source_cycle
field. Old records legitimately hold empty link fields - those become
sentinel annotations, never silently dropped.
"""

import os

from . import body as body_mod
from . import identity
from . import resolve
from . import sentinels


def field_link(nid, fields, key, kind, links, annotations, expect=None):
    """Uniform frontmatter link-field policy: absent -> nothing; sentinel or
    empty -> sentinel annotation; otherwise a raw link."""
    if key not in fields:
        return
    value = fields[key]
    if isinstance(value, list):
        # An unquoted template placeholder ([filled at the destination fork])
        # parses as a YAML flow list; no link field legitimately holds a real
        # list, so restore the bracketed form and let the sentinel rule refuse
        # it.
        value = "[" + ", ".join(str(v) for v in value) + "]"
    if sentinels.is_sentinel(value):
        annotations.append(resolve.annotation(nid, key, value, "sentinel"))
        return
    links.append(resolve.raw_link(nid, kind, value, key, expect=expect))


def parse(path, craft_rel, fields, body):
    stem = os.path.splitext(os.path.basename(craft_rel))[0]
    nid = identity.node_id("fix", craft_rel)
    node = {
        "id": nid,
        "type": "fix",
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
    field_link(
        nid, fields, "source_story", "source_story", links, annotations,
        expect={"story"},
    )
    field_link(
        nid, fields, "source_cycle", "source_cycle", links, annotations,
        expect={"cycle"},
    )
    if fields.get("source_cycle") and not sentinels.is_sentinel(
        fields["source_cycle"]
    ):
        links.append(
            resolve.raw_link(
                nid, "belongs_to", fields["source_cycle"], "source_cycle",
                expect={"cycle"},
            )
        )
    field_link(
        nid, fields, "satisfied_todo", "satisfied_todo", links, annotations,
        expect={"notebook"},
    )
    return node, links, annotations
