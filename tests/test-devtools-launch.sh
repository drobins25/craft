#!/bin/bash
# test-devtools-launch.sh - Launcher core: lock decision, pinned argv, marker, status/notice verbs.
#
# Runs without Chrome. Every path the launcher touches is redirected into a
# test-owned temp dir through its env overrides, so the real ~/.cache is never read or written.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCH="$REPO/hooks/scripts/devtools-launch.cjs"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Expected: $2"; [ -n "${3:-}" ] && echo "    Got:      $3"; return 0; }
expect_eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "$3" "$2"; fi; }

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not found, launcher tests need it"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Nothing below may reach the real home cache.
export CRAFT_DEVTOOLS_STATE_DIR="$TMP/state"
export TMPDIR="$TMP/tmp"
mkdir -p "$TMPDIR" "$CRAFT_DEVTOOLS_STATE_DIR"
unset CLAUDE_PID CRAFT_DEVTOOLS_KEY CRAFT_DEVTOOLS_PROFILE_DIR

HOST="$(node -p 'require("os").hostname()')"

# lock_json <js-options-expression> -> JSON of lockState(opts)
lock_json() {
  node -e "const m=require('$LAUNCH'); process.stdout.write(JSON.stringify(m.lockState($1)))"
}
held_of() { node -e "process.stdout.write(String(JSON.parse(process.argv[1]).held))" "$1"; }

echo "devtools launcher core"

# --- FIRST: the Windows sharing-violation condition, on an injected probe ---
OUT="$(lock_json "{platform:'win32',profileDir:'/x',probe:{openForWrite(){throw Object.assign(new Error('busy'),{code:'EBUSY'})}}}")"
expect_eq "win32: lockfile held open for write reads held" "$(held_of "$OUT")" "true"

for code in ENOENT EPERM EACCES; do
  OUT="$(lock_json "{platform:'win32',profileDir:'/x',probe:{openForWrite(){throw Object.assign(new Error('x'),{code:'$code'})}}}")"
  expect_eq "win32: $code reads free" "$(held_of "$OUT")" "false"
done
OUT="$(lock_json "{platform:'win32',profileDir:'/x',probe:{openForWrite(){}}}")"
expect_eq "win32: successful open reads free" "$(held_of "$OUT")" "false"
OUT="$(lock_json "{platform:'win32',profileDir:'/x',probe:{openForWrite(){throw null}}}")"
expect_eq "win32: a non-error throw reads free" "$(held_of "$OUT")" "false"

# --- POSIX rule against real symlink fixtures ---
PROF="$TMP/profile"; mkdir -p "$PROF"
lock_with() { rm -f "$PROF/SingletonLock"; ln -s "$1" "$PROF/SingletonLock"; }
posix() { lock_json "{platform:'linux',profileDir:'$PROF'}"; }

lock_with "$HOST-$$"
expect_eq "posix: live same-host lock reads held" "$(held_of "$(posix)")" "true"

sleep 0 & DEAD=$!; wait "$DEAD" 2>/dev/null || true
lock_with "$HOST-$DEAD"
expect_eq "posix: dead pid reads free" "$(held_of "$(posix)")" "false"

lock_with "some-other-host-$$"
expect_eq "posix: foreign host reads free" "$(held_of "$(posix)")" "false"

lock_with "no-pid-here"
expect_eq "posix: garbage target reads free" "$(held_of "$(posix)")" "false"
rm -f "$PROF/SingletonLock"
expect_eq "posix: no lock reads free" "$(held_of "$(posix)")" "false"

OUT="$(lock_json "{platform:'linux',profileDir:'$TMP/no-such-dir'}")"
expect_eq "posix: no profile dir reads free" "$(held_of "$OUT")" "false"

# Hostnames with dashes split at the last dash
OUT="$(lock_json "{platform:'linux',profileDir:'/x',hostname:'my-dashed-host',probe:{readlink(){return 'my-dashed-host-$$'},isAlive(){return true},openForWrite(){}}}")"
expect_eq "posix: dashed hostname splits at the last dash" "$(held_of "$OUT")" "true"

