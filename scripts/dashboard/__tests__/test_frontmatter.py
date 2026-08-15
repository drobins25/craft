import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src import frontmatter


WELL_FORMED = """---
name: widget-panel
title: "Widget Panel"
status: ready
tags: [ui, panel]
source_concept: []
paths: ['planning/a.md', 'planning/b.md']
mode: fast # inline note
commands: "kebab-case"           # my-command.md
---

# Story: Widget Panel

Body starts here.
"""

LOOKALIKE_BODY = """---
name: real-name
---

Some prose, then a code sample:

```markdown
---
name: fake-name-from-code-sample
---
```

More prose.
"""


class TestParse(unittest.TestCase):
    def test_block_at_byte_zero_parses(self):
        fields, body = frontmatter.parse(WELL_FORMED)
        self.assertEqual(fields["name"], "widget-panel")
        self.assertEqual(fields["title"], "Widget Panel")
        self.assertEqual(fields["status"], "ready")
        self.assertTrue(body.lstrip().startswith("# Story: Widget Panel"))

    def test_lookalike_in_body_is_ignored(self):
        fields, body = frontmatter.parse(LOOKALIKE_BODY)
        self.assertEqual(fields, {"name": "real-name"})
        self.assertIn("fake-name-from-code-sample", body)

    def test_inline_list_parses(self):
        fields, _ = frontmatter.parse(WELL_FORMED)
        self.assertEqual(fields["tags"], ["ui", "panel"])

    def test_empty_list_parses_to_empty(self):
        fields, _ = frontmatter.parse(WELL_FORMED)
        self.assertEqual(fields["source_concept"], [])

    def test_quoted_flow_list_of_paths(self):
        fields, _ = frontmatter.parse(WELL_FORMED)
        self.assertEqual(fields["paths"], ["planning/a.md", "planning/b.md"])

    def test_trailing_comment_stripped_from_unquoted_scalar(self):
        fields, _ = frontmatter.parse(WELL_FORMED)
        self.assertEqual(fields["mode"], "fast")

    def test_trailing_comment_stripped_after_quoted_scalar(self):
        fields, _ = frontmatter.parse(WELL_FORMED)
        self.assertEqual(fields["commands"], "kebab-case")

    def test_missing_frontmatter_returns_empty_and_full_body(self):
        text = "# Just a heading\n\nPlain markdown.\n"
        fields, body = frontmatter.parse(text)
        self.assertEqual(fields, {})
        self.assertEqual(body, text)

    def test_malformed_unterminated_fence_returns_empty_and_full_body(self):
        text = "---\nname: dangling\n\n# never closed\n"
        fields, body = frontmatter.parse(text)
        self.assertEqual(fields, {})
        self.assertEqual(body, text)

    def test_fence_not_at_byte_zero_is_body(self):
        text = "\n---\nname: late\n---\n"
        fields, body = frontmatter.parse(text)
        self.assertEqual(fields, {})
        self.assertEqual(body, text)

    def test_bom_prefixed_parses_identically(self):
        with_bom = "\ufeff" + WELL_FORMED
        self.assertEqual(
            frontmatter.parse(with_bom), frontmatter.parse(WELL_FORMED)
        )

    def test_nested_indented_lines_are_skipped(self):
        text = "---\nname: outer\nnested:\n  inner: value\n---\nbody\n"
        fields, _ = frontmatter.parse(text)
        self.assertEqual(fields["name"], "outer")
        self.assertNotIn("inner", fields)

    def test_crlf_line_endings_parse(self):
        text = "---\r\nname: windows-record\r\n---\r\nbody\r\n"
        fields, _ = frontmatter.parse(text)
        self.assertEqual(fields["name"], "windows-record")


class TestRead(unittest.TestCase):
    def test_read_from_disk(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "record.md")
            with open(path, "w", encoding="utf-8") as f:
                f.write(WELL_FORMED)
            fields, body = frontmatter.read(path)
            self.assertEqual(fields["name"], "widget-panel")
            self.assertIn("Body starts here.", body)

    def test_read_missing_file_never_raises(self):
        fields, body = frontmatter.read("/nonexistent/nowhere/record.md")
        self.assertEqual(fields, {})
        self.assertEqual(body, "")


if __name__ == "__main__":
    unittest.main()
