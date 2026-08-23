"""Story parser: envelope, chunk attribute, and the story link grammar.

Stories are the link-heaviest record type: cycle membership, dependency
lines, Reference Materials citations (two incompatible real shapes), body
paths and wikilinks, and the Element Binding Table. Backlog stories differ
from cycle stories only by location and a possibly-absent `cycle:` field.
"""

import os
import re

from . import body as body_mod
from . import identity
from . import resolve
from . import sentinels

_CHUNK_RE = re.compile(r"^### Chunk (\d+): (.+)$", re.M)
_NUM_PREFIX_RE = re.compile(r"^\d+-")


def parse(path, craft_rel, fields, body):
    stem = os.path.splitext(os.path.basename(craft_rel))[0]
    nid = identity.node_id("story", craft_rel)
    warnings = []
    stripped = body_mod.strip_fenced(body)

    node = {
        "id": nid,
        "type": "story",
        "title": fields.get("title")
        or body_mod.humanize(_NUM_PREFIX_RE.sub("", stem)),
        "date": fields.get("created") or None,
        "status": fields.get("status") or None,
        "tags": _tags(fields),
        "surface": None,
        "chunks": _chunks(fields, stripped),
        "_path": craft_rel,
        "_name": fields.get("name", ""),
        "_warnings": warnings,
    }

    links = []
    annotations = []

    parts = craft_rel.split("/")
    if parts[0] == "cycles" and len(parts) >= 2:
        links.append(resolve.raw_link(nid, "story", "path", parts[1]))
    elif fields.get("cycle"):
        links.append(resolve.raw_link(nid, "story", "cycle", fields["cycle"]))

    for field in ("mockup", "grew_from"):
        value = fields.get(field)
        if value:
            links.append(resolve.raw_link(nid, "story", field, value))

    _parse_dependencies(nid, stripped, links, annotations)
    _parse_reference_materials(nid, stripped, links, annotations)
    # Reference Materials has its own citation grammar - subtract it from
    # the generic body scan so its paths are not double-counted.
    ref_section = body_mod.section(stripped, "Reference Materials")
    body_scope = (
        stripped.replace(ref_section, "", 1) if ref_section else stripped
    )
    _parse_body_references(nid, body_scope, links)
    _parse_binding_table(nid, stripped, annotations)

    return node, links, annotations


def _tags(fields):
    tags = fields.get("tags")
    if isinstance(tags, list):
        return tags
    if tags:
        return [tags]
    return []


def _chunks(fields, stripped_body):
    total = _to_int(fields.get("chunks_total"))
    complete = _to_int(fields.get("chunks_complete"))
    current = _to_int(fields.get("current_chunk"))
    chunk_list = []
    for m in _CHUNK_RE.finditer(stripped_body):
        number = int(m.group(1))
        if current <= 0:
            status = "pending"
        elif number < current:
            status = "complete"
        elif number == current:
            status = "active"
        else:
            status = "pending"
        chunk_list.append(
            {"number": number, "title": m.group(2).strip(), "status": status}
        )
    return {"total": total, "complete": complete, "list": chunk_list}


def _to_int(value):
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return 0


_DEP_MARKER_RE = re.compile(r"^\*\*(Blocked by|Blocks):\*\*[ \t]*(.*)$")
_DEP_BULLET_RE = re.compile(r"^\s*- (.*)$")
# Marker text -> the vocabulary FIELD it declares. The kind itself (both
# markers resolve to the "blocks" kind, one of them inverted) comes from
# vocabulary.kind_for via raw_link - this parser no longer names a kind.
_DEP_FIELDS = {"Blocked by": "blocked_by", "Blocks": "blocks"}


def _parse_dependencies(nid, stripped, links, annotations):
    """Both real dependency shapes: inline (roadmap template - targets
    comma-separated on the marker line) and bullet-list (full/backlog
    templates - a bare marker line with one `- target` bullet per line
    underneath). The marker match must never cross the newline, or the
    first bullet gets swallowed as a mangled inline value."""
    lines = stripped.split("\n")
    i = 0
    while i < len(lines):
        m = _DEP_MARKER_RE.match(lines[i])
        if not m:
            i += 1
            continue
        field = _DEP_FIELDS[m.group(1)]
        value = m.group(2).strip()
        if value:
            if sentinels.is_sentinel(value):
                annotations.append(
                    resolve.annotation(nid, field, value, "sentinel")
                )
            else:
                for part in value.split(","):
                    _dep_target(nid, field, part, links, annotations)
            i += 1
            continue
        j = i + 1
        while j < len(lines):
            bullet = _DEP_BULLET_RE.match(lines[j])
            if not bullet:
                break
            _dep_target(nid, field, bullet.group(1), links, annotations)
            j += 1
        i = max(j, i + 1)


def _dep_target(nid, field, text, links, annotations):
    """One dependency target -> a raw link, an annotation, or both.

    Handles `(none)`-style sentinels, parenthetical rationales, and
    `slug - prose` suffixes by delegating to resolve.prose_guarded_link -
    the same slug-or-prose grammar every mixed frontmatter link field uses,
    so this parser is not a second hand-kept copy of the rule."""
    original = text.strip()
    if not original:
        return
    link, note = resolve.prose_guarded_link(nid, "story", field, original)
    if link is not None:
        links.append(link)
    if note is not None:
        annotations.append(note)


def _parse_reference_materials(nid, stripped, links, annotations):
    section = body_mod.section(stripped, "Reference Materials")
    if section is None:
        return
    backticked = re.findall(r"`([^`]+)`", section)
    if not backticked:
        if section.strip():
            annotations.append(
                resolve.annotation(
                    nid, "reference_materials", section.strip()[:500], "prose"
                )
            )
        return
    for raw in backticked:
        rel = body_mod.craft_relative(raw)
        if rel:
            links.append(
                resolve.raw_link(nid, "story", "reference_materials", rel)
            )
        else:
            annotations.append(
                resolve.annotation(
                    nid, "reference_materials", raw, "out-of-scope-type"
                )
            )


def _parse_body_references(nid, stripped, links):
    for raw_path in body_mod.craft_paths(stripped):
        rel = body_mod.craft_relative(raw_path)
        if rel:
            links.append(resolve.raw_link(nid, "story", "body_path", rel))
    for inner in body_mod.wikilinks(stripped):
        links.append(resolve.raw_link(nid, "story", "body_wikilink", inner))


def _parse_binding_table(nid, stripped, annotations):
    lines = stripped.split("\n")
    token_col = None
    for i, line in enumerate(lines):
        if not line.strip().startswith("|"):
            token_col = None
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if token_col is None:
            if "Token" in cells:
                token_col = cells.index("Token")
            continue
        if set("".join(cells)) <= set("-: "):
            continue
        if token_col < len(cells) and cells[token_col]:
            annotations.append(
                resolve.annotation(
                    nid, "token", cells[token_col], "out-of-scope-type"
                )
            )
