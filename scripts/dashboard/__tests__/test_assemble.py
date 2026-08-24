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
                SYNTH_NODES[1]["id"], "tweak", "source_story", "widget-panel"
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
                SYNTH_NODES[0]["id"], "story", "body_path", "no-such-thing"
            )
        ]
        edges, notes = assemble.link_pass(SYNTH_NODES, links)
        self.assertEqual(edges, [])
        self.assertEqual(notes[0]["reason"], "unresolved")

    def test_sentinel_link_becomes_sentinel_annotation(self):
        links = [
            resolve.raw_link(
                SYNTH_NODES[0]["id"], "story", "body_path", "none-matched"
            )
        ]
        _, notes = assemble.link_pass(SYNTH_NODES, links)
        self.assertEqual(notes[0]["reason"], "sentinel")

    def test_self_edge_is_dropped_and_annotated(self):
        links = [
            resolve.raw_link(
                SYNTH_NODES[0]["id"], "story", "body_wikilink", "widget-panel"
            )
        ]
        edges, notes = assemble.link_pass(SYNTH_NODES, links)
        self.assertEqual(edges, [])
        self.assertEqual(len(notes), 1)
        self.assertEqual(notes[0]["reason"], "self-reference")

    def test_duplicate_edges_collapse_to_one(self):
        link = resolve.raw_link(
            SYNTH_NODES[1]["id"], "tweak", "source_story", "widget-panel"
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
                "mockup",
                "graduated_to",
                "SPLIT: (1) tweak-sample-polish (tweak) (2) 3-widget-panel (story)",
            )
        ]
        edges, notes = assemble.link_pass(nodes, links)
        targets = sorted(e["target"] for e in edges)
        self.assertEqual(
            targets,
            sorted([SYNTH_NODES[0]["id"], SYNTH_NODES[1]["id"]]),
        )
        self.assertEqual([n["reason"] for n in notes], ["prose"])

    def test_comma_split_prose_fragment_annotated_as_prose_not_unresolved(
        self,
    ):
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
                "mockup",
                "graduated_to",
                "3-widget-panel, this part is prose and never a slug",
            )
        ]
        edges, notes = assemble.link_pass(nodes, links)
        self.assertEqual(
            [e["target"] for e in edges], [SYNTH_NODES[0]["id"]]
        )
        self.assertEqual([n["reason"] for n in notes], ["prose"])

    def test_not_records_body_path_annotated_as_not_a_record(self):
        link = resolve.raw_link(
            SYNTH_NODES[0]["id"], "story", "body_path", "design/tokens.yaml"
        )
        edges, notes = assemble.link_pass(SYNTH_NODES, [link])
        self.assertEqual(edges, [])
        self.assertEqual([n["reason"] for n in notes], ["not-a-record"])

    def test_not_records_check_is_scoped_to_path_fields(self):
        # A dependency-style field value that happens to equal a
        # NOT_RECORDS directory name is a plain miss, not a not-a-record
        # citation - the check only applies to path-shaped fields.
        link = resolve.raw_link(
            SYNTH_NODES[0]["id"], "story", "blocked_by", "design"
        )
        edges, notes = assemble.link_pass(SYNTH_NODES, [link])
        self.assertEqual(edges, [])
        self.assertEqual([n["reason"] for n in notes], ["unresolved"])

    def test_folder_prefix_annotated_as_container_not_unresolved(self):
        link = resolve.raw_link(
            SYNTH_NODES[0]["id"], "story", "body_path", "tweaks"
        )
        edges, notes = assemble.link_pass(SYNTH_NODES, [link])
        self.assertEqual(edges, [])
        self.assertEqual([n["reason"] for n in notes], ["container"])

    def test_inverted_link_points_from_target_to_source(self):
        blocked = _make_node(
            "story--cycles--x--stories--blocked",
            "story",
            "cycles/x/stories/2-blocked.md",
            "blocked",
            "2026-04-01",
        )
        blocker = _make_node(
            "story--cycles--x--stories--blocker",
            "story",
            "cycles/x/stories/1-blocker.md",
            "blocker",
            "2026-03-01",
        )
        link = resolve.raw_link(blocked["id"], "story", "blocked_by", "blocker")
        edges, _ = assemble.link_pass([blocked, blocker], [link])
        self.assertEqual(len(edges), 1)
        self.assertEqual(edges[0]["kind"], "blocks")
        self.assertEqual(edges[0]["source"], blocker["id"])
        self.assertEqual(edges[0]["target"], blocked["id"])

    def test_story_dependency_naming_a_non_story_annotates_wrong_type(self):
        # The value names a real record - just not one of the kind the
        # field forbids - so it must say "wrong-type", not the generic
        # "not found" a plain miss gets.
        planning_node = _make_node(
            "planning--planning--sample-concept",
            "planning",
            "planning/sample-concept.md",
            "sample-concept",
            "2026-01-01",
        )
        nodes = SYNTH_NODES + [planning_node]
        links = [
            resolve.raw_link(
                SYNTH_NODES[0]["id"], "story", "blocked_by", "sample-concept"
            )
        ]
        edges, notes = assemble.link_pass(nodes, links)
        self.assertEqual(edges, [])
        self.assertEqual(notes[0]["reason"], "wrong-type")

    def test_emitted_kinds_stay_inside_the_closed_set(self):
        root = corpus_helper.corpus_root()
        try:
            result = assemble.build(root)
        finally:
            corpus_helper.cleanup(root)
        kinds = {e["kind"] for e in result["graph"]["edges"]}
        self.assertTrue(kinds <= assemble.EDGE_KINDS, kinds)

    def test_no_emitted_edge_carries_the_kind_blocked_by(self):
        root = corpus_helper.corpus_root()
        try:
            result = assemble.build(root)
        finally:
            corpus_helper.cleanup(root)
        kinds = {e["kind"] for e in result["graph"]["edges"]}
        self.assertNotIn("blocked_by", kinds)


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

    def test_fixture_corpus_unresolved_count_stays_at_or_below_ceiling(self):
        # THE FIRST TEST: the fixture corpus must express a None. sentinel,
        # a cross-type slug collision, a folder mention and a NOT_RECORDS
        # citation without leaving any of them recorded as an unclassified
        # failed lookup. Only the cross-type collision is a genuine miss by
        # design.
        unresolved = [
            a
            for a in self.graph["annotations"]
            if a["reason"] == "unresolved"
        ]
        self.assertLessEqual(
            len(unresolved),
            1,
            "unexpected unresolved entries: %s" % unresolved,
        )

    def test_none_dependency_yields_sentinel_not_unresolved(self):
        sentinels = [
            a
            for a in self.graph["annotations"]
            if a["reason"] == "sentinel" and a["value"] == "None."
        ]
        self.assertEqual(len(sentinels), 1)

    def test_cross_type_dependency_annotates_wrong_type(self):
        # sample-concept is a real planning record; a story's blocked_by
        # field forbids planning targets, so this is wrong-type rather
        # than an unclassified miss.
        unresolved = [
            a
            for a in self.graph["annotations"]
            if a["reason"] == "unresolved" and a["value"] == "sample-concept"
        ]
        self.assertEqual(unresolved, [])
        wrong_type = [
            a
            for a in self.graph["annotations"]
            if a["reason"] == "wrong-type" and a["value"] == "sample-concept"
        ]
        self.assertEqual(len(wrong_type), 1)
        self.assertEqual(
            wrong_type[0]["source_id"], "story--backlog--orphan-idea"
        )

    def test_folder_mention_yields_container_not_unresolved(self):
        unresolved_folder = [
            a
            for a in self.graph["annotations"]
            if a["reason"] == "unresolved" and "tweaks" in a["value"]
        ]
        self.assertEqual(unresolved_folder, [])
        container = [
            a for a in self.graph["annotations"] if a["reason"] == "container"
        ]
        self.assertEqual(len(container), 1)
        self.assertIn("tweaks", container[0]["value"])

    def test_not_records_citation_yields_not_a_record_not_unresolved(self):
        # design/tokens.yaml and research/... exercise the directory shape;
        # settings.yaml (cited bare, no directory segment) exercises the
        # root-level filename shape - both keyed the same way in
        # vocabulary.NOT_RECORDS and resolved by the same lookup.
        watched = {
            "design/tokens.yaml",
            "research/some-investigation.md",
            "settings.yaml",
            "notebook/assets/sample-asset.md",
            "mockups/2026-01-15-sample-hero/rounds/round-1.html",
        }
        unresolved_leaked = [
            a
            for a in self.graph["annotations"]
            if a["reason"] == "unresolved" and a["value"] in watched
        ]
        self.assertEqual(unresolved_leaked, [])
        not_a_record = {
            a["value"]
            for a in self.graph["annotations"]
            if a["reason"] == "not-a-record"
        }
        self.assertEqual(not_a_record, watched)

    def test_bullet_form_dependencies_resolve_to_edges(self):
        edges = {
            (e["kind"], e["source"], e["target"])
            for e in self.graph["edges"]
        }
        blocked = "story--cycles--8-other-cycle--stories--4-bullet-deps"
        # blocked_by is inverted at resolution: the edge points from the
        # blocker (the target the bullet names) to the blocked record.
        self.assertIn(
            (
                "blocks",
                "story--cycles--7-sample-cycle--stories--3-widget-panel",
                blocked,
            ),
            edges,
        )
        self.assertIn(
            (
                "blocks",
                "story--cycles--7-sample-cycle--stories--1-data-layer",
                blocked,
            ),
            edges,
        )

    def test_two_ended_dependency_yields_exactly_one_edge_blocker_to_blocked(
        self,
    ):
        edges = [
            e
            for e in self.graph["edges"]
            if e["kind"] == "blocks"
            and {e["source"], e["target"]}
            == {
                "story--cycles--7-sample-cycle--stories--1-data-layer",
                "story--cycles--7-sample-cycle--stories--3-widget-panel",
            }
        ]
        self.assertEqual(len(edges), 1)
        self.assertEqual(
            edges[0]["source"],
            "story--cycles--7-sample-cycle--stories--1-data-layer",
        )
        self.assertEqual(
            edges[0]["target"],
            "story--cycles--7-sample-cycle--stories--3-widget-panel",
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

    def test_graph_envelope_keys_are_unchanged_by_derived_registration(self):
        self.assertEqual(
            set(self.graph),
            {
                "version",
                "nodes",
                "edges",
                "annotations",
                "stats",
                "build",
                "vocabulary",
            },
        )

    def test_envelope_carries_a_vocabulary_block_and_version_stays_one(self):
        self.assertEqual(self.graph["version"], 1)
        self.assertEqual(
            set(self.graph["vocabulary"]),
            {"kinds", "statuses", "dial_outcomes", "types", "membership"},
        )

    def test_emitted_vocabulary_covers_every_kind_the_build_emitted(self):
        emitted_kinds = {e["kind"] for e in self.graph["edges"]}
        known_kinds = set(self.graph["vocabulary"]["kinds"])
        missing = emitted_kinds - known_kinds
        self.assertEqual(missing, set(), "kinds with no display words: %s" % missing)

    def test_emitted_vocabulary_covers_every_status_the_build_emitted(self):
        # Dial nodes hold a session outcome in the status slot, a separate
        # vocabulary axis (Content Direction: "dial records carry no
        # status by design"). Decision 11 is its own designed valve for an
        # unrecognised value there - this gate covers the status axis every
        # other record type validates against.
        emitted = {
            n["status"]
            for n in self.graph["nodes"]
            if n.get("status") and n["type"] != "dial"
        }
        known = set(self.graph["vocabulary"]["statuses"])
        missing = emitted - known
        self.assertEqual(missing, set(), "statuses with no display words: %s" % missing)

    def test_type_prefixed_citation_resolves(self):
        # S1: "story-data-layer" on 4-bullet-deps.md.
        values = {a["value"] for a in self.graph["annotations"]}
        self.assertNotIn("story-data-layer", values)

    def test_zero_padded_story_number_resolves(self):
        # S3: "01-data-layer" on 4-bullet-deps.md.
        values = {a["value"] for a in self.graph["annotations"]}
        self.assertNotIn("01-data-layer", values)

    def test_cycle_dir_story_stem_citation_resolves(self):
        # S4: "7-sample-cycle/3-widget-panel" on 4-bullet-deps.md - also
        # disambiguates the corpus's own ambiguous "widget-panel" stem.
        values = {a["value"] for a in self.graph["annotations"]}
        self.assertNotIn("7-sample-cycle/3-widget-panel", values)
        edges = {
            (e["kind"], e["source"], e["target"])
            for e in self.graph["edges"]
        }
        self.assertIn(
            (
                "blocks",
                "story--cycles--7-sample-cycle--stories--3-widget-panel",
                "story--cycles--8-other-cycle--stories--4-bullet-deps",
            ),
            edges,
        )

    def test_backticked_citation_resolves_with_no_prose_annotation(self):
        # S6: "`data-layer`" on 4-bullet-deps.md.
        prose_values = {
            a["value"] for a in self.graph["annotations"] if a["reason"] == "prose"
        }
        self.assertNotIn("`data-layer`", prose_values)
        self.assertNotIn(
            "`data-layer`", {a["value"] for a in self.graph["annotations"]}
        )

    def test_date_stripped_satisfied_todo_resolves(self):
        # S2: tweak-sample-polish.md's satisfied_todo moved to the
        # date-stripped form craft's own notebook helper actually writes.
        edges = {
            (e["kind"], e["source"], e["target"])
            for e in self.graph["edges"]
        }
        self.assertIn(
            (
                "satisfied_todo",
                "tweak--tweaks--tweak-sample-polish",
                "notebook--notebook--todos--2026-01-20-sample-todo",
            ),
            edges,
        )

    def test_record_folder_citation_resolves(self):
        # S5: 1-data-layer.md cites the mockup's containing folder bare.
        values = {a["value"] for a in self.graph["annotations"]}
        self.assertNotIn("mockups/2026-01-15-sample-hero", values)
        edges = {
            (e["kind"], e["source"], e["target"])
            for e in self.graph["edges"]
        }
        self.assertIn(
            (
                "references",
                "story--cycles--7-sample-cycle--stories--1-data-layer",
                "mockup--mockups--2026-01-15-sample-hero--record",
            ),
            edges,
        )

    def test_sibling_artifact_beside_record_md_resolves(self):
        # 1-data-layer.md also cites a sibling artifact inside that folder.
        values = {a["value"] for a in self.graph["annotations"]}
        self.assertNotIn(
            "mockups/2026-01-15-sample-hero/mockup.html", values
        )

    def test_source_story_naming_a_cycle_annotates_wrong_type(self):
        # legacy-heading-tweak.md's source_story names sample-cycle, a real
        # cycle record - the audit's S7 shape, end to end on the fixture
        # corpus rather than a synthetic node list.
        wrong_type = [
            a
            for a in self.graph["annotations"]
            if a["reason"] == "wrong-type" and a["value"] == "sample-cycle"
        ]
        self.assertEqual(len(wrong_type), 1)
        self.assertEqual(
            wrong_type[0]["source_id"], "tweak--tweaks--legacy-heading-tweak"
        )

    def test_fix_emits_exactly_one_edge_to_its_source_cycle(self):
        fix_id = "fix--fixes--sample-broken-widget"
        cycle_id = "cycle--cycles--7-sample-cycle--cycle"
        edges_to_cycle = [
            e
            for e in self.graph["edges"]
            if e["source"] == fix_id and e["target"] == cycle_id
        ]
        self.assertEqual(len(edges_to_cycle), 1, edges_to_cycle)
        self.assertEqual(edges_to_cycle[0]["kind"], "source_cycle")

    def test_every_fix_with_a_resolved_cycle_is_still_a_cluster_member(self):
        # Computed the way the page computes it: the first edge whose kind
        # is in the emitted membership set, pointing at a cycle.
        membership_kinds = set(self.graph["vocabulary"]["membership"])
        cycle_ids = {
            n["id"] for n in self.graph["nodes"] if n["type"] == "cycle"
        }
        fix_ids = {n["id"] for n in self.graph["nodes"] if n["type"] == "fix"}
        fixes_with_source_cycle = {
            e["source"]
            for e in self.graph["edges"]
            if e["kind"] == "source_cycle" and e["source"] in fix_ids
        }
        self.assertTrue(fixes_with_source_cycle)
        for fix_id in fixes_with_source_cycle:
            is_member = any(
                e["source"] == fix_id
                and e["kind"] in membership_kinds
                and e["target"] in cycle_ids
                for e in self.graph["edges"]
            )
            self.assertTrue(is_member, fix_id)


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
        self.assertNotIn("tokens", graph)


if __name__ == "__main__":
    unittest.main()
