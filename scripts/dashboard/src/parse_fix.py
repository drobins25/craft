"""Fix parser: adhoc fix records from the flat fixes/ directory.

Fixes carry no cycle path, so cluster membership derives from the
source_cycle field - one edge, one kind. vocabulary.KINDS marks
source_cycle a membership kind for exactly this reason: the page clusters
a fix on the same edge that already carries "Came from cycle," rather than
a second edge built only for layout. Old records legitimately hold empty
link fields - those become sentinel annotations, never silently dropped.
"""

import os

from . import body as body_mod
from . import identity
from . import resolve
from . import sentinels

# Fields whose value is a polymorphic multi-target string (SPLIT
# enumerations, comma lists) rather than a single slug-or-prose value.
# resolve.extract_targets and assemble.link_pass split and resolve these
# candidate by candidate - prose_guarded_link's single-slug decision would
# misread the whole raw value as one prose fragment and drop it.
_MULTI_TARGET_FIELDS = frozenset({"graduated_to"})


def field_link(nid, fields, record_type, key, links, annotations):
    """Uniform frontmatter link-field policy: absent -> nothing; sentinel or
    empty -> sentinel annotation; a slug wearing a parenthetical or dash
    aside -> a link for the slug plus a prose annotation for the aside; a
    value that is still prose after the aside is stripped -> a prose
    annotation and no link. resolve.prose_guarded_link is the one place
    this decision lives - parse_story._dep_target uses the same rule.

    A multi-target field's raw value is passed straight through instead -
    it is not one slug to guard, it is a set of candidates the assembler
    splits later.

    Returns (link, note) - most callers ignore it."""
    if key not in fields:
        return None, None
    value = fields[key]
    if isinstance(value, list):
        # An unquoted template placeholder ([filled at the destination fork])
        # parses as a YAML flow list; no link field legitimately holds a real
        # list, so restore the bracketed form and let the sentinel rule refuse
        # it.
        value = "[" + ", ".join(str(v) for v in value) + "]"
    if key in _MULTI_TARGET_FIELDS:
        if sentinels.is_sentinel(value):
            note = resolve.annotation(nid, key, value, "sentinel")
            annotations.append(note)
            return None, note
        link = resolve.raw_link(nid, record_type, key, value)
        links.append(link)
        return link, None
    link, note = resolve.prose_guarded_link(nid, record_type, key, value)
    if link is not None:
        links.append(link)
    if note is not None:
        annotations.append(note)
    return link, note


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
    field_link(nid, fields, "fix", "source_story", links, annotations)
    field_link(nid, fields, "fix", "source_cycle", links, annotations)
    field_link(nid, fields, "fix", "satisfied_todo", links, annotations)
    return node, links, annotations
