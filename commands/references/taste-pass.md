# Taste Pass (reference - read inline by both propagation doors)

You are running a taste pass: loved tweaks have accrued, and this offers a victory lap that spreads
proven taste to other surfaces. This file owns the whole brain - the offer gate, the scout, the
selection, the handoff to `/craft:mockup`, and the pacing. Both doors (the tweak-close door and the
session-start ripe line) read THIS file inline and execute it; neither invokes it via the Skill tool
(a Skill-tool call ends the turn and control never returns - see
`.claude/rules/skill-invocation-chain-breaks.md`; `craft-mockup.md` Step 3 is the inline-read precedent).

**Guiding rule (do not violate): bookkeeping bends to creativity, never the reverse.** The scout
POINTS; the making is fully `/craft:mockup`'s; the ledger just remembers.

## The offer gate

The victory-lap offer fires only when BOTH hold:

```bash
ENABLED=$(grep -m1 '^taste_pass_enabled:' "${CRAFT_PROJECT_ROOT:-.}/.craft/settings.yaml" 2>/dev/null | sed 's/^taste_pass_enabled:[[:space:]]*//')
THRESHOLD=$("${CLAUDE_PLUGIN_ROOT}/hooks/scripts/taste-pass-state.sh" effective-threshold 2>/dev/null || echo 3)
COUNT=$("${CLAUDE_PLUGIN_ROOT}/hooks/scripts/count-loved-tweaks.sh" "$THRESHOLD" 2>/dev/null || echo 0)
```

- `taste_pass_enabled` is not `false` (absent or true both pass - the default is on), AND
- `COUNT` >= `THRESHOLD`.

The gate passes the threshold to the counter so the count early-exits (it never needs the exact
total, only "is it ripe"). If the gate does not pass, say nothing and do nothing - there is no offer.

**Same-day quiet is designed:** a tweak loved the same calendar day as the last accepted pass does
not count until the next day (`created > last_asked`, strict). You just ran a pass; the loop stays
quiet on purpose rather than re-offering the moves you already spread.

The offer itself is ONE ignorable line, never an AskUserQuestion - notebook conventions:

> "That's [N] loved tweaks now - want a victory lap? I'll look for other surfaces that could use the
> same taste. Otherwise moving on."

## The scout

On accept, find the spots that could inherit the loved taste. Default move: **screenshot the loved
surface and the candidate surfaces and compare by eye** (needs a running app plus browser tooling -
`craft:browser` or the chrome-devtools MCP). Rank candidates as siblings (same component family) and
vibe-cousins (different surface, kindred feeling). The scout POINTS, never prescribes - it names where
the taste could spread and one seed move for each, and hands the making to `/craft:mockup` unchanged.

Find generously. The taste filter is downstream: the user prunes the list, then the real mockup render
decides. Divergence is a feature to spread, so:

- NO tokens/locked gate on discovery - a surface that breaks the current tokens is still a candidate.
- NO `style-analyzer`, NO new agent, NO subagent - the scout is the orchestrator, vibe-driven, eyes
  and taste. The alchemist lives downstream, inside mockup.

**Graceful degradation (no live app / no browser tooling):** when there is no running app or no browser
channel, the scout DEGRADES - it points from component and structure by reading the code, and says so
plainly:

> "I can't see it live, so I'm pointing from the code - boot the app if you want a visual compare."

Accepting the victory lap is NEVER a dead end. Pointing from code is a smaller move, not a failure.

## Selection

Present the ranked list and take the pick **conversationally** - any, some, or all. This is plain text,
NOT an AskUserQuestion (a widget between the user and their taste kills the flow). "The first two",
"all of them", "just the profile cards" are all valid. The user prunes; you carry forward only winners.

## Handoff - one notebook todo per winner, one shared family

Each winner becomes ONE notebook todo, all sharing a family tag (e.g. `taste-<origin-slug>`), so the
family travels together. Create the todo skeleton, then append the dossier body to the returned path:

