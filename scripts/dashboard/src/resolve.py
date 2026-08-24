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
_DATE_PREFIX_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-")
_SINGLE_DIGIT_PREFIX_RE = re.compile(r"^(\d)-(.+)$")

# The two record types the registry declares as living inside a folder
# rather than as a flat file (registry._RULES: mockups/*/record.md and
# cycles/*/cycle.yaml). A node whose filename is one of these is the one
# shape whose CONTAINING FOLDER is worth citing on its own.
_RECORD_FOLDER_FILENAMES = frozenset({"record.md", "cycle.yaml"})


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


def _not_records_key_matches(key, value):
    """True when key's `/`-separated segments equal value's LEADING
    segments, case-insensitively, with a `*` segment in key matching
    exactly one segment of value."""
    key_parts = key.lower().split("/")
    value_parts = value.lower().split("/")
    if len(value_parts) < len(key_parts):
        return False
    return all(k == "*" or k == v for k, v in zip(key_parts, value_parts))


def is_not_a_record(raw_value):
    """True when the value's leading path segments match a vocabulary.
    NOT_RECORDS segment pattern - a citation to a real .craft/ surface
    craft deliberately does not ingest as a record, not a failed lookup.
    A root-level filename key's whole value is a one-segment pattern, so
    the same match covers both shapes without a second code path."""
    value = str(raw_value).strip()
    return any(
        _not_records_key_matches(key, value) for key in vocabulary.NOT_RECORDS
    )


def failure_reason(raw_value, index=None, field=None, expect=None):
    """Why a value failed to resolve, in precedence order: sentinel if it
    is one; not-a-record if it names a NOT_RECORDS surface on a path field;
    wrong-type if it names a real record of a kind the field forbids;
    container if it strictly prefixes a registered node path; else
    unresolved.

    wrong-type sits above container because a value that names a real
    record is never a folder mention, and below not-a-record because a
    path field's excluded surface is the more specific fact. It requires
    both an index and an expect set - without either there is nothing to
    diagnose the value's type against - and fires only when the alias
    lookup itself found candidates, which is the evidence that the value
    names a real record rather than nothing at all.

    The container and wrong-type checks both need the alias index, so
    they only run when the caller has one to give - a bare sentinel check
    never requires it.
    """
    if sentinels.is_sentinel(raw_value):
        return "sentinel"
    if field in _PATH_FIELDS and is_not_a_record(raw_value):
        return "not-a-record"
    if index is not None and expect is not None and index.candidates(str(raw_value)):
        return "wrong-type"
    if index is not None and index.is_container(raw_value):
        return "container"
    return "unresolved"


class FrozenIndex(Exception):
    """Raised by register() once freeze_canonical() has run - a structural
    phase boundary rather than a reading-order convention. A maintainer
    who adds a tenth record type's canonical registration in the wrong
    half gets an exception here, not a silent shadow six months later."""


