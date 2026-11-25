#!/bin/bash
# test-session-end.sh - The SessionEnd hook removes only the ending session's
# gate file, quickly, and a session resumed afterwards gets its gate back.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"
source "$SCRIPT_DIR/fixtures/minimal.sh"

END="$SCRIPTS_DIR/session-end.sh"
GATE="$SCRIPTS_DIR/write-gate.sh"
HOOK="$SCRIPTS_DIR/check-write-permission.py"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"

# end_as <session id> <folder>: run the hook as the SessionEnd event would
end_as() {
  (cd "$2" && unset CRAFT_PROJECT_ROOT && printf '{"session_id":"%s","reason":"clear"}' "$1" | bash "$END")
}

gate_as() {
  local sid="$1" root="$2"
  shift 2
  (unset CRAFT_PROJECT_ROOT; CLAUDE_CODE_SESSION_ID="$sid" "$GATE" --root "$root" "$@")
}

hook_says() { # <session id> <project>
  local json out
  json="{\"session_id\":\"$1\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$2/src/app.ts\"},\"cwd\":\"$2\"}"
  out=$(cd "$2" && unset CRAFT_PROJECT_ROOT && python3 "$HOOK" <<< "$json" 2>/dev/null || true)
  case "$out" in *deny*) echo denied ;; *) echo allowed ;; esac
}

# A git monorepo: a top-level project plus three registered sub-projects
make_monorepo() {
  local top sub
  top=$(mktemp -d)
  top=$(cd "$top" && pwd -P)
  git -C "$top" init -q
  git -C "$top" config user.name "t"
  git -C "$top" config user.email "t@example.com"
  mkdir -p "$top/.craft/projects"
  printf 'ACTIVE_CYCLE=""\nCURRENT_STORY=""\n' > "$top/.craft/.global-state"
  for sub in a b c; do
    mkdir -p "$top/apps/$sub/.craft"
    printf 'ACTIVE_CYCLE=""\nCURRENT_STORY=""\n' > "$top/apps/$sub/.craft/.global-state"
    printf -- '---\nname: %s\npath: apps/%s\n---\n' "$sub" "$sub" > "$top/.craft/projects/$sub.md"
  done
  echo "$top"
}

echo "=== test-session-end.sh ==="
echo ""

begin_test "session-end removes the session's file, two lines included, and leaves B's file and .gitignore alone"
P=$(create_minimal_craft); P=$(cd "$P" && pwd -P)
mkdir -p "$P/.craft/.gate"
printf '*\n' > "$P/.craft/.gate/.gitignore"
printf '/x/story.md\nworkflow /w\n' > "$P/.craft/.gate/session-a"
printf 'docs\n' > "$P/.craft/.gate/session-b"
B_BEFORE=$(cat "$P/.craft/.gate/session-b")
OUT=$(end_as session-a "$P" 2>&1); RC=$?
assert_eq "exits 0" "0" "$RC"
assert_eq "prints nothing" "" "$OUT"
assert_file_not_exists "A's file is gone" "$P/.craft/.gate/session-a"
assert_eq "B's file is byte-identical" "$B_BEFORE" "$(cat "$P/.craft/.gate/session-b")"
assert_eq ".gitignore is byte-identical" "*" "$(cat "$P/.craft/.gate/.gitignore")"
rm -rf "$P"
echo ""

begin_test "an invalid, empty, numeric or missing session_id removes nothing, prints nothing, exits 0"
P=$(create_minimal_craft); P=$(cd "$P" && pwd -P)
mkdir -p "$P/.craft/.gate"
printf '*\n' > "$P/.craft/.gate/.gitignore"
printf 'docs\n' > "$P/.craft/.gate/session-a"
BEFORE=$(cd "$P/.craft" && ls -A . .gate | sort | tr '\n' ' ')
GS_BEFORE=$(cat "$P/.craft/.global-state")
for body in '{"session_id":"../.global-state"}' '{"session_id":".gitignore"}' '{"session_id":""}' '{"session_id":42}' '{}' '{"session_id":null}' '[1]' 'not json' ''; do
  OUT=$(cd "$P" && unset CRAFT_PROJECT_ROOT && printf '%s' "$body" | bash "$END" 2>&1); RC=$?
  assert_eq "exit 0 for [$body]" "0" "$RC"
  assert_eq "no output for [$body]" "" "$OUT"
