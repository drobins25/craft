import importlib.util
import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

import corpus_helper
from src import paths, registry, resolve, sentinels


def _load_fixture_nodes():
    fixture = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "__fixtures__",
        "nodes_minimal.py",
    )
    spec = importlib.util.spec_from_file_location("nodes_minimal", fixture)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.NODES


NODES = _load_fixture_nodes()


def _by_id(node_id):
    return next(n for n in NODES if n["id"] == node_id)


def _synth_node(node_id, node_type, path, name="", date="2026-01-01"):
    return {
        "id": node_id,
        "type": node_type,
        "date": date,
        "_path": path,
        "_name": name,
    }


def _corpus_nodes():
    """Every real node in the fixture corpus, parsed exactly as the
    builder parses them - the ambiguity invariant and the derived-order
    tests need the corpus's own alias table, not the hand-authored
    nodes_minimal fixture."""
    root = corpus_helper.corpus_root()
    try:
        nodes = []
        for record_type, craft_rel in registry.discover(root):
            text = paths.read_under_craft(root, craft_rel)
            node, _links, _notes = registry.parse_file(
                record_type, craft_rel, text
            )
            nodes.append(node)
        return nodes
    finally:
        corpus_helper.cleanup(root)


CORPUS_NODES = _corpus_nodes()


class TestSentinels(unittest.TestCase):
    def test_every_locked_sentinel_is_refused(self):
        for value in [
            "",
            "none",
            "n/a",
            "na",
            "unknown",
            "tbd",
            "none-matched",
            "none - recording source (prose trail)",
            "[filled at the destination fork]",
            "[TBD]",
        ]:
            self.assertTrue(sentinels.is_sentinel(value), value)

    def test_sentinel_check_is_case_and_whitespace_insensitive(self):
        self.assertTrue(sentinels.is_sentinel("  N/A  "))
        self.assertTrue(sentinels.is_sentinel("None"))
        self.assertTrue(sentinels.is_sentinel("  TBD "))

    def test_real_slugs_are_not_sentinels(self):
        for value in ["widget-panel", "3-widget-panel", "nonesuch-feature"]:
            self.assertFalse(sentinels.is_sentinel(value), value)

    def test_negative_declarations_with_trailing_punctuation_are_refused(self):
        for value in ["None.", "none.", "Nothing", "Null.", "Nope.", "No."]:
            self.assertTrue(sentinels.is_sentinel(value), value)

    def test_trailing_punctuation_stripping_does_not_eat_real_slugs(self):
        for value in ["nonesuch-feature.", "notable-story."]:
            self.assertFalse(sentinels.is_sentinel(value), value)


