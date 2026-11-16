#!/bin/bash
# story-rules.sh - Print the extra rules a story's sources bring, for one reader.
#
# Usage: story-rules.sh <story-file> <planner|builder|orchestrator>
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
# The orchestrator (the plan-chunks skill) is a third reader with one block of
# its own. It runs this before it plans, and hears only about a story that is
# not planned yet, whose look was settled in a mockup, an annotate run or a
# dial, and whose binding table is missing (settled-look-story-rules.md). None
# of the blocks above print for it.
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
  planner|builder|orchestrator) ;;
  *) fatal "the reader must be planner, builder or orchestrator, got '${ROLE}'" ;;
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
    # The story template ships one row of bracketed placeholders. It is not a row.
    in_table && /^\|[[:space:]]*\[[^]|]*\][[:space:]]*\|/ { sep = 0; next }
    # Neither is a row whose last cell says nothing.
    in_table && /\|[[:space:]]*-?[[:space:]]*\|[[:space:]]*$/ { sep = 0; next }
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
case "$MOCKUP_RAW" in none|None|null|'~'|n/a|N/A) MOCKUP_RAW="" ;; esac

# mockup_names - the folder name of each mockup the story's header names, one
# a line. The header may give a bare name, a folder path or the file's path.
mockup_names() {
  local entry name
  for entry in $MOCKUP_RAW; do
    name="${entry%/}"
    name="${name%/mockup.html}"
    name="${name##*mockups/}"
    [ -n "$name" ] && printf '%s\n' "$name"
  done
  return 0
}

# mockup_dirs_pointing_here - the folder of each mockup whose record says it
# graduated to this story, one a line. A mockup record carries no outcome
# line, so any record that names this story counts.
mockup_dirs_pointing_here() {
  local r
  for r in "$ROOT"/.craft/mockups/*/record.md; do
    [ -f "$r" ] && points_here "$r" && dirname "$r"
  done
  return 0
}

# find_mockups - looks up each mockup the story names and sets MOCKUPS_FOUND
# and MOCKUPS_MISSING, one "- ..." line per mockup.
find_mockups() {
  local name file
  MOCKUPS_FOUND=""
  MOCKUPS_MISSING=""
  for name in $(mockup_names); do
    file="$ROOT/.craft/mockups/$name/mockup.html"
    if [ -f "$file" ]; then
      MOCKUPS_FOUND="${MOCKUPS_FOUND}- mockup file: $file
"
    else
      MOCKUPS_MISSING="${MOCKUPS_MISSING}- MOCKUP FILE MISSING: $file
"
    fi
  done
}

# --- A story built from a mockup -------------------------------------------
mockup_block() {
  [ -n "$MOCKUP_RAW" ] || return 0
  if [ -z "$ROOT" ]; then
    block_failed "the story names a mockup but is not under a .craft folder, so the mockup cannot be found: $STORY_ABS"
    return 0
  fi
  local rules found="" missing="" counts
  rules=$(part mockup-story-rules.md)
  if [ -z "$rules" ]; then
    block_failed "this story names a mockup ($MOCKUP_RAW) but the $ROLE rules could not be read from $REFS/mockup-story-rules.md"
    return 0
  fi

  find_mockups
  found="$MOCKUPS_FOUND"
  missing="$MOCKUPS_MISSING"

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
  [ "$MOCKUP_FROM_RECORD" -eq 1 ] && echo "- story header: has no mockup: line; the mockup's record points at this story"
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
  # Neither does a line with nothing after the label, or only the template's placeholder.
  printf '%s\n' "$line" | grep -q -E ':\*\*[[:space:]]*(\[[^]]*\])?[[:space:]]*$' && return 0
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

# --- A look settled elsewhere that has not reached the story's table ---------
# Only the orchestrator is told, and only before a story is planned. A mockup,
# an annotate run or a dial settles how something looks; the story's binding
# table is how planning proves that look was carried over. Once a story has
# chunks the planner has already bound the look into them and the builder is
# handed the source before each chunk, so a planned story needs nothing said.
#
# A look is found two ways: the story's header names it, or a record says it
# graduated to this story. The second catches a link written from the record
# side only.

# story_keys - the names a record may use for this story: its name: field and
# its file name, each with and without the leading number.
story_keys() {
  local stem name
  stem=$(basename "$STORY" .md)
  name=$(field name)
  printf '%s\n%s\n%s\n' "$stem" "${stem#[0-9]*-}" "$name" | sed '/^$/d' | sort -u
}

# points_here <record file> - true when its graduated_to names this story.
# The value may be a bare name or a path; only its last part is compared, whole.
points_here() {
  local to key
  local keys
  keys=$(story_keys)
  # One destination per line: a value may list several, split by ; or ,
  # and each may carry a note in brackets.
  while IFS= read -r to; do
    to=$(printf '%s' "$to" | sed 's/[[:space:]]*(.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/\.md$//')
    to="${to%/}"; to="${to##*/}"
    [ -n "$to" ] || continue
    while IFS= read -r key; do
      [ "$to" = "$key" ] && return 0
    done <<EOF_KEYS
