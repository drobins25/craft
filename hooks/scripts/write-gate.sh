#!/bin/bash
# write-gate.sh - Open, close and report one session's write gate.
#
# Usage: write-gate.sh [--root <dir>] <verb> [args]
#   open <holder>              take or keep the gate for a holder
#   open story|workflow <p> --take-over
#                              the same, then remove that holder from every other
#                              session's file (a takeover)
#   close <holder>             give up that holder (a replaced holder gets the gate back)
#   claim story|workflow <p>   mine / other, or open it when no session names it
#   check story|workflow <p>   mine / other / free, writes nothing
#   holder                     print this session's line 1
#   preflight                  fail like open would, write nothing
# Holders: story <file>, workflow <folder>, adhoc [<record>], or one of
#   reflect rule-pass become research docs approve
#
# The gate is the file <root>/.craft/.gate/<CLAUDE_CODE_SESSION_ID>. Line 1 names
# the holder; line 2 exists only under a story and keeps the holder the story
# replaced, so that holder holds the gate again the moment the story closes.
#
# Pure bash with a short tool list (dirname basename mkdir printf rm mv cat grep
# sed head tr mktemp): it runs under start-story.sh's stripped PATH, with no
# python3 and, when --root is given, no git.

NAMES="reflect rule-pass become research docs approve"
NOT_OPENED="CLAUDE_CODE_SESSION_ID is empty or not a session id - the gate was not opened"

fail() {
  printf 'write-gate: %s\n' "$1" >&2
  exit 1
}

# An id names a file, so it may hold only these characters (same rule as
# annotate-run.sh) and never reaches a path through "/" or "..".
valid_id() {
  case "${1:-}" in
    ''|*[!A-Za-z0-9_-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

is_name() {
  case " $NAMES " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

is_blank() {
  case "$1" in
    *[![:space:]]*) return 1 ;;
  esac
  return 0
}

# --- Arguments -------------------------------------------------------------

ROOT_ARG=""
if [ "${1:-}" = "--root" ]; then
  [ $# -ge 2 ] || fail "--root needs a folder"
  ROOT_ARG="$2"
  shift 2
fi

VERB="${1:-}"
[ $# -gt 0 ] && shift

# Holder parsing, checked before the root so a typo fails everywhere alike.
H_KIND=""   # story | workflow | adhoc | name
H_NAME=""
H_ARG=""

parse_holder() { # <allow-adhoc-record yes|no> <args...>
  local rec="$1"
  shift
  [ $# -ge 1 ] || fail "missing holder"
  case "$1" in
    story|workflow)
      [ $# -eq 2 ] && [ -n "$2" ] || fail "$1 needs exactly one path"
      H_KIND="$1"; H_ARG="$2"
      ;;
    adhoc)
      if [ "$rec" = "yes" ]; then
        [ $# -le 2 ] || fail "adhoc takes at most one record path"
        H_ARG="${2:-}"
      else
        [ $# -eq 1 ] || fail "close adhoc takes no path"
      fi
      H_KIND="adhoc"
      ;;
    *)
      is_name "$1" || fail "unknown holder: $1"
      [ $# -eq 1 ] || fail "$1 takes no argument"
      H_KIND="name"; H_NAME="$1"
      ;;
  esac
}

# A trailing --take-over on open story|workflow is a takeover:
# once this session names the holder, other sessions' lines naming it are removed.
TAKE=""
if [ "$VERB" = "open" ] && [ $# -ge 1 ] && [ "${!#}" = "--take-over" ]; then
  TAKE=1
  set -- "${@:1:$(($# - 1))}"
fi

case "$VERB" in
  open)
    parse_holder yes "$@"
    if [ -n "$TAKE" ] && [ "$H_KIND" != "story" ] && [ "$H_KIND" != "workflow" ]; then
      fail "--take-over goes with story or workflow"
    fi
    ;;
  close) parse_holder no "$@" ;;
  claim|check)
    case "${1:-}" in
      story|workflow) ;;
      *) fail "$VERB takes story or workflow" ;;
    esac
    parse_holder no "$@"
    ;;
  holder|preflight)
    [ $# -eq 0 ] || fail "$VERB takes no argument"
    ;;
  *) fail "unknown verb: ${VERB:-<none>}" ;;
esac

# --- Root ------------------------------------------------------------------

ROOT=""
if [ -n "$ROOT_ARG" ]; then
  ROOT="$ROOT_ARG"
else
  WG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  unset PROJECT_ROOT
  if . "$WG_DIR/find-workshop.sh" 2>/dev/null; then
    ROOT="${PROJECT_ROOT:-}"
  fi
fi
while [ "${#ROOT}" -gt 1 ] && [ "${ROOT%/}" != "$ROOT" ]; do ROOT="${ROOT%/}"; done
if [ -n "$ROOT" ] && [ -d "$ROOT" ]; then
  ROOT="$(cd "$ROOT" && pwd -P)"
fi

# A folder holding neither .global-state nor project.md never ran init; gating
# it would arm a project that was never set up.
if [ -z "$ROOT" ] || { [ ! -f "$ROOT/.craft/.global-state" ] && [ ! -f "$ROOT/.craft/project.md" ]; }; then
  case "$VERB" in
    check) echo "free" ;;
    holder) ;;
    *) echo "skipped" ;;
  esac
  exit 0