done
assert_eq "no file changed" "$BEFORE" "$(cd "$P/.craft" && ls -A . .gate | sort | tr '\n' ' ')"
assert_eq ".global-state unchanged" "$GS_BEFORE" "$(cat "$P/.craft/.global-state")"
assert_eq "A's file still there" "docs" "$(cat "$P/.craft/.gate/session-a")"
rm -rf "$P"
echo ""

begin_test "no .craft/ and a never-inited bare .craft/ exit 0 and create nothing"
E=$(mktemp -d); E=$(cd "$E" && pwd -P)
end_as session-a "$E" >/dev/null 2>&1; RC=$?
assert_eq "no .craft/: exit 0" "0" "$RC"
assert_dir_not_exists "no .craft/ created" "$E/.craft"
mkdir -p "$E/.craft/mockups"
end_as session-a "$E" >/dev/null 2>&1; RC=$?
assert_eq "bare .craft/: exit 0" "0" "$RC"
assert_dir_not_exists "no .gate/ created" "$E/.craft/.gate"
assert_eq "bare .craft/ holds only mockups" "mockups" "$(ls -A "$E/.craft")"
rm -rf "$E"
echo ""

begin_test "monorepo: the session's file goes from the top level and every sub-project, nothing else"
M=$(make_monorepo)
for r in "$M" "$M/apps/a" "$M/apps/b" "$M/apps/c"; do
  mkdir -p "$r/.craft/.gate"
  printf 'docs\n' > "$r/.craft/.gate/session-a"
  printf 'docs\n' > "$r/.craft/.gate/session-b"
  printf '*\n' > "$r/.craft/.gate/.gitignore"
done
end_as session-a "$M" >/dev/null 2>&1; RC=$?
assert_eq "exit 0" "0" "$RC"
for r in "$M" "$M/apps/a" "$M/apps/b" "$M/apps/c"; do
  assert_file_not_exists "A removed in ${r#$M}" "$r/.craft/.gate/session-a"
  assert_eq "B kept in ${r#$M}" "docs" "$(cat "$r/.craft/.gate/session-b" 2>/dev/null)"
  assert_eq ".gitignore kept in ${r#$M}" "*" "$(cat "$r/.craft/.gate/.gitignore" 2>/dev/null)"
done
echo ""

