"""Link-inventory coverage: the declared handler and ruled-out registries.

Every (record_type, field) pair from the authoritative link inventory maps
to exactly one of these two sets. A coverage test asserts the union equals
the transcribed inventory fixture - partial link coverage fails the build
rather than shipping quietly, and a stale entry fails just as loudly.
"""

from . import vocabulary


def _derive_handled():
    """Every pair a parser routes a link OR an annotation for, named the
    way __fixtures__/link_inventory.py spells it.

    vocabulary.FIELDS is the one place this used to be transcribed a
    second time: its optional "inventory" key carries the rename (or the
    None that folds a pair into another one) directly on the entry, so
    this is a pure comprehension rather than a bridge table between two
    modules."""
    handled = set()
    for (record_type, field), spec in vocabulary.FIELDS.items():
        if "inventory" in spec:
            inventory_field = spec["inventory"]
            if inventory_field is None:
                continue
        else:
            inventory_field = field
        handled.add((record_type, inventory_field))
    return handled


# Pairs a parser emits links or annotations for.
HANDLED = _derive_handled()

# Pairs deliberately excluded, each with a one-line reason.
RULED_OUT = {
    ("story", "element_binding_token_targets"):
        "tokens.yaml is design DNA, not a node - Token cells are annotations",
    ("tweak", "surface"):
        "virtual join key -> envelope attribute, never a node (Ruling 1)",
    ("dial", "surface"):
        "virtual join key -> envelope attribute, never a node (Ruling 1)",
    ("dial", "kind"):
        "shared tweak vocabulary -> envelope attribute, not a link",
    ("dial", "offered"):
        "comma string of candidate values, not references",
    ("notebook", "tags"):
        "facets -> envelope attribute, not links",
    ("riff", "riff"):
        "free-text title field, no structured links by spec",
    ("riff", "players"):
        "free-text participants field, no structured links by spec",
    ("riff", "date"):
        "date field, not a reference",
    ("mockup", "status"):
        "lifecycle value -> envelope attribute, not a link",
    ("checkpoint", "story"):
        "checkpoints are state, not records - not nodes (alignment)",
    ("checkpoint", "cycle"):
        "checkpoints are state, not records - not nodes (alignment)",
    ("checkpoint", "chunk"):
        "checkpoints are state, not records - not nodes (alignment)",
    ("request", "processed_marker"):
        "requests are not nodes in v1 (alignment)",
    ("learnings", "evidence_story"):
        "state file, not a record - out of v1 (Ruling 2)",
    ("learnings", "meta_cycle"):
        "state file, not a record - out of v1 (Ruling 2)",
    ("triage-ledger", "entries"):
        "state file, not a record - out of v1 (Ruling 2)",
}
