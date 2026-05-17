# Craft Plugin Decision Tree

This document maps the complete routing logic from the `/craft` entry point based on the state of the `.craft` folder.

## Main Entry Point: `/craft`

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    START["/craft invoked"] --> CHECK_CRAFT{".craft/ exists?"}

    CHECK_CRAFT -->|No| INIT["Route to /craft:init"]
    CHECK_CRAFT -->|Yes| CHECK_STORY_FP{"Fast path 1:<br/>CURRENT_STORY set?"}

    CHECK_STORY_FP -->|Yes| FP1["Resume story in progress<br/>→ /craft:story-continue"]
    CHECK_STORY_FP -->|No| CHECK_PLANNING_FP{"Fast path 2:<br/>PLANNING_CYCLE set?"}

    CHECK_PLANNING_FP -->|Yes| FP2["Resume cycle planning<br/>→ /craft:cycle-design"]
    CHECK_PLANNING_FP -->|No| CHECK_INSPIRATION_FP{"Fast path 3:<br/>.inspiration-session exists?"}

    CHECK_INSPIRATION_FP -->|Yes| FP3["AskUserQuestion:<br/>• Resume inspiration session<br/>• Start fresh<br/>• Skip"]
    CHECK_INSPIRATION_FP -->|No| READ_STATE{"Read .global-state"}

    READ_STATE -->|Missing/Corrupt| RECOVER["State Recovery:<br/>1. Scan cycles for active<br/>2. Scan stories for active<br/>3. Rebuild state file"]
    RECOVER --> AMBIGUOUS{"Ambiguous?"}
    AMBIGUOUS -->|Yes| ASK_WHICH["AskUserQuestion:<br/>Which is current?"]
    AMBIGUOUS -->|No| CHECK_REQUESTS
    ASK_WHICH --> CHECK_REQUESTS

    READ_STATE -->|OK| CHECK_REQUESTS{"Step 2.5: Pending requests<br/>in .craft/requests/?"}

    CHECK_REQUESTS -->|Yes| REQUESTS_GATE["AskUserQuestion:<br/>• Review N pending requests<br/>• Continue to full state scan"]
    REQUESTS_GATE -->|Review| ROUTE_5B["Step 5b inline (in /craft):<br/>review and route requests<br/>(NOT a separate command)"]
    ROUTE_5B --> CHECK_LEARNINGS
    REQUESTS_GATE -->|Continue| CHECK_LEARNINGS

    CHECK_REQUESTS -->|No| CHECK_LEARNINGS{"Learnings > 0?"}

    CHECK_LEARNINGS -->|Yes| LEARNINGS_NUDGE["AskUserQuestion:<br/>• Review learnings<br/>• Continue working"]
    LEARNINGS_NUDGE -->|Review| ROUTE_REFLECT["/craft:reflect"]
    LEARNINGS_NUDGE -->|Continue| CHECK_PENDING

    CHECK_LEARNINGS -->|No| CHECK_PENDING{"Pending findings?"}

    CHECK_PENDING --> CHECK_CYCLE{"ACTIVE_CYCLE set?"}

    CHECK_CYCLE -->|Yes| ASK_PICK["AskUserQuestion:<br/>• Start [first ready story]<br/>• Pick a different story<br/>• Create new story<br/>+ Review N findings (if pending)"]
    CHECK_CYCLE -->|No| CHECK_BACKLOG{"Backlog has stories?"}

    CHECK_BACKLOG -->|Yes| ASK_START["AskUserQuestion:<br/>• Start a cycle (designs from backlog)<br/>• Create new story<br/>+ Review N findings (if pending)"]
    CHECK_BACKLOG -->|No| ASK_NEW["AskUserQuestion:<br/>• Create first story<br/>• Create first cycle"]

    ASK_PICK -->|Start/Pick| ROUTE_IMPL["/craft:story-implement"]
    ASK_PICK -->|Create| ROUTE_NEW["/craft:story-new"]
    ASK_PICK -->|Review| ROUTE_ANALYZE["/craft:analyze pending"]

    ASK_START -->|Start a cycle| ROUTE_CYCLE_NEW["/craft:cycle-design"]
    ASK_START -->|New story| ROUTE_NEW

    ASK_NEW -->|Story| ROUTE_NEW
    ASK_NEW -->|Cycle| ROUTE_CYCLE_NEW
