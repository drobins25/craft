"""Graph stats: derived ONLY from assembled nodes and edges.

This module never opens a file - the pure-lens law and testability both
depend on it staying file-free. days_of_craft spans the oldest to the most
recent node date, NEVER today: deriving it from the clock would change
graph.js daily on an untouched corpus and break byte-identical rebuilds.
"""

import datetime
from collections import Counter

from . import vocabulary

# Kinds counted toward the "born from" stat - derived from the definition's
# lineage flag so a new lineage kind is one flag in vocabulary.py, not a
# second hand-kept tuple here.
LINEAGE_KINDS = tuple(
    kind for kind in vocabulary.KINDS if vocabulary.KINDS[kind]["lineage"]
)


def compute(nodes, edges):
    dates = [n["date"] for n in nodes if n.get("date")]
    birthday = min(dates) if dates else None
    days_of_craft = _day_diff(birthday, max(dates)) if dates else 0
    counter = Counter(n["type"] for n in nodes)
    counts = {t: counter[t] for t in sorted(counter)}
    return {
        "birthday": birthday,
        "days_of_craft": days_of_craft,
        "counts": counts,
        "keystone": _keystone(nodes, edges),
    }


def _day_diff(a, b):
    try:
        start = datetime.date.fromisoformat(str(a)[:10])
        end = datetime.date.fromisoformat(str(b)[:10])
        return (end - start).days
    except ValueError:
        return 0


def _keystone(nodes, edges):
    """Highest-degree node; ties broken by earliest date then smallest id.

    Null if and only if there are no nodes - a single edgeless node still
    wins at degree 0. The kind label is the most common incident edge kind,
    lineage kinds preferred over structural ones when both are present.
    """
    if not nodes:
        return None
    degree = Counter()
    incident = {}
    for edge in edges:
        for node_id in (edge["source"], edge["target"]):
            degree[node_id] += 1
            incident.setdefault(node_id, Counter())[edge["kind"]] += 1

    def rank(node):
        return (-degree[node["id"]], node.get("date") or "9999-99-99", node["id"])

    best = min(nodes, key=rank)
    kinds = incident.get(best["id"], Counter())
    label = None
    if kinds:
        lineage = {k: v for k, v in kinds.items() if k in LINEAGE_KINDS}
        pool = lineage or dict(kinds)
        label = sorted(pool.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
    return {"id": best["id"], "degree": degree[best["id"]], "kind": label}
