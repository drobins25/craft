import importlib.util
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src import resolve, sentinels


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


if __name__ == "__main__":
    unittest.main()
