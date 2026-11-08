#!/bin/bash
# test-decisions-scripts.sh — Behavior tests for the decisions-*.sh trio
# Usage: bash tests/test-decisions-scripts.sh
#
# Chunk 1 covers decisions-list.sh only. Chunks 2-4 append sections here
# for decisions-capture.sh, decisions-transition.sh, and the complete-story.sh
# flip.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$SCRIPT_DIR/../hooks/scripts/decisions-list.sh"
CAPTURE="$SCRIPT_DIR/../hooks/scripts/decisions-capture.sh"
TRANSITION="$SCRIPT_DIR/../hooks/scripts/decisions-transition.sh"
COMPLETE_STORY="$SCRIPT_DIR/../hooks/scripts/complete-story.sh"
VIEW="$SCRIPT_DIR/../hooks/scripts/decisions-view.sh"
PARSER="$SCRIPT_DIR/../hooks/scripts/decision-body-parser.py"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Expected: $2"; [ -n "${3:-}" ] && echo "    Got:      $3"; return 0; }

fresh_root() {
  ROOT=$(mktemp -d)
  export CRAFT_PROJECT_ROOT="$ROOT"
}

# write_record ROOM SLUG DATE TITLE STATUS TAGS_CSV [DISPOSITION] [STORIES_CSV] [EXTRA_BODY_LINE]
write_record() {
  local room="$1" slug="$2" date="$3" title="$4" status="$5" tags="$6"
  local disposition="${7:-}" stories="${8:-}" extra="${9:-}"
  local dir
  case "$room" in
    root) dir="$ROOT/.craft/decisions" ;;
    approved) dir="$ROOT/.craft/decisions/approved" ;;
    archive) dir="$ROOT/.craft/decisions/archive" ;;
  esac
  mkdir -p "$dir"
  {
    echo "---"
    echo "type: decision"
    echo "status: $status"
    echo "created: $date"
    echo "source: session"
    echo "tags: [$tags]"
    [ -n "$disposition" ] && echo "disposition: $disposition"
    [ -n "$stories" ] && echo "stories: [$stories]"
    echo "---"
    echo "# $title"
    echo ""
    echo "## Context"
    [ -n "$extra" ] && echo "$extra"
    echo ""
    echo "## Options considered"
    echo "## Decision"
    echo "## Consequences"
    echo "## Approval"
    echo "> \"approved\" - $date, session"
  } > "$dir/$date-$slug.md"
}

# write_story NAME STATUS DECISIONS_CSV [SUBDIR]
# SUBDIR defaults to a cycle stories dir so the story scan glob matches it.
write_story() {
  local name="$1" status="$2" decisions="$3" subdir="${4:-.craft/cycles/1-test/stories}"
  local dir="$ROOT/$subdir"
  mkdir -p "$dir"
  cat > "$dir/$name.md" <<EOF
---
name: $name
status: $status
decisions: [$decisions]
---
# $name
EOF
}

echo "=== test-decisions-scripts.sh ==="
echo ""

echo "-- Test: list over 40 records and 205 story files completes in under 2 seconds --"
fresh_root
for i in $(seq -w 1 40); do
  write_record "root" "scale-record-$i" "2026-01-01" "Scale record $i" "pending" "scale"
done
for i in $(seq -w 1 205); do
  write_story "scale-story-$i" "planning" ""
done
START=$(date +%s)
set +e
OUT=$(bash "$LIST")
RC=$?
set -e
END=$(date +%s)
ELAPSED=$((END - START))
[ "$RC" -eq 0 ] && pass "exit 0 at scale" || fail "exit 0 at scale" "0" "$RC"
COUNT=$(echo "$OUT" | grep -c "^SLUG=" || true)
[ "$COUNT" -eq 40 ] && pass "all 40 records emitted at scale" || fail "all 40 records emitted at scale" "40" "$COUNT"
[ "$ELAPSED" -lt 2 ] && pass "completes in under 2 seconds ($ELAPSED s)" || fail "completes in under 2 seconds" "<2s" "${ELAPSED}s"
rm -rf "$ROOT"

echo "-- Test: no .craft/decisions directory is silent and exits 0 --"
fresh_root
set +e
OUT=$(bash "$LIST")
RC=$?
set -e
[ "$RC" -eq 0 ] && pass "exit 0 with no .craft/decisions" || fail "exit 0 with no .craft/decisions" "0" "$RC"
[ -z "$OUT" ] && pass "empty stdout with no .craft/decisions" || fail "empty stdout with no .craft/decisions" "(empty)" "$OUT"
rm -rf "$ROOT"

echo "-- Test: a record whose BODY contains a disposition: line still reads DISPOSITION=open --"
fresh_root
write_record "approved" "fence-trap" "2026-09-03" "Fence trap record" "accepted" "decisions" "" "" \
  "disposition: open | claimed | crafted - pure enum, nothing else."
OUT=$(bash "$LIST" --slug=2026-09-03-fence-trap)
echo "$OUT" | grep -q "^DISPOSITION=open$" && pass "fence-scoped parse ignores body prose" || fail "fence-scoped parse ignores body prose" "DISPOSITION=open" "$(echo "$OUT" | grep '^DISPOSITION=' || echo missing)"
rm -rf "$ROOT"

echo "-- Test: keys are emitted in the contracted order for every block --"
fresh_root
write_record "root" "order-check" "2026-01-01" "Order check" "pending" "tag-a"
OUT=$(bash "$LIST")
KEYS=$(echo "$OUT" | grep -v '^$' | sed -E 's/=.*$//' | tr '\n' ',')
EXPECTED="FILE,ROOM,SLUG,DATE,TITLE,STATUS,TAGS,DISPOSITION,STORIES,"
[ "$KEYS" = "$EXPECTED" ] && pass "keys emitted in contracted order" || fail "keys emitted in contracted order" "$EXPECTED" "$KEYS"
rm -rf "$ROOT"

echo "-- Test: SLUG is the full dated slug, not the date-stripped slug --"
fresh_root
write_record "root" "keep-my-date" "2026-05-01" "Keep my date" "pending" "tag-a"
OUT=$(bash "$LIST")
echo "$OUT" | grep -q "^SLUG=2026-05-01-keep-my-date$" && pass "SLUG carries the full dated slug" || fail "SLUG carries the full dated slug" "SLUG=2026-05-01-keep-my-date" "$(echo "$OUT" | grep '^SLUG=' || echo missing)"
rm -rf "$ROOT"

echo "-- Test: a record claimed by a non-complete story reads claimed with STORIES set --"
fresh_root
write_record "approved" "claimed-record" "2026-01-01" "Claimed record" "accepted" "tag-a"
write_story "claiming-story" "planning" "2026-01-01-claimed-record"
OUT=$(bash "$LIST" --slug=2026-01-01-claimed-record)
echo "$OUT" | grep -q "^DISPOSITION=claimed$" && pass "claimed by a non-complete story" || fail "claimed by a non-complete story" "DISPOSITION=claimed" "$(echo "$OUT" | grep '^DISPOSITION=' || echo missing)"
echo "$OUT" | grep -q "^STORIES=claiming-story$" && pass "STORIES set to the claiming story" || fail "STORIES set to the claiming story" "STORIES=claiming-story" "$(echo "$OUT" | grep '^STORIES=' || echo missing)"
rm -rf "$ROOT"

echo "-- Test: the same record reads open once the claiming story's status is complete --"
fresh_root
write_record "approved" "was-claimed" "2026-01-01" "Was claimed" "accepted" "tag-a"
write_story "shipped-story" "complete" "2026-01-01-was-claimed"
OUT=$(bash "$LIST" --slug=2026-01-01-was-claimed)
echo "$OUT" | grep -q "^DISPOSITION=open$" && pass "reads open once claiming story completes" || fail "reads open once claiming story completes" "DISPOSITION=open" "$(echo "$OUT" | grep '^DISPOSITION=' || echo missing)"
echo "$OUT" | grep -q "^STORIES=$" && pass "STORIES empty once open" || fail "STORIES empty once open" "STORIES=" "$(echo "$OUT" | grep '^STORIES=' || echo missing)"
rm -rf "$ROOT"

echo "-- Test: frontmatter disposition: crafted wins over an active claiming story --"
fresh_root
write_record "approved" "already-crafted" "2026-01-01" "Already crafted" "accepted" "tag-a" "crafted" "shipping-story"
write_story "another-claimant" "planning" "2026-01-01-already-crafted"
OUT=$(bash "$LIST" --slug=2026-01-01-already-crafted)
echo "$OUT" | grep -q "^DISPOSITION=crafted$" && pass "crafted wins over an active claiming story" || fail "crafted wins over an active claiming story" "DISPOSITION=crafted" "$(echo "$OUT" | grep '^DISPOSITION=' || echo missing)"
rm -rf "$ROOT"

echo "-- Test: frontmatter disposition: claimed is never emitted from disk --"
fresh_root
write_record "approved" "fake-claimed" "2026-01-01" "Fake claimed" "accepted" "tag-a" "claimed"
OUT=$(bash "$LIST" --slug=2026-01-01-fake-claimed)
echo "$OUT" | grep -q "^DISPOSITION=open$" && pass "a disk claimed value is never trusted, reads open with no claimant" || fail "a disk claimed value is never trusted" "DISPOSITION=open" "$(echo "$OUT" | grep '^DISPOSITION=' || echo missing)"
rm -rf "$ROOT"

echo "-- Test: STORIES for a crafted record comes from frontmatter, not from the scan --"
fresh_root
write_record "approved" "frontmatter-stories" "2026-01-01" "Frontmatter stories" "accepted" "tag-a" "crafted" "shipped-by-me"
write_story "not-the-shipper" "planning" "2026-01-01-frontmatter-stories"
OUT=$(bash "$LIST" --slug=2026-01-01-frontmatter-stories)
echo "$OUT" | grep -q "^STORIES=shipped-by-me$" && pass "STORIES comes from frontmatter for a crafted record" || fail "STORIES comes from frontmatter for a crafted record" "STORIES=shipped-by-me" "$(echo "$OUT" | grep '^STORIES=' || echo missing)"
rm -rf "$ROOT"

echo "-- Test: --room, --tag, --status, --disposition and --slug each filter, and two filters AND together --"
fresh_root
write_record "root" "pending-one" "2026-01-01" "Pending one" "pending" "alpha"
write_record "approved" "accepted-one" "2026-01-02" "Accepted one" "accepted" "beta" "crafted" "some-story"
OUT_ROOM=$(bash "$LIST" --room=approved)
echo "$OUT_ROOM" | grep -q "^SLUG=2026-01-02-accepted-one$" && pass "--room filters to matching room" || fail "--room filters to matching room"
echo "$OUT_ROOM" | grep -q "^SLUG=2026-01-01-pending-one$" && fail "--room excludes non-matching room" "absent" "present" || pass "--room excludes non-matching room"

OUT_TAG=$(bash "$LIST" --tag=alpha)
echo "$OUT_TAG" | grep -q "^SLUG=2026-01-01-pending-one$" && pass "--tag filters to matching tag" || fail "--tag filters to matching tag"

OUT_STATUS=$(bash "$LIST" --status=accepted)
echo "$OUT_STATUS" | grep -q "^SLUG=2026-01-02-accepted-one$" && pass "--status filters to matching status" || fail "--status filters to matching status"

OUT_DISP=$(bash "$LIST" --disposition=crafted)
echo "$OUT_DISP" | grep -q "^SLUG=2026-01-02-accepted-one$" && pass "--disposition filters to matching disposition" || fail "--disposition filters to matching disposition"

OUT_SLUG=$(bash "$LIST" --slug=2026-01-01-pending-one)
COUNT_SLUG=$(echo "$OUT_SLUG" | grep -c "^SLUG=" || true)
[ "$COUNT_SLUG" -eq 1 ] && pass "--slug filters to exactly one record" || fail "--slug filters to exactly one record" "1" "$COUNT_SLUG"

OUT_AND=$(bash "$LIST" --room=root --tag=alpha)
COUNT_AND=$(echo "$OUT_AND" | grep -c "^SLUG=" || true)
[ "$COUNT_AND" -eq 1 ] && pass "two filters AND together (match)" || fail "two filters AND together (match)" "1" "$COUNT_AND"

OUT_AND_NONE=$(bash "$LIST" --room=archive --tag=alpha)
[ -z "$OUT_AND_NONE" ] && pass "two filters AND together (no match)" || fail "two filters AND together (no match)" "(empty)" "$OUT_AND_NONE"
rm -rf "$ROOT"

echo "-- Test: --tag=<a tag no record carries> prints nothing and exits 0 --"
fresh_root
write_record "root" "only-record" "2026-01-01" "Only record" "pending" "known-tag"
set +e
OUT=$(bash "$LIST" --tag=neverseen)
RC=$?
set -e
[ "$RC" -eq 0 ] && pass "unmatched tag exits 0" || fail "unmatched tag exits 0" "0" "$RC"
[ -z "$OUT" ] && pass "unmatched tag prints nothing" || fail "unmatched tag prints nothing" "(empty)" "$OUT"
rm -rf "$ROOT"

echo "-- Test: assets/ never appears in output --"
fresh_root
write_record "root" "real-record" "2026-01-01" "Real record" "pending" "tag-a"
mkdir -p "$ROOT/.craft/decisions/assets"
echo "not-a-record" > "$ROOT/.craft/decisions/assets/2026-01-01-decoy.md"
OUT=$(bash "$LIST")
COUNT=$(echo "$OUT" | grep -c "^SLUG=" || true)
[ "$COUNT" -eq 1 ] && pass "assets/ excluded from output" || fail "assets/ excluded from output" "1" "$COUNT"
echo "$OUT" | grep -q "decoy" && fail "no assets/ leakage" "absent" "present" || pass "no assets/ leakage"
rm -rf "$ROOT"

echo "-- Test: --no-scan returns the same SLUG and TAGS with DISPOSITION and STORIES empty --"
fresh_root
write_record "root" "scan-pending" "2026-01-01" "Scan pending" "pending" "alpha, beta"
write_record "approved" "scan-claimed" "2026-01-02" "Scan claimed" "accepted" "gamma"
write_record "approved" "scan-crafted" "2026-01-03" "Scan crafted" "accepted" "delta" "crafted" "shipping-story"
write_story "claiming-story" "planning" "2026-01-02-scan-claimed"
set +e
OUT_PLAIN=$(bash "$LIST")
RC_PLAIN=$?
OUT_NOSCAN=$(bash "$LIST" --no-scan)
RC_NOSCAN=$?
set -e
[ "$RC_NOSCAN" -eq 0 ] && pass "--no-scan exits 0" || fail "--no-scan exits 0" "0" "$RC_NOSCAN"

SLUGS_PLAIN=$(echo "$OUT_PLAIN" | grep "^SLUG=" | tr '\n' ',')
SLUGS_NOSCAN=$(echo "$OUT_NOSCAN" | grep "^SLUG=" | tr '\n' ',')
[ "$SLUGS_NOSCAN" = "$SLUGS_PLAIN" ] && pass "--no-scan returns the same SLUG values" || fail "--no-scan returns the same SLUG values" "$SLUGS_PLAIN" "$SLUGS_NOSCAN"

TAGS_PLAIN=$(echo "$OUT_PLAIN" | grep "^TAGS=" | tr '\n' ',')
TAGS_NOSCAN=$(echo "$OUT_NOSCAN" | grep "^TAGS=" | tr '\n' ',')
[ "$TAGS_NOSCAN" = "$TAGS_PLAIN" ] && pass "--no-scan returns the same TAGS values" || fail "--no-scan returns the same TAGS values" "$TAGS_PLAIN" "$TAGS_NOSCAN"

KEYS_NOSCAN=$(echo "$OUT_NOSCAN" | grep -v '^$' | sed -E 's/=.*$//' | tr '\n' ',')
EXPECTED_KEYS="FILE,ROOM,SLUG,DATE,TITLE,STATUS,TAGS,DISPOSITION,STORIES,FILE,ROOM,SLUG,DATE,TITLE,STATUS,TAGS,DISPOSITION,STORIES,FILE,ROOM,SLUG,DATE,TITLE,STATUS,TAGS,DISPOSITION,STORIES,"
[ "$KEYS_NOSCAN" = "$EXPECTED_KEYS" ] && pass "--no-scan still prints all nine keys in order on every block" || fail "--no-scan still prints all nine keys in order on every block" "$EXPECTED_KEYS" "$KEYS_NOSCAN"

BAD_DISP=$(echo "$OUT_NOSCAN" | grep "^DISPOSITION=" | grep -vc "^DISPOSITION=$" || true)
[ "$BAD_DISP" -eq 0 ] && pass "--no-scan leaves DISPOSITION empty on every block" || fail "--no-scan leaves DISPOSITION empty on every block" "0 non-empty" "$BAD_DISP non-empty"

BAD_STORIES=$(echo "$OUT_NOSCAN" | grep "^STORIES=" | grep -vc "^STORIES=$" || true)
[ "$BAD_STORIES" -eq 0 ] && pass "--no-scan leaves STORIES empty on every block" || fail "--no-scan leaves STORIES empty on every block" "0 non-empty" "$BAD_STORIES non-empty"