class TestResolve(unittest.TestCase):
    def setUp(self):
        self.index = resolve.build_index(NODES)

    def test_sentinel_resolves_to_none_with_reason_sentinel(self):
        self.assertIsNone(resolve.resolve(self.index, "none-matched"))
        self.assertEqual(resolve.failure_reason("none-matched"), "sentinel")

    def test_template_placeholder_is_a_sentinel(self):
        self.assertIsNone(
            resolve.resolve(self.index, "[filled at the destination fork]")
        )

    def test_bare_story_name_resolves_to_numbered_filename_node(self):
        from_node = _by_id("cycle--cycles--7-sample-cycle--cycle")
        nid = resolve.resolve(
            self.index, "widget-panel", from_node, expect_types={"story"}
        )
        self.assertEqual(
            nid, "story--cycles--7-sample-cycle--stories--3-widget-panel"
        )

    def test_numbered_story_ref_resolves(self):
        nid = resolve.resolve(self.index, "3-widget-panel")
        self.assertEqual(
            nid, "story--cycles--7-sample-cycle--stories--3-widget-panel"
        )

    def test_bare_and_numbered_cycle_refs_resolve_identically(self):
        bare = resolve.resolve(self.index, "sample-cycle")
        numbered = resolve.resolve(self.index, "7-sample-cycle")
        self.assertEqual(bare, "cycle--cycles--7-sample-cycle--cycle")
        self.assertEqual(bare, numbered)

    def test_path_refs_resolve_with_and_without_extension(self):
        with_ext = resolve.resolve(
            self.index, "cycles/7-sample-cycle/stories/3-widget-panel.md"
        )
        without_ext = resolve.resolve(
            self.index, "cycles/7-sample-cycle/stories/3-widget-panel"
        )
        self.assertEqual(
            with_ext, "story--cycles--7-sample-cycle--stories--3-widget-panel"
        )
        self.assertEqual(with_ext, without_ext)

    def test_ambiguous_bare_name_prefers_same_cycle_node(self):
        from_node = _by_id(
            "story--cycles--8-other-cycle--stories--2-widget-panel"
        )
        nid = resolve.resolve(
            self.index, "widget-panel", from_node, expect_types={"story"}
        )
        self.assertEqual(
            nid, "story--cycles--8-other-cycle--stories--2-widget-panel"
        )

    def test_ambiguous_name_without_cycle_affinity_is_deterministic(self):
        from_node = _by_id("notebook--notebook--todos--2026-01-20-sample-todo")
        results = {
            resolve.resolve(self.index, "widget-panel", from_node)
            for _ in range(10)
        }
        self.assertEqual(len(results), 1)

    def test_expect_types_filters_cross_type_name_collision(self):
        nid = resolve.resolve(
            self.index, "widget-panel", expect_types={"tweak"}
        )
        self.assertEqual(nid, "tweak--tweaks--tweak-widget-panel")

    def test_unknown_ref_returns_none_with_reason_unresolved(self):
        self.assertIsNone(resolve.resolve(self.index, "no-such-record"))
        self.assertEqual(resolve.failure_reason("no-such-record"), "unresolved")

    def test_wikilink_brackets_stripped_before_resolution(self):
        targets = resolve.extract_targets("[[3-widget-panel]]")
        self.assertEqual(targets, ["3-widget-panel"])
        self.assertEqual(
            resolve.resolve(self.index, targets[0]),
            "story--cycles--7-sample-cycle--stories--3-widget-panel",
        )

    def test_resolution_never_does_substring_matching(self):
        self.assertIsNone(resolve.resolve(self.index, "widget"))
        self.assertIsNone(resolve.resolve(self.index, "widget-pan"))


class TestContainerRule(unittest.TestCase):
    def setUp(self):
        self.index = resolve.build_index(NODES)

    def test_folder_prefix_of_registered_paths_is_a_container(self):
        self.assertIsNone(resolve.resolve(self.index, "tweaks"))
        self.assertEqual(
            resolve.failure_reason("tweaks", self.index), "container"
        )

    def test_container_check_derives_from_the_alias_index_not_the_filesystem(
        self,
    ):
        # A nonexistent root is proof enough that no path is ever opened -
        # the check only ever consults the in-memory node paths.
        index = resolve.build_index(NODES)
        self.assertEqual(
            resolve.failure_reason(
                "cycles/7-sample-cycle/stories", index
            ),
            "container",
        )

    def test_non_prefix_unknown_value_stays_unresolved(self):
        self.assertEqual(
            resolve.failure_reason("no-such-record", self.index),
            "unresolved",
        )

    def test_a_registered_alias_resolves_exactly_rather_than_as_a_container(
        self,
    ):
        # "widget-panel" is both a registered alias AND a literal directory
        # prefix of a second, unrelated node's path - the exact match must
        # win, never the prefix test.
        nodes = [
            {
                "id": "story--widget-panel",
                "type": "story",
                "date": "2026-01-01",
                "_path": "widget-panel.md",
                "_name": "widget-panel",
            },
            {
                "id": "story--widget-panel--notes",
                "type": "story",
                "date": "2026-01-02",
                "_path": "widget-panel/notes.md",
                "_name": "notes",
            },
        ]
        index = resolve.build_index(nodes)
        self.assertEqual(
            resolve.resolve(index, "widget-panel"), "story--widget-panel"
        )