# EPERM from kill(pid,0) means the process exists
OUT="$(lock_json "{platform:'linux',profileDir:'/x',hostname:'h',probe:{readlink(){return 'h-1234'}}}")"
expect_eq "posix: default liveness probe never throws (pid 1234 answer is valid either way)" "$(node -e "process.stdout.write(typeof JSON.parse(process.argv[1]).held)" "$OUT")" "boolean"

# A throwing probe reads free
OUT="$(lock_json "{platform:'linux',profileDir:'/x',probe:{readlink(){throw new Error('boom')}}}")"
expect_eq "posix: a throwing probe reads free" "$(held_of "$OUT")" "false"

# Regular file as profile dir
echo x > "$TMP/regular-file"
OUT="$(CRAFT_DEVTOOLS_PROFILE_DIR="$TMP/regular-file" lock_json "{platform:'linux'}")"
expect_eq "check error reads free (profile dir is a regular file)" "$(held_of "$OUT")" "false"

# Env override is honored (live lock found through CRAFT_DEVTOOLS_PROFILE_DIR)
lock_with "$HOST-$$"
OUT="$(CRAFT_DEVTOOLS_PROFILE_DIR="$PROF" lock_json "{platform:'linux'}")"
expect_eq "profile dir comes from CRAFT_DEVTOOLS_PROFILE_DIR" "$(held_of "$OUT")" "true"
rm -f "$PROF/SingletonLock"

# --- argv ---
OUT="$(CRAFT_DEVTOOLS_PROFILE_DIR="$PROF" node "$LAUNCH" --dry-run)"
EXPECT_SHARED='{"mode":"shared","command":"npx","args":["-y","chrome-devtools-mcp@1.10.1","--no-usage-statistics","--no-performance-crux"],"shell":false}'
expect_eq "dry-run argv is pinned and private" "$OUT" "$EXPECT_SHARED"

OUT="$(node "$LAUNCH" --dry-run --assume isolated)"
LAST="$(node -e "const j=JSON.parse(process.argv[1]);process.stdout.write(j.mode+' '+j.args[j.args.length-1]+' '+j.args.length)" "$OUT")"
expect_eq "--assume isolated appends --isolated last" "$LAST" "isolated --isolated 5"

OUT="$(node "$LAUNCH" --dry-run --assume shared)"
expect_eq "--assume shared matches the plain shared argv" "$OUT" "$EXPECT_SHARED"

if grep -q '@latest' "$LAUNCH"; then fail "no @latest anywhere in the launcher"; else pass "no @latest anywhere in the launcher"; fi

# dry-run follows a live lock when nothing is assumed
lock_with "$HOST-$$"
OUT="$(CRAFT_DEVTOOLS_PROFILE_DIR="$PROF" node "$LAUNCH" --dry-run)"
expect_eq "dry-run mode follows the live lock" "$(node -e "process.stdout.write(JSON.parse(process.argv[1]).mode)" "$OUT")" "isolated"
rm -f "$PROF/SingletonLock"

W="$(node -e "const m=require('$LAUNCH');process.stdout.write([m.serverArgv({isolated:false,platform:'win32'}).shell,m.serverArgv({isolated:false,platform:'darwin'}).shell,m.serverArgv({isolated:true,platform:'linux'}).shell].join(','))")"
expect_eq "win32 argv uses a shell, others do not" "$W" "true,false,false"

EXPORTS="$(node -e "const m=require('$LAUNCH');process.stdout.write(Object.keys(m).sort().join(','))")"
expect_eq "module exports the contracted names" "$EXPORTS" "FALLBACK_NOTICE,PINNED_VERSION,lockState,pruneNoticeFlags,serverArgv"

# --- marker, status, notice ---
COPY='Another session has the browser open, so this one gets a fresh window - you may need to sign in there.'
write_marker() { # key mode pid
  printf '{"mode":"%s","launcher_pid":%s,"version":"1.10.1","at":"2026-10-05T00:00:00.000Z"}' "$2" "$3" > "$CRAFT_DEVTOOLS_STATE_DIR/$1.json"
}
status_for() { CRAFT_DEVTOOLS_KEY="$1" node "$LAUNCH" status; }
notice_for() { CRAFT_DEVTOOLS_KEY="$1" node "$LAUNCH" notice "${@:2}"; }

