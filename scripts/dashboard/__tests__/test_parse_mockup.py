import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

import corpus_helper
from src import registry, resolve


HERO = "mockups/2026-01-15-sample-hero/record.md"
FLOW = "mockups/2026-02-15-sample-flow/record.md"


def _parse(craft_rel):
    return registry.parse_file(
        "mockup", craft_rel, corpus_helper.read_fixture(craft_rel)
    )


class TestParseMockup(unittest.TestCase):
    def test_envelope_maps_name_created_status(self):
        node, _, _ = _parse(HERO)
        self.assertEqual(node["date"], "2026-01-15")
        self.assertEqual(node["status"], "graduated-story")
        self.assertEqual(node["_name"], "2026-01-15-sample-hero")

    def test_graduated_to_split_raw_value_extracts_two_targets(self):
        _, links, _ = _parse(HERO)
        graduated = [l for l in links if l["kind"] == "graduated_to"]
        self.assertEqual(len(graduated), 1)
        targets = resolve.extract_targets(graduated[0]["raw_value"])
        self.assertEqual(targets, ["tweak-sample-polish", "3-widget-panel"])

    def test_graduated_to_template_placeholder_yields_sentinel_annotation(self):
        _, links, annotations = _parse(FLOW)
        self.assertEqual([l for l in links if l["kind"] == "graduated_to"], [])
        sentinel = [
            a for a in annotations
            if a["field"] == "graduated_to" and a["reason"] == "sentinel"
        ]
        self.assertEqual(len(sentinel), 1)

    def test_solidify_outcome_always_yields_annotation_never_link(self):
        _, links, annotations = _parse(HERO)
        self.assertEqual(
            [l for l in links if l["field"] == "solidify_outcome"], []
        )
        notes = [a for a in annotations if a["field"] == "solidify_outcome"]
        self.assertEqual(len(notes), 1)

    def test_origin_yields_tweak_link(self):
        _, links, _ = _parse(HERO)
        origin = [l for l in links if l["kind"] == "origin"]
        self.assertEqual(
            [l["raw_value"] for l in origin], ["tweak-sample-polish"]
        )
        self.assertEqual(origin[0]["expect"], {"tweak"})


if __name__ == "__main__":
    unittest.main()
