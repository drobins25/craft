# Changelog

Notable, user-facing changes per version. Internal changes (tests, refactors, contributor tooling) bump the version without an entry, so version numbers here may skip.

## 1.99.32

- Changed mockup rounds to edit the living page instead of regenerating it, and to verify handoffs with console/DOM checks - screenshots now happen only for viewports you can't see (mobile emulation, unattended sessions) or on request

## 1.99.31

- Changed the changelog to notable-only: features and user-visible fixes get entries, internal fixes bump the version silently

## 1.99.29

- Added /craft:mockup: a live HTML mockup funnel - a persistent alchemist builds 3 genuinely different options, you converge by reacting through diverge/refine/polish rounds, and new design values solidify to tokens.yaml at acceptance
- Added three graduation ramps for a converged mockup: port it now as a tweak, create a pre-filled story (mockup CSS is normative - ported, never reinterpreted), or park it as a notebook todo
- Added mockup visibility: a Mockups section in /craft:status and a session-start segment when mockups await a destination
- Changed story creation: the source question now also offers "From mockup" when converged mockup records exist

## 1.99.28

- Added this changelog: notable user-facing changes land here with every release, enforced by the doc-drift push gate