expect_eq "status reads NONE without a marker" "$(status_for nokey)" "NONE"
write_marker s1 shared $$;   expect_eq "status reads SHARED" "$(status_for s1)" "SHARED"
write_marker s2 isolated $$; expect_eq "status reads ISOLATED" "$(status_for s2)" "ISOLATED"
write_marker s3 pending $$;  expect_eq "status reads PENDING" "$(status_for s3)" "PENDING"
write_marker s4 isolated "$DEAD"; expect_eq "a dead launcher_pid reads NONE" "$(status_for s4)" "NONE"
printf 'not json' > "$CRAFT_DEVTOOLS_STATE_DIR/s5.json"
expect_eq "a garbage marker reads NONE" "$(status_for s5)" "NONE"

# CLAUDE_PID is tried after CRAFT_DEVTOOLS_KEY
write_marker 4242 isolated $$
expect_eq "status falls back to CLAUDE_PID" "$(CLAUDE_PID=4242 node "$LAUNCH" status)" "ISOLATED"

# keys from the environment never reach outside the state folder
mkdir -p "$TMP/outside"
printf '{"mode":"isolated","launcher_pid":%s,"version":"1.10.1","at":"x"}' $$ > "$TMP/outside/m.json"
expect_eq "a CRAFT_DEVTOOLS_KEY with a path is never read" "$(CRAFT_DEVTOOLS_KEY=../outside/m node "$LAUNCH" status)" "NONE"
expect_eq "a CLAUDE_PID with a path is never read" "$(CLAUDE_PID=../outside/m node "$LAUNCH" status)" "NONE"
expect_eq "a rejected CRAFT_DEVTOOLS_KEY still lets CLAUDE_PID through" "$(CRAFT_DEVTOOLS_KEY=../outside/m CLAUDE_PID=4242 node "$LAUNCH" status)" "ISOLATED"
expect_eq "a key with dots and dashes is still a key" "$(write_marker k.e-y_1 shared $$; CRAFT_DEVTOOLS_KEY=k.e-y_1 node "$LAUNCH" status)" "SHARED"

# ancestor walk: with no key set, the marker is found by walking parent processes
write_marker "$$" shared $$
expect_eq "the walk finds a marker on an ancestor process" "$(node "$LAUNCH" status)" "SHARED"
rm -f "$CRAFT_DEVTOOLS_STATE_DIR/$$.json"

# A BusyBox-style ps (Alpine) rejects -p and answers only the list-all form. The
# fake hands back a two-hop chain above the launcher's parent; the walk must
# still reach the marker at its end.
REAL_PS="$(command -v ps)"
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/ps" <<FAKEPS
#!/bin/sh
case " \$* " in
  *" -p "*) echo "ps: unrecognized option: p" >&2; exit 1 ;;
esac
node_ppid=\$("$REAL_PS" -o ppid= -p "\$PPID" | tr -d ' ')
printf '  %s  90001\n  90001  90002\n    1     0\n' "\$node_ppid"
FAKEPS
chmod +x "$TMP/fakebin/ps"
write_marker 90002 isolated $$
expect_eq "the walk reaches an ancestor through a ps without -p" "$(PATH="$TMP/fakebin:$PATH" node "$LAUNCH" status)" "ISOLATED"
rm -f "$CRAFT_DEVTOOLS_STATE_DIR/90002.json"

# notice: once for isolated, then nothing
FIRST="$(notice_for s2)"; SECOND="$(notice_for s2)"
expect_eq "notice prints the copy the first time for isolated" "$FIRST" "$COPY"
expect_eq "notice prints nothing the second time" "$SECOND" ""
for k in s1 s3 nokey; do
  expect_eq "notice prints nothing for $k" "$(notice_for $k)" ""
done

# --quiet marks it said without printing
rm -f "$TMPDIR"/craft-devtools-noticed-*
Q1="$(notice_for s2 --quiet)"; Q2="$(notice_for s2)"
expect_eq "notice --quiet prints nothing" "$Q1" ""
expect_eq "notice after --quiet prints nothing" "$Q2" ""

