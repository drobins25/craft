"""Node identity for the dashboard graph.

Ids are path-derived, not basename-derived: the corpus legitimately contains
same-named files in different directories (multiple README.md under
planning/), and every id doubles as a records/{id}.js mirror filename, so a
collision would silently overwrite a mirror.

Ids are lowercased at generation. On a case-insensitive filesystem (APFS
default) two ids differing only by case would collide as mirror filenames.
Resolving that collision is assemble._ensure_unique_id's job - it holds the
per-build seen-id map, so the suffix rule lives there and only there.
"""

import re

_UNSAFE_RE = re.compile(r"[^A-Za-z0-9._-]")
_EXT_RE = re.compile(r"\.(md|yaml|yml)$", re.IGNORECASE)


def node_id(record_type, craft_relative_path):
    """Pure transformation: (type, .craft-relative path) -> node id."""
    stem = _EXT_RE.sub("", craft_relative_path.strip("/"))
    parts = [_UNSAFE_RE.sub("-", p) for p in stem.split("/") if p]
    return (record_type + "--" + "--".join(parts)).lower()
