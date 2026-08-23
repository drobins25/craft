"""Sentinel vocabulary: values that look like references but must never
resolve to an edge.

Record fields hold placeholder and negative values by design ("none-matched",
"n/a", template placeholders in square brackets). The resolver refuses these
before any lookup; they become annotations, never edges.
"""

_EXACT = {
    "",
    "none",
    "n/a",
    "na",
    "unknown",
    "tbd",
    "none-matched",
    "nothing",
    "null",
    "nope",
    "no",
}


def is_sentinel(value):
    """True when the value is a placeholder/negative, never a reference."""
    if value is None:
        return True
    v = str(value).strip().lower()
    # A negative declaration is often the last word of a sentence ("None.",
    # "Nothing!") - strip the closing punctuation before matching so the
    # refusal rule does not depend on whether the writer added a period.
    v = v.rstrip(".!?")
    if v in _EXACT:
        return True
    if v.startswith("none -") or v.startswith("none-"):
        return True
    if v.startswith("[") and v.endswith("]") and not v.startswith("[["):
        return True
    return False
