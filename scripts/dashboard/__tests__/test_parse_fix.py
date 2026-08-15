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
        "fix", craft_rel, corpus_helper.read_fixture(craft_rel)
    )


BROKEN = "fixes/sample-broken-widget.md"
LEGACY = "fixes/sample-legacy-fix.md"


class TestParseFix(unittest.TestCase):
    def test_envelope_maps_name_created_status_with_humanized_title(self):
        node, _, _ = _parse(BROKEN)
        self.assertEqual(node["title"], "Sample broken widget")
        self.assertEqual(node["date"], "2026-03-05")
        self.assertEqual(node["status"], "accepted")

    def test_empty_source_fields_yield_sentinel_annotations_no_links(self):
        _, links, annotations = _parse(LEGACY)
        self.assertEqual(links, [])
        reasons = {
            (a["field"], a["reason"])
            for a in annotations
        }
        self.assertIn(("source_story", "sentinel"), reasons)
        self.assertIn(("source_cycle", "sentinel"), reasons)

    def test_satisfied_todo_none_matched_yields_sentinel_annotation(self):
        _, _, annotations = _parse(BROKEN)
        matches = [
            a for a in annotations
            if a["field"] == "satisfied_todo" and a["reason"] == "sentinel"
        ]
        self.assertEqual(len(matches), 1)

    def test_source_story_and_cycle_yield_links(self):
        _, links, _ = _parse(BROKEN)
        kinds = {(l["kind"], l["raw_value"]) for l in links}
        self.assertIn(("source_story", "widget-panel"), kinds)
        self.assertIn(("source_cycle", "sample-cycle"), kinds)

    def test_belongs_to_derives_from_source_cycle(self):
        _, links, _ = _parse(BROKEN)
        belongs = [l for l in links if l["kind"] == "belongs_to"]
        self.assertEqual(len(belongs), 1)
        self.assertEqual(belongs[0]["raw_value"], "sample-cycle")


if __name__ == "__main__":
    unittest.main()
