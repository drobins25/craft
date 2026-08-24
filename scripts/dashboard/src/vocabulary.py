"""Craft's record vocabulary: the one place a relationship kind, a display
word, a record type or a link field is written down.

This module is the bottom of the dependency ladder - stdlib only, nothing
from `src/` - so every other module can depend on it without a cycle.

The registry that used to hold this vocabulary (`coverage.HANDLED` plus two
hand-written tables in the browser page) rotted because its test proved only
the input axis: every field a parser can see must be routed somewhere. The
output axis - the display words a browser prints - was never gated, which is
exactly where the drift showed up: five relationship kinds and 136 statuses
on this project's own graph print the raw internal string because no table
had an entry for them.

Two structures carry the whole vocabulary:

- `KINDS` says what a relationship IS and how it reads from either end -
  the outbound word, the inbound word, which record types can sit at each
  end, whether the kind is a membership edge (clusters a card visually) or
  a lineage edge (counted in the "born from" stat), and whether inversion
  is meaningful for it at all.
- `FIELDS` says what a parser is allowed to route through `raw_link` -
  one entry per `(record_type, field)` pair a parser actually emits a link
  for. `kind_for` is the enforcement point: an unregistered pair raises
  rather than falling back to a guessed kind, which is what makes the wrong
  shape unexpressible instead of merely undocumented.

`blocked_by` does not appear in `KINDS` at all. A story's `**Blocked by:**`
marker is a `blocks` FIELD entry with `invert=True` - the definition marks
which end of the dependency wrote the marker, not a second kind pointing
the opposite way. That is what collapses the 13 inverse-pair twins in this
project's live graph into 13 single edges once the parsers read this file
instead of naming kinds themselves.
"""

# The nine record types that become nodes, in registry.PARSERS's order.
RECORD_TYPES = (
    "story",
    "cycle",
    "planning",
    "fix",
    "tweak",
    "notebook",
    "riff",
    "mockup",
    "dial",
)

# The closed set of reasons a reference-shaped value can fail to become an
# edge. This is the one vocabulary axis the rest of this module did not
# make unexpressible until now: every other list here (kinds, fields,
# statuses) has a gate that fails on an unregistered value, while a reason
# string lived as a docstring list in resolve.py plus bare literals spread
# across the parsers - nothing stopped a typo'd reason from shipping
# silently. resolve.annotation raises on anything not in this set.
REASONS = frozenset(
    {
        "sentinel",
        "unresolved",
        "out-of-scope-type",
        "prose",
        "container",
        "not-a-record",
        "wrong-type",
        "self-reference",
    }
)

# .craft/ surfaces that are never a record source, each with the reason a
# future maintainer can act on. Naming an exclusion turns "nobody thought
# about it" into a decision (Decision 7's RULED_OUT idiom, one level up).
#
# A key is a `/`-separated SEGMENT PATTERN: a plain segment matches itself
# and a `*` segment matches exactly one path segment. A key matches a value
# when the key's segments equal the value's LEADING segments, case-
# insensitively - "design" matches "design/tokens.yaml", "notebook/assets"
# matches "notebook/assets/x.md", and "mockups/*/rounds" matches
# "mockups/<anything>/rounds/round-1.html" through the wildcard middle
# segment. A bare root-level filename ("project.md") is a one-segment key
# whose value has no directory to be a segment of, so the same rule covers
# it without a second code path. resolve.is_not_a_record owns the match.
NOT_RECORDS = {
    "graph": "builder output - .craft/graph/ is written by the build, "
    "never read as a record source (registry.py skip list)",
    "dashboard": "dashboard output - .craft/dashboard/ is written by the "
    "build, never read as a record source (registry.py skip list)",
    "checkpoints": "state, not records - not nodes (alignment)",
    "requests": "queued user requests are not nodes in v1 (alignment)",
    "design": "visual DNA (tokens, locked patterns) - values, not records "
    "(Decision 8: hue and visual values stay in tokens.yaml)",
    "projects": "cross-project pointer state, not authored records",
    "research": "free-form investigation prose, no declared record shape",
    "workflows": "workflow definitions and sessions carry real path "
    "references but are out of scope for v1 - not in the registry",
    "map": "Living Map's per-file extraction cache and index - derived "
    "state, not an authored record",
    "docs": "generated doc-drift briefs and review findings - build "
    "output, not records",
    "inspiration": "reference screenshots and sites collected for design "
    "work, not records",
    "project.md": "project DNA (stack, conventions) - a value file, not a "
    "record, and never parsed by registry._RULES",
    "settings.yaml": "project configuration - a value file, not a record",
    "quality.yaml": "quality-gate configuration - a value file, not a "
    "record",
    "dashboard.html": "the shipped browser page itself - build output, not "
    "a record",
    "notebook/assets": "attachments a notebook idea or todo links to - "
    "craft does not ingest .craft/notebook/assets/ as a record source",
    "mockups/*/rounds": "per-round screenshots inside a mockup folder - "
    "craft does not ingest a mockup's rounds/ as a record source",
    "analysis": "quality-gate analysis output (templates/analysis/pending "
    "ships the shape) - craft does not ingest .craft/analysis/ as a "
    "record source",
}

