"""Output-axis gates for src/vocabulary.py.

These tests fail on the definition itself - never on a corpus that happens
to exercise it. A kind with a missing word, a duplicated inbound word whose
target types collide, or an invert flag that cannot resolve is a defect in
the vocabulary, independent of anything craft has ever written to disk.
"""

import copy
import json
import os
import re
import sys
import unittest
from pathlib import Path

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

from src import vocabulary


def _instantiate_segment(segment):
    """A rule-pattern segment with its wildcard(s) replaced by a literal
    that satisfies them - "*" and "**" both become "probe", ".md"-suffixed
    wildcards become "probe.md"."""
    if segment in ("*", "**"):
        return "probe"
    if "*" in segment:
        return segment.replace("*", "probe")
    return segment


def _probe_path(key, pattern):
    """The path a NOT_RECORDS key would need to prefix in order to also be
    a real record under `pattern` - key's own segments (wildcards
    instantiated) followed by however much of pattern's tail the key does
    not already cover. When key is at least as long as pattern, only
    pattern's final segment is appended, so a key like "mockups/*/rounds"
    is probed with a trailing "record.md" rather than nothing at all."""
    key_segments = [
        "probe" if segment == "*" else segment for segment in key.split("/")
    ]
    rule_segments = pattern.split("/")
    if len(key_segments) >= len(rule_segments):
        tail = [rule_segments[-1]]
    else:
        tail = rule_segments[len(key_segments):]
    tail = [_instantiate_segment(segment) for segment in tail]
    return "/".join(key_segments + tail)


def _failing_not_records_keys(not_records):
    """Every key in not_records that prefixes at least one probe path the
    real registry.classify calls a record - the guard's verdict, derived
    from registry._RULES rather than a hand-kept probe list so a new rule
    shape is covered automatically."""
    from src import registry

    failing = set()
    for key in not_records:
        for _record_type, pattern in registry._RULES:
            probe = _probe_path(key, pattern)
            if registry.classify(probe) is not None:
                failing.add(key)
    return failing


class TestKindWords(unittest.TestCase):
    def test_every_kind_carries_a_non_empty_outbound_and_inbound_word(self):
        for kind, spec in vocabulary.KINDS.items():
            self.assertTrue(spec["out"].strip(), "%s: missing outbound word" % kind)
            self.assertTrue(spec["in"].strip(), "%s: missing inbound word" % kind)

    def test_every_kind_declares_non_empty_source_and_target_type_sets(self):
        for kind, spec in vocabulary.KINDS.items():
            self.assertTrue(spec["sources"], "%s: empty source type set" % kind)
            self.assertTrue(spec["targets"], "%s: empty target type set" % kind)

    def test_kinds_carry_no_invert_key(self):
        # Inversion is a property of a FIELD, never of the kind itself - a
        # KINDS entry that carried "invert": False for all twelve rows was
        # a key whose only job was to say "not here." Asserted directly so
        # the key cannot silently creep back in.
        for kind, spec in vocabulary.KINDS.items():
            self.assertNotIn("invert", spec, kind)

    def test_no_two_kinds_share_an_inbound_word_where_target_sets_intersect(self):
        kinds = list(vocabulary.KINDS)
        for i, a in enumerate(kinds):
            for b in kinds[i + 1:]:
                spec_a = vocabulary.KINDS[a]
                spec_b = vocabulary.KINDS[b]
                if spec_a["in"] != spec_b["in"]:
                    continue
                overlap = spec_a["targets"] & spec_b["targets"]
                self.assertFalse(
                    overlap,
                    "%s and %s share inbound word %r over target types %r"
                    % (a, b, spec_a["in"], overlap),
                )

    def test_no_two_kinds_share_an_outbound_word_where_source_sets_intersect(self):
        kinds = list(vocabulary.KINDS)
        for i, a in enumerate(kinds):
            for b in kinds[i + 1:]:
                spec_a = vocabulary.KINDS[a]
                spec_b = vocabulary.KINDS[b]
                if spec_a["out"] != spec_b["out"]:
                    continue
                overlap = spec_a["sources"] & spec_b["sources"]
                self.assertFalse(
                    overlap,
                    "%s and %s share outbound word %r over source types %r"
                    % (a, b, spec_a["out"], overlap),
                )

    def test_every_declared_source_and_target_type_is_a_real_record_type(self):
        for kind, spec in vocabulary.KINDS.items():
            for record_type in spec["sources"] | spec["targets"]:
                self.assertIn(
                    record_type,
                    vocabulary.RECORD_TYPES,
                    "%s: %r is not a declared record type" % (kind, record_type),
                )

    def test_removing_a_kinds_inbound_word_fails_the_gate(self):
        # Vacuity check, mirroring test_coverage.py's discard-a-handler
        # test: the real word-presence assertion, re-run against a
        # deliberately broken copy, must actually fail and name the kind.
        broken = copy.deepcopy(vocabulary.KINDS)
        target_kind = "dial"
        broken[target_kind]["in"] = ""
        with self.assertRaises(AssertionError) as ctx:
            for kind, spec in broken.items():
                self.assertTrue(spec["in"].strip(), "%s: missing inbound word" % kind)
        self.assertIn(target_kind, str(ctx.exception))


