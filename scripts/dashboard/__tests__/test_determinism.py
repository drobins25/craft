import json
import os
import re
import subprocess
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

import corpus_helper
from src import assemble


def _snapshot(root):
    dashboard = os.path.join(root, ".craft", "dashboard")
    files = {}
    for dirpath, _, filenames in os.walk(dashboard):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            with open(full, "rb") as f:
                files[os.path.relpath(full, dashboard)] = f.read()
    return files


class TestDeterminism(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = corpus_helper.corpus_root()
        cls.first = assemble.build(cls.root)
        cls.first_files = _snapshot(cls.root)
        cls.second = assemble.build(cls.root)
        cls.second_files = _snapshot(cls.root)

    @classmethod
    def tearDownClass(cls):
        corpus_helper.cleanup(cls.root)

    def test_double_build_is_byte_identical(self):
        self.assertEqual(set(self.first_files), set(self.second_files))
        for rel in self.first_files:
            self.assertEqual(
                self.first_files[rel], self.second_files[rel], rel
            )

    def test_second_run_writes_zero_files(self):
        self.assertGreater(self.first["written"], 0)
        self.assertEqual(self.second["written"], 0)

    def test_graph_js_contains_no_timestamp(self):
        text = self.first_files["graph.js"].decode("utf-8")
        self.assertIsNone(re.search(r"\d{2}:\d{2}:\d{2}", text))
        self.assertNotIn("generated", text)

    def test_graph_js_contains_no_environment_derived_path(self):
        # Content-derived paths quoted from records are fine; the build
        # environment's own paths must never leak into the output.
        text = self.first_files["graph.js"].decode("utf-8")
        self.assertNotIn(os.path.realpath(self.root), text)
        self.assertNotIn(self.root, text)
        self.assertNotIn(os.getcwd(), text)

    def test_node_ordering_is_sorted_by_date_then_id(self):
        nodes = self.first["graph"]["nodes"]
        keys = [(n.get("date") or "", n["id"]) for n in nodes]
        self.assertEqual(keys, sorted(keys))

    def test_edge_ordering_is_sorted_by_kind_source_target(self):
        edges = self.first["graph"]["edges"]
        keys = [(e["kind"], e["source"], e["target"]) for e in edges]
        self.assertEqual(keys, sorted(keys))

    def test_days_of_craft_is_stable_across_runs(self):
        self.assertEqual(
            self.first["graph"]["stats"]["days_of_craft"],
            self.second["graph"]["stats"]["days_of_craft"],
        )


class TestCli(unittest.TestCase):
    def test_build_py_prints_one_json_status_line(self):
        root = corpus_helper.corpus_root()
        try:
            proc = subprocess.run(
                [
                    sys.executable,
                    os.path.join(
                        os.path.dirname(_HERE), "build.py"
                    ),
                    "--root",
                    root,
                ],
                capture_output=True,
                text=True,
            )
        finally:
            corpus_helper.cleanup(root)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        lines = proc.stdout.strip().split("\n")
        self.assertEqual(len(lines), 1)
        status = json.loads(lines[0])
        self.assertEqual(status["status"], "ok")
        self.assertGreater(status["nodes"], 0)


if __name__ == "__main__":
    unittest.main()
