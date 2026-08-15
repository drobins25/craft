import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

import corpus_helper
from src import registry


EXPECTED = {
    "backlog/orphan-idea.md": "story",
    "cycles/7-sample-cycle/cycle.yaml": "cycle",
    "cycles/7-sample-cycle/stories/1-data-layer.md": "story",
    "cycles/7-sample-cycle/stories/3-widget-panel.md": "story",
    "cycles/8-other-cycle/cycle.yaml": "cycle",
    "cycles/8-other-cycle/stories/2-widget-panel.md": "story",
    "cycles/8-other-cycle/stories/4-bullet-deps.md": "story",
    "dials/2026-02-20-panel-spacing.md": "dial",
    "dials/2026-02-21-exit-dial.md": "dial",
    "fixes/sample-broken-widget.md": "fix",
    "fixes/sample-legacy-fix.md": "fix",
    "mockups/2026-01-15-sample-hero/record.md": "mockup",
    "mockups/2026-02-15-sample-flow/record.md": "mockup",
    "notebook/ideas/2026-01-18-sample-idea.md": "notebook",
    "notebook/notes/2026-01-25-sample-note.md": "notebook",
    "notebook/todos/2026-01-20-sample-todo.md": "notebook",
    "notebook/todos/done/2026-01-22-finished-todo.md": "notebook",
    "planning/README.md": "planning",
    "planning/empty-doc.md": "planning",
    "planning/nested-area/README.md": "planning",
    "planning/sample-concept.md": "planning",
    "riff/notes/2026-02-05-sample-riff.md": "riff",
    "tweaks/legacy-heading-tweak.md": "tweak",
    "tweaks/tweak-prose-source.md": "tweak",
    "tweaks/tweak-sample-polish.md": "tweak",
}


class TestClassify(unittest.TestCase):
    def test_every_fixture_path_classifies_to_expected_type(self):
        for craft_rel, expected_type in EXPECTED.items():
            self.assertEqual(
                registry.classify(craft_rel), expected_type, craft_rel
            )

    def test_notebook_assets_and_research_are_skipped_silently(self):
        self.assertIsNone(registry.classify("notebook/assets/sample-asset.md"))
        self.assertIsNone(registry.classify("research/scratch.md"))

    def test_future_record_shapes_are_skipped_not_crashed(self):
        self.assertIsNone(registry.classify("holograms/2030-01-01-demo.md"))
        self.assertIsNone(registry.classify(".continuation"))

    def test_dashboard_output_never_classifies(self):
        self.assertIsNone(registry.classify("dashboard/graph.js"))
        self.assertIsNone(registry.classify("dashboard/records/x.js"))


class TestDiscover(unittest.TestCase):
    def test_discover_walks_corpus_and_matches_expected_set(self):
        root = corpus_helper.corpus_root()
        try:
            found = registry.discover(root)
        finally:
            corpus_helper.cleanup(root)
        self.assertEqual(dict((rel, t) for t, rel in found), EXPECTED)

    def test_discover_output_is_sorted_and_deterministic(self):
        root = corpus_helper.corpus_root()
        try:
            first = registry.discover(root)
            second = registry.discover(root)
        finally:
            corpus_helper.cleanup(root)
        self.assertEqual(first, second)
        self.assertEqual([r for _, r in first], sorted(r for _, r in first))


class TestNeverCrash(unittest.TestCase):
    def test_raising_parser_yields_minimal_node_plus_warning(self):
        def explode(path, craft_rel, fields, body):
            raise ValueError("synthetic parser failure")

        original = registry.PARSERS["story"]
        registry.PARSERS["story"] = explode
        try:
            node, links, annotations = registry.parse_file(
                "story",
                "backlog/orphan-idea.md",
                corpus_helper.read_fixture("backlog/orphan-idea.md"),
            )
        finally:
            registry.PARSERS["story"] = original
        self.assertEqual(node["type"], "story")
        self.assertEqual(node["title"], "Orphan idea")
        self.assertEqual(links, [])
        self.assertEqual(annotations, [])
        self.assertIn("synthetic parser failure", node["_warnings"][0])


if __name__ == "__main__":
    unittest.main()