```

---

## Story Creation Flow: `/craft:story-new`

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    STORY_NEW["/craft:story-new"] --> CAPTURE["Step 1: Capture idea"]
    CAPTURE --> CLARIFY{"Idea clear?"}

    CLARIFY -->|No| ASK_CLARIFY["Clarify with user"]
    ASK_CLARIFY --> CLARIFY
    CLARIFY -->|Yes| CHOOSE_PATH{"Step 3: How formed is this idea?"}

    CHOOSE_PATH -->|"Just a spark"| SAVE_MIN["Step 10: Save & Place<br/>(minimal — no content-spark, no chunks)"]
    CHOOSE_PATH -->|"Let's get creative"| CONTENT_CREATIVE["Step 3b: Execute content-spark-inline.md<br/>(inline, NOT Skill tool — chain break)"]
    CHOOSE_PATH -->|"I know what I want"| CONTENT_SMART["Step 3b: Execute content-spark-inline.md<br/>(inline, NOT Skill tool — chain break)"]

    CONTENT_CREATIVE --> CREATIVE["PATH A: With Creative-Spark"]
    CONTENT_SMART --> SMART["PATH B: Skip Creative-Spark"]

    CREATIVE --> SPARK["Step 4: Execute creative-spark-inline.md<br/>(inline, NOT Skill tool — chain break)<br/>Generate 2-3 options + visual direction"]
    SPARK --> USER_PICK["Step 5: User picks option<br/>Visual direction comes from option<br/>(no separate design-vibe per-story)"]

    USER_PICK --> DESIGN_DECISIONS["Step 6: Capture typed design decisions<br/>AskUserQuestion: layout / component /<br/>density / visibility"]

    DESIGN_DECISIONS --> LOCK_CREATIVE["Decisions stored in story file<br/>(story-scoped, not project-locked)"]

    LOCK_CREATIVE --> CONT_OR_SAVE_A{"Continue or save?"}
    CONT_OR_SAVE_A -->|Save what we have| SAVE
    CONT_OR_SAVE_A -->|Keep designing| ALIGNMENT

    SMART["PATH B: Skip Creative-Spark"] --> QUICK["Step 7: Quick decisions only<br/>(story-scoped, NOT lock-decision unless project-wide)"]
    QUICK --> CONT_OR_SAVE_B{"Continue or save?"}
    CONT_OR_SAVE_B -->|Save what we have| SAVE
    CONT_OR_SAVE_B -->|Keep designing| ALIGNMENT
    CONT_OR_SAVE_B -->|"Let's get creative"| SPARK

    ALIGNMENT["Step 8: Codebase Alignment Check<br/>Spawn Explore agent, investigate codebase"]
    ALIGNMENT --> INVESTIGATE["Read commands/references/alignment-check.md<br/>Surface product questions"]
    INVESTIGATE --> GAPS{"Unasked product<br/>questions remain?"}
    GAPS -->|Yes| ASK_GAPS["AskUserQuestion:<br/>Conflicts, adjacencies, assumptions"]
    ASK_GAPS --> SCOPE_CHECK{"Answers expanded scope?"}
    SCOPE_CHECK -->|Yes| SENDMSG["SendMessage to same Explore agent<br/>Investigate new scope implications"]
    SENDMSG --> GAPS
    SCOPE_CHECK -->|No| GAPS
    GAPS -->|No| SET_ALIGNED["Set alignment: complete<br/>in story frontmatter"]

    SET_ALIGNED --> ACCEPTANCE["Step 9: Define acceptance,<br/>scope, preserve list, dependencies"]
    ACCEPTANCE --> SAVE

    SAVE["Step 10: Save & Place<br/>Write story file to .craft/backlog/<br/>Status: planning (until chunks planned)"]
    SAVE --> SAVE_MIN
    SAVE_MIN --> CHUNK_OFFER{"Step 11: Plan chunks now? (OPTIONAL)"}

    CHUNK_OFFER -->|"Yes, plan chunks now"| CHUNKS["Invoke plan-chunks via Skill tool<br/>(this IS a Skill invocation —<br/>plan-chunks does not chain back)<br/>Status → ready"]
    CHUNK_OFFER -->|"Later, just save spark"| KEEP_PLANNING["Status stays: planning<br/>plan-chunks needed before implementing"]
    CHUNK_OFFER -->|"Explore creatively first"| SPARK

    CHUNKS --> PLACE
    KEEP_PLANNING --> PLACE

    PLACE{"Step 12: Where should it go?"}
    PLACE -->|"Save to backlog"| DONE_BACKLOG["Stays in .craft/backlog/<br/>Ready for later (user decides when to implement)"]
    PLACE -->|"Add to current cycle"| MOVE["Run move-story.sh<br/>Move to cycle/stories/<br/>(does NOT auto-implement)"]
    PLACE -->|"Create new cycle"| ROUTE_CD["/craft:cycle-design"]
```

---

