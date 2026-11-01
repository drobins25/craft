#!/bin/bash
# cycle-stage.sh - Say whether a cycle may be implemented, from its recorded stage
# Usage: cycle-stage.sh <cycle-dir>
#
# Output (exit 0), exactly four lines:
#   implement=<yes|no>
#   stage=<authorized_stage, or empty>
#   source_issue=<source_issue, or empty>
#   say=<one line to show the user when implement=no, else empty>
#
# A cycle with no source_issue is not tracker-sourced and may be implemented.
# So may a cycle with a source_issue and no authorized_stage key at all: the
# issue had no Go, so nothing limits it. Build stages may be implemented. Plan,
# hold and any present but empty or unknown stage stop, because a stage that
# cannot be read must never widen what is allowed.
# Read-only. A cycle dir without cycle.yaml prints one line on stderr, exit 1.

set -e

CYCLE_DIR="${1:-}"
YAML="$CYCLE_DIR/cycle.yaml"

if [ -z "$CYCLE_DIR" ] || [ ! -f "$YAML" ]; then
  echo "cycle-stage.sh: no cycle.yaml in '${CYCLE_DIR}'" >&2
  exit 1
fi

# Value of a flat top-level key written as a one-line single-quoted scalar.
read_key() {
  grep -m1 "^$1:" "$YAML" 2>/dev/null \
    | sed -e "s/^$1:[[:space:]]*//" -e "s/[[:space:]]*\$//" \
          -e "s/^'\(.*\)'\$/\1/" -e "s/''/'/g" || true
}

KEY=$(read_key source_issue)
STAGE=$(read_key authorized_stage)
AUTHOR=$(read_key go_author)

IMPLEMENT=yes
SAY=""

# A recorded stage key, even an empty one, is a limit; only its absence is not.
if [ -n "$KEY" ] && grep -q "^authorized_stage:" "$YAML"; then
  case "$STAGE" in
    build|"build and open the PR") ;;
    plan)
      IMPLEMENT=no
      if [ -n "$AUTHOR" ]; then
        SAY="Stage for $KEY is plan, per the Go from $AUTHOR, so I stop before implementing. Building needs a newer Go on $KEY that says build."
      else
        SAY="Stage for $KEY is plan because no readable Go is on record for it, so I stop before implementing. Building needs a Go on $KEY that says build."
      fi
      ;;
    hold)
      IMPLEMENT=no
      if [ -n "$AUTHOR" ]; then
        SAY="$KEY is on hold, per the Go from $AUTHOR, so I'm not starting anything new."
      else
        SAY="$KEY is on hold, per its newest Go, so I'm not starting anything new."
      fi
      ;;
    *)
      IMPLEMENT=no
      SAY="This cycle names $KEY but records no stage I know, so I stop before implementing."
      ;;
  esac
fi

printf 'implement=%s\nstage=%s\nsource_issue=%s\nsay=%s\n' "$IMPLEMENT" "$STAGE" "$KEY" "$SAY"
