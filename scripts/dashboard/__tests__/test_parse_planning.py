import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

import corpus_helper
from src import registry


def _parse(craft_rel):
    return registry.parse_file(
        "planning", craft_rel, corpus_helper.read_fixture(craft_rel)
    )


class TestParsePlanning(unittest.TestCase):
    def test_title_from_first_heading_and_date_from_last_updated(self):
        node, _, _ = _parse("planning/sample-concept.md")
        self.assertEqual(node["title"], "Sample Concept")
        self.assertEqual(node["date"], "2026-01-03")

    def test_doc_without_frontmatter_has_heading_title_and_null_date(self):
        node, _, _ = _parse("planning/README.md")
        self.assertEqual(node["title"], "Sample Planning Index")
        self.assertIsNone(node["date"])

    def test_doc_with_neither_heading_nor_date_is_minimal_with_warning(self):
        node, _, _ = _parse("planning/empty-doc.md")
        self.assertEqual(node["title"], "Empty doc")
        self.assertIsNone(node["date"])
        self.assertEqual(len(node["_warnings"]), 1)

    def test_body_craft_path_yields_references_candidate(self):
        _, links, _ = _parse("planning/sample-concept.md")
        self.assertEqual(
            [l["raw_value"] for l in links],
            ["cycles/7-sample-cycle/stories/1-data-layer.md"],
        )

    def test_same_named_nested_readmes_get_distinct_ids(self):
        node_a, _, _ = _parse("planning/README.md")
        node_b, _, _ = _parse("planning/nested-area/README.md")
        self.assertNotEqual(node_a["id"], node_b["id"])


if __name__ == "__main__":
    unittest.main()
