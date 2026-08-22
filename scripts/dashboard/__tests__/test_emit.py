import json
import os
import re
import sys
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

from src import emit, paths


class EmitTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = self._tmp.name
        os.makedirs(os.path.join(self.root, ".craft"))
        paths.reset_log()

    def tearDown(self):
        self._tmp.cleanup()

    def _read(self, rel):
        with open(
            os.path.join(self.root, ".craft", "graph", rel),
            encoding="utf-8",
        ) as f:
            return f.read()


class TestMirrors(EmitTestCase):
    def test_record_mirror_round_trips_markdown_exactly(self):
        record = "---\nname: sample\n---\n\n# Heading\n\nBody with unicode: café\n"
        emit.write_mirror(self.root, "story--sample", record)
        text = self._read(os.path.join("records", "story--sample.js"))
        payload = re.search(
            r'window\.CRAFT_RECORDS\["story--sample"\] = (.*);\n\Z',
            text,
            re.S,
        )
        self.assertIsNotNone(payload)
        self.assertEqual(json.loads(payload.group(1)), record)

    def test_script_close_tag_is_escaped(self):
        record = "A body containing </script> inside prose.\n"
        emit.write_mirror(self.root, "story--closer", record)
        text = self._read(os.path.join("records", "story--closer.js"))
        self.assertNotIn("</script>", text)
        payload = text.split(" = ", 2)[2].rstrip(";\n")
        self.assertEqual(json.loads(payload), record)

    def test_line_separator_is_escaped(self):
        record = "before after"
        emit.write_mirror(self.root, "story--ls", record)
        text = self._read(os.path.join("records", "story--ls.js"))
        self.assertNotIn(" ", text)
        payload = text.split(" = ", 2)[2].rstrip(";\n")
        self.assertEqual(json.loads(payload), record)


class TestOrphanSweep(EmitTestCase):
    def test_orphan_mirrors_are_removed(self):
        emit.write_mirror(self.root, "story--keep", "keep\n")
        emit.write_mirror(self.root, "story--gone", "gone\n")
        removed = emit.sweep_orphans(self.root, {"story--keep"})
        self.assertEqual(removed, 1)
        records = os.listdir(
            os.path.join(self.root, ".craft", "graph", "records")
        )
        self.assertEqual(records, ["story--keep.js"])


class TestCrashSafety(EmitTestCase):
    def test_stale_temp_file_does_not_corrupt_existing_graph(self):
        emit.write_graph(self.root, {"version": 1, "nodes": []})
        graph_dir = os.path.join(self.root, ".craft", "graph")
        stale = os.path.join(graph_dir, "graph.js.tmp")
        with open(stale, "w", encoding="utf-8") as f:
            f.write("truncat")
        emit.write_graph(self.root, {"version": 1, "nodes": ["changed"]})
        text = self._read("graph.js")
        self.assertIn("changed", text)
        self.assertTrue(text.endswith(";\n"))


class TestWriteAll(EmitTestCase):
    def test_write_all_lands_graph_and_mirrors(self):
        graph = {"version": 1, "nodes": []}
        texts = {"story--sample": "record body\n"}
        written, removed = emit.write_all(self.root, graph, texts)
        self.assertEqual(written, 2)
        self.assertEqual(removed, 0)
        self.assertTrue(
            os.path.isfile(
                os.path.join(self.root, ".craft", "graph", "graph.js")
            )
        )
        self.assertTrue(
            os.path.isfile(
                os.path.join(
                    self.root,
                    ".craft",
                    "graph",
                    "records",
                    "story--sample.js",
                )
            )
        )


if __name__ == "__main__":
    unittest.main()
