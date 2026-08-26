#!/bin/bash
# test-dashboard-page.sh — Tests for scripts/dashboard/dashboard-page.sh:
# the two-stamp version check and the checksum verdict that keeps a
# hand-edited copy from being silently overwritten.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

PAGE_SCRIPT="$PLUGIN_ROOT/scripts/dashboard/dashboard-page.sh"
TEMPLATE="$PLUGIN_ROOT/scripts/dashboard/template/index.html"

echo "=== test-dashboard-page.sh ==="
echo ""

# Builds a fresh fixture root: <tmp>/.craft exists, empty.
make_fixture_root() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.craft"
  echo "$tmp"
}

# Writes a minimal page with the given (possibly non-numeric) stamp value.
write_page_with_stamp() {
  local root="$1" stamp="$2"
  cat > "$root/.craft/dashboard.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="craft-template-version" content="$stamp">
<title>Craft Browser</title>
</head>
<body>fixture page</body>
</html>
EOF
}

live_shipped_stamp() {
  grep -o 'craft-template-version" content="[0-9]*"' "$TEMPLATE" | head -1 | sed -E 's/.*content="([0-9]*)"/\1/'
}

SHIPPED_STAMP="$(live_shipped_stamp)"

# --- Test 1: unreadable stamp -> behind + unknown, never missing (FIRST) ---
begin_test "a copy with an unreadable stamp reports behind and unknown, never missing"

ROOT=$(make_fixture_root)
write_page_with_stamp "$ROOT" "x"

OUT=$(bash "$PAGE_SCRIPT" --check --root "$ROOT")

assert_contains "STATE=behind" "STATE=behind" "$OUT"
assert_contains "COPY=unknown" "COPY=unknown" "$OUT"
assert_not_contains "never STATE=missing" "STATE=missing" "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 2: no .craft anywhere -> no-project, writes nothing ---
begin_test "no .craft anywhere reports no-project and writes nothing"

ROOT=$(mktemp -d)

set +e
OUT=$(bash "$PAGE_SCRIPT" --check --root "$ROOT" 2>&1)
RC=$?
set -e

assert_exit_code "exits 0" "0" "$RC"
assert_contains "STATE=no-project" "STATE=no-project" "$OUT"
assert_dir_not_exists "no .craft was created" "$ROOT/.craft"

rm -rf "$ROOT"
echo ""

# --- Test 3: absent page -> missing, COPY=unknown ---
begin_test "an absent page reports missing with COPY=unknown"

ROOT=$(make_fixture_root)

OUT=$(bash "$PAGE_SCRIPT" --check --root "$ROOT")

assert_contains "STATE=missing" "STATE=missing" "$OUT"
assert_contains "COPY=unknown" "COPY=unknown" "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 4: one stamp behind the live shipped template -> behind ---
begin_test "a copy one stamp behind the live shipped template reports behind"

ROOT=$(make_fixture_root)
write_page_with_stamp "$ROOT" "$((SHIPPED_STAMP - 1))"

OUT=$(bash "$PAGE_SCRIPT" --check --root "$ROOT")

assert_contains "STATE=behind" "STATE=behind" "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 5: at the live shipped stamp -> current ---
begin_test "a copy at the live shipped stamp reports current"

ROOT=$(make_fixture_root)
write_page_with_stamp "$ROOT" "$SHIPPED_STAMP"

OUT=$(bash "$PAGE_SCRIPT" --check --root "$ROOT")

assert_contains "STATE=current" "STATE=current" "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 6: above the live shipped stamp -> current (downgrade case) ---
begin_test "a copy above the live shipped stamp reports current"

ROOT=$(make_fixture_root)
write_page_with_stamp "$ROOT" "$((SHIPPED_STAMP + 1))"

OUT=$(bash "$PAGE_SCRIPT" --check --root "$ROOT")

assert_contains "STATE=current" "STATE=current" "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 7: pull with no prior page writes it, BACKUP=none, sidecar written ---
begin_test "pull with no prior page writes the page, reports BACKUP=none, and writes the sidecar"

ROOT=$(make_fixture_root)

