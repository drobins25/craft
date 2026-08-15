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
        "story", craft_rel, corpus_helper.read_fixture(craft_rel)
    )


WIDGET = "cycles/7-sample-cycle/stories/3-widget-panel.md"
DATA_LAYER = "cycles/7-sample-cycle/stories/1-data-layer.md"
NUMBERED_DEPS = "cycles/8-other-cycle/stories/2-widget-panel.md"
BULLET_DEPS = "cycles/8-other-cycle/stories/4-bullet-deps.md"
BACKLOG = "backlog/orphan-idea.md"


def _links(links, kind):
    return [l for l in links if l["kind"] == kind]


def _notes(annotations, field=None, reason=None):
    out = annotations
    if field is not None:
        out = [a for a in out if a["field"] == field]
    if reason is not None:
        out = [a for a in out if a["reason"] == reason]
    return out


class TestEnvelope(unittest.TestCase):
    def test_envelope_fields_map_per_translation_table(self):
        node, _, _ = _parse(WIDGET)
        self.assertEqual(node["type"], "story")
        self.assertEqual(node["title"], "Widget Panel")
        self.assertEqual(node["date"], "2026-01-05")
        self.assertEqual(node["status"], "active")
        self.assertEqual(node["tags"], ["ui", "panel"])
        self.assertIsNone(node["surface"])

    def test_title_falls_back_to_humanized_stem(self):
        node, _, _ = _parse(BACKLOG)
        self.assertEqual(node["title"], "Orphan idea")


class TestChunks(unittest.TestCase):
    def test_chunk_list_parses_number_and_title_in_order(self):
        node, _, _ = _parse(WIDGET)
        chunks = node["chunks"]["list"]
        self.assertEqual([c["number"] for c in chunks], [1, 2, 3])
        self.assertEqual(chunks[0]["title"], "Panel shell")

    def test_chunk_status_derives_from_current_chunk(self):
        node, _, _ = _parse(WIDGET)
        statuses = [c["status"] for c in node["chunks"]["list"]]
        self.assertEqual(statuses, ["complete", "active", "pending"])

    def test_all_pending_when_current_chunk_is_zero(self):
        node, _, _ = _parse(BACKLOG)
        statuses = [c["status"] for c in node["chunks"]["list"]]
        self.assertEqual(statuses, ["pending", "pending"])

    def test_counters_land_in_envelope(self):
        node, _, _ = _parse(WIDGET)
        self.assertEqual(node["chunks"]["total"], 3)
        self.assertEqual(node["chunks"]["complete"], 1)

    def test_chunk_headings_inside_fenced_code_are_ignored(self):
        node, _, _ = _parse(WIDGET)
        numbers = [c["number"] for c in node["chunks"]["list"]]
        self.assertNotIn(9, numbers)


