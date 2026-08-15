"""The authoritative link inventory, transcribed once as (type, field) pairs.

Authored from the story's Alignment Link Inventory - the enumeration of
every field or body grammar that can hold a reference, taken from craft's
record-WRITING source (templates, hooks/scripts, skill specs). The coverage
test asserts the code's HANDLED | RULED_OUT registries equal this set
exactly; the two sides are authored independently so a mismatch is a real
diff, not a tautology.
"""

INVENTORY = {
    # story
    ("story", "cycle"),
    ("story", "mockup"),
    ("story", "grew_from"),
    ("story", "dependencies_blocked_by"),
    ("story", "dependencies_blocks"),
    ("story", "reference_materials"),
    ("story", "element_binding_table"),
    ("story", "element_binding_token_targets"),
    ("story", "body_paths"),
    ("story", "body_wikilinks"),
    # cycle
    ("cycle", "source_concept"),
    ("cycle", "stories_membership"),
    # fix
    ("fix", "source_story"),
    ("fix", "source_cycle"),
    ("fix", "satisfied_todo"),
    # tweak
    ("tweak", "source_story"),
    ("tweak", "mockup"),
    ("tweak", "dial"),
    ("tweak", "reapplies"),
    ("tweak", "grew_from"),
    ("tweak", "satisfied_todo"),
    ("tweak", "surface"),
    # dial
    ("dial", "graduated_to"),
    ("dial", "surface"),
    ("dial", "kind"),
    ("dial", "offered"),
    # mockup
    ("mockup", "graduated_to"),
    ("mockup", "status"),
    ("mockup", "origin"),
    ("mockup", "solidify_outcome"),
    # notebook
    ("notebook", "graduated_to"),
    ("notebook", "source"),
    ("notebook", "tags"),
    # planning (body grammar per Ruling 3)
    ("planning", "body_paths"),
    ("planning", "body_wikilinks"),
    # riff
    ("riff", "riff"),
    ("riff", "players"),
    ("riff", "date"),
    ("riff", "body_paths"),
    ("riff", "body_wikilinks"),
    # satellite surfaces - present in the inventory, excluded from v1
    ("checkpoint", "story"),
    ("checkpoint", "cycle"),
    ("checkpoint", "chunk"),
    ("request", "processed_marker"),
    ("learnings", "evidence_story"),
    ("learnings", "meta_cycle"),
    ("triage-ledger", "entries"),
}
