import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

import corpus_helper
from src import registry


LANDED = "dials/2026-02-20-panel-spacing.md"
EXITED = "dials/2026-02-21-exit-dial.md"


def _parse(craft_rel):
    return registry.parse_file(
        "dial", craft_rel, corpus_helper.read_fixture(craft_rel)
    )


class TestParseDial(unittest.TestCase):
    def test_discriminated_by_source_dial_and_identified_by_slug(self):
        node, _, _ = _parse(LANDED)
        self.assertEqual(node["_name"], "2026-02-20-panel-spacing")
        self.assertEqual(node["_warnings"], [])

    def test_missing_discriminator_warns(self):
        text = corpus_helper.read_fixture(LANDED).replace(
            "source: dial", "source: other"
        )
        node, _, _ = registry.parse_file("dial", LANDED, text)
        self.assertEqual(len(node["_warnings"]), 1)

    def test_status_derives_from_outcome(self):
        self.assertEqual(_parse(LANDED)[0]["status"], "landed")
        self.assertEqual(_parse(EXITED)[0]["status"], "exit")

    def test_surface_and_kind_are_envelope_attributes(self):
        node, _, _ = _parse(LANDED)
        self.assertEqual(node["surface"], "panel-toolbar")
        self.assertEqual(node["kind"], "spacing")

    def test_offered_comma_string_is_not_treated_as_links(self):
        _, links, _ = _parse(LANDED)
        self.assertEqual([l for l in links if l["field"] == "offered"], [])

    def test_graduated_to_yields_link_and_empty_yields_sentinel(self):
        _, landed_links, _ = _parse(LANDED)
        graduated = [l for l in landed_links if l["kind"] == "graduated_to"]
        self.assertEqual(
            [l["raw_value"] for l in graduated], ["tweak-sample-polish"]
        )
        _, exit_links, exit_annotations = _parse(EXITED)
        self.assertEqual(
            [l for l in exit_links if l["kind"] == "graduated_to"], []
        )
        sentinel = [
            a for a in exit_annotations
            if a["field"] == "graduated_to" and a["reason"] == "sentinel"
        ]
        self.assertEqual(len(sentinel), 1)


class TestTruncatedFiles(unittest.TestCase):
    def test_every_parser_survives_a_truncated_file(self):
        truncated = "---\nname: truncated-record"
        for record_type in sorted(registry.PARSERS):
            node, links, annotations = registry.parse_file(
                record_type, "sample/truncated.md", truncated
            )
            self.assertEqual(node["type"], record_type)
            self.assertTrue(node["id"])
            self.assertIsInstance(links, list)
            self.assertIsInstance(annotations, list)


if __name__ == "__main__":
    unittest.main()
