"""Stdlib-only frontmatter reader for .craft/ records.

Fields are parsed ONLY from a `---` fence starting at byte 0 of the file
(after an optional UTF-8 BOM) - a `---` appearing later is body content.
Record bodies quote craft syntax at itself (code samples with their own
frontmatter-lookalike lines), so position-anchored parsing is a correctness
requirement, not a nicety.

Missing or malformed frontmatter returns ({}, full_text). Never raises on
file content.
"""

import re

BOM = "\ufeff"

_KEY_RE = re.compile(r"^([A-Za-z0-9_-]+):(.*)$")
_COMMENT_RE = re.compile(r"\s#\s?")


def read(path):
    """Read a record file -> (fields dict, body str)."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return {}, ""
    return parse(text)


def parse(text):
    """Parse full file text -> (fields dict, body str)."""
    if text.startswith(BOM):
        text = text[len(BOM):]
    lines = text.split("\n")
    if not lines or lines[0].rstrip("\r") != "---":
        return {}, text
    close = None
    for i in range(1, len(lines)):
        if lines[i].rstrip("\r") == "---":
            close = i
            break
    if close is None:
        return {}, text
    fields = parse_mapping(lines[1:close])
    body = "\n".join(lines[close + 1:])
    return fields, body


def parse_mapping(lines):
    """Parse top-level `key: value` lines -> dict.

    Values are strings, except inline lists (`[a, b]`) which become list[str]
    (`[]` becomes []). Trailing ` # comment` is stripped from unquoted
    scalars. Indented (nested) lines and comment lines are skipped.
    """
    fields = {}
    for line in lines:
        line = line.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line[0] in (" ", "\t"):
            continue
        m = _KEY_RE.match(line)
        if not m:
            continue
        key = m.group(1)
        rest = m.group(2).strip()
        if rest.startswith("["):
            end = rest.rfind("]")
            if end != -1:
                fields[key] = _parse_list(rest[1:end])
                continue
        fields[key] = _parse_scalar(rest)
    return fields


def _parse_scalar(raw):
    s = raw.strip()
    if not s:
        return ""
    if s[0] in ('"', "'"):
        quote = s[0]
        end = s.find(quote, 1)
        if end != -1:
            return s[1:end]
        return s
    m = _COMMENT_RE.search(s)
    if m:
        s = s[: m.start()].rstrip()
    return s


def _parse_list(inner):
    items = []
    for part in _split_commas(inner):
        part = part.strip()
        if not part:
            continue
        items.append(_parse_scalar(part))
    return items


def _split_commas(s):
    """Split on commas, respecting single- and double-quoted spans."""
    out = []
    buf = []
    quote = None
    for ch in s:
        if quote:
            buf.append(ch)
            if ch == quote:
                quote = None
        elif ch in ('"', "'"):
            quote = ch
            buf.append(ch)
        elif ch == ",":
            out.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    out.append("".join(buf))
    return out