class TestRecordTypesAndDirectories(unittest.TestCase):
    def test_record_types_match_the_parser_registry_exactly(self):
        from src import registry

        self.assertEqual(set(vocabulary.RECORD_TYPES), set(registry.PARSERS))

    def test_every_excluded_directory_carries_a_non_empty_reason(self):
        for directory, reason in vocabulary.NOT_RECORDS.items():
            self.assertTrue(reason.strip(), directory)


class TestNotRecordsGuard(unittest.TestCase):
    """Decision 6: the old guard was a literal set-intersection of dict
    keys against record-type names, which works only while every key is a
    single segment - "notebook/ideas" would pass it clean and silently
    stop every real notebook idea from resolving. This rewrite checks each
    key as a path prefix against the real classifier instead."""

    def test_a_not_records_key_cannot_prefix_any_path_the_classifier_calls_a_record(
        self,
    ):
        # THE FIRST TEST: probes built from registry._RULES for every
        # declared key, failing with the key(s) that classified.
        failing = _failing_not_records_keys(vocabulary.NOT_RECORDS)
        self.assertEqual(
            failing,
            set(),
            "NOT_RECORDS key(s) prefix a path the classifier calls a "
            "record: %s" % sorted(failing),
        )

    def test_seeding_notebook_ideas_as_a_key_fails_the_guard_and_names_it(
        self,
    ):
        broken = dict(vocabulary.NOT_RECORDS)
        broken["notebook/ideas"] = "seeded for the vacuity check"
        self.assertIn("notebook/ideas", _failing_not_records_keys(broken))

    def test_seeding_mockups_star_as_a_key_fails_the_guard_and_names_it(self):
        broken = dict(vocabulary.NOT_RECORDS)
        broken["mockups/*"] = "seeded for the vacuity check"
        self.assertIn("mockups/*", _failing_not_records_keys(broken))


