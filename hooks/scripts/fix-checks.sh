#!/usr/bin/env bash
# fix-checks.sh - the checks an adhoc fix passes before it is committed.
#
# The adhoc fix hand-off runs these on a fix the smith agent reports. They read
# the fix record and the working tree; they never change either.
#
#   fix-checks.sh snapshot <project-root>
#       Run before the fix starts. Prints one snapshot id (a git tree hash of
#       the working tree as it is now: tracked and untracked files, ignored
#       files left out), so the user's own uncommitted work is not later taken
#       for the fix's.
#
#   fix-checks.sh changed <project-root> <snapshot-id>
#       Prints every path under <project-root> added, changed or deleted since
#       that snapshot, one per line, relative to <project-root>, leaving out
#       .craft/. Prints nothing when nothing changed.
#
#   fix-checks.sh run <project-root> <snapshot-id|-> <fix-record>
#       Prints one line per thing found, then a closing line:
#         1 undecided reader: <a Seen by others row whose verdict is changed
#                              and that carries no "decided:">
#         2 wrong hit outside Files: <file> in: <a Same construct elsewhere
#                             line that says wrong and names that file:line,
#                             which no Files line names>
#         2 wrong hit names no file:line: <such a line with no file:line in it>
#         3 undeclared path: <a path changed since the snapshot that is not on
#                             a Files line of the record>
#         4 status not validated: <the record's status, when it is anything
#                             but validated>
#         5 staged outside Files: <a path already in git's index that no Files
#                             line names; a commit would carry it along>
#         checks run: <N> found
#       Every numbered line above the closing line means the fix is not ready
#       to commit. A wrong hit whose file is on a Files line was cured by this
#       fix and prints nothing; so does one that carries a
#       "decided:" ruling. With "-" for the snapshot id, check 3 is skipped
#       and the first line, which is not numbered, says so and what to
#       compare by hand: "note: check 3 skipped, no snapshot; ...".
#
# A snapshot writes loose objects into the repository's object store, which git
# prunes on its own schedule. Nothing else is written.
#
# Exit 2 with a message on stderr for a bad call, a missing record, a folder
# outside a git repository, or a working tree git cannot read (a file without
# read permission). Exit 0 whenever the command ran, found or not.

set -euo pipefail

usage() {
  echo "usage: fix-checks.sh snapshot <project-root>" >&2
  echo "       fix-checks.sh changed <project-root> <snapshot-id>" >&2
  echo "       fix-checks.sh run <project-root> <snapshot-id> <fix-record>" >&2
  exit 2
}

CMD="${1:-}"
ROOT="${2:-}"
[ -n "$CMD" ] && [ -n "$ROOT" ] || usage
[ -d "$ROOT" ] || { echo "fix-checks: not a folder: $ROOT" >&2; exit 2; }

# A relative record path is read from where the caller stood, not from ROOT.
RECORD="${4:-}"
case "$RECORD" in
  ""|/*) ;;
  *) RECORD="$PWD/$RECORD" ;;
esac

ROOT_GIVEN="${ROOT%/}"
cd "$ROOT"
ROOT_REAL="$(pwd -P)"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "fix-checks: not inside a git repository: $ROOT" >&2; exit 2; }

# Writes the working tree under the current folder into a throwaway index and
# prints its tree hash. The real index is never touched.
snapshot_tree() {
  local idx
  idx="$(mktemp "${TMPDIR:-/tmp}/craft-fix-index.XXXXXX")"
  rm -f "$idx"
  # A repository with no commit yet has no HEAD to start from; the index then
  # starts empty and holds only what the working tree holds.
  GIT_INDEX_FILE="$idx" git read-tree HEAD 2>/dev/null || true
  # git's own message stays on stderr, so a file it cannot read is named.
  if ! GIT_INDEX_FILE="$idx" git add -A . >/dev/null; then
    rm -f "$idx"
    echo "fix-checks: could not read the working tree (git's message is above)" >&2
    return 2
  fi
  GIT_INDEX_FILE="$idx" git write-tree || { rm -f "$idx"; return 2; }
  rm -f "$idx"
}

need_snapshot() {
  git cat-file -e "${1}^{tree}" 2>/dev/null \
    || { echo "fix-checks: unknown snapshot id: $1" >&2; exit 2; }
}

# Paths are printed as written (git quotes nothing with -z), so they can be
# compared with the record's Files lines.
changed_paths() {
  local after
  after="$(snapshot_tree)" || return 2
  git diff -z --name-only --no-renames --relative \
    "$1" "$after" -- . ':(exclude).craft' | tr '\0' '\n' || return 2
}

# Prints the lines of one bold-labelled record field: the label's own line and
# what follows it, up to the next bold label or heading.
record_field() {
  awk -v label="$2" '
    index($0, "**" label ":**") == 1 { inside = 1; print; next }
    inside && (/^\*\*/ || /^## /)    { inside = 0 }
    inside                            { print }
  ' "$1"
}

