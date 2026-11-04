#!/bin/bash
# test-annotate-background.sh - The listener as a Claude Code background command:
# arm --background prepares, listen execs the listener (so the process a stop
# reaches is the listener), ready reports the port the listener wrote, and
# ensure restarts nothing itself when the listener was started that way.
# Plain arm keeps its detached launch. Every listener started here is stopped.
# Usage: bash tests/test-annotate-background.sh

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

RUN="$SCRIPTS_DIR/annotate-run.sh"

TMP_ROOTS=()
TMP_PIDS=()

BOUNDARY_ROOT="$(mktemp -d)"
TMP_ROOTS+=("$BOUNDARY_ROOT")
export CRAFT_ANNOTATE_BOUNDARY_DIR="$BOUNDARY_ROOT/boundary"

# The implementer's own shell may carry this; every case sets it itself.
unset CLAUDE_CODE_DISABLE_BACKGROUND_TASKS

# stop_job <pid>... - signal a listener job started by start_listen and wait for it to end
stop_job() {
  local p
  for p in "$@"; do
    [ -n "$p" ] || continue
    kill "$p" 2>/dev/null || true
    wait_dead "$p" || true
  done
  return 0
}

cleanup() {
  local r p f
  for r in "${TMP_ROOTS[@]:-}"; do
    [ -n "$r" ] || continue
    for f in "$r"/.craft/annotations/*/listener.pid; do
      [ -f "$f" ] || continue
      p="$(cat "$f" 2>/dev/null || true)"
      case "$p" in ''|*[!0-9]*) ;; *) kill "$p" 2>/dev/null || true ;; esac
    done
    rm -rf "$r"
  done
  stop_job "${TMP_PIDS[@]:-}"
  return 0
}
trap cleanup EXIT

new_root() {
  NEW_ROOT="$(cd "$(mktemp -d)" && pwd -P)"
  TMP_ROOTS+=("$NEW_ROOT")
  mkdir -p "$NEW_ROOT/.craft"
}

is_running() {
  local st
  st="$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')" || true
  [ -n "$st" ] && [ "${st#Z}" = "$st" ]
}

wait_dead() {
  local i=0
  while is_running "$1" && [ "$i" -lt 40 ]; do
    sleep 0.25; i=$((i + 1))
  done
  ! is_running "$1"
}

# run_sh <root> <args...> - one script call with an explicit root, output and errors together
run_sh() {
  local root="$1"; shift
  env -u CRAFT_PROJECT_ROOT bash "$RUN" "$1" --root "$root" "${@:2}" 2>&1 || true
}

# annotate_procs <root> - count of listener processes serving the root
annotate_procs() {
  ps -ax -o command= 2>/dev/null | grep -F "annotate-channel.py --dir $1/" | grep -vc grep || true
}

rd() { cat "$1" 2>/dev/null | tr -d '\n' || true; }

# start_listen <root> <id> - plays Claude Code: listen as a shell job; sets LJ
start_listen() {
  bash "$RUN" listen --root "$1" --session "$2" >/dev/null 2>&1 &
  LJ=$!
  # Disowned so the shell prints no job report when a test stops it.
  disown "$LJ" 2>/dev/null || true
  TMP_PIDS+=("$LJ")
}

# wait_port <dir> - bounded poll for the listener's port file
wait_port() {
  local i=0
  while [ "$i" -lt 100 ]; do
    case "$(rd "$1/port")" in ''|*[!0-9]*) ;; *) return 0 ;; esac
    sleep 0.1; i=$((i + 1))
  done
  return 1
}

# wait_pid_file <dir> - bounded poll for listen to record its pid
wait_pid_file() {
  local i=0
  while [ "$i" -lt 100 ]; do
    [ -s "$1/listener.pid" ] && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}

# ---------------------------------------------------------------------------

begin_test "the listener started by listen is the process a stop reaches"
new_root; R="$NEW_ROOT"
D="$R/.craft/annotations/bg1"
run_sh "$R" arm --background --session bg1 --owner-pid "$$" >/dev/null
start_listen "$R" bg1
wait_port "$D" || true
assert_eq "the listen job pid is the recorded listener pid" "$LJ" "$(rd "$D/listener.pid")"
assert_eq "one listener serves the root" "1" "$(annotate_procs "$R")"
kill -TERM "$LJ" 2>/dev/null || true
assert_eq "SIGTERM to the listen pid stops the listener" "0" "$(wait_dead "$LJ" && echo 0 || echo 1)"
assert_eq "no listener process is left after SIGTERM" "0" "$(annotate_procs "$R")"
rm -f "$D/listener.pid" "$D/port"
start_listen "$R" bg1
wait_port "$D" || true
assert_eq "a second start is again the recorded pid" "$LJ" "$(rd "$D/listener.pid")"
kill -HUP "$LJ" 2>/dev/null || true
assert_eq "SIGHUP to the listen pid stops the listener" "0" "$(wait_dead "$LJ" && echo 0 || echo 1)"
assert_eq "no listener process is left after SIGHUP" "0" "$(annotate_procs "$R")"

begin_test "arm --background prepares and prints LISTEN without starting anything"
new_root; R="$NEW_ROOT"
D="$R/.craft/annotations/bg2"
OUT="$(run_sh "$R" arm --background --session bg2 --owner-pid "$$")"
assert_eq "prints the listen line" "SESSION bg2 LISTEN" "$OUT"
assert_eq "launch marker is background" "background" "$(rd "$D/launch")"
assert_eq "owner is the given pid" "$$" "$(rd "$D/owner.pid")"
assert_file_not_exists "no listener pid" "$D/listener.pid"
assert_file_not_exists "no port" "$D/port"
assert_eq "no process" "0" "$(annotate_procs "$R")"
OUT="$(run_sh "$R" arm --background --owner-pid "$$")"
case "$OUT" in "SESSION "*" LISTEN") NEWID="ok" ;; *) NEWID="$OUT" ;; esac
assert_eq "without --session a fresh id is minted" "ok" "$NEWID"

begin_test "listen then ready prints the port the listener wrote"
new_root; R="$NEW_ROOT"
D="$R/.craft/annotations/bg3"
run_sh "$R" arm --background --session bg3 --owner-pid "$$" >/dev/null
start_listen "$R" bg3
OUT="$(run_sh "$R" ready --session bg3)"
P="$(rd "$D/port")"
assert_eq "ready line equals the port file" "SESSION bg3 PORT $P" "$OUT"
TOKEN="$(rd "$D/token")"
HEALTH="$(curl -s --max-time 5 "http://127.0.0.1:$P/health?token=$TOKEN" 2>/dev/null || true)"
assert_contains "health answers with the session token" "ok" "$HEALTH"
assert_eq "status reads the port back" "SESSION bg3 PORT $P PID $LJ CLIENTS 0" "$(run_sh "$R" status --session bg3)"
stop_job "$LJ"

begin_test "ready on a session whose listener never starts times out with a message"
new_root; R="$NEW_ROOT"
run_sh "$R" arm --background --session bg3b --owner-pid "$$" >/dev/null
OUT="$(run_sh "$R" ready --session bg3b --timeout 1)"
assert_contains "names the log" "listener did not report a port" "$OUT"

begin_test "arm --background on a live listener reuses it"
new_root; R="$NEW_ROOT"
D="$R/.craft/annotations/bg4"
run_sh "$R" arm --background --session bg4 --owner-pid "$$" >/dev/null
start_listen "$R" bg4
run_sh "$R" ready --session bg4 >/dev/null
P="$(rd "$D/port")"
OUT="$(run_sh "$R" arm --background --session bg4 --owner-pid "$$")"
assert_eq "same port line" "SESSION bg4 PORT $P" "$OUT"
assert_eq "same pid" "$LJ" "$(rd "$D/listener.pid")"
assert_eq "still one process" "1" "$(annotate_procs "$R")"

begin_test "listen on a live listener exits 0 and starts no second one"
OUT="$(run_sh "$R" listen --session bg4)"
assert_eq "prints the live port" "SESSION bg4 PORT $P" "$OUT"
assert_eq "still one process" "1" "$(annotate_procs "$R")"
assert_eq "pid unchanged" "$LJ" "$(rd "$D/listener.pid")"
stop_job "$LJ"

begin_test "listen on a missing folder says no such session and creates nothing"
new_root; R="$NEW_ROOT"
OUT="$(run_sh "$R" listen --session nope)"
assert_contains "says so" "no such session: nope" "$OUT"
assert_dir_not_exists "no folder created" "$R/.craft/annotations/nope"
assert_eq "no process" "0" "$(annotate_procs "$R")"

begin_test "ensure on a dead background listener prints LISTEN STREAK and starts nothing"
new_root; R="$NEW_ROOT"
D="$R/.craft/annotations/bg5"
run_sh "$R" arm --background --session bg5 --owner-pid "$$" >/dev/null
start_listen "$R" bg5
run_sh "$R" ready --session bg5 >/dev/null
assert_contains "healthy probe" "OK PORT" "$(run_sh "$R" ensure --session bg5)"
kill -KILL "$LJ" 2>/dev/null || true
wait_dead "$LJ" || true
assert_eq "first death" "LISTEN STREAK 1" "$(run_sh "$R" ensure --session bg5)"
assert_eq "nothing started" "0" "$(annotate_procs "$R")"
assert_file_not_exists "pid file removed" "$D/listener.pid"
assert_file_not_exists "port file removed" "$D/port"
# The exit notice and the watch's UNREACHABLE can both run ensure before Claude
# runs listen: the second call is the same death and must not count again.
assert_eq "same death asked twice" "LISTEN STREAK 1" "$(run_sh "$R" ensure --session bg5)"
assert_eq "streak file still 1" "1" "$(rd "$D/rearm.streak")"
start_listen "$R" bg5
run_sh "$R" ready --session bg5 >/dev/null
kill -KILL "$LJ" 2>/dev/null || true
wait_dead "$LJ" || true
assert_eq "second death" "LISTEN STREAK 2" "$(run_sh "$R" ensure --session bg5)"
start_listen "$R" bg5
run_sh "$R" ready --session bg5 >/dev/null
assert_contains "healthy again" "OK PORT" "$(run_sh "$R" ensure --session bg5)"
assert_eq "streak reset" "0" "$(rd "$D/rearm.streak")"
stop_job "$LJ"

begin_test "ensure waits for a starting listener instead of killing it"
new_root; R="$NEW_ROOT"
D="$R/.craft/annotations/bg6"
run_sh "$R" arm --background --session bg6 --owner-pid "$$" >/dev/null
start_listen "$R" bg6
wait_pid_file "$D" || true
OUT="$(run_sh "$R" ensure --session bg6)"
assert_contains "ok" "OK PORT" "$OUT"
assert_eq "the listener survived" "0" "$(is_running "$LJ" && echo 0 || echo 1)"
stop_job "$LJ"

begin_test "with CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1, arm --background starts detached"
new_root; R="$NEW_ROOT"
D="$R/.craft/annotations/bg7"
OUT="$(CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 run_sh "$R" arm --background --session bg7 --owner-pid "$$")"
P="$(rd "$D/port")"
assert_eq "prints the port line" "SESSION bg7 PORT $P" "$OUT"
assert_eq "launch marker is detached" "detached" "$(rd "$D/launch")"
TOKEN="$(rd "$D/token")"
assert_contains "listener answers" "ok" "$(curl -s --max-time 5 "http://127.0.0.1:$P/health?token=$TOKEN" 2>/dev/null || true)"
LP="$(rd "$D/listener.pid")"
kill "$LP" 2>/dev/null || true
wait_dead "$LP" || true
OUT="$(run_sh "$R" ensure --session bg7)"
assert_contains "restarts as today" "REARMED PORT" "$OUT"
assert_contains "streak 1" "STREAK 1" "$OUT"
kill "$(rd "$D/listener.pid")" 2>/dev/null || true
for v in TRUE Yes ON; do
  OUT="$(CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=$v run_sh "$R" arm --background --session "bg7$v" --owner-pid "$$")"
  case "$OUT" in "SESSION bg7$v PORT "*) RES=detached ;; *) RES="$OUT" ;; esac
  assert_eq "$v counts as disabled" "detached" "$RES"
done

begin_test "plain arm writes the detached launch marker and starts the listener"
new_root; R="$NEW_ROOT"
D="$R/.craft/annotations/bg8"
OUT="$(run_sh "$R" arm --session bg8 --owner-pid "$$")"
assert_eq "plain arm prints the port line" "SESSION bg8 PORT $(rd "$D/port")" "$OUT"
assert_eq "launch marker" "detached" "$(rd "$D/launch")"
kill "$(rd "$D/listener.pid")" 2>/dev/null || true

begin_test "listen takes its own pid as owner only when the session has none"
new_root; R="$NEW_ROOT"
D="$R/.craft/annotations/bg9"
run_sh "$R" arm --background --session bg9 --owner-pid "$$" >/dev/null
start_listen "$R" bg9
run_sh "$R" ready --session bg9 >/dev/null
assert_eq "owner stays the given pid" "$$" "$(rd "$D/owner.pid")"
stop_job "$LJ"
rm -f "$D/owner.pid" "$D/listener.pid" "$D/port"
start_listen "$R" bg9
run_sh "$R" ready --session bg9 >/dev/null
assert_eq "owner is the listener pid" "$LJ" "$(rd "$D/owner.pid")"
stop_job "$LJ"

finish_tests