# One row per Content Direction relationship kind, in the table's order so
# the table and this literal can be diffed by eye. `sources`/`targets` are
# the record types that can sit at the outbound/inbound end of an edge of
# this kind - the type-level invariant the uniqueness gate below checks
# against, independent of any single field's narrower `expect` set.
#
# No `invert` key here: inversion is a property of a FIELD (see FIELDS
# below), never of the kind itself - a kind is inverted when the record
# that writes the field is the wrong end of the relationship the kind
# names, and `blocks` is the only one, via the story `blocked_by` field.
KINDS = {
    "belongs_to": {
        "out": "Part of",
        "in": "Contains",
        "sources": frozenset({"story", "fix"}),
        "targets": frozenset({"cycle"}),
        "membership": True,
        "lineage": False,
    },
    "blocks": {
        "out": "Blocks",
        "in": "Blocked by",
        "sources": frozenset({"story"}),
        "targets": frozenset({"story"}),
        "membership": False,
        "lineage": False,
    },
    "reapplies": {
        "out": "Re-applies",
        "in": "Re-applied by",
        "sources": frozenset({"tweak"}),
        "targets": frozenset({"tweak"}),
        "membership": False,
        "lineage": True,
    },
    "references": {
        "out": "Points to",
        "in": "Pointed to by",
        "sources": frozenset(
            {"story", "cycle", "planning", "riff", "notebook"}
        ),
        # references carries no type filter - any record can cite any
        # record, so the target set is every node-producing type.
        "targets": frozenset(RECORD_TYPES),
        "membership": False,
        "lineage": False,
    },
    "source_story": {
        "out": "Came from story",
        "in": "Gave rise to",
        "sources": frozenset({"fix", "tweak"}),
        "targets": frozenset({"story"}),
        "membership": False,
        "lineage": False,
    },
    "source_cycle": {
        "out": "Came from cycle",
        "in": "Gave rise to",
        "sources": frozenset({"fix"}),
        "targets": frozenset({"cycle"}),
        "membership": True,
        "lineage": False,
    },
    "graduated_to": {
        "out": "Graduated into",
        "in": "Graduated from",
        "sources": frozenset({"mockup", "notebook", "dial"}),
        "targets": frozenset({"story", "tweak", "notebook", "fix", "dial"}),
        "membership": False,
        "lineage": True,
    },
    "grew_from": {
        "out": "Grew from",
        "in": "Became",
        "sources": frozenset({"story", "tweak"}),
        "targets": frozenset({"tweak"}),
        "membership": False,
        "lineage": True,
    },
    "satisfied_todo": {
        "out": "Answers",
        "in": "Answered by",
        "sources": frozenset({"fix", "tweak"}),
        "targets": frozenset({"notebook"}),
        "membership": False,
        "lineage": True,
    },
    "mockup": {
        "out": "Designed in",
        "in": "Design for",
        "sources": frozenset({"story", "tweak"}),
        "targets": frozenset({"mockup"}),
        "membership": False,
        "lineage": False,
    },
    "dial": {
        "out": "Tuned from",
        "in": "Became",
        "sources": frozenset({"tweak"}),
        "targets": frozenset({"dial"}),
        "membership": False,
        "lineage": False,
    },
    "origin": {
        "out": "Sparked by",
        "in": "Sparked",
        "sources": frozenset({"mockup"}),
        "targets": frozenset({"tweak"}),
        "membership": False,
        "lineage": False,
    },
}