class TestNotARecord(unittest.TestCase):
    def test_value_under_a_not_records_directory_is_not_a_record(self):
        self.assertTrue(resolve.is_not_a_record("design/tokens.yaml"))
        self.assertTrue(resolve.is_not_a_record("research/some-doc.md"))

    def test_value_under_a_real_record_directory_is_not_flagged(self):
        self.assertFalse(resolve.is_not_a_record("tweaks/tweak-widget.md"))

    def test_root_level_not_records_filename_has_no_directory_to_match_on(self):
        # settings.yaml sits directly at .craft/ root - its "first path
        # segment" is the whole value, and the same NOT_RECORDS lookup
        # covers it without a second code path.
        self.assertTrue(resolve.is_not_a_record("settings.yaml"))
        self.assertTrue(resolve.is_not_a_record("project.md"))
        self.assertFalse(resolve.is_not_a_record("widget-panel.md"))

    def test_a_nested_key_matches_a_value_inside_a_record_producing_folder(
        self,
    ):
        self.assertTrue(resolve.is_not_a_record("notebook/assets/x.md"))

    def test_a_wildcard_key_matches_through_one_segment(self):
        self.assertTrue(
            resolve.is_not_a_record("mockups/anything/rounds/round-1.html")
        )

    def test_a_wildcard_key_does_not_match_a_shorter_value(self):
        self.assertFalse(resolve.is_not_a_record("mockups/anything"))

    def test_failure_reason_only_checks_not_a_record_for_path_fields(self):
        self.assertEqual(
            resolve.failure_reason("design/tokens.yaml", field="body_path"),
            "not-a-record",
        )
        self.assertEqual(
            resolve.failure_reason(
                "design/tokens.yaml", field="reference_materials"
            ),
            "not-a-record",
        )
        # A dependency-style field never gets this treatment, even if a
        # slug happens to collide with a NOT_RECORDS directory name.
        self.assertEqual(
            resolve.failure_reason("design", field="blocked_by"),
            "unresolved",
        )
        self.assertEqual(
            resolve.failure_reason("design", field=None), "unresolved"
        )


class TestProseGuardedLink(unittest.TestCase):
    def test_clean_slug_yields_a_link_and_no_annotation(self):
        link, note = resolve.prose_guarded_link(
            "fix--x", "fix", "source_story", "widget-panel"
        )
        self.assertEqual(link["raw_value"], "widget-panel")
        self.assertIsNone(note)

    def test_decorated_slug_yields_a_link_and_a_prose_annotation(self):
        link, note = resolve.prose_guarded_link(
            "fix--x",
            "fix",
            "source_story",
            "widget-panel (needs the store first)",
        )
        self.assertEqual(link["raw_value"], "widget-panel")
        self.assertEqual(note["reason"], "prose")
        self.assertEqual(
            note["value"], "widget-panel (needs the store first)"
        )

    def test_prose_with_no_surviving_slug_yields_no_link(self):
        link, note = resolve.prose_guarded_link(
            "fix--x",
            "fix",
            "source_story",
            "alignment-gate-auq-fixes (story 16, cycle 11) plus more",
        )
        self.assertIsNone(link)
        self.assertEqual(note["reason"], "prose")

    def test_negative_declaration_with_parenthetical_yields_sentinel(self):
        link, note = resolve.prose_guarded_link(
            "fix--x", "fix", "source_story", "none (design pattern shift)"
        )
        self.assertIsNone(link)
        self.assertEqual(note["reason"], "sentinel")

    def test_bare_sentinel_yields_sentinel_with_no_decoration_stripping(self):
        link, note = resolve.prose_guarded_link(
            "fix--x", "fix", "source_story", "none-matched"
        )
        self.assertIsNone(link)
        self.assertEqual(note["reason"], "sentinel")


