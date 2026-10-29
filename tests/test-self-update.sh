#!/bin/bash
# test-self-update.sh - craft's SessionStart self-update hook.
# A fake `claude` on PATH records every call and answers from a script, so no
# network and no real plugin cache are touched. Guards, throttle, the update
# command, the notice, the log cap, and the hooks.json entry.
# Usage: bash tests/test-self-update.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

SU="$SCRIPTS_DIR/self-update.sh"

SU_TMP=()
su_cleanup() {
  local d
  for d in "${SU_TMP[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done
  return 0
}
trap su_cleanup EXIT

# su_env - a fresh fake world: a fake claude on PATH, a cache-shaped plugin
# root, an empty data dir. Sets BIN, CALLS, ROOT, DATA.
su_env() {
  BIN=$(mktemp -d); SU_TMP+=("$BIN")
  DATA=$(mktemp -d); SU_TMP+=("$DATA")
  CACHE=$(mktemp -d); SU_TMP+=("$CACHE")
  ROOT="$CACHE/plugins/cache/craft/craft/2.12.1"
  mkdir -p "$ROOT"
  CALLS="$BIN/calls"
  : > "$CALLS"
  # The fake claude: appends its arguments to CALLS, then prints what the
  # UPDATE_SAYS file tells it to.
  cat > "$BIN/claude" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$CALLS"
case "\$*" in
  "plugin update craft@craft")
    cat "$BIN/update_says" 2>/dev/null || echo "craft is already at the latest version (2.12.1)."; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$BIN/claude"
}

# run_entry [extra env...] - the hook entry, synchronous worker, clean env
run_entry() {
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$HOME" \
    CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_DATA="$DATA" CRAFT_SELF_UPDATE_SYNC=1 \
    "$@" bash "$SU" 2>/dev/null
}

calls() { cat "$CALLS" 2>/dev/null; }

# --- guards: each leaves no call, no stamp, no output -----------------------

begin_test "every off switch exits silently before any call"
for pair in "CRAFT_AUTO_UPDATE=0" "CRAFT_AUTO_UPDATE=false" "DISABLE_AUTOUPDATER=1" "DISABLE_UPDATES=true" "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1" "CRAFT_SELF_UPDATE_RUNNING=1"; do
  su_env
  OUT=$(run_entry "$pair")
  assert_eq "$pair: no output" "" "$OUT"
  assert_eq "$pair: no call" "" "$(calls)"
  assert_file_not_exists "$pair: no stamp" "$DATA/self-update.stamp"
done

begin_test "a no-auto-update file in the data dir turns it off"
su_env
: > "$DATA/no-auto-update"
OUT=$(run_entry)
assert_eq "no output" "" "$OUT"
assert_eq "no call" "" "$(calls)"

begin_test "a plugin root outside the craft marketplace cache is left alone"
su_env
for r in "$CACHE/dev/craft" "$CACHE/plugins/cache/other/craft/1.0.0" "$CACHE/plugins/synced/craft"; do
  OUT=$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$HOME" CLAUDE_PLUGIN_ROOT="$r" CLAUDE_PLUGIN_DATA="$DATA" CRAFT_SELF_UPDATE_SYNC=1 bash "$SU" 2>/dev/null)
  assert_eq "$(basename "$r"): no output" "" "$OUT"
done
assert_eq "no call for any of them" "" "$(calls)"

begin_test "no claude on PATH means no attempt"
su_env
OUT=$(env -i PATH="/usr/bin:/bin" HOME="$HOME" CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_DATA="$DATA" CRAFT_SELF_UPDATE_SYNC=1 bash "$SU" 2>/dev/null)
assert_eq "no output" "" "$OUT"
assert_file_not_exists "no stamp" "$DATA/self-update.stamp"

begin_test "no data dir means no attempt"
su_env
OUT=$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$HOME" CLAUDE_PLUGIN_ROOT="$ROOT" CRAFT_SELF_UPDATE_SYNC=1 bash "$SU" 2>/dev/null)
assert_eq "no output" "" "$OUT"
assert_eq "no call" "" "$(calls)"

# --- first run ----------------------------------------------------------------

begin_test "first run discloses once, then runs the update command"
su_env
OUT=$(run_entry)
assert_contains_literal "one JSON line with the disclosure" '{"systemMessage": "craft checks for its own update once a day' "$OUT"
assert_eq "exactly one line of output" "1" "$(printf '%s\n' "$OUT" | grep -c .)"
assert_eq "exactly one call: plugin update" "plugin update craft@craft" "$(calls)"
assert_file_exists "stamp written" "$DATA/self-update.stamp"
assert_file_exists "disclosed marker written" "$DATA/self-update.disclosed"
assert_file_not_exists "no notice when already at the latest" "$DATA/self-update.notice"
assert_contains_literal "log has the result" "plugin update rc=0: craft is already at the latest version (2.12.1)." "$(cat "$DATA/self-update.log")"

begin_test "a second run inside the interval makes no call and says nothing"
OUT=$(run_entry)
assert_eq "no output" "" "$OUT"
assert_eq "still only the first call" "1" "$(calls | wc -l | tr -d ' ')"

# --- an update lands ----------------------------------------------------------

begin_test "an update leaves a notice that the next session shows once"
su_env
: > "$DATA/self-update.disclosed"
echo "Successfully updated plugin: craft@craft" > "$BIN/update_says"
OUT=$(run_entry CRAFT_SELF_UPDATE_INTERVAL=0)
assert_eq "the run that updates says nothing itself" "" "$OUT"
assert_file_exists "notice written" "$DATA/self-update.notice"
rm -f "$BIN/update_says"
OUT=$(run_entry CRAFT_SELF_UPDATE_INTERVAL=0)
assert_contains_literal "next session shows the notice" '{"systemMessage": "craft updated itself; the new version loads in your next session."}' "$OUT"
assert_file_not_exists "notice consumed" "$DATA/self-update.notice"
OUT=$(run_entry CRAFT_SELF_UPDATE_INTERVAL=0)
assert_eq "and not again" "" "$OUT"

begin_test "the log never grows past 50 lines"
su_env
: > "$DATA/self-update.disclosed"
i=0
while [ "$i" -lt 60 ]; do printf 'old line %s\n' "$i" >> "$DATA/self-update.log"; i=$((i + 1)); done
run_entry >/dev/null
assert_eq "capped" "50" "$(wc -l < "$DATA/self-update.log" | tr -d ' ')"

# --- wiring -------------------------------------------------------------------

begin_test "hooks.json runs the script on session startup only"
HOOKS="$PLUGIN_ROOT/hooks/hooks.json"
ENTRY=$(python3 -c "
import json,sys
h=json.load(open(sys.argv[1]))['hooks']['SessionStart']
for e in h:
    for k in e.get('hooks',[]):
        if 'self-update.sh' in k.get('command',''):
            print(e.get('matcher',''), k.get('timeout',''))
" "$HOOKS")
assert_eq "matcher startup, 10s timeout" "startup 10" "$ENTRY"
assert_eq "script is executable" "yes" "$([ -x "$SU" ] && echo yes || echo no)"

begin_test "the README says what runs, when, and how to turn it off"
README="$PLUGIN_ROOT/README.md"
assert_file_contains "names the daily check" "Once a day" "$README"
assert_file_contains "names the off switch" "CRAFT_AUTO_UPDATE=0" "$README"
assert_file_contains "names what is fetched" "claude plugin update craft@craft" "$README"

finish_tests
