import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

import corpus_helper
from src import assemble, paths, resolve


def _make_node(node_id, node_type, path, name, date):
    return {
        "id": node_id,
        "type": node_type,
        "date": date,
        "_path": path,
        "_name": name,
    }


SYNTH_NODES = [
    _make_node(
        "story--cycles--7-sample-cycle--stories--3-widget-panel",
        "story",
        "cycles/7-sample-cycle/stories/3-widget-panel.md",
        "widget-panel",
        "2026-01-05",
    ),
    _make_node(
        "tweak--tweaks--tweak-sample-polish",
        "tweak",
        "tweaks/tweak-sample-polish.md",
        "sample-polish",
        "2026-03-02",
    ),
]


class TestLinkPass(unittest.TestCase):
    def test_resolving_links_become_edges(self):
        links = [
            resolve.raw_link(
                SYNTH_NODES[1]["id"], "source_story", "widget-panel",
                "source_story", expect={"story"},
            )
        ]
        edges, notes = assemble.link_pass(SYNTH_NODES, links)
        self.assertEqual(
            edges,
            [
                {
                    "source": SYNTH_NODES[1]["id"],
                    "target": SYNTH_NODES[0]["id"],
                    "kind": "source_story",
                }
            ],
        )
        self.assertEqual(notes, [])

    def test_unresolved_link_becomes_annotation(self):
        links = [
            resolve.raw_link(
                SYNTH_NODES[0]["id"], "references", "no-such-thing", "body_path"
            )
        ]
        edges, notes = assemble.link_pass(SYNTH_NODES, links)
        self.assertEqual(edges, [])
        self.assertEqual(notes[0]["reason"], "unresolved")

    def test_sentinel_link_becomes_sentinel_annotation(self):
        links = [
            resolve.raw_link(
                SYNTH_NODES[0]["id"], "references", "none-matched", "body_path"
            )
        ]
        _, notes = assemble.link_pass(SYNTH_NODES, links)
        self.assertEqual(notes[0]["reason"], "sentinel")

    def test_self_edge_is_dropped_and_annotated(self):
        links = [
            resolve.raw_link(
                SYNTH_NODES[0]["id"], "references", "widget-panel",
                "body_wikilink",
            )
        ]
        edges, notes = assemble.link_pass(SYNTH_NODES, links)
        self.assertEqual(edges, [])
        self.assertEqual(len(notes), 1)

    def test_duplicate_edges_collapse_to_one(self):
        link = resolve.raw_link(
            SYNTH_NODES[1]["id"], "source_story", "widget-panel", "source_story"
        )
        edges, _ = assemble.link_pass(SYNTH_NODES, [link, dict(link)])
        self.assertEqual(len(edges), 1)

    def test_split_graduated_to_yields_two_edges_plus_prose_annotation(self):
        extra = _make_node(
            "mockup--mockups--2026-01-15-sample-hero--record",
            "mockup",
            "mockups/2026-01-15-sample-hero/record.md",
            "2026-01-15-sample-hero",
            "2026-01-15",
        )
        nodes = SYNTH_NODES + [extra]
        links = [
            resolve.raw_link(
                extra["id"],
                "graduated_to",
                "SPLIT: (1) tweak-sample-polish (tweak) (2) 3-widget-panel (story)",
                "graduated_to",
                expect={"story", "tweak", "notebook"},
            )
        ]
        edges, notes = assemble.link_pass(nodes, links)
        targets = sorted(e["target"] for e in edges)
        self.assertEqual(
            targets,
            sorted([SYNTH_NODES[0]["id"], SYNTH_NODES[1]["id"]]),
        )
        self.assertEqual([n["reason"] for n in notes], ["prose"])

    def test_emitted_kinds_stay_inside_the_closed_set(self):
        root = corpus_helper.corpus_root()
        try:
            result = assemble.build(root)
        finally:
            corpus_helper.cleanup(root)
        kinds = {e["kind"] for e in result["graph"]["edges"]}
        self.assertTrue(kinds <= assemble.EDGE_KINDS, kinds)


class TestBuildOnCorpus(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = corpus_helper.corpus_root()
        cls.result = assemble.build(cls.root)
        cls.graph = cls.result["graph"]

    @classmethod
    def tearDownClass(cls):
        corpus_helper.cleanup(cls.root)

    def test_node_count_matches_fixture_corpus(self):
        self.assertEqual(len(self.graph["nodes"]), 25)

    def test_bullet_form_dependencies_resolve_to_edges(self):
        edges = {
            (e["kind"], e["source"], e["target"])
            for e in self.graph["edges"]
        }
        source = "story--cycles--8-other-cycle--stories--4-bullet-deps"
        self.assertIn(
            (
                "blocked_by",
                source,
                "story--cycles--7-sample-cycle--stories--3-widget-panel",
            ),
            edges,
        )
        self.assertIn(
            (
                "blocked_by",
                source,
                "story--cycles--7-sample-cycle--stories--1-data-layer",
            ),
            edges,
        )

    def test_expected_lineage_edges_exist(self):
        edges = {
            (e["kind"], e["source"], e["target"])
            for e in self.graph["edges"]
        }
        self.assertIn(
            (
                "graduated_to",
                "dial--dials--2026-02-20-panel-spacing",
                "tweak--tweaks--tweak-sample-polish",
            ),
            edges,
        )
        self.assertIn(
            (
                "belongs_to",
                "story--cycles--7-sample-cycle--stories--3-widget-panel",
                "cycle--cycles--7-sample-cycle--cycle",
            ),
            edges,
        )

    def test_boundary_holds_no_read_outside_craft_no_write_outside_graph(
        self,
    ):
        real_root = os.path.realpath(self.root)
        craft = os.path.join(real_root, ".craft")
        graph = os.path.join(craft, "graph")
        for kind, accessed in paths.access_log():
            if kind == "read":
                self.assertTrue(accessed.startswith(craft + os.sep), accessed)
            else:
                self.assertTrue(
                    accessed.startswith(graph + os.sep), accessed
                )

    def test_public_nodes_carry_no_internal_keys(self):
        for node in self.graph["nodes"]:
            for key in node:
                self.assertFalse(key.startswith("_"), key)

    def test_unresolved_count_matches_annotations(self):
        expected = sum(
            1
            for a in self.graph["annotations"]
            if a["reason"] == "unresolved"
        )
        self.assertEqual(self.graph["build"]["unresolved"], expected)


class TestEmptyCorpus(unittest.TestCase):
    def test_empty_corpus_emits_valid_graph_with_null_keystone(self):
        import tempfile

        root = tempfile.mkdtemp()
        os.makedirs(os.path.join(root, ".craft", "design"))
        try:
            result = assemble.build(root)
        finally:
            corpus_helper.cleanup(root)
        graph = result["graph"]
        self.assertEqual(graph["nodes"], [])
        self.assertEqual(graph["edges"], [])
        self.assertEqual(graph["annotations"], [])
        self.assertIsNone(graph["stats"]["birthday"])
        self.assertEqual(graph["stats"]["days_of_craft"], 0)
        self.assertIsNone(graph["stats"]["keystone"])
        self.assertEqual(graph["tokens"], {})


if __name__ == "__main__":
    unittest.main()