class TestExtractTargets(unittest.TestCase):
    def test_slug_with_parenthetical_prose_resolves(self):
        targets = resolve.extract_targets(
            "sample-polish (craft:adhoc, 2026-07-08)"
        )
        self.assertEqual(targets, ["sample-polish"])

    def test_typed_suffix_resolves(self):
        targets = resolve.extract_targets("widget-panel (story, 2026-07-10)")
        self.assertEqual(targets, ["widget-panel"])

    def test_split_value_yields_both_targets_in_source_order(self):
        targets = resolve.extract_targets(
            "SPLIT: (1) tweak-sample-polish (tweak) (2) 3-widget-panel (story)"
        )
        self.assertEqual(targets, ["tweak-sample-polish", "3-widget-panel"])

    def test_comma_list_yields_each_target(self):
        targets = resolve.extract_targets("sample-polish, 3-widget-panel")
        self.assertEqual(targets, ["sample-polish", "3-widget-panel"])

    def test_negative_sentinel_with_prose_yields_no_targets(self):
        self.assertEqual(
            resolve.extract_targets("none - recording source (session only)"),
            [],
        )

    def test_bare_sentinel_yields_no_targets(self):
        self.assertEqual(resolve.extract_targets("none"), [])

    def test_comma_split_prose_fragment_is_dropped_not_yielded(self):
        targets = resolve.extract_targets(
            "3-widget-panel, this part is prose and never a slug"
        )
        self.assertEqual(targets, ["3-widget-panel"])

    def test_extract_targets_strips_backticks_from_each_candidate(self):
        targets = resolve.extract_targets("`sample-polish`, `3-widget-panel`")
        self.assertEqual(targets, ["sample-polish", "3-widget-panel"])


class TestBacktickDecoration(unittest.TestCase):
    def test_strip_decoration_unwraps_a_matched_backtick_pair_without_marking_decorated(
        self,
    ):
        slug, decorated = resolve.strip_decoration("`widget-panel`")
        self.assertEqual(slug, "widget-panel")
        self.assertFalse(decorated)

    def test_backticked_slug_resolves_and_produces_no_prose_annotation(self):
        link, note = resolve.prose_guarded_link(
            "fix--x", "fix", "source_story", "`widget-panel`"
        )
        self.assertEqual(link["raw_value"], "widget-panel")
        self.assertIsNone(note)

    def test_backticked_value_with_whitespace_is_still_prose(self):
        link, note = resolve.prose_guarded_link(
            "fix--x", "fix", "source_story", "`widget panel notes`"
        )
        self.assertIsNone(link)
        self.assertEqual(note["reason"], "prose")


class TestTwoPassRegistration(unittest.TestCase):
    def test_register_raises_after_freeze_canonical(self):
        index = resolve.AliasIndex()
        index.freeze_canonical()
        with self.assertRaises(resolve.FrozenIndex):
            index.register("some-alias", "some-id")

    def test_register_derived_raises_before_freeze_canonical(self):
        # The boundary is enforced from BOTH ends. Called early, the
        # canonical snapshot is empty, so every alias would pass the
        # unclaimed check and freeze_canonical() would then snapshot these
        # derived forms as canonical - the silent shadow, through the other
        # write path.
        index = resolve.AliasIndex()
        with self.assertRaises(resolve.FrozenIndex):
            index.register_derived("some-alias", "some-id")

    def test_register_derived_refuses_an_alias_already_in_the_frozen_canonical_snapshot(
        self,
    ):
        index = resolve.AliasIndex()
        index.register("claimed-alias", "node-a")
        index.freeze_canonical()
        index.register_derived("claimed-alias", "node-b")
        self.assertEqual(index.candidates("claimed-alias"), ["node-a"])

    def test_a_derived_alias_never_shadows_a_canonical_one(self):
        # The audit's measured casualty: zero-padding story 5-muse-at-init
        # would collide with the real planning doc 05-muse-at-init.
        nodes = NODES + [
            _synth_node(
                "story--5-muse-at-init",
                "story",
                "5-muse-at-init.md",
                name="muse-at-init",
                date="2026-04-01",
            ),
            _synth_node(
                "planning--planning--oss-ux-polish--05-muse-at-init",
                "planning",
                "planning/oss-ux-polish/05-muse-at-init.md",
                name="muse-at-init",
                date="2026-01-01",
            ),
        ]
        index = resolve.build_index(nodes)
        self.assertEqual(
            index.candidates("05-muse-at-init"),
            ["planning--planning--oss-ux-polish--05-muse-at-init"],
        )