class TestFields(unittest.TestCase):
    def test_every_linkable_field_entry_names_a_kind_that_exists(self):
        for pair, spec in vocabulary.FIELDS.items():
            if "kind" not in spec:
                continue
            self.assertIn(
                spec["kind"], vocabulary.KINDS, "%r: unknown kind %r" % (pair, spec["kind"])
            )

    def test_every_field_marked_invert_names_a_kind_whose_types_admit_the_flip(self):
        for pair, spec in vocabulary.FIELDS.items():
            if not spec.get("invert"):
                continue
            kind_spec = vocabulary.KINDS[spec["kind"]]
            # Flipping source and target must land inside the kind's own
            # declared type sets, or the inverted edge could never resolve.
            self.assertTrue(
                kind_spec["sources"] & kind_spec["targets"],
                "%r: kind %r cannot flip - source and target types never overlap"
                % (pair, spec["kind"]),
            )

    def test_the_locked_blocked_by_field_maps_to_an_inverted_blocks_kind(self):
        self.assertEqual(
            vocabulary.kind_for("story", "blocked_by"),
            {"kind": "blocks", "expect": frozenset({"story"}), "invert": True},
        )

    def test_kind_for_return_shape_is_stable_even_when_the_literal_is_short(self):
        # ("story", "cycle") writes no "invert" and no "expect" override in
        # the FIELDS literal beyond its own expect set - kind_for still
        # returns all three keys, defaults filled in.
        self.assertEqual(
            vocabulary.kind_for("story", "cycle"),
            {"kind": "belongs_to", "expect": frozenset({"cycle"}), "invert": False},
        )
        self.assertEqual(
            vocabulary.kind_for("story", "reference_materials"),
            {"kind": "references", "expect": None, "invert": False},
        )

    def test_kind_for_raises_unknown_field_for_an_unregistered_pair(self):
        with self.assertRaises(vocabulary.UnknownField):
            vocabulary.kind_for("story", "not-a-real-field")

    def test_kind_for_raises_for_an_annotation_only_pair(self):
        # Declared in FIELDS for the coverage inventory's sake, but a
        # parser only ever emits an annotation for it - not linkable.
        for pair in (
            ("story", "element_binding_table"),
            ("cycle", "stories_membership"),
            ("mockup", "solidify_outcome"),
        ):
            with self.assertRaises(vocabulary.UnknownField):
                vocabulary.kind_for(*pair)


class TestReasons(unittest.TestCase):
    def test_reasons_gains_wrong_type_and_self_reference_without_losing_any(
        self,
    ):
        self.assertEqual(
            vocabulary.REASONS,
            frozenset(
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
            ),
        )

    def test_resolve_annotation_accepts_every_registered_reason(self):
        from src import resolve

        for reason in vocabulary.REASONS:
            note = resolve.annotation("x", "field", "value", reason)
            self.assertEqual(note["reason"], reason)

    def test_resolve_annotation_raises_on_an_unregistered_reason(self):
        from src import resolve

        with self.assertRaises(vocabulary.UnknownReason):
            resolve.annotation("x", "field", "value", "not-a-real-reason")

    def test_removing_a_reason_fails_a_caller_that_uses_it(self):
        # Vacuity check, mirroring kind_for's discard-a-handler tests: the
        # gate must actually fail once a reason a caller depends on is
        # removed, not just pass by construction.
        from src import resolve

        broken = frozenset(vocabulary.REASONS - {"container"})
        original = vocabulary.REASONS
        vocabulary.REASONS = broken
        try:
            with self.assertRaises(vocabulary.UnknownReason):
                resolve.annotation("x", "field", "value", "container")
        finally:
            vocabulary.REASONS = original


class TestStatuses(unittest.TestCase):
    def test_every_status_word_is_non_empty(self):
        for stored, word in vocabulary.STATUSES.items():
            self.assertTrue(word.strip(), "status %r maps to an empty word" % stored)

    def test_statuses_has_no_pending_key(self):
        self.assertNotIn("pending", vocabulary.STATUSES)

    def test_statuses_carries_both_proposal_and_proposed(self):
        self.assertEqual(vocabulary.STATUSES["proposal"], "Proposed")
        self.assertEqual(vocabulary.STATUSES["proposed"], "Proposed")

    def test_dial_outcomes_has_exactly_the_four_content_direction_rows(self):
        self.assertEqual(
            vocabulary.DIAL_OUTCOMES,
            {
                "nothing": "Unchanged",
                "tweak": "Tweaked",
                "story": "Planned",
                "todo": "Parked",
            },
        )


