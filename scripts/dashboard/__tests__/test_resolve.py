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


if __name__ == "__main__":
    unittest.main()