$keys
EOF_KEYS
  done <<EOF_TO
$(awk '/^graduated_to:/ { sub(/^graduated_to:[[:space:]]*/, ""); print; exit }' "$1" 2>/dev/null \
    | tr -d '\r"' | tr -d "'" | sed 's/[[:space:]]#.*$//' | sed 's/([^)]*)//g' | tr ';,' '\n\n')
EOF_TO
  return 1
}

settled_look_block() {
  if [ -z "$ROOT" ]; then
    if [ -n "$MOCKUP_RAW" ] || [ -n "$(field annotate)" ] || [ -n "$(field dial)" ]; then
      block_failed "the story's header names a settled look but the story is not under a .craft folder, so it cannot be looked up: $STORY_ABS"
    fi
    return 0
  fi
  # Planned or finished: nothing to say.
  grep -q -E '^### Chunk [0-9]' "$STORY" && return 0
  [ "$(field status)" = "complete" ] && return 0
  local counts
  counts=$(binding_counts)
  # A table whose every row is still TBD is as good as none.
  [ "${counts%% *}" -gt "${counts##* }" ] && return 0

  local rules name dir record sheet r d chose tokens lead said_lead=0
  tokens="$ROOT/.craft/design/tokens.yaml"
  lead="Offer this story no visual options and no creative exploration at any later step: its look is already settled."

  # -- mockup: the header names it, or a mockup record points here
  local mock_dirs=""
  if [ -n "$MOCKUP_RAW" ]; then
    mock_dirs=$(mockup_names | while IFS= read -r name; do printf '%s\n' "$ROOT/.craft/mockups/$name"; done)
  else
    mock_dirs=$(mockup_dirs_pointing_here)
  fi
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    open_block
    if [ ! -f "$dir/mockup.html" ]; then
      echo "This story was built from a mockup and has no binding table, and the mockup cannot be read:"
      echo "- MOCKUP FILE MISSING: $dir/mockup.html"
      echo "The table cannot be built without it. Say so to the user in one line and plan on. $lead"
      continue
    fi
    rules=$(part settled-look-story-rules.md "orchestrator, mockup")
    if [ -z "$rules" ]; then
      FAILED=1
      echo "STORY RULES UNAVAILABLE: this story was built from a mockup and has no binding table, but the rules for that could not be read from $REFS/settled-look-story-rules.md"
      continue
    fi
    echo "This story was built from a mockup and has no binding table. Follow the rules below. Facts checked first:"
    echo "- mockup file: $dir/mockup.html"
    if [ -f "$dir/record.md" ]; then
      echo "- mockup record: $dir/record.md"
      if ! awk '/^solidify_outcome:/ { sub(/^solidify_outcome:[[:space:]]*/, ""); if ($0 != "" && $0 !~ /^\[/) found = 1 } END { exit !found }' "$dir/record.md"; then
        echo "- tokens: the record shows no answer to the tokens question for this mockup"
      fi
    else
      echo "- mockup record: none beside the mockup"
    fi
    [ -n "$MOCKUP_RAW" ] || echo "- story header: has no mockup: line; the record named above points at this story"
    echo ""
    [ "$said_lead" -eq 1 ] || { echo "$lead"; echo ""; said_lead=1; }
    printf '%s\n' "$rules"
  done <<EOF_DIRS
$mock_dirs
EOF_DIRS

  # -- annotate: the header names it, or an annotate record points here
  local ann_dirs=""
  name=$(field annotate)
  name="${name%/}"; name="${name%/record.md}"; name="${name##*annotations/}"
  if [ -n "$name" ]; then
    ann_dirs="$ROOT/.craft/annotations/$name
"
  else
    for r in "$ROOT"/.craft/annotations/*/record.md; do
      [ -f "$r" ] && grep -q '^outcome: story' "$r" && points_here "$r" && ann_dirs="${ann_dirs}$(dirname "$r")
"
    done
  fi
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    record="$dir/record.md"; sheet="$dir/session.css"
    open_block
    if [ ! -f "$record" ] || [ ! -f "$sheet" ]; then
      echo "This story was built from an annotate run and has no binding table, and the run's files cannot be read:"
      [ -f "$record" ] || echo "- ANNOTATE RECORD MISSING: $record"
      [ -f "$sheet" ] || echo "- ANNOTATE SHEET MISSING: $sheet"
      echo "The table cannot be built without them. Say so to the user in one line and plan on. $lead"
      continue
    fi
    rules=$(part settled-look-story-rules.md "orchestrator, annotate")
    if [ -z "$rules" ]; then
      FAILED=1
      echo "STORY RULES UNAVAILABLE: this story was built from an annotate run and has no binding table, but the rules for that could not be read from $REFS/settled-look-story-rules.md"
      continue
    fi
    echo "This story was built from an annotate run and has no binding table. Follow the rules below. Facts checked first:"
    echo "- annotate record: $record"
    echo "- the changes the user saw on the page: $sheet"
    [ -n "$(field annotate)" ] || echo "- story header: has no annotate: line; the record named above points at this story"
    echo ""
    [ "$said_lead" -eq 1 ] || { echo "$lead"; echo ""; said_lead=1; }
    printf '%s\n' "$rules"
  done <<EOF_ANN
$ann_dirs
EOF_ANN

  # -- dial: the header names it, or a dial record that ended in a story points here
  local dials=""
  local dial_names
  dial_names=$(field dial)
  if [ -n "$dial_names" ]; then
    # One story can carry several dials, each naming its own record.
    for name in $dial_names; do
      name="${name%,}"; name="${name%.md}"; name="${name##*dials/}"
      [ -n "$name" ] || continue
      d="$ROOT/.craft/dials/$name.md"
      if [ ! -f "$d" ]; then
        dials="${dials}- DIAL RECORD MISSING: $d
"
      else
        chose=$(awk '/^chose:/ { sub(/^chose:[[:space:]]*/, ""); print; exit }' "$d" | tr -d '\r')
        dials="${dials}- dial record: $d (position chosen: ${chose:-not recorded})
