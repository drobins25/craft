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

    def test_source_cycle_yields_exactly_one_link(self):
        # No belongs_to twin: vocabulary.KINDS["source_cycle"]["membership"]
        # is what keeps a fix in its cluster now, so a fix's own single
        # source_cycle edge carries both the label and the layout.
        _, links, _ = _parse(BROKEN)
        cycle_links = [l for l in links if l["kind"] == "source_cycle"]
        self.assertEqual(len(cycle_links), 1)
        self.assertEqual(cycle_links[0]["raw_value"], "sample-cycle")
        self.assertEqual([l for l in links if l["kind"] == "belongs_to"], [])

    def test_decorated_source_fields_still_link_on_the_clean_slug(self):
        # source_story and source_cycle both carry a parenthetical aside in
        # the fixture - the link uses the stripped slug, not the raw text.
        _, links, _ = _parse(BROKEN)
        kinds = {(l["kind"], l["raw_value"]) for l in links}
        self.assertIn(("source_story", "widget-panel"), kinds)
        self.assertIn(("source_cycle", "sample-cycle"), kinds)

    def test_decorated_source_fields_also_yield_prose_annotations(self):
        _, _, annotations = _parse(BROKEN)
        prose = {
            (a["field"], a["value"])
            for a in annotations
            if a["reason"] == "prose"
        }
        self.assertIn(
            ("source_story", "widget-panel (needs the store first)"), prose
        )
        self.assertIn(
            ("source_cycle", "sample-cycle (surfaced during a live QA pass)"),
            prose,
        )

    def test_negative_declaration_with_parenthetical_yields_sentinel(self):
        # "none (design pattern shift)" - the parenthetical must be stripped
        # before the sentinel check, or this manufactures a failed lookup.
        _, links, annotations = _parse(LEGACY)
        self.assertEqual([l for l in links if l["field"] == "source_story"], [])
        sentinel = [
            a
            for a in annotations
            if a["field"] == "source_story" and a["reason"] == "sentinel"
        ]
        self.assertEqual(len(sentinel), 1)
        self.assertEqual(sentinel[0]["value"], "none (design pattern shift)")

if __name__ == "__main__":
    unittest.main()
