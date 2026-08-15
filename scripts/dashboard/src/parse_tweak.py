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
from . import resolve
from . import sentinels
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

    source_story = fields.get("source_story")
    if source_story is not None:
        if sentinels.is_sentinel(source_story):
            annotations.append(
                resolve.annotation(nid, "source_story", source_story, "sentinel")
            )
        elif _is_prose(source_story):
            annotations.append(
                resolve.annotation(nid, "source_story", source_story, "prose")
            )
        else:
            links.append(
                resolve.raw_link(
                    nid, "source_story", source_story, "source_story",
                    expect={"story"},
                )
            )

    field_link(nid, fields, "mockup", "mockup", links, annotations,
               expect={"mockup"})
    field_link(nid, fields, "dial", "dial", links, annotations,
               expect={"dial"})
    field_link(nid, fields, "reapplies", "reapplies", links, annotations,
               expect={"tweak"})
    field_link(nid, fields, "grew_from", "grew_from", links, annotations,
               expect={"tweak"})
    field_link(nid, fields, "satisfied_todo", "satisfied_todo", links,
               annotations, expect={"notebook"})
    return node, links, annotations


def _is_prose(value):
    """A slug never contains whitespace; anything with spaces left after
    stripping a parenthetical is prose."""
    stripped = re.sub(r"\([^)]*\)", "", str(value)).strip()
    return " " in stripped