case "$CMD" in
  snapshot)
    [ $# -eq 2 ] || usage
    snapshot_tree || exit 2
    ;;
  changed)
    [ $# -eq 3 ] || usage
    need_snapshot "$3"
    changed_paths "$3" || exit 2
    ;;
  run)
    [ $# -eq 4 ] || usage
    [ "$3" = "-" ] || need_snapshot "$3"
    [ -f "$RECORD" ] || { echo "fix-checks: no fix record at: $RECORD" >&2; exit 2; }
    # Read before any check prints, so a tree that cannot be read stops the
    # run instead of passing check 3 with nothing to compare. With "-" in
    # place of a snapshot id (the snapshot failed), check 3 is skipped and
    # says so, and checks 1 and 2 still run.
    if [ "$3" = "-" ]; then
      CHANGED=""
      echo "note: check 3 skipped, no snapshot; compare git status --porcelain with the Files lines by hand, and name any path that was changed before the fix as the user's"
    else
      CHANGED="$(changed_paths "$3")" || exit 2
    fi
    FOUND=0

    # 1. A reader row whose verdict is "changed" and that nobody decided. The
    #    verdict is the row's last word, or follows " - ", "->" or ": "; the
    #    word inside another word or a sentence ("unchanged", "0 changed
    #    lines") is not a verdict, and neither is a quoted output ("status:
    #    changed"). An indented line continues the row above it, so a decision
    #    written on the next line still counts, but a new bullet (indented or
    #    not) starts a new row. A row is split at each file:line it names, the
    #    way check 2 does, and each reader is judged on its own part, so one
    #    "decided:" does not clear its neighbours. A row naming no file:line is
    #    judged whole.
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      echo "1 undecided reader: $row"
      FOUND=$((FOUND + 1))
    done < <(record_field "$RECORD" "Seen by others" | awk '
      function verdict(s,  low) {
        low = tolower(s)
        gsub(/"[^"]*"/, "", low); gsub(/`[^`]*`/, "", low)
        if (low ~ /decided:/) return 0
        return (low ~ /( - |-> ?|: )changed([^a-z0-9]|$)/ || low ~ /(^|[^a-z0-9])changed[^a-z0-9]*$/)
      }
      function judge(r,  rest, off, n, i, starts, ends, seg) {
        if (r == "") return
        n = 0; rest = r; off = 0
        while (match(rest, /[][A-Za-z0-9_.\/@()+-]+\.[A-Za-z0-9]+:[0-9]/)) {
          n++
          starts[n] = off + RSTART
          ends[n] = off + RSTART + RLENGTH - 1
          off += RSTART + RLENGTH - 2
          rest = substr(rest, RSTART + RLENGTH - 1)
        }
        if (n == 0) { if (verdict(r)) print r; return }
        for (i = 1; i <= n; i++) {
          seg = (i < n) ? substr(r, starts[i], starts[i + 1] - starts[i]) : substr(r, starts[i])
          if (verdict(seg)) print substr(r, 1, starts[1] - 1) seg
        }
      }
      /^[ \t]*[-*+][ \t]/ { judge(row); row = $0; next }
      /^[ \t]/ && row != "" { row = row " " $0; next }
      { judge(row); row = $0 }
      END { judge(row) }
    ')

    # The Files text, for checks 2 and 3. A Files line may name a path as
    # absolute or with a leading "./"; both are read as the project-relative
    # path.
    FILES_TEXT="$(record_field "$RECORD" "Files" | awk -v a="$ROOT_GIVEN/" -v b="$ROOT_REAL/" '
      function strip(s, prefix,  at) {
        if (prefix == "/") return s
        while ((at = index(s, prefix)) > 0) s = substr(s, 1, at - 1) substr(s, at + length(prefix))
        return s
      }
      {
        # The longer prefix goes first: one can sit inside the other
        # ("/var/x/" inside "/private/var/x/").
        if (length(a) >= length(b)) line = strip(strip($0, a), b)
        else line = strip(strip($0, b), a)
        gsub(/(^|[^A-Za-z0-9_.\/-])\.\//, " ", line)
        print line
      }
    ')"

    # on_files <path> <whole|tail>: is <path> named on a Files line? It must
    # stand on its own: "a.py" is not found inside "data.py", and "b.txt" is
    # not found inside "b.txt.bak"; a full stop straight after it still counts,
    # as at the end of a sentence. With "tail", a bare or partial path counts
    # when a Files path ends with it ("tracker_issue.py" names
    # "hooks/scripts/tracker_issue.py"), because a hit is written as file:line.
    on_files() {
      printf '%s\n' "$FILES_TEXT" | P="$1" awk -v mode="$2" '
        BEGIN { p = ENVIRON["P"] }
        {
          line = $0
          while ((at = index(line, p)) > 0) {
            before = (at == 1) ? "" : substr(line, at - 1, 1)
            after = substr(line, at + length(p), 1)
            next_char = substr(line, at + length(p) + 1, 1)
            before_ok = (before !~ /[A-Za-z0-9_.\/-]/) || (mode == "tail" && before == "/")
            if (before_ok && after !~ /[A-Za-z0-9_\/-]/ \
                && !(after == "." && next_char ~ /[A-Za-z0-9_]/)) { hit = 1; exit }
            line = substr(line, at + 1)
          }
        }
        END { exit hit ? 0 : 1 }
      '
    }

    # 2. A Same construct elsewhere hit marked wrong whose file is not in the
    #    fix. A row (an indented line continues the row above it) that says
    #    wrong is split at each file:line it names; each hit runs from its
    #    file:line to the next one. Quoted and backticked text (run output) is
    #    not read, as in check 1. A hit is skipped when its own part says
    #    right and not wrong, or carries a "decided:" ruling. Every
    #    other hit's file is looked up on the Files lines. A wrong row that
    #    names no file:line cannot be checked, so it is reported too.
    while IFS="$(printf '\t')" read -r hit_file row; do
      [ -n "$row" ] || continue
      if [ "$hit_file" = "-" ]; then
        echo "2 wrong hit names no file:line: $row"
        FOUND=$((FOUND + 1))
      elif case "$hit_file" in /*) ! on_files "$hit_file" whole ;; *) ! on_files "$hit_file" tail ;; esac; then
        echo "2 wrong hit outside Files: $hit_file in: $row"
        FOUND=$((FOUND + 1))
      fi
    done < <(record_field "$RECORD" "Same construct elsewhere" \
      | A="$ROOT_GIVEN/" B="$ROOT_REAL/" awk '
      function word(s, w) { return s ~ ("(^|[^a-z0-9])" w "([^a-z0-9]|$)") }
      # Quoted and backticked text is run output, not the verdict.
      function unquote(s) { gsub(/"[^"]*"/, "", s); gsub(/`[^`]*`/, "", s); return s }
      function rel(p,  a, b) {
        a = ENVIRON["A"]; b = ENVIRON["B"]
        if (length(b) > length(a)) { t = a; a = b; b = t }
        if (index(p, a) == 1) p = substr(p, length(a) + 1)
        else if (index(p, b) == 1) p = substr(p, length(b) + 1)
        sub(/^\.\//, "", p)
        return p
      }
      function judge(r,  low, rest, n, i, starts, ends, toks, seg, tok) {
        if (r == "") return
        low = tolower(r)
        if (!word(unquote(low), "wrong")) return
        # every file:line in the row, with where it starts and ends
        n = 0; rest = r; off = 0
        while (match(rest, /[][A-Za-z0-9_.\/@()+-]+\.[A-Za-z0-9]+:[0-9]/)) {
          n++
          toks[n] = substr(rest, RSTART, RLENGTH - 2)
          starts[n] = off + RSTART
          ends[n] = off + RSTART + RLENGTH - 1
          off += RSTART + RLENGTH - 2
          rest = substr(rest, RSTART + RLENGTH - 1)
        }
        if (n == 0) { if (unquote(low) !~ /decided:/) print "-\t" r; return }
        for (i = 1; i <= n; i++) {
          seg = (i < n) ? substr(low, ends[i] + 1, starts[i + 1] - ends[i] - 1) : substr(low, ends[i] + 1)
          seg = unquote(seg)
          if (seg ~ /decided:/) continue
          if (word(seg, "right") && !word(seg, "wrong")) continue
          tok = rel(toks[i])
          if (!(tok in seen)) { seen[tok] = 1; print tok "\t" r }
        }
        delete seen
      }
      /^[ \t]/ && row != "" { row = row " " $0; next }
      { judge(row); row = $0 }
      END { judge(row) }
    ')

    # 3. A path changed since the snapshot that no Files line names.
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if ! on_files "$path" whole; then
        echo "3 undeclared path: $path"
        FOUND=$((FOUND + 1))
      fi
    done <<< "$CHANGED"

    # 4. The record's status. Only a validated fix is ready to commit.
    STATUS="$(awk '
      NR == 1 && $0 != "---" { exit }
      NR > 1 && $0 == "---"  { exit }
      /^status:/ { sub(/^status:[ \t]*/, ""); gsub(/["\047]/, ""); print; exit }
    ' "$RECORD")"
    if [ "$STATUS" != "validated" ]; then
      echo "4 status not validated: ${STATUS:-none}"
      FOUND=$((FOUND + 1))
    fi

    # 5. Paths already staged that no Files line names: the user's own staged
    #    work, which a plain commit would carry into the fix commit.
    #    An index git cannot read stops the run; it is not "nothing staged".
    STAGED="$(git diff --cached -z --name-only --no-renames --relative -- . ':(exclude).craft' | tr '\0' '\n')" \
      || { echo "fix-checks: could not read git's index (git's message is above)" >&2; exit 2; }
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if ! on_files "$path" whole; then
        echo "5 staged outside Files: $path"
        FOUND=$((FOUND + 1))
      fi
    done <<< "$STAGED"

    echo "checks run: $FOUND found"
    ;;
  *)
    usage
    ;;
esac
