"""Design-token fold: tokens.yaml -> a flat dotted-key map.

Schema-agnostic by requirement: a tokens.yaml may hold colors and spacing,
or nothing but naming/file-structure conventions. The fold is an indentation
walk (no recursive YAML parsing), comments stripped, values as strings. A
missing file folds to an empty dict without a warning.
"""

import re

_KEY_RE = re.compile(r"^(\s*)([A-Za-z0-9_-]+):(.*)$")
_COMMENT_RE = re.compile(r"\s#\s?")


def fold(path):
    """Fold a tokens.yaml file -> {dotted.key: value}. Missing file -> {}."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return fold_text(f.read())
    except OSError:
        return {}


def fold_text(text):
    result = {}
    stack = []
    for line in text.split("\n"):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = _KEY_RE.match(line)
        if not m:
            continue
        indent, name, rest = m.groups()
        depth = len(indent) // 2
        stack = stack[:depth] + [name]
        value = _value(rest)
        if value:
            result[".".join(stack)] = value
    return result


def _value(rest):
    s = rest.strip()
    if not s:
        return ""
    if s.startswith('"'):
        end = s.find('"', 1)
        if end != -1:
            return s[1:end]
    m = _COMMENT_RE.search(s)
    if m:
        s = s[: m.start()].rstrip()
    if len(s) >= 2 and s[0] == "'" and s[-1] == "'":
        s = s[1:-1]
    return s.strip()