```bash
TODO_PATH=$("${CLAUDE_PLUGIN_ROOT}/hooks/scripts/notebook-capture.sh" todo "<target surface> - spread <origin>'s taste" \
  --tags="<family>" --source='"[[<origin-tweak>]]"')
```

`--source` is written verbatim, so pass the origin as a QUOTED wikilink - `"[[<origin-tweak>]]"` -
which is valid YAML and renders as a two-way link for any wiki-aware reader, while still grepping clean
for craft's own tooling. Then append the A6 dossier body to `$TODO_PATH` with Write, under these headings:

```markdown
## Target
[the surface this todo targets - where the taste should land]

## Taste-print
[the felt principle / emotional target / move family carried from the origin tweak]

## Fit read
[how the move fits this neighborhood - siblings, conventions, what adapts]

## Divergences
[where this surface may want to diverge from the seed - noted, never forced]

## Run
Hand to /craft:mockup when ready - fully open; the seed is a starting point, not a spec.
```

The dossier is prose, not schema - its only consumer is `/craft:mockup`'s overridable Brief, which
wants rich human-readable context. Do NOT add structured frontmatter for taste-print/fit/divergences.

**Lineage:** the todo's `source: "[[<origin-tweak>]]"` carries the origin forward. When a winner is
later handed to `/craft:mockup`, pass that origin into the mockup launch so the mockup record stamps it
at creation (see `mockup-inline.md`) - that is how a button that snowballs into a whole page still
traces home.

## The march

After selection, offer to start immediately - this is NOT deferral:

> "Start with the first one in `/craft:mockup`? Or 'trust you, go' and I'll march the whole family."

- **"start with the first"** -> hand winner 1 to `/craft:mockup`, fully open, one at a time.
- **"trust you, go"** -> march the family tag in order, each its own open mockup session.

Do NOT create the mockups
here - each winner goes to `/craft:mockup` as its own thread, fully open (the user may go COMPLETELY
different from the seed - that freedom is the point). Mockup's own graduation ramps decide each fate.

## Pacing - CALL the state script, never hand-edit state

Every state change goes through `taste-pass-state.sh`; this file never writes `.taste-pass-state` or
`settings.yaml` directly.

- **Accept** (the victory lap runs), OR "run it now", OR the terminal "neither" from the disable branch
  -> `"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/taste-pass-state.sh" accept` (advances `last_asked` to today,
  drops the snooze offset to 0).
- **Explicit decline below the cap** ("not now") -> `"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/taste-pass-state.sh" decline`
  (raises the snooze offset 0->2->5; the banked loved tweaks stand - the bar rises, the signal is kept).
- **Explicit decline when the offset is already maxed (5)** -> read `taste-pass-disable.md` inline and
  run its three-outcome earned exit. Do NOT load that file on any other path.

**Pure silence writes NOTHING.** Ignoring the ripe line or the tweak-close offer never calls the script
and never infers accept-or-decline - only an explicit yes resets, only an explicit "not now" raises the
offset (`.claude/rules/explicit-lock-confirmation.md` - silence is never consent). A silently-ignored
low-frequency line may simply reprint next session.

**A second offer in one session is intentional.** Both doors re-check live state with NO once-per-session
flag, so the session-start ripe line and a later tweak-close offer can both fire in one session - that is
correct, not a double-nag. An explicit decline at either door quiets both (it moves the shared state).

## Seed pool and the back catalogue

The seed pool for a pass is the recent batch that crossed the threshold (loved records after
`last_asked`). Older un-spread moves are NOT auto-dumped into the pass - they stay reachable on demand:
if the user later says "spread my [X] move", scout that specific move against the whole corpus. The
auto-pass seeds from the recent batch to avoid overwhelm; the back catalogue is always reachable by ask.

## Anti-patterns (do NOT resurrect)

1. Do NOT gate discovery on tokens/locked/quality - that kills new inspiration.
2. Do NOT lock the mockup to the seed vibe - that bypasses the creative session.
3. Do NOT sever lineage when the outcome diverged from the origin - that breaks the snowball.

Root rule: bookkeeping bends to creativity, never the reverse.
