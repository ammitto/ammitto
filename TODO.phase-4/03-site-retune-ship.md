# Site: retune thresholds, merge #6/#8/#7, deploy with coverage status

## Why this matters

The public site is broken and stale on every axis. The deploy pipeline
has been broken since Feb 26 (a build-api path bug; the fix is site
PR #6). What the live site serves is a CN-only March snapshot —
`public/api/v1/stats.json` says cn 323, generated 2026-03-03 — while
the full tree sits unserved, and the live March stats double-count AU
(3,811 real files vs the claimed 7,468). Vessel pages 404 because of
the hyphen/underscore mismatch (site PR #7 fixes; that is fork F3's
settled direction). Consumer impact: the public face of the project
shows months-old single-source data with inflated numbers and broken
vessel pages. The chain per the gap matrix: ordered merges
**#6 (pipeline repair) → #8 (unpin + thresholds) → #7 (vessel
slugs)** — four remote state transitions with CI feedback cycles, then
verify the deploy against newly regenerated data. All three PRs are
review-converged; the day goes into pipeline verification, not code.

## What to do

This card mixes maintainer actions (the original board marks the
merges and deploy-watch as USER work) with developer verification —
each step names its actor.

1. MAINTAINER decides the policy gate first: ship-fresh-but-partial vs
   hold (discussion-queue item 6). What to read for the decision: the
   work-sizing C4 row in `.codex-context/work-sizing-2026-07-28.md`.
   Shipping partial means the site goes live with an explicit coverage
   date and per-source status rather than waiting for 15/15; holding
   keeps the stale March snapshot public until more restores land.
2. MAINTAINER merges site PR #6; waits for CI. Then #8. Then #7.
   (Merges and the deploy are remote actions — the maintainer's.)
3. DEVELOPER verifies the deploy against the regenerated data from
   `TODO.phase-4/01-full-harvest.md`.
4. DEVELOPER confirms the shipped site states its coverage: explicit
   coverage date + per-source status (the converged week-4
   requirement).

## Where

- ammitto.github.io repo: site PRs #6, #8, #7 (review-converged, in
  that order); the deploy workflow (broken since Feb 26);
  `public/api/v1/` (stale CN-only March snapshot)

## Done when

- The live site serves freshly regenerated multi-source data.
- Explicit per-source coverage status and coverage date are visible.
- Vessel pages stop 404ing (PR #7 landed).

## Size and dependencies

**M** — about a day, mostly pipeline verification. Blocked by: the
ship-partial-vs-hold policy decision (yours); its value rises with
each restore that lands (or is honestly exempted via
`TODO.phase-4/02-allow-empty-shrink.md`). Depends on
`TODO.phase-4/01-full-harvest.md` for the data. Merges/pushes/deploys
are user-gated remote actions.

## ADHD

- 🔴 Live site: deploy broken since Feb 26, serving CN-only March snapshot with inflated AU stats
- 🔧 Maintainer merges, in order: site #6 → #8 → #7; developer verifies deploy on fresh data
- 🗣️ Policy first: ship-fresh-but-partial vs hold (maintainer's call)
- ✅ Live site = fresh multi-source data + explicit per-source coverage + date
- ⛓️ Needs `TODO.phase-4/01-full-harvest.md`; all merges are your remote actions
- 📦 M — ~1 day of pipeline verification