## Story Implementation Flow: `/craft:story-implement`

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    IMPL["/craft:story-implement"] --> CHECK_STATUS{"Status Guard"}

    CHECK_STATUS -->|backlog| BLOCK_BACKLOG["BLOCK: Assign to cycle first?<br/>→ /craft:cycle-assign"]
    CHECK_STATUS -->|complete| BLOCK_DONE["BLOCK: Story already complete.<br/>Pick another?"]
    CHECK_STATUS -->|blocked| BLOCK_DEP["BLOCK: Blocked by [X].<br/>Resolve first?"]
    CHECK_STATUS -->|ready/active| CHECK_CHUNKS{"Has chunks?"}

    CHECK_CHUNKS -->|No| ASK_PATH["AskUserQuestion:<br/>• Design it now (Creative)<br/>• Plan chunks (Smart)<br/>• Pick different story"]
    CHECK_CHUNKS -->|Yes| CHECK_PARALLEL{"Parallel story active?"}

    CHECK_PARALLEL -->|Yes| CONFLICT_CHECK["Extract files from both stories"]
    CONFLICT_CHECK --> OVERLAP{"File overlap?"}
    OVERLAP -->|Yes| BLOCK_CONFLICT["AskUserQuestion:<br/>Files overlap: auth.ts, types.ts<br/>• Work on Story A first<br/>• Work on Story B first<br/>• Continue anyway (risk)"]
    OVERLAP -->|No| START_IMPL["Start implementation"]
    BLOCK_CONFLICT --> START_IMPL

    CHECK_PARALLEL -->|No| START_IMPL

    START_IMPL --> INIT_LEARNINGS["Initialize in-memory learnings:<br/>errors[], patterns[], corrections[]"]
    INIT_LEARNINGS --> REVIEW["Review story<br/>Show chunks, decisions, criteria"]

    REVIEW --> LOOP["IMPLEMENTATION LOOP"]

    LOOP --> CHECKPOINT["1. Git checkpoint<br/>Before chunk N"]
    CHECKPOINT --> DELEGATE["2. Spawn implementer agent<br/>Pass chunk details + context"]
    DELEGATE --> VALIDATE["3. Invoke validate-chunk skill<br/>TypeScript, lint, tests"]

    VALIDATE --> LOG_ERRORS["Log errors to in-memory learnings"]
    LOG_ERRORS --> PASS{"Validation passed?"}

    PASS -->|Yes| MODE_CHECK{"Run mode?"}
    PASS -->|No| REFINE["Invoke refine-chunk skill"]

    REFINE --> RETRY{"Attempt count?"}
    RETRY -->|"< 2"| VALIDATE
    RETRY -->|">= 2"| ESCALATE["Stop and ask user<br/>Offer rollback"]
    ESCALATE --> LOOP

    MODE_CHECK -->|Cruise| AUTO_NEXT["Auto-continue to next chunk"]
    MODE_CHECK -->|Guided| ASK_NEXT["Ask: Continue to next chunk?"]

    AUTO_NEXT --> MORE_CHUNKS{"More chunks?"}
    ASK_NEXT --> MORE_CHUNKS

    MORE_CHUNKS -->|Yes| RECHECK_PARALLEL["Re-check file conflicts"]
    RECHECK_PARALLEL --> LOOP
    MORE_CHUNKS -->|No| COMPLETE["STORY COMPLETION"]

    COMPLETE --> WRITE_LEARNINGS["Write in-memory learnings<br/>to .learnings.yaml"]
    WRITE_LEARNINGS --> GATES["1. Run quality gates<br/>From quality.yaml"]
    GATES --> CRITIQUE["2. Self-critique<br/>Compare to locked patterns"]
    CRITIQUE --> OFFER_CAPTURE["3. Offer to capture corrections"]

    OFFER_CAPTURE --> MARK_DONE["4. Run complete-story.sh<br/>Mark story complete"]

    MARK_DONE --> CYCLE_DONE{"All stories done?"}
    CYCLE_DONE -->|Yes| ROUTE_COMPLETE["/craft:cycle-complete"]
    CYCLE_DONE -->|No| NEXT_STORY["Continue to next story"]
