import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_HERE))
sys.path.insert(0, _HERE)

from src import tokens


CONVENTIONS_ONLY = """# Project conventions - no visual tokens at all
naming:
  commands: "kebab-case"           # my-command.md
  agents: "kebab-case"
frontmatter:
  required: "name, description"
file_structure:
  skills: "skills/<name>/SKILL.md"
"""

VISUAL = """color:
  primary: "#3B82F6"
  surface: '#FFFFFF'
spacing:
  scale:
    small: 8
"""


class TestFold(unittest.TestCase):
    def test_dotted_keys_with_comments_stripped(self):
        folded = tokens.fold_text(CONVENTIONS_ONLY)
        self.assertEqual(folded["naming.commands"], "kebab-case")
        self.assertEqual(folded["frontmatter.required"], "name, description")

    def test_conventions_only_schema_folds_without_visual_assumptions(self):
        folded = tokens.fold_text(CONVENTIONS_ONLY)
        self.assertNotIn("color.primary", folded)
        self.assertEqual(len(folded), 4)

    def test_visual_schema_folds_nested_keys(self):
        folded = tokens.fold_text(VISUAL)
        self.assertEqual(folded["color.primary"], "#3B82F6")
        self.assertEqual(folded["color.surface"], "#FFFFFF")
        self.assertEqual(folded["spacing.scale.small"], "8")

    def test_missing_file_returns_empty_dict(self):
        self.assertEqual(tokens.fold("/nonexistent/tokens.yaml"), {})


if __name__ == "__main__":
    unittest.main()
