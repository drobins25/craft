"""Hand-authored minimal node list for resolver tests.

Neutral placeholder names only - no real user project content. The shapes
matter: two stories sharing a bare name across cycles, a tweak sharing a
slug with those stories, a cycle citable by numbered and bare forms, and a
todo as a cross-type graduation target.
"""


def _node(node_id, node_type, path, name, date):
    return {
        "id": node_id,
        "type": node_type,
        "date": date,
        "_path": path,
        "_name": name,
    }


NODES = [
    _node(
        "story--cycles--7-sample-cycle--stories--3-widget-panel",
        "story",
        "cycles/7-sample-cycle/stories/3-widget-panel.md",
        "widget-panel",
        "2026-01-05",
    ),
    _node(
        "story--cycles--8-other-cycle--stories--2-widget-panel",
        "story",
        "cycles/8-other-cycle/stories/2-widget-panel.md",
        "widget-panel",
        "2026-02-10",
    ),
    _node(
        "cycle--cycles--7-sample-cycle--cycle",
        "cycle",
        "cycles/7-sample-cycle/cycle.yaml",
        "sample-cycle",
        "2026-01-01",
    ),
    _node(
        "tweak--tweaks--tweak-widget-panel",
        "tweak",
        "tweaks/tweak-widget-panel.md",
        "widget-panel",
        "2026-03-01",
    ),
    _node(
        "tweak--tweaks--tweak-sample-polish",
        "tweak",
        "tweaks/tweak-sample-polish.md",
        "sample-polish",
        "2026-03-02",
    ),
    _node(
        "notebook--notebook--todos--2026-01-20-sample-todo",
        "notebook",
        "notebook/todos/2026-01-20-sample-todo.md",
        "sample-todo",
        "2026-01-20",
    ),
]
