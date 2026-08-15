"""Reference resolution: raw reference strings -> node ids, or annotations.

Records cite each other in many surface forms - bare names, numbered
filenames, paths, wikilinks, slugs with trailing prose. Every node registers
every surface form it can be cited by in an alias index built once per build;
resolution is an exact lookup plus a deterministic tie-break. Never fuzzy,
never substring - a value that does not resolve exactly becomes an
annotation, not a guessed edge.
"""

import os
import re

from . import sentinels


_NUM_PREFIX_RE = re.compile(r"^\d+-")
_WIKILINK_RE = re.compile(r"\[\[([^\]]+)\]\]")
_PAREN_RE = re.compile(r"\([^)]*\)")
_ENUM_SPLIT_RE = re.compile(r"\(\d+\)")


def raw_link(source_id, kind, raw_value, field, expect=None):
    """A parser-emitted, not-yet-resolved reference.

    expect optionally narrows the node types this field may point at (the
    narrowest set the field's grammar allows), applied at resolution.
    """
    link = {
        "source_id": source_id,
        "kind": kind,
        "raw_value": raw_value,
        "field": field,
    }
    if expect is not None:
        link["expect"] = set(expect)
    return link


def annotation(source_id, field, value, reason):
    """A reference-shaped value that did not become an edge.

    reason is one of: sentinel, unresolved, out-of-scope-type, prose.
    """
    return {
        "source_id": source_id,
        "field": field,
        "value": value,
        "reason": reason,
    }


def failure_reason(raw_value):
    """Why a value failed to resolve: sentinel if it is one, else unresolved."""
    return "sentinel" if sentinels.is_sentinel(raw_value) else "unresolved"


class AliasIndex:
    def __init__(self):
        self._aliases = {}
        self._meta = {}

    def register(self, alias, node_id):
        alias = alias.strip().lower()
        if not alias:
            return
        self._aliases.setdefault(alias, [])
        if node_id not in self._aliases[alias]:
            self._aliases[alias].append(node_id)

    def register_node(self, node_id, node_type, date, cycle):
        self._meta[node_id] = {
            "type": node_type,
            "date": date or "",
            "cycle": cycle,
        }

    def candidates(self, alias):
        return list(self._aliases.get(alias.strip().lower(), []))

    def meta(self, node_id):
        return self._meta.get(node_id, {"type": None, "date": "", "cycle": None})


def _cycle_of_path(path):
    parts = (path or "").split("/")
    if len(parts) >= 2 and parts[0] == "cycles":
        return parts[1]
    return None


def build_index(nodes):
    """Build the alias index from the COMPLETE node set.

    Each node registers: its canonical id; its .craft-relative path with and
    without extension; its filename stem; its frontmatter name/slug; stories
    additionally the stem with the numeric prefix stripped; cycles
    additionally both the numbered directory name and the bare cycle name.
    """
    index = AliasIndex()
    for node in nodes:
        nid = node["id"]
        ntype = node.get("type")
        path = node.get("_path", "")
        name = node.get("_name", "")
        index.register_node(nid, ntype, node.get("date"), _cycle_of_path(path))

        index.register(nid, nid)
        if path:
            index.register(path, nid)
            root, _ext = os.path.splitext(path)
            index.register(root, nid)
            stem = os.path.basename(root)
            index.register(stem, nid)
            if ntype == "story":
                index.register(_NUM_PREFIX_RE.sub("", stem), nid)
            if ntype == "cycle":
                cycle_dir = _cycle_of_path(path)
                if cycle_dir:
                    index.register(cycle_dir, nid)
                    index.register(_NUM_PREFIX_RE.sub("", cycle_dir), nid)
        if name:
            index.register(name, nid)
    return index


def resolve(index, raw_value, from_node=None, expect_types=None):
    """Resolve one reference string -> node id, or None.

    Order: sentinel refusal; exact alias lookup; expect_types filter;
    deterministic ambiguity tie-break (same cycle as from_node, then latest
    date, then smallest id). No fuzzy or substring matching, ever.
    """
    if sentinels.is_sentinel(raw_value):
        return None
    candidates = index.candidates(str(raw_value))
    if expect_types is not None:
        candidates = [
            c for c in candidates if index.meta(c)["type"] in expect_types
        ]
    if not candidates:
        return None
    if len(candidates) == 1:
        return candidates[0]

    from_cycle = None
    if isinstance(from_node, dict):
        from_cycle = _cycle_of_path(from_node.get("_path", ""))
    if from_cycle:
        same_cycle = [
            c for c in candidates if index.meta(c)["cycle"] == from_cycle
        ]
        if same_cycle:
            candidates = same_cycle
        if len(candidates) == 1:
            return candidates[0]

    best_date = max(index.meta(c)["date"] for c in candidates)
    latest = [c for c in candidates if index.meta(c)["date"] == best_date]
    return min(latest)


def extract_targets(raw_value):
    """Split a polymorphic multi-target value into candidate reference
    strings, in source order.

    Handles wikilink brackets, parenthetical suffixes, semicolon and comma
    lists, and numbered (1)/(2) enumerations. Sentinels yield no candidates.
    The caller resolves each candidate and preserves the unresolved remainder
    as annotation text.
    """
    if sentinels.is_sentinel(raw_value):
        return []
    s = str(raw_value)
    s = _WIKILINK_RE.sub(r"\1", s)
    segments = _ENUM_SPLIT_RE.split(s)
    candidates = []
    for segment in segments:
        segment = _PAREN_RE.sub("", segment)
        for part in re.split(r"[;,]", segment):
            part = part.strip().strip(".:")
            if not part:
                continue
            if part.lower() in ("split", "and", "&"):
                continue
            if sentinels.is_sentinel(part):
                continue
            candidates.append(part)
    return candidates