```

---

## Cycle Creation Flow: `/craft:cycle-design`

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    CYCLE_DESIGN["/craft:cycle-design"] --> MODE_DISPATCH{"Mode dispatch<br/>(args provided?)"}

    MODE_DISPATCH -->|"Args = existing PLANNING cycle"| DETAILING["Read references/cycle-design/<br/>detailing-mode.md<br/>(Resume + flesh out unfinished cycle)"]
    MODE_DISPATCH -->|"Args = ready/active/complete cycle"| ERR["Error: cycle not in planning.<br/>Use /craft:cycle-start instead"]
    MODE_DISPATCH -->|"No args (new cycle)"| NAME["Step 1: Name & Goal"]

    NAME --> CREATE_FILES["Create cycle.yaml + .state IMMEDIATELY<br/>(create-cycle.sh)<br/>Set PLANNING_CYCLE in .global-state<br/>(prevents orphaned dirs on interrupt)"]
    CREATE_FILES --> DEPTH{"Step 1b: Planning depth?"}

    DEPTH -->|"Add stories now"| DEFAULT["Read references/cycle-design/<br/>default-mode.md"]
    DEPTH -->|"Quick sketch (Roadmap)"| ROADMAP["Read references/cycle-design/<br/>roadmap-mode.md<br/>(story titles only, detail later)"]

    DEFAULT --> BRAINSTORM["Step 2: Brainstorm story list<br/>(plain conversation —<br/>NO skill invocation here:<br/>brainstorm is decomposition,<br/>not creative exploration)"]
    BRAINSTORM --> LIST["Present story list"]
    LIST --> CONFIRM_LIST{"User confirms?"}
    CONFIRM_LIST -->|No| ADJUST["Add/remove/adjust"]
    ADJUST --> LIST
    CONFIRM_LIST -->|Yes| FOR_EACH["FOR EACH STORY (Step 3)"]

    FOR_EACH --> STORY_SPARK["3a: Discuss spark"]
    STORY_SPARK --> STORY_CONTENT["3b: content-spark per story<br/>(inline-via-reference)"]
    STORY_CONTENT --> STORY_PATH{"Creative or smart?"}
    STORY_PATH -->|Creative| STORY_CREATIVE["creative-spark per story<br/>(inline-via-reference)<br/>visual direction included"]
    STORY_PATH -->|Smart| STORY_DECIDE["Quick technical decisions"]
    STORY_CREATIVE --> STORY_LOCK
    STORY_DECIDE --> STORY_LOCK["lock-decision (typed keys)"]
    STORY_LOCK --> STORY_ALIGN["3c: Codebase Alignment Check<br/>(commands/references/alignment-check.md)"]
    STORY_ALIGN --> STORY_GAPS{"Unasked product<br/>questions remain?"}
    STORY_GAPS -->|Yes| STORY_ASK["AskUserQuestion +<br/>SendMessage loop"]
    STORY_ASK --> STORY_GAPS
    STORY_GAPS -->|No| STORY_ALIGNED["Set alignment: complete"]
    STORY_ALIGNED --> STORY_ACCEPT["3d: Define acceptance"]
    STORY_ACCEPT --> SAVE_STORY["Write story file immediately<br/>.craft/cycles/[name]/stories/<br/>status: planning"]
    SAVE_STORY --> MORE_STORIES{"More stories?"}
    MORE_STORIES -->|Yes| FOR_EACH
    MORE_STORIES -->|No| VIBE["Step 7: design-vibe<br/>(CYCLE-LEVEL cohesion check<br/>across all UI stories — once per cycle)"]
    VIBE --> CHUNKS_BATCH["Invoke plan-chunks MODE=batch<br/>(parallel planning across stories)"]
    CHUNKS_BATCH --> REVIEW["Cycle review"]

    REVIEW --> CERTAINTY{"Right stories in right order?"}
    CERTAINTY -->|No| REVISIT["Edit/add/remove/reorder"]
    REVISIT --> REVIEW
    CERTAINTY -->|Yes| ACTIVATE{"Activate now?"}

    ACTIVATE -->|Yes| SET_ACTIVE["Clear PLANNING_CYCLE<br/>Route to /craft:cycle-start"]
    ACTIVATE -->|No| KEEP_READY["Clear PLANNING_CYCLE<br/>Cycle stays in ready state"]

    ROADMAP --> ROADMAP_DONE["Story titles sketched.<br/>Detail later via<br/>/craft:cycle-design [name]<br/>(re-enters via Detailing Mode)"]
```

---

## Cycle Start Flow: `/craft:cycle-start`

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    CYCLE_START["/craft:cycle-start"] --> SELECT{"Cycle specified?"}

    SELECT -->|No| LIST_CYCLES["List available cycles"]
    LIST_CYCLES --> ASK_CYCLE["AskUserQuestion:<br/>Which cycle?"]
    ASK_CYCLE --> SHOW_OVERVIEW
    SELECT -->|Yes| SHOW_OVERVIEW["Show cycle overview<br/>Goal, stories, chunks"]

    SHOW_OVERVIEW --> CHECK_SETTING{"Run mode setting exists?"}
    CHECK_SETTING -->|Yes| CONFIRM_MODE["Use saved mode?<br/>[cruise/guided]"]
    CHECK_SETTING -->|No| CHOOSE_MODE["AskUserQuestion:<br/>• Cruise Mode (autonomous)<br/>• Guided Mode (check-ins)<br/>• Save as default"]

    CONFIRM_MODE --> ACTIVATE
    CHOOSE_MODE -->|Save default| SAVE_SETTING["Update settings.yaml<br/>run_mode: [choice]"]
    SAVE_SETTING --> ACTIVATE
    CHOOSE_MODE --> ACTIVATE

    ACTIVATE["Update .global-state:<br/>ACTIVE_CYCLE, RUN_MODE"]

    ACTIVATE --> INIT_LEARNINGS["Initialize .learnings.yaml"]
    INIT_LEARNINGS --> PICK_STORY{"Start with Story 1?"}

    PICK_STORY -->|Yes| ROUTE_IMPL["/craft:story-implement"]
    PICK_STORY -->|Pick different| ASK_STORY["AskUserQuestion:<br/>Which story?"]
    ASK_STORY --> ROUTE_IMPL