class TestRendersOn(unittest.TestCase):
    def test_renders_on_inbound_returns_targets(self):
        self.assertEqual(
            vocabulary.renders_on("dial", "in"),
            vocabulary.KINDS["dial"]["targets"],
        )

    def test_renders_on_outbound_returns_sources(self):
        self.assertEqual(
            vocabulary.renders_on("dial", "out"),
            vocabulary.KINDS["dial"]["sources"],
        )

    def test_dial_and_grew_from_never_land_on_the_same_card(self):
        # Both read "Became" inbound; the words are safe only because a dial
        # edge targets a dial record and a grew_from edge targets a tweak.
        self.assertFalse(
            vocabulary.renders_on("dial", "in")
            & vocabulary.renders_on("grew_from", "in")
        )


class TestDisplayBlock(unittest.TestCase):
    """The projection the graph envelope carries as `vocabulary` - display
    words only. The page never needs the enforcement half (invert flags,
    type sets), and shipping it would put a second copy of the rules on
    disk, which is the exact defect this story exists to end."""

    def test_display_block_has_the_four_declared_top_level_keys(self):
        block = vocabulary.display_block()
        self.assertEqual(
            set(block),
            {"statuses", "dial_outcomes", "types", "membership"},
        )

    def test_display_block_emits_no_relationship_words(self):
        # The card stopped printing relationship verbs when its Connections
        # region became the commit strip. KINDS still carries the words and
        # the gates below still hold them correct - they are simply not
        # shipped to a page with no reader for them.
        self.assertNotIn("kinds", vocabulary.display_block())

    def test_display_block_carries_no_enforcement_data(self):
        # No invert flags, no type sets, no expect sets - the page reads
        # words only, never the rules that produced them.
        serialized = json.dumps(vocabulary.display_block())
        for forbidden in ("invert", "sources", "targets", "expect"):
            self.assertNotIn(forbidden, serialized, forbidden)

    def test_display_block_statuses_and_dial_outcomes_match_the_definition(self):
        block = vocabulary.display_block()
        self.assertEqual(block["statuses"], vocabulary.STATUSES)
        self.assertEqual(block["dial_outcomes"], vocabulary.DIAL_OUTCOMES)

    def test_display_block_types_cover_every_record_type(self):
        block = vocabulary.display_block()
        self.assertEqual(set(block["types"]), set(vocabulary.RECORD_TYPES))
        for record_type, word in block["types"].items():
            self.assertTrue(word.strip(), record_type)

    def test_display_block_membership_matches_kinds_flagged_membership(self):
        block = vocabulary.display_block()
        self.assertEqual(
            set(block["membership"]),
            {k for k, spec in vocabulary.KINDS.items() if spec["membership"]},
        )


