#!/bin/bash
# story-rules.sh - Print the extra rules a story's sources bring, for one reader.
#
# Usage: story-rules.sh <story-file> <planner|builder>
#
# The planner and the builder each run this before they start. A story with no
# special source prints nothing, so the common path costs one call and no
# words. Each source a story carries gets its own block: the facts checked
# about it, then that reader's part of the source's rules file under
# commands/references/.
#
#   source            found by                              rules file
#   mockup            frontmatter mockup:                   mockup-story-rules.md
#   decisions         frontmatter decisions:, as record     decision-record-story-rules.md
#                     names or as written-out sentences
#   planning sources  source_concept:, or a cited planning  citation-story-rules.md
#                     log or research file
#   motion            a Motion line, with no mockup         motion-story-rules.md
#   empty project     the project root holds only .craft    empty-project-story-rules.md
#                     and housekeeping files, no mockup
#   user interface    frontmatter type: ui, a mockup:,      ui-story-rules.md
#                     or a binding table
#
# The last two are not sources a story carries: one is the state of the
# project, the other is the kind of story. They ride here because the same two
# readers need them and most stories need neither.
#
# To add one: a block function below, a rules file with a
# "## planner" and/or "## builder" part, one call at the bottom.
#
# Silence must only ever mean "nothing applies". A block that cannot do its
# job prints a line starting "STORY RULES UNAVAILABLE", the other blocks still
# print, and the script exits 1, because a reader cannot tell an empty answer
# from a broken one.

STORY="${1:-}"
ROLE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$SCRIPT_DIR/../.." && pwd)"
# STORY_RULES_DIR lets the tests point at a rules folder with a file missing.
REFS="${STORY_RULES_DIR:-$PLUGIN/commands/references}"

FAILED=0
PRINTED=0

fatal() {
  echo "STORY RULES UNAVAILABLE: $1"
  exit 1
}

# Blocks are separated by one blank line.
open_block() {
  [ "$PRINTED" -eq 1 ] && echo ""
  PRINTED=1
}

block_failed() {
  open_block
  echo "STORY RULES UNAVAILABLE: $1"
  FAILED=1
}

case "$ROLE" in
  planner|builder) ;;
  *) fatal "the reader must be planner or builder, got '${ROLE}'" ;;
esac
[ -n "$STORY" ] || fatal "no story file given"
[ -f "$STORY" ] && [ -r "$STORY" ] || fatal "cannot read the story file $STORY"

