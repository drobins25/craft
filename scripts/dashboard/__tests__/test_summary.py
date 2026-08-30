import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

import corpus_helper
from src import registry
from src import summary


class TestPerTypeExtraction(unittest.TestCase):
    def test_story_summary_comes_from_spark_section(self):
        body = (
            "# Story: Sample\n\n"
            "## Spark\n\n"
            "The dashboard becomes a real page.\n\n"
            "## Chunks\n\n### Chunk 1: First\n"
        )
        self.assertEqual(
            summary.extract("story", {}, body),
            "The dashboard becomes a real page.",
        )

    def test_cycle_summary_comes_from_target_field(self):
        fields = {"target": "Ship the graph template."}
        self.assertEqual(
            summary.extract("cycle", fields, ""), "Ship the graph template."
        )

    def test_cycle_target_written_as_a_block_scalar_is_not_the_indicator(self):
        # Handing extract() a pre-parsed dict never exercises the parse step,
        # which is how a cycle shipped with "|" as its whole summary. Parse
        # the TEXT so the reader is in the path under test.
        from src import registry
        text = (
            "name: x\n"
            "title: \"X\"\n"
            "status: active\n"
            "target: |\n"
            "  Make the harness comprehensible.\n"
            "  A second line of prose.\n"
        )
        node, _, _ = registry.parse_file("cycle", "cycles/9-x/cycle.yaml", text)
        self.assertNotEqual(node.get("summary"), "|")
        self.assertIn("Make the harness comprehensible.", node.get("summary", ""))

    def test_fix_summary_comes_from_symptom(self):
        body = "## Symptom\n\nThe agent produces stale output.\n\n## Root Cause\n\nCache never invalidated.\n"
        self.assertEqual(
            summary.extract("fix", {"trigger": "manual QA"}, body),
            "The agent produces stale output.",
        )

    def test_fix_without_symptom_falls_back_to_trigger(self):
        body = "## Root Cause\n\nCache never invalidated.\n"
        self.assertEqual(
            summary.extract("fix", {"trigger": "manual QA pass"}, body),
            "manual QA pass",
        )

    def test_tweak_summary_comes_from_request(self):
        body = "## Request\n\nTighten the toolbar spacing.\n\n## Fit Check\n\nlooks right\n"
        self.assertEqual(
            summary.extract("tweak", {}, body),
            "Tighten the toolbar spacing.",
        )

    def test_legacy_tweak_without_request_falls_back_to_first_paragraph(self):
        body = "# Tweak: Legacy toolbar nudge\n\nThe one remaining record from the pre-spec generation.\n"
        self.assertEqual(
            summary.extract("tweak", {}, body),
            "The one remaining record from the pre-spec generation.",
        )

    def test_mockup_summary_comes_from_brief(self):
        body = "## Brief\n\nThree hero directions for the widget panel.\n\n## Reactions\n\nliked it\n"
        self.assertEqual(
            summary.extract("mockup", {}, body),
            "Three hero directions for the widget panel.",
        )

    def test_notebook_summary_is_paragraph_after_title_line(self):
        body = (
            "What if the widget panel could rearrange itself?\n\n"
            "More detail about the idea in a second paragraph.\n"
        )
        self.assertEqual(
            summary.extract("notebook", {}, body),
            "More detail about the idea in a second paragraph.",
        )

    def test_notebook_summary_is_not_the_title_itself(self):
        body = "Only a title line, nothing follows.\n"
        self.assertIsNone(summary.extract("notebook", {}, body))

    def test_dial_summary_is_bare_body_prose(self):
        body = "\nFelt tighter without crowding the icons.\n"
        self.assertEqual(
            summary.extract("dial", {}, body),
            "Felt tighter without crowding the icons.",
        )

    def test_riff_and_planning_skip_the_h1(self):
        riff_body = (
            "# The widget panel rethink\n\n"
            "A session memory in prose. No structured link fields.\n"
        )
        planning_body = (
            "# Sample Concept\n\n"
            "A planning concept the fixture cycle grew from.\n"
        )
        self.assertEqual(
            summary.extract("riff", {}, riff_body),
            "A session memory in prose. No structured link fields.",
        )
        self.assertEqual(
            summary.extract("planning", {}, planning_body),
            "A planning concept the fixture cycle grew from.",
        )


class TestNoExtractableSource(unittest.TestCase):
    def test_absent_section_yields_none(self):
        body = "## Root Cause\n\nCache never invalidated.\n"
        self.assertIsNone(summary.extract("fix", {}, body))

    def test_empty_section_yields_none(self):
        body = "## Symptom\n\n## Root Cause\n\nCache never invalidated.\n"
        self.assertIsNone(summary.extract("fix", {}, body))

    def test_unrecognized_record_type_yields_none(self):
        self.assertIsNone(summary.extract("holograms", {}, "some body"))