# a failed flag write still prints
rm -f "$TMPDIR"/craft-devtools-noticed-*
OUT="$(TMPDIR="$TMP/does-not-exist" notice_for s2)"
expect_eq "a failed flag write still prints the copy" "$OUT" "$COPY"
RC=0; CRAFT_DEVTOOLS_KEY=s2 TMPDIR="$TMP/does-not-exist" node "$LAUNCH" notice >/dev/null || RC=$?
expect_eq "notice always exits 0" "$RC" "0"

# two simultaneous notices print one line
rm -f "$TMPDIR"/craft-devtools-noticed-*
write_marker s6 isolated $$
( notice_for s6 > "$TMP/n1" ) & N1=$!
( notice_for s6 > "$TMP/n2" ) & N2=$!
( notice_for s6 > "$TMP/n3" ) & N3=$!
wait "$N1" "$N2" "$N3"
expect_eq "three concurrent notices print one line" "$(cat "$TMP/n1" "$TMP/n2" "$TMP/n3" | grep -cF "$COPY" || true)" "1"

# a pre-planted symlink at the flag path is never written through
rm -f "$TMPDIR"/craft-devtools-noticed-*
ln -s "$TMP/victim" "$TMPDIR/craft-devtools-noticed-$$"
write_marker s7 isolated $$
SYM_OUT="$(notice_for s7)"
[ ! -e "$TMP/victim" ] && NOT_WRITTEN=yes || NOT_WRITTEN=no
expect_eq "a dangling symlink target is never created" "$NOT_WRITTEN" "yes"
expect_eq "a pre-planted flag path stays silent" "$SYM_OUT" ""
rm -f "$TMPDIR/craft-devtools-noticed-$$"

# the copy lives exactly once
N="$(grep -cF "$COPY" "$LAUNCH" || true)"
expect_eq "the copy appears exactly once in devtools-launch.cjs" "$N" "1"
N2="$(node -e "process.stdout.write(require('$LAUNCH').FALLBACK_NOTICE)")"
expect_eq "FALLBACK_NOTICE is the ruled copy" "$N2" "$COPY"

# =====================================================================
# Serve mode, end to end against the fake server. The real npx server is never
# launched: CRAFT_DEVTOOLS_SERVER swaps it for the fixture, and every path the
# launcher or the fixture touches lives in a test-owned dir.
# =====================================================================
FAKE="$REPO/tests/fixtures/devtools-fake-server.cjs"
export CRAFT_DEVTOOLS_SERVER="$FAKE"
echo ""
echo "serve mode (fake server)"

LAUNCHER_PID=""
trap 'exec 3>&- 2>/dev/null || true; [ -n "$LAUNCHER_PID" ] && kill "$LAUNCHER_PID" 2>/dev/null || true; rm -rf "$TMP"' EXIT

# wait_for <ticks> <cmd...> - poll every 0.1s, bounded
wait_for() { local n=$1; shift; local i=0; while [ "$i" -lt "$n" ]; do "$@" && return 0; i=$((i+1)); sleep 0.1; done; return 1; }

# start_session [ENV=val ...] - fresh dirs, launcher on a FIFO, fd 3 is the client's stdout-to-server
SESSION=0
start_session() {
  SESSION=$((SESSION+1))
  S="$TMP/s$SESSION"; mkdir -p "$S/state" "$S/profile" "$S/tmp"
  KEY="key$SESSION"; OUTF="$S/out"; ERRF="$S/err"; : > "$OUTF"
  mkfifo "$S/in"
  if [ -n "${PRESEED_DEAD_PID:-}" ]; then
    printf '{"mode":"isolated","launcher_pid":%s,"version":"1.10.1","at":"x"}' "$PRESEED_DEAD_PID" > "$S/state/stale.json"
    : > "$S/tmp/craft-devtools-noticed-$PRESEED_DEAD_PID"
  fi
  # cat bridges the FIFO to a real pipe: node on macOS never sees EOF on a FIFO stdin.
  cat "$S/in" | env CRAFT_DEVTOOLS_KEY="$KEY" CRAFT_DEVTOOLS_STATE_DIR="$S/state" CRAFT_DEVTOOLS_PROFILE_DIR="$S/profile" \
      TMPDIR="$S/tmp" FAKE_LOG="$S/spawns" "$@" node "$LAUNCH" > "$OUTF" 2> "$ERRF" &
  LAUNCHER_PID=$!
  exec 3> "$S/in"
}
end_session() {
  exec 3>&- 2>/dev/null || true
  wait_for 50 bash -c "! kill -0 $LAUNCHER_PID 2>/dev/null" || kill "$LAUNCHER_PID" 2>/dev/null || true
  wait "$LAUNCHER_PID" 2>/dev/null || true
  LAUNCHER_PID=""
}
hold_lock() { ln -s "$HOST-$$" "$S/profile/SingletonLock"; }
send() { printf '%s\n' "$1" >&3; }
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}'
INITED='{"jsonrpc":"2.0","method":"notifications/initialized"}'
LIST='{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
CALL='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"take_snapshot","arguments":{}}}'
handshake() { send "$INIT"; send "$INITED"; send "$LIST"; }

