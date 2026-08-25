import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src import identity


ID_PATTERN = re.compile(r"^[a-z0-9-]+(--[A-Za-z0-9._-]+)+$")


class TestNodeId(unittest.TestCase):
    def test_same_named_nested_files_get_distinct_ids(self):
        paths = [
            "planning/README.md",
            "planning/sample-area/README.md",
            "planning/another-area/README.md",
            "planning/third-area/README.md",
        ]
        ids = [identity.node_id("planning", p) for p in paths]
        self.assertEqual(len(set(ids)), 4)

    def test_id_is_filename_safe(self):
        nid = identity.node_id(
            "story", "cycles/7-sample-cycle/stories/3-widget panel!.md"
        )
        self.assertNotIn("/", nid)
        self.assertTrue(ID_PATTERN.match(nid), nid)

    def test_extension_is_stripped(self):
        self.assertEqual(
            identity.node_id("cycle", "cycles/7-sample-cycle/cycle.yaml"),
            "cycle--cycles--7-sample-cycle--cycle",
        )

    def test_id_is_lowercased(self):
        nid = identity.node_id("planning", "planning/README.md")
        self.assertEqual(nid, nid.lower())


if __name__ == "__main__":
    unittest.main()