```

---

## Cycle Complete Flow: `/craft:cycle-complete`

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    CYCLE_COMPLETE["/craft:cycle-complete"] --> CHECK_STORIES{"All stories complete?"}

    CHECK_STORIES -->|No| ASK_END["AskUserQuestion:<br/>• Complete cycle (archive incomplete)<br/>• Continue working"]
    ASK_END -->|Continue| EXIT["Exit"]
    ASK_END -->|Complete| LOAD_LEARNINGS

    CHECK_STORIES -->|Yes| LOAD_LEARNINGS["Load .learnings.yaml"]

    LOAD_LEARNINGS --> FILTER["Filter actionable items:<br/>• errors with count >= 2<br/>• all corrections<br/>• patterns with count >= 2"]

    FILTER --> CHECK_FRESHNESS{"Harness checked recently?<br/>(within 14 days)"}
    CHECK_FRESHNESS -->|Stale| ASK_UPDATE["AskUserQuestion:<br/>Check for Claude Code updates?"]
    ASK_UPDATE -->|Yes| WEB_SEARCH["WebSearch: Claude Code changelog"]
    WEB_SEARCH --> CATEGORIZE
    ASK_UPDATE -->|No| CATEGORIZE
    CHECK_FRESHNESS -->|Fresh| CATEGORIZE

    CATEGORIZE["Categorize learnings by target:<br/>• CLAUDE.md (conventions)<br/>• Rules (enforcement)<br/>• Hooks (automation)<br/>• Locked patterns (design)"]

    CATEGORIZE --> PRESENT["Present summary:<br/>'Apply these harness updates?'"]

    PRESENT --> ASK_APPLY["AskUserQuestion:<br/>• Apply all<br/>• Review each<br/>• Skip harness updates"]

    ASK_APPLY -->|Apply all| APPLY_ALL["Apply all updates"]
    ASK_APPLY -->|Review| REVIEW_EACH["Review each update one by one"]
    ASK_APPLY -->|Skip| ARCHIVE

    APPLY_ALL --> UPDATE_CLAUDE["Update .claude/CLAUDE.md<br/>(create if missing)"]
    REVIEW_EACH --> UPDATE_CLAUDE

    UPDATE_CLAUDE --> CREATE_RULES["Create .claude/rules/*.md<br/>for error patterns"]
    CREATE_RULES --> ADD_HOOKS["Update project settings<br/>for automations"]
    ADD_HOOKS --> LOCK_PATTERNS["Append to .craft/design/locked.md"]

    LOCK_PATTERNS --> ARCHIVE["Archive learnings<br/>Clear .learnings.yaml"]

    ARCHIVE --> UPDATE_STATE["Update .global-state:<br/>Clear ACTIVE_CYCLE<br/>Set HARNESS_CHECKED"]

    UPDATE_STATE --> SUMMARY["Cycle Complete Summary:<br/>• Stories completed<br/>• Harness updates applied"]

    SUMMARY --> NEXT["AskUserQuestion:<br/>• Start new cycle<br/>• Review backlog<br/>• Take a break"]
```

---

## Reflect Flow: `/craft:reflect`

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    REFLECT["/craft:reflect"] --> CONTEXT{"What triggered reflect?"}

    CONTEXT -->|User correction| CAPTURE_CORRECTION["'Got it — use X instead of Y.<br/>Should I capture this?'"]
    CONTEXT -->|Pattern observed| CAPTURE_PATTERN["'I've used [pattern] in N places.<br/>Worth locking?'"]
    CONTEXT -->|Manual invoke| GATHER["Gather recent insights"]

    CAPTURE_CORRECTION --> ASK_CAPTURE["AskUserQuestion:<br/>• Yes, remember this<br/>• No, one-time thing"]
    CAPTURE_PATTERN --> ASK_CAPTURE

    ASK_CAPTURE -->|Yes| WRITE_LEARNING["Append to .learnings.yaml"]
    ASK_CAPTURE -->|No| EXIT["Continue working"]

    GATHER --> PRESENT["Present learnings so far:<br/>• Errors: N<br/>• Corrections: N<br/>• Patterns: N"]

    PRESENT --> ASK_ACTION["AskUserQuestion:<br/>• Process now (→ cycle-complete)<br/>• Keep accumulating"]

    ASK_ACTION -->|Process| ROUTE_COMPLETE["/craft:cycle-complete"]
    ASK_ACTION -->|Keep| EXIT

    WRITE_LEARNING --> CONFIRM["Learning captured.<br/>Will apply at cycle-complete."]
