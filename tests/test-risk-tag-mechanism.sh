#!/bin/bash
# test-risk-tag-mechanism.sh - Verify the risk-tag mechanism gate discriminates
#
# The plan-chunks structural check (row #8) scans a story's `## Risk Tags`
# section: for each `- tag-name    # comment` line in the risk_tags YAML block,
# ONLY the text after the first `#` is scanned. A comment carrying a numeric
# threshold with no mechanism/verification connective is flagged; a comment
# with no threshold always passes; tag names and YAML structure are never
# scanned. These tests run that exact logic against static fixtures and verify
# the authoring/consumption surfaces carry the rule.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

# --- The gate logic under test (mirrors SKILL.md check #8) ---

# Prints the ## Risk Tags section body (heading to next ## heading or EOF)
risk_tags_section() {
  awk '/^## Risk Tags/{found=1; next} /^## /{if(found) exit} found' "$1"
}

# Prints the extracted comment of each tag line (text after the first #).
# The scan unit: only `- ` tag lines, only their post-# comment text.
risk_tag_comments() {
  risk_tags_section "$1" | grep -E '^[[:space:]]*- ' | grep '#' | sed 's/^[^#]*#//'
}

# Returns 0 if the comment text contains a threshold token
comment_has_threshold() {
  echo "$1" | grep -Eq '([0-9]+[[:space:]]?(px|pt|rem))|((>=|<=|>|<)[[:space:]]?[0-9])'
}

# Returns 0 if the comment text contains a mechanism/verification connective
comment_has_connective() {
  echo "$1" | grep -Eiq '(via|through|instead of|not min-height|extend|hit area|padding|pseudo-element|verif|cite|rule)'
}

# Prints "flagged" if any tag comment has a threshold with no connective
gate_verdict() {
  local verdict="passes"
  while IFS= read -r comment; do
    [ -z "$comment" ] && continue
    if comment_has_threshold "$comment" && ! comment_has_connective "$comment"; then
      verdict="flagged"
    fi
  done < <(risk_tag_comments "$1")
  echo "$verdict"
}

# --- Fixtures ---

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

FIXTURE_BARE="$TMP_DIR/story-bare-threshold.md"
cat > "$FIXTURE_BARE" << 'EOF'
# Story fixture: bare-threshold tag comment

## Risk Tags

```yaml
risk_tags:
  - has-touch-targets    # must stay >=44px
```

## Acceptance
EOF

FIXTURE_MECHANISM="$TMP_DIR/story-mechanism-named.md"
cat > "$FIXTURE_MECHANISM" << 'EOF'
# Story fixture: mechanism-named tag comment with verification threshold

## Risk Tags

```yaml
risk_tags:
  - has-touch-targets    # hit area extended via padding/pseudo-element, not min-height on the visual element; verify computed target >=44px
```

## Acceptance
EOF

FIXTURE_RESTING="$TMP_DIR/story-no-threshold.md"
cat > "$FIXTURE_RESTING" << 'EOF'
# Story fixture: long single-line comment with no threshold token

## Risk Tags

```yaml
risk_tags:
  - diverges-from-existing    # an implementer reading the surrounding code would naturally mirror the legacy modal pattern here, but this feature must follow the drawer pattern the design system standardized on; the divergence is intentional and the legacy pattern must not be copied forward into the new surface
```

## Acceptance
EOF

FIXTURE_TAG_DIGIT="$TMP_DIR/story-digit-in-tag-name.md"
cat > "$FIXTURE_TAG_DIGIT" << 'EOF'
# Story fixture: digit in the tag NAME, clean comment

## Risk Tags

```yaml
risk_tags:
  - has-variants-2col    # follow the existing grid mechanism
```

## Acceptance
EOF

# --- Tests ---

echo "=== test-risk-tag-mechanism.sh ==="
echo ""

# Test 1: a bare-threshold tag comment is flagged
begin_test "bare-threshold tag comment is flagged"

assert_eq \
  "gate flags a comment with a threshold and no mechanism wording" \
  "flagged" \
  "$(gate_verdict "$FIXTURE_BARE")"

echo ""

# Test 2: a mechanism-named comment with a verification threshold passes
begin_test "mechanism-named tag comment passes"

assert_eq \
  "gate passes a comment that names the mechanism with the threshold as verification" \
  "passes" \
  "$(gate_verdict "$FIXTURE_MECHANISM")"

echo ""

# Test 3: a long comment with no threshold token is never flagged
begin_test "no-threshold comment is never flagged"

assert_eq \
  "gate passes a long comment with no numeric token regardless of wording" \
  "passes" \
  "$(gate_verdict "$FIXTURE_RESTING")"

echo ""

# Test 4: the scan unit is the # comment only - digits in tag names are ignored
begin_test "scan unit is the # comment only"

assert_eq \
  "gate ignores digits in tag names; only the extracted comment is scanned" \
  "passes" \
  "$(gate_verdict "$FIXTURE_TAG_DIGIT")"

echo ""

# Test 5: the fixtures carry the section and YAML format the gate scans
begin_test "fixture carries the Risk Tags section and YAML tag-line format"

assert_file_contains \
  "fixture contains the section heading" \
  "^## Risk Tags" \
  "$FIXTURE_BARE"

assert_file_contains \
  "fixture contains a YAML tag line with a # comment" \
  "^  - has-touch-targets    # " \
  "$FIXTURE_BARE"

echo ""

# Test 7: the canonical anchor string is present on all three rule surfaces
begin_test "anchor string present on all three rule surfaces"

assert_file_contains \
  "chunk-format-guide carries the canonical anchor heading" \
  "^### Risk Tag Authoring Rule" \
  "$PLUGIN_ROOT/skills/plan-chunks/references/chunk-format-guide.md"

assert_file_contains \
  "content-spark SKILL body carries the short form under the anchor name" \
  "Risk Tag Authoring Rule" \
  "$PLUGIN_ROOT/skills/content-spark/SKILL.md"

assert_file_contains \
  "content-spark inline reference points at the anchor" \
  "Risk Tag Authoring Rule" \
  "$PLUGIN_ROOT/commands/references/content-spark-inline.md"

echo ""

finish_tests
