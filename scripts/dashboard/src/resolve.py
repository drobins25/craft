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
from . import vocabulary


_NUM_PREFIX_RE = re.compile(r"^\d+-")
_WIKILINK_RE = re.compile(r"\[\[([^\]]+)\]\]")
_PAREN_RE = re.compile(r"\([^)]*\)")
_ENUM_SPLIT_RE = re.compile(r"\(\d+\)")


def raw_link(source_id, record_type, field, raw_value):
    """A parser-emitted, not-yet-resolved reference.

    The kind, the type filter and the invert flag all come from
    vocabulary.kind_for(record_type, field) - a parser cannot invent a kind
    or forget a field's type filter, because the only way to get one is to
    ask the definition, and it raises UnknownField on anything it does not
    know rather than handing back a guess.
    """
    spec = vocabulary.kind_for(record_type, field)
    link = {
        "source_id": source_id,
        "kind": spec["kind"],
        "raw_value": raw_value,
        "field": field,
        "invert": spec["invert"],
    }
    if spec["expect"] is not None:
        link["expect"] = set(spec["expect"])
    return link


def annotation(source_id, field, value, reason):
    """A reference-shaped value that did not become an edge.

    reason must be a member of vocabulary.REASONS - this is the one place
    that gate lives, mirroring kind_for's discipline: an unregistered
    reason string is a bug in the caller, not a new reason quietly
    shipping unvalidated.
    """
    if reason not in vocabulary.REASONS:
        raise vocabulary.UnknownReason(
            "no vocabulary entry for reason %r" % (reason,)
        )
    return {
        "source_id": source_id,
        "field": field,
        "value": value,
        "reason": reason,
    }


# Fields whose values are .craft-relative paths rather than record slugs -
# the only shapes a NOT_RECORDS directory name can meaningfully prefix.
# Scoped deliberately: a dependency slug that happens to equal a directory
# name ("design", "graph") is still a plain unresolved lookup, never a
# not-a-record citation.
_PATH_FIELDS = frozenset({"body_path", "reference_materials"})


def is_not_a_record(raw_value):
    """True when the value's first path segment names a vocabulary.
    NOT_RECORDS directory or root-level filename - a citation to a real
    .craft/ surface craft deliberately does not ingest as a record, not a
    failed lookup. A root file's first segment is the whole value, so the
    same lookup covers both shapes without a second code path."""
    first = str(raw_value).strip().split("/", 1)[0].lower()
    return first in vocabulary.NOT_RECORDS


def failure_reason(raw_value, index=None, field=None):
    """Why a value failed to resolve: sentinel if it is one, not-a-record if
    it names a NOT_RECORDS surface, container if it strictly prefixes a
    registered node path, else unresolved.

    The container check needs the alias index, so it only runs when the
    caller has one to give - a bare sentinel check never requires it.
    """
    if sentinels.is_sentinel(raw_value):
        return "sentinel"
    if field in _PATH_FIELDS and is_not_a_record(raw_value):
        return "not-a-record"
    if index is not None and index.is_container(raw_value):
        return "container"
    return "unresolved"


class AliasIndex:
    def __init__(self):
        self._aliases = {}
        self._meta = {}
        self._paths = []

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

    def register_path(self, path):
        """Record a node's .craft-relative path for the container check.

        Kept separate from the alias table: aliases include stems and names
        that are not paths at all, and prefixing against those would let an
        unrelated slug get misread as a folder.
        """
        if path:
            self._paths.append(path)

    def candidates(self, alias):
        return list(self._aliases.get(alias.strip().lower(), []))

    def meta(self, node_id):
        return self._meta.get(node_id, {"type": None, "date": "", "cycle": None})

    def is_container(self, value):
        """True when value names a directory a registered node lives under.

        Derived from the in-memory path list only - never from the
        filesystem. A value that resolves to a real node never reaches this
        check, because callers only run it after an exact alias lookup has
        already failed.
        """
        stem = str(value).strip().rstrip("/")
        if not stem:
            return False
        prefix = stem.lower() + "/"
        return any(path.lower().startswith(prefix) for path in self._paths)


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
            index.register_path(path)
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


def strip_decoration(value):
    """Strip parenthetical asides and a trailing ' - prose' suffix from a
    would-be slug.

    Returns (clean, decorated): clean is the surviving text with
    surrounding whitespace trimmed; decorated is True only when something
    was actually removed. A slug never contains whitespace or parentheses -
    this is the one place that rule is enforced, so every field that mixes
    a real reference with free prose applies it the same way.
    """
    original = str(value).strip()
    slug = original
    decorated = False
    if _PAREN_RE.search(slug):
        decorated = True
        slug = _PAREN_RE.sub("", slug).strip()
    if " - " in slug:
        decorated = True
        slug = slug.split(" - ", 1)[0].strip()
    return slug, decorated


def prose_guarded_link(source_id, record_type, field, raw_value):
    """A frontmatter link field that may hold a real slug, free prose, or a
    slug wearing a parenthetical/dash aside - the shape source_story,
    source_cycle and satisfied_todo all carry in practice.

    Returns (link_or_None, annotation_or_None). A clean slug yields a link
    and no annotation; a value that is still prose after decoration is
    stripped yields an annotation and no link; a decorated value that
    cleans to a real slug yields BOTH - the link for the surviving slug and
    a prose annotation preserving the discarded aside, so the aside stays
    visible instead of silently vanishing. A value that reduces to a
    sentinel (bare, or once its aside is stripped - "none (design pattern
    shift)" is exactly this shape) always yields a sentinel annotation and
    never a link, even if it was also decorated.
    """
    if sentinels.is_sentinel(raw_value):
        return None, annotation(source_id, field, raw_value, "sentinel")
    slug, decorated = strip_decoration(raw_value)
    if sentinels.is_sentinel(slug):
        return None, annotation(source_id, field, raw_value, "sentinel")
    if not slug or " " in slug:
        return None, annotation(source_id, field, raw_value, "prose")
    link = raw_link(source_id, record_type, field, slug)
    note = (
        annotation(source_id, field, raw_value, "prose") if decorated else None
    )
    return link, note


def extract_targets(raw_value):
    """Split a polymorphic multi-target value into candidate reference
    strings, in source order.

    Handles wikilink brackets, parenthetical suffixes, semicolon and comma
    lists, and numbered (1)/(2) enumerations. Sentinels yield no candidates.
    A slug never contains whitespace (the same rule parse_story enforces on
    dependency targets); a segment that still has whitespace after
    decoration-stripping is a prose fragment, not a second target, and is
    dropped rather than handed to the resolver as a guaranteed miss. The
    caller resolves each surviving candidate and preserves the unresolved
    remainder as annotation text.
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
            if " " in part:
                continue
            candidates.append(part)
    return candidates
