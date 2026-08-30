"""Graph assembly: discover -> parse all -> resolve -> emit.

Resolution cannot start before every node exists - that ordering is why
parsers emit raw links instead of edges. One pass builds the complete node
set, then the alias index, then partitions every raw link into an edge or
an annotation. Nothing is guessed and nothing is silently dropped.
"""

from . import emit
from . import paths
from . import registry
from . import resolve
from . import stats as stats_mod
from . import vocabulary

# The closed set of relationship kinds a build may emit - sourced from the
# definition so a thirteenth kind (blocked_by, normalized away by field
# inversion) can never sneak back in as a separate hand-kept literal.
EDGE_KINDS = frozenset(vocabulary.KINDS)

_MULTI_TARGET_KINDS = {"graduated_to"}


def build(root):
    """Full pipeline. Returns {"graph", "written", "removed"}."""
    paths.reset_log()
    nodes = []
    raw_links = []
    annotations = []
    texts = {}
    warnings = []
    seen_ids = {}

    for record_type, craft_rel in registry.discover(root):
        try:
            text = paths.read_under_craft(root, craft_rel)
        except (OSError, paths.BoundaryError) as exc:
            warnings.append(
                {"path": craft_rel, "reason": "unreadable: %s" % exc}
            )
            continue
        node, links, notes = registry.parse_file(record_type, craft_rel, text)
        node, links = _ensure_unique_id(node, links, seen_ids, warnings)
        nodes.append(node)
        texts[node["id"]] = text
        raw_links.extend(links)
        annotations.extend(notes)
        for warning in node.get("_warnings", []):
            warnings.append({"path": craft_rel, "reason": str(warning)})

    edges, resolution_notes = link_pass(nodes, raw_links)
    annotations = _clean_annotations(annotations + resolution_notes)

    nodes_sorted = sorted(nodes, key=lambda n: (n.get("date") or "", n["id"]))
    public_nodes = [
        {k: v for k, v in n.items() if not k.startswith("_")}
        for n in nodes_sorted
    ]
    warnings_sorted = sorted(
        warnings, key=lambda w: (w["path"], w["reason"])
    )
    unresolved = sum(1 for a in annotations if a["reason"] == "unresolved")

    graph = {
        "version": 1,
        "nodes": public_nodes,
        "edges": edges,
        "annotations": annotations,
        "stats": stats_mod.compute(nodes_sorted, edges),
        "build": {"warnings": warnings_sorted, "unresolved": unresolved},
        "vocabulary": vocabulary.display_block(),
    }
    written, removed = emit.write_all(root, graph, texts)
    return {"graph": graph, "written": written, "removed": removed}


def link_pass(nodes, raw_links):
    """Resolve every raw link against the complete node set.

    Returns (edges, annotations). Self-edges are dropped with an annotation;
    duplicate (source, target, kind) triples collapse to one; edges are
    sorted by (kind, source, target).
    """
    index = resolve.build_index(nodes)
    by_id = {n["id"]: n for n in nodes}
    edge_set = set()
    notes = []

    for link in raw_links:
        source_id = link["source_id"]
        source = by_id.get(source_id)
        kind = link["kind"]
        field = link["field"]
        raw = str(link["raw_value"])
        expect = link.get("expect")
        invert = link.get("invert", False)

        if kind in _MULTI_TARGET_KINDS:
            candidates = resolve.extract_targets(raw)
            if not candidates:
                notes.append(
                    resolve.annotation(
                        source_id,
                        field,
                        raw,
                        resolve.failure_reason(raw, index, field, expect),
                    )
                )
                continue
            if raw.strip() != ", ".join(candidates):
                # Decorated value (parentheticals, SPLIT text): preserve the
                # remainder alongside whatever targets resolve.
                notes.append(resolve.annotation(source_id, field, raw, "prose"))
        else:
            candidates = [raw]

        for candidate in candidates:
            target = resolve.resolve(index, candidate, source, expect)
            if target is None:
                notes.append(
                    resolve.annotation(
                        source_id,
                        field,
                        candidate,
                        resolve.failure_reason(candidate, index, field, expect),
                    )
                )
            elif target == source_id:
                notes.append(
                    resolve.annotation(
                        source_id, field, candidate, "self-reference"
                    )
                )
            elif invert:
                # The field's writer is the inbound end of the relationship
                # (a story's Blocked by marker names its blocker) - flip
                # after resolution, once the target is a real node id, per
                # this module's own ordering law above.
                edge_set.add((kind, target, source_id))
            else:
                edge_set.add((kind, source_id, target))

    edges = [
        {"source": source, "target": target, "kind": kind}
        for kind, source, target in sorted(edge_set)
    ]
    return edges, notes


def _ensure_unique_id(node, links, seen_ids, warnings):
    """Case-folded ids can collide across paths; remap deterministically."""
    base = node["id"]
    if base not in seen_ids:
        seen_ids[base] = node["_path"]
        return node, links
    n = 2
    while "%s--%d" % (base, n) in seen_ids:
        n += 1
    new_id = "%s--%d" % (base, n)
    seen_ids[new_id] = node["_path"]
    warnings.append(
        {
            "path": node["_path"],
            "reason": "id collision with %s: %s remapped to %s"
            % (seen_ids[base], base, new_id),
        }
    )
    node["id"] = new_id
    for link in links:
        link["source_id"] = new_id
    return node, links


def _clean_annotations(annotations):
    unique = {}
    for a in annotations:
        key = (
            str(a["source_id"]),
            str(a["field"]),
            str(a["value"]),
            str(a["reason"]),
        )
        unique[key] = {
            "source_id": key[0],
            "field": key[1],
            "value": key[2],
            "reason": key[3],
        }
    return [
        unique[key]
        for key in sorted(unique, key=lambda k: (k[0], k[1], k[2]))
    ]