"
      fi
    done
  else
    for d in "$ROOT"/.craft/dials/*.md; do
      [ -f "$d" ] || continue
      grep -q '^outcome: story' "$d" || continue
      points_here "$d" || continue
      chose=$(awk '/^chose:/ { sub(/^chose:[[:space:]]*/, ""); print; exit }' "$d" | tr -d '\r')
      dials="${dials}- dial record: $d (position chosen: ${chose:-not recorded})
"
    done
  fi
  if [ -n "$dials" ]; then
    open_block
    rules=$(part settled-look-story-rules.md "orchestrator, dial")
    if [ -z "$rules" ]; then
      FAILED=1
      echo "STORY RULES UNAVAILABLE: part of this story's look was settled on a dial and it has no binding table, but the rules for that could not be read from $REFS/settled-look-story-rules.md"
    else
      echo "Part of this story's look was settled on a dial and the story has no binding table. Follow the rules below. Facts checked first:"
      printf '%s' "$dials"
      echo ""
      [ "$said_lead" -eq 1 ] || { echo "$lead"; echo ""; said_lead=1; }
      printf '%s\n' "$rules"
    fi
  fi
}

# mockup_from_record - a story can be linked to its mockup from the record's
# side only: the record says it graduated to this story and the story's header
# names nothing. The planner and the builder then get what a named mockup gets.
# A record whose mockup file is gone is passed over, so a stale record can
# never stop the build of a story that does not name it.
MOCKUP_FROM_RECORD=0
mockup_from_record() {
  [ -z "$MOCKUP_RAW" ] || return 0
  [ -n "$ROOT" ] || return 0
  local dir names=""
  while IFS= read -r dir; do
    [ -n "$dir" ] && [ -f "$dir/mockup.html" ] && names="${names}$(basename "$dir") "
  done <<EOF_RECORDS
$(mockup_dirs_pointing_here)
EOF_RECORDS
  [ -n "$names" ] || return 0
  MOCKUP_RAW="${names% }"
  MOCKUP_FROM_RECORD=1
}

if [ "$ROLE" = "orchestrator" ]; then
  settled_look_block
else
  mockup_from_record
  mockup_block
  decisions_block
  citations_block
  motion_block
  empty_project_block
  ui_block
fi

exit "$FAILED"
