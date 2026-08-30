#!/usr/bin/env python3
"""CLI entry point for the dashboard graph builder.

Invocation shape: build.py --root <project-root>. Prints a one-line JSON
status object to stdout; exits 0 on success, 1 on an internal error (the
wrapper script translates that into a degraded build status).
"""

import argparse
import json
import sys

from src import assemble


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="build.py",
        description="Build .craft/graph/ graph data from .craft/ records.",
    )
    parser.add_argument(
        "--root", default=".", help="project root containing .craft/"
    )
    args = parser.parse_args(argv)
    try:
        result = assemble.build(args.root)
    except Exception as exc:  # noqa: BLE001 - one line out, wrapper degrades
        print(json.dumps({"status": "error", "reason": str(exc)}))
        return 1
    graph = result["graph"]
    print(
        json.dumps(
            {
                "status": "ok",
                "nodes": len(graph["nodes"]),
                "edges": len(graph["edges"]),
                "annotations": len(graph["annotations"]),
                "warnings": len(graph["build"]["warnings"]),
                "written": result["written"],
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