# out_info <id> count|text - over the captured stdout, batch lines flattened
out_info() {
  node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
    const msgs = lines.flatMap((l) => { const m = JSON.parse(l); return Array.isArray(m) ? m : [m]; });
    const hit = msgs.filter((m) => m.id === Number(process.argv[2]) && m.method === undefined);
    if (process.argv[3] === "count") process.stdout.write(String(hit.length));
    else process.stdout.write(hit[0] && hit[0].result && hit[0].result.content ? hit[0].result.content[0].text : "");
  ' "$OUTF" "$1" "$2"
}
has_id() { [ "$(out_info "$1" count)" -ge 1 ]; }
marker_mode() { node -e 'try{process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).mode)}catch{}' "$S/state/$KEY.json"; }
spawn_count() { [ -f "$S/spawns" ] && wc -l < "$S/spawns" | tr -d ' ' || echo 0; }

# --- FIRST: replayed handshake yields a working isolated session ---
start_session; hold_lock
handshake; send "$CALL"
wait_for 100 has_id 3 || true
expect_eq "replay: exactly one initialize response" "$(out_info 1 count)" "1"
expect_eq "replay: exactly one tools/list response" "$(out_info 2 count)" "1"
expect_eq "replay: the call is served by the isolated twin" "$(out_info 3 text)" "isolated=true"
expect_eq "replay: marker reads isolated" "$(marker_mode)" "isolated"
PURE="$(node -e 'const ok=require("fs").readFileSync(process.argv[1],"utf8").split("\n").filter(Boolean).every((l)=>{try{const m=JSON.parse(l);return (Array.isArray(m)?m:[m]).every((x)=>x.jsonrpc==="2.0")}catch{return false}});process.stdout.write(String(ok))' "$OUTF")"
expect_eq "stdout is pure JSON-RPC" "$PURE" "true"

# notice while this launcher is still running
expect_eq "notice after an isolated decision prints the copy once" "$(CRAFT_DEVTOOLS_STATE_DIR="$S/state" notice_for "$KEY")" "$COPY"
expect_eq "notice stays quiet the second time" "$(CRAFT_DEVTOOLS_STATE_DIR="$S/state" notice_for "$KEY")" ""

# launcher exits when stdin closes; marker is left for pruning
exec 3>&-
GONE=0; wait_for 80 bash -c "! kill -0 $LAUNCHER_PID 2>/dev/null" && GONE=1
expect_eq "launcher exits when stdin closes" "$GONE" "1"
wait "$LAUNCHER_PID" 2>/dev/null || true; LAUNCHER_PID=""
expect_eq "marker is left behind after exit" "$([ -f "$S/state/$KEY.json" ] && echo yes || echo no)" "yes"

# --- free lock serves from the shared child ---
start_session
handshake; send "$CALL"; wait_for 100 has_id 3 || true
expect_eq "free: call served by the shared child" "$(out_info 3 text)" "isolated=false"
expect_eq "free: marker reads shared" "$(marker_mode)" "shared"
expect_eq "free: no second child is spawned" "$(spawn_count)" "1"
end_session

