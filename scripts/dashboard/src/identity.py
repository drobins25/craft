"""Node identity for the dashboard graph.

Ids are path-derived, not basename-derived: the corpus legitimately contains
same-named files in different directories (multiple README.md under
planning/), and every id doubles as a records/{id}.js mirror filename, so a
collision would silently overwrite a mirror.

Ids are lowercased at generation. On a case-insensitive filesystem (APFS
default) two ids differing only by case would collide as mirror filenames;
case-fold collisions get a deterministic numeric suffix plus a warning.
"""

import re

_UNSAFE_RE = re.compile(r"[^A-Za-z0-9._-]")
_EXT_RE = re.compile(r"\.(md|yaml|yml)$", re.IGNORECASE)


def node_id(record_type, craft_relative_path):
    """Pure transformation: (type, .craft-relative path) -> node id."""
    stem = _EXT_RE.sub("", craft_relative_path.strip("/"))
    parts = [_UNSAFE_RE.sub("-", p) for p in stem.split("/") if p]
    return (record_type + "--" + "--".join(parts)).lower()


class IdAllocator:
    """Allocates unique ids across a whole build.

    Distinct paths normally yield distinct ids; when two paths collide after
    case-folding and sanitization, the second (in allocation order) gets a
    numeric suffix and a warning. Callers allocate in sorted discovery order,
    which makes the suffix assignment deterministic.
    """

    def __init__(self):
        self._taken = {}

    def allocate(self, record_type, craft_relative_path):
        """Return (id, warning_or_None)."""
        base = node_id(record_type, craft_relative_path)
        if base not in self._taken:
            self._taken[base] = craft_relative_path
            return base, None
        n = 2
        while "%s--%d" % (base, n) in self._taken:
            n += 1
        nid = "%s--%d" % (base, n)
        self._taken[nid] = craft_relative_path
        warning = (
            "id collision after case-folding: %r and %r both normalize to %r; "
            "using %r" % (self._taken[base], craft_relative_path, base, nid)
        )
        return nid, warning