OUT=$(bash "$PAGE_SCRIPT" --pull --root "$ROOT")

assert_contains "PULLED=1" "PULLED=1" "$OUT"
assert_contains "BACKUP=none" "BACKUP=none" "$OUT"
assert_file_exists "page written" "$ROOT/.craft/dashboard.html"
assert_file_exists "sidecar written" "$ROOT/.craft/graph/.dashboard.sha256"

rm -rf "$ROOT"
echo ""

# --- Test 8: pull over an existing page backs up the old bytes first ---
begin_test "pull over an existing page moves the old bytes to dashboard-backup.html before writing"

ROOT=$(make_fixture_root)
echo "old hand-edited content" > "$ROOT/.craft/dashboard.html"

bash "$PAGE_SCRIPT" --pull --root "$ROOT" >/dev/null

assert_file_exists "backup exists" "$ROOT/.craft/dashboard-backup.html"
assert_eq "backup carries the old bytes" "old hand-edited content" "$(cat "$ROOT/.craft/dashboard-backup.html")"
assert_eq "page now matches the shipped template" "$(cat "$TEMPLATE")" "$(cat "$ROOT/.craft/dashboard.html")"

rm -rf "$ROOT"
echo ""

# --- Test 9: pull then check reports current and pristine ---
begin_test "pull then check reports current and pristine"

ROOT=$(make_fixture_root)
bash "$PAGE_SCRIPT" --pull --root "$ROOT" >/dev/null

OUT=$(bash "$PAGE_SCRIPT" --check --root "$ROOT")

assert_contains "STATE=current" "STATE=current" "$OUT"
assert_contains "COPY=pristine" "COPY=pristine" "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 10: editing the page after a pull flips COPY to edited ---
begin_test "editing the page after a pull flips COPY to edited"

ROOT=$(make_fixture_root)
bash "$PAGE_SCRIPT" --pull --root "$ROOT" >/dev/null
echo "<!-- hand edit -->" >> "$ROOT/.craft/dashboard.html"

OUT=$(bash "$PAGE_SCRIPT" --check --root "$ROOT")

assert_contains "COPY=edited" "COPY=edited" "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 11: no sidecar -> unknown even when content matches the shipped template ---
begin_test "a page with no sidecar reports COPY=unknown even when it matches the shipped template"

ROOT=$(make_fixture_root)
cp "$TEMPLATE" "$ROOT/.craft/dashboard.html"

OUT=$(bash "$PAGE_SCRIPT" --check --root "$ROOT")

assert_contains "COPY=unknown" "COPY=unknown" "$OUT"

rm -rf "$ROOT"
echo ""

# --- Test 12: a second pull overwrites the prior backup, one generation deep ---
begin_test "a second pull overwrites the prior backup, one generation deep"

ROOT=$(make_fixture_root)
echo "generation one" > "$ROOT/.craft/dashboard.html"
bash "$PAGE_SCRIPT" --pull --root "$ROOT" >/dev/null

echo "generation two" > "$ROOT/.craft/dashboard.html"
bash "$PAGE_SCRIPT" --pull --root "$ROOT" >/dev/null

assert_eq "backup holds only the most recent prior copy" "generation two" "$(cat "$ROOT/.craft/dashboard-backup.html")"

rm -rf "$ROOT"
echo ""

# --- Test 13: an unwritable .craft reports PULLED=0 with a machine code ---
begin_test "an unwritable .craft reports PULLED=0 with a machine code and exits 0"

if [ "$(id -u)" = "0" ]; then
  echo "  SKIP: running as root, chmod does not deny writes"
else
  ROOT=$(make_fixture_root)
  chmod 500 "$ROOT/.craft"

  set +e
  OUT=$(bash "$PAGE_SCRIPT" --pull --root "$ROOT" 2>&1)
  RC=$?
  set -e

  chmod 700 "$ROOT/.craft"

  assert_exit_code "exits 0" "0" "$RC"
  assert_contains "PULLED=0" "PULLED=0" "$OUT"
  assert_contains "carries a REASON code" "REASON=" "$OUT"

  rm -rf "$ROOT"
fi
echo ""

finish_tests "test-dashboard-page"
