#!/bin/bash
# check-doc-drift.sh - deterministic structural doc-drift check for the craft plugin.
#
# CONTRIBUTOR TOOLING - for developing craft ITSELF. It checks craft's own docs
# (agent-catalog, decision-tree, README, DESIGN) against craft's own source files.
# It is NOT a feature for projects built with craft - it is inert in any other repo.
#
# Caller-agnostic: reads no stdin, emits no JSON. exit 0 = clean, exit 1 = drift.
# Prints specific, actionable findings to stderr. Reusable by the push-gate
# wrapper, manual runs, a future CI job, and the guide agent's read-only query.
#
# Iron rule: every expected value is DERIVED FROM SOURCE (ls/grep over the live
# tree). Nothing about the inventory is hardcoded - a hardcoded number would
# itself drift, which is the exact bug this guards against.
#
# Guards STRUCTURAL truth only (counts, missing/renamed entries, orphans, a
# known retired string). Semantic truth (does a described flow match behavior?)
# is out of scope and handled elsewhere on demand.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || { echo "check-doc-drift: cannot resolve repo root" >&2; exit 1; }

BT='`'   # backtick literal, so the shell never tries to expand `...`

# --- Orphan-reference allowlist -------------------------------------------
# Reference docs that are legitimately NOT wired to a hook or command. Each
# entry REQUIRES a one-line reason. Adds appear in the commit diff, so a
# reviewer sees the bypass and the reason forces a conscious "yes, standalone."
ALLOWLIST=(
  # reference/decision-tree.md: human- and guide-facing orchestration map. Read
  #   directly by people and the guide agent; not invoked by any hook/command.
  "reference/decision-tree.md"
)

findings=()
add() { findings+=("$1"); }

# Print the body of a "## <Heading>" section up to the next "## " heading.
section() { awk -v s="$1" '$0==s{f=1;next} /^## /{f=0} f' "$2"; }

# Does haystack contain the exact `token` (backtick-delimited) ?
has_token() { printf '%s' "$1" | grep -qF "${BT}${2}${BT}"; }

# =========================================================================
# Tier A - trivial, high-value
# =========================================================================

# 1. Command parity: every entry-point appears in the Commands Reference.
#    Expected set = /craft (commands/craft.md) + /craft:<x> (commands/craft-*.md)
#    + skills invoked as commands, read from the machine-readable marker so the
#    list stays single-source (never hardcoded here).
cmd_ref="$(section '## Commands Reference' reference/decision-tree.md)"
# Unquoted $skill_cmds in the loop below is intentional - it word-splits the
# marker list on IFS (spaces and newlines), which handles one or many markers.
# Do not quote it.
skill_cmds="$(grep -oE '<!-- skill-commands:[^>]*-->' reference/decision-tree.md \
  | sed -E 's/<!-- skill-commands: *//; s/ *-->//' | tr ',' ' ')"
expected_cmds="/craft"
for f in commands/craft-*.md; do
  [ -e "$f" ] || continue
  expected_cmds="$expected_cmds /craft:$(basename "$f" .md | sed 's/^craft-//')"
done
for s in $skill_cmds; do expected_cmds="$expected_cmds /craft:$(echo "$s" | tr -d ' ')"; done
for c in $expected_cmds; do
  has_token "$cmd_ref" "$c" || add "[command] $c is a craft entry-point but is missing from the decision-tree Commands Reference"
done

# 2. Skill parity: every skill dir appears in the Skills Reference.
skill_ref="$(section '## Skills Reference' reference/decision-tree.md)"
for d in skills/*/; do
  [ -d "$d" ] || continue
  n="$(basename "$d")"
  has_token "$skill_ref" "$n" || add "[skill] $n exists but is missing from the decision-tree Skills Reference"
done

# 3. Agent parity x3: every agent appears in all three lists.
agents_dt="$(section '## Agents Reference' reference/decision-tree.md)"
agents_rm="$(section '## Agents' README.md)"
catalog="$(cat docs/agent-catalog.md)"
for f in agents/*.md; do
  [ -e "$f" ] || continue
  a="$(basename "$f" .md)"
  has_token "$catalog"   "$a" || add "[agent] $a is missing from docs/agent-catalog.md"
  has_token "$agents_dt" "$a" || add "[agent] $a is missing from the decision-tree Agents Reference"
  has_token "$agents_rm" "$a" || add "[agent] $a is missing from the README agents table"
done

# 4. Count strings: every "<N> agents|skills|commands" must equal the live count.
n_agents="$(ls -1 agents/*.md 2>/dev/null | wc -l | tr -d ' ')"
n_skills="$(ls -1d skills/*/ 2>/dev/null | wc -l | tr -d ' ')"
n_commands="$(ls -1 commands/craft*.md 2>/dev/null | wc -l | tr -d ' ')"
check_count() { # $1=word $2=live
  local n
  while read -r n; do
    [ -n "$n" ] && [ "$n" != "$2" ] && add "[count] a doc says \"$n $1\" but the live count is $2"
  done < <(grep -rhoE "[0-9]+ $1\b" README.md DESIGN.md docs/agent-catalog.md 2>/dev/null | grep -oE '^[0-9]+')
}
check_count agents   "$n_agents"
check_count skills   "$n_skills"
check_count commands "$n_commands"

# =========================================================================
# Tier B - cheap insurance
# =========================================================================