class AliasIndex:
    def __init__(self):
        self._aliases = {}
        self._meta = {}
        self._paths = []
        self._folder_aliases = {}
        self._frozen = False
        self._canonical_snapshot = frozenset()
        self._derived_report = {
            "proposed": 0,
            "suppressed_claimed": 0,
            "suppressed_multiple": 0,
            "registered": 0,
        }

    def register(self, alias, node_id):
        if self._frozen:
            raise FrozenIndex(
                "register() called after freeze_canonical(); "
                "use register_derived() in pass two"
            )
        alias = alias.strip().lower()
        if not alias:
            return
        self._aliases.setdefault(alias, [])
        if node_id not in self._aliases[alias]:
            self._aliases[alias].append(node_id)

    def freeze_canonical(self):
        """Close pass one. Snapshots every alias registered so far - the
        set register_derived() is forbidden to touch - and flips the
        index so a further register() call raises rather than quietly
        adding a second canonical form."""
        self._canonical_snapshot = frozenset(self._aliases.keys())
        self._frozen = True

    def alias_is_claimed(self, alias):
        """True when alias was registered during pass one, before the
        freeze - the fact pass two's unclaimed-only rule is checked
        against."""
        return alias.strip().lower() in self._canonical_snapshot

    def register_derived(self, alias, node_id):
        """Pass two's only write path. Refuses any alias already in the
        frozen canonical snapshot - a derived alias may never win a fight
        with a canonical one, and this is the second line of defence
        behind the caller's own unclaimed check in _register_derived.

        Raises BEFORE the freeze for the same reason register() raises
        after it - the phase boundary is structural, not a reading-order
        convention, and it is enforced from both ends. Called early, the
        canonical snapshot is still empty, so every alias would pass the
        unclaimed check and freeze_canonical() would then snapshot these
        derived forms AS canonical: the silent shadow this class exists
        to prevent, arriving through the other write path."""
        if not self._frozen:
            raise FrozenIndex(
                "register_derived() called before freeze_canonical(); "
                "canonical registration is not complete yet"
            )
        alias = alias.strip().lower()
        if not alias:
            return
        if alias in self._canonical_snapshot:
            return
        self._aliases.setdefault(alias, [])
        if node_id not in self._aliases[alias]:
            self._aliases[alias].append(node_id)

    def mark_record_folder(self, alias, node_id):
        """Track alias as a record-folder alias - the narrow subset the
        parent-directory retry is allowed to consult. Deliberately
        separate from the general alias table: a canonical alias can also
        look directory-shaped (a cycle's bare numbered dir name, say), and
        letting the retry match against ANY registered alias would turn a
        one-level parent lookup into a de facto substring scan. Only a
        node whose own file lives at <folder>/record.md or
        <folder>/cycle.yaml earns a folder-retry entry.
        """
        alias = alias.strip().lower()
        self._folder_aliases.setdefault(alias, [])
        if node_id not in self._folder_aliases[alias]:
            self._folder_aliases[alias].append(node_id)

    def folder_candidates(self, value):
        stem = str(value).strip().rstrip("/")
        return list(self._folder_aliases.get(stem.lower(), []))

    def set_derived_report(self, report):
        self._derived_report = dict(report)

    def derived_report(self):
        """{"proposed", "suppressed_claimed", "suppressed_multiple",
        "registered"} - a build-time measurement of how much the derived
        pass widened the index and how much of that widening it refused.
        In-memory only; never added to the graph envelope."""
        return dict(self._derived_report)

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


def _register_canonical(index, nodes):
    """Pass one: exact canonical surface forms, unchanged from before the
    two-pass split. Each node registers its id; its .craft-relative path
    with and without extension; its filename stem; its frontmatter
    name/slug; stories additionally the stem with the numeric prefix
    stripped; cycles additionally both the numbered directory name and
    the bare cycle name.
    """
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


def _derived_candidates(node):
    """The five miss-shape surface forms derivable from one node's own
    _path, type and _name - never the filesystem (AliasIndex.is_container's
    pure-lens law applies here too: derived from the in-memory path list
    only).

    S1: cited by type name plus stem, with and without the leading number
        - the "story-27-riff-the-game" shape a written-out citation takes
          when `27-riff-the-game` is what got registered.
    S2: a dated stem with its leading YYYY-MM-DD- removed - the exact form
        craft's own notebook helper writes into satisfied_todo.
    S3: for stories only, a single-digit leading story number zero-padded
        to two digits.
    S4: for stories under cycles/, cited relative to their cycle - by
        numbered directory and by bare cycle name - which also
        disambiguates a stem shared across cycles.
    S5: the containing folder of a record that lives at <folder>/<file>
        rather than as a flat file (a mockup's record.md, a cycle's
        cycle.yaml) - so a citation naming the folder resolves like
        naming the record itself.
    """
    path = node.get("_path", "")
    if not path:
        return set()
    ntype = node.get("type")
    root, _ext = os.path.splitext(path)
    stem = os.path.basename(root)
    stripped_stem = _NUM_PREFIX_RE.sub("", stem)
    candidates = set()

    # S1 is keyed off a record's own slug ("story-27-riff-the-game"). For the
    # two folder-based types the filename is a constant - every mockup's stem
    # is "record", every cycle's is "cycle" - so S1 there would propose the
    # meaningless "mockup-record" / "cycle-cycle" for every instance. A corpus
    # with several of each suppresses them by multiplicity, but one with a
    # single mockup would register it. S5 already covers what a citation to
    # these types actually looks like: the containing folder.
    if ntype and os.path.basename(path) not in _RECORD_FOLDER_FILENAMES:
        candidates.add("%s-%s" % (ntype, stem))
        candidates.add("%s-%s" % (ntype, stripped_stem))

    date_stripped = _DATE_PREFIX_RE.sub("", stem)
    if date_stripped != stem:
        candidates.add(date_stripped)

    if ntype == "story":
        m = _SINGLE_DIGIT_PREFIX_RE.match(stem)
        if m:
            candidates.add("0%s-%s" % (m.group(1), m.group(2)))

    if ntype == "story" and path.startswith("cycles/"):
        cycle_dir = _cycle_of_path(path)
        if cycle_dir:
            candidates.add("%s/%s" % (cycle_dir, stem))
            candidates.add(
                "%s/%s" % (_NUM_PREFIX_RE.sub("", cycle_dir), stem)
            )

    if os.path.basename(path) in _RECORD_FOLDER_FILENAMES:
        folder = os.path.dirname(path)
        if folder:
            candidates.add(folder)

    return candidates


