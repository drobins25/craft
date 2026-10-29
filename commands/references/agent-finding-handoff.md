# Agent → User Finding Handoff (Inline Reference)

This file is Read inline by agents that surface findings to the user after deep research. It defines the translation rule that prevents bare identifiers (table names, file paths, locked-decision numbers, commit hashes, acronyms) from appearing in findings without semantic context.

**DO NOT invoke this as a skill via the Skill tool.** Calling agents Read this file and apply its rule inline. Skill-tool nesting causes the chain break documented in the chain-break-fix-discovery memo.

## When This Runs

This file is Read by three specific agents RIGHT BEFORE they surface findings to the user. Not at task start, not during research - at the output handoff boundary:

- **`plan-chunks-agent`** - before formatting concerns and findings for return to the orchestrator
- **`alignment-check.md` Step 3** - before writing the question cards that surface gaps to the user
- **`pr-reviewer-expert`** - before writing the review report

These three agents do most of their thinking in isolated contexts (deep research, codebase scans, diff reads). The user is not in that context. Reading this file at the output boundary closes the context-handoff gap.

## The Self-Contained Test

The rule, stated once:

> **Could a stranger read this finding without my research context and answer the question? If no, expand.**

The test is subjective but anchorable - applied to one finding at a time, with the examples in this file as calibration. Run the test on every finding you're about to surface. If it fails, apply the Identifier-Type Translation Table below.

## Identifier-Type Translation Table

Every identifier type below has a translation pattern. The Good column shows the right-sized expansion: what the thing IS + what it does/stores + current state (where relevant).

| Identifier type | Bad (raw) | Good (semantic) |
|---|---|---|
| Table/column name | "HZ_ARG_GROUPS needs HX_BU_ID" | "Argument-groups lookup table (HZ_ARG_GROUPS, 12 rows mapping codes to labels) needs a business-unit filter column (HX_BU_ID, currently missing)" |
| File path | "src/api/CustomerProfile.cs needs update" | "The customer profile API (src/api/CustomerProfile.cs - builds the Oracle-to-frontend mapping in MapCustomer()) needs an update" |
| Function name | "MapCustomer() returns wrong type" | "The MapCustomer() method (assembles the API response from Oracle source data) currently returns industry as int instead of string" |
| LD/Pattern/concept # | "Violates LD 4" | "Violates the rule that all Oracle ID fields render as strings (locked decision #4 at .craft/design/locked.md)" |
| Commit hash | "Commit 1432 changed it" | "The recent commit changing MapCustomer() in CustomerProfile.cs - switched industry from string to int (was: string `Manufacturing`, now: int `47`)" |
| Acronym (HZ_, HX_, etc.) | "Check HZ_CUST_SITES" | "Check the customer-to-site relationship table (HZ_CUST_SITES, ~50K rows linking customers to physical locations)" |
| Config key | "Set EnableCustomerProfileTab" | "Set the customer profile feature flag (EnableCustomerProfileTab - currently false in dev, controls whether the new profile tab is visible)" |
| Env var | "Add ORACLE_DSN" | "Add the Oracle connection string env var (ORACLE_DSN - used by the data-access layer for read-only Oracle queries)" |
| Ticket # | "Resolves ADO 35758" | "Resolves the Address & Contact backend story (ADO 35758) which extends the customer profile API with 5 deferred fields" |

## Right-Sized Expansion

Each expansion includes three components:

1. **What it IS** - the kind of thing (table, file, method, locked decision, commit, etc.)
2. **What it does or stores** - the role it plays in the system
3. **Current state** - size, status, or value WHERE RELEVANT to the finding

Component 3 is where most expansions go wrong. Include it when it's load-bearing for the question being asked. Skip it when the finding is about something else (e.g., for a rule violation, the rule text matters more than the rule's row count).

**Bad (under-expanded):** "The argument-groups table needs a filter column."
- Missing: it's a lookup table, it has 12 rows, the missing column is HX_BU_ID, no such column currently exists.

**Bad (over-expanded):** "The argument-groups lookup table (HZ_ARG_GROUPS, 12 rows, indexed on group_code, created 2024-Q3, owner = data-platform-team, last migrated in commit 8392f1a) needs a business-unit filter column (HX_BU_ID)."
- Bloat: index, creation date, owner, last migration aren't load-bearing for "needs a filter column."

**Good (right-sized):** "The argument-groups lookup table (HZ_ARG_GROUPS, 12 rows mapping codes to labels) needs a business-unit filter column (HX_BU_ID, currently missing)."

## When NOT to Expand

The Self-Contained Test produces bloat if applied indiscriminately. Skip expansion in these cases:

- **Identifiers the user just mentioned in this turn.** If the user asked "what's wrong with HZ_ARG_GROUPS?" don't expand "HZ_ARG_GROUPS" back at them - they have the context.
- **Identifiers that ARE the proper noun for what's being discussed.** If the conversation is about "the customer profile tab," don't define "customer profile tab" mid-finding. It's the subject of the conversation.
- **Standard tool/framework names known broadly.** TypeScript, React, Postgres, Next.js, ESLint - don't define unless relevant to the specific finding. "Postgres" doesn't need "Postgres (relational database)."
- **Identifiers the user has already locked or named themselves in this session.** A decision they captured doesn't need re-naming when you reference it.

The test is "would a stranger reading this finding cold need expansion?" - not "should every identifier be expanded always."

## Self-Contained Test Application

Apply the test to each finding you're about to surface. Examples:

**Finding: "MapCustomer returns int instead of string for industry."**
- Test: Would a stranger know what MapCustomer is, what it should return, or where it lives?
- Result: **Fails.** Stranger has no idea what MapCustomer does or where to look.
- Expanded: "The MapCustomer() method in src/api/CustomerProfile.cs (assembles the API response from Oracle source data) currently returns the industry field as an int instead of a string - the frontend renderer expects a string."

**Finding: "Add a unique constraint to user.email."**
- Test: Would a stranger know what user.email is, and that a unique constraint is the right kind of fix?
- Result: **Passes.** `user.email` is self-explanatory if the conversation is about user management. Unique constraint is the standard pattern.
- No expansion needed.

**Finding: "Commit 1432 violates LD 4."**
- Test: Would a stranger know what commit 1432 changed, what LD 4 says, or what's locked about it?
- Result: **Fails twice** (commit reference + LD number both opaque).
- Expanded: "The recent commit changing MapCustomer() (commit 1432, switched industry from string to int) violates the rule that all Oracle ID fields render as strings (locked decision #4 at .craft/design/locked.md)."

**Finding: "Set EnableCustomerProfileTab to true in production."**
- Test: Would a stranger know what EnableCustomerProfileTab is and what it controls?
- Result: **Fails** - flag name implies its function but stranger doesn't know its current state or scope.
- Expanded: "Set the customer profile feature flag (EnableCustomerProfileTab - currently false in production, controls visibility of the new profile tab) to true."

## Apply Then Surface

After running the test and expanding identifiers that need it, surface the finding via your agent's normal output mechanism (concerns table, question card, review report). This file does not change WHEN or HOW findings are surfaced - only the CONTENT of each finding.