fi

# --- Session id ------------------------------------------------------------

SID="${CLAUDE_CODE_SESSION_ID:-}"
if ! valid_id "$SID"; then
  case "$VERB" in
    close)
      printf 'write-gate: CLAUDE_CODE_SESSION_ID is empty or not a session id - nothing closed\n' >&2
      exit 0
      ;;
    open|claim|preflight) fail "$NOT_OPENED" ;;
    *) fail "CLAUDE_CODE_SESSION_ID is empty or not a session id" ;;
  esac
fi

GATE_DIR="$ROOT/.craft/.gate"
GATE_FILE="$GATE_DIR/$SID"

# --- Paths -----------------------------------------------------------------

check_path() {
  case "$1" in
    *$'\n'*|*$'\r'*) fail "a path holding a line break cannot go in a gate file" ;;
  esac
}

# Absolute, folder symlinks resolved, no trailing slash. Relative paths resolve
# against the project root, never the cwd.
canon_file() {
  local p="$1" d b rd
  check_path "$p"
  case "$p" in
    /*) ;;
    *) p="$ROOT/$p" ;;
  esac
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  d="$(dirname "$p")"
  b="$(basename "$p")"
  if rd="$(cd "$d" 2>/dev/null && pwd -P)"; then
    if [ "$rd" = "/" ]; then
      printf '/%s\n' "$b"
    else
      printf '%s/%s\n' "$rd" "$b"
    fi
  else
    printf '%s\n' "$p"
  fi
}

canon_dir() {
  local p="$1" rd
  check_path "$p"
  case "$p" in
    /*) ;;
    *) p="$ROOT/$p" ;;
  esac
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  if [ -d "$p" ] && rd="$(cd "$p" 2>/dev/null && pwd -P)"; then
    printf '%s\n' "$rd"
  else
    canon_file "$p"
  fi
}

# H_LINE is the text the holder writes on a gate line.
H_LINE=""
build_line() {
  case "$H_KIND" in
    story) H_LINE="$(canon_file "$H_ARG")" || exit 1 ;;
    workflow) H_LINE="workflow $(canon_dir "$H_ARG")" || exit 1 ;;
    adhoc)
      if [ -n "$H_ARG" ]; then
        H_LINE="adhoc $(canon_file "$H_ARG")" || exit 1
      else
        H_LINE="adhoc"
      fi
      ;;
    name) H_LINE="$H_NAME" ;;
  esac
}

# --- Gate file -------------------------------------------------------------

# kind_of <line>: blank | story | workflow | adhoc | <name> | unknown
kind_of() {
  local l="$1"
  if is_blank "$l"; then echo blank; return; fi
  case "$l" in
    /*) echo story ;;
    "workflow "*) echo workflow ;;
    adhoc|"adhoc "*) echo adhoc ;;
    *) if is_name "$l"; then echo "$l"; else echo unknown; fi ;;
  esac
}

rank_of() {
  case "$(kind_of "$1")" in
    story) echo 3 ;;
    workflow) echo 2 ;;
    adhoc|reflect|rule-pass|become|research|docs|approve) echo 1 ;;
    *) echo 0 ;;
  esac
}

# read_gate <file>: sets G1 and G2, or fails when the file cannot be read.
G1=""
G2=""
read_gate() {
  G1=""
  G2=""
  [ -e "$1" ] || return 0
  [ -f "$1" ] && [ -r "$1" ] || fail "cannot read the gate file $1"
  { IFS= read -r G1; IFS= read -r G2; } < "$1"
  return 0
}

# Does this gate line name the given holder?
names_holder() { # <line>
  case "$H_KIND" in
    adhoc) [ "$(kind_of "$1")" = "adhoc" ] ;;
    name) [ "$1" = "$H_NAME" ] ;;
    *) [ "$1" = "$H_LINE" ] ;;
  esac
}

same_kind() { # <line> <new line>
  [ "$(kind_of "$1")" = "$(kind_of "$2")" ]
}

ensure_gate_dir() {
  if [ -e "$GATE_DIR" ] && [ ! -d "$GATE_DIR" ]; then
    fail "$GATE_DIR is not a folder"
  fi
  if [ ! -d "$GATE_DIR" ]; then
    mkdir -p "$GATE_DIR" 2>/dev/null || fail "cannot create $GATE_DIR"
    # Only the run that creates the folder seeds the ignore file, so deleting it
    # later is a lasting choice.
    if [ ! -e "$GATE_DIR/.gitignore" ]; then
      printf '*\n' > "$GATE_DIR/.gitignore" 2>/dev/null || true
    fi
  fi
}

# write_gate <line1> [line2]: complete temp file, then one rename over the gate
# file, so a reader never sees it half-written or missing.
write_gate() {
  local tmp
  ensure_gate_dir
  tmp="$(mktemp "$GATE_DIR/.tmp.XXXXXX" 2>/dev/null)" || fail "cannot write in $GATE_DIR"
  if ! { printf '%s\n' "$1" > "$tmp" && { [ -z "${2:-}" ] || printf '%s\n' "$2" >> "$tmp"; }; }; then
    rm -f "$tmp"
    fail "cannot write in $GATE_DIR"
  fi
  if ! mv -f "$tmp" "$GATE_FILE" 2>/dev/null; then
    rm -f "$tmp"
    fail "cannot write $GATE_FILE"
  fi
}

# Does a gate line of any session other than this one name H_LINE?
other_names() { # <line>
  local f name l1 l2
  for f in "$GATE_DIR"/*; do
    [ -f "$f" ] && [ -r "$f" ] || continue
    name="${f##*/}"
    valid_id "$name" || continue
    [ "$name" = "$SID" ] && continue
    l1=""; l2=""
    { IFS= read -r l1; IFS= read -r l2; } < "$f"
    if [ "$l1" = "$1" ] || [ "$l2" = "$1" ]; then
      return 0
    fi
  done
  return 1
}

