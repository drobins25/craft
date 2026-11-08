#!/bin/bash
# test-decisions-wiring.sh - Structural coverage for /craft:decisions wiring
#
# The command file's routing rule now lives ONLY in its dot graph: a
# question is a diamond, an answer is a one-word arrow label, a
# destination is a node. This test never holds a byte-pinned copy of that
# graph - it parses it and asserts structure (labels defined, fan-out
# bounded, every node reachable, no script call hiding in prose) the same
# way evals/check-edges.sh does, and reuses that script's own edge and
# node grammar deliberately, so the two parsers never drift apart by
# reading the fence two different ways.
#
# The prose below the graph is technique only (the drawing rule,
# card-authoring rules, receipts) - what survives it is a capped, named
# list of literal phrases, not a growing pile of ad hoc greps.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$SCRIPT_DIR/.."
CMD="$REPO/commands/craft-decisions.md"

PASS_COUNT=0; FAIL_COUNT=0; TOTAL=0
pass() { PASS_COUNT=$((PASS_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    Expected: $2"; [ -n "${3:-}" ] && echo "    Got:      $3"; return 0; }

echo "=== test-decisions-wiring.sh ==="
echo ""

if [ ! -e "$CMD" ]; then
  fail "commands/craft-decisions.md exists" "file present" "absent"
  echo ""
  echo "-- Summary --"
  echo "Total:  $TOTAL"
  echo "Passed: $PASS_COUNT"
  echo "Failed: $FAIL_COUNT"
  exit 1
fi

# ---------------------------------------------------------------------
# Frontmatter: exactly four keys, in order, values match the ruled record
# ---------------------------------------------------------------------
echo "-- Test: frontmatter is exactly the four ruled keys, in order --"
FRONTMATTER="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$CMD")"
TOP_KEYS="$(printf '%s\n' "$FRONTMATTER" | grep -oE '^[a-zA-Z_-]+:' | sed 's/:$//')"
EXPECTED_KEYS=$'name\ndescription\nwhen_to_use\nargument-hint'
if [ "$TOP_KEYS" = "$EXPECTED_KEYS" ]; then
  pass "frontmatter keys are name, description, when_to_use, argument-hint, in order, and no others"
else
  fail "frontmatter keys are name, description, when_to_use, argument-hint, in order, and no others" "$EXPECTED_KEYS" "$TOP_KEYS"
fi

echo "-- Test: description and when_to_use match the frontmatter record, whitespace-normalized --"
# A tracked copy of the frontmatter ruling - this repo's own decision store is
# gitignored, so CI has no .craft/ to read it from
RECORD="$SCRIPT_DIR/fixtures/decision-records/2026-09-05-the-decisions-skill-frontmatter.md"
norm() { tr '\n' ' ' <<<"$1" | tr -s ' ' | sed 's/^ *//; s/ *$//'; }
if [ -s "$RECORD" ]; then
  pass "the frontmatter record fixture exists"
else
  fail "the frontmatter record fixture exists" "$RECORD" "absent"
  RECORD=/dev/null
fi

RECORD_DESC="$(sed -n '/^  description: "The Shelf/,/topic\."/p' "$RECORD")"
CMD_DESC="$(sed -n '/^description: "The Shelf/,/topic\."/p' "$CMD")"
if [ "$(norm "$RECORD_DESC")" = "$(norm "$CMD_DESC")" ]; then
  pass "description matches the frontmatter record (whitespace-normalized)"
else
  fail "description matches the frontmatter record (whitespace-normalized)" "$(norm "$RECORD_DESC")" "$(norm "$CMD_DESC")"
fi

RECORD_WTU="$(sed -n '/^  when_to_use: |/,/^  argument-hint:/p' "$RECORD" | sed '1d;$d')"
CMD_WTU="$(sed -n '/^when_to_use: |/,/^argument-hint:/p' "$CMD" | sed '1d;$d')"
if [ "$(norm "$RECORD_WTU")" = "$(norm "$CMD_WTU")" ]; then
  pass "when_to_use matches the frontmatter record (whitespace-normalized)"
else
  fail "when_to_use matches the frontmatter record (whitespace-normalized)" "$(norm "$RECORD_WTU")" "$(norm "$CMD_WTU")"
fi

# ---------------------------------------------------------------------
# The routing graph, parsed structurally (never held as a literal copy)
# ---------------------------------------------------------------------
echo "-- Test: the routing graph's structure (labels, definitions, fan-out, reachability, no hidden routing) --"
# The parser is written to a scratch file first, rather than piped in via a
# heredoc directly inside a $(...) substitution - bash 3.2 (macOS's system
# bash) mishandles an apostrophe in a quoted heredoc's body when that
# heredoc sits inside a command substitution, and several sentences below
# have one.
GRAPH_SCRIPT="$(mktemp)"
trap 'rm -f "$GRAPH_SCRIPT"' EXIT
cat > "$GRAPH_SCRIPT" <<'PYEOF'
import re
import sys

command_file = sys.argv[1]
text = open(command_file).read()

SCRIPTS = ["decisions-list.sh", "decisions-view.sh", "decisions-capture.sh", "decisions-transition.sh"]


def out(status, desc, expected="", got=""):
    line = f"{status}: {desc}"
    if expected:
        line += f"\n    Expected: {expected}"
    if got:
        line += f"\n    Got:      {got}"
    print(line)


# --- locate the routing fence (same selection rule as evals/check-edges.sh:
# the fence whose own first line is "digraph decisions {", not the first
# fence in the file - the hard-gate block above it is a plain, non-dot
# fence, so this only matters if that ever changes) -----------------------
BACKTICKS = chr(96) * 3
fence_match = None
for m in re.finditer(BACKTICKS + r"dot\n(.*?)\n" + BACKTICKS, text, re.DOTALL):
    if m.group(1).lstrip().startswith("digraph decisions {"):
        fence_match = m
        break
if fence_match is None:
    out("FAIL", "a fenced dot block starting with 'digraph decisions {' exists")
    sys.exit(0)
fence_body = fence_match.group(1)
above_fence = text[: fence_match.start()]
below_fence = text[fence_match.end():]

# --- parse edges and nodes (same grammar as evals/check-edges.sh) --------
def parse_edges(body):
    edges = []
    for raw in body.splitlines():
        line = raw.strip()
        if '" -> "' not in line:
            continue
        left, _, right = line.partition('" -> "')
        if not left.startswith('"'):
            continue
        src = left[1:]
        m = re.match(r'^(?P<dst>.*?)"\s*(\[label="(?P<label>.*)"\])?;\s*$', right)
        if not m:
            continue
        edges.append((src, m.group("dst"), m.group("label") or ""))
    return edges


def parse_nodes(body):
    nodes = {}
    for raw in body.splitlines():
        line = raw.strip()
        if '" -> "' in line:
            continue
        m = re.match(r'^"(?P<name>(?:[^"\\]|\\.)*)"\s*\[(?P<attrs>[^\]]*)\]\s*;\s*$', line)
        if not m:
            continue
        nodes[m.group("name")] = m.group("attrs")
    return nodes


edges = parse_edges(fence_body)
node_attrs = parse_nodes(fence_body)


def shape_of(attrs):
    m = re.search(r"shape\s*=\s*(\w+)", attrs or "")
    return m.group(1) if m else None


shapes = {name: shape_of(attrs) for name, attrs in node_attrs.items()}
diamonds = [n for n, s in shapes.items() if s == "diamond"]
doublecircles = [n for n, s in shapes.items() if s == "doublecircle"]

# --- definitions section: "## Words the graph uses" up to the next "## " -
def_section_match = re.search(
    r"## Words the graph uses\n(.*?)\n## ", text, re.DOTALL
)
def_section = def_section_match.group(1) if def_section_match else ""

TERM_RE = re.compile(r"^- \*\*(.+?)\*\* - ", re.MULTILINE)
defined_terms = set()
for term_group in TERM_RE.findall(def_section):
    for term in term_group.split("/"):
        defined_terms.add(term.strip().lower())

def_text_lower = def_section.lower()

# --- 1: every arrow leaving a diamond is labelled and its label defined -
undefined_labels = []
unlabelled_diamond_exits = []
fanout_violations = []
for d in diamonds:
    exits = [e for e in edges if e[0] == d]
    if len(exits) > 3:
        fanout_violations.append((d, len(exits)))
    for src, dst, label in exits:
        if not label:
            unlabelled_diamond_exits.append((src, dst))
        elif label.lower() not in defined_terms:
            undefined_labels.append((src, label))

if unlabelled_diamond_exits:
    out("FAIL", "every arrow leaving a diamond carries a label", "labelled", str(unlabelled_diamond_exits))
else:
    out("PASS", "every arrow leaving a diamond carries a label")

if undefined_labels:
    out("FAIL", "every label leaving a diamond has a definitions bullet", "defined", str(undefined_labels))
else:
    out("PASS", "every label leaving a diamond has a definitions bullet")

if fanout_violations:
    out("FAIL", "no diamond asks more than three ways", "<= 3 exits", str(fanout_violations))
else:
    out("PASS", "no diamond asks more than three ways")

# --- 2: every word of every diamond's own name has a definitions bullet -
# Fuzzy on purpose: a diamond name uses ordinary English around its
# technical words ("Which face does the record call for?"), and a
# definition is written in its own sentence, not as a repeated token - so
# a word is "covered" when a same-rooted word (its first 4 letters, or the
# whole word if shorter) appears anywhere in the definitions section
# (heading terms or body prose alike). This still catches the conductor's
# original catch (a word like "changed" with no definition anywhere would
# not match any 4-letter root in the section) without demanding the exact
# grammatical form of every connector.
STOPWORDS = {
    "the", "a", "an", "with", "on", "or", "for", "is", "are", "do", "does",
    "how", "many", "which", "named", "ask", "call", "as", "at", "of", "to",
    "in", "card", "cards", "decision", "question", "reopen",
}

diamond_word_gaps = []
for d in diamonds:
    words = re.findall(r"[a-zA-Z']+", d.lower())
    for w in words:
        if len(w) <= 2 or w in STOPWORDS:
            continue
        root = w[:4] if len(w) >= 4 else w
        if root not in def_text_lower:
            diamond_word_gaps.append((d, w))

if diamond_word_gaps:
    out("FAIL", "every word of every diamond's own name has a definitions bullet", "covered", str(diamond_word_gaps))
else:
    out("PASS", "every word of every diamond's own name has a definitions bullet")

# --- 3: reachability from the entry double circles -----------------------
adjacency = {}
for src, dst, _ in edges:
    adjacency.setdefault(src, []).append(dst)

reachable = set()
frontier = list(doublecircles[:2]) if len(doublecircles) >= 2 else list(doublecircles)
# Entry points are "Command invoked" and "Ruling in conversation" by name,
# not merely "the first two doublecircles" - falls back to all doublecircles
# only if those two aren't present, so a reordering of the node block never
# silently changes which nodes count as entries.
entries = [n for n in ("Command invoked", "Ruling in conversation") if n in shapes]
frontier = entries if entries else frontier
seen = set(frontier)
queue = list(frontier)
while queue:
    node = queue.pop()
    reachable.add(node)
    for nxt in adjacency.get(node, []):
        if nxt not in seen:
            seen.add(nxt)
            queue.append(nxt)

declared = set(shapes.keys())
unreachable = sorted(declared - reachable)
if unreachable:
    out("FAIL", "every declared node is reachable from an entry double circle", "none", str(unreachable))
else:
    out("PASS", "every declared node is reachable from an entry double circle")

# --- 4: no routing hides in an arrow label --------------------------------
bad_labels = [
    (s, d, l) for s, d, l in edges
    if l and (".sh" in l or re.search(r"(^|\s)-{1,2}[A-Za-z]", l))
]
if bad_labels:
    out("FAIL", "no arrow label contains a .sh name or a - flag", "none", str(bad_labels))
else:
    out("PASS", "no arrow label contains a .sh name or a - flag")

# --- 5: script calls are plaintext nodes, and only script calls are ------
mismatched_shape = [
    n for n in shapes
    if any(s in n for s in SCRIPTS) and shapes[n] != "plaintext"
]
# The one plaintext node that is not a script call: reading a parked or
# retire record's own file, which every card face already has the path of.
FILE_READ_NODE = "cat <FILE>"
mismatched_prefix = [
    n for n, s in shapes.items()
    if s == "plaintext" and n != FILE_READ_NODE and not any(n.startswith(s2) for s2 in SCRIPTS)
]
if shapes.get(FILE_READ_NODE) != "plaintext":
    mismatched_prefix.append("missing plaintext node: " + FILE_READ_NODE)
if mismatched_shape or mismatched_prefix:
    out(
        "FAIL",
        "every node naming a decisions script is shape=plaintext and every plaintext node's name begins with one (or is the one file read)",
        "consistent",
        str(mismatched_shape + mismatched_prefix),
    )
else:
    out("PASS", "every node naming a decisions script is shape=plaintext and every plaintext node's name begins with one (or is the one file read)")

# --- 6: the never-bend rules are a hard gate, and the one octagon is red -
hard_gate_blocks = re.findall(r"<HARD-GATE>\n(.*?)\n</HARD-GATE>", text, re.DOTALL)
if len(hard_gate_blocks) != 1:
    out("FAIL", "exactly one <HARD-GATE> block", "1", str(len(hard_gate_blocks)))
else:
    lines = [l for l in hard_gate_blocks[0].splitlines() if l.strip()]
    non_never = [l for l in lines if not l.strip().startswith("NEVER")]
    if len(lines) != 9:
        out("FAIL", "the hard gate holds exactly nine rules", "9", str(len(lines)))
    elif non_never:
        out("FAIL", "every hard gate rule begins with NEVER", "all begin NEVER", str(non_never))
    else:
        out("PASS", "the hard gate holds exactly nine rules, each beginning NEVER")

octagons = [n for n, s in shapes.items() if s == "octagon"]
if len(octagons) != 1:
    out("FAIL", "exactly one octagon sits inside the routing graph", "1", str(len(octagons)))
else:
    attrs = node_attrs[octagons[0]]
    if "style=filled" in attrs.replace(" ", "") and "fillcolor=red" in attrs.replace(" ", ""):
        out("PASS", "the one octagon carries style=filled and fillcolor=red")
    else:
        out("FAIL", "the one octagon carries style=filled and fillcolor=red", "style=filled, fillcolor=red", attrs)

# --- 7: the reopen diff is the only card the view script draws ----------
# Every other card is drawn from text already in the conversation, so
# exactly one plaintext node calls "decisions-view.sh card", it is the
# reopen draw, and the reopen card is the only state that feeds it.
view_card_nodes = [n for n in shapes if "decisions-view.sh card" in n]
if len(view_card_nodes) != 1:
    out("FAIL", "exactly one plaintext node calls decisions-view.sh card", "1", str(view_card_nodes))
else:
    view_card_node = view_card_nodes[0]
    feeders = sorted({s_ for s_, d_, _ in edges if d_ == view_card_node})
    if "--variant=reopen" in view_card_node and feeders == ["Reopen card on screen"]:
        out("PASS", "the only decisions-view.sh card call is the reopen draw, fed only by the reopen card")
    else:
        out("FAIL", "the only decisions-view.sh card call is the reopen draw, fed only by the reopen card", "--variant=reopen fed by Reopen card on screen", f"{view_card_node} <- {feeders}")

# --- section bounds: "## The four scripts" up to "## How to read the graph" -
# The contracts live in their own section, the one place a script name or
# the plugin-root path may appear outside the flag table and the graph.
SCRIPTS_HEADING = "## The four scripts\n"
sec_start = text.find(SCRIPTS_HEADING)
sec_end = text.find("\n## How to read the graph", sec_start + 1) if sec_start >= 0 else -1
if sec_start < 0 or sec_end < 0:
    out("FAIL", "the file has '## The four scripts' before '## How to read the graph'", "both headings, in that order", f"start={sec_start} end={sec_end}")
    scripts_section = ""
    above_outside_section = above_fence
else:
    out("PASS", "the file has '## The four scripts' before '## How to read the graph'")
    scripts_section = text[sec_start:sec_end]
    above_outside_section = text[:sec_start] + text[sec_end:fence_match.start()]

# --- 8: no decisions script name outside the fence, the flag table and the scripts section
def strip_table_rows(s):
    return "\n".join(l for l in s.splitlines() if not l.strip().startswith("|"))

below_hits = [name for name in SCRIPTS if name in below_fence]
above_hits = [name for name in SCRIPTS if name in strip_table_rows(above_outside_section)]
if below_hits:
    out("FAIL", "no decisions script name appears below the routing fence", "none", str(below_hits))
else:
    out("PASS", "no decisions script name appears below the routing fence")
if above_hits:
    out("FAIL", "above the fence, a decisions script name appears only in the flag table or ## The four scripts", "none outside them", str(above_hits))
else:
    out("PASS", "above the fence, a decisions script name appears only in the flag table or ## The four scripts")

# --- 9: a write arrow's label never doubles as a pre-card word ------------
# Pre-card = a node reachable from an entry before any card is on screen and
# NOT reachable from any card. A card is an ellipse that feeds a "Move on"
# diamond; the Shelf and the match drawer are ellipses too but draw no card,
# so they are walked through. A gate a card's
# path can also reach (the crafted? diamonds) is not a pre-card node - its
# answers come from data, not from what the user typed at the Shelf. The
# retag write is exempt: the hard gate rules that a retag draws no card.
cards = {n for n, s in shapes.items() if s == "ellipse"
         and any(nxt.startswith("Move on") for nxt in adjacency.get(n, []))}
def reach(starts, stop_at=frozenset()):
    seen = set(starts); q = list(starts)
    while q:
        node = q.pop()
        if node in stop_at and node not in starts: continue
        for nxt in adjacency.get(node, []):
            if nxt not in seen: seen.add(nxt); q.append(nxt)
    return seen
postcard = reach(cards)
precard = {n for n in reach(entries, stop_at=cards) if n not in postcard and n not in cards}
precard_labels = {l for s_, d_, l in edges if l and s_ in precard}
write_nodes = {n for n, s in shapes.items() if s == "plaintext" and ("decisions-transition.sh" in n or "decisions-capture.sh" in n)}
collisions = sorted({(l, d_) for s_, d_, l in edges if d_ in write_nodes and l and l in precard_labels and " retag " not in d_})
if collisions: out("FAIL", "no arrow into a write carries a label that also leaves a pre-card node (retag exempt)", "none", str(collisions))
else: out("PASS", "no arrow into a write carries a label that also leaves a pre-card node (retag exempt)")

# --- 10: the scripts' location sits only inside ## The four scripts ------
# Every other command that runs a script writes its plugin path; the desk
# named its scripts bare and a fresh session opened with `find` for them.
# The section carries the path with the variable Claude Code substitutes at
# load, never a resolved path. Command nodes stay bare: a plaintext node is
# the literal command, so no plaintext node may carry a path of its own, and
# no line may start a call with a bare script name (it would run from
# wherever the model last cd'd to).
LOC = "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/"
loc_total = text.count(LOC)
loc_in_section = scripts_section.count(LOC)
pathed_nodes = sorted(n for n, s in shapes.items() if s == "plaintext" and "/" in n)
bare_calls = [l for l in text.splitlines() if re.match(r"\s*bash\s+decisions-", l)]
if loc_total == loc_in_section and loc_in_section >= 5 and not pathed_nodes and not bare_calls:
    out("PASS", "the scripts' location sits only inside ## The four scripts, and no command node carries a path")
else:
    out("FAIL", "the scripts' location sits only inside ## The four scripts, and no command node carries a path", "all inside the section, at least 5, no pathed nodes, no bare calls", f"total={loc_total} in_section={loc_in_section} pathed_nodes={pathed_nodes} bare_calls={bare_calls}")

# --- 11: each script has an example in the absolute form ------------------
for name in SCRIPTS:
    call = 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/' + name + '"'
    if any(call in l for l in scripts_section.splitlines()):
        out("PASS", f"the section has an absolute-form example line for {name}")
    else:
        out("FAIL", f"the section has an absolute-form example line for {name}", call, "absent")

# --- 12: the opener states the form and where it runs from ----------------
opener = " ".join(scripts_section.split("\n", 2)[-1].split()) if scripts_section else ""
first_para = opener.split(" ```")[0]
if 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/<name>.sh"' in first_para and "from wherever the session is" in first_para:
    out("PASS", "the section opens with the absolute-form sentence, run from wherever the session is")
else:
    out("FAIL", "the section opens with the absolute-form sentence, run from wherever the session is", "literal form plus 'from wherever the session is'", first_para[:200])

# --- 13: the nine-key exhibit appears once, keys in order -----------------
EXHIBIT = [
    "FILE=/home/you/app/.craft/decisions/approved/2026-03-14-search-ranks-titles-first.md",
    "ROOM=approved",
    "SLUG=2026-03-14-search-ranks-titles-first",
    "DATE=2026-03-14",
    "TITLE=Search ranks titles first",
    "STATUS=accepted",
    "TAGS=search",
    "DISPOSITION=claimed",
    "STORIES=search-results-page",
]
exhibit_text = "\n".join(EXHIBIT)
if text.count(exhibit_text) == 1 and scripts_section.count(exhibit_text) == 1 and text.count("FILE=/home/you/app/") == 1:
    out("PASS", "the nine-key exhibit appears exactly once, keys in order, inside the section")
else:
    out("FAIL", "the nine-key exhibit appears exactly once, keys in order, inside the section", "1", f"total={text.count(exhibit_text)} in_section={scripts_section.count(exhibit_text)}")

sec_flat_pre = " ".join(scripts_section.split())
# --- 13b: the match example feeds only the matched blocks -----------------
# Bug 2026-09-30-match-drawer-drawn-from-the-whole-store: the view block
# must say match draws every block it is given, and show two --slug= lists
# piped into it, so a reader never pipes the whole store in.
match_lines = [l for l in scripts_section.split("\n")
               if 'decisions-view.sh" match' in l and l.count("--slug=") >= 2]
if "match draws every block it is given" in sec_flat_pre and len(match_lines) == 1:
    out("PASS", "the view block says match draws only what it is given and shows a two-slug match example")
else:
    out("FAIL", "the view block says match draws only what it is given and shows a two-slug match example", "fact + 1 example line with two --slug=", f"fact={'match draws every block it is given' in sec_flat_pre} examples={len(match_lines)}")

# --- 13c: the capture contract states the fork options and the reopen rule -
# Bug 2026-09-30-fresh-question-card-still-reads-script-source: the facts the
# desk opened the scripts to find. The write takes its body on stdin; a
# reopen sends only what changed and prints which sections it wrote.
fork_ok = '"(a) Proposed: ..."' in sec_flat_pre and 'a settled ruling is "- " lines' in sec_flat_pre
reopen_ok = (
    "only the sections that changed" in sec_flat_pre
    and "Sections written:" in sec_flat_pre
    and "on law it requires an ## Approval section, in the root it refuses one" in sec_flat_pre
    and "re-sends all four sections" not in sec_flat_pre
)
if fork_ok and reopen_ok:
    out("PASS", "the capture block states the lettered fork options and the partial-reopen rule")
else:
    out("FAIL", "the capture block states the lettered fork options and the partial-reopen rule", "both facts", f"fork={fork_ok} reopen={reopen_ok}")
flag_table_rows = [l for l in text.split("\n") if l.startswith("| fresh question card |") or l.startswith("| Card face |")]
if not flag_table_rows:
    out("PASS", "the flag table of draw-node flags is gone")
else:
    out("FAIL", "the flag table of draw-node flags is gone", "no table rows", str(flag_table_rows))

# --- 14: the find line and the glyph-to-folder line -----------------------
if "find .craft/decisions -name '*-<slug>.md'" in scripts_section:
    out("PASS", "the find-by-name line is present verbatim")
else:
    out("FAIL", "the find-by-name line is present verbatim", "find .craft/decisions -name '*-<slug>.md'", "absent")
sec_flat = " ".join(scripts_section.split())
if "archive/" in sec_flat and "approved/" in sec_flat and "never on the Shelf" in sec_flat:
    out("PASS", "the section maps each glyph to its folder and keeps the archive off the Shelf")
else:
    out("FAIL", "the section maps each glyph to its folder and keeps the archive off the Shelf", "approved/, archive/, never on the Shelf", "absent")

# --- 15: the hard gate is the pinned eight lines --------------------------
GATE = [
    "NEVER use AskUserQuestion here - the answer is typed into the prompt.",
    "NEVER write a record file by hand - every write is a call on the graph.",
    "NEVER draw a card from memory - draw it from the record text in the conversation, and after any write read the file again before drawing it.",
    "NEVER let a box-drawing character into a script's stdout - the rail is drawn here.",
    "NEVER relay a script's error line as the answer.",
    "NEVER render anything below the Shelf unasked.",
    "NEVER select with subcommand syntax - selection is the list filters.",
    "NEVER draw a card, take a quote or write an approval line for a retag.",
    "NEVER treat the desk as open once the card the user asked about is ruled or put away - a later ruling in conversation is just conversation until they type the command again or call it a decision.",
]
gate_m = re.search(r"<HARD-GATE>\n(.*?)\n</HARD-GATE>", text, re.DOTALL)
gate_lines = [l for l in gate_m.group(1).splitlines() if l.strip()] if gate_m else []
if gate_lines == GATE:
    out("PASS", "the hard gate is the pinned nine NEVER lines")
else:
    out("FAIL", "the hard gate is the pinned nine NEVER lines", str(GATE), str(gate_lines))

# --- 15b: the graph's second entry is defined narrowly --------------------
# "Ruling in conversation" is an entry node into the desk. The command body
# stays loaded for the rest of a session once typed, so without a narrow
# definition a ruling said in passing could read as a way back in.
RULING_DEF = '- **a ruling in conversation** - the user calls it a decision ("save this as a decision", "make that a decision") or types the command again; "go with that" and "yes, do it" said in passing are just conversation.'
def_lines = def_section.splitlines()
if RULING_DEF in def_lines and "a ruling in conversation" in defined_terms:
    rec_idx = next((i for i, l in enumerate(def_lines) if l.startswith("- **a record** - ")), -1)
    if rec_idx >= 0 and rec_idx + 1 < len(def_lines) and def_lines[rec_idx + 1] == RULING_DEF:
        out("PASS", "the words list defines a ruling in conversation narrowly, directly after a record")
    else:
        out("FAIL", "the words list defines a ruling in conversation narrowly, directly after a record", "the line directly after - **a record**", "elsewhere in the list")
else:
    out("FAIL", "the words list defines a ruling in conversation narrowly, directly after a record", RULING_DEF, "absent")

# --- 16: the two reading sentences ----------------------------------------
flat = " ".join(text.split())
UNASKED = "The Shelf rule above bars a second view nobody asked for, not words: one sentence of Claude's own under a drawer or the Shelf is fine."
REDRAW = "On a card, words come back to the same card as a redraw only when they changed what the card shows, or ask to see it again; a question or a remark gets an answer in words, and the card stays on screen as it is."
gate_end = text.find("</HARD-GATE>")
after_gate = " ".join(text[gate_end:gate_end + 600].split())
if UNASKED in after_gate and after_gate.index(UNASKED) < 80:
    out("PASS", "one sentence directly under the gate fence reads the Shelf rule as no second view, not silence")
else:
    out("FAIL", "one sentence directly under the gate fence reads the Shelf rule as no second view, not silence", UNASKED, after_gate[:200])
if "arriving at a state a second time redraws it. " + REDRAW in flat:
    out("PASS", "the redraw sentence in How to read the graph carries the words-that-change-nothing reading")
else:
    out("FAIL", "the redraw sentence in How to read the graph carries the words-that-change-nothing reading", REDRAW, "absent")

# --- 17: every write takes its body on stdin, in a quoted heredoc ---------
all_nodes = list(shapes.keys())
writes = [n for n, s in shapes.items() if s == "plaintext" and ("decisions-capture.sh" in n or "decisions-transition.sh" in n)]
non_stdin = [n for n in writes if " retag " not in n and "--stdin <<'EOF'" not in n]
dead_flags = [n for n in all_nodes if any(f in n for f in ("--quote=", "--dry-run", "--new-group"))]
if non_stdin or dead_flags or not writes:
    out("FAIL", "every write node except retag carries --stdin <<'EOF' and no node carries --quote=, --dry-run or --new-group", "all stdin, none dead", f"not stdin={non_stdin} dead={dead_flags} writes={len(writes)}")
else:
    out("PASS", "every write node except retag carries --stdin <<'EOF' and no node carries --quote=, --dry-run or --new-group")
SECTION_FLAGS = ("--context=", "--options=", "--decision=", "--consequences=", "--title=")
leftover = sorted({f for f in SECTION_FLAGS + ("--quote=", "--dry-run", "--new-group") if f in text})
if leftover:
    out("FAIL", "no removed flag appears anywhere in the command", "none", str(leftover))
else:
    out("PASS", "no removed flag appears anywhere in the command")

# --- 18: nothing the user typed meets the shell ---------------------------
# bash 3.2 mishandles an apostrophe in a quoted heredoc that sits inside a
# command substitution, and an unquoted delimiter would expand what the
# user typed - so every heredoc is quoted and feeds the script directly.
heredoc_lines = [l for l in text.splitlines() if "<<" in l]
unquoted = [l for l in heredoc_lines if "<<'EOF'" not in l]
in_substitution = re.findall(r"\$\([^)]*<<", text)
if unquoted or in_substitution:
    out("FAIL", "the command has no unquoted heredoc and no heredoc inside a command substitution", "none", str(unquoted + in_substitution))
else:
    out("PASS", "the command has no unquoted heredoc and no heredoc inside a command substitution")

# --- 19: call budget ------------------------------------------------------
# Plaintext nodes between a start (an entry, or any screen already showing)
# and the card, plus the card's own draw leaf. Nothing walks through a
# screen: an ellipse ends a path.
def calls_to_cards(starts):
    import heapq
    dist = {}
    heap = [(0, s_) for s_ in starts]
    while heap:
        d_, n = heapq.heappop(heap)
        if n in dist and dist[n] <= d_:
            continue
        dist[n] = d_
        if shapes.get(n) == "ellipse" and n not in starts:
            continue
        for nxt in adjacency.get(n, []):
            heapq.heappush(heap, (d_ + (1 if shapes.get(nxt) == "plaintext" else 0), nxt))
    return dist

def leaf_cost(card):
    return 1 if any(shapes.get(n) == "plaintext" and not adjacency.get(n) for n in adjacency.get(card, [])) else 0

over_budget = []
for card in sorted(cards):
    starts = [n for n in entries + [n for n, s in shapes.items() if s == "ellipse"] if n != card]
    dist = calls_to_cards(starts)
    cost = dist.get(card)
    if cost is None or cost + leaf_cost(card) > 2:
        over_budget.append((card, cost))
fresh_cards = [c for c in cards if c.startswith("Fresh ")]
fresh_bad = []
for card in fresh_cards:
    dist = calls_to_cards(["Ruling in conversation"])
    if dist.get(card) != 1 or leaf_cost(card) != 0:
        fresh_bad.append((card, dist.get(card)))
fresh_view = [n for n in shapes if shapes[n] == "plaintext" and "decisions-view.sh" in n and any(
    nxt == n for c in fresh_cards for nxt in adjacency.get(c, []))]
if over_budget or fresh_bad or fresh_view or len(fresh_cards) != 2:
    out("FAIL", "every card face is at most two plaintext calls from an entry or a prior screen, and the fresh faces exactly one with no view call", "within budget", f"over={over_budget} fresh={fresh_bad} view={fresh_view} fresh_cards={fresh_cards}")
else:
    out("PASS", "every card face is at most two plaintext calls from an entry or a prior screen, and the fresh faces exactly one with no view call")

# --- 20: a reshaped parked write and a fresh write are different commands -
def dsts(src, label):
    return [d_ for s_, d_, l in edges if s_ == src and l == label]
reshaped_keep = dsts("Which move on a reshaped parked card?", "keep pending")
fresh_keep = dsts("Which move on a fresh card?", "keep pending") + dsts("Move on the fresh question card?", "keep pending")
capture_nodes = [n for n in writes if "decisions-capture.sh" in n]
if (reshaped_keep and all(d_.startswith("decisions-capture.sh --reopen=<slug>") for d_ in reshaped_keep)
        and fresh_keep and all(d_.startswith("decisions-capture.sh --tag=<tag>") and "--reopen" not in d_ for d_ in fresh_keep)
        and all(n.startswith("decisions-capture.sh --reopen=<slug>") or n.startswith("decisions-capture.sh --tag=<tag>") for n in capture_nodes)):
    out("PASS", "the reshaped-parked keep-pending lands on a --reopen=<slug> write, the fresh one on a write with no --reopen")
else:
    out("FAIL", "the reshaped-parked keep-pending lands on a --reopen=<slug> write, the fresh one on a write with no --reopen", "distinct commands", f"reshaped={reshaped_keep} fresh={fresh_keep}")

# --- 21: the retag is one call --------------------------------------------
retag_nodes = [n for n in shapes if " retag " in n]
records_dst = dsts("Named records or a group?", "records")
retag_after = reach(retag_nodes[0]) - {retag_nodes[0]} if len(retag_nodes) == 1 else set()
retag_succ = adjacency.get(retag_nodes[0], []) if len(retag_nodes) == 1 else []
retag_bad = [n for n in retag_after if shapes.get(n) == "plaintext"]
if len(retag_nodes) == 1 and records_dst == retag_nodes and retag_succ == ["Retagged in place"] and not retag_bad:
    out("PASS", "the records arrow reaches the retag node directly and no list or view node follows it")
else:
    out("FAIL", "the records arrow reaches the retag node directly and no list or view node follows it", "records -> retag -> Retagged in place", f"retag={retag_nodes} records={records_dst} after={retag_succ} calls_after={retag_bad}")

# --- 22: the retire diamond has three exits and no self-loop --------------
retire_exits = sorted(l for s_, d_, l in edges if s_ == "Move on a retire?")
retire_self = [(s_, d_) for s_, d_, _ in edges if s_ == "Move on a retire?" and d_ in ("Retire line on screen",)]
if retire_exits == sorted(["a letter", "words that change the text", "the card asked for"]) and not retire_self:
    out("PASS", "Move on a retire? has exactly three exits: a letter, words that change the text, the card asked for")
else:
    out("FAIL", "Move on a retire? has exactly three exits: a letter, words that change the text, the card asked for", "three named exits", str(retire_exits))

# --- 23: the faces Claude draws -------------------------------------------
faces_m = re.search(r"### The faces Claude draws\n(.*?)\n### ", text, re.DOTALL)
faces = faces_m.group(1) if faces_m else ""
def move_row(letter, move, effect):
    return "{}) {}  {}".format(letter, move.ljust(14), effect)
FACE_ROWS = [
    move_row("a", "approve", "what it becomes, and what gets built to it"),
    move_row("b", "keep pending", "saved on the Shelf, decide later"),
    move_row("c", "decline", "goes to the archive with your words, never re-proposed"),
    move_row("x", "pick", "picks this option and redraws"),
    move_row("x", "keep pending", "saved on the Shelf as a question, decide later"),
    move_row("a", "approve", "moves to approved/ as shown"),
    move_row("b", "keep pending", "saves your changes, stays on the Shelf"),
    move_row("c", "decline", "moves to the archive with your words"),
    move_row("x", "keep pending", "saves your changes, stays on the Shelf"),
    move_row("a", "retire", "no longer applies, goes to the archive with your words"),
]
# A pick row's letter varies with the options, so those rows are matched on
# everything after the letter.
missing_rows = [r for r in FACE_ROWS if (r[2:] if r.startswith("x)") else r) not in faces]
FACE_WORDS = [
    "YOUR OPTIONS", "(a) Proposed: ", "DECISION if (<letter>)", "CONSEQUENCES if (<letter>)",
    "OPTIONS CONSIDERED", "CLAIMED BY STORIES", "(NEW GROUP)", "PENDING \u00b7 tags: <tag> \u00b7 source: session",
    "<STATUS> \u00b7 tags: <tag> \u00b7 source: <source>", ", or just tell me what to change.",
]
missing_words = [w for w in FACE_WORDS if w not in faces]
if faces and not missing_rows and not missing_words:
    out("PASS", "the faces section carries every YOUR MOVE row verbatim and the question-state dividers")
else:
    out("FAIL", "the faces section carries every YOUR MOVE row verbatim and the question-state dividers", "all rows and dividers", f"section={bool(faces)} rows={missing_rows} words={missing_words}")

# --- 24: the retire line --------------------------------------------------
line_m = re.search(r"### The retire line\n(.*?)\n(?:### |## )", text, re.DOTALL)
line_sec = " ".join(line_m.group(1).split()) if line_m else ""
LINE_FACTS = ["title", "group", "<story> (<status>)", "nobody carries it", "no rail", "asking whether to retire it", "the typed answer", "the full retire card"]
missing_line = [f for f in LINE_FACTS if f not in line_sec]
if line_sec and not missing_line:
    out("PASS", "the retire line names title, group, claimants, nobody carries it, and draws the card only when asked")
else:
    out("FAIL", "the retire line names title, group, claimants, nobody carries it, and draws the card only when asked", "all facts", f"section={bool(line_sec)} missing={missing_line}")

# --- 25: the card-identity bullet ends with the fresh-card sentence --------
ident_m = re.search(r"- \*\*Card identity:\*\*(.*?)\n- \*\*", text, re.DOTALL)
ident = " ".join(ident_m.group(1).split()) if ident_m else ""
if ident.endswith("A fresh card has no slug yet; the receipt after the write shows the path."):
    out("PASS", "the card-identity bullet ends with the fresh-card sentence")
else:
    out("FAIL", "the card-identity bullet ends with the fresh-card sentence", "ends with the sentence", ident[-120:])

# --- 26: the move block sits inside the frame -----------------------------
# Three runs drew the moves three ways (outside the rail, plain text, left
# out) because the faces section never said where they go.
faces_lines = faces.splitlines()
has_divider = "\u251c\u2500 YOUR MOVE" in faces
has_row = any(re.match(r"^\u2502    a\) ", l) for l in faces_lines)
has_closing = any(re.match(r"^\u2502  a, .*or just tell me what to change\.$", l) for l in faces_lines)
div_i = next((i for i, l in enumerate(faces_lines) if l.startswith("\u251c\u2500 YOUR MOVE")), -1)
close_i = next((i for i in range(max(div_i, 0), len(faces_lines)) if faces_lines[i].startswith("\u2514")), -1)
if has_divider and has_row and has_closing and 0 <= div_i < close_i:
    out("PASS", "the faces section places the move block in-rail: divider, rows at four spaces, closing line at two spaces, before the closing rule")
else:
    out("FAIL", "the faces section places the move block in-rail: divider, rows at four spaces, closing line at two spaces, before the closing rule", "in-rail block", f"divider={has_divider} row={has_row} closing={has_closing} order={div_i},{close_i}")

# --- 27: the desk names what it already holds ----------------------------
# Each sentence closes a path where the desk spent a call on something the
# conversation already held, or reshaped a card after writing instead of before.
HOLDS = [
    ("## The four scripts", "\n## How to read the graph", "These blocks are the whole contract: what a script takes and what it prints are written here, and a script's source is never opened to learn more."),
    ("## The four scripts", "\n## How to read the graph", "A block already carries its record's `FILE=`: the next call on a record the list just printed is `cat <FILE>`, never the list again with `--slug=`."),
    ("## The four scripts", "\n## How to read the graph", "a reopen body may open with a \"# <title>\" line, which retitles the record (its filename keeps the slug); a reshape whose ruling no longer fits the title sends one"),
    ("### The faces Claude draws", "\n### The retire line", "A fresh card's only call is the tag check: no Shelf, no list and no file read come before it."),
    ("### The faces Claude draws", "\n### The retire line", "Words that reshape a parked card and name a writing move in the same message draw the reshaped card first; the move's one write follows the card, never precedes it."),
    ("### The faces Claude draws", "\n### The retire line", "Approve is the exception: named in the same message as the words that open, select or reshape a card, it draws the card and waits for the answer at that card - law is filed only from a card the human has already seen."),
    ("### The retire line", "\n## The card", "That draw is one `cat <FILE>`: the claimants lines are already in the conversation and are never listed again."),
    ("## The card", "\n### Refusal wording", "- A ruling whose subject is a literal - a character, an emoji, a colour, a line of copy - carries that literal verbatim in the Decision, never a description of it."),
]
def holds_section(heading, next_heading):
    start = text.find(heading + "\n")
    end = text.find(next_heading, start + 1) if start >= 0 else -1
    return " ".join(text[start:end].split()) if start >= 0 and end >= 0 else ""
holds_missing = [sent[:40] for head, nxt, sent in HOLDS if " ".join(sent.split()) not in holds_section(head, nxt)]
if not holds_missing:
    out("PASS", "the desk names what it already holds: six sentences sit in their named sections")
else:
    out("FAIL", "the desk names what it already holds: six sentences sit in their named sections", "all six", f"missing={holds_missing}")

PYEOF
GRAPH_REPORT="$(python3 "$GRAPH_SCRIPT" "$CMD")"
rm -f "$GRAPH_SCRIPT"
trap - EXIT
echo "$GRAPH_REPORT" | sed 's/^/  /'
GRAPH_PASS="$(printf '%s\n' "$GRAPH_REPORT" | grep -c '^PASS:' || true)"
GRAPH_FAIL="$(printf '%s\n' "$GRAPH_REPORT" | grep -c '^FAIL:' || true)"
PASS_COUNT=$((PASS_COUNT + GRAPH_PASS)); FAIL_COUNT=$((FAIL_COUNT + GRAPH_FAIL)); TOTAL=$((TOTAL + GRAPH_PASS + GRAPH_FAIL))

# ---------------------------------------------------------------------
# The capped list of prose that survives below the graph
# ---------------------------------------------------------------------
echo "-- Test: the capped prose-grep list --"
# Every phrase here is a sentence the Sentence Inventory marks "kept" (or
# the drawing rule content it says is carried over unchanged); nothing
# else below the graph is grepped by this test. This IS the cap the
# story's Acceptance points at - a new routing rule has nowhere to land
# here, because this list is prose survivors, never rules.
PROSE_SURVIVORS=(
  "Done records never get a row"
  "No right edge"
  "fixed width"
  "print exactly as the file holds them"
  'MATCH "<words>"'
  "removed row draws red"
  "added row draws green"
  "colour is drawn here"
  "One ruling per card"
  "not in the room"
  "complete alternative in plain words"
  "why not the other options"
  "path not chosen"
  "no hand wrapping"
  "Ideas to consider, not ruled:"
  "rename it in words like anything else on the card"
  "an exhibit is never invented"
  "an unanswered second step is a trap"
  "read it again against the new meaning"
  "already built"
)
if [ "${#PROSE_SURVIVORS[@]}" -le 20 ]; then
  pass "the prose-grep array holds at most 20 entries (${#PROSE_SURVIVORS[@]})"
else
  fail "the prose-grep array holds at most 20 entries" "<= 20" "${#PROSE_SURVIVORS[@]}"
fi

BODY_JOINED="$(awk '/^---$/{n++; next} n>=2{print}' "$CMD" | tr '\n' ' ' | tr -s ' ')"
for phrase in "${PROSE_SURVIVORS[@]}"; do
  if printf '%s' "$BODY_JOINED" | grep -qiE -- "$phrase"; then
    pass "prose survives: $phrase"
  else
    fail "prose survives: $phrase" "found below the frontmatter fence" "not found"
  fi
done

# ---------------------------------------------------------------------
# Structural bans (not "prose that stays" - things that must NOT appear)
# ---------------------------------------------------------------------
grep_fail_below_fence() { # asserts pattern does NOT appear below the closing frontmatter fence
  local desc="$1" pattern="$2"
  local body
  body="$(awk '/^---$/{n++; next} n>=2{print}' "$CMD")"
  if printf '%s\n' "$body" | grep -qE -- "$pattern"; then
    fail "$desc" "absent" "found: $(printf '%s\n' "$body" | grep -E -- "$pattern" | head -1)"
  else
    pass "$desc"
  fi
}

echo "-- Test: no graduation flow below the frontmatter fence --"
grep_fail_below_fence "no 'graduate' verb below the frontmatter fence" '[Gg]raduate'

echo "-- Test: no direct record-writing instruction (a ## Context/## Decision heredoc or a .craft/decisions/ write path) --"
SCRIPTS_SECTION_STRIPPED="$(awk '/^## The four scripts$/{p=1; next} /^## How to read the graph$/{p=0} !p{print}' "$CMD")"
if printf '%s\n' "$SCRIPTS_SECTION_STRIPPED" | grep -qE '^## (Context|Decision|Consequences|Approval)$'; then
  fail "no direct record-writing instruction outside the stdin examples in ## The four scripts" "absent" "a section heading on its own line"
else
  pass "no direct record-writing instruction outside the stdin examples in ## The four scripts"
fi
grep_fail_below_fence "no direct .craft/decisions/ write path" '> *"?\.craft/decisions/'

echo "-- Test: AskUserQuestion is forbidden; answers are typed into the prompt --"
AUQ_LINES="$(grep -h "AskUserQuestion" "$CMD" || true)"
if [ -z "$AUQ_LINES" ]; then
  fail "AskUserQuestion mentioned only under a prohibition" "at least one prohibition line" "zero mentions"
else
  BAD="$(printf '%s\n' "$AUQ_LINES" | grep -iv "never" || true)"
  if [ -z "$BAD" ]; then pass "every AskUserQuestion mention sits on a NEVER line"; else fail "every AskUserQuestion mention sits on a NEVER line" "all lines contain NEVER" "$BAD"; fi
fi

echo "-- Test: the drawing rule survives, heading and rail characters --"
if grep -qE '^### The drawing rule$' "$CMD"; then
  pass "### The drawing rule heading is present, exact"
else
  fail "### The drawing rule heading is present, exact" "### The drawing rule" "not found"
fi
if grep -q '[┌│└├]' "$CMD"; then
  pass "the command file carries the rail characters ┌ │ ├ └ - it is where Claude reads the shape from"
else
  fail "the command file carries the rail characters ┌ │ ├ └ - it is where Claude reads the shape from" "present" "absent"
fi

echo "-- Test: craft-notebook.md's when_to_use ends with the ruled Not-for line --"
NOTEBOOK="$REPO/commands/craft-notebook.md"
LAST_LINE_OF_WTU="$(awk '/^when_to_use: \|/{p=1; next} p && /^argument-hint:/{exit} p{last=$0} END{print last}' "$NOTEBOOK")"
if [ "$LAST_LINE_OF_WTU" = "  Not for: product rulings (decisions) - those belong to /craft:decisions." ]; then
  pass "notebook when_to_use ends with the ruled Not-for line, verbatim"
else
  fail "notebook when_to_use ends with the ruled Not-for line, verbatim" "  Not for: product rulings (decisions) - those belong to /craft:decisions." "$LAST_LINE_OF_WTU"
fi

LIVE_CMDS="$(ls -1 "$REPO"/commands/craft*.md 2>/dev/null | wc -l | tr -d ' ')"
echo "-- Test: /craft:decisions is present in decision-tree, DESIGN.md and README.md; DESIGN.md says $LIVE_CMDS commands (the live count) --"
grep -q '/craft:decisions' "$REPO/docs/decision-tree.md" && pass "/craft:decisions in docs/decision-tree.md" || fail "/craft:decisions in docs/decision-tree.md"
grep -q '/craft:decisions' "$REPO/DESIGN.md" && pass "/craft:decisions in DESIGN.md" || fail "/craft:decisions in DESIGN.md"
grep -q '/craft:decisions' "$REPO/README.md" && pass "/craft:decisions in README.md" || fail "/craft:decisions in README.md"
grep -q "$LIVE_CMDS commands" "$REPO/DESIGN.md" && pass "DESIGN.md says $LIVE_CMDS commands (the live count)" || fail "DESIGN.md says $LIVE_CMDS commands (the live count)"

echo "-- Test: the alignment check's agent prompt cites no decision record by slug --"
# A slug names a record in THIS repo's store. A user's project has none, and the
# same prompt tells the agent where records live and to report one it cannot find,
# so a citation there can read as a rule with no authority behind it.
ALIGNMENT_REF="$REPO/commands/references/alignment-check.md"
ALIGNMENT_SLUGS="$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z][a-z0-9-]+' "$ALIGNMENT_REF" || true)"
if [ -z "$ALIGNMENT_SLUGS" ]; then
  pass "alignment-check.md names no decision record by slug"
else
  fail "alignment-check.md names no decision record by slug" "none" "$ALIGNMENT_SLUGS"
fi
grep -q "the older is cited as superseded" "$ALIGNMENT_REF" && pass "the superseding rule itself survives, stated on its own authority" || fail "the superseding rule itself survives, stated on its own authority" "present" "absent"
grep -q "holds the story's own records and no others" "$ALIGNMENT_REF" && pass "the investigator gets the story's own records and no others" || fail "the investigator gets the story's own records and no others" "present" "absent"
NOT_LAW_COUNT="$(grep -c "is NOT LAW for this story" "$ALIGNMENT_REF" || true)"
if [ "$NOT_LAW_COUNT" -eq 2 ]; then pass "the NOT LAW sentence is in the rule and in the prompt template"; else fail "the NOT LAW sentence is in the rule and in the prompt template" "2" "$NOT_LAW_COUNT"; fi

echo "-- Test: the command names no real decision record by slug; fictional ones sit only in ## The four scripts --"
# A slug in shipped text can name a record only this repo has. The exhibit's
# fictional slug is the one allowed form: inside the scripts section, and
# matching no file in this store.
CMD_SECTION="$(awk '/^## The four scripts$/{p=1; next} /^## How to read the graph$/{p=0} p{print}' "$CMD")"
CMD_OUTSIDE="$(awk '/^## The four scripts$/{p=1; next} /^## How to read the graph$/{p=0} !p{print}' "$CMD")"
SLUG_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z][a-z0-9-]+'
OUTSIDE_SLUGS="$(printf '%s\n' "$CMD_OUTSIDE" | grep -oE "$SLUG_RE" || true)"
if [ -z "$OUTSIDE_SLUGS" ]; then
  pass "no dated slug appears outside ## The four scripts"
else
  fail "no dated slug appears outside ## The four scripts" "none" "$OUTSIDE_SLUGS"
fi
REAL_HITS=""
while IFS= read -r slug; do
  [ -z "$slug" ] && continue
  if [ -n "$(find "$REPO/.craft/decisions" -name "${slug}.md" 2>/dev/null)" ]; then REAL_HITS="$REAL_HITS $slug"; fi
done < <(printf '%s\n' "$CMD_SECTION" | grep -oE "$SLUG_RE" | sort -u)
if [ -z "$REAL_HITS" ]; then
  pass "no slug in ## The four scripts matches a record in this store"
else
  fail "no slug in ## The four scripts matches a record in this store" "none" "$REAL_HITS"
fi

echo "-- Test: scripts run through the absolute path, never a changed directory --"
grep_fail_below_fence "no 'cd ' command below the frontmatter fence" '(^|[^A-Za-z])cd '
grep_fail_below_fence "no 'from that directory' below the frontmatter fence" 'from that directory'

echo "-- Test: the command's drawing rule and receipts name records by title, not slug --"
if grep -qE 'date-stripped, as on the Shelf|glyph and slug' "$CMD"; then
  fail "no slug-as-on-the-Shelf wording remains in the command" "absent" "$(grep -nE 'date-stripped, as on the Shelf|glyph and slug' "$CMD")"
else
  pass "no slug-as-on-the-Shelf wording remains in the command"
fi
grep -qF 'the record'"'"'s title at its full length' "$CMD" && pass "the drawing rule's rows bullet names the title at its full length" || fail "the drawing rule's rows bullet names the title at its full length" "present" "absent"
grep -qF 'Okay - moved <title> to <tag>' "$CMD" && pass "the retag receipt line names the title" || fail "the retag receipt line names the title" "present" "absent"
tr '\n' ' ' < "$CMD" | tr -s ' ' | grep -qF "glyph and title as the Shelf would show them" && pass "the receipt rows read as glyph and title" || fail "the receipt rows read as glyph and title" "present" "absent"

grep -qF 'decision-body-parser' "$CMD" && fail "the command never names the body parser" "absent" "$(grep -nF 'decision-body-parser' "$CMD")" || pass "the command never names the body parser"

echo ""
echo "-- Summary --"
echo "Total:  $TOTAL"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
