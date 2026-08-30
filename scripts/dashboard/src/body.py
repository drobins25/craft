"""Shared body-text helpers for record parsers.

Fenced code blocks are stripped BEFORE any path, wikilink, or heading scan:
record bodies are the one place craft quotes its own syntax at itself, and
scanning code samples would mint edges out of documentation examples.
"""

import re

_CRAFT_PATH_RE = re.compile(r"\.craft/[A-Za-z0-9][A-Za-z0-9._/-]*")
_WIKILINK_RE = re.compile(r"\[\[([^\]]+)\]\]")


def strip_fenced(text):
    """Remove ``` and ~~~ fenced blocks, keeping everything else."""
    out = []
    in_fence = False
    fence_mark = ""
    for line in text.split("\n"):
        stripped = line.lstrip()
        if in_fence:
            if stripped.startswith(fence_mark):
                in_fence = False
            continue
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = True
            fence_mark = stripped[:3]
            continue
        out.append(line)
    return "\n".join(out)


def section(text, title):
    """Text of a `## <title>` section up to the next `## ` heading, or None."""
    lines = text.split("\n")
    start = None
    for i, line in enumerate(lines):
        if line.strip() == "## " + title:
            start = i + 1
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start, len(lines)):
        if lines[j].startswith("## "):
            end = j
            break
    return "\n".join(lines[start:end])


def craft_paths(text):
    """All `.craft/...` path strings in the text, trailing dots trimmed."""
    return [p.rstrip(".") for p in _CRAFT_PATH_RE.findall(text)]


def wikilinks(text):
    """Inner values of all `[[...]]` wikilinks."""
    return [w.strip() for w in _WIKILINK_RE.findall(text)]


def craft_relative(path):
    """Normalize any path form to .craft-relative, or None if outside .craft/.

    Handles absolute paths containing /.craft/, bare .craft/-prefixed paths,
    and already-relative record paths (which are returned unchanged only when
    they were explicitly .craft-prefixed - a bare path is not assumed).
    """
    if "/.craft/" in path:
        return path.split("/.craft/", 1)[1]
    if path.startswith(".craft/"):
        return path[len(".craft/"):]
    return None


def humanize(slug):
    """Replace dashes with spaces, capitalize the first character only -
    never title-case, which mangles acronyms."""
    s = slug.replace("-", " ").strip()
    if not s:
        return slug
    return s[:1].upper() + s[1:]
