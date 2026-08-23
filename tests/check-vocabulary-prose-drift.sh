#!/bin/bash
# check-vocabulary-prose-drift.sh - shared field-axis logic for Decision 12's
# prose-versus-definition gate (Story 7, Chunk 5).
#
# NOT a test file itself (no test-*.sh name, so run-all.sh never runs it
# standalone). Sourced by tests/test-vocabulary-prose.sh (the always-run
# suite) AND scripts/check-doc-drift.sh (the manual/push-gate tool), so the
# rule is written once. Two copies of a drift rule is the drift this story
# exists to end.
#
# Field names are read live from src/vocabulary.FIELDS via python - nothing
# about the DEFINITION's expected values is hardcoded here, per the iron
# rule at the top of check-doc-drift.sh. What IS a literal list, with
# reasons, is the doc SCOPE (which four reference docs this check reads and
# which record type each one is the sole authority for) and the small set
# of bookkeeping frontmatter keys (name, status, taste...) that are
# structurally never a relationship to another record - scope, not values.

VOCAB_PROSE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
VOCAB_PROSE_DASHBOARD="$VOCAB_PROSE_ROOT/scripts/dashboard"

# The four reference docs where craft's record-linking fields are
# documented in prose. templates/story-full.md is deliberately absent - it
# names dependency markers ("Blocked by:", "Blocks:") as bold headers, never
# as backticked field names, so it carries nothing this check can read.
VOCAB_PROSE_DOCS=(
  "skills/adhoc/references/fix.md"
  "skills/adhoc/references/tweak.md"
  "commands/references/mockup-inline.md"
  "commands/references/story-from-mockup.md"
)

# path -> the one record type this doc is the SOLE reference for; every
# vocabulary.FIELDS entry for that type must appear here (reverse
# direction). story-from-mockup.md owns nothing here on purpose: it only
# documents the two lineage fields a mockup graduation writes onto a story
# (mockup, grew_from), not the story's full field grammar, which lives in
# templates/story-full.md - outside this check's four-doc scope.
VOCAB_PROSE_OWNERS=(
  "skills/adhoc/references/fix.md|fix"
  "skills/adhoc/references/tweak.md|tweak"
  "commands/references/mockup-inline.md|mockup"
)

# Bookkeeping frontmatter keys that are never a link to another record -
# each entry is "key:one-line reason". Structural facts about craft's own
# record schema, not a second copy of KINDS/FIELDS/STATUSES.
VOCAB_PROSE_NONLINK=(
  "name:every record's own identity field, never a link"
  "status:checked by the STATUS axis (test_vocabulary.py), not this one"
  "lesson_scope:fix's craft|project bookkeeping enum"
  "kind:tweak's own category enum (icon|copy|spacing|...)"
  "surface:tweak's free-text location slug"
  "taste:tweak's close-out sentiment stamp"
  "created:universal bookkeeping date field"
  "project:the project-name bookkeeping field (mockup-inline.md:98)"
  "evaluate_script:a Chrome DevTools tool name in prose, not a field"
  "subagent_type:an Agent tool invocation parameter, not a field"
  "tweak:a commit-message prefix convention mentioned in prose"
  "alignment:the story alignment-gate field, unrelated to record links"
)

_vocab_prose_is_nonlink() {
  local word="$1" entry
  for entry in "${VOCAB_PROSE_NONLINK[@]}"; do
    [ "${entry%%:*}" = "$word" ] && return 0
  done
  return 1
}

# Every distinct field name vocabulary.FIELDS knows, across every record
# type - derived live, one process per call.
_vocab_prose_known_fields() {
  python3 -c "
import sys
sys.path.insert(0, '$VOCAB_PROSE_DASHBOARD')
from src import vocabulary
for _, field in sorted(vocabulary.FIELDS):
    print(field)
" | sort -u
}

# Every field vocabulary.FIELDS knows for one record type.
_vocab_prose_fields_for_type() {
  python3 -c "
import sys
sys.path.insert(0, '$VOCAB_PROSE_DASHBOARD')
from src import vocabulary
for record_type, field in sorted(vocabulary.FIELDS):
    if record_type == '$1':
        print(field)
"
}

# Direction 1 over one doc: every backticked field-shaped mention adjacent
# to a colon - the shape a real field-setting instruction takes in these
# docs (` field:` or `field`:) - must be a field the definition knows about
# SOMEWHERE. Never scoped to the doc's own record type: a doc legitimately
# names the field of a record it hands off to (tweak.md mentions the dial
# record's own `graduated_to`). Prints one finding per line to stdout.
_vocab_prose_check_direction1() {
  local doc="$1" path="$2" known_fields="$3"
  local line word
  while read -r line word; do
    [ -z "$word" ] && continue
    _vocab_prose_is_nonlink "$word" && continue
    if ! printf '%s\n' "$known_fields" | grep -qxF "$word"; then
      echo "[field] $doc:$line names \`$word\` with no matching vocabulary.FIELDS entry"
    fi
  done < <(grep -noE '`[a-z][a-z_]*:|`[a-z][a-z_]*`:' "$path" \
    | sed -E 's/^([0-9]+):`([a-z_]+)`?:$/\1 \2/')
}

# Direction 2 over one doc: every field vocabulary.FIELDS declares for the
# doc's owned record type must appear in it, plain text - the frontmatter
# block that ships a field is fenced code, never backtick-wrapped, so this
# direction cannot require a backtick the way direction 1 does.
_vocab_prose_check_direction2() {
  local doc="$1" path="$2" record_type="$3"
  local field
  while read -r field; do
    [ -z "$field" ] && continue
    grep -qF "$field" "$path" \
      || echo "[field] $doc documents $record_type but never names \`$field\`, which vocabulary.FIELDS declares for it"
  done < <(_vocab_prose_fields_for_type "$record_type")
}

# Populates the global array VOCAB_PROSE_FINDINGS by walking the declared
# doc scope. Returns 0 (true) when clean, 1 (false) on any finding - callers
# that just want a pass/fail can use this in an if; callers that want the
# findings text read VOCAB_PROSE_FINDINGS after calling it.
check_vocabulary_prose_drift() {
  VOCAB_PROSE_FINDINGS=()
  local known_fields entry doc path
  known_fields="$(_vocab_prose_known_fields)"

  for doc in "${VOCAB_PROSE_DOCS[@]}"; do
    path="$VOCAB_PROSE_ROOT/$doc"
    [ -f "$path" ] || continue
    while IFS= read -r finding; do
      [ -n "$finding" ] && VOCAB_PROSE_FINDINGS+=("$finding")
    done < <(_vocab_prose_check_direction1 "$doc" "$path" "$known_fields")
  done

  for entry in "${VOCAB_PROSE_OWNERS[@]}"; do
    doc="${entry%%|*}"
    path="$VOCAB_PROSE_ROOT/$doc"
    [ -f "$path" ] || continue
    while IFS= read -r finding; do
      [ -n "$finding" ] && VOCAB_PROSE_FINDINGS+=("$finding")
    done < <(_vocab_prose_check_direction2 "$doc" "$path" "${entry##*|}")
  done

  [ "${#VOCAB_PROSE_FINDINGS[@]}" -eq 0 ]
}