# --- the decision waits for the first call ---
start_session
handshake; wait_for 100 has_id 2 || true
expect_eq "pre-call: marker reads pending" "$(marker_mode)" "pending"
hold_lock
send "$CALL"; wait_for 100 has_id 3 || true
expect_eq "a lock taken after the handshake still isolates the call" "$(out_info 3 text)" "isolated=true"
end_session

# --- a failing isolated child falls back to shared ---
start_session FAKE_FAIL_ISOLATED=1; hold_lock
handshake; send "$CALL"; wait_for 100 has_id 3 || true
expect_eq "failing twin: call lands on the shared child" "$(out_info 3 text)" "isolated=false"
expect_eq "failing twin: marker reads shared" "$(marker_mode)" "shared"
expect_eq "failing twin: replies are not duplicated" "$(out_info 2 count)" "1"
end_session

# --- an erroring lock check falls back to shared ---
start_session; rmdir "$S/profile"; : > "$S/profile"
handshake; send "$CALL"; wait_for 100 has_id 3 || true
expect_eq "lock check error: call served by the shared child" "$(out_info 3 text)" "isolated=false"
end_session

# --- dead markers are pruned at start ---
sleep 0 & DEAD2=$!; wait "$DEAD2" 2>/dev/null || true
PRESEED_DEAD_PID="$DEAD2" start_session
wait_for 50 bash -c "[ -f '$S/state/$KEY.json' ]" || true
expect_eq "dead markers are pruned at start" "$([ -f "$S/state/stale.json" ] && echo kept || echo pruned)" "pruned"
expect_eq "a live launcher's own marker survives the prune" "$([ -f "$S/state/$KEY.json" ] && echo yes || echo no)" "yes"
expect_eq "a dead launcher's notice flag is pruned at start" "$([ -e "$S/tmp/craft-devtools-noticed-$DEAD2" ] && echo kept || echo pruned)" "pruned"
end_session

# --- a launcher given a key with a path writes its marker inside the state folder ---
start_session CRAFT_DEVTOOLS_KEY=../esc/m
mkdir -p "$S/state/.../esc" "$S/esc"
handshake; send "$CALL"; wait_for 100 has_id 3 || true
expect_eq "a path in CRAFT_DEVTOOLS_KEY never writes outside the state folder" "$([ -e "$S/esc/m.json" ] && echo escaped || echo inside)" "inside"
expect_eq "the launcher still writes its marker inside the state folder" "$(ls "$S/state" | grep -c '\.json$' || true)" "1"
end_session

# --- notice flags: a reused pid starts unsaid, live launchers keep theirs ---
FLAGS="$TMP/flags"; mkdir -p "$FLAGS"
sleep 0 & DEAD3=$!; wait "$DEAD3" 2>/dev/null || true
sleep 30 & OTHER=$!
: > "$FLAGS/craft-devtools-noticed-$$"
: > "$FLAGS/craft-devtools-noticed-$DEAD3"
: > "$FLAGS/craft-devtools-noticed-$OTHER"
: > "$FLAGS/unrelated-file"
TMPDIR="$FLAGS" node -e "require('$LAUNCH').pruneNoticeFlags($$)"
expect_eq "a flag carrying the starting launcher's own (reused) pid is removed" "$([ -e "$FLAGS/craft-devtools-noticed-$$" ] && echo kept || echo removed)" "removed"
expect_eq "a dead launcher's flag is removed" "$([ -e "$FLAGS/craft-devtools-noticed-$DEAD3" ] && echo kept || echo removed)" "removed"
expect_eq "another live launcher's flag is kept" "$([ -e "$FLAGS/craft-devtools-noticed-$OTHER" ] && echo kept || echo removed)" "kept"
expect_eq "files that are not notice flags are left alone" "$([ -e "$FLAGS/unrelated-file" ] && echo kept || echo removed)" "kept"
kill "$OTHER" 2>/dev/null || true; wait "$OTHER" 2>/dev/null || true
RC=0; TMPDIR="$TMP/does-not-exist" node -e "require('$LAUNCH').pruneNoticeFlags($$)" || RC=$?
expect_eq "pruning a missing temp dir never throws" "$RC" "0"

