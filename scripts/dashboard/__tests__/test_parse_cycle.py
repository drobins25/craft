import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

import corpus_helper
from src import registry


SAMPLE = "cycles/7-sample-cycle/cycle.yaml"
OTHER = "cycles/8-other-cycle/cycle.yaml"


def _parse(craft_rel):
    return registry.parse_file(
        "cycle", craft_rel, corpus_helper.read_fixture(craft_rel)
    )


class TestParseCycle(unittest.TestCase):
    def test_cycle_yaml_parses_without_frontmatter_fence(self):
        node, _, _ = _parse(SAMPLE)
        self.assertEqual(node["title"], "Sample Cycle")
        self.assertEqual(node["date"], "2026-01-01")
        self.assertEqual(node["status"], "active")

    def test_node_id_represents_the_cycle_directory(self):
        node, _, _ = _parse(SAMPLE)
        self.assertEqual(node["id"], "cycle--cycles--7-sample-cycle--cycle")

    def test_source_concept_list_yields_one_references_link_per_path(self):
        _, links, _ = _parse(SAMPLE)
        refs = [l for l in links if l["field"] == "source_concept"]
        self.assertEqual(
            [l["raw_value"] for l in refs], ["planning/sample-concept.md"]
        )
        self.assertTrue(all(l["kind"] == "references" for l in refs))

    def test_empty_source_concept_yields_no_links(self):
        _, links, _ = _parse(OTHER)
        self.assertEqual(links, [])

    def test_no_membership_links_are_emitted(self):
        _, links, _ = _parse(SAMPLE)
        self.assertEqual([l for l in links if l["kind"] == "belongs_to"], [])


if __name__ == "__main__":
    unittest.main()
