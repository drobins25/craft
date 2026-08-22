"""Per-record summary extraction: one card-ready line per record type.

Nine record types, six distinct source shapes, one fallback: story reads
`## Spark`; cycle reads the `target:` field (cycle.yaml has no body); fix
reads `## Symptom`, falling back to `trigger:` for records predating the
heading; tweak reads `## Request`, falling back to the first body paragraph
for the legacy shape; mockup reads `## Brief`; notebook has no headings, so
its summary is the paragraph after the title line the parser already takes;
dial, riff and planning have no per-type heading, so the summary is the
first body paragraph, skipping a leading H1 where one exists.

The panel renders this through `textContent`, so inline markdown syntax
would show its own punctuation on the card - it is reduced to plain text.
"""

import re

from . import body as body_mod

LIMIT = 280

_BOLD_STAR_RE = re.compile(r"\*\*(.+?)\*\*")
_BOLD_UNDER_RE = re.compile(r"__(.+?)__")
_EM_STAR_RE = re.compile(r"\*(.+?)\*")
_EM_UNDER_RE = re.compile(r"_(.+?)_")
_CODE_RE = re.compile(r"`([^`]+?)`")
_WIKILINK_RE = re.compile(r"\[\[([^\]]+?)\]\]")
_IMAGE_RE = re.compile(r"!\[([^\]]*?)\]\([^)]*?\)")
_LINK_TEXT = r"(?:[^\[\]]|\[[^\[\]]*\])*"
_LINK_RE = re.compile(r"\[(" + _LINK_TEXT + r")\]\([^)]*?\)")

_H1_RE = re.compile(r"^# .+$", re.M)
_LIST_MARKER_RE = re.compile(r"^\s*(?:[-*]\s|\d+\.\s)")
_WHITESPACE_RE = re.compile(r"\s+")


def extract(record_type, fields, body):
    """A card-ready summary for one record, or None with no source text."""
    handler = _HANDLERS.get(record_type)
    if handler is None:
        return None
    stripped = body_mod.strip_fenced(body)
    raw = handler(fields, stripped)
    if not raw:
        return None
    cleaned = _clean(str(raw))
    if not cleaned:
        return None
    return _truncate(cleaned)


def _from_section(stripped, title):
    section = body_mod.section(stripped, title)
    if section is None:
        return None
    return _first_paragraph(section)


def _story(fields, stripped):
    return _from_section(stripped, "Spark")


def _cycle(fields, stripped):
    return fields.get("target") or None


def _fix(fields, stripped):
    return _from_section(stripped, "Symptom") or fields.get("trigger") or None


def _tweak(fields, stripped):
    return _from_section(stripped, "Request") or _first_paragraph(stripped)


def _mockup(fields, stripped):
    return _from_section(stripped, "Brief")


def _notebook(fields, stripped):
    lines = stripped.split("\n")
    for i, line in enumerate(lines):
        if line.strip():
            return _first_paragraph("\n".join(lines[i + 1 :]))
    return None


def _after_h1(fields, stripped):
    match = _H1_RE.search(stripped)
    rest = stripped[match.end() :] if match else stripped
    return _first_paragraph(rest)


_HANDLERS = {
    "story": _story,
    "cycle": _cycle,
    "fix": _fix,
    "tweak": _tweak,
    "mockup": _mockup,
    "notebook": _notebook,
    "dial": _after_h1,
    "riff": _after_h1,
    "planning": _after_h1,
}


def _first_paragraph(text):
    """The first run of consecutive non-blank lines that is not a heading,
    table row, blockquote, or list item."""
    para = []
    for line in text.split("\n"):
        stripped_line = line.strip()
        if not stripped_line:
            if para:
                break
            continue
        if stripped_line.startswith(("#", "|", ">")) or _LIST_MARKER_RE.match(
            line
        ):
            if para:
                break
            continue
        para.append(stripped_line)
    if not para:
        return None
    return " ".join(para)


def _clean(text):
    text = _BOLD_STAR_RE.sub(r"\1", text)
    text = _BOLD_UNDER_RE.sub(r"\1", text)
    text = _EM_STAR_RE.sub(r"\1", text)
    text = _EM_UNDER_RE.sub(r"\1", text)
    text = _CODE_RE.sub(r"\1", text)
    text = _WIKILINK_RE.sub(r"\1", text)
    text = _IMAGE_RE.sub(r"\1", text)
    text = _LINK_RE.sub(r"\1", text)
    return _WHITESPACE_RE.sub(" ", text).strip()


def _truncate(text):
    if len(text) <= LIMIT:
        return text
    cut = text[:LIMIT]
    space = cut.rfind(" ")
    if space > 0:
        cut = cut[:space]
    return cut.rstrip() + "…"