class TestDependencies(unittest.TestCase):
    def test_bare_name_yields_blocked_by_raw_link(self):
        _, links, _ = _parse(WIDGET)
        blocked = _links(links, "blocked_by")
        self.assertEqual([l["raw_value"] for l in blocked], ["data-layer"])

    def test_numbered_name_yields_blocked_by_raw_link(self):
        _, links, _ = _parse(NUMBERED_DEPS)
        blocked = _links(links, "blocked_by")
        self.assertEqual([l["raw_value"] for l in blocked], ["3-widget-panel"])

    def test_blocked_by_none_yields_no_links_and_one_sentinel_annotation(self):
        _, links, annotations = _parse(DATA_LAYER)
        self.assertEqual(_links(links, "blocked_by"), [])
        sentinel = _notes(annotations, field="blocked_by", reason="sentinel")
        self.assertEqual(len(sentinel), 1)

    def test_parenthetical_is_stripped_to_annotation_slug_still_links(self):
        _, links, annotations = _parse(WIDGET)
        blocked = _links(links, "blocked_by")
        self.assertEqual(blocked[0]["raw_value"], "data-layer")
        prose = _notes(annotations, field="blocked_by", reason="prose")
        self.assertEqual(len(prose), 1)
        self.assertIn("needs the store first", prose[0]["value"])

    def test_blocks_line_yields_blocks_raw_link(self):
        _, links, _ = _parse(DATA_LAYER)
        blocks = _links(links, "blocks")
        self.assertEqual([l["raw_value"] for l in blocks], ["widget-panel"])

    def test_bullet_form_yields_one_link_per_bullet(self):
        _, links, _ = _parse(BULLET_DEPS)
        blocked = _links(links, "blocked_by")
        self.assertEqual(
            [l["raw_value"] for l in blocked],
            ["3-widget-panel", "data-layer"],
        )

    def test_bullet_parenthetical_and_dash_prose_become_annotations(self):
        _, _, annotations = _parse(BULLET_DEPS)
        prose = _notes(annotations, field="blocked_by", reason="prose")
        values = sorted(a["value"] for a in prose)
        self.assertEqual(
            values,
            [
                "3-widget-panel (needs the panel shell first)",
                "data-layer - shares the store contract",
            ],
        )

    def test_bullet_none_yields_sentinel_annotation_no_links(self):
        _, links, annotations = _parse(BULLET_DEPS)
        self.assertEqual(_links(links, "blocks"), [])
        sentinel = _notes(annotations, field="blocks", reason="sentinel")
        self.assertEqual([a["value"] for a in sentinel], ["(none)"])

    def test_bare_marker_with_no_bullets_yields_nothing(self):
        _, links, annotations = _parse(NUMBERED_DEPS)
        self.assertEqual(_links(links, "blocks"), [])
        self.assertEqual(_notes(annotations, field="blocks"), [])

    def test_bullets_stop_at_first_non_bullet_line(self):
        text = corpus_helper.read_fixture(BULLET_DEPS).replace(
            "**Blocks:**\n- (none)",
            "**Blocks:**\n- data-layer\n\n- orphan-idea",
        )
        _, links, _ = registry.parse_file("story", BULLET_DEPS, text)
        blocks = _links(links, "blocks")
        self.assertEqual([l["raw_value"] for l in blocks], ["data-layer"])

    def test_multiword_prose_value_is_annotation_not_unresolved_link(self):
        text = corpus_helper.read_fixture(DATA_LAYER).replace(
            "**Blocked by:** none",
            "**Blocked by:** the pending commit from an earlier session",
        )
        _, links, annotations = registry.parse_file("story", DATA_LAYER, text)
        self.assertEqual(_links(links, "blocked_by"), [])
        prose = _notes(annotations, field="blocked_by", reason="prose")
        self.assertEqual(len(prose), 1)


class TestReferenceMaterials(unittest.TestCase):
    def test_citation_bullets_yield_references_links(self):
        _, links, _ = _parse(WIDGET)
        refs = [
            l for l in links if l["field"] == "reference_materials"
        ]
        self.assertEqual(
            [l["raw_value"] for l in refs], ["planning/sample-concept.md"]
        )

    def test_path_outside_craft_yields_annotation_not_link(self):
        _, links, annotations = _parse(WIDGET)
        outside = _notes(
            annotations, field="reference_materials", reason="out-of-scope-type"
        )
        self.assertEqual(len(outside), 1)
        self.assertIn("/usr/share/outside/example.md", outside[0]["value"])

    def test_prose_section_yields_one_annotation_and_no_links(self):
        _, links, annotations = _parse(DATA_LAYER)
        self.assertEqual(
            [l for l in links if l["field"] == "reference_materials"], []
        )
        prose = _notes(
            annotations, field="reference_materials", reason="prose"
        )
        self.assertEqual(len(prose), 1)


class TestMembershipAndBody(unittest.TestCase):
    def test_belongs_to_derives_from_cycle_directory_path(self):
        _, links, _ = _parse(WIDGET)
        belongs = _links(links, "belongs_to")
        self.assertEqual(len(belongs), 1)
        self.assertEqual(belongs[0]["raw_value"], "7-sample-cycle")
        self.assertEqual(belongs[0]["field"], "path")

    def test_backlog_story_without_cycle_emits_no_belongs_to(self):
        _, links, _ = _parse(BACKLOG)
        self.assertEqual(_links(links, "belongs_to"), [])

    def test_body_craft_path_yields_references_candidate(self):
        _, links, _ = _parse(WIDGET)
        body_paths = [l for l in links if l["field"] == "body_path"]
        self.assertEqual(
            [l["raw_value"] for l in body_paths],
            ["tweaks/tweak-sample-polish.md"],
        )

    def test_body_wikilink_yields_references_candidate(self):
        _, links, _ = _parse(WIDGET)
        wikis = [l for l in links if l["field"] == "body_wikilink"]
        self.assertEqual([l["raw_value"] for l in wikis], ["1-data-layer"])

    def test_fenced_craft_path_is_not_a_candidate(self):
        _, links, _ = _parse(WIDGET)
        values = [l["raw_value"] for l in links]
        self.assertNotIn("fixes/fake-fix.md", values)

    def test_binding_table_token_column_yields_token_annotations(self):
        _, _, annotations = _parse(WIDGET)
        tokens = _notes(annotations, field="token")
        self.assertEqual(
            [a["value"] for a in tokens], ["color.surface", "color.border"]
        )


if __name__ == "__main__":
    unittest.main()