# One entry per (record_type, field) pair a parser can see, PLUS the pairs
# a parser only ever emits an ANNOTATION for (no "kind" key at all -
# kind_for still raises UnknownField for these; a pair being declared here
# is not a pair being linkable). Declaring both kinds in one place is what
# lets coverage.HANDLED collapse to a comprehension over this dict instead
# of a second, hand-kept module.
#
# `expect` narrows the node types a field's grammar allows - the type
# filter Decision 5 asks for, arriving as a property of the field so no
# call site can forget it. Absent means no type filter. `invert=True`
# marks a field where the record declaring it is the inbound end of the
# kind, not the outbound end - `blocked_by` is the only one. Both keys are
# written only where they diverge from their default (None, False) - 27 of
# 28 linkable entries agreed on both, and writing them out every time
# camouflaged the one row that matters. kind_for is where the defaults are
# filled back in, so its return shape never changes.
#
# `inventory` names the field the way __fixtures__/link_inventory.py spells
# it, when that differs from the parser's own field key (the dependency
# markers by their prose heading, and the body-scan fields in the plural
# the templates use). Absent means the names already match. `None` means
# this pair folds into a different one for inventory purposes - a story's
# cycle membership is one inventory entry regardless of whether it came
# from the directory path or the frontmatter `cycle:` field, so the
# path-derived entry declares no inventory name of its own and
# ("story", "cycle") carries it instead.
FIELDS = {
    ("story", "path"):
        {"kind": "belongs_to", "expect": frozenset({"cycle"}), "inventory": None},
    ("story", "cycle"):
        {"kind": "belongs_to", "expect": frozenset({"cycle"})},
    ("story", "mockup"):
        {"kind": "mockup", "expect": frozenset({"mockup"})},
    ("story", "grew_from"):
        {"kind": "grew_from", "expect": frozenset({"tweak"})},
    ("story", "blocked_by"): {
        "kind": "blocks",
        "expect": frozenset({"story"}),
        "invert": True,
        "inventory": "dependencies_blocked_by",
    },
    ("story", "blocks"): {
        "kind": "blocks",
        "expect": frozenset({"story"}),
        "inventory": "dependencies_blocks",
    },
    ("story", "reference_materials"):
        {"kind": "references"},
    ("story", "body_path"):
        {"kind": "references", "inventory": "body_paths"},
    ("story", "body_wikilink"):
        {"kind": "references", "inventory": "body_wikilinks"},
    ("story", "element_binding_table"): {},
    ("fix", "source_story"):
        {"kind": "source_story", "expect": frozenset({"story"})},
    ("fix", "source_cycle"):
        {"kind": "source_cycle", "expect": frozenset({"cycle"})},
    ("fix", "satisfied_todo"):
        {"kind": "satisfied_todo", "expect": frozenset({"notebook"})},
    ("tweak", "source_story"):
        {"kind": "source_story", "expect": frozenset({"story"})},
    ("tweak", "mockup"):
        {"kind": "mockup", "expect": frozenset({"mockup"})},
    ("tweak", "dial"):
        {"kind": "dial", "expect": frozenset({"dial"})},
    ("tweak", "reapplies"):
        {"kind": "reapplies", "expect": frozenset({"tweak"})},
    ("tweak", "grew_from"):
        {"kind": "grew_from", "expect": frozenset({"tweak"})},
    ("tweak", "satisfied_todo"):
        {"kind": "satisfied_todo", "expect": frozenset({"notebook"})},
    ("mockup", "graduated_to"): {
        "kind": "graduated_to",
        "expect": frozenset({"story", "tweak", "notebook"}),
    },
    ("mockup", "origin"):
        {"kind": "origin", "expect": frozenset({"tweak"})},
    ("notebook", "graduated_to"): {
        "kind": "graduated_to",
        "expect": frozenset({"fix", "tweak", "story", "dial"}),
    },
    ("notebook", "source"):
        {"kind": "references"},
    ("dial", "graduated_to"): {
        "kind": "graduated_to",
        "expect": frozenset({"tweak", "story", "notebook"}),
    },
    ("cycle", "source_concept"):
        {"kind": "references"},
    ("cycle", "stories_membership"): {},
    ("planning", "body_path"):
        {"kind": "references", "inventory": "body_paths"},
    ("planning", "body_wikilink"):
        {"kind": "references", "inventory": "body_wikilinks"},
    ("riff", "body_path"):
        {"kind": "references", "inventory": "body_paths"},
    ("riff", "body_wikilink"):
        {"kind": "references", "inventory": "body_wikilinks"},
    ("mockup", "solidify_outcome"): {},
}