# after a reused-pid flag is pruned, the next launcher's notice prints again
write_marker s8 isolated $$
: > "$TMPDIR/craft-devtools-noticed-$$"
expect_eq "a leftover flag for the same pid silences the notice" "$(notice_for s8)" ""
node -e "require('$LAUNCH').pruneNoticeFlags($$)"
expect_eq "after the start-up prune the notice prints again" "$(notice_for s8)" "$COPY"
rm -f "$TMPDIR/craft-devtools-noticed-$$"

# --- an outstanding tools/list during the switch is still answered ---
start_session FAKE_LIST_DELAY_MS=400; hold_lock
send "$INIT"; send "$INITED"; wait_for 100 has_id 1 || true
send "$LIST"; send "$CALL"
wait_for 100 has_id 3 || true
wait_for 100 has_id 2 || true
expect_eq "drain: the in-flight tools/list is answered" "$(out_info 2 count)" "1"
expect_eq "drain: the call still lands on the isolated twin" "$(out_info 3 text)" "isolated=true"
end_session

# --- a client reply goes to the child that asked, even when ids collide ---
# Both children ask roots/list with id 900. The client answers the shared child's
# request first and the isolated child's second; each answer must reach its asker.
S_REPLY="$TMP/reply-log"; rm -f "$S_REPLY"
start_session FAKE_SERVER_REQUEST=1 FAKE_LIST_DELAY_MS=1500 FAKE_REPLY_LOG="$S_REPLY"; hold_lock
asks() { [ "$(grep -c roots/list "$OUTF" || true)" -ge "$1" ]; }
send "$INIT"; send "$INITED"; wait_for 100 has_id 1 || true
send "$LIST"; wait_for 100 asks 1 || true
send "$CALL"; wait_for 100 asks 2 || true
send '{"jsonrpc":"2.0","id":900,"result":{"roots":["from-first-answer"]}}'
send '{"jsonrpc":"2.0","id":900,"result":{"roots":["from-second-answer"]}}'
wait_for 100 has_id 3 || true
wait_for 100 has_id 2 || true
expect_eq "routing: the isolated child got the answer to its own request" "$(out_info 3 text)" 'isolated=true;reply={"roots":["from-second-answer"]}'
expect_eq "routing: the shared child got the answer to its own request" "$(cat "$S_REPLY" 2>/dev/null)" 'shared:{"roots":["from-first-answer"]}'
expect_eq "routing: the colliding id does not disturb the drain" "$(out_info 2 count)" "1"
end_session

# --- a 2 MB line passes through intact ---
start_session; hold_lock
handshake; send '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"big","arguments":{}}}'
wait_for 150 has_id 3 || true
BIGLEN="$(out_info 3 text | wc -c | tr -d ' ')"
expect_eq "a 2 MB line arrives intact" "$BIGLEN" "2097152"
end_session

# --- a batch line containing a tools/call triggers the decision ---
start_session; hold_lock
handshake; send "[$CALL]"
wait_for 100 has_id 3 || true
expect_eq "batch: a tools/call inside an array decides isolated" "$(out_info 3 text)" "isolated=true"
end_session

# --- an injected throw in the pump leaves the session working ---
start_session CRAFT_DEVTOOLS_FAULT=pump; hold_lock
handshake; send "$CALL"; wait_for 100 has_id 3 || true
expect_eq "pump fault: the call is still answered" "$(out_info 3 text)" "isolated=false"
send '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"take_snapshot","arguments":{}}}'
wait_for 100 has_id 4 || true
expect_eq "pump fault: later calls keep working over the raw pipe" "$(out_info 4 text)" "isolated=false"
end_session

# --- .mcp.json launches the launcher ---
MCP="$(node -e '
  const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).mcpServers["chrome-devtools"];
  process.stdout.write([s.command, s.args.join(" "), JSON.stringify(s.env)].join("|"));
' "$REPO/.mcp.json")"
expect_eq ".mcp.json launches the launcher through node" "$MCP" 'node|${CLAUDE_PLUGIN_ROOT}/hooks/scripts/devtools-launch.cjs|{}'
N3="$(grep -c 'npx\|@latest' "$REPO/.mcp.json" || true)"
expect_eq ".mcp.json no longer names npx or @latest" "$N3" "0"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed ($TOTAL total)"
[ "$FAIL_COUNT" -eq 0 ]
