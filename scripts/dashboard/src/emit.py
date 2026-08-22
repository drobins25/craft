"""Emitters: graph.js and per-record mirrors, deterministic and idempotent.

graph.js carries no timestamp, no absolute path, and no value derived from
the clock or the environment - an unchanged corpus must produce byte-
identical output so downstream writes can be skipped entirely.

Every embedded string passes through one sanitizer: json.dumps with
ensure_ascii (which escapes U+2028/U+2029), then `</` -> `<\\/` so record
content can never terminate the page's script tag.
"""

import json
import os

from . import paths


def sanitize_json(obj):
    text = json.dumps(obj, ensure_ascii=True, separators=(",", ":"))
    return text.replace("</", "<\\/")


def write_graph(root, graph):
    text = "window.CRAFT_GRAPH = %s;\n" % sanitize_json(graph)
    return paths.write_under_graph(root, "graph.js", text)


def write_mirror(root, node_id, record_text):
    text = (
        "window.CRAFT_RECORDS = window.CRAFT_RECORDS || {};\n"
        "window.CRAFT_RECORDS[%s] = %s;\n"
        % (sanitize_json(node_id), sanitize_json(record_text))
    )
    return paths.write_under_graph(
        root, os.path.join("records", node_id + ".js"), text
    )


def sweep_orphans(root, keep_ids):
    """Remove records/*.js mirrors whose record no longer exists."""
    records_dir = os.path.join(
        os.path.realpath(root), ".craft", "graph", "records"
    )
    removed = 0
    if not os.path.isdir(records_dir):
        return removed
    for filename in sorted(os.listdir(records_dir)):
        if not filename.endswith(".js"):
            continue
        if filename[: -len(".js")] not in keep_ids:
            paths.remove_under_graph(
                root, os.path.join("records", filename)
            )
            removed += 1
    return removed


def write_all(root, graph, texts):
    """Emit everything -> (files_written, orphans_removed)."""
    written = 0
    if write_graph(root, graph):
        written += 1
    for node_id in sorted(texts):
        if write_mirror(root, node_id, texts[node_id]):
            written += 1
    removed = sweep_orphans(root, set(texts))
    return written, removed
