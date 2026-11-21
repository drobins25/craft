#!/bin/bash
# test-annotate-write.sh - The annotate scripts share one atomic write.
#
# Every annotate writer that must never show a reader a half-written file goes
# through write_atomic in hooks/scripts/annotate_write.py. This file proves there
# is one definition, that each former copy now calls it, that the helper keeps
# what every site did (mode, fsync, exclusive create, temp name and folder,
# cleanup on error), that each program finds it by its own directory, and that
# the external-page gate loads it only on the path that writes.
# Usage: bash tests/test-annotate-write.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

HELPER="$SCRIPTS_DIR/annotate_write.py"
GATE="$SCRIPTS_DIR/annotate-external-gate.sh"
REC="$SCRIPTS_DIR/annotate-record.sh"

TMP_ROOTS=()
cleanup() {
  local r
  for r in "${TMP_ROOTS[@]:-}"; do
    [ -n "$r" ] && rm -rf "$r"
  done
  return 0
}
trap cleanup EXIT

BASE="$(mktemp -d)"
TMP_ROOTS+=("$BASE")

# helper_py <python body> - runs the body with the helper loaded as annotate_write
helper_py() {
  python3 - "$SCRIPTS_DIR" "$BASE" "$1" <<'PYEOF'
import os, sys
sys.path.insert(0, sys.argv[1])
import annotate_write
del sys.path[0]
base = sys.argv[2]
exec(sys.argv[3])
PYEOF
}

# --- one definition --------------------------------------------------------
begin_test "the annotate scripts carry one temp-file write, in annotate_write.py"
SITES="$(cd "$SCRIPTS_DIR" && grep -n 'tempfile\.mkstemp' annotate-* annotate_write.py 2>/dev/null || true)"
assert_eq "one tempfile.mkstemp across the annotate scripts" "1" "$(printf '%s\n' "$SITES" | grep -c . || true)"
assert_contains "it is in annotate_write.py" "^annotate_write\.py:" "$SITES"
assert_eq "no annotate script replaces a temp of its own" "0" "$(cd "$SCRIPTS_DIR" && cat annotate-* | grep -c 'os\.replace(\|os\.link(' || true)"

begin_test "every former copy calls write_atomic"
# At least one real call per script (comment lines do not count). The count is not
# pinned: a new save is allowed, and a bare temp-and-rename is caught by the block above.
calls() { { grep 'annotate_write\.write_atomic(' "$SCRIPTS_DIR/$1" || true; } | { grep -v '^[[:space:]]*#' || true; } | grep -c . || true; }
calls_it() { if [ "$(calls "$1")" -ge 1 ]; then echo yes; else echo no; fi; }
assert_eq "annotate-run.sh calls it: write_text, begin, the sheet, the watch cursor" "yes" "$(calls_it annotate-run.sh)"
assert_eq "annotate-resolve.sh calls it: the resolutions cache" "yes" "$(calls_it annotate-resolve.sh)"
assert_eq "annotate-external-gate.sh calls it: the lift" "yes" "$(calls_it annotate-external-gate.sh)"
assert_eq "annotate-channel.py calls it: replace_json, the token and the port" "yes" "$(calls_it annotate-channel.py)"
assert_eq "annotate-record.sh calls it: the graduate rewrite" "yes" "$(calls_it annotate-record.sh)"

# --- what each site did, kept ---------------------------------------------
begin_test "a plain write: same folder, <name>.<random>.tmp, mode 600, no fsync, temp gone"
OUT="$(helper_py '
seen = {}
real_replace, real_fsync = os.replace, os.fsync
def spy_replace(src, dst):
    seen["tmp"] = src
    seen["tmp_mode"] = oct(os.stat(src).st_mode & 0o777)
    return real_replace(src, dst)
def spy_fsync(fd):
    seen["fsync"] = seen.get("fsync", 0) + 1
    return real_fsync(fd)