class TestAmbiguityInvariant(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.nodes = CORPUS_NODES

    def test_fixture_corpus_has_ambiguous_canonical_aliases_including_widget_panel(
        self,
    ):
        # Non-vacuity check: the collect-then-commit rule only proves
        # anything if the corpus genuinely has ambiguous names to protect.
        # Asserts the specific alias the suppression tests below depend on
        # rather than a closed count - an exact count would break whenever a
        # later story adds an unrelated fixture record that happens to share
        # a stem, failing for a reason this test is not about.
        canonical_only = resolve.AliasIndex()
        resolve._register_canonical(canonical_only, self.nodes)
        ambiguous = {
            alias
            for alias, ids in canonical_only._aliases.items()
            if len(ids) > 1
        }
        self.assertIn("widget-panel", ambiguous)

    def test_derived_registration_never_changes_the_set_of_ambiguous_aliases(
        self,
    ):
        # THE FIRST TEST.
        canonical_only = resolve.AliasIndex()
        resolve._register_canonical(canonical_only, self.nodes)
        canonical_only.freeze_canonical()
        before = {
            alias
            for alias, ids in canonical_only._aliases.items()
            if len(ids) > 1
        }
        full = resolve.build_index(self.nodes)
        after = {
            alias for alias, ids in full._aliases.items() if len(ids) > 1
        }
        self.assertEqual(
            before, after, "ambiguity changed for: %s" % (before ^ after)
        )

    def test_two_nodes_proposing_the_same_derived_alias_means_neither_is_registered(
        self,
    ):
        index = resolve.build_index(self.nodes)
        self.assertEqual(index.candidates("story-widget-panel"), [])

    def test_derived_registration_is_independent_of_node_order(self):
        # Canonical registration order is per-node insertion order and was
        # never order-independent (an ambiguous alias's candidate LIST
        # order tracks node order, harmlessly - resolve()'s tie-break does
        # not depend on it). What must not depend on order is which
        # aliases exist at all and which node each singly-registered one
        # points at.
        forward = resolve.build_index(self.nodes)
        backward = resolve.build_index(list(reversed(self.nodes)))
        forward_sets = {
            alias: set(ids) for alias, ids in forward._aliases.items()
        }
        backward_sets = {
            alias: set(ids) for alias, ids in backward._aliases.items()
        }
        self.assertEqual(forward_sets, backward_sets)


class TestDerivedReport(unittest.TestCase):
    def test_derived_report_returns_four_counts_that_sum_consistently(self):
        index = resolve.build_index(NODES)
        report = index.derived_report()
        self.assertEqual(
            set(report),
            {
                "proposed",
                "suppressed_claimed",
                "suppressed_multiple",
                "registered",
            },
        )
        self.assertEqual(
            report["proposed"],
            report["suppressed_claimed"]
            + report["suppressed_multiple"]
            + report["registered"],
        )
        self.assertGreater(report["registered"], 0)


class TestDerivedShapesResolve(unittest.TestCase):
    def test_the_canonical_dated_stem_still_resolves(self):
        # The fixture no longer carries this form end to end (it now cites
        # the date-stripped alias instead) - a direct check keeps the
        # canonical shape from silently losing coverage.
        index = resolve.build_index(NODES)
        self.assertEqual(
            resolve.resolve(index, "2026-01-20-sample-todo"),
            "notebook--notebook--todos--2026-01-20-sample-todo",
        )

    def test_a_citation_naming_a_record_folder_resolves_to_that_folders_record(
        self,
    ):
        nodes = [
            _synth_node(
                "mockup--mockups--2026-01-15-sample-hero--record",
                "mockup",
                "mockups/2026-01-15-sample-hero/record.md",
            )
        ]
        index = resolve.build_index(nodes)
        self.assertEqual(
            resolve.resolve(index, "mockups/2026-01-15-sample-hero"),
            "mockup--mockups--2026-01-15-sample-hero--record",
        )

    def test_a_lone_folder_based_record_proposes_no_constant_stem_alias(self):
        # S1 is keyed off a record's own slug. A mockup's stem is always
        # "record" and a cycle's always "cycle", so S1 would propose the
        # meaningless "mockup-record" / "cycle-cycle" for every instance.
        # With several of each the multiplicity rule hides it; this corpus
        # has exactly one of each, which is where it would actually
        # register. The folder alias (S5) is what a citation really uses.
        nodes = [
            _synth_node(
                "mockup--mockups--2026-01-15-sample-hero--record",
                "mockup",
                "mockups/2026-01-15-sample-hero/record.md",
            ),
            _synth_node(
                "cycle--cycles--7-sample-cycle--cycle",
                "cycle",
                "cycles/7-sample-cycle/cycle.yaml",
            ),
        ]
        index = resolve.build_index(nodes)
        self.assertEqual(index.candidates("mockup-record"), [])
        self.assertEqual(index.candidates("cycle-cycle"), [])
        # The real citation shape still resolves.
        self.assertEqual(
            resolve.resolve(index, "mockups/2026-01-15-sample-hero"),
            "mockup--mockups--2026-01-15-sample-hero--record",
        )

    def test_a_sibling_artifact_beside_record_md_resolves_to_that_record(
        self,
    ):
        nodes = [
            _synth_node(
                "mockup--mockups--2026-01-15-sample-hero--record",
                "mockup",
                "mockups/2026-01-15-sample-hero/record.md",
            )
        ]
        index = resolve.build_index(nodes)
        self.assertEqual(
            resolve.resolve(
                index, "mockups/2026-01-15-sample-hero/mockup.html"
            ),
            "mockup--mockups--2026-01-15-sample-hero--record",
        )

    def test_a_sibling_artifact_beside_cycle_yaml_resolves_to_that_cycle(
        self,
    ):
        # The SECOND folder-based record type - registry._RULES declares
        # exactly two (mockups/*/record.md and cycles/*/cycle.yaml), and
        # every other type is a flat file the retry can never fire for.
        nodes = [
            _synth_node(
                "cycle--cycles--7-sample-cycle--cycle",
                "cycle",
                "cycles/7-sample-cycle/cycle.yaml",
                name="sample-cycle",
            )
        ]
        index = resolve.build_index(nodes)
        self.assertEqual(
            resolve.resolve(index, "cycles/7-sample-cycle/notes.txt"),
            "cycle--cycles--7-sample-cycle--cycle",
        )

    def test_a_story_path_does_not_promote_to_its_cycle(self):
        # cycles/<dir>/stories/<file>.md retries to cycles/<dir>/stories,
        # which is registered as nothing - the one-level bound stopping an
        # unbounded retry from silently attributing a story's citation to
        # its cycle.
        nodes = [
            _synth_node(
                "cycle--cycles--7-sample-cycle--cycle",
                "cycle",
                "cycles/7-sample-cycle/cycle.yaml",
                name="sample-cycle",
            ),
            _synth_node(
                "story--cycles--7-sample-cycle--stories--3-widget-panel",
                "story",
                "cycles/7-sample-cycle/stories/3-widget-panel.md",
                name="widget-panel",
            ),
        ]
        index = resolve.build_index(nodes)
        self.assertIsNone(
            resolve.resolve(
                index, "cycles/7-sample-cycle/stories/notes.txt"
            )
        )

    def test_a_file_one_level_deeper_than_a_record_folder_does_not_resolve(
        self,
    ):
        nodes = [
            _synth_node(
                "mockup--mockups--2026-01-15-sample-hero--record",
                "mockup",
                "mockups/2026-01-15-sample-hero/record.md",
            )
        ]
        index = resolve.build_index(nodes)
        self.assertIsNone(
            resolve.resolve(
                index,
                "mockups/2026-01-15-sample-hero/rounds/round-1.html",
            )
        )

    def test_the_parent_retry_does_not_run_when_the_expect_filter_emptied_the_candidates(
        self,
    ):
        nodes = [
            _synth_node(
                "tweak--folder--target",
                "tweak",
                "folder/target.md",
            ),
            _synth_node(
                "mockup--folder--record",
                "mockup",
                "folder/record.md",
            ),
        ]
        index = resolve.build_index(nodes)
        # The raw exact lookup for "folder/target" finds one candidate (the
        # tweak) - non-empty, so the parent retry to "folder" (which would
        # resolve to the mockup) must never run, even once expect_types
        # filters that one candidate away.
        self.assertIsNone(
            resolve.resolve(
                index, "folder/target", expect_types={"mockup"}
            )
        )

    def test_no_substring_or_fragment_resolves_for_derived_aliases(self):
        index = resolve.build_index(NODES)
        self.assertIsNone(resolve.resolve(index, "7-sample-cycle/3-widget-pan"))
        self.assertIsNone(resolve.resolve(index, "ample-cycle/3-widget-panel"))


class TestFailureReasonWrongType(unittest.TestCase):
    def setUp(self):
        self.index = resolve.build_index(NODES)

    def test_a_source_story_naming_a_fix_annotates_wrong_type(self):
        nodes = [
            _synth_node("fix--fixes--sample-a", "fix", "fixes/sample-a.md", "sample-a"),
            _synth_node("fix--fixes--sample-b", "fix", "fixes/sample-b.md", "sample-b"),
        ]
        index = resolve.build_index(nodes)
        self.assertIsNone(
            resolve.resolve(index, "sample-a", expect_types={"story"})
        )
        self.assertEqual(
            resolve.failure_reason(
                "sample-a", index, expect={"story"}
            ),
            "wrong-type",
        )

    def test_a_source_story_naming_a_cycle_annotates_wrong_type(self):
        self.assertIsNone(
            resolve.resolve(self.index, "sample-cycle", expect_types={"story"})
        )
        self.assertEqual(
            resolve.failure_reason(
                "sample-cycle", self.index, expect={"story"}
            ),
            "wrong-type",
        )

    def test_a_value_that_names_nothing_still_annotates_unresolved(self):
        self.assertEqual(
            resolve.failure_reason(
                "no-such-record", self.index, expect={"story"}
            ),
            "unresolved",
        )

    def test_wrong_type_outranks_container(self):
        nodes = [
            _synth_node("cycle--folder--cycle", "cycle", "folder/cycle.yaml", "folder"),
            _synth_node("story--folder--child", "story", "folder/child.md", "child"),
        ]
        index = resolve.build_index(nodes)
        # "folder" is both a registered alias for the cycle node AND a
        # literal directory prefix of the story's path - the wrong-type
        # diagnosis (a real record of a forbidden kind) must win over the
        # weaker container guess.
        self.assertEqual(
            resolve.failure_reason("folder", index, expect={"story"}),
            "wrong-type",
        )
        self.assertEqual(
            resolve.failure_reason("folder", index),
            "container",
        )

    def test_not_a_record_outranks_wrong_type_on_a_path_field(self):
        nodes = [
            _synth_node("story--design", "story", "design.md", "design"),
        ]
        index = resolve.build_index(nodes)
        # "design" both resolves to a real node AND matches the NOT_RECORDS
        # "design" key - on a path field, the excluded-surface diagnosis is
        # the more specific fact and must win.
        self.assertEqual(
            resolve.failure_reason(
                "design", index, field="body_path", expect={"tweak"}
            ),
            "not-a-record",
        )

    def test_failure_reason_without_an_expect_set_behaves_exactly_as_before(
        self,
    ):
        self.assertEqual(
            resolve.failure_reason("none-matched"), "sentinel"
        )
        self.assertEqual(
            resolve.failure_reason("no-such-record"), "unresolved"
        )
        self.assertEqual(
            resolve.failure_reason("tweaks", self.index), "container"
        )


if __name__ == "__main__":
    unittest.main()
