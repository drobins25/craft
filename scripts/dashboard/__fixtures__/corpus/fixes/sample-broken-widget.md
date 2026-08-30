---
name: sample-broken-widget
status: accepted
created: 2026-03-05
project: sample-project
category: logic-error
source_story: widget-panel (needs the store first)
source_cycle: sample-cycle (surfaced during a live QA pass)
files_changed: 1
lines_changed: 4
trigger: manual QA pass
lesson_scope:
satisfied_todo: none-matched
---

## Symptom
The widget panel rendered stale data after a refresh.

## Root Cause
The store returned a cached list instead of re-reading.