os.replace = spy_replace
os.fsync = spy_fsync
target = os.path.join(base, "plain", "current.json")
os.makedirs(os.path.dirname(target))
annotate_write.write_atomic(target, "{}\n")
print("dir", os.path.dirname(seen["tmp"]) == os.path.dirname(target))
print("name", os.path.basename(seen["tmp"]))
print("mode", oct(os.stat(target).st_mode & 0o777))
print("fsync", seen.get("fsync", 0))
print("text", repr(open(target).read()))
print("left", sorted(os.listdir(os.path.dirname(target))))
')"
assert_contains "the temp is in the target's folder" "^dir True$" "$OUT"
assert_contains "the temp is named <name>.<random>.tmp" '^name current\.json\.[A-Za-z0-9_]\{1,\}\.tmp$' "$OUT"
assert_contains "the file is mode 600" "^mode 0o600$" "$OUT"
assert_contains "no fsync" "^fsync 0$" "$OUT"
assert_contains "the text is written" "^text '{}\\\\n'$" "$OUT"
assert_contains "only the target is left" "^left \['current.json'\]$" "$OUT"

begin_test "mode= sets the file's bits before the text goes in (bake, strip, record.md)"
OUT="$(helper_py '
target = os.path.join(base, "page.html")
umask = os.umask(0o022)
annotate_write.write_atomic(target, "<p>x</p>", mode=0o666 & ~0o022)
os.umask(umask)
print("mode", oct(os.stat(target).st_mode & 0o777))
')"
assert_contains "the page gets a new file's mode" "^mode 0o644$" "$OUT"

begin_test "sync=True flushes and fsyncs the temp before it takes the path (replace_json)"
OUT="$(helper_py '
order = []
real_fsync, real_replace = os.fsync, os.replace
os.fsync = lambda fd: (order.append("fsync"), real_fsync(fd))[1]
os.replace = lambda a, b: (order.append("replace"), real_replace(a, b))[1]
annotate_write.write_atomic(os.path.join(base, "synced.json"), "[]", sync=True)
print("order", " ".join(order))
')"
assert_contains "fsync comes before the replace" "^order fsync replace$" "$OUT"

begin_test "exclusive=True creates once and never replaces (the session token)"
OUT="$(helper_py '
target = os.path.join(base, "tok", "token")
os.makedirs(os.path.dirname(target))
print("first", annotate_write.write_atomic(target, "aaaa\n", exclusive=True))
print("second", annotate_write.write_atomic(target, "bbbb\n", exclusive=True))
print("kept", repr(open(target).read()))
print("mode", oct(os.stat(target).st_mode & 0o777))
print("left", sorted(os.listdir(os.path.dirname(target))))
')"
assert_contains "the first create returns True" "^first True$" "$OUT"
assert_contains "a second create returns False" "^second False$" "$OUT"
assert_contains "the first token is kept" "^kept 'aaaa\\\\n'$" "$OUT"
assert_contains "the token is mode 600" "^mode 0o600$" "$OUT"
assert_contains "no temp is left either way" "^left \['token'\]$" "$OUT"

begin_test "an error mid-write removes the temp, leaves the target, and re-raises"
OUT="$(helper_py '
target = os.path.join(base, "err", "run.json")
os.makedirs(os.path.dirname(target))
open(target, "w").write("old\n")
real_fdopen = os.fdopen
class Boom:
    def __init__(self, handle): self.handle = handle
    def __enter__(self): self.handle.__enter__(); return self
    def __exit__(self, *exc): return self.handle.__exit__(*exc)
    def write(self, text): raise OSError("disk full")
os.fdopen = lambda *a, **k: Boom(real_fdopen(*a, **k))
try:
    annotate_write.write_atomic(target, "new\n")
    print("raised no")
except OSError as error:
    print("raised", error)
print("kept", repr(open(target).read()))
print("left", sorted(os.listdir(os.path.dirname(target))))
')"
assert_contains "the error reaches the caller" "^raised disk full$" "$OUT"
assert_contains "the target is untouched" "^kept 'old\\\\n'$" "$OUT"
assert_contains "the temp is removed" "^left \['run.json'\]$" "$OUT"

