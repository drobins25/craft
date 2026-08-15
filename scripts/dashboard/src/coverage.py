"""Link-inventory coverage: the declared handler and ruled-out registries.

Every (record_type, field) pair from the authoritative link inventory maps
to exactly one of these two sets. A coverage test asserts the union equals
the transcribed inventory fixture - partial link coverage fails the build
rather than shipping quietly, and a stale entry fails just as loudly.
"""

# Pairs a parser emits links or annotations for.
HANDLED = {
    ("story", "cycle"),
    ("story", "mockup"),
    ("story", "grew_from"),
    ("story", "dependencies_blocked_by"),
    ("story", "dependencies_blocks"),
    ("story", "reference_materials"),
    ("story", "element_binding_table"),
    ("story", "body_paths"),
    ("story", "body_wikilinks"),
    ("cycle", "source_concept"),
    ("cycle", "stories_membership"),
    ("fix", "source_story"),
    ("fix", "source_cycle"),
    ("fix", "satisfied_todo"),
    ("tweak", "source_story"),
    ("tweak", "mockup"),
    ("tweak", "dial"),
    ("tweak", "reapplies"),
    ("tweak", "grew_from"),
    ("tweak", "satisfied_todo"),
    ("dial", "graduated_to"),
    ("mockup", "graduated_to"),
    ("mockup", "origin"),
    ("mockup", "solidify_outcome"),
    ("notebook", "graduated_to"),
    ("notebook", "source"),
    ("planning", "body_paths"),
    ("planning", "body_wikilinks"),
    ("riff", "body_paths"),
    ("riff", "body_wikilinks"),
}

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