# 5. No orphan reference docs: each reference/ file is wired somewhere, or on
#    the allowlist (with a stated reason).
for f in reference/*.md reference/*.min; do
  [ -e "$f" ] || continue
  skip=0
  for a in "${ALLOWLIST[@]}"; do [ "$a" = "$f" ] && skip=1; done
  [ "$skip" = 1 ] && continue
  base="$(basename "$f")"
  grep -rqF "$base" hooks/ commands/ skills/ agents/ 2>/dev/null \
    || add "[orphan] reference/$base is referenced by no hook/command/skill/agent and is not on the allowlist"
done

# 6. Forbidden-stale sentinel: the retired validation-invocation pattern must
#    not appear in the public docs (the live loop invokes the chunk-validator
#    agent via Task; the skill is manual-only).
sentinel="$(grep -rln 'validate-chunk via Skill\|Invoke validate-chunk skill' \
  reference/ docs/ README.md DESIGN.md 2>/dev/null)"
[ -n "$sentinel" ] && add "[sentinel] retired 'validate-chunk via Skill' wording found in: $(echo $sentinel | tr '\n' ' ')"

# 7. Reference-path existence: every references/<path>.md named in a decision
#    -tree node must resolve (allow a commands/ prefix, since some nodes write
#    the path relative to commands/).
while read -r p; do
  [ -z "$p" ] && continue
  [ -e "$p" ] || [ -e "commands/$p" ] || add "[refpath] decision-tree names '$p' but no such file exists"
done < <(grep -oE '(commands/)?references/[A-Za-z0-9_./-]+\.md' reference/decision-tree.md | sort -u)

# 8. Changelog sanity: entries are notable-only (features and user-visible
#    fixes), so the newest entry may LAG plugin.json - internal changes bump
#    with no entry - but it must never be AHEAD of it or malformed. Ahead
#    means release notes exist for a version that doesn't.
#    Format: "## <version> - <YYYY-MM-DD>" headings, newest first. Every
#    heading (not just the newest) must carry a date - a date-less heading
#    is a format regression, not an older style.
plugin_version="$(grep -oE '"version": *"[^"]+"' .claude-plugin/plugin.json 2>/dev/null \
  | sed -E 's/.*"([^"]+)"$/\1/')"
top_entry="$(grep -m1 -E '^## ' CHANGELOG.md 2>/dev/null | sed -E 's/^## +//')"
top_version="$(printf '%s' "$top_entry" | sed -E 's/ - [0-9]{4}-[0-9]{2}-[0-9]{2}$//')"
if [ -z "$plugin_version" ]; then
  add "[changelog] cannot read a version from .claude-plugin/plugin.json"
elif [ -z "$top_entry" ]; then
  add "[changelog] CHANGELOG.md has no '## <version> - <date>' entries"
elif ! printf '%s' "$top_entry" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+ - [0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  add "[changelog] CHANGELOG.md's newest heading '## $top_entry' is not '<version> - <YYYY-MM-DD>'"
elif [ "$(printf '%s\n%s\n' "$top_version" "$plugin_version" | sort -V | tail -1)" != "$plugin_version" ]; then
  add "[changelog] CHANGELOG.md's newest entry ($top_version) is ahead of plugin.json ($plugin_version)"
fi
while read -r h; do
  [ -z "$h" ] && continue
  add "[changelog] heading '## $h' is missing its date - format is '## <version> - <YYYY-MM-DD>'"
done < <(grep -E '^## ' CHANGELOG.md 2>/dev/null | sed -E 's/^## +//' \
  | grep -vE '^[0-9]+\.[0-9]+\.[0-9]+ - [0-9]{4}-[0-9]{2}-[0-9]{2}$')

# 9. Feature release notes: an unpushed feat: commit must be accompanied by a
#    CHANGELOG.md change somewhere in the unpushed range - a feature cannot
#    ship without release notes. Fixes stay a judgment call (notable-only).
#    Runs only when an upstream exists; fails open elsewhere (CI on a merged
#    tree has no unpushed range to judge).
if upstream="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null)"; then
  feat_commits="$(git log --format='%h %s' "$upstream"..HEAD 2>/dev/null \
    | grep -E '^[0-9a-f]+ feat[(!:]' || true)"
  if [ -n "$feat_commits" ] \
    && ! git diff --name-only "$upstream"..HEAD 2>/dev/null | grep -qxF 'CHANGELOG.md'; then
    add "[changelog] feat commit(s) about to push with no CHANGELOG.md entry in the range: $(printf '%s' "$feat_commits" | head -3 | tr '\n' ';')"
  fi
fi

# =========================================================================
# Tier C - DEFERRED (not v1). Intentionally not enforced yet:
#   - analysis-type parity: assert pending/*.yaml types == the types named in
#     the decision-tree directory block (walkthrough.yaml et al.)
#   - state-key spot check: every Key Field in the State Files table appears as
#     a real token somewhere in commands/skills/hooks (catches invented fields).
# =========================================================================

# --- Verdict --------------------------------------------------------------
if [ "${#findings[@]}" -eq 0 ]; then
  exit 0
fi
{
  echo "Documentation drift detected (${#findings[@]} issue(s)) - docs no longer match source:"
  for f in "${findings[@]}"; do echo "  - $f"; done
  echo ""
  echo "Fix the docs to match the source files above, then retry."
} >&2
exit 1