[ "$RC_PLAIN" -eq 0 ] && pass "the plain call still exits 0" || fail "the plain call still exits 0" "0" "$RC_PLAIN"
echo "$OUT_PLAIN" | grep -q "^DISPOSITION=claimed$" && pass "the plain call still derives claimed" || fail "the plain call still derives claimed" "DISPOSITION=claimed" "$(echo "$OUT_PLAIN" | grep '^DISPOSITION=' | tr '\n' ',')"
echo "$OUT_PLAIN" | grep -q "^STORIES=claiming-story$" && pass "the plain call still names the claiming story" || fail "the plain call still names the claiming story" "STORIES=claiming-story" "$(echo "$OUT_PLAIN" | grep '^STORIES=' | tr '\n' ',')"
echo "$OUT_PLAIN" | grep -q "^DISPOSITION=crafted$" && pass "the plain call still reads crafted from frontmatter" || fail "the plain call still reads crafted from frontmatter" "DISPOSITION=crafted" "$(echo "$OUT_PLAIN" | grep '^DISPOSITION=' | tr '\n' ',')"
rm -rf "$ROOT"

echo "=== decisions-capture.sh (Chunk 2) ==="
echo ""

echo "-- Test: a record with no approval lands in the root as pending --"
fresh_root
OUT=$(bash "$CAPTURE" "New pending idea" --tag=alpha --context="ctx body" --options="opts body" --decision="dec body" --consequences="cons body")
FILE=$(echo "$OUT" | tail -1)
[ -f "$FILE" ] && pass "capture writes a file" || fail "capture writes a file" "a file" "none"
DIRNAME=$(dirname "$FILE")
[ "$DIRNAME" = "$ROOT/.craft/decisions" ] && pass "record lands in the root" || fail "record lands in the root" "$ROOT/.craft/decisions" "$DIRNAME"
grep -q "^status: pending$" "$FILE" && pass "status: pending written" || fail "status: pending written" "status: pending" "$(grep '^status:' "$FILE" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: a record with an approval lands in approved/ as accepted with the quote rendered --"
fresh_root
OUT=$(bash "$CAPTURE" "New accepted idea" --tag=alpha --context="ctx body" --options="opts body" --decision="dec body" --consequences="cons body" --quote="the words, verbatim")
FILE=$(echo "$OUT" | tail -1)
DIRNAME=$(dirname "$FILE")
[ "$DIRNAME" = "$ROOT/.craft/decisions/approved" ] && pass "record lands in approved/" || fail "record lands in approved/" "$ROOT/.craft/decisions/approved" "$DIRNAME"
grep -q "^status: accepted$" "$FILE" && pass "status: accepted written" || fail "status: accepted written" "status: accepted" "$(grep '^status:' "$FILE" || echo missing)"
TODAY=$(date +%Y-%m-%d)
grep -qF "> \"the words, verbatim\" - $TODAY, session" "$FILE" && pass "quote rendered as quote, date, source" || fail "quote rendered as quote, date, source" "> \"the words, verbatim\" - $TODAY, session" "$(grep '^>' "$FILE" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: the approval line carries no name: --by= is rejected as unknown, store unchanged --"
fresh_root
set +e
ERR=$(bash "$CAPTURE" "Named attempt" --tag=alpha --context=c --options=o --decision=d --consequences=k --quote="the words" --by="Darin" 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "--by= is rejected as unknown" || fail "--by= is rejected as unknown" "non-zero" "$RC"
if [ -d "$ROOT/.craft/decisions" ]; then
  COUNT=$(find "$ROOT/.craft/decisions" -name "*.md" | wc -l | tr -d ' ')
else
  COUNT=0
fi
[ "$COUNT" -eq 0 ] && pass "store unchanged after rejected call" || fail "store unchanged after rejected call" "0" "$COUNT"
rm -rf "$ROOT"

echo "-- Test: the five section headings are written in record order --"
fresh_root
OUT=$(bash "$CAPTURE" "Heading order check" --tag=alpha --context="ctx body" --options="opts body" --decision="dec body" --consequences="cons body")
FILE=$(echo "$OUT" | tail -1)
HEADINGS=$(grep -E "^## " "$FILE" | tr '\n' ',')
EXPECTED="## Context,## Options considered,## Decision,## Consequences,## Approval,"
[ "$HEADINGS" = "$EXPECTED" ] && pass "five section headings in record order" || fail "five section headings in record order" "$EXPECTED" "$HEADINGS"
rm -rf "$ROOT"

echo "-- Test: the path is the last stdout line --"
fresh_root
OUT=$(bash "$CAPTURE" "Last line check" --tag=alpha --context=c --options=o --decision=d --consequences=k)
LAST=$(echo "$OUT" | tail -1)
[ -f "$LAST" ] && pass "last stdout line is the written path" || fail "last stdout line is the written path" "a file path" "$LAST"
rm -rf "$ROOT"

echo "-- Test: a second tag that exists on another record is accepted --"
fresh_root
write_record "root" "seed" "2026-01-01" "Seed" "pending" "known-tag"
OUT=$(bash "$CAPTURE" "Two tags" --tag=new-group --tag=known-tag --context=c --options=o --decision=d --consequences=k)
FILE=$(echo "$OUT" | tail -1)
grep -q "^tags: \[new-group, known-tag\]$" "$FILE" && pass "second tag accepted, both written" || fail "second tag accepted, both written" "tags: [new-group, known-tag]" "$(grep '^tags:' "$FILE" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: a second tag that exists nowhere exits non-zero naming the tag, and writes nothing --"
fresh_root
write_record "root" "seed2" "2026-01-01" "Seed 2" "pending" "known-tag"
set +e
ERR=$(bash "$CAPTURE" "Bad tags" --tag=new-group --tag=neverseen --context=c --options=o --decision=d --consequences=k 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "second unseen tag exits non-zero" || fail "second unseen tag exits non-zero" "non-zero" "$RC"
echo "$ERR" | grep -q "neverseen" && pass "error names the tag" || fail "error names the tag" "neverseen" "$ERR"
COUNT=$(find "$ROOT/.craft/decisions" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -eq 1 ] && pass "no new file written" || fail "no new file written" "1" "$COUNT"
rm -rf "$ROOT"

echo "-- Test: reopen rewrites the body in place at the same filename, date and status --"
fresh_root
write_record "approved" "reopen-target" "2026-02-01" "Reopen target" "accepted" "reopen-tag"
BEFORE_FILE="$ROOT/.craft/decisions/approved/2026-02-01-reopen-target.md"
OUT=$(bash "$CAPTURE" --reopen=2026-02-01-reopen-target --context="new ctx" --options="new opts" --decision="new dec" --consequences="new cons" --quote="reopen words")
FILE=$(echo "$OUT" | tail -1)
[ "$FILE" = "$BEFORE_FILE" ] && pass "reopen keeps the same filename" || fail "reopen keeps the same filename" "$BEFORE_FILE" "$FILE"
grep -q "^created: 2026-02-01$" "$FILE" && pass "reopen leaves created: untouched" || fail "reopen leaves created: untouched" "created: 2026-02-01" "$(grep '^created:' "$FILE" || echo missing)"
grep -q "^status: accepted$" "$FILE" && pass "reopen leaves status: untouched" || fail "reopen leaves status: untouched" "status: accepted" "$(grep '^status:' "$FILE" || echo missing)"
grep -qF "new dec" "$FILE" && pass "reopen rewrites the body" || fail "reopen rewrites the body" "new dec" "$(cat "$FILE")"
rm -rf "$ROOT"

echo "-- Test: reopen appends a Reopen line and leaves the original approval line intact --"
fresh_root
write_record "approved" "reopen-approval" "2026-02-02" "Reopen approval" "accepted" "reopen-tag"
FILE_PRE="$ROOT/.craft/decisions/approved/2026-02-02-reopen-approval.md"
ORIGINAL_LINE=$(grep '^> "approved"' "$FILE_PRE")
OUT=$(bash "$CAPTURE" --reopen=2026-02-02-reopen-approval --context=c --options=o --decision=d --consequences=k --quote="new words")
FILE=$(echo "$OUT" | tail -1)
grep -qF "$ORIGINAL_LINE" "$FILE" && pass "original approval line intact" || fail "original approval line intact" "$ORIGINAL_LINE" "$(cat "$FILE")"
grep -q '^> Reopen: "new words"' "$FILE" && pass "Reopen line appended" || fail "Reopen line appended" "> Reopen: \"new words\" - ..." "$(grep '^> Reopen' "$FILE" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: reopen on a claimed record prints one Claimed: line per claiming story, before the path --"
fresh_root
write_record "approved" "claimed-reopen" "2026-02-03" "Claimed reopen" "accepted" "reopen-tag"
write_story "claiming-story-a" "planning" "2026-02-03-claimed-reopen"
OUT=$(bash "$CAPTURE" --reopen=2026-02-03-claimed-reopen --context=c --options=o --decision=d --consequences=k --quote="new words")
LAST=$(echo "$OUT" | tail -1)
FIRST_LINE=$(echo "$OUT" | head -1)
[ "$FIRST_LINE" = "Claimed: claiming-story-a" ] && pass "Claimed: line printed before the path" || fail "Claimed: line printed before the path" "Claimed: claiming-story-a" "$FIRST_LINE"
[ -f "$LAST" ] && pass "path is still the last line on a claimed reopen" || fail "path is still the last line on a claimed reopen" "a file path" "$LAST"
rm -rf "$ROOT"

echo "-- Test: reopen on a crafted record writes nothing, names the shipping story, exits non-zero --"
fresh_root
write_record "approved" "crafted-reopen" "2026-02-04" "Crafted reopen" "accepted" "reopen-tag" "crafted" "shipping-story"
FILE="$ROOT/.craft/decisions/approved/2026-02-04-crafted-reopen.md"
BEFORE=$(cat "$FILE")
set +e
ERR=$(bash "$CAPTURE" --reopen=2026-02-04-crafted-reopen --context=c --options=o --decision=d --consequences=k --quote="new words" 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "reopen on a crafted record exits non-zero" || fail "reopen on a crafted record exits non-zero" "non-zero" "$RC"
echo "$ERR" | grep -q "shipping-story" && pass "error names the shipping story" || fail "error names the shipping story" "shipping-story" "$ERR"
AFTER=$(cat "$FILE")
[ "$BEFORE" = "$AFTER" ] && pass "crafted record is byte-identical after the refused reopen" || fail "crafted record is byte-identical after the refused reopen" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: capture never touches a story file --"
fresh_root
write_record "approved" "story-touch-check" "2026-02-05" "Story touch check" "accepted" "reopen-tag"
write_story "bystander-story" "planning" "2026-02-05-story-touch-check"
STORY_FILE="$ROOT/.craft/cycles/1-test/stories/bystander-story.md"
BEFORE_CONTENT=$(cat "$STORY_FILE")
bash "$CAPTURE" --reopen=2026-02-05-story-touch-check --context=c --options=o --decision=d --consequences=k --quote="new words" >/dev/null
AFTER_CONTENT=$(cat "$STORY_FILE")
[ "$BEFORE_CONTENT" = "$AFTER_CONTENT" ] && pass "story file untouched by capture" || fail "story file untouched by capture" "unchanged" "changed"
rm -rf "$ROOT"

echo "=== decisions-capture.sh --dry-run and cross-room collisions (Chunk 1) ==="
echo ""

echo "-- Test: dry-run body is capture's file byte for byte --"
fresh_root
OUT_DRY=$(bash "$CAPTURE" "Dry run matches file" --tag=alpha --context="ctx body" --options="opts body" --decision="dec body" --consequences="cons body" --quote="approve words" --dry-run)
OUT_REAL=$(bash "$CAPTURE" "Dry run matches file" --tag=alpha --context="ctx body" --options="opts body" --decision="dec body" --consequences="cons body" --quote="approve words")
REAL_FILE=$(echo "$OUT_REAL" | tail -1)
DRY_LINE1=$(echo "$OUT_DRY" | head -1)
EXPECTED_SLUG_LINE="SLUG=$(basename "$REAL_FILE" .md)"
[ "$DRY_LINE1" = "$EXPECTED_SLUG_LINE" ] && pass "dry-run line 1 is SLUG= matching the real basename" || fail "dry-run line 1 is SLUG= matching the real basename" "$EXPECTED_SLUG_LINE" "$DRY_LINE1"
DRY_BODY=$(echo "$OUT_DRY" | tail -n +2)
REAL_BODY=$(cat "$REAL_FILE")
[ "$DRY_BODY" = "$REAL_BODY" ] && pass "dry-run body equals the real file byte for byte" || fail "dry-run body equals the real file byte for byte" "$REAL_BODY" "$DRY_BODY"
rm -rf "$ROOT"

echo "-- Test: dry-run creates no file and no room directory --"
fresh_root
bash "$CAPTURE" "Dry run writes nothing" --tag=alpha --context=c --options=o --decision=d --consequences=k --quote="a" --dry-run >/dev/null
[ ! -d "$ROOT/.craft/decisions" ] && pass "dry-run: .craft/decisions still absent" || fail "dry-run: .craft/decisions still absent" "absent" "present"
[ ! -d "$ROOT/.craft/decisions/approved" ] && pass "dry-run: .craft/decisions/approved still absent" || fail "dry-run: .craft/decisions/approved still absent" "absent" "present"
rm -rf "$ROOT"

echo "-- Test: the same title yields the same slug with and without --quote= --"
fresh_root
write_record "root" "collide-me" "2026-04-01" "Collide me" "pending" "tag-a"
OUT=$(bash "$CAPTURE" "Collide me" --tag=tag-a --context=c --options=o --decision=d --consequences=k --quote="a" --dry-run --created=2026-04-01)
SLUG=$(echo "$OUT" | head -1)
echo "$SLUG" | grep -q -- "-2$" && pass "collision loop sees the root from the approved side" || fail "collision loop sees the root from the approved side" "SLUG=...-2" "$SLUG"
rm -rf "$ROOT"

echo "-- Test: the collision loop sees approved/ from the root side too --"
fresh_root
write_record "approved" "collide-me-2" "2026-04-02" "Collide me 2" "accepted" "tag-a"
OUT=$(bash "$CAPTURE" "Collide me 2" --tag=tag-a --context=c --options=o --decision=d --consequences=k --dry-run --created=2026-04-02)
SLUG=$(echo "$OUT" | head -1)
echo "$SLUG" | grep -q -- "-2$" && pass "collision loop sees approved/ from the root side" || fail "collision loop sees approved/ from the root side" "SLUG=...-2" "$SLUG"
rm -rf "$ROOT"

echo "-- Test: dry-run reports the pending room when no quote is given --"
fresh_root
OUT=$(bash "$CAPTURE" "Dry run pending room" --tag=alpha --context=c --options=o --decision=d --consequences=k --dry-run)
echo "$OUT" | grep -q "^status: pending$" && pass "dry-run body carries status: pending with no quote" || fail "dry-run body carries status: pending with no quote" "status: pending" "$OUT"
echo "$OUT" | grep -q '^> "' && fail "dry-run body has no approval quote line with no quote" "(none)" "$OUT" || pass "dry-run body has no approval quote line with no quote"
rm -rf "$ROOT"

echo "-- Test: dry-run enforces every required flag --"
fresh_root
set +e
ERR=$(bash "$CAPTURE" "Missing decision" --tag=alpha --context=c --options=o --consequences=k --dry-run 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "dry-run enforces --decision=" || fail "dry-run enforces --decision=" "non-zero" "$RC"
echo "$ERR" | grep -qi "decision" && pass "dry-run's error names --decision" || fail "dry-run's error names --decision" "mentions decision" "$ERR"
rm -rf "$ROOT"

echo "-- Test: dry-run enforces the additional-tag rule --"
fresh_root
set +e
ERR=$(bash "$CAPTURE" "Dry run bad tag" --tag=new-group --tag=neverseen --context=c --options=o --decision=d --consequences=k --dry-run 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "dry-run enforces the additional-tag rule" || fail "dry-run enforces the additional-tag rule" "non-zero" "$RC"
echo "$ERR" | grep -q "neverseen" && pass "dry-run's tag error names the tag" || fail "dry-run's tag error names the tag" "neverseen" "$ERR"
[ ! -d "$ROOT/.craft/decisions" ] && pass "dry-run's tag error writes nothing" || fail "dry-run's tag error writes nothing" "absent" "present"
rm -rf "$ROOT"

echo "-- Test: --dry-run with --reopen= is refused and the target file is unchanged --"
fresh_root
write_record "approved" "dry-reopen-refused" "2026-04-03" "Dry reopen refused" "accepted" "tag-a"
FILE="$ROOT/.craft/decisions/approved/2026-04-03-dry-reopen-refused.md"
BEFORE=$(cat "$FILE")
set +e
ERR=$(bash "$CAPTURE" --reopen=2026-04-03-dry-reopen-refused --context=c --options=o --decision=d --consequences=k --quote="x" --dry-run 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "--dry-run with --reopen= is refused" || fail "--dry-run with --reopen= is refused" "non-zero" "$RC"
echo "$ERR" | grep -qi "dry-run" && echo "$ERR" | grep -qi "reopen" && pass "the refusal names both flags" || fail "the refusal names both flags" "mentions dry-run and reopen" "$ERR"
AFTER=$(cat "$FILE")
[ "$BEFORE" = "$AFTER" ] && pass "--dry-run --reopen= leaves the target file byte-identical" || fail "--dry-run --reopen= leaves the target file byte-identical" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: unknown flags remain a hard error alongside --dry-run --"
fresh_root
set +e
ERR=$(bash "$CAPTURE" "Unknown flag check" --tag=alpha --context=c --options=o --decision=d --consequences=k --dry-run --nope=1 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "unknown flag alongside --dry-run is a hard error" || fail "unknown flag alongside --dry-run is a hard error" "non-zero" "$RC"
rm -rf "$ROOT"

echo "-- Test: reopen in approved/ is unchanged --"
fresh_root
write_record "approved" "reopen-approved-unchanged" "2026-04-04" "Reopen approved unchanged" "accepted" "tag-a"
OUT=$(bash "$CAPTURE" --reopen=2026-04-04-reopen-approved-unchanged --context=c --options=o --decision="new dec" --consequences=k --quote="new words")
FILE=$(echo "$OUT" | tail -1)
[ "$FILE" = "$ROOT/.craft/decisions/approved/2026-04-04-reopen-approved-unchanged.md" ] && pass "reopen in approved/ keeps the same file" || fail "reopen in approved/ keeps the same file" "same path" "$FILE"
grep -q '^> Reopen: "new words"' "$FILE" && pass "reopen in approved/ still appends the Reopen line" || fail "reopen in approved/ still appends the Reopen line" "> Reopen: \"new words\" ..." "$(grep '^> Reopen' "$FILE" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: reopen in the root is a reshape --"
fresh_root
PARK_OUT=$(bash "$CAPTURE" "Parked proposal" --tag=tag-a --context="orig ctx" --options="orig opts" --decision="orig dec" --consequences="orig cons")
PARK_FILE=$(echo "$PARK_OUT" | tail -1)
PARK_SLUG=$(basename "$PARK_FILE" .md)
RESHAPE_OUT=$(bash "$CAPTURE" --reopen="$PARK_SLUG" --context="new ctx" --options="new opts" --decision="new dec" --consequences="new cons")
RESHAPE_FILE=$(echo "$RESHAPE_OUT" | tail -1)
[ "$RESHAPE_FILE" = "$PARK_FILE" ] && pass "root reshape leaves the record in the root" || fail "root reshape leaves the record in the root" "$PARK_FILE" "$RESHAPE_FILE"
grep -qF "new dec" "$RESHAPE_FILE" && pass "root reshape rewrites the body" || fail "root reshape rewrites the body" "new dec" "$(cat "$RESHAPE_FILE")"
grep -q "^status: pending$" "$RESHAPE_FILE" && pass "root reshape leaves status: pending intact" || fail "root reshape leaves status: pending intact" "status: pending" "$(grep '^status:' "$RESHAPE_FILE" || echo missing)"
grep -q "^> Reopen:" "$RESHAPE_FILE" && fail "root reshape writes no Reopen line" "(none)" "$(cat "$RESHAPE_FILE")" || pass "root reshape writes no Reopen line"
ACCEPT_OUT=$(bash "$TRANSITION" "$PARK_SLUG" accept --quote="a")
ACCEPTED_FILE=$(echo "$ACCEPT_OUT" | tail -1)
grep -qF "new dec" "$ACCEPTED_FILE" && pass "accept after reshape carries the changed Decision" || fail "accept after reshape carries the changed Decision" "new dec" "$(cat "$ACCEPTED_FILE")"
APPROVAL_COUNT=$(grep -c '^> "' "$ACCEPTED_FILE" || true)
[ "$APPROVAL_COUNT" -eq 1 ] && pass "accept after reshape writes exactly one approval line" || fail "accept after reshape writes exactly one approval line" "1" "$APPROVAL_COUNT"
rm -rf "$ROOT"

echo "-- Test: reopen in the root refuses --quote= --"
fresh_root
PARK_OUT=$(bash "$CAPTURE" "Parked with quote attempt" --tag=tag-a --context=c --options=o --decision=d --consequences=k)
PARK_FILE=$(echo "$PARK_OUT" | tail -1)
PARK_SLUG=$(basename "$PARK_FILE" .md)
BEFORE=$(cat "$PARK_FILE")
set +e
ERR=$(bash "$CAPTURE" --reopen="$PARK_SLUG" --context=c --options=o --decision="attempted dec" --consequences=k --quote="not allowed" 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "reopen in the root refuses --quote=" || fail "reopen in the root refuses --quote=" "non-zero" "$RC"
AFTER=$(cat "$PARK_FILE")
[ "$BEFORE" = "$AFTER" ] && pass "reopen in the root refusing --quote= leaves the file byte-identical" || fail "reopen in the root refusing --quote= leaves the file byte-identical" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: reopen in archive/ is refused --"
fresh_root
write_record "archive" "reopen-archive-refused" "2026-04-05" "Reopen archive refused" "declined" "tag-a"
FILE="$ROOT/.craft/decisions/archive/2026-04-05-reopen-archive-refused.md"
BEFORE=$(cat "$FILE")
set +e
ERR=$(bash "$CAPTURE" --reopen=2026-04-05-reopen-archive-refused --context=c --options=o --decision=d --consequences=k --quote="x" 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "reopen in archive/ is refused" || fail "reopen in archive/ is refused" "non-zero" "$RC"
AFTER=$(cat "$FILE")
[ "$BEFORE" = "$AFTER" ] && pass "reopen in archive/ leaves the file byte-identical" || fail "reopen in archive/ leaves the file byte-identical" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: deprecate refuses crafted law and names the shipping story --"
fresh_root
write_record "approved" "deprecate-crafted" "2026-04-06" "Deprecate crafted" "accepted" "tag-a" "crafted" "shipping-story"
FILE="$ROOT/.craft/decisions/approved/2026-04-06-deprecate-crafted.md"
BEFORE=$(cat "$FILE")
set +e
ERR=$(bash "$TRANSITION" 2026-04-06-deprecate-crafted deprecate --quote="x" 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "deprecate refuses crafted law" || fail "deprecate refuses crafted law" "non-zero" "$RC"
echo "$ERR" | grep -q "shipping-story" && pass "deprecate's refusal names the shipping story" || fail "deprecate's refusal names the shipping story" "shipping-story" "$ERR"
AFTER=$(cat "$FILE")
[ "$BEFORE" = "$AFTER" ] && pass "deprecate's refusal leaves the crafted record byte-identical" || fail "deprecate's refusal leaves the crafted record byte-identical" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: deprecate still retires claimed law --"
fresh_root
write_record "approved" "deprecate-claimed" "2026-04-07" "Deprecate claimed" "accepted" "tag-a"
write_story "claiming-story-d" "planning" "2026-04-07-deprecate-claimed"
OUT=$(bash "$TRANSITION" 2026-04-07-deprecate-claimed deprecate --quote="x")
DEST="$ROOT/.craft/decisions/archive/2026-04-07-deprecate-claimed.md"
[ -f "$DEST" ] && pass "deprecate still retires claimed law" || fail "deprecate still retires claimed law" "present" "missing"
grep -q "^status: deprecated$" "$DEST" && pass "deprecate on claimed law writes status: deprecated" || fail "deprecate on claimed law writes status: deprecated" "status: deprecated" "$(grep '^status:' "$DEST" || echo missing)"
rm -rf "$ROOT"

echo "=== decisions-transition.sh (Chunk 3) ==="
echo ""

echo "-- Test: accept moves a pending root record into approved/ with status accepted and the quote appended --"
fresh_root
write_record "root" "accept-me" "2026-03-01" "Accept me" "pending" "tag-a"
SRC="$ROOT/.craft/decisions/2026-03-01-accept-me.md"
OUT=$(bash "$TRANSITION" 2026-03-01-accept-me accept --quote="accept words")
DEST="$ROOT/.craft/decisions/approved/2026-03-01-accept-me.md"
LAST=$(echo "$OUT" | tail -1)
[ "$LAST" = "$DEST" ] && pass "accept: path is the destination file" || fail "accept: path is the destination file" "$DEST" "$LAST"
[ -f "$DEST" ] && pass "accept: record present in approved/" || fail "accept: record present in approved/" "exists" "missing"
[ ! -f "$SRC" ] && pass "accept: record no longer in root" || fail "accept: record no longer in root" "removed" "still present"
grep -q "^status: accepted$" "$DEST" && pass "accept: status accepted" || fail "accept: status accepted" "status: accepted" "$(grep '^status:' "$DEST" || echo missing)"
grep -qF '> "accept words"' "$DEST" && pass "accept: quote appended" || fail "accept: quote appended" "> \"accept words\" ..." "$(grep '^>' "$DEST" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: accept without --quote exits non-zero and leaves the record in the root --"
fresh_root
write_record "root" "no-quote" "2026-03-02" "No quote" "pending" "tag-a"
SRC="$ROOT/.craft/decisions/2026-03-02-no-quote.md"
BEFORE=$(cat "$SRC")
set +e
ERR=$(bash "$TRANSITION" 2026-03-02-no-quote accept 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "accept without --quote exits non-zero" || fail "accept without --quote exits non-zero" "non-zero" "$RC"
[ -f "$SRC" ] && pass "accept without --quote leaves the record in root" || fail "accept without --quote leaves the record in root" "present" "missing"
AFTER=$(cat "$SRC")
[ "$BEFORE" = "$AFTER" ] && pass "accept without --quote leaves the record byte-identical" || fail "accept without --quote leaves the record byte-identical" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: decline moves a pending root record into archive/ with status declined --"
fresh_root
write_record "root" "decline-me" "2026-03-03" "Decline me" "pending" "tag-a"
OUT=$(bash "$TRANSITION" 2026-03-03-decline-me decline --quote="decline words")
DEST="$ROOT/.craft/decisions/archive/2026-03-03-decline-me.md"
[ -f "$DEST" ] && pass "decline: record present in archive/" || fail "decline: record present in archive/" "exists" "missing"
grep -q "^status: declined$" "$DEST" && pass "decline: status declined" || fail "decline: status declined" "status: declined" "$(grep '^status:' "$DEST" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: deprecate moves an approved record into archive/ with status deprecated --"
fresh_root
write_record "approved" "deprecate-me" "2026-03-04" "Deprecate me" "accepted" "tag-a"
OUT=$(bash "$TRANSITION" 2026-03-04-deprecate-me deprecate --quote="deprecate words")
DEST="$ROOT/.craft/decisions/archive/2026-03-04-deprecate-me.md"
[ -f "$DEST" ] && pass "deprecate: record present in archive/" || fail "deprecate: record present in archive/" "exists" "missing"
grep -q "^status: deprecated$" "$DEST" && pass "deprecate: status deprecated" || fail "deprecate: status deprecated" "status: deprecated" "$(grep '^status:' "$DEST" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: deprecate on a pending record exits non-zero with a wrong-status message --"
fresh_root
write_record "root" "still-pending" "2026-03-05" "Still pending" "pending" "tag-a"
set +e
ERR=$(bash "$TRANSITION" 2026-03-05-still-pending deprecate --quote="x" 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "deprecate on a pending record exits non-zero" || fail "deprecate on a pending record exits non-zero" "non-zero" "$RC"
echo "$ERR" | grep -qi "pending" && pass "deprecate on a pending record names the wrong status" || fail "deprecate on a pending record names the wrong status" "mentions pending" "$ERR"
rm -rf "$ROOT"

echo "-- Test: craft writes disposition: crafted and appends the story to stories: in one act, without moving the file --"
fresh_root
write_record "approved" "craft-me" "2026-03-06" "Craft me" "accepted" "tag-a"
FILE="$ROOT/.craft/decisions/approved/2026-03-06-craft-me.md"
OUT=$(bash "$TRANSITION" 2026-03-06-craft-me craft --story=story-one)
LAST=$(echo "$OUT" | tail -1)
[ "$LAST" = "$FILE" ] && pass "craft: path unchanged (no move)" || fail "craft: path unchanged (no move)" "$FILE" "$LAST"
grep -q "^disposition: crafted$" "$FILE" && pass "craft: disposition: crafted written" || fail "craft: disposition: crafted written" "disposition: crafted" "$(grep '^disposition:' "$FILE" || echo missing)"
grep -q "^stories: \[story-one\]$" "$FILE" && pass "craft: stories: appended" || fail "craft: stories: appended" "stories: [story-one]" "$(grep '^stories:' "$FILE" || echo missing)"
echo "$OUT" | grep -q "^CHANGED=1$" && pass "craft: first flip emits CHANGED=1" || fail "craft: first flip emits CHANGED=1" "CHANGED=1" "$(echo "$OUT" | grep '^CHANGED=' || echo missing)"
rm -rf "$ROOT"

echo "-- Test: craft inserts disposition: and stories: directly after tags: when both are absent --"
fresh_root
write_record "approved" "insert-order" "2026-03-07" "Insert order" "accepted" "tag-a"
FILE="$ROOT/.craft/decisions/approved/2026-03-07-insert-order.md"
bash "$TRANSITION" 2026-03-07-insert-order craft --story=story-two >/dev/null
FIELDS=$(sed -n '/^---$/,/^---$/p' "$FILE" | sed -E 's/^([a-z]+):.*$/\1/' | grep -v '^---$')
EXPECTED=$(printf 'type\nstatus\ncreated\nsource\ntags\ndisposition\nstories')
[ "$FIELDS" = "$EXPECTED" ] && pass "craft inserts disposition/stories right after tags" || fail "craft inserts disposition/stories right after tags" "$EXPECTED" "$FIELDS"
rm -rf "$ROOT"

echo "-- Test: craft on an already-crafted record appends a second story, emits CHANGED=0, exits 0, and does not duplicate an existing story name --"
fresh_root
write_record "approved" "already-crafted-t" "2026-03-08" "Already crafted t" "accepted" "tag-a" "crafted" "story-one"
FILE="$ROOT/.craft/decisions/approved/2026-03-08-already-crafted-t.md"
OUT=$(bash "$TRANSITION" 2026-03-08-already-crafted-t craft --story=story-two)
echo "$OUT" | grep -q "^CHANGED=0$" && pass "already-crafted second story: CHANGED=0" || fail "already-crafted second story: CHANGED=0" "CHANGED=0" "$(echo "$OUT" | grep '^CHANGED=' || echo missing)"
grep -q "^stories: \[story-one, story-two\]$" "$FILE" && pass "already-crafted second story: both stories present" || fail "already-crafted second story: both stories present" "stories: [story-one, story-two]" "$(grep '^stories:' "$FILE" || echo missing)"
set +e
RC=0
bash "$TRANSITION" 2026-03-08-already-crafted-t craft --story=story-two >/dev/null 2>&1
RC=$?
set -e
[ "$RC" -eq 0 ] && pass "already-crafted repeat call still exits 0" || fail "already-crafted repeat call still exits 0" "0" "$RC"
DUP=$(grep '^stories:' "$FILE")
[ "$DUP" = "stories: [story-one, story-two]" ] && pass "already-crafted: repeating an existing story does not duplicate it" || fail "already-crafted: repeating an existing story does not duplicate it" "stories: [story-one, story-two]" "$DUP"
rm -rf "$ROOT"

echo "-- Test: craft on a pending record exits non-zero with a still-pending message distinct from the not-found message --"
fresh_root
write_record "root" "craft-pending" "2026-03-09" "Craft pending" "pending" "tag-a"
set +e
ERR_PENDING=$(bash "$TRANSITION" 2026-03-09-craft-pending craft --story=x 2>&1 1>/dev/null)
RC_PENDING=$?
ERR_NOTFOUND=$(bash "$TRANSITION" 2026-01-01-does-not-exist craft --story=x 2>&1 1>/dev/null)
RC_NOTFOUND=$?
set -e
[ "$RC_PENDING" -ne 0 ] && pass "craft on a pending record exits non-zero" || fail "craft on a pending record exits non-zero" "non-zero" "$RC_PENDING"
[ "$RC_NOTFOUND" -ne 0 ] && pass "craft on an unknown slug exits non-zero" || fail "craft on an unknown slug exits non-zero" "non-zero" "$RC_NOTFOUND"
[ "$ERR_PENDING" != "$ERR_NOTFOUND" ] && pass "still-pending message differs from not-found message" || fail "still-pending message differs from not-found message" "distinct" "identical: $ERR_PENDING"
rm -rf "$ROOT"

echo "-- Test: craft on an archived record exits non-zero with an archived message --"
fresh_root
write_record "archive" "craft-archived" "2026-03-10" "Craft archived" "declined" "tag-a"
set +e
ERR=$(bash "$TRANSITION" 2026-03-10-craft-archived craft --story=x 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "craft on an archived record exits non-zero" || fail "craft on an archived record exits non-zero" "non-zero" "$RC"
echo "$ERR" | grep -qi "archive" && pass "craft on an archived record names archive" || fail "craft on an archived record names archive" "mentions archive" "$ERR"
rm -rf "$ROOT"

echo "-- Test: an unknown slug exits non-zero naming the slug --"
fresh_root
set +e
ERR=$(bash "$TRANSITION" 2099-01-01-nonexistent-slug accept --quote="x" 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "unknown slug exits non-zero" || fail "unknown slug exits non-zero" "non-zero" "$RC"
echo "$ERR" | grep -q "2099-01-01-nonexistent-slug" && pass "unknown slug error names the slug" || fail "unknown slug error names the slug" "2099-01-01-nonexistent-slug" "$ERR"
rm -rf "$ROOT"

echo "-- Test: every success prints TITLE=, CHANGED=, and the path last --"
fresh_root
write_record "root" "stdout-shape" "2026-03-11" "Stdout shape" "pending" "tag-a"
OUT=$(bash "$TRANSITION" 2026-03-11-stdout-shape accept --quote="x")
LINES=$(echo "$OUT" | wc -l | tr -d ' ')
LINE1=$(echo "$OUT" | sed -n '1p')
LINE2=$(echo "$OUT" | sed -n '2p')
LINE3=$(echo "$OUT" | sed -n '3p')
echo "$LINE1" | grep -q "^TITLE=Stdout shape$" && pass "stdout: TITLE= first" || fail "stdout: TITLE= first" "TITLE=Stdout shape" "$LINE1"
echo "$LINE2" | grep -q "^CHANGED=" && pass "stdout: CHANGED= second" || fail "stdout: CHANGED= second" "CHANGED=..." "$LINE2"
[ -f "$LINE3" ] && pass "stdout: path is the last line" || fail "stdout: path is the last line" "a file path" "$LINE3"
[ "$LINES" -eq 3 ] && pass "stdout: exactly three lines" || fail "stdout: exactly three lines" "3" "$LINES"
rm -rf "$ROOT"

echo "-- Test: a record whose body quotes status: in prose is not corrupted by any transition --"
fresh_root
write_record "root" "fence-trap-t" "2026-03-12" "Fence trap t" "pending" "tag-a" "" "" \
  "status: pending | accepted | declined - the enum, quoted here on purpose."
FILE_SRC="$ROOT/.craft/decisions/2026-03-12-fence-trap-t.md"
OUT=$(bash "$TRANSITION" 2026-03-12-fence-trap-t accept --quote="x")
DEST="$ROOT/.craft/decisions/approved/2026-03-12-fence-trap-t.md"
grep -q "^status: accepted$" "$DEST" && pass "fence trap: frontmatter status flipped correctly" || fail "fence trap: frontmatter status flipped correctly" "status: accepted" "$(grep '^status:' "$DEST" || echo missing)"
grep -qF "status: pending | accepted | declined - the enum, quoted here on purpose." "$DEST" && pass "fence trap: body prose line survives untouched" || fail "fence trap: body prose line survives untouched" "prose line present" "$(cat "$DEST")"
rm -rf "$ROOT"

echo "-- Test: accept into an unwritable approved/ exits non-zero and leaves the root record byte-identical --"
fresh_root
write_record "root" "unwritable-dest" "2026-03-13" "Unwritable dest" "pending" "tag-a"
SRC="$ROOT/.craft/decisions/2026-03-13-unwritable-dest.md"
BEFORE=$(cat "$SRC")
mkdir -p "$ROOT/.craft/decisions/approved"
chmod 000 "$ROOT/.craft/decisions/approved"
set +e
ERR=$(bash "$TRANSITION" 2026-03-13-unwritable-dest accept --quote="x" 2>&1 1>/dev/null)
RC=$?
set -e
chmod 755 "$ROOT/.craft/decisions/approved"
[ "$RC" -ne 0 ] && pass "unwritable destination exits non-zero" || fail "unwritable destination exits non-zero" "non-zero" "$RC"
[ -f "$SRC" ] && pass "unwritable destination leaves the source in place" || fail "unwritable destination leaves the source in place" "present" "missing"
AFTER=$(cat "$SRC")
[ "$BEFORE" = "$AFTER" ] && pass "unwritable destination leaves the source byte-identical" || fail "unwritable destination leaves the source byte-identical" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: a slug found in two rooms exits non-zero naming both rooms --"
fresh_root
write_record "root" "double-room" "2026-03-14" "Double room" "pending" "tag-a"
write_record "approved" "double-room" "2026-03-14" "Double room" "accepted" "tag-a"
set +e
ERR=$(bash "$TRANSITION" 2026-03-14-double-room accept --quote="x" 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "slug in two rooms exits non-zero" || fail "slug in two rooms exits non-zero" "non-zero" "$RC"
echo "$ERR" | grep -q "root" && echo "$ERR" | grep -q "approved" && pass "slug in two rooms names both rooms" || fail "slug in two rooms names both rooms" "mentions root and approved" "$ERR"
rm -rf "$ROOT"

echo "=== decisions-transition.sh retag ==="
echo ""

echo "-- Test: retag with one good and one unknown record writes nothing and leaves the good record byte-identical --"
fresh_root
write_record "root" "good-one" "2026-04-01" "Good one" "pending" "old-tag"
GOOD="$ROOT/.craft/decisions/2026-04-01-good-one.md"
BEFORE=$(cat "$GOOD")
set +e
ERR=$(bash "$TRANSITION" "2026-04-01-good-one,2026-04-01-nope" retag --tag=new-tag 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "retag all-or-nothing: exits non-zero" || fail "retag all-or-nothing: exits non-zero" "non-zero" "$RC"
echo "$ERR" | grep -q "2026-04-01-nope" && pass "retag all-or-nothing: stderr names the unknown slug" || fail "retag all-or-nothing: stderr names the unknown slug" "2026-04-01-nope" "$ERR"
AFTER=$(cat "$GOOD")
[ "$BEFORE" = "$AFTER" ] && pass "retag all-or-nothing: good record byte-identical" || fail "retag all-or-nothing: good record byte-identical" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: retag sets tags: to exactly the target and prints the path as the last stdout line --"
fresh_root
write_record "root" "single-move" "2026-04-02" "Single move" "pending" "old-tag"
FILE="$ROOT/.craft/decisions/2026-04-02-single-move.md"
set +e
OUT=$(bash "$TRANSITION" 2026-04-02-single-move retag --tag=new-tag)
RC=$?
set -e
[ "$RC" -eq 0 ] && pass "retag single: exits 0" || fail "retag single: exits 0" "0" "$RC"
grep -q "^tags: \[new-tag\]$" "$FILE" && pass "retag single: tags: rewritten to exactly the target" || fail "retag single: tags: rewritten to exactly the target" "tags: [new-tag]" "$(grep '^tags:' "$FILE" || echo missing)"
echo "$OUT" | tail -1 | grep -qF "$FILE" && pass "retag single: last stdout line is the path" || fail "retag single: last stdout line is the path" "$FILE" "$(echo "$OUT" | tail -1)"
rm -rf "$ROOT"

echo "-- Test: retag on three comma-separated slugs moves all three and prints three path lines --"
fresh_root
write_record "root" "multi-a" "2026-04-03" "Multi a" "pending" "old-tag"
write_record "root" "multi-b" "2026-04-03" "Multi b" "pending" "old-tag"
write_record "approved" "multi-c" "2026-04-03" "Multi c" "accepted" "old-tag"
OUT=$(bash "$TRANSITION" "2026-04-03-multi-a,2026-04-03-multi-b,2026-04-03-multi-c" retag --tag=new-tag)
echo "$OUT" | grep -q "^MOVED=3$" && pass "retag multi: MOVED=3" || fail "retag multi: MOVED=3" "MOVED=3" "$OUT"
PATH_COUNT=$(echo "$OUT" | grep -c "^$ROOT" || true)
[ "$PATH_COUNT" -eq 3 ] && pass "retag multi: three path lines" || fail "retag multi: three path lines" "3" "$PATH_COUNT"
grep -q "^tags: \[new-tag\]$" "$ROOT/.craft/decisions/2026-04-03-multi-a.md" && \
  grep -q "^tags: \[new-tag\]$" "$ROOT/.craft/decisions/2026-04-03-multi-b.md" && \
  grep -q "^tags: \[new-tag\]$" "$ROOT/.craft/decisions/approved/2026-04-03-multi-c.md" && \
  pass "retag multi: all three files carry the target tag" || fail "retag multi: all three files carry the target tag" "all three" "not all"
rm -rf "$ROOT"

echo "-- Test: retag on a record whose frontmatter has no tags: line refuses the whole call --"
fresh_root
mkdir -p "$ROOT/.craft/decisions"
NOTAGS="$ROOT/.craft/decisions/2026-04-04-no-tags-field.md"
{
  echo "---"
  echo "type: decision"
  echo "status: pending"
  echo "created: 2026-04-04"
  echo "source: session"
  echo "---"
  echo "# No tags field"
  echo ""
  echo "## Context"
  echo ""
  echo "## Options considered"
  echo "## Decision"
  echo "## Consequences"
  echo "## Approval"
} > "$NOTAGS"
write_record "root" "good-companion" "2026-04-04" "Good companion" "pending" "old-tag"
GOOD="$ROOT/.craft/decisions/2026-04-04-good-companion.md"
BEFORE=$(cat "$GOOD")
set +e
ERR=$(bash "$TRANSITION" "2026-04-04-no-tags-field,2026-04-04-good-companion" retag --tag=new-tag 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "retag no-tags-field: exits non-zero" || fail "retag no-tags-field: exits non-zero" "non-zero" "$RC"
echo "$ERR" | grep -q "2026-04-04-no-tags-field" && pass "retag no-tags-field: stderr names the bad slug" || fail "retag no-tags-field: stderr names the bad slug" "2026-04-04-no-tags-field" "$ERR"
AFTER=$(cat "$GOOD")
[ "$BEFORE" = "$AFTER" ] && pass "retag no-tags-field: good record byte-identical" || fail "retag no-tags-field: good record byte-identical" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: retag skips a record already on the target, counts it, and moves the rest --"
fresh_root
write_record "root" "already-there" "2026-04-05" "Already there" "pending" "target-tag"
write_record "root" "needs-move" "2026-04-05" "Needs move" "pending" "old-tag"
SKIPPED="$ROOT/.craft/decisions/2026-04-05-already-there.md"
BEFORE=$(cat "$SKIPPED")
OUT=$(bash "$TRANSITION" "2026-04-05-already-there,2026-04-05-needs-move" retag --tag=target-tag)
echo "$OUT" | grep -q "^MOVED=1$" && pass "retag skip: MOVED=1" || fail "retag skip: MOVED=1" "MOVED=1" "$OUT"
echo "$OUT" | grep -q "^ALREADY=1$" && pass "retag skip: ALREADY=1" || fail "retag skip: ALREADY=1" "ALREADY=1" "$OUT"
PATH_COUNT=$(echo "$OUT" | grep -c "^$ROOT" || true)
[ "$PATH_COUNT" -eq 1 ] && pass "retag skip: one path line" || fail "retag skip: one path line" "1" "$PATH_COUNT"
AFTER=$(cat "$SKIPPED")
[ "$BEFORE" = "$AFTER" ] && pass "retag skip: skipped file byte-identical" || fail "retag skip: skipped file byte-identical" "unchanged" "changed"
grep -q "^tags: \[target-tag\]$" "$ROOT/.craft/decisions/2026-04-05-needs-move.md" && pass "retag skip: the other record still moves" || fail "retag skip: the other record still moves" "tags: [target-tag]" "$(grep '^tags:' "$ROOT/.craft/decisions/2026-04-05-needs-move.md" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: retag where every named record is already on the target prints MOVED=0 and exits 0 --"
fresh_root
write_record "root" "already-one" "2026-04-06" "Already one" "pending" "target-tag"
write_record "root" "already-two" "2026-04-06" "Already two" "pending" "target-tag"
F1="$ROOT/.craft/decisions/2026-04-06-already-one.md"
F2="$ROOT/.craft/decisions/2026-04-06-already-two.md"
B1=$(cat "$F1"); B2=$(cat "$F2")
set +e
OUT=$(bash "$TRANSITION" "2026-04-06-already-one,2026-04-06-already-two" retag --tag=target-tag)
RC=$?
set -e
[ "$RC" -eq 0 ] && pass "retag all-already: exits 0" || fail "retag all-already: exits 0" "0" "$RC"
echo "$OUT" | grep -q "^MOVED=0$" && pass "retag all-already: MOVED=0" || fail "retag all-already: MOVED=0" "MOVED=0" "$OUT"
echo "$OUT" | grep -q "^ALREADY=2$" && pass "retag all-already: ALREADY=2" || fail "retag all-already: ALREADY=2" "ALREADY=2" "$OUT"
PATH_COUNT=$(echo "$OUT" | grep -c "^$ROOT" || true)
[ "$PATH_COUNT" -eq 0 ] && pass "retag all-already: no path lines" || fail "retag all-already: no path lines" "0" "$PATH_COUNT"
[ "$(cat "$F1")" = "$B1" ] && [ "$(cat "$F2")" = "$B2" ] && pass "retag all-already: both files byte-identical" || fail "retag all-already: both files byte-identical" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: retag collapses a two-tag record to exactly the target --"
fresh_root
write_record "root" "two-tags" "2026-04-07" "Two tags" "pending" "alpha, beta"
FILE="$ROOT/.craft/decisions/2026-04-07-two-tags.md"
bash "$TRANSITION" 2026-04-07-two-tags retag --tag=target-tag >/dev/null
grep -q "^tags: \[target-tag\]$" "$FILE" && pass "retag two-tag collapse: exactly the target" || fail "retag two-tag collapse: exactly the target" "tags: [target-tag]" "$(grep '^tags:' "$FILE" || echo missing)"
grep -q "^tags:.*\(alpha\|beta\)" "$FILE" && fail "retag two-tag collapse: no old tag survives on the tags: line" "(none)" "$(grep '^tags:' "$FILE")" || pass "retag two-tag collapse: no old tag survives on the tags: line"
rm -rf "$ROOT"

echo "-- Test: retag moves a crafted record --"
fresh_root
write_record "approved" "crafted-rec" "2026-04-08" "Crafted rec" "accepted" "old-tag" "crafted" "some-story"
FILE="$ROOT/.craft/decisions/approved/2026-04-08-crafted-rec.md"
set +e
OUT=$(bash "$TRANSITION" 2026-04-08-crafted-rec retag --tag=new-tag)
RC=$?
set -e
[ "$RC" -eq 0 ] && pass "retag crafted: exits 0" || fail "retag crafted: exits 0" "0" "$RC"
grep -q "^tags: \[new-tag\]$" "$FILE" && pass "retag crafted: new tag written" || fail "retag crafted: new tag written" "tags: [new-tag]" "$(grep '^tags:' "$FILE" || echo missing)"
grep -q "^disposition: crafted$" "$FILE" && pass "retag crafted: disposition: unchanged" || fail "retag crafted: disposition: unchanged" "disposition: crafted" "$(grep '^disposition:' "$FILE" || echo missing)"
grep -q "^stories: \[some-story\]$" "$FILE" && pass "retag crafted: stories: unchanged" || fail "retag crafted: stories: unchanged" "stories: [some-story]" "$(grep '^stories:' "$FILE" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: retag moves an archived record --"
fresh_root
write_record "archive" "archived-rec" "2026-04-09" "Archived rec" "declined" "old-tag"
FILE="$ROOT/.craft/decisions/archive/2026-04-09-archived-rec.md"
set +e
OUT=$(bash "$TRANSITION" 2026-04-09-archived-rec retag --tag=new-tag)
RC=$?
set -e
[ "$RC" -eq 0 ] && pass "retag archived: exits 0" || fail "retag archived: exits 0" "0" "$RC"
grep -q "^tags: \[new-tag\]$" "$FILE" && pass "retag archived: new tag written" || fail "retag archived: new tag written" "tags: [new-tag]" "$(grep '^tags:' "$FILE" || echo missing)"
[ -f "$FILE" ] && pass "retag archived: file still in archive/" || fail "retag archived: file still in archive/" "present" "missing"
rm -rf "$ROOT"

echo "-- Test: retag moves a pending root record and an approved record without changing room or status --"
fresh_root
write_record "root" "root-rec" "2026-04-10" "Root rec" "pending" "old-tag"
write_record "approved" "approved-rec" "2026-04-10" "Approved rec" "accepted" "old-tag"
ROOT_FILE="$ROOT/.craft/decisions/2026-04-10-root-rec.md"
APPROVED_FILE="$ROOT/.craft/decisions/approved/2026-04-10-approved-rec.md"
bash "$TRANSITION" "2026-04-10-root-rec,2026-04-10-approved-rec" retag --tag=new-tag >/dev/null
[ -f "$ROOT_FILE" ] && pass "retag rooms: root record stays in root" || fail "retag rooms: root record stays in root" "present" "missing"
[ -f "$APPROVED_FILE" ] && pass "retag rooms: approved record stays in approved/" || fail "retag rooms: approved record stays in approved/" "present" "missing"
grep -q "^status: pending$" "$ROOT_FILE" && pass "retag rooms: root record keeps status pending" || fail "retag rooms: root record keeps status pending" "status: pending" "$(grep '^status:' "$ROOT_FILE" || echo missing)"
grep -q "^status: accepted$" "$APPROVED_FILE" && pass "retag rooms: approved record keeps status accepted" || fail "retag rooms: approved record keeps status accepted" "status: accepted" "$(grep '^status:' "$APPROVED_FILE" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: retag leaves a body line that reads tags: as prose untouched --"
fresh_root
write_record "root" "fence-trap-tags" "2026-04-11" "Fence trap tags" "pending" "old-tag" "" "" \
  "tags: [decoy] - a body line that looks like frontmatter, quoted here on purpose."
FILE="$ROOT/.craft/decisions/2026-04-11-fence-trap-tags.md"
bash "$TRANSITION" 2026-04-11-fence-trap-tags retag --tag=new-tag >/dev/null
grep -q "^tags: \[new-tag\]$" "$FILE" && pass "retag body prose: frontmatter tags: rewritten" || fail "retag body prose: frontmatter tags: rewritten" "tags: [new-tag]" "$(grep '^tags:' "$FILE" || echo missing)"
DECOY_COUNT=$(grep -c "tags: \[decoy\]" "$FILE")
[ "$DECOY_COUNT" -eq 1 ] && pass "retag body prose: decoy line survives exactly once" || fail "retag body prose: decoy line survives exactly once" "1" "$DECOY_COUNT"
rm -rf "$ROOT"

echo "-- Test: retag with no --tag= exits non-zero and writes nothing --"
fresh_root
write_record "root" "no-tag-flag" "2026-04-12" "No tag flag" "pending" "old-tag"
FILE="$ROOT/.craft/decisions/2026-04-12-no-tag-flag.md"
BEFORE=$(cat "$FILE")
set +e
ERR=$(bash "$TRANSITION" 2026-04-12-no-tag-flag retag 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "retag no --tag=: exits non-zero" || fail "retag no --tag=: exits non-zero" "non-zero" "$RC"
echo "$ERR" | grep -qi "tag" && pass "retag no --tag=: error names the missing target" || fail "retag no --tag=: error names the missing target" "mentions tag" "$ERR"
AFTER=$(cat "$FILE")
[ "$BEFORE" = "$AFTER" ] && pass "retag no --tag=: file byte-identical" || fail "retag no --tag=: file byte-identical" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: retag with an empty --tag= exits non-zero and writes nothing --"
fresh_root
write_record "root" "empty-tag-flag" "2026-04-13" "Empty tag flag" "pending" "old-tag"
FILE="$ROOT/.craft/decisions/2026-04-13-empty-tag-flag.md"
BEFORE=$(cat "$FILE")
set +e
ERR=$(bash "$TRANSITION" 2026-04-13-empty-tag-flag retag --tag= 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "retag empty --tag=: exits non-zero" || fail "retag empty --tag=: exits non-zero" "non-zero" "$RC"
AFTER=$(cat "$FILE")
[ "$BEFORE" = "$AFTER" ] && pass "retag empty --tag=: file byte-identical" || fail "retag empty --tag=: file byte-identical" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: retag to a tag no record carries succeeds --"
fresh_root
write_record "root" "new-group" "2026-04-14" "New group" "pending" "old-tag"
bash "$TRANSITION" 2026-04-14-new-group retag --tag=brand-new-tag >/dev/null
FOUND=$(bash "$LIST" --tag=brand-new-tag --no-scan)
echo "$FOUND" | grep -q "SLUG=2026-04-14-new-group" && pass "retag new tag: list finds the record under the new tag" || fail "retag new tag: list finds the record under the new tag" "SLUG=2026-04-14-new-group" "$FOUND"
rm -rf "$ROOT"

echo "-- Test: source-by-tag: every SLUG= from list --tag=<source> --no-scan, passed as one comma-separated list, moves off the source --"
fresh_root
write_record "root" "source-a" "2026-04-15" "Source a" "pending" "source-tag"
write_record "approved" "source-b" "2026-04-15" "Source b" "accepted" "source-tag"
write_record "root" "unrelated" "2026-04-15" "Unrelated" "pending" "other-tag"
SLUGS=$(bash "$LIST" --tag=source-tag --no-scan | sed -n 's/^SLUG=//p' | paste -sd, -)
bash "$TRANSITION" "$SLUGS" retag --tag=dest-tag >/dev/null
AFTER=$(bash "$LIST" --tag=source-tag --no-scan)
[ -z "$AFTER" ] && pass "source-by-tag: source tag now empty" || fail "source-by-tag: source tag now empty" "(empty)" "$AFTER"
grep -q "^tags: \[dest-tag\]$" "$ROOT/.craft/decisions/2026-04-15-source-a.md" && pass "source-by-tag: first record moved to dest" || fail "source-by-tag: first record moved to dest" "tags: [dest-tag]" "$(grep '^tags:' "$ROOT/.craft/decisions/2026-04-15-source-a.md" || echo missing)"
grep -q "^tags: \[dest-tag\]$" "$ROOT/.craft/decisions/approved/2026-04-15-source-b.md" && pass "source-by-tag: second record moved to dest" || fail "source-by-tag: second record moved to dest" "tags: [dest-tag]" "$(grep '^tags:' "$ROOT/.craft/decisions/approved/2026-04-15-source-b.md" || echo missing)"
grep -q "^tags: \[other-tag\]$" "$ROOT/.craft/decisions/2026-04-15-unrelated.md" && pass "source-by-tag: unrelated record untouched" || fail "source-by-tag: unrelated record untouched" "tags: [other-tag]" "$(grep '^tags:' "$ROOT/.craft/decisions/2026-04-15-unrelated.md" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: retag to a tag containing a backslash-digit writes it literally - no regex group parsing, no traceback --"
fresh_root
write_record "root" "backslash-tag" "2026-04-17" "Backslash tag" "pending" "old-tag"
set +e
BS_ERR=$(bash "$TRANSITION" 2026-04-17-backslash-tag retag --tag='weird\1tag' 2>&1 >/dev/null)
BS_EXIT=$?
set -e
[ "$BS_EXIT" -eq 0 ] && pass "retag with a backslash-digit tag exits 0" || fail "retag with a backslash-digit tag exits 0" "0" "$BS_EXIT: $BS_ERR"
echo "$BS_ERR" | grep -q "Traceback" && fail "no Python traceback on stderr" "(none)" "$BS_ERR" || pass "no Python traceback on stderr"
BS_LINE=$(grep '^tags:' "$ROOT/.craft/decisions/2026-04-17-backslash-tag.md" || echo missing)
[ "$BS_LINE" = 'tags: [weird\1tag]' ] && pass "the tag is written literally, backslash and digit intact" || fail "the tag is written literally, backslash and digit intact" 'tags: [weird\1tag]' "$BS_LINE"
rm -rf "$ROOT"

echo "-- Test: an unknown action still exits non-zero and its message names retag among the verbs --"
fresh_root
write_record "root" "unknown-action" "2026-04-16" "Unknown action" "pending" "old-tag"
set +e
ERR=$(bash "$TRANSITION" 2026-04-16-unknown-action bogus 2>&1 1>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "unknown action: exits non-zero" || fail "unknown action: exits non-zero" "non-zero" "$RC"
echo "$ERR" | grep -q "retag" && pass "unknown action: message names retag" || fail "unknown action: message names retag" "mentions retag" "$ERR"
rm -rf "$ROOT"

# ── Chunk 4: the flip in complete-story.sh ──────────────────────────────

# write_flip_story CSV_OR_EMPTY HAS_FIELD(0|1) [NAME]
# Builds a full .craft/ tree (cycle dir, .state, .global-state) around one
# story so complete-story.sh can run against it end to end.
write_flip_story() {
  local csv="$1" has_field="${2:-1}" name="${3:-flip-story}"
  mkdir -p "$ROOT/.craft/cycles/1-flip-cycle/stories"
  STORY_FILE="$ROOT/.craft/cycles/1-flip-cycle/stories/1-${name}.md"
  {
    echo "---"
    echo "name: $name"
    echo "title: \"Flip Story\""
    echo "status: active"
    echo "priority: medium"
    echo "created: 2026-01-01"
    echo "updated: 2026-01-01"
    echo "cycle: flip-cycle"
    echo "story_number: 1"
    echo "chunks_total: 1"
    echo "chunks_complete: 0"
    echo "current_chunk: 1"
    if [ "$has_field" = "1" ]; then
      echo "decisions: [$csv]"
    fi
    echo "---"
    echo ""
    echo "# Story: Flip Story"
    echo ""
    echo "## Spark"
    echo "Test story for the flip."
    echo ""
    echo "## Chunks"
    echo "### Chunk 1: only chunk"
    echo "**Goal:** test."
  } > "$STORY_FILE"

  cat > "$ROOT/.craft/.global-state" <<EOF
ACTIVE_CYCLE="1-flip-cycle"
CURRENT_STORY="$name"
PLANNING_CYCLE=""
LAST_ACTIVITY=""
EOF

  mkdir -p "$ROOT/.craft/cycles/1-flip-cycle"
  cat > "$ROOT/.craft/cycles/1-flip-cycle/.state" <<EOF
CYCLE_NAME="flip-cycle"
CYCLE_STATUS="active"
CURRENT_STORY="$name"
CURRENT_CHUNK="1"
TOTAL_CHUNKS="1"
LAST_VALIDATION=""
LAST_CHECKPOINT=""
EOF
}

# run_flip — runs complete-story.sh against $STORY_FILE from $ROOT, leaving
# FLIP_STDOUT, FLIP_STDERR and FLIP_RC set.
run_flip() {
  local stderr_file="$ROOT/.flip-stderr"
  set +e
  FLIP_STDOUT=$(cd "$ROOT" && bash "$COMPLETE_STORY" "$STORY_FILE" 2>"$stderr_file")
  FLIP_RC=$?
  set -e
  FLIP_STDERR=$(cat "$stderr_file" 2>/dev/null || true)
}

echo "-- Test: in a repo that gitignores .craft/, the flip appends nothing and prints no warning --"
fresh_root
(cd "$ROOT" && git init -q && git config user.email "t@example.com" && git config user.name "t" \
  && echo ".craft/" > .gitignore && git add -A && git commit -q -m init --no-verify --allow-empty)
write_record "approved" "gitignore-record" "2026-01-01" "Gitignore record" "accepted" "tag-a"
write_flip_story "2026-01-01-gitignore-record" 1
run_flip
[ "$FLIP_RC" -eq 0 ] && pass "gitignored .craft/: exits 0" || fail "gitignored .craft/: exits 0" "0" "$FLIP_RC"
echo "$FLIP_STDOUT" | grep -q "^Crafted: Gitignore record$" && pass "gitignored .craft/: still flips and prints Crafted" || fail "gitignored .craft/: still flips and prints Crafted" "Crafted: Gitignore record" "$FLIP_STDOUT"
echo "$FLIP_STDERR" | grep -qi "gitignored" && fail "gitignored .craft/: no gitignore warning leaks in" "(no gitignore warning)" "$FLIP_STDERR" || pass "gitignored .craft/: no gitignore warning leaks in"
rm -rf "$ROOT"

echo "-- Test: a story with no decisions: field completes with output and exit code identical to today's --"
fresh_root
write_flip_story "" 0
run_flip
[ "$FLIP_RC" -eq 0 ] && pass "no decisions field: exits 0" || fail "no decisions field: exits 0" "0" "$FLIP_RC"
echo "$FLIP_STDOUT" | grep -q "^Crafted:" && fail "no decisions field: no Crafted line" "(none)" "$FLIP_STDOUT" || pass "no decisions field: no Crafted line"
echo "$FLIP_STDERR" | grep -q "decision record" && fail "no decisions field: no decision warning" "(none)" "$FLIP_STDERR" || pass "no decisions field: no decision warning"
echo "$FLIP_STDOUT" | grep -q "^Story completed: $STORY_FILE$" && pass "no decisions field: still reports story completed" || fail "no decisions field: still reports story completed" "Story completed: $STORY_FILE" "$FLIP_STDOUT"
rm -rf "$ROOT"

echo "-- Test: a story with decisions: [] completes with no warning and no record touched --"
fresh_root
write_record "approved" "untouched-record" "2026-01-01" "Untouched record" "accepted" "tag-a"
BEFORE=$(cat "$ROOT/.craft/decisions/approved/2026-01-01-untouched-record.md")
write_flip_story "" 1
run_flip
[ "$FLIP_RC" -eq 0 ] && pass "decisions: []: exits 0" || fail "decisions: []: exits 0" "0" "$FLIP_RC"
echo "$FLIP_STDOUT" | grep -q "^Crafted:" && fail "decisions: []: no Crafted line" "(none)" "$FLIP_STDOUT" || pass "decisions: []: no Crafted line"
AFTER=$(cat "$ROOT/.craft/decisions/approved/2026-01-01-untouched-record.md")
[ "$BEFORE" = "$AFTER" ] && pass "decisions: []: record untouched" || fail "decisions: []: record untouched" "unchanged" "changed"
rm -rf "$ROOT"

echo "-- Test: each listed record is flipped to disposition: crafted with the story's name appended to stories: --"
fresh_root
write_record "approved" "flip-a" "2026-01-01" "Flip A" "accepted" "tag-a"
write_record "approved" "flip-b" "2026-01-02" "Flip B" "accepted" "tag-a"
write_flip_story "2026-01-01-flip-a, 2026-01-02-flip-b" 1
run_flip
[ "$FLIP_RC" -eq 0 ] && pass "two records flip: exits 0" || fail "two records flip: exits 0" "0" "$FLIP_RC"
FILE_A="$ROOT/.craft/decisions/approved/2026-01-01-flip-a.md"
FILE_B="$ROOT/.craft/decisions/approved/2026-01-02-flip-b.md"
grep -q "^disposition: crafted$" "$FILE_A" && pass "record A flipped to crafted" || fail "record A flipped to crafted" "disposition: crafted" "$(grep '^disposition:' "$FILE_A" || echo missing)"
grep -q "^stories: \[flip-story\]$" "$FILE_A" && pass "record A gains the story's name" || fail "record A gains the story's name" "stories: [flip-story]" "$(grep '^stories:' "$FILE_A" || echo missing)"
grep -q "^disposition: crafted$" "$FILE_B" && pass "record B flipped to crafted" || fail "record B flipped to crafted" "disposition: crafted" "$(grep '^disposition:' "$FILE_B" || echo missing)"
grep -q "^stories: \[flip-story\]$" "$FILE_B" && pass "record B gains the story's name" || fail "record B gains the story's name" "stories: [flip-story]" "$(grep '^stories:' "$FILE_B" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: one Crafted: <title> line is printed per newly-flipped record --"
fresh_root
write_record "approved" "count-a" "2026-01-01" "Count A" "accepted" "tag-a"
write_record "approved" "count-b" "2026-01-02" "Count B" "accepted" "tag-a"
write_flip_story "2026-01-01-count-a, 2026-01-02-count-b" 1
run_flip
COUNT=$(echo "$FLIP_STDOUT" | grep -c "^Crafted: " || true)
[ "$COUNT" -eq 2 ] && pass "one Crafted line per flipped record" || fail "one Crafted line per flipped record" "2" "$COUNT"
echo "$FLIP_STDOUT" | grep -q "^Crafted: Count A$" && pass "Crafted line names Count A" || fail "Crafted line names Count A" "Crafted: Count A" "$FLIP_STDOUT"
echo "$FLIP_STDOUT" | grep -q "^Crafted: Count B$" && pass "Crafted line names Count B" || fail "Crafted line names Count B" "Crafted: Count B" "$FLIP_STDOUT"
rm -rf "$ROOT"

echo "-- Test: Crafted: lines are present when the commit is aborted, and precede the deferred abort message --"
fresh_root
write_record "approved" "abort-record" "2026-01-01" "Abort record" "accepted" "tag-a"
write_flip_story "2026-01-01-abort-record" 1
printf 'story: some-other-story\n' > "$ROOT/.craft/.commit-manifest"
set +e
COMBINED=$(cd "$ROOT" && bash "$COMPLETE_STORY" "$STORY_FILE" 2>&1)
RC=$?
set -e
[ "$RC" -eq 1 ] && pass "aborted commit + flip: exits 1" || fail "aborted commit + flip: exits 1" "1" "$RC"
echo "$COMBINED" | grep -q "^Crafted: Abort record$" && pass "aborted commit: Crafted line still printed" || fail "aborted commit: Crafted line still printed" "Crafted: Abort record" "$COMBINED"
CRAFTED_LINE_NUM=$(echo "$COMBINED" | grep -n "^Crafted: Abort record$" | head -1 | cut -d: -f1)
ABORT_LINE_NUM=$(echo "$COMBINED" | grep -n "commit was aborted" | head -1 | cut -d: -f1)
[ -n "$CRAFTED_LINE_NUM" ] && [ -n "$ABORT_LINE_NUM" ] && [ "$CRAFTED_LINE_NUM" -lt "$ABORT_LINE_NUM" ] && pass "Crafted line precedes the deferred abort message" || fail "Crafted line precedes the deferred abort message" "Crafted before Error" "Crafted@$CRAFTED_LINE_NUM Error@$ABORT_LINE_NUM"
rm -rf "$ROOT"

echo "-- Test: an already-crafted record prints no Crafted: line but still gains the story name --"
fresh_root
write_record "approved" "already-crafted" "2026-01-01" "Already crafted" "accepted" "tag-a" "crafted" "earlier-story"
write_flip_story "2026-01-01-already-crafted" 1
run_flip
[ "$FLIP_RC" -eq 0 ] && pass "already-crafted: exits 0" || fail "already-crafted: exits 0" "0" "$FLIP_RC"
echo "$FLIP_STDOUT" | grep -q "^Crafted:" && fail "already-crafted: no Crafted line" "(none)" "$FLIP_STDOUT" || pass "already-crafted: no Crafted line"
FILE="$ROOT/.craft/decisions/approved/2026-01-01-already-crafted.md"
grep -q "^stories: \[earlier-story, flip-story\]$" "$FILE" && pass "already-crafted: story name appended alongside the earlier one" || fail "already-crafted: story name appended alongside the earlier one" "stories: [earlier-story, flip-story]" "$(grep '^stories:' "$FILE" || echo missing)"
rm -rf "$ROOT"

echo "-- Test: an unresolvable slug warns to stderr, flips the resolvable records, and exits 1 --"
fresh_root
write_record "approved" "resolvable" "2026-01-01" "Resolvable" "accepted" "tag-a"
write_flip_story "2026-01-01-resolvable, 2026-01-01-does-not-exist" 1
run_flip
[ "$FLIP_RC" -eq 1 ] && pass "unresolvable slug: exits 1" || fail "unresolvable slug: exits 1" "1" "$FLIP_RC"
echo "$FLIP_STDERR" | grep -q "^Warning: decision record '2026-01-01-does-not-exist' could not be flipped to crafted" && pass "unresolvable slug: warns naming the slug" || fail "unresolvable slug: warns naming the slug" "Warning: decision record '2026-01-01-does-not-exist' ..." "$FLIP_STDERR"
echo "$FLIP_STDERR" | grep -q -- "- continuing$" && pass "unresolvable slug: warning ends with - continuing" || fail "unresolvable slug: warning ends with - continuing" "- continuing" "$FLIP_STDERR"
echo "$FLIP_STDOUT" | grep -q "^Crafted: Resolvable$" && pass "unresolvable slug: the resolvable record still flips" || fail "unresolvable slug: the resolvable record still flips" "Crafted: Resolvable" "$FLIP_STDOUT"
rm -rf "$ROOT"

echo "-- Test: after an unresolvable slug the cycle state, global state and event log are still written --"
fresh_root
write_flip_story "2026-01-01-does-not-exist" 1
run_flip
[ "$FLIP_RC" -eq 1 ] && pass "unresolvable slug (non-stranding): exits 1" || fail "unresolvable slug (non-stranding): exits 1" "1" "$FLIP_RC"
source "$ROOT/.craft/.global-state"
[ -z "$CURRENT_STORY" ] && pass "unresolvable slug: global CURRENT_STORY cleared" || fail "unresolvable slug: global CURRENT_STORY cleared" "" "$CURRENT_STORY"
unset CURRENT_STORY
source "$ROOT/.craft/cycles/1-flip-cycle/.state"
[ -z "$CURRENT_STORY" ] && pass "unresolvable slug: cycle CURRENT_STORY cleared" || fail "unresolvable slug: cycle CURRENT_STORY cleared" "" "$CURRENT_STORY"
[ -f "$ROOT/.craft/cycles/1-flip-cycle/.events/1-flip-story.jsonl" ] && pass "unresolvable slug: event log written" || fail "unresolvable slug: event log written" "present" "missing"
rm -rf "$ROOT"

echo "-- Test: the flip-failure error message is distinct from the commit-abort message --"
fresh_root
write_flip_story "2026-01-01-does-not-exist" 1
run_flip
FLIP_ONLY_MSG=$(echo "$FLIP_STDERR" | grep "decision record(s) could not be flipped" || true)
[ -n "$FLIP_ONLY_MSG" ] && ! echo "$FLIP_ONLY_MSG" | grep -q "commit was aborted" && pass "flip-only error message names decision records, not the commit" || fail "flip-only error message names decision records, not the commit" "distinct message" "$FLIP_ONLY_MSG"
rm -rf "$ROOT"

echo "-- Test: when the commit is aborted AND a slug fails, both error lines print and the exit is 1 --"
fresh_root
write_flip_story "2026-01-01-does-not-exist" 1
printf 'story: some-other-story\n' > "$ROOT/.craft/.commit-manifest"
run_flip
[ "$FLIP_RC" -eq 1 ] && pass "both failures: exits 1" || fail "both failures: exits 1" "1" "$FLIP_RC"
echo "$FLIP_STDERR" | grep -q "commit was aborted" && pass "both failures: commit-abort message prints" || fail "both failures: commit-abort message prints" "commit was aborted" "$FLIP_STDERR"
echo "$FLIP_STDERR" | grep -q "decision record(s) could not be flipped" && pass "both failures: flip-failure message prints" || fail "both failures: flip-failure message prints" "decision record(s) could not be flipped" "$FLIP_STDERR"
rm -rf "$ROOT"

echo "-- Test: when the run exits at the deferred abort with no decisions carried, no Crafted: lines are printed --"
fresh_root
write_flip_story "" 0
printf 'story: some-other-story\n' > "$ROOT/.craft/.commit-manifest"
run_flip
[ "$FLIP_RC" -eq 1 ] && pass "abort with no decisions: exits 1" || fail "abort with no decisions: exits 1" "1" "$FLIP_RC"
echo "$FLIP_STDOUT" | grep -q "^Crafted:" && fail "abort with no decisions: no Crafted line printed" "(none)" "$FLIP_STDOUT" || pass "abort with no decisions: no Crafted line printed"
rm -rf "$ROOT"

echo "=== decisions-list.sh --claimants ==="
echo ""

echo "-- Test: claimants prints one line per non-complete claimant, sorted by path --"
fresh_root
write_record "approved" "claimed-law" "2026-05-01" "Claimed law" "accepted" "tag-a"
SLUG5="2026-05-01-claimed-law"
write_story "01-planning-claimer" "planning" "$SLUG5"
write_story "02-active-claimer" "active" "other-slug, $SLUG5"
write_story "03-complete-claimer" "complete" "$SLUG5"
write_story "ready-claimer" "ready" "$SLUG5" ".craft/backlog"
write_story "unrelated" "planning" "2026-05-01-something-else"
set +e
OUT=$(bash "$LIST" --claimants="$SLUG5")
RC=$?
set -e
[ "$RC" -eq 0 ] && pass "claimants: exits 0" || fail "claimants: exits 0" "0" "$RC"
LINES=$(echo "$OUT" | grep -c . || true)
[ "$LINES" -eq 3 ] && pass "claimants: three lines (complete claimant omitted)" || fail "claimants: three lines" "3" "$OUT"
# backlog sorts before cycles; within a dir, filename order
EXPECTED="$(printf 'ready ready-claimer %s/.craft/backlog/ready-claimer.md\nplanning 01-planning-claimer %s/.craft/cycles/1-test/stories/01-planning-claimer.md\nactive 02-active-claimer %s/.craft/cycles/1-test/stories/02-active-claimer.md' "$ROOT" "$ROOT" "$ROOT")"
[ "$OUT" = "$EXPECTED" ] && pass "claimants: lines are '<status> <story> <path>', sorted by path" || fail "claimants: lines are '<status> <story> <path>', sorted by path" "$EXPECTED" "$OUT"
rm -rf "$ROOT"

echo "-- Test: claimants takes the story name from the filename when frontmatter has no name --"
fresh_root
write_record "approved" "nameless" "2026-05-02" "Nameless" "accepted" "tag-a"
mkdir -p "$ROOT/.craft/backlog"
printf -- '---\nstatus: planning\ndecisions: [2026-05-02-nameless]\n---\n# x\n' > "$ROOT/.craft/backlog/07-from-the-file.md"
OUT=$(bash "$LIST" --claimants=2026-05-02-nameless)
[ "$OUT" = "planning from-the-file $ROOT/.craft/backlog/07-from-the-file.md" ] && pass "claimants: name falls back to the basename minus its numeric prefix" || fail "claimants: name falls back to the basename" "planning from-the-file ..." "$OUT"
rm -rf "$ROOT"

echo "-- Test: claimants on an unclaimed slug prints nothing and exits 0 --"
fresh_root
write_record "approved" "unclaimed" "2026-05-03" "Unclaimed" "accepted" "tag-a"
write_story "some-story" "planning" "2026-05-03-other"
set +e
OUT=$(bash "$LIST" --claimants=2026-05-03-unclaimed)
RC=$?
set -e
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && pass "claimants: unclaimed slug prints nothing, exits 0" || fail "claimants: unclaimed slug prints nothing, exits 0" "empty, 0" "rc=$RC out=$OUT"
rm -rf "$ROOT"

echo "-- Test: claimants on crafted law shipped only by complete stories prints nothing --"
fresh_root
write_record "approved" "shipped-law" "2026-05-04" "Shipped law" "accepted" "tag-a" "crafted" "done-story"
write_story "done-story" "complete" "2026-05-04-shipped-law"
OUT=$(bash "$LIST" --claimants=2026-05-04-shipped-law)
[ -z "$OUT" ] && pass "claimants: law claimed only by complete stories prints nothing" || fail "claimants: law claimed only by complete stories prints nothing" "empty" "$OUT"
rm -rf "$ROOT"

echo "-- Test: claimants ignores every other flag and works without a decisions dir --"
fresh_root
write_story "lonely-story" "planning" "2026-05-05-x"
set +e
OUT=$(bash "$LIST" --claimants=2026-05-05-x --room=archive --tag=nope)
RC=$?
set -e
[ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^planning lonely-story " && pass "claimants: other flags ignored" || fail "claimants: other flags ignored" "one planning line" "rc=$RC out=$OUT"
rm -rf "$ROOT"

echo "-- Test: a list call without --claimants is unchanged by the new mode --"
fresh_root
write_record "approved" "plain-call" "2026-05-06" "Plain call" "accepted" "tag-a"
write_story "plain-claimer" "planning" "2026-05-06-plain-call"
OUT=$(bash "$LIST" --slug=2026-05-06-plain-call)
EXPECTED="$(printf 'FILE=%s/.craft/decisions/approved/2026-05-06-plain-call.md\nROOM=approved\nSLUG=2026-05-06-plain-call\nDATE=2026-05-06\nTITLE=Plain call\nSTATUS=accepted\nTAGS=tag-a\nDISPOSITION=claimed\nSTORIES=plain-claimer\n' "$ROOT")"
[ "$OUT" = "$EXPECTED" ] && pass "list without --claimants: nine keys, same order, same values" || fail "list without --claimants unchanged" "$EXPECTED" "$OUT"
rm -rf "$ROOT"

echo "=== decisions-transition.sh --stdin ==="
echo ""

echo "-- Test: accept --stdin writes the same approval line as --quote=, answer round-trips byte-exact --"
ANSWER='it'"'"'s $5 🎉 and `ticks` "quoted" \n'
fresh_root
write_record "root" "stdin-accept" "2026-05-10" "Stdin accept" "pending" "tag-a"
printf '%s\n' "$ANSWER" | bash "$TRANSITION" 2026-05-10-stdin-accept accept --stdin > /dev/null
GOT=$(cat "$ROOT/.craft/decisions/approved/2026-05-10-stdin-accept.md")
rm -rf "$ROOT"
fresh_root
write_record "root" "stdin-accept" "2026-05-10" "Stdin accept" "pending" "tag-a"
bash "$TRANSITION" 2026-05-10-stdin-accept accept --quote="$ANSWER" > /dev/null
WANT=$(cat "$ROOT/.craft/decisions/approved/2026-05-10-stdin-accept.md")
[ "$GOT" = "$WANT" ] && pass "accept --stdin: file identical to the --quote= result" || fail "accept --stdin: file identical to the --quote= result" "$WANT" "$GOT"
echo "$GOT" | grep -qF "> \"$ANSWER\" - $(date +%Y-%m-%d), session" && pass "accept --stdin: answer round-trips byte-exact" || fail "accept --stdin: answer round-trips byte-exact" "$ANSWER" "$GOT"
rm -rf "$ROOT"

echo "-- Test: stdin answer is stripped of leading and trailing blank lines --"
fresh_root
write_record "root" "stdin-strip" "2026-05-11" "Stdin strip" "pending" "tag-a"
printf '\n\n  yes, do it\n\n\n' | bash "$TRANSITION" 2026-05-11-stdin-strip accept --stdin > /dev/null
grep -qF "> \"  yes, do it\" - $(date +%Y-%m-%d), session" "$ROOT/.craft/decisions/approved/2026-05-11-stdin-strip.md" && pass "accept --stdin: leading and trailing blank lines stripped" || fail "accept --stdin: leading and trailing blank lines stripped" "quote '  yes, do it'" "$(tail -2 "$ROOT/.craft/decisions/approved/2026-05-11-stdin-strip.md")"
rm -rf "$ROOT"

echo "-- Test: decline and deprecate --stdin carry the answer --"
fresh_root
write_record "root" "stdin-decline" "2026-05-12" "Stdin decline" "pending" "tag-a"
write_record "approved" "stdin-deprecate" "2026-05-12" "Stdin deprecate" "accepted" "tag-a"
OUT=$(printf 'no thanks\n' | bash "$TRANSITION" 2026-05-12-stdin-decline decline --stdin)
grep -q '^> "no thanks" - ' "$ROOT/.craft/decisions/archive/2026-05-12-stdin-decline.md" && grep -q "^status: declined$" "$ROOT/.craft/decisions/archive/2026-05-12-stdin-decline.md" && pass "decline --stdin carries the answer" || fail "decline --stdin carries the answer" "declined with quote" "$(tail -3 "$ROOT/.craft/decisions/archive/2026-05-12-stdin-decline.md" 2>&1)"
echo "$OUT" | head -2 | tr '\n' ' ' | grep -q "^TITLE=Stdin decline CHANGED=1 $" && pass "decline --stdin: TITLE=/CHANGED= unchanged" || fail "decline --stdin: TITLE=/CHANGED= unchanged" "TITLE=Stdin decline CHANGED=1" "$OUT"
printf 'obsolete\n' | bash "$TRANSITION" 2026-05-12-stdin-deprecate deprecate --stdin > /dev/null
grep -q '^> "obsolete" - ' "$ROOT/.craft/decisions/archive/2026-05-12-stdin-deprecate.md" && grep -q "^status: deprecated$" "$ROOT/.craft/decisions/archive/2026-05-12-stdin-deprecate.md" && pass "deprecate --stdin carries the answer" || fail "deprecate --stdin carries the answer" "deprecated with quote" "$(tail -3 "$ROOT/.craft/decisions/archive/2026-05-12-stdin-deprecate.md" 2>&1)"
rm -rf "$ROOT"

echo "-- Test: --stdin with --quote= is refused and writes nothing --"
fresh_root
write_record "root" "stdin-both" "2026-05-13" "Stdin both" "pending" "tag-a"
F="$ROOT/.craft/decisions/2026-05-13-stdin-both.md"
B=$(cat "$F")
set +e
printf 'x\n' | bash "$TRANSITION" 2026-05-13-stdin-both accept --stdin --quote="y" >/dev/null 2>&1
RC=$?
set -e
[ "$RC" -ne 0 ] && [ "$(cat "$F")" = "$B" ] && [ ! -e "$ROOT/.craft/decisions/approved/2026-05-13-stdin-both.md" ] && pass "--stdin with --quote= refused, nothing written" || fail "--stdin with --quote= refused, nothing written" "non-zero, untouched" "rc=$RC"
rm -rf "$ROOT"

echo "-- Test: --stdin on retag and on craft is refused and writes nothing --"
fresh_root
write_record "root" "stdin-retag" "2026-05-14" "Stdin retag" "pending" "old-tag"
write_record "approved" "stdin-craft" "2026-05-14" "Stdin craft" "accepted" "old-tag"
F1="$ROOT/.craft/decisions/2026-05-14-stdin-retag.md"; F2="$ROOT/.craft/decisions/approved/2026-05-14-stdin-craft.md"
B1=$(cat "$F1"); B2=$(cat "$F2")
set +e
printf 'x\n' | bash "$TRANSITION" 2026-05-14-stdin-retag retag --tag=new-tag --stdin >/dev/null 2>&1
RC1=$?
printf 'x\n' | bash "$TRANSITION" 2026-05-14-stdin-craft craft --story=s --stdin >/dev/null 2>&1
RC2=$?
set -e
[ "$RC1" -ne 0 ] && [ "$(cat "$F1")" = "$B1" ] && pass "--stdin on retag refused, nothing written" || fail "--stdin on retag refused, nothing written" "non-zero, untouched" "rc=$RC1"
[ "$RC2" -ne 0 ] && [ "$(cat "$F2")" = "$B2" ] && pass "--stdin on craft refused, nothing written" || fail "--stdin on craft refused, nothing written" "non-zero, untouched" "rc=$RC2"
rm -rf "$ROOT"

echo "-- Test: an empty stdin answer is refused like a missing quote --"
fresh_root
write_record "root" "stdin-empty" "2026-05-15" "Stdin empty" "pending" "tag-a"
F="$ROOT/.craft/decisions/2026-05-15-stdin-empty.md"
B=$(cat "$F")
set +e
ERR=$(printf '\n  \n' | bash "$TRANSITION" 2026-05-15-stdin-empty accept --stdin 2>&1 >/dev/null)
RC=$?
ERR2=$(printf '\n\n' | bash "$TRANSITION" 2026-05-15-stdin-empty accept --stdin 2>&1 >/dev/null)
RC2=$?
ERR3=$(bash "$TRANSITION" 2026-05-15-stdin-empty accept 2>&1 >/dev/null)
set -e
[ "$RC2" -ne 0 ] && [ "$(cat "$F")" = "$B" ] && [ "$ERR2" = "$ERR3" ] && pass "empty stdin answer: same error as a missing --quote" || fail "empty stdin answer: same error as a missing --quote" "$ERR3" "rc=$RC2 $ERR2"
rm -rf "$ROOT"

echo "-- Test: stdin is never read without --stdin (a craft call with an open stdin does not block) --"
fresh_root
write_record "approved" "no-read" "2026-05-16" "No read" "accepted" "tag-a"
set +e
START=$SECONDS
bash "$TRANSITION" 2026-05-16-no-read craft --story=some-story > "$ROOT/no-read.out" 2>&1 < <(sleep 4)
RC=$?
OUT=$(cat "$ROOT/no-read.out")
ELAPSED=$((SECONDS - START))
set -e
[ "$RC" -eq 0 ] && [ "$ELAPSED" -lt 3 ] && echo "$OUT" | grep -q "^TITLE=No read$" && pass "craft without --stdin returns without reading stdin" || fail "craft without --stdin returns without reading stdin" "rc 0 in under 3s with TITLE=" "rc=$RC elapsed=${ELAPSED}s $OUT"
rm -rf "$ROOT"

echo "=== decisions-transition.sh retag receipt ==="
echo ""

echo "-- Test: retag prints NEW_GROUP=1 when no record carried the target before the write --"
fresh_root
write_record "root" "rc-a" "2026-05-20" "Receipt a" "pending" "old-tag"
write_record "root" "rc-b" "2026-05-20" "Receipt b" "pending" "old-tag"
OUT=$(bash "$TRANSITION" "2026-05-20-rc-a,2026-05-20-rc-b" retag --tag=fresh-target)
echo "$OUT" | grep -q "^NEW_GROUP=1$" && pass "retag: NEW_GROUP=1 for a tag no record carried" || fail "retag: NEW_GROUP=1 for a tag no record carried" "NEW_GROUP=1" "$OUT"
rm -rf "$ROOT"

echo "-- Test: retag prints NEW_GROUP=0 when one already carried the target, with receipt order --"
fresh_root
write_record "root" "rd-there" "2026-05-21" "Already there" "pending" "target-tag"
write_record "root" "rd-move" "2026-05-21" "Moving one" "pending" "old-tag"
write_story "rd-claimer" "planning" "2026-05-21-rd-move"
OUT=$(bash "$TRANSITION" "2026-05-21-rd-there,2026-05-21-rd-move" retag --tag=target-tag)
echo "$OUT" | grep -q "^NEW_GROUP=0$" && echo "$OUT" | grep -q "^ALREADY=1$" && pass "retag: NEW_GROUP=0 and ALREADY=1" || fail "retag: NEW_GROUP=0 and ALREADY=1" "NEW_GROUP=0 ALREADY=1" "$OUT"
HEADS=$(echo "$OUT" | head -4 | tr '\n' ' ')
[ "$HEADS" = "MOVED=1 ALREADY=1 NEW_GROUP=0 TITLE=Moving one " ] && pass "retag: counts, NEW_GROUP, then TITLE= in order" || fail "retag: counts, NEW_GROUP, then TITLE= in order" "MOVED=1 ALREADY=1 NEW_GROUP=0 TITLE=Moving one" "$HEADS"
rm -rf "$ROOT"

echo "-- Test: retag prints one TITLE= per moved record and the target group's data before the paths --"
fresh_root
write_record "root" "rt-a" "2026-05-22" "Title alpha" "pending" "old-tag"
write_record "approved" "rt-b" "2026-05-22" "Title beta" "accepted" "old-tag"
write_story "rt-claimer" "planning" "2026-05-22-rt-b"
OUT=$(bash "$TRANSITION" "2026-05-22-rt-b,2026-05-22-rt-a" retag --tag=grp-target)
TITLES=$(echo "$OUT" | grep '^TITLE=' | tr '\n' '|')
[ "$TITLES" = "TITLE=Title beta|TITLE=Title alpha|" ] && pass "retag: one TITLE= per moved record in argument order" || fail "retag: one TITLE= per moved record in argument order" "TITLE=Title beta|TITLE=Title alpha|" "$TITLES"
echo "$OUT" | grep -q "^GROUP=grp-target" && echo "$OUT" | grep -q "^TOTAL=2$" && echo "$OUT" | grep -q "^ROW=" && pass "retag: the target group's GROUP=/TOTAL=/ROW= data is printed" || fail "retag: the target group's GROUP=/TOTAL=/ROW= data is printed" "GROUP= TOTAL=2 ROW=" "$OUT"
LAST2=$(echo "$OUT" | tail -2 | tr '\n' ' ')
[ "$LAST2" = "$ROOT/.craft/decisions/approved/2026-05-22-rt-b.md $ROOT/.craft/decisions/2026-05-22-rt-a.md " ] && pass "retag: the moved paths come last, in argument order" || fail "retag: the moved paths come last, in argument order" "two paths" "$LAST2"
FIRST_PATH=$(echo "$OUT" | grep -n "^$ROOT" | head -1 | cut -d: -f1)
LAST_DATA=$(echo "$OUT" | grep -n "^ROW=\|^GROUP=\|^TOTAL=\|^COUNT_\|^MORE=\|^STRIP=" | tail -1 | cut -d: -f1)
[ "$LAST_DATA" -lt "$FIRST_PATH" ] && pass "retag: group data sits wholly before the first path" || fail "retag: group data sits wholly before the first path" "data before paths" "$OUT"
echo "$OUT" | grep '^ROW=' | grep -q "Title beta" && pass "retag: the story scan is on (claimed record gets a Shelf row)" || fail "retag: the story scan is on" "a row for Title beta" "$(echo "$OUT" | grep '^ROW=')"
rm -rf "$ROOT"

echo "-- Test: retag that moves nothing prints no group data --"
fresh_root
write_record "root" "rn-a" "2026-05-23" "Nothing a" "pending" "target-tag"
OUT=$(bash "$TRANSITION" 2026-05-23-rn-a retag --tag=target-tag)
[ "$OUT" = "$(printf 'MOVED=0\nALREADY=1\nNEW_GROUP=0')" ] && pass "retag nothing moved: only MOVED=/ALREADY=/NEW_GROUP=" || fail "retag nothing moved: only MOVED=/ALREADY=/NEW_GROUP=" "MOVED=0 ALREADY=1 NEW_GROUP=0" "$OUT"
rm -rf "$ROOT"

echo "-- Test: a failed retag prints no receipt and leaves every record byte-identical --"
fresh_root
write_record "root" "rf-a" "2026-05-24" "Fail a" "pending" "old-tag"
F="$ROOT/.craft/decisions/2026-05-24-rf-a.md"; B=$(cat "$F")
set +e
OUT=$(bash "$TRANSITION" "2026-05-24-rf-a,2026-05-24-nope" retag --tag=new-tag 2>/dev/null)
RC=$?
set -e
[ "$RC" -ne 0 ] && [ -z "$OUT" ] && [ "$(cat "$F")" = "$B" ] && pass "failed retag: no receipt, nothing written" || fail "failed retag: no receipt, nothing written" "non-zero, empty stdout" "rc=$RC out=$OUT"
rm -rf "$ROOT"

# ── capture: the record on stdin, partial reopen, the receipt ───────────

echo "-- Test: create --stdin is byte-identical to create by flags, with and without an Approval --"
fresh_root
STDIN_BODY=$(printf '# Parity title\n\n## Context\nWhy we are here.\n\n## Options considered\n- one\n- two\n\n## Decision\nPick one.\n\n## Consequences\nIt costs a day.\n\n## Approval\napproved, go\n')
P_FLAGS=$(bash "$CAPTURE" "Parity title" --tag=par --context="Why we are here." --options="$(printf -- '- one\n- two')" --decision="Pick one." --consequences="It costs a day." --quote="approved, go" --created=2026-06-01)
cp "$P_FLAGS" "$ROOT/flags.md"; rm "$P_FLAGS"
P_STDIN=$(printf '%s\n' "$STDIN_BODY" | bash "$CAPTURE" --tag=par --stdin --created=2026-06-01)
[ "$P_STDIN" = "$P_FLAGS" ] && cmp -s "$ROOT/flags.md" "$P_STDIN" && pass "create --stdin with an Approval matches the flag form byte for byte" || fail "create --stdin with an Approval matches the flag form byte for byte" "identical bytes" "$(diff "$ROOT/flags.md" "$P_STDIN" 2>&1 | head -5)"
rm "$P_STDIN"
NOAPP=$(printf '%s\n' "$STDIN_BODY" | sed '/^## Approval$/,$d')
F2=$(bash "$CAPTURE" "Parity title" --tag=par --context="Why we are here." --options="$(printf -- '- one\n- two')" --decision="Pick one." --consequences="It costs a day." --created=2026-06-01)
cp "$F2" "$ROOT/flags2.md"; rm "$F2"
S2=$(printf '%s\n' "$NOAPP" | bash "$CAPTURE" --tag=par --stdin --created=2026-06-01)
cmp -s "$ROOT/flags2.md" "$S2" && [ "$(dirname "$S2")" = "$ROOT/.craft/decisions" ] && pass "create --stdin without an Approval matches the flag form and files pending in the root" || fail "create --stdin without an Approval matches the flag form and files pending in the root" "identical bytes, root" "$S2"
rm -rf "$ROOT"

echo "-- Test: an apostrophe, a dollar sign and an emoji round-trip byte-exact through --stdin --"
fresh_root
RT_CTX="It's \$HOME and \$(not run) 🎯 and a backtick \` too"
F=$(printf '# Round trip\n\n## Context\n%s\n\n## Options considered\nopt\n\n## Decision\ndec\n\n## Consequences\ncons\n' "$RT_CTX" | bash "$CAPTURE" --tag=rt --stdin --created=2026-06-02)
GOT=$(sed -n '/^## Context$/,/^## Options considered$/p' "$F" | sed '1d;$d' | sed '$d')
[ "$GOT" = "$RT_CTX" ] && pass "special characters survive --stdin byte-exact" || fail "special characters survive --stdin byte-exact" "$RT_CTX" "$GOT"
rm -rf "$ROOT"

echo "-- Test: an unknown ## heading on stdin is refused and writes nothing --"
fresh_root
set +e
ERR=$(printf '# T\n\n## Context\nc\n\n## Notes\nn\n\n## Options considered\no\n\n## Decision\nd\n\n## Consequences\nk\n' | bash "$CAPTURE" --tag=bad --stdin 2>&1 1>/dev/null)
RC=$?
ERR2=$(printf '# T\n\n## Context\nc\n\n## Context\nagain\n\n## Options considered\no\n\n## Decision\nd\n\n## Consequences\nk\n' | bash "$CAPTURE" --tag=bad --stdin 2>&1 1>/dev/null)
RC2=$?
set -e
[ "$RC" -ne 0 ] && echo "$ERR" | grep -qF '## Notes' && [ ! -d "$ROOT/.craft" ] && pass "an unknown heading exits non-zero naming it and writes nothing" || fail "an unknown heading exits non-zero naming it and writes nothing" "non-zero, names ## Notes, no .craft" "rc=$RC err=$ERR"
[ "$RC2" -ne 0 ] && echo "$ERR2" | grep -qF '## Context' && [ ! -d "$ROOT/.craft" ] && pass "a repeated heading is refused naming it" || fail "a repeated heading is refused naming it" "non-zero, names ## Context" "rc=$RC2 err=$ERR2"
rm -rf "$ROOT"

echo "-- Test: create --stdin with --quote=, a section flag or a positional title is refused --"
fresh_root
BODY=$(printf '# T\n\n## Context\nc\n\n## Options considered\no\n\n## Decision\nd\n\n## Consequences\nk\n')
for extra in '--quote=words' '--context=x' '--decision=x' 'Positional'; do
  set +e
  printf '%s\n' "$BODY" | bash "$CAPTURE" --tag=t --stdin "$extra" >/dev/null 2>&1
  RC=$?
  set -e
  [ "$RC" -ne 0 ] && [ ! -d "$ROOT/.craft" ] && pass "create --stdin with $extra is refused before any write" || fail "create --stdin with $extra is refused before any write" "non-zero, nothing written" "rc=$RC"
done
set +e
printf '# T\n\n## Context\nc\n' | bash "$CAPTURE" --tag=t --stdin >/dev/null 2>"$ROOT/err.txt"
RC=$?
set -e
[ "$RC" -ne 0 ] && grep -q -- '--options is required' "$ROOT/err.txt" && pass "create --stdin missing a section gives the flag form's message" || fail "create --stdin missing a section gives the flag form's message" "--options is required" "$(cat "$ROOT/err.txt")"
rm -rf "$ROOT"

echo "-- Test: reopen --stdin with only Consequences rewrites it and leaves every other byte identical --"
fresh_root
write_record "approved" "partial-law" "2026-06-03" "Partial law" "accepted" "pl"
F="$ROOT/.craft/decisions/approved/2026-06-03-partial-law.md"
python3 - "$F" <<'PY'
import sys
p=sys.argv[1]
t=open(p,encoding='utf-8').read()
t=t.replace("## Options considered\n## Decision\n## Consequences\n","## Options considered\n- keep\n\n## Decision\nWe keep it.\n\n## Consequences\nOld consequence.\nSecond old line.\n\n")
open(p,'w',encoding='utf-8').write(t)
PY
span() { python3 - "$1" "$2" <<'PY'
import sys,re
t=open(sys.argv[1],encoding='utf-8').read()
name=sys.argv[2]
if name=='front': print(t.split('---\n')[1]); sys.exit()
m=re.search(r'^## '+re.escape(name)+r'\n(.*?)(?=^## |\Z)',t,re.S|re.M)
print(m.group(1) if m else 'MISSING', end='')
PY
}
B_FRONT=$(span "$F" front); B_CTX=$(span "$F" Context); B_OPT=$(span "$F" "Options considered"); B_DEC=$(span "$F" Decision); B_APP=$(span "$F" Approval)
OUT=$(printf '## Consequences\nNew consequence.\n\n## Approval\nyes, reshape it\n' | bash "$CAPTURE" --reopen=2026-06-03-partial-law --stdin)
A_CONS=$(span "$F" Consequences)
[ "$A_CONS" = "$(printf 'New consequence.\n\n')" ] && pass "reopen --stdin replaces the Consequences text" || fail "reopen --stdin replaces the Consequences text" "New consequence." "$A_CONS"
[ "$(span "$F" front)" = "$B_FRONT" ] && [ "$(span "$F" Context)" = "$B_CTX" ] && [ "$(span "$F" "Options considered")" = "$B_OPT" ] && [ "$(span "$F" Decision)" = "$B_DEC" ] && pass "frontmatter, Context, Options and Decision are byte-identical after a Consequences-only reopen" || fail "untouched spans stay identical" "unchanged" "changed"
grep -q '^# Partial law$' "$F" && grep -q '^> "approved" - 2026-06-03, session$' "$F" && pass "the title and the original approval line are untouched" || fail "the title and the original approval line are untouched" "kept" "$(cat "$F")"
echo "-- Test: reopen receipt names the sections written before the path --"
EXPECT=$(printf 'Sections written: Consequences\n%s' "$F")
[ "$OUT" = "$EXPECT" ] && pass "receipt is Sections written then the path" || fail "receipt is Sections written then the path" "$EXPECT" "$OUT"
OUT=$(printf '# Renamed law\n\n## Decision\nWe change it.\n\n## Context\nNew ctx.\n\n## Approval\nagain\n' | bash "$CAPTURE" --reopen=2026-06-03-partial-law --stdin)
[ "$(printf '%s\n' "$OUT" | sed -n 1p)" = "Sections written: Title, Context, Decision" ] && pass "the receipt lists names in record order, Title first" || fail "the receipt lists names in record order, Title first" "Sections written: Title, Context, Decision" "$OUT"
rm -rf "$ROOT"

echo "-- Test: reopen --stdin on law requires an Approval and appends a Reopen line; in the root it refuses one --"
fresh_root
write_record "approved" "law-needs-approval" "2026-06-04" "Law needs approval" "accepted" "pl"
F="$ROOT/.craft/decisions/approved/2026-06-04-law-needs-approval.md"; B=$(cat "$F")
set +e
printf '## Context\nnew\n' | bash "$CAPTURE" --reopen=2026-06-04-law-needs-approval --stdin >/dev/null 2>&1
RC=$?
set -e
[ "$RC" -ne 0 ] && [ "$(cat "$F")" = "$B" ] && pass "reopen --stdin on law without an Approval is refused and writes nothing" || fail "reopen --stdin on law without an Approval is refused" "non-zero, unchanged" "rc=$RC"
printf '## Context\nnew\n\n## Approval\nship it\n' | bash "$CAPTURE" --reopen=2026-06-04-law-needs-approval --stdin >/dev/null
grep -q '^> Reopen: "ship it" - ' "$F" && grep -q '^> "approved" - 2026-06-04, session$' "$F" && pass "the Approval text lands as a Reopen line under the original approval" || fail "the Approval text lands as a Reopen line" "> Reopen: \"ship it\"" "$(tail -4 "$F")"
write_record "root" "root-quiet" "2026-06-04" "Root quiet" "pending" "pl"
F="$ROOT/.craft/decisions/2026-06-04-root-quiet.md"; B=$(cat "$F")
set +e
printf '## Context\nnew\n\n## Approval\nnot here\n' | bash "$CAPTURE" --reopen=2026-06-04-root-quiet --stdin >/dev/null 2>&1
RC=$?
set -e
[ "$RC" -ne 0 ] && [ "$(cat "$F")" = "$B" ] && pass "reopen --stdin in the root refuses an Approval and writes nothing" || fail "reopen --stdin in the root refuses an Approval" "non-zero, unchanged" "rc=$RC"
printf '## Context\nquiet new\n' | bash "$CAPTURE" --reopen=2026-06-04-root-quiet --stdin >/dev/null
grep -q '^quiet new$' "$F" && pass "reopen --stdin in the root reshapes without an Approval" || fail "reopen --stdin in the root reshapes without an Approval" "quiet new" "$(cat "$F")"
rm -rf "$ROOT"

echo "-- Test: reopen naming a section the record lacks is refused and writes nothing --"
fresh_root
mkdir -p "$ROOT/.craft/decisions"
printf -- '---\ntype: decision\nstatus: pending\ncreated: 2026-06-05\nsource: session\ntags: [pl]\n---\n# Thin\n\n## Context\nonly context\n' > "$ROOT/.craft/decisions/2026-06-05-thin.md"
F="$ROOT/.craft/decisions/2026-06-05-thin.md"; B=$(cat "$F")
set +e
printf '## Context\nnew\n\n## Decision\nlacking\n' | bash "$CAPTURE" --reopen=2026-06-05-thin --stdin >/dev/null 2>&1
RC=$?
set -e
[ "$RC" -ne 0 ] && [ "$(cat "$F")" = "$B" ] && pass "a section the record lacks refuses the reopen and writes nothing" || fail "a section the record lacks refuses the reopen" "non-zero, unchanged" "rc=$RC"
rm -rf "$ROOT"

echo "-- Test: a single-section flag reopen now succeeds, and a reopen with nothing to write is refused --"
fresh_root
write_record "root" "single-flag" "2026-06-06" "Single flag" "pending" "pl"
F="$ROOT/.craft/decisions/2026-06-06-single-flag.md"
python3 - "$F" <<'PY'
import sys
p=sys.argv[1]
t=open(p,encoding='utf-8').read().replace("## Decision\n","## Decision\nkeep this\n\n")
open(p,'w',encoding='utf-8').write(t)
PY
OUT=$(bash "$CAPTURE" --reopen=2026-06-06-single-flag --context="flag ctx")
grep -q '^flag ctx$' "$F" && grep -q '^keep this$' "$F" && [ "$(printf '%s\n' "$OUT" | sed -n 1p)" = "Sections written: Context" ] && pass "one section flag rewrites only that section and prints the receipt" || fail "one section flag rewrites only that section" "flag ctx, keep this kept" "$OUT"
B=$(cat "$F")
set +e
bash "$CAPTURE" --reopen=2026-06-06-single-flag >/dev/null 2>&1
RC=$?
set -e
[ "$RC" -ne 0 ] && [ "$(cat "$F")" = "$B" ] && pass "a reopen naming no section is refused" || fail "a reopen naming no section is refused" "non-zero" "rc=$RC"
rm -rf "$ROOT"

echo "-- Test: the stdin grammar lives in one file, and both scripts call it --"
if [ -f "$PARSER" ] && grep -qF "'## Options considered':" "$PARSER" \
   && ! grep -qF "'## Options considered':" "$CAPTURE" "$VIEW" \
   && grep -qF 'decision-body-parser.py' "$CAPTURE" && grep -qF 'decision-body-parser.py' "$VIEW"; then
  pass "the heading table is in the parser alone and both scripts name the parser"
else
  fail "the heading table is in the parser alone and both scripts name the parser" "table only in the parser; capture and view call it" "parser exists: $([ -f "$PARSER" ] && echo yes || echo no)"
fi

echo "-- Test: one body through the parser, capture and the view reads the same sections --"
fresh_root
ONE_CTX="$(printf "It's \$HOME \360\237\216\211\n-n")"
ONE_BODY="$(printf '# One grammar\n\n## Context\n%s\n\n## Options considered\n- a\n- b\n\n## Decision\nPick a.\n\n## Consequences\nCosts a day.\n' "$ONE_CTX")"
PARSED=$(python3 "$PARSER" "$ONE_BODY")
P_CTX=$(printf '%s\n' "$PARSED" | sed -n 's/^CONTEXT=//p' | base64 -d)
[ "$P_CTX" = "$ONE_CTX" ] && pass "the parser's CONTEXT decodes to the input bytes" || fail "the parser's CONTEXT decodes to the input bytes" "$ONE_CTX" "$P_CTX"
ONE_F=$(printf '%s\n' "$ONE_BODY" | bash "$CAPTURE" --tag=one --stdin --created=2026-06-10)
C_CTX=$(sed -n '/^## Context$/,/^## Options considered$/p' "$ONE_F" | sed '1d;$d' | sed '$d')
[ "$C_CTX" = "$ONE_CTX" ] && pass "the record capture writes holds the same Context bytes" || fail "the record capture writes holds the same Context bytes" "$ONE_CTX" "$C_CTX"
ONE_CARD=$(printf '%s\n' "$ONE_BODY" | bash "$VIEW" card --variant=reopen --file="$ONE_F" --stdin)
if echo "$ONE_CARD" | grep -q '^MARK=' && ! echo "$ONE_CARD" | grep -qE '^MARK=[-+]'; then
  pass "the view reads the same body as unchanged against the record capture wrote"
else
  fail "the view reads the same body as unchanged against the record capture wrote" "MARK= lines, none - or +" "$ONE_CARD"
fi
rm -rf "$ROOT"

echo "-- Test: an empty Approval files pending, byte-identical to no Approval --"
fresh_root
EA_BODY=$(printf '# Empty approval\n\n## Context\nc\n\n## Options considered\no\n\n## Decision\nd\n\n## Consequences\nk\n')
EA_NONE=$(printf '%s\n' "$EA_BODY" | bash "$CAPTURE" --tag=ea --stdin --created=2026-06-11)
cp "$EA_NONE" "$ROOT/none.md"; rm "$EA_NONE"
EA_EMPTY=$(printf '%s\n\n## Approval\n\n' "$EA_BODY" | bash "$CAPTURE" --tag=ea --stdin --created=2026-06-11)
if cmp -s "$ROOT/none.md" "$EA_EMPTY" && [ "$(dirname "$EA_EMPTY")" = "$ROOT/.craft/decisions" ]; then
  pass "an empty Approval files pending in the root, byte-identical to no Approval"
else
  fail "an empty Approval files pending in the root, byte-identical to no Approval" "identical bytes, root" "$EA_EMPTY"
fi
rm -rf "$ROOT"

echo "-- Test: transition refuses an unknown flag on every verb and touches nothing --"
fresh_root
write_record "root" "flag-accept" "2026-07-01" "Flag accept" "pending" "tag-a"
write_record "root" "flag-decline" "2026-07-02" "Flag decline" "pending" "tag-a"
write_record "approved" "flag-deprecate" "2026-07-03" "Flag deprecate" "accepted" "tag-a"
write_record "approved" "flag-craft" "2026-07-04" "Flag craft" "accepted" "tag-a"
write_record "approved" "flag-retag" "2026-07-05" "Flag retag" "accepted" "tag-a"
tree_hash() { (cd "$ROOT" && find . -type f ! -name '*.err' | sort | xargs shasum); }
BEFORE_TREE=$(tree_hash)
for spec in "2026-07-01-flag-accept accept" "2026-07-02-flag-decline decline" "2026-07-03-flag-deprecate deprecate" "2026-07-04-flag-craft craft" "2026-07-05-flag-retag retag"; do
  read -r T_SLUG T_VERB <<< "$spec"
  set +e
  OUT=$(bash "$TRANSITION" "$T_SLUG" "$T_VERB" --quote="words" --story=s --tag=t --bogus=1 2>"$ROOT/t.err")
  RC=$?
  set -e
  ERR=$(cat "$ROOT/t.err")
  if [ "$RC" -eq 1 ] && [ -z "$OUT" ] && [ "$ERR" = "Error: unknown flag '--bogus=1'" ] && [ "$BEFORE_TREE" = "$(tree_hash)" ]; then
    pass "transition $T_VERB refuses an unknown flag and leaves every file alone"
  else
    fail "transition $T_VERB refuses an unknown flag and leaves every file alone" "exit 1, stderr names '--bogus=1', tree unchanged" "rc=$RC out='$OUT' err='$ERR'"
  fi
done
set +e
printf 'typed words\n' | bash "$TRANSITION" 2026-07-01-flag-accept accept --stdin --bogus=1 >/dev/null 2>"$ROOT/t.err"
RC=$?
set -e
[ "$RC" -eq 1 ] && [ "$(cat "$ROOT/t.err")" = "Error: unknown flag '--bogus=1'" ] && pass "transition refuses an unknown flag alongside --stdin" || fail "transition refuses an unknown flag alongside --stdin" "exit 1 naming the flag" "rc=$RC $(cat "$ROOT/t.err")"
rm -f "$ROOT/t.err"
set +e
OUT=$(bash "$TRANSITION" 2026-07-01-flag-accept accept --quote="ok" stray-positional 2>&1)
RC=$?
set -e
[ "$RC" -eq 0 ] && [ -f "$ROOT/.craft/decisions/approved/2026-07-01-flag-accept.md" ] && pass "transition still ignores a non-flag positional" || fail "transition still ignores a non-flag positional" "accepted" "rc=$RC $OUT"
rm -rf "$ROOT"

echo "-- Test: list still ignores an unknown flag --"
fresh_root
write_record "root" "list-flag" "2026-07-06" "List flag" "pending" "tag-a"
set +e
OUT=$(bash "$LIST" --bogus=1 2>"$ROOT/l.err")
RC=$?
set -e
[ "$RC" -eq 0 ] && [ ! -s "$ROOT/l.err" ] && echo "$OUT" | grep -q "^TITLE=List flag$" && pass "list ignores an unknown flag, exits 0 and still lists" || fail "list ignores an unknown flag, exits 0 and still lists" "exit 0, silent, listed" "rc=$RC $(cat "$ROOT/l.err")"
rm -rf "$ROOT"

echo "=== a multi-line typed answer keeps the quote marker on every line ==="
echo ""
# The typed answer is the audit trail, and the view reads a quote as a run
# of "> " lines. A line written without the marker falls out of the quote,
# and the date with it.
ML_TODAY=$(date +%Y-%m-%d)
ML_WANT=$(printf '> "Yes, blue.\n> But a deep blue, not sky." - %s, session' "$ML_TODAY")

echo "-- Test: accept --stdin with a two-line answer --"
fresh_root
write_record "root" "ml-accept" "2026-07-10" "Ml accept" "pending" "tag-a"
printf 'Yes, blue.\nBut a deep blue, not sky.\n' | bash "$TRANSITION" 2026-07-10-ml-accept accept --stdin > /dev/null
ML_GOT=$(tail -2 "$ROOT/.craft/decisions/approved/2026-07-10-ml-accept.md")
[ "$ML_GOT" = "$ML_WANT" ] && pass "accept: both answer lines carry the marker, date on the last" || fail "accept: both answer lines carry the marker, date on the last" "$ML_WANT" "$ML_GOT"
rm -rf "$ROOT"

echo "-- Test: capture --stdin with a two-line Approval section --"
fresh_root
ML_F=$(printf '# Ml capture\n\n## Context\nctx\n\n## Options considered\nopt\n\n## Decision\ndec\n\n## Consequences\ncons\n\n## Approval\nYes, blue.\nBut a deep blue, not sky.\n' | bash "$CAPTURE" --tag=ml --stdin | tail -1)
ML_GOT=$(tail -2 "$ML_F")
[ "$ML_GOT" = "$ML_WANT" ] && pass "capture: both answer lines carry the marker, date on the last" || fail "capture: both answer lines carry the marker, date on the last" "$ML_WANT" "$ML_GOT"
rm -rf "$ROOT"

echo "-- Test: reopen with a two-line answer --"
fresh_root
write_record "approved" "ml-reopen" "2026-07-11" "Ml reopen" "accepted" "tag-a"
ML_F=$(printf '## Context\nnew ctx\n\n## Approval\nYes, blue.\nBut a deep blue, not sky.\n' | bash "$CAPTURE" --reopen=2026-07-11-ml-reopen --stdin | tail -1)
ML_WANT_REOPEN=$(printf '> Reopen: "Yes, blue.\n> But a deep blue, not sky." - %s, session' "$ML_TODAY")
ML_GOT=$(tail -2 "$ML_F")
[ "$ML_GOT" = "$ML_WANT_REOPEN" ] && pass "reopen: both answer lines carry the marker, date on the last" || fail "reopen: both answer lines carry the marker, date on the last" "$ML_WANT_REOPEN" "$ML_GOT"
rm -rf "$ROOT"

echo "-- Test: a one-line answer is written exactly as before --"
fresh_root
write_record "root" "ml-one" "2026-07-12" "Ml one" "pending" "tag-a"
printf 'go\n' | bash "$TRANSITION" 2026-07-12-ml-one accept --stdin > /dev/null
ML_GOT=$(tail -1 "$ROOT/.craft/decisions/approved/2026-07-12-ml-one.md")
[ "$ML_GOT" = "> \"go\" - $ML_TODAY, session" ] && pass "one-line answer unchanged" || fail "one-line answer unchanged" "> \"go\" - $ML_TODAY, session" "$ML_GOT"
rm -rf "$ROOT"

echo "=== a write the script cannot make is refused, never reported as done ==="
echo ""
# write_bare_record ROOM SLUG DROP - a record missing one frontmatter line
# (DROP is tags or status), as a hand-made record might be.
write_bare_record() {
  local room="$1" slug="$2" drop="$3" dir="$ROOT/.craft/decisions"
  [ "$room" = "approved" ] && dir="$dir/approved"
  mkdir -p "$dir"
  {
    echo "---"
    echo "type: decision"
    [ "$drop" = "status" ] || { [ "$room" = "approved" ] && echo "status: accepted" || echo "status: pending"; }
    echo "created: 2026-08-01"
    echo "source: session"
    [ "$drop" = "tags" ] || echo "tags: [tag-a]"
    echo "---"
    echo "# Bare $slug"
  } > "$dir/2026-08-01-$slug.md"
}

echo "-- Test: craft on a record with no tags: and no disposition: is refused and writes nothing --"
fresh_root
write_bare_record "approved" "no-tags" "tags"
F="$ROOT/.craft/decisions/approved/2026-08-01-no-tags.md"
B=$(cat "$F")
set +e
OUT=$(bash "$TRANSITION" 2026-08-01-no-tags craft --story=s 2>"$ROOT/c.err")
RC=$?
set -e
[ "$RC" -ne 0 ] && pass "craft with no tags: line exits non-zero" || fail "craft with no tags: line exits non-zero" "non-zero" "rc=$RC out=$OUT"
[ "$(cat "$F")" = "$B" ] && pass "craft with no tags: line leaves the record unchanged" || fail "craft with no tags: line leaves the record unchanged" "$B" "$(cat "$F")"
if echo "$OUT" | grep -q '^CHANGED=1$'; then fail "craft with no tags: line never reports CHANGED=1" "no CHANGED=1" "$OUT"; else pass "craft with no tags: line never reports CHANGED=1"; fi
grep -q 'no tags: line' "$ROOT/c.err" && pass "the refusal names the missing tags: line" || fail "the refusal names the missing tags: line" "no tags: line" "stderr: $(cat "$ROOT/c.err")"
rm -rf "$ROOT"

echo "-- Test: story completion prints no Crafted: line for a record it could not mark --"
fresh_root
write_bare_record "approved" "no-tags-flip" "tags"
write_flip_story "2026-08-01-no-tags-flip" 1
run_flip
if echo "$FLIP_STDOUT" | grep -q '^Crafted: '; then fail "no Crafted: line for an unmarked record" "none" "$FLIP_STDOUT"; else pass "no Crafted: line for an unmarked record"; fi
echo "$FLIP_STDERR" | grep -q "^Warning: decision record '2026-08-01-no-tags-flip' could not be flipped to crafted" && pass "story completion warns about the unmarked record" || fail "story completion warns about the unmarked record" "Warning: ..." "stderr: $FLIP_STDERR"
[ "$FLIP_RC" -eq 1 ] && pass "story completion exits 1 when a record could not be marked" || fail "story completion exits 1 when a record could not be marked" "1" "$FLIP_RC"
rm -rf "$ROOT"

echo "=== a tag or story name is one list item ==="
echo ""
# tags: and stories: are bracketed, comma-separated lists, and the list
# script joins them with semicolons, so a name holding any of those - or a
# newline - would split into two names or break the list.

echo "-- Test: capture refuses a tag with a comma, semicolon, bracket or newline, and writes nothing --"
for bad in "home, page" "home;page" "home]" "[home" "$(printf 'home\npage')"; do
  fresh_root
  mkdir -p "$ROOT/.craft/decisions"
  set +e
  OUT=$(bash "$CAPTURE" "Bad tag" --tag="$bad" --context=c --options=o --decision=d --consequences=k 2>"$ROOT/t.err")
  RC=$?
  set -e
  LEFT=$(find "$ROOT/.craft" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$RC" -ne 0 ] && [ "$LEFT" = "0" ] && grep -q "is one name" "$ROOT/t.err" && pass "capture refuses tag $(printf '%q' "$bad")" || fail "capture refuses tag $(printf '%q' "$bad")" "non-zero, no record, 'is one name'" "rc=$RC files=$LEFT stderr=$(cat "$ROOT/t.err")"
  rm -rf "$ROOT"
done

echo "-- Test: retag refuses a target tag with a comma and leaves the record unchanged --"
fresh_root
write_record "approved" "bad-retag" "2026-08-02" "Bad retag" "accepted" "tag-a"
F="$ROOT/.craft/decisions/approved/2026-08-02-bad-retag.md"
B=$(cat "$F")
set +e
bash "$TRANSITION" 2026-08-02-bad-retag retag --tag="a, b" >/dev/null 2>"$ROOT/r.err"
RC=$?
set -e
[ "$RC" -ne 0 ] && [ "$(cat "$F")" = "$B" ] && grep -q "is one name" "$ROOT/r.err" && pass "retag refuses a comma tag, record unchanged" || fail "retag refuses a comma tag, record unchanged" "non-zero, unchanged, 'is one name'" "rc=$RC stderr=$(cat "$ROOT/r.err") file=$(grep '^tags:' "$F")"
rm -rf "$ROOT"

echo "-- Test: craft refuses a story name with a bracket and leaves the record unchanged --"
fresh_root
write_record "approved" "bad-story" "2026-08-03" "Bad story" "accepted" "tag-a"
F="$ROOT/.craft/decisions/approved/2026-08-03-bad-story.md"
B=$(cat "$F")
set +e
bash "$TRANSITION" 2026-08-03-bad-story craft --story="story-x]" >/dev/null 2>"$ROOT/s.err"
RC=$?
set -e
[ "$RC" -ne 0 ] && [ "$(cat "$F")" = "$B" ] && grep -q "is one name" "$ROOT/s.err" && pass "craft refuses a bracket story name, record unchanged" || fail "craft refuses a bracket story name, record unchanged" "non-zero, unchanged, 'is one name'" "rc=$RC stderr=$(cat "$ROOT/s.err") file=$(grep -E '^(disposition|stories):' "$F")"
rm -rf "$ROOT"

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