```

---

## Analysis Flow: `/craft:analyze`

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    ANALYZE["/craft:analyze"] --> CHECK_PENDING{"Pending findings exist?"}

    CHECK_PENDING -->|Yes| OFFER_REVIEW["Offer: Review pending first?"]
    OFFER_REVIEW --> REVIEW_CHOICE{"User choice?"}
    REVIEW_CHOICE -->|Review| JUMP_REVIEW["Jump to Step 5: Review"]
    REVIEW_CHOICE -->|Continue/Clear| SELECT_TYPE["Step 2: Select type"]

    CHECK_PENDING -->|No| SELECT_TYPE

    SELECT_TYPE --> TYPE{"Analysis type?"}

    TYPE -->|QA| QA["Spawn: qa-analyzer agent"]
    TYPE -->|UX| UX["Spawn: ux-analyzer agent"]
    TYPE -->|Creative| CREATIVE["Spawn: creative-analyzer agent"]
    TYPE -->|Style| STYLE["Spawn: style-analyzer agent"]
    TYPE -->|Walkthrough| WALK["Spawn: walkthrough-analyzer agent<br/>(browser, first-time-user simulation)"]
    TYPE -->|Full| ALL["Run all sequentially"]

    QA --> SCOPE["Step 3: Select scope"]
    UX --> SCOPE
    CREATIVE --> SCOPE
    STYLE --> SCOPE
    WALK --> SCOPE
    ALL --> SCOPE

    SCOPE --> CHECK_MCP{"chrome-devtools MCP available?"}

    CHECK_MCP -->|No| SETUP_MCP["Offer to setup MCP<br/>Create .mcp.json"]
    SETUP_MCP --> RESTART["User must restart Claude"]

    CHECK_MCP -->|Yes| RUN["Step 4: Run analysis<br/>Findings save to pending/*.yaml"]

    RUN --> JUMP_REVIEW["Step 5: Review findings"]

    JUMP_REVIEW --> FOR_FINDING["Present each finding"]
    FOR_FINDING --> ACTION{"User action?"}

    ACTION -->|"Create story"| CREATE_STORY["Run create-story.sh<br/>Update finding: story_created"]
    ACTION -->|"Keep for later"| KEEP["Update finding: pending"]
    ACTION -->|"Dismiss"| DISMISS["Update finding: dismissed"]

    CREATE_STORY --> MORE{"More findings?"}
    KEEP --> MORE
    DISMISS --> MORE

    MORE -->|Yes| FOR_FINDING
    MORE -->|No| SUMMARY["Step 7: Summary<br/>Stories created, pending, dismissed"]

    SUMMARY --> NEXT{"What next?"}
    NEXT -->|"Another analysis"| SELECT_TYPE
    NEXT -->|"Review pending"| JUMP_REVIEW
    NEXT -->|"New cycle"| ROUTE_CYCLE["/craft:cycle-design"]
    NEXT -->|"Done"| END["End"]
```

---

## Complete State Machine

```mermaid
%%{init: {'theme': 'dark'}}%%
stateDiagram-v2
    [*] --> NO_CRAFT: No .craft folder

    NO_CRAFT --> INITIALIZED: /craft:init

    INITIALIZED --> HAS_BACKLOG: /craft:story-new
    INITIALIZED --> PLANNING_CYCLE: /craft:cycle-design

    HAS_BACKLOG --> PLANNING_CYCLE: /craft:cycle-design
    HAS_BACKLOG --> HAS_BACKLOG: /craft:story-new (more stories)

    PLANNING_CYCLE --> CYCLE_READY: 95% alignment + create files

    CYCLE_READY --> CYCLE_ACTIVE: /craft:cycle-start

    CYCLE_ACTIVE --> STORY_ACTIVE: Pick story to implement
    CYCLE_ACTIVE --> CYCLE_ACTIVE: /craft:reflect (capture learnings)

    STORY_ACTIVE --> STORY_ACTIVE: Chunk loop (learnings accumulate)
    STORY_ACTIVE --> STORY_COMPLETE: All chunks done

    STORY_COMPLETE --> CYCLE_ACTIVE: More stories
    STORY_COMPLETE --> CYCLE_COMPLETE: All stories done → /craft:cycle-complete

    CYCLE_COMPLETE --> HARNESS_UPDATED: Process learnings → CLAUDE.md, rules, hooks, locks
    HARNESS_UPDATED --> ANALYZING: /craft:analyze
    HARNESS_UPDATED --> HAS_BACKLOG: Create stories from analysis
    HARNESS_UPDATED --> PLANNING_CYCLE: /craft:cycle-design

    ANALYZING --> HAS_BACKLOG: Create stories from findings
    ANALYZING --> HARNESS_UPDATED: Done analyzing

    note right of NO_CRAFT: .craft/ doesn't exist
    note right of INITIALIZED: .craft/ exists, empty
    note right of HAS_BACKLOG: Stories in .craft/backlog/
    note right of PLANNING_CYCLE: PLANNING_CYCLE set in .global-state
    note right of CYCLE_READY: Cycle files created, not active
    note right of CYCLE_ACTIVE: ACTIVE_CYCLE set, .learnings.yaml tracking
    note right of STORY_ACTIVE: CURRENT_STORY set, in-memory learnings
    note right of CYCLE_COMPLETE: All stories done, learnings ready
    note right of HARNESS_UPDATED: Learnings → CLAUDE.md, rules, hooks, locks
```

---

