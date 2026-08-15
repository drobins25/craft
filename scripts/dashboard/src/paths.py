"""Filesystem boundary enforcement for the dashboard builder.

Reads stay inside <root>/.craft/; writes stay inside <root>/.craft/dashboard/.
Paths are realpath-resolved BEFORE the prefix comparison, so a symlink under
.craft/ pointing outside the project raises rather than leaking external file
content into a record mirror.

Every access is appended to a module-level log the build report reads - the
log is also how the boundary property is asserted in tests without
monkeypatching.
"""

import os


class BoundaryError(Exception):
    pass


_ACCESS_LOG = []


def reset_log():
    del _ACCESS_LOG[:]


def access_log():
    return list(_ACCESS_LOG)


def _resolve(base, path):
    if os.path.isabs(path):
        return os.path.realpath(path)
    return os.path.realpath(os.path.join(base, path))


def _ensure_under(resolved, boundary_dir, kind):
    boundary = os.path.realpath(boundary_dir)
    if resolved != boundary and not resolved.startswith(boundary + os.sep):
        raise BoundaryError("%s escapes %s: %s" % (kind, boundary, resolved))


def read_under_craft(root, path):
    """Read a file, raising BoundaryError unless it resolves under .craft/."""
    craft = os.path.join(os.path.realpath(root), ".craft")
    resolved = _resolve(craft, path)
    _ensure_under(resolved, craft, "read")
    _ACCESS_LOG.append(("read", resolved))
    with open(resolved, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def write_under_dashboard(root, path, data):
    """Write a file under .craft/dashboard/, idempotently and atomically.

    Compares existing bytes first and skips identical content (returns
    False), so an unchanged corpus produces zero writes. Real writes go
    through temp-file-plus-rename so a crash never leaves a truncated file.
    Returns True when bytes were written.
    """
    dashboard = os.path.join(os.path.realpath(root), ".craft", "dashboard")
    resolved = _resolve(dashboard, path)
    _ensure_under(resolved, dashboard, "write")
    _ACCESS_LOG.append(("write", resolved))
    if isinstance(data, str):
        data = data.encode("utf-8")
    if os.path.exists(resolved):
        with open(resolved, "rb") as f:
            if f.read() == data:
                return False
    os.makedirs(os.path.dirname(resolved), exist_ok=True)
    tmp = resolved + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, resolved)
    return True


def remove_under_dashboard(root, path):
    """Remove a file under .craft/dashboard/, boundary-checked and logged."""
    dashboard = os.path.join(os.path.realpath(root), ".craft", "dashboard")
    resolved = _resolve(dashboard, path)
    _ensure_under(resolved, dashboard, "remove")
    _ACCESS_LOG.append(("remove", resolved))
    if os.path.exists(resolved):
        os.remove(resolved)
        return True
    return False