class TestStatusProseDrift(unittest.TestCase):
    """The status half of Decision 12's prose-versus-definition gate. The
    field half lives in bash (tests/test-vocabulary-prose.sh) because it
    reads markdown prose; this half is python because it needs
    vocabulary.STATUSES directly. check-doc-drift.sh does not restate this
    check - Decision 12 only asks the always-run suite to carry it, and
    invoking the same python module from bash would need a subprocess for
    no reason.

    The record-writer scope cannot be the whole repo:
    hooks/scripts/update-story-status.sh writes `status: $NEW_STATUS` from
    a runtime argument (no grep closes that set), and
    commands/craft-become.md, craft-docs.md and craft-reflect.md write
    `in-progress`, `draft` and `written` onto session files that classify
    as no record type under registry._RULES. So the scope below is a
    declared list, per file, with the reason it counts as a record-writer -
    the ALLOWLIST idiom already used by the orphan-reference check in
    scripts/check-doc-drift.sh (grep for `ALLOWLIST=`; named rather than
    cited by line, so an edit above it cannot rot this reference). Decision
    11 (an unrecognised status prints as stored) is the designed valve for
    what this scope cannot reach.
    """

    _REPO_ROOT = Path(__file__).resolve().parents[3]

    # (path relative to repo root, reason it writes a literal status onto a
    # path that DOES classify as a record under registry._RULES). The
    # planning-doc templates are a glob (templates/planning/*.md) rather
    # than a hand-kept trio, so a new planning template joins the scope for
    # free instead of waiting for someone to remember to list it.
    _EXPLICIT_RECORD_WRITER_FILES = (
        ("templates/story-full.md", "the story template every new story starts from"),
        ("templates/story-backlog.md", "the backlog story template"),
        ("hooks/scripts/create-cycle.sh", "writes the cycle record's initial status"),
        ("skills/adhoc/references/fix.md", "the fix flow's status lifecycle"),
        ("skills/adhoc/references/tweak.md", "the tweak flow's status lifecycle"),
        ("commands/references/mockup-inline.md", "the mockup flow's status lifecycle"),
        (
            "commands/references/story-from-mockup.md",
            "writes graduated-story onto the mockup record",
        ),
    )

    @classmethod
    def _record_writer_files(cls):
        files = list(cls._EXPLICIT_RECORD_WRITER_FILES)
        planning_dir = cls._REPO_ROOT / "templates" / "planning"
        for path in sorted(planning_dir.glob("*.md")):
            files.append(
                (
                    "templates/planning/%s" % path.name,
                    "a planning-doc template (templates/planning/*.md)",
                )
            )
        return tuple(files)

    # Session-file statuses that must NEVER be in scope - proves the scope
    # is deliberately narrower than "every status: in the repo", not an
    # accident of what nobody has written yet.
    _OUT_OF_SCOPE = (
        ("commands/craft-become.md", "in-progress"),
        ("commands/craft-docs.md", "draft"),
        ("commands/craft-reflect.md", "written"),
    )

    _STATUS_LITERAL = re.compile(r"`?status:\s+([a-zA-Z][\w-]*)`?")

    def _literals_in(self, relpath):
        text = (self._REPO_ROOT / relpath).read_text()
        found = []
        for lineno, line in enumerate(text.splitlines(), start=1):
            for match in self._STATUS_LITERAL.finditer(line):
                found.append((match.group(1), lineno))
        return found

    def test_every_status_literal_in_record_writer_files_has_a_display_word(self):
        for relpath, _reason in self._record_writer_files():
            for value, lineno in self._literals_in(relpath):
                self.assertIn(
                    value,
                    vocabulary.STATUSES,
                    "%s:%d writes status %r, which has no display word"
                    % (relpath, lineno, value),
                )

    def test_removing_a_status_from_the_definition_fails_the_gate(self):
        # Vacuity check, mirroring kind_for's discard-a-handler tests:
        # skills/adhoc/references/fix.md:20 writes `status: proposed`, so
        # deleting that key must break the assertion above and name it -
        # not pass silently on a definition missing the word.
        broken = dict(vocabulary.STATUSES)
        del broken["proposed"]
        with self.assertRaises(AssertionError) as ctx:
            for value, lineno in self._literals_in("skills/adhoc/references/fix.md"):
                self.assertIn(value, broken, "fix.md:%d writes status %r" % (lineno, value))
        self.assertIn("proposed", str(ctx.exception))

    def test_a_status_written_onto_a_session_file_does_not_fail_the_gate(self):
        writer_paths = {relpath for relpath, _reason in self._record_writer_files()}
        for relpath, value in self._OUT_OF_SCOPE:
            self.assertNotIn(
                relpath, writer_paths, "%s should not be a declared record-writer" % relpath
            )
            # And confirm the value really is unknown to STATUSES -
            # otherwise the exclusion isn't guarding against anything.
            self.assertNotIn(
                value, vocabulary.STATUSES, "%r unexpectedly has a display word" % value
            )


if __name__ == "__main__":
    unittest.main()
