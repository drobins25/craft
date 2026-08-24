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
        "tweak", craft_rel, corpus_helper.read_fixture(craft_rel)
    )


POLISH = "tweaks/tweak-sample-polish.md"
PROSE = "tweaks/tweak-prose-source.md"
LEGACY = "tweaks/legacy-heading-tweak.md"


class TestParseTweak(unittest.TestCase):
    def test_envelope_maps_name_created_status_surface(self):
        node, _, _ = _parse(POLISH)
        self.assertEqual(node["title"], "Tweak sample polish")
        self.assertEqual(node["date"], "2026-03-02")
        self.assertEqual(node["status"], "accepted")
        self.assertEqual(node["surface"], "panel-toolbar")

    def test_legacy_tweak_falls_back_to_heading_and_date_with_warning(self):
        node, _, _ = _parse(LEGACY)
        self.assertEqual(node["title"], "Legacy toolbar nudge")
        self.assertEqual(node["date"], "2026-02-20")
        self.assertEqual(len(node["_warnings"]), 1)

    def test_prose_source_story_becomes_prose_annotation_not_link(self):
        _, links, annotations = _parse(PROSE)
        self.assertEqual(
            [l for l in links if l["kind"] == "source_story"], []
        )
        prose = [
            a for a in annotations
            if a["field"] == "source_story" and a["reason"] == "prose"
        ]
        self.assertEqual(len(prose), 1)
        self.assertEqual(prose[0]["value"], "hero section (pre-existing)")

    def test_slug_source_story_yields_link(self):
        _, links, _ = _parse(POLISH)
        source = [l for l in links if l["kind"] == "source_story"]
        self.assertEqual([l["raw_value"] for l in source], ["widget-panel"])

    def test_reapplies_and_grew_from_yield_tweak_scoped_links(self):
        _, links, _ = _parse(PROSE)
        for kind in ("reapplies", "grew_from"):
            matches = [l for l in links if l["kind"] == kind]
            self.assertEqual(
                [l["raw_value"] for l in matches], ["tweak-sample-polish"], kind
            )
            self.assertEqual(matches[0]["expect"], {"tweak"})

    def test_mockup_and_dial_fields_yield_links(self):
        _, polish_links, _ = _parse(POLISH)
        _, prose_links, _ = _parse(PROSE)
        self.assertEqual(
            [l["raw_value"] for l in polish_links if l["kind"] == "mockup"],
            ["2026-01-15-sample-hero"],
        )
        self.assertEqual(
            [l["raw_value"] for l in prose_links if l["kind"] == "dial"],
            ["2026-02-20-panel-spacing"],
        )

    def test_satisfied_todo_slug_yields_link(self):
        _, links, _ = _parse(POLISH)
        matches = [l for l in links if l["kind"] == "satisfied_todo"]
        self.assertEqual([l["raw_value"] for l in matches], ["sample-todo"])


if __name__ == "__main__":
    unittest.main()