# --- found by its own directory --------------------------------------------
begin_test "a script finds the helper beside itself, never through the environment"
ROOT="$BASE/proj"
mkdir -p "$ROOT/.craft/annotations/rec-1" "$BASE/planted"
printf -- '---\nstatus: filed\ngraduated_to:\noutcome:\n---\nbody\n' > "$ROOT/.craft/annotations/rec-1/record.md"
printf 'raise SystemExit("a planted annotate_write was loaded")\n' > "$BASE/planted/annotate_write.py"
set +e
ERR="$(PYTHONPATH="$BASE/planted" CRAFT_ANNOTATE_SCRIPTS_DIR="$BASE/planted" CRAFT_PROJECT_ROOT="$ROOT" \
  bash "$REC" graduate --record rec-1 --to story-x 2>&1 >/dev/null)"
RC=$?
set -e
assert_exit_code "graduate exits 0 with a planted module on PYTHONPATH and in the variable" "0" "$RC"
assert_not_contains "the planted module never ran" "planted" "$ERR"
assert_file_contains "record.md is graduated" "^graduated_to: story-x$" "$ROOT/.craft/annotations/rec-1/record.md"

# --- the gate loads it only where it writes --------------------------------
# The test shell plays the conversation: the pointer is keyed by $$, an
# ancestor of every gate run. PYTHONPROFILEIMPORTTIME lists every module the
# gate's Python imports, on stderr.
export CRAFT_ANNOTATE_BOUNDARY_DIR="$BASE/boundary"
mkdir -p "$CRAFT_ANNOTATE_BOUNDARY_DIR" "$BASE/sessions/s1"
echo '{"since": "2026-01-01T00:00:00Z", "page": "https://example.test/"}' > "$BASE/sessions/s1/external.json"
imports() { # <mode> <hook json> - the gate's imported module names, one per line
  printf '%s' "$2" | PYTHONPROFILEIMPORTTIME=1 bash "$GATE" "$1" 2>&1 >/dev/null \
    | awk -F'|' '/^import time:/ {gsub(/^ +| +$/, "", $3); print $3}'
}
PRE='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"curl https://x.test"},"prompt_id":"p1"}'

begin_test "the gate's no-boundary path starts no Python and loads no helper"
rm -f "$CRAFT_ANNOTATE_BOUNDARY_DIR"/*
assert_eq "no module imported" "0" "$(imports pre-tool "$PRE" | grep -c . || true)"

begin_test "the gate's live-boundary deny path never imports the helper"
printf '{"sessions": ["%s"], "updated": %s}' "$BASE/sessions/s1" "$(date +%s)" > "$CRAFT_ANNOTATE_BOUNDARY_DIR/$$.json"
VERDICT="$(printf '%s' "$PRE" | bash "$GATE" pre-tool | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)"
assert_eq "the call is denied" "deny" "$VERDICT"
DENY_IMPORTS="$(imports pre-tool "$PRE")"
assert_contains "Python ran" "^json$" "$DENY_IMPORTS"
assert_eq "annotate_write is not imported" "0" "$(printf '%s\n' "$DENY_IMPORTS" | grep -c '^annotate_write$' || true)"
assert_eq "tempfile is not imported" "0" "$(printf '%s\n' "$DENY_IMPORTS" | grep -c '^tempfile$' || true)"

begin_test "a typed prompt's lift write imports the helper and writes the lift"
LIFT_IMPORTS="$(imports prompt '{"hook_event_name":"UserPromptSubmit","prompt":"yes go","prompt_id":"p9"}')"
assert_eq "annotate_write is imported" "1" "$(printf '%s\n' "$LIFT_IMPORTS" | grep -c '^annotate_write$' || true)"
assert_eq "the lift holds the prompt id" "p9" "$(cat "$CRAFT_ANNOTATE_BOUNDARY_DIR/$$.lift" 2>/dev/null || echo MISSING)"
assert_eq "no temp is left" "0" "$(ls "$CRAFT_ANNOTATE_BOUNDARY_DIR" | grep -c '\.tmp$' || true)"

finish_tests "test-annotate-write"