begin_test "session-end finishes in under 1000 ms on the monorepo fixture"
for r in "$M" "$M/apps/a" "$M/apps/b" "$M/apps/c"; do printf 'docs\n' > "$r/.craft/.gate/session-a"; done
MS=$(python3 - "$END" "$M" <<'PY'
import subprocess, sys, time
end, cwd = sys.argv[1], sys.argv[2]
t = time.monotonic()
subprocess.run(["bash", end], input=b'{"session_id":"session-a"}', cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(int((time.monotonic() - t) * 1000))
PY
)
if [ "$MS" -lt 1000 ]; then echo "  PASS: took ${MS} ms"; PASS=$((PASS + 1)); else echo "  FAIL: took ${MS} ms"; FAIL=$((FAIL + 1)); fi
rm -rf "$M"
echo ""

begin_test "after session-end for A, the write hook denies A; a resumed A claims the story again, or is told another session holds it"
P=$(create_minimal_craft); P=$(cd "$P" && pwd -P)
mkdir -p "$P/.craft/stories"
printf -- '---\ntitle: "X"\n---\n' > "$P/stories-x.md"
STORY="$P/stories-x.md"
gate_as session-a "$P" open docs >/dev/null
assert_eq "A allowed while holding" "allowed" "$(hook_says session-a "$P")"
end_as session-a "$P"
assert_eq "A denied after session-end" "denied" "$(hook_says session-a "$P")"
OUT=$(gate_as session-a "$P" claim story "$STORY")
assert_eq "A's claim opens it again" "opened $STORY" "$OUT"
assert_eq "A allowed again" "allowed" "$(hook_says session-a "$P")"
end_as session-a "$P"
gate_as session-b "$P" open story "$STORY" >/dev/null
OUT=$(gate_as session-a "$P" claim story "$STORY")
assert_eq "A's claim says other" "other" "$OUT"
assert_file_not_exists "claim wrote nothing for A" "$P/.craft/.gate/session-a"
assert_eq "A stays denied" "denied" "$(hook_says session-a "$P")"
rm -rf "$P"
echo ""

begin_test "post-compact-reinject.sh and export-progress.sh leave every gate file byte-identical"
P=$(create_minimal_craft); P=$(cd "$P" && pwd -P)
gate_as session-a "$P" open reflect >/dev/null
gate_as session-b "$P" open docs >/dev/null
SNAP() { (cd "$P/.craft/.gate" && for f in $(ls -A); do echo "== $f"; cat "$f"; done); }
BEFORE=$(SNAP)
(cd "$P" && unset CRAFT_PROJECT_ROOT && bash "$SCRIPTS_DIR/post-compact-reinject.sh" >/dev/null 2>&1) || true
(cd "$P" && unset CRAFT_PROJECT_ROOT && echo '{"session_id":"session-a"}' | bash "$SCRIPTS_DIR/export-progress.sh" >/dev/null 2>&1) || true
assert_eq "gate folder unchanged" "$BEFORE" "$(SNAP)"
rm -rf "$P"
echo ""

begin_test "session-end.sh is executable; hooks.json has 8 events and one SessionEnd entry with timeout 2"
if [ -x "$END" ]; then echo "  PASS: executable"; PASS=$((PASS + 1)); else echo "  FAIL: not executable"; FAIL=$((FAIL + 1)); fi
assert_eq "8 events" "8" "$(jq '.hooks | length' "$HOOKS_JSON")"
assert_eq "one SessionEnd group" "1" "$(jq '.hooks.SessionEnd | length' "$HOOKS_JSON")"
assert_eq "one SessionEnd hook" "1" "$(jq '[.hooks.SessionEnd[].hooks[]] | length' "$HOOKS_JSON")"
assert_eq "it runs session-end.sh with timeout 2" "1" \
  "$(jq '[.hooks.SessionEnd[].hooks[] | select(.command == "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/session-end.sh" and .timeout == 2)] | length' "$HOOKS_JSON")"
assert_eq "no matcher" "0" "$(jq '[.hooks.SessionEnd[] | select(has("matcher"))] | length' "$HOOKS_JSON")"
echo ""

begin_test "two sessions on one story: A claims, B sees other, B opens, B then reads mine, A's close leaves B's file"
P=$(create_minimal_craft); P=$(cd "$P" && pwd -P)
printf -- '---\ntitle: "X"\n---\n' > "$P/story-x.md"
S="$P/story-x.md"
assert_eq "A claims" "opened $S" "$(gate_as session-a "$P" claim story "$S")"
assert_eq "B's claim prints other" "other" "$(gate_as session-b "$P" claim story "$S")"
gate_as session-b "$P" open story "$S" >/dev/null
assert_eq "A's file names X" "$S" "$(head -1 "$P/.craft/.gate/session-a")"
assert_eq "B's file names X" "$S" "$(head -1 "$P/.craft/.gate/session-b")"
A_BEFORE=$(cat "$P/.craft/.gate/session-a")
assert_eq "B's claim now prints mine" "mine" "$(gate_as session-b "$P" claim story "$S")"
assert_eq "A's file byte-identical" "$A_BEFORE" "$(cat "$P/.craft/.gate/session-a")"
gate_as session-a "$P" close story "$S" >/dev/null
assert_eq "B's file survives A's close" "$S" "$(cat "$P/.craft/.gate/session-b")"
rm -rf "$P"
echo ""

finish_tests
