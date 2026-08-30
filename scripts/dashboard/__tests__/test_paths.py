import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src import paths


class PathsTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = self._tmp.name
        os.makedirs(os.path.join(self.root, ".craft", "design"))
        with open(
            os.path.join(self.root, ".craft", "record.md"), "w", encoding="utf-8"
        ) as f:
            f.write("hello\n")
        paths.reset_log()

    def tearDown(self):
        self._tmp.cleanup()

    def test_read_inside_craft(self):
        self.assertEqual(paths.read_under_craft(self.root, "record.md"), "hello\n")

    def test_read_rejects_escaping_relative_path(self):
        with self.assertRaises(paths.BoundaryError):
            paths.read_under_craft(self.root, "../../etc/passwd")

    def test_read_rejects_absolute_path_outside_craft(self):
        with self.assertRaises(paths.BoundaryError):
            paths.read_under_craft(self.root, "/etc/passwd")

    def test_symlink_escaping_project_raises(self):
        outside = os.path.join(self.root, "outside.txt")
        with open(outside, "w", encoding="utf-8") as f:
            f.write("secret\n")
        link = os.path.join(self.root, ".craft", "link.md")
        os.symlink(outside, link)
        with self.assertRaises(paths.BoundaryError):
            paths.read_under_craft(self.root, "link.md")

    def test_write_inside_graph(self):
        wrote = paths.write_under_graph(self.root, "graph.js", "data")
        self.assertTrue(wrote)
        target = os.path.join(self.root, ".craft", "graph", "graph.js")
        with open(target, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), "data")

    def test_write_rejects_path_outside_graph(self):
        with self.assertRaises(paths.BoundaryError):
            paths.write_under_graph(self.root, "../graph.js", "data")

    def test_write_rejects_symlink_escape(self):
        outside = os.path.join(self.root, "outside.txt")
        with open(outside, "w", encoding="utf-8") as f:
            f.write("secret\n")
        paths.write_under_graph(self.root, "graph.js", "data")
        link = os.path.join(self.root, ".craft", "graph", "escape.js")
        os.symlink(outside, link)
        with self.assertRaises(paths.BoundaryError):
            paths.write_under_graph(self.root, "escape.js", "changed")

    def test_identical_write_is_skipped(self):
        self.assertTrue(paths.write_under_graph(self.root, "graph.js", "data"))
        self.assertFalse(paths.write_under_graph(self.root, "graph.js", "data"))

    def test_changed_write_lands(self):
        paths.write_under_graph(self.root, "graph.js", "one")
        self.assertTrue(paths.write_under_graph(self.root, "graph.js", "two"))

    def test_access_log_records_reads_and_writes(self):
        paths.read_under_craft(self.root, "record.md")
        paths.write_under_graph(self.root, "graph.js", "data")
        kinds = [kind for kind, _ in paths.access_log()]
        self.assertEqual(kinds, ["read", "write"])

    def test_write_creates_graph_directory(self):
        self.assertFalse(
            os.path.isdir(os.path.join(self.root, ".craft", "graph"))
        )
        paths.write_under_graph(self.root, "records/sample.js", "data")
        self.assertTrue(
            os.path.isfile(
                os.path.join(
                    self.root, ".craft", "graph", "records", "sample.js"
                )
            )
        )


if __name__ == "__main__":
    unittest.main()