# Stored status value -> display word. Every Content Direction row verbatim,
# plus `proposed` (skills/adhoc/references/fix.md writes it; the corpus
# carries `proposal`; both are real, only one had a word until now).
# `pending` is deliberately absent: craft has no record-writing path that
# emits it (the only source hits are commented-out template examples).
STATUSES = {
    "complete": "Completed",
    "active": "In progress",
    "planning": "Planning",
    "ready": "Ready",
    "open": "Open",
    "accepted": "Accepted",
    "applied": "Applied",
    "reverted": "Reverted",
    "superseded": "Superseded",
    "validated": "Validated",
    "escalated": "Escalated",
    "done": "Done",
    "graduated": "Graduated",
    "converging": "Converging",
    "converged": "Converged",
    "parked": "Parked",
    "abandoned": "Abandoned",
    "backlog": "In backlog",
    "revised-then-accepted": "Revised & accepted",
    "proposal": "Proposed",
    "proposed": "Proposed",
    "graduated-story": "Graduated",
    "graduated-tweak": "Graduated",
}

# Dial records carry no status by design - this is the status slot's other
# source, worded as a session outcome rather than a condition.
DIAL_OUTCOMES = {
    "nothing": "Unchanged",
    "tweak": "Tweaked",
    "story": "Planned",
    "todo": "Parked",
}


class UnknownField(Exception):
    """Raised by kind_for when a parser asks the vocabulary about a
    (record_type, field) pair it has never registered. There is no
    default kind to fall back to - an unregistered pair is a bug in the
    parser, not a gap the vocabulary should paper over."""


class UnknownReason(Exception):
    """Raised by resolve.annotation when a caller passes a reason string
    outside REASONS. Mirrors UnknownField's discipline for the one
    vocabulary axis that used to ship as a docstring list plus bare string
    literals: an unregistered reason is a typo to fix, not a sixth reason
    quietly joining the set."""


def kind_for(record_type, field):
    """The (record_type, field) pair's link spec, with defaults filled in -
    {"kind": str, "expect": frozenset|None, "invert": bool} - or raise
    UnknownField.

    This is the mechanism that makes an undeclared field unexpressible: a
    parser cannot invent a kind string, because the only way to get one is
    to ask this function, and it refuses anything it does not know. A pair
    declared in FIELDS with no "kind" - one that a parser only ever emits
    an annotation for - refuses here too: being declared for the coverage
    inventory is not the same as being routable through raw_link. The
    return shape is always these exact three keys, regardless of how few
    of them the FIELDS literal itself bothered to write out.
    """
    spec = FIELDS.get((record_type, field))
    if spec is None or "kind" not in spec:
        raise UnknownField(
            "no vocabulary entry for (%r, %r)" % (record_type, field)
        )
    return {
        "kind": spec["kind"],
        "expect": spec.get("expect"),
        "invert": spec.get("invert", False),
    }


def display_block():
    """The additive `vocabulary` key the graph envelope carries - a
    projection of this module's display words, nothing else.

    No invert flags, no type sets, no expect sets: the page reads a
    relationship verb, a status word, a dial outcome or a type name, and
    never needs the rules that produced them. Shipping the enforcement
    half here would put a second copy of the rules on disk, which is the
    exact defect this module exists to end. `membership` is the kind set
    the page uses to decide which edge clusters a card - reading it from
    here instead of a hardcoded literal is what lets a fix collapse to one
    cycle edge without leaving the page's clustering broken.
    """
    return {
        "kinds": {
            kind: {"out": spec["out"], "in": spec["in"]}
            for kind, spec in KINDS.items()
        },
        "statuses": dict(STATUSES),
        "dial_outcomes": dict(DIAL_OUTCOMES),
        "types": {t: t.capitalize() for t in RECORD_TYPES},
        "membership": sorted(
            kind for kind, spec in KINDS.items() if spec["membership"]
        ),
    }


def renders_on(kind, direction):
    """The record-type set a relationship row of this kind and direction
    renders on: targets for an inbound row, sources for an outbound row.

    A row renders on the node it is attached to when the card is built -
    an inbound row sits on the edge's target, an outbound row on its
    source. This is what scopes the word-uniqueness gate to only the
    kinds that could ever share a card, instead of failing on a vocabulary
    that is correct (see KINDS docstring: dial vs. grew_from).
    """
    spec = KINDS[kind]
    return spec["targets"] if direction == "in" else spec["sources"]
