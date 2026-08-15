"""Sentinel vocabulary: values that look like references but must never
resolve to an edge.

Record fields hold placeholder and negative values by design ("none-matched",
"n/a", template placeholders in square brackets). The resolver refuses these
before any lookup; they become annotations, never edges.
"""

_EXACT = {"", "none", "n/a", "na", "unknown", "tbd", "none-matched"}


def is_sentinel(value):
    """True when the value is a placeholder/negative, never a reference."""
    if value is None:
        return True
    v = str(value).strip().lower()
    if v in _EXACT:
        return True
    if v.startswith("none -") or v.startswith("none-"):
        return True
    if v.startswith("[") and v.endswith("]") and not v.startswith("[["):
        return True
    return False