def _folder_candidate(node):
    """The S5 folder-path candidate alone (lowercased), or None - used to
    mark which committed derived aliases the parent-directory retry may
    consult. A node earns one only when its own file is <folder>/record.md
    or <folder>/cycle.yaml; every other candidate resolve() finds through
    the ordinary alias table instead."""
    path = node.get("_path", "")
    if not path or os.path.basename(path) not in _RECORD_FOLDER_FILENAMES:
        return None
    folder = os.path.dirname(path)
    return folder.strip().lower() if folder else None


def _register_derived(index, nodes):
    """Pass two: COLLECT every node's derived candidates into one
    alias -> {node id} map first, then commit only the aliases that are
    (a) absent from the frozen canonical snapshot and (b) proposed by
    exactly one node.

    Collecting before committing is what makes the outcome independent of
    node order: checking against pass one's frozen snapshot alone stops a
    derived alias from beating a canonical one, but two derived aliases
    from different nodes could still race each other inside pass two if
    each committed as soon as it found itself unclaimed. Requiring a
    single proposer, decided from the complete map, closes that gap
    without depending on which node happened to run first.
    """
    proposals = {}
    folder_keys = set()
    for node in nodes:
        folder_candidate = _folder_candidate(node)
        for alias in _derived_candidates(node):
            key = alias.strip().lower()
            if not key:
                continue
            proposals.setdefault(key, set()).add(node["id"])
            if folder_candidate is not None and key == folder_candidate:
                folder_keys.add(key)

    claimed = 0
    multiple = 0
    registered = 0
    for alias, node_ids in proposals.items():
        if index.alias_is_claimed(alias):
            claimed += 1
            continue
        if len(node_ids) > 1:
            multiple += 1
            continue
        node_id = next(iter(node_ids))
        index.register_derived(alias, node_id)
        if alias in folder_keys:
            index.mark_record_folder(alias, node_id)
        registered += 1

    index.set_derived_report(
        {
            "proposed": len(proposals),
            "suppressed_claimed": claimed,
            "suppressed_multiple": multiple,
            "registered": registered,
        }
    )


def build_index(nodes):
    """Build the alias index from the COMPLETE node set, in two passes
    with a freeze between them: register canonical forms exactly as
    before, freeze, then register derived forms - see _register_canonical
    and _register_derived for what each half writes.
    """
    index = AliasIndex()
    _register_canonical(index, nodes)
    index.freeze_canonical()
    _register_derived(index, nodes)
    return index


def resolve(index, raw_value, from_node=None, expect_types=None):
    """Resolve one reference string -> node id, or None.

    Order: sentinel refusal; exact alias lookup; if THAT lookup found zero
    candidates and the value contains a "/", one retry against the value's
    parent directory - exact, one level, and scoped to registered
    record-folder aliases only (AliasIndex.folder_candidates, not the
    general alias table), so a bare directory name that merely happens to
    match a canonical alias can never turn this into a substring scan;
    never attempted when the exact lookup found candidates that the
    expect_types filter below then emptied, so it can never mask a
    wrong-type diagnosis; expect_types filter; deterministic ambiguity
    tie-break (same cycle as from_node, then latest date, then smallest
    id). No fuzzy or substring matching, ever.
    """
    if sentinels.is_sentinel(raw_value):
        return None
    value = str(raw_value)
    candidates = index.candidates(value)
    if not candidates and "/" in value:
        parent = value.rsplit("/", 1)[0]
        candidates = index.folder_candidates(parent)
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
    """Strip a wrapping backtick pair, parenthetical asides, and a
    trailing ' - prose' suffix from a would-be slug.

    Returns (clean, decorated): clean is the surviving text with
    surrounding whitespace trimmed; decorated is True only when something
    was actually DISCARDED. A slug never contains whitespace or
    parentheses - this is the one place that rule is enforced, so every
    field that mixes a real reference with free prose applies it the same
    way. A matched pair of surrounding backticks is unwrapped rather than
    discarded - the text inside survives whole - so it does not set
    decorated; marking it decorated would emit a spurious prose annotation
    for every backticked citation, which is the opposite of what quoting a
    slug is for.
    """
    original = str(value).strip()
    slug = original
    decorated = False
    if len(slug) >= 2 and slug.startswith("`") and slug.endswith("`"):
        slug = slug[1:-1].strip()
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
            part = part.strip().strip(".:`")
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