# drop_from_others <line>: the takeover. Removes the line from every other
# session's gate file; a file left with one line keeps it, a file left with none
# is deleted. This is the only place one session edits another's file.
drop_from_others() {
  local f name l1 l2 keep tmp
  for f in "$GATE_DIR"/*; do
    [ -f "$f" ] && [ -r "$f" ] || continue
    name="${f##*/}"
    valid_id "$name" || continue
    [ "$name" = "$SID" ] && continue
    l1=""; l2=""
    { IFS= read -r l1; IFS= read -r l2; } < "$f"
    if [ "$l1" = "$1" ]; then
      keep="$l2"
    elif [ "$l2" = "$1" ]; then
      keep="$l1"
    else
      continue
    fi
    if is_blank "$keep"; then
      rm -f "$f"
    else
      tmp="$(mktemp "$GATE_DIR/.tmp.XXXXXX" 2>/dev/null)" || fail "cannot write in $GATE_DIR"
      if ! printf '%s\n' "$keep" > "$tmp" || ! mv -f "$tmp" "$f" 2>/dev/null; then
        rm -f "$tmp"
        fail "cannot write $f"
      fi
    fi
  done
}

# --- Verbs -----------------------------------------------------------------

do_open() {
  local new="$H_LINE" k1 r_new r_old
  if [ "$H_KIND" = "story" ] && [ ! -f "$new" ]; then
    fail "story file not found: $new"
  fi
  read_gate "$GATE_FILE"

  if [ ! -e "$GATE_FILE" ] || is_blank "$G1"; then
    write_gate "$new"
    echo "opened $new"
    return
  fi

  k1="$(kind_of "$G1")"
  if [ "$H_KIND" = "story" ]; then
    if [ "$k1" = "story" ]; then
      write_gate "$new" "$(is_blank "$G2" || printf '%s' "$G2")"
    else
      write_gate "$new" "$G1"
    fi
    echo "opened $new"
    return
  fi

  if [ "$k1" = "story" ]; then
    if [ -n "$G2" ] && ! is_blank "$G2" && same_kind "$G2" "$new" && [ "$G2" != "$new" ]; then
      write_gate "$G1" "$new"
    fi
    echo "held $G1"
    return
  fi

  r_new="$(rank_of "$new")"
  r_old="$(rank_of "$G1")"
  if same_kind "$G1" "$new" || [ "$r_new" -gt "$r_old" ]; then
    write_gate "$new"
    echo "opened $new"
  else
    echo "held $G1"
  fi
}