class TestNormalization(unittest.TestCase):
    def test_fenced_code_is_never_a_summary(self):
        body = (
            "## Spark\n\n"
            "```\nsome code sample line\n```\n\n"
            "The real prose after the fence.\n"
        )
        self.assertEqual(
            summary.extract("story", {}, body),
            "The real prose after the fence.",
        )

    def test_fenced_only_section_yields_none(self):
        body = "## Spark\n\n```\nonly code, no prose\n```\n"
        self.assertIsNone(summary.extract("story", {}, body))

    def test_inline_markdown_is_reduced_to_text(self):
        body = (
            "## Spark\n\n"
            "This has **bold**, _em_, `code`, [[a link]], "
            "and [a text](http://example.com) all in it.\n"
        )
        self.assertEqual(
            summary.extract("story", {}, body),
            "This has bold, em, code, a link, and a text all in it.",
        )

    def test_long_section_is_truncated_at_a_word_boundary(self):
        words = ["word%d" % i for i in range(100)]
        long_text = " ".join(words)
        body = "## Spark\n\n%s\n" % long_text
        result = summary.extract("story", {}, body)
        self.assertLessEqual(len(result), 280)
        self.assertTrue(result.endswith("…"))
        self.assertTrue(long_text.startswith(result[:-1]))

    def test_short_section_is_not_padded_or_truncated(self):
        body = "## Spark\n\nOne short sentence.\n"
        self.assertEqual(summary.extract("story", {}, body), "One short sentence.")

    def test_whitespace_is_collapsed(self):
        body = "## Spark\n\nLine one   with   extra    spaces\nand a second   line.\n"
        self.assertEqual(
            summary.extract("story", {}, body),
            "Line one with extra spaces and a second line.",
        )

    def test_plain_image_reduces_to_alt_text(self):
        body = "## Spark\n\nAn image ![Alt text](https://example.com/img.png) inline.\n"
        self.assertEqual(
            summary.extract("story", {}, body),
            "An image Alt text inline.",
        )

    def test_nested_badge_link_reduces_fully(self):
        body = (
            "## Request\n\n"
            'Darin provided the snippet: "[![Listed on ClaudePluginHub]'
            "(https://www.claudepluginhub.com/badge/drobins25-craft)]"
            "(https://www.claudepluginhub.com/plugins/drobins25-craft?ref=badge)\""
            "\n"
        )
        result = summary.extract("tweak", {}, body)
        self.assertNotIn("](", result)
        self.assertNotIn("[[", result)
        self.assertNotIn("**", result)
        self.assertNotIn("!", result)
        self.assertIn("Listed on ClaudePluginHub", result)

    def test_link_text_containing_brackets_reduces_to_text(self):
        body = "## Spark\n\nSee the [rendered [inline] example](https://example.com) here.\n"
        self.assertEqual(
            summary.extract("story", {}, body),
            "See the rendered [inline] example here.",
        )


class TestRegistryWiring(unittest.TestCase):
    def test_record_with_extractable_source_gets_summary_key(self):
        node, _, _ = registry.parse_file(
            "fix",
            "fixes/sample-broken-widget.md",
            corpus_helper.read_fixture("fixes/sample-broken-widget.md"),
        )
        self.assertEqual(
            node["summary"],
            "The widget panel rendered stale data after a refresh.",
        )

    def test_record_with_no_extractable_source_has_no_summary_key(self):
        text = (
            "---\n"
            "name: no-source-fix\n"
            "status: accepted\n"
            "created: 2026-04-01\n"
            "---\n\n"
            "## Root Cause\n\nSomething unrelated.\n"
        )
        node, _, _ = registry.parse_file("fix", "fixes/no-source-fix.md", text)
        self.assertNotIn("summary", node)

    def test_extraction_failure_cannot_crash_a_build(self):
        def explode(record_type, fields, body):
            raise ValueError("synthetic summary failure")

        original = registry.summary_mod.extract
        registry.summary_mod.extract = explode
        try:
            node, links, annotations = registry.parse_file(
                "story",
                "backlog/orphan-idea.md",
                corpus_helper.read_fixture("backlog/orphan-idea.md"),
            )
        finally:
            registry.summary_mod.extract = original
        self.assertEqual(node["type"], "story")
        self.assertNotIn("summary", node)

    def test_parser_crash_path_carries_no_summary(self):
        def explode(path, craft_rel, fields, body):
            raise ValueError("synthetic parser failure")

        original = registry.PARSERS["story"]
        registry.PARSERS["story"] = explode
        try:
            node, links, annotations = registry.parse_file(
                "story",
                "backlog/orphan-idea.md",
                corpus_helper.read_fixture("backlog/orphan-idea.md"),
            )
        finally:
            registry.PARSERS["story"] = original
        self.assertNotIn("summary", node)


if __name__ == "__main__":
    unittest.main()