# Frontmatter is the block between the first two --- lines.
FRONT=$(awk '
  NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
  /^---[[:space:]]*$/ { exit }
  { print }
' "$STORY")

# field <name> - one frontmatter value, without quotes, list brackets or a
# trailing comment. A YAML list written one item per line comes back
# space-separated.
field() {
  printf '%s\n' "$FRONT" | awk -v key="$1" '
    $0 ~ "^" key ":" {
      v = $0; sub("^" key ":[[:space:]]*", "", v); sub(/[[:space:]]#.*$/, "", v)
      on = (v == ""); out = v; next
    }
    on && /^[[:space:]]+-[[:space:]]/ { v = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", v); out = out " " v; next }
    on { on = 0 }
    END { print out }
  ' | tr -d '\r"[]' | tr -d "'" | tr ',' ' ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# items <name> - a frontmatter list, one item per line, whether it is written
# inline ([a, b]) or one item per line. An item may be a sentence.
items() {
  printf '%s\n' "$FRONT" | awk -v key="$1" '
    $0 ~ "^" key ":" {
      v = $0; sub("^" key ":[[:space:]]*", "", v)
      if (v == "") { on = 1; next }
      gsub(/^\[|\][[:space:]]*$/, "", v); n = split(v, a, ",")
      for (i = 1; i <= n; i++) print a[i]
      next
    }
    on && /^[[:space:]]+-[[:space:]]/ { v = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", v); print v; next }
    on { on = 0 }
  ' | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/' | sed '/^$/d'
}

# The project root is the story path up to /.craft/, the same rule the planner uses.
STORY_DIR="$(cd "$(dirname "$STORY")" 2>/dev/null && pwd)"
STORY_ABS="$STORY_DIR/$(basename "$STORY")"
case "$STORY_ABS" in
  */.craft/*) ROOT="${STORY_ABS%%/.craft/*}" ;;
  *) ROOT="" ;;
esac

# part <rules file> [heading] - one part of a rules file, heading left out.
# The heading defaults to the reader's name.
part() {
  [ -r "$REFS/$1" ] || return 0
  awk -v want="## ${2:-$ROLE}" '
    $0 == want { on = 1; next }
    /^## / { on = 0 }
    on { print }
  ' "$REFS/$1" | sed '/./,$!d'
}

# The story above its plan: sources live there, and a table inside a chunk is
# not the story's binding table.
BODY=$(awk '/^## Chunks/ { exit } { print }' "$STORY")

# binding_counts - "<rows> <rows marked TBD>" for tables whose first column
# is Part or Element.
binding_counts() {
  printf '%s\n' "$BODY" | awk '
    /^\|[[:space:]]*(Part|Element)[[:space:]]*\|/ { in_table = 1; sep = 1; next }
    in_table && sep && /^\|[-:|[:space:]]+\|[[:space:]]*$/ { sep = 0; next }
    in_table && /^\|/ {
      rows++
      if ($0 ~ /(^|[^A-Za-z])TBD([^A-Za-z]|$)/) tbd++
      sep = 0
      next
    }
    { in_table = 0; sep = 0 }
    END { printf "%d %d", rows, tbd }
  '
}

MOCKUP_RAW=$(field mockup)

# --- A story built from a mockup -------------------------------------------
mockup_block() {
  [ -n "$MOCKUP_RAW" ] || return 0
  if [ -z "$ROOT" ]; then
    block_failed "the story names a mockup but is not under a .craft folder, so the mockup cannot be found: $STORY_ABS"
    return 0
  fi
  local rules found="" missing="" entry name file counts
  rules=$(part mockup-story-rules.md)
  if [ -z "$rules" ]; then
    block_failed "this story names a mockup ($MOCKUP_RAW) but the $ROLE rules could not be read from $REFS/mockup-story-rules.md"
    return 0
  fi

  for entry in $MOCKUP_RAW; do
    name="${entry%/}"
    name="${name%/mockup.html}"
    name="${name##*mockups/}"
    [ -n "$name" ] || continue
    file="$ROOT/.craft/mockups/$name/mockup.html"
    if [ -f "$file" ]; then
      found="${found}- mockup file: $file
"
    else
      missing="${missing}- MOCKUP FILE MISSING: $file
"
    fi
  done

  open_block
  # A mockup that cannot be read leaves nothing to carry over, so the rules
  # are held back and the reader is told what to do instead.
  if [ -n "$missing" ]; then
    echo "This story was built from a mockup, and the approved look cannot be read:"
    printf '%s' "$missing"
    if [ "$ROLE" = "planner" ]; then
      echo "List this as a Critical Blocker. Never plan the look from the story's description."
    else
      echo "Stop and report this under Not done. Never rebuild the look from the story's description."
    fi
    return 0
  fi

  echo "This story was built from a mockup. Follow the rules below. Facts checked first:"
  printf '%s' "$found"
  # Only the planner binds rows, so only the planner is told the count.
  if [ "$ROLE" = "planner" ]; then
    counts=$(binding_counts)
    if [ "${counts%% *}" -gt 0 ]; then
      echo "- binding table: ${counts%% *} rows, ${counts##* } marked TBD"
    else
      echo "- binding table: none in this story"
    fi
  fi
  echo ""
  printf '%s\n' "$rules"
}

# --- A story that carries decisions in its header ---------------------------
# The decisions: list holds record names (one word, no spaces) that point at
# files under .craft/decisions/, and in older stories whole sentences: the
# decision itself, written out. Each kind gets its own facts and rules.
decisions_block() {
  [ "$ROLE" = "planner" ] || return 0
  local all records="" written="" item rules file created
  all=$(items decisions)
  [ -n "$all" ] || return 0
  while IFS= read -r item; do
    case "$item" in
      *[[:space:]]*) written="${written}${item}
" ;;
      *) records="${records}${item}
" ;;
    esac
  done <<EOF_ITEMS
$all
EOF_ITEMS

  if [ -n "$records" ]; then
    rules=$(part decision-record-story-rules.md)
    if [ -z "$ROOT" ]; then
      block_failed "the story carries decision records but is not under a .craft folder, so they cannot be found: $STORY_ABS"
    elif [ -z "$rules" ]; then
      block_failed "this story carries decision records but the $ROLE rules could not be read from $REFS/decision-record-story-rules.md"
    else
      open_block
      echo "This story carries decision records. Follow the rules below. Facts checked first:"
      while IFS= read -r item; do
        [ -n "$item" ] || continue
        # A name may be written with its folder or its .md ending.
        item="${item##*/}"
        item="${item%.md}"
        file="$ROOT/.craft/decisions/approved/$item.md"
        if [ -f "$file" ]; then
          created=$(sed -n 's/^created:[[:space:]]*//p' "$file" | head -1 | tr -d '\r')
          if grep -q '^disposition:[[:space:]]*crafted' "$file"; then
            echo "- record: $file (ruled ${created:-date unknown}; frozen, already built)"
          else
            echo "- record: $file (ruled ${created:-date unknown})"
          fi
        elif [ -f "$ROOT/.craft/decisions/archive/$item.md" ]; then
          echo "- RECORD RETIRED: $item is in the archive and no longer in force"
        else
          echo "- RECORD NOT FOUND: $item has no file under $ROOT/.craft/decisions/approved/"
        fi
      done <<EOF_RECORDS
$records
EOF_RECORDS
      echo ""
      printf '%s\n' "$rules"
    fi
  fi

  if [ -n "$written" ]; then
    rules=$(part decision-record-story-rules.md "planner, decisions written in the header")
    if [ -z "$rules" ]; then
      block_failed "this story has decisions written in its header but the rules for them could not be read from $REFS/decision-record-story-rules.md"
    else
      open_block
      echo "This story has decisions written in its header. Follow the rule below. They are:"
      while IFS= read -r item; do
        [ -n "$item" ] && echo "- $item"
      done <<EOF_WRITTEN
$written
EOF_WRITTEN
      echo ""
      printf '%s\n' "$rules"
    fi
  fi
}

# --- A story that came from planning, or cites a planning log or research --
citations_block() {
  [ "$ROLE" = "planner" ] || return 0
  local concept refs entries log research rules
  concept=$(field source_concept)
  # Read from the whole story: on a re-plan the section can sit below the plan.
  refs=$(awk '/^## Reference Materials/ { on = 1; next } /^## / { on = 0 } on' "$STORY")
  entries=$(printf '%s\n' "$refs" | grep -c '^[[:space:]]*[-*][[:space:]]' || true)
  log=$(printf '%s\n' "$refs" | grep -c 'active\.md' || true)
  research=$(printf '%s\n' "$refs" | grep -c '\.craft/research/' || true)
  [ -n "$concept" ] || [ "$log" -gt 0 ] || [ "$research" -gt 0 ] || return 0
  rules=$(part citation-story-rules.md)
  if [ -z "$rules" ]; then
    block_failed "this story has planning sources but the $ROLE rules could not be read from $REFS/citation-story-rules.md"
    return 0
  fi

  open_block
  echo "This story has planning sources. Follow the rules below. Facts checked first:"
  [ -n "$concept" ] && echo "- written from a planning concept: $concept"
  if [ "$entries" -gt 0 ]; then
    echo "- Reference Materials: $entries entries"
  else
    echo "- NO REFERENCE MATERIALS: the story cites nothing"
  fi
  [ "$log" -gt 0 ] && echo "- cites a planning log (active.md)"
  [ "$research" -gt 0 ] && echo "- cites research"
  echo ""
  printf '%s\n' "$rules"
}

# --- A story with a Motion line --------------------------------------------
# A mockup settles its own motion, so a story that names one never gets the
# catalog rules as well.
motion_block() {
  [ -z "$MOCKUP_RAW" ] || return 0
  # The label may be a bullet and may carry a note: "- **Motion (GPU-safe):**".
  # A line that says there is none brings no rules.
  local line rules catalog
  line=$(printf '%s\n' "$BODY" | grep -m1 -E '^[[:space:]]*([-*][[:space:]]+)?\*\*Motion([[:space:]]*\([^)]*\))?:\*\*' || true)
  [ -n "$line" ] || return 0
  printf '%s\n' "$line" | grep -q -i -E ':\*\*[[:space:]]*(none|n/a)([^a-z]|$)' && return 0
  rules=$(part motion-story-rules.md)
  if [ -z "$rules" ]; then
    block_failed "this story has a Motion line but the $ROLE rules could not be read from $REFS/motion-story-rules.md"
    return 0
  fi

  open_block
  # Only the planner picks from the catalog, so only the planner is shown it.
  # The project's own catalog comes first; the plugin's general one stands in.
  if [ "$ROLE" = "planner" ]; then
    echo "This story has a Motion line. Follow the rules below. Facts checked first:"
    catalog=""
    [ -n "$ROOT" ] && [ -f "$ROOT/.craft/design/animations.md" ] && catalog="$ROOT/.craft/design/animations.md"
    if [ -n "$catalog" ]; then
      echo "- motion catalog: $catalog"
    elif [ -f "$PLUGIN/templates/craft/design/animations.md" ]; then
      echo "- motion catalog: $PLUGIN/templates/craft/design/animations.md (the plugin's general catalog; this project has none of its own)"
    else
      echo "- NO MOTION CATALOG FOUND"
    fi
  else
    echo "This story has a Motion line. Follow the rules below."
  fi
  echo ""
  printf '%s\n' "$rules"
}

# --- A project with nothing in it yet ---------------------------------------
# Only the planner needs this. A mockup story is handled by the mockup rules.
# A miss here costs a missing setup chunk; a false hit would lay a new project
# over live code, so the check fires only when the root holds nothing it does
# not recognize, and says nothing inside a larger repository.
empty_project_block() {
  [ "$ROLE" = "planner" ] || return 0
  [ -z "$MOCKUP_RAW" ] || return 0
  [ -n "$ROOT" ] && [ -d "$ROOT" ] || return 0
  local here top other rules
  here=$(cd "$ROOT" && pwd -P)
  top=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)
  # Inside a larger repo the parent may hold the build: say nothing.
  [ -z "$top" ] || [ "$top" = "$here" ] || return 0
  other=$(ls -A "$ROOT" | grep -v -x -E '\.craft|\.git|\.gitignore|\.gitattributes|\.claude|\.DS_Store|CLAUDE\.md|AGENTS\.md|README.*|LICENSE.*|COPYING.*' | head -1 || true)
  [ -z "$other" ] || return 0
  rules=$(part empty-project-story-rules.md)
  if [ -z "$rules" ]; then
    block_failed "this project has no code yet but the $ROLE rules could not be read from $REFS/empty-project-story-rules.md"
    return 0
  fi

  open_block
  echo "This project has no code yet. Follow the rules below. Facts checked first:"
  echo "- nothing under $ROOT except .craft and repository housekeeping files"
  echo ""
  printf '%s\n' "$rules"
}

# --- A story with a user interface -------------------------------------------
# Only the builder is told; the planner already has the Visual Direction rules.
# Some user-interface stories carry no type, so a mockup or a binding table
# counts too.
ui_block() {
  [ "$ROLE" = "builder" ] || return 0
  local kind why="" counts rules
  kind=$(field type | tr '[:upper:]' '[:lower:]')
  if [ "$kind" = "ui" ]; then
    why="the story's type is ui"
  elif [ -n "$MOCKUP_RAW" ]; then
    why="the story names a mockup"
  else
    counts=$(binding_counts)
    [ "${counts%% *}" -gt 0 ] && why="the story has a Visual Direction binding table"
  fi
  [ -n "$why" ] || return 0
  rules=$(part ui-story-rules.md)
  if [ -z "$rules" ]; then
    block_failed "this story has a user interface but the $ROLE rules could not be read from $REFS/ui-story-rules.md"
    return 0
  fi

  open_block
  echo "This story has a user interface. Follow the rules below. Facts checked first:"
  echo "- $why"
  echo ""
  printf '%s\n' "$rules"
}

mockup_block
decisions_block
citations_block
motion_block
empty_project_block
ui_block

exit "$FAILED"