do_close() {
  read_gate "$GATE_FILE"
  if [ ! -e "$GATE_FILE" ]; then
    echo "not open"
    return
  fi
  if is_blank "$G1"; then
    rm -f "$GATE_FILE"
    echo "closed"
    return
  fi
  if names_holder "$G1"; then
    if is_blank "$G2"; then
      rm -f "$GATE_FILE"
      echo "closed"
    else
      write_gate "$G2"
      echo "restored $G2"
    fi
    return
  fi
  if ! is_blank "$G2" && names_holder "$G2"; then
    write_gate "$G1"
    echo "closed"
    return
  fi
  echo "held $G1"
}

# answer_for <line>: mine | other | free, writing nothing.
answer_for() {
  read_gate "$GATE_FILE"
  if [ "$G1" = "$1" ] || [ "$G2" = "$1" ]; then
    echo mine
  elif other_names "$1"; then
    echo other
  else
    echo free
  fi
}

do_preflight() {
  read_gate "$GATE_FILE"
  if [ -e "$GATE_DIR" ] && [ ! -d "$GATE_DIR" ]; then
    fail "$GATE_DIR is not a folder"
  fi
  if [ -d "$GATE_DIR" ]; then
    [ -w "$GATE_DIR" ] || fail "cannot write in $GATE_DIR - the gate was not opened"
  else
    [ -w "$ROOT/.craft" ] || fail "cannot create $GATE_DIR - the gate was not opened"
  fi
}

case "$VERB" in
  open)
    build_line
    do_open
    if [ -n "$TAKE" ]; then
      read_gate "$GATE_FILE"
      if [ "$G1" = "$H_LINE" ] || [ "$G2" = "$H_LINE" ]; then
        drop_from_others "$H_LINE"
      fi
    fi
    ;;
  close)
    build_line
    do_close
    ;;
  claim)
    build_line
    ans="$(answer_for "$H_LINE")" || exit 1
    case "$ans" in
      free) do_open ;;
      *) echo "$ans" ;;
    esac
    ;;
  check)
    build_line
    answer_for "$H_LINE"
    ;;
  holder)
    read_gate "$GATE_FILE"
    is_blank "$G1" || printf '%s\n' "$G1"
    ;;
  preflight)
    do_preflight
    ;;
esac
exit 0
