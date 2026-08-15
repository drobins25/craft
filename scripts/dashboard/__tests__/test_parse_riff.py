import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

import corpus_helper
from src import registry


RIFF = "riff/notes/2026-02-05-sample-riff.md"


class TestParseRiff(unittest.TestCase):
    def test_envelope_maps_riff_and_date(self):
        node, _, _ = registry.parse_file(
            "riff", RIFF, corpus_helper.read_fixture(RIFF)
        )
        self.assertEqual(
            node["title"],
            "the widget panel rethink - where the panel learned to breathe",
        )
        self.assertEqual(node["date"], "2026-02-05")
        self.assertIsNone(node["status"])

    def test_no_structured_links(self):
        _, links, annotations = registry.parse_file(
            "riff", RIFF, corpus_helper.read_fixture(RIFF)
        )
        self.assertEqual(links, [])
        self.assertEqual(annotations, [])

    def test_body_wikilink_yields_reference_candidate(self):
        text = corpus_helper.read_fixture(RIFF) + "\nWe kept [[1-data-layer]].\n"
        _, links, _ = registry.parse_file("riff", RIFF, text)
        self.assertEqual([l["raw_value"] for l in links], ["1-data-layer"])


if __name__ == "__main__":
    unittest.main()