## Learnings Flow

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart LR
    subgraph During_Work["During Work"]
        VALIDATE["validate-chunk"]
        CORRECT["User corrections"]
        OBSERVE["Pattern observations"]
    end

    subgraph Accumulate["Accumulation"]
        MEMORY["In-memory during story"]
        FILE[".learnings.yaml at story end"]
    end

    subgraph Process["At Cycle-Complete"]
        FILTER["Filter actionable items"]
        CATEGORIZE["Categorize by target"]
        APPLY["Apply harness updates"]
    end

    subgraph Harness["Harness Outputs"]
        CLAUDE[".claude/CLAUDE.md"]
        RULES[".claude/rules/*.md"]
        HOOKS["settings.local.json"]
        LOCKED[".craft/design/locked.md"]
    end

    VALIDATE --> MEMORY
    CORRECT --> MEMORY
    OBSERVE --> MEMORY

    MEMORY --> FILE

    FILE --> FILTER
    FILTER --> CATEGORIZE
    CATEGORIZE --> APPLY

    APPLY --> CLAUDE
    APPLY --> RULES
    APPLY --> HOOKS
    APPLY --> LOCKED
```

---

## Commands Reference

| Command | Purpose |
|---------|---------|
| `/craft` | Main entry point — routes based on context |
| `/craft:init` | One-time setup for new projects |
| `/craft:status` | Rich dashboard (cycles, stories, backlog) |
| `/craft:story-new` | Create story → backlog (with alignment check) |
| `/craft:story-implement` | Implement story with chunk loop |
| `/craft:story-implement-auto` | Implement a story (autonomous, for implement phase) |
| `/craft:story-continue` | Resume interrupted story |
| `/craft:story-archive` | Move story back to backlog |
| `/craft:story-delete` | Delete a story |
| `/craft:cycle-design` | Create cycle with planned stories (95% alignment) |
| `/craft:cycle-start` | Activate cycle, choose run mode |
| `/craft:cycle-assign` | Move story from backlog to cycle |
| `/craft:cycle-complete` | Process learnings into harness updates |
| `/craft:reflect` | Capture learnings anytime |
| `/craft:analyze` | Post-cycle QA, UX, Creative, Style, Walkthrough analysis |
| `/craft:review` | PR-style code review — branch, story, or project audit. `--maze` flag for perpendicular review |
| `/craft:update-docs` | Re-scan project, update project.md and locked.md |
| `/craft:docs` | Generate or update docs using the crystallized doc-writer agent |
| `/craft:become` | Crystallize a tool, role, or person into a portable 9-section agent |
| `/craft:ask` | Consult a workshop agent — routes to the best available mind |
| `/craft:workflow` | Reusable multi-step workflows with agent/inline/manual/command execution |
| `/craft:research` | Ad-hoc research — discover, elaborate, synthesize with ranked branches |
| `/craft:research-verify` | Verify existing research findings against independent primary sources |
| `/craft:fix` | Adhoc fix for small bugs without story ceremony. Creates record in `.craft/fixes/` |
| `/craft:project` | Switch projects or cross-project dashboard |

## Skills Reference

| Skill | Invoked During | Purpose |
|-------|----------------|---------|
| `content-spark` | story-new, cycle-design | Surface content assumptions before creative/planning |
| `creative-spark` | story-new, cycle-design | Generate options, brainstorm. Step 1.5 invokes muse/alchemist interrogators |
| `design-vibe` | story-new, cycle-design (if UI) | Visual direction, aesthetics |
| `lock-decision` | story-new, cycle-design | Formalize approved decisions (typed keys) |
| `plan-chunks` | story-new, cycle-design | Break story into implementable pieces. Batch mode requires Dependencies section |
| `validate-chunk` | story-implement | TypeScript, lint, tests. Derives FILES_CHANGED from git diff |
| `refine-chunk` | story-implement | Fix validation failures |
| `test-fix` | story-implement | Triage failing tests, fix the right thing |
| `fix` | /craft:fix | Adhoc fix without story ceremony |
| `approve` | any (write gate) | Request scoped write permission from the user |
| `browser` | /craft:browser | Launch persistent playwright-cli browser session |

## Agents Reference

See `docs/agent-catalog.md` for full descriptions, model assignments, and usage guidance.

**Core Workflow**

| Agent | Invoked During | Purpose |
|-------|----------------|---------|
| `implementer` | story-implement | Owns implement→validate→refine loop per chunk |
| `tester` | story-implement | Integration tests, E2E, final validation |
| `chunk-validator` | validate-chunk | Runs quality checks, returns structured report (haiku) |
| `plan-chunks-agent` | plan-chunks (batch) | Autonomous chunk planning per story |
| `project-scanner` | update-docs | Full project analysis for documentation updates |

**Analysis**

| Agent | Invoked During | Purpose |
|-------|----------------|---------|
| `qa-analyzer` | analyze (QA) | Find bugs, errors, edge cases |
| `ux-analyzer` | analyze (UX) | Find friction, accessibility issues |
| `creative-analyzer` | analyze (Creative) | Find delight opportunities |
| `style-analyzer` | analyze (Style) | Find token violations, pattern drift |
| `walkthrough-analyzer` | analyze (Walkthrough) | First-time user simulation, clicks everything |

**Review and Research**

| Agent | Invoked During | Purpose |
|-------|----------------|---------|
| `pr-reviewer-expert` | /craft:review | PR review crystallized from CodeRabbit |
| `maze-architect` | /craft:review --maze | Perpendicular review questions from diff (haiku) |
| `researcher` | /craft:research | Investigates one sub-question, writes branch file |
| `verifier` | /craft:research-verify | Adversarial claim checker |
| `practitioner-reviewer` | /craft:research-verify | Challenges verified claims from experience |

**Browser**

| Agent | Invoked During | Purpose |
|-------|----------------|---------|
| `playwright-browser` | browser skill | Owns a live browser session via playwright-cli |

**Crystallized Experts** (consult via `/craft:ask`)

| Agent | Purpose |
|-------|---------|
| `muse` | Emotional job translator — interrogator for creative-spark Step 1.5 |
| `alchemist` | CSS interaction physicist — interrogator for creative-spark Step 1.5 |
| `conductor` | AI orchestration architect |
| `doc-writer` | Documentation diagnostician |
| `product-anthropologist` | Human-truth layer — diagnoses real-problem fit |
| `crystallizer` | Psychological synthesizer, distills research into agent personas (opus) |
| `become-researcher` | Psychological material collector for `/craft:become` |

## State Files Reference

| File | Purpose | Key Fields |
|------|---------|------------|
| `.craft/.global-state` | Global state | ACTIVE_CYCLE, PLANNING_CYCLE, CURRENT_STORY, RUN_MODE, HARNESS_CHECKED |
| `.craft/settings.yaml` | User preferences | run_mode, default_mode, certainty_threshold |
| `.craft/cycles/[N]-[name]/.state` | Cycle runtime state | CURRENT_STORY, CURRENT_CHUNK, TOTAL_CHUNKS |
| `.craft/cycles/[N]-[name]/.learnings.yaml` | Accumulated learnings | errors, corrections, patterns, conventions, automations |
| `.craft/cycles/[N]-[name]/cycle.yaml` | Cycle metadata | status, goals, target, focus (no stories array) |
| `.craft/cycles/[N]-[name]/stories/[N]-[name].md` | Story details | status, chunks, decisions (typed), acceptance |
| `.craft/backlog/[name].md` | Backlog stories | status: ready, priority |
| `.craft/analysis/pending/*.yaml` | Pending findings | QA, UX, Creative, Style queues |
| `.craft/fixes/[name].md` | Adhoc fix records | Created by /craft:fix |

## Directory Structure Check Points

```
.craft/                          ← EXISTS? → If no, route to /craft:init
├── .global-state                ← READ for ACTIVE_CYCLE, PLANNING_CYCLE, CURRENT_STORY, HARNESS_CHECKED
├── settings.yaml                ← READ for run_mode, default_mode, certainty_threshold
├── backlog/                     ← COUNT stories here
│   └── *.md                     ← Each is a ready story
├── cycles/                      ← LIST available cycles
│   └── [N]-[name]/
│       ├── cycle.yaml           ← READ status (ready/active/complete)
│       ├── .state               ← READ CURRENT_STORY, CURRENT_CHUNK (runtime only)
│       ├── .learnings.yaml      ← READ/WRITE during cycle for learnings
│       └── stories/
│           └── *.md             ← READ status, chunks
├── fixes/                       ← Adhoc fix records (permanent log)
├── analysis/
│   └── pending/
│       ├── qa.yaml              ← CHECK for pending findings
│       ├── ux.yaml
│       ├── creative.yaml
│       └── style.yaml
└── design/
    └── locked.md                ← READ locked patterns for validation
```

---

## Resolved Design Decisions

| Decision | Resolution |
|----------|------------|
| Status transitions | **Gate at command level** — status guards in story-implement and cycle-assign |
| Backlog vs cycle handling | **Smart inference with AskUserQuestion** — contextual options based on state |
| Pending findings check | **Include as AskUserQuestion option** — shown when pending > 0 |
| State corruption recovery | **Hybrid reconstruct + ask** — scan files, rebuild, ask if ambiguous |
| Parallel stories | **Bulletproof file conflict detection** — extract files from chunks, block overlaps |
| Reflect vs cycle-complete | **Reflect captures, cycle-complete processes** — separation of concerns |
| Learnings ownership | **validate-chunk logs errors, AskUserQuestion for corrections** |
| Run mode persistence | **settings.yaml with run_mode** — read at cycle-start |
| 95% alignment check | **Codebase investigation loop before plan-chunks.** Orchestrator spawns Explore agent, surfaces product questions (conflicts, adjacencies, assumptions), loops via SendMessage until zero unasked questions remain. Gate measures user intent capture, not solution confidence. `alignment` frontmatter field (`pending`/`complete`) ensures no story skips the check. See `commands/references/alignment-check.md`. |
| Design decisions | **Typed keys (layout/component/density/visibility)** — structured for Tokens Studio |
| Harness freshness | **Check at cycle-complete if > 14 days** — optional WebSearch for updates |
| Harness updates | **Applied at cycle-complete, not reflect** — CLAUDE.md, rules, hooks, locks |
| Context safety | **Save stories immediately when confirmed** — survives context compaction mid-planning |
