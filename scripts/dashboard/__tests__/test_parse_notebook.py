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
        "notebook", craft_rel, corpus_helper.read_fixture(craft_rel)
    )


IDEA = "notebook/ideas/2026-01-18-sample-idea.md"
TODO = "notebook/todos/2026-01-20-sample-todo.md"
DONE = "notebook/todos/done/2026-01-22-finished-todo.md"
NOTE = "notebook/notes/2026-01-25-sample-note.md"


class TestParseNotebook(unittest.TestCase):
    def test_subtype_derives_from_path_including_todos_done(self):
        self.assertEqual(_parse(IDEA)[0]["subtype"], "idea")
        self.assertEqual(_parse(TODO)[0]["subtype"], "todo")
        self.assertEqual(_parse(DONE)[0]["subtype"], "todo")
        self.assertEqual(_parse(NOTE)[0]["subtype"], "note")

    def test_title_is_first_non_blank_body_line_trimmed(self):
        node, _, _ = _parse(IDEA)
        self.assertEqual(
            node["title"],
            "What if the widget panel could rearrange itself based on usage?",
        )
        self.assertLessEqual(len(node["title"]), 120)

    def test_tags_parse_from_inline_list(self):
        node, _, _ = _parse(IDEA)
        self.assertEqual(node["tags"], ["widgets", "sample"])

    def test_todo_status_lands_and_note_status_is_null(self):
        self.assertEqual(_parse(TODO)[0]["status"], "open")
        self.assertIsNone(_parse(NOTE)[0]["status"])

    def test_source_wikilink_yields_link_session_prose_yields_annotation(self):
        _, done_links, _ = _parse(DONE)
        wikis = [l for l in done_links if l["field"] == "source"]
        self.assertEqual(
            [l["raw_value"] for l in wikis], ["tweak-sample-polish"]
        )
        _, _, todo_annotations = _parse(TODO)
        prose = [
            a for a in todo_annotations
            if a["field"] == "source" and a["reason"] == "prose"
        ]
        self.assertEqual([a["value"] for a in prose], ["session 2026-01-20"])

    def test_graduated_to_pointing_at_a_fix_yields_a_link(self):
        _, links, _ = _parse(DONE)
        graduated = [l for l in links if l["kind"] == "graduated_to"]
        self.assertEqual(
            [l["raw_value"] for l in graduated], ["sample-broken-widget"]
        )
        self.assertIn("fix", graduated[0]["expect"])

    def test_idea_graduated_to_backlog_story_yields_link(self):
        _, links, _ = _parse(IDEA)
        graduated = [l for l in links if l["kind"] == "graduated_to"]
        self.assertEqual([l["raw_value"] for l in graduated], ["orphan-idea"])


if __name__ == "__main__":
    unittest.main()
