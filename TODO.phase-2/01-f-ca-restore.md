# F-ca: restore Canada data path from canary evidence

## Why this matters

D7 — data-ca's `processed/` is EMPTY today (0 tracked input files), yet
its committed `api/` still holds 10,558 old-schema nodes: proof the
pipeline once produced entities and then regressed. The fetch itself was
proven working on the 2026-05-11 gem (that run saved 500+ files parsed
from sema-lmes.xml; the upstream still answers HEAD 200 text/xml) — the
output was simply discarded by the gitignore and the cron then died.
Two caveats from the diagnosis: `sources/ca` code changed on main since
(PR #16, 07-22) and no spec exercises the ca parse, so current-main
health is unverified — the first re-enabled run doubles as the
verification; and the ca transformer has NEVER been exercised on real
data (audit: quality UNKNOWN, not OK). Consumer impact: Canada is one
of four sources with no data at all, while its stale committed api
misleads.

## What to do

1. After write authorization and the gitignore fix
   (`TODO.phase-1/02-data-repo-gitignore-alignment.md`) and canary
   approval (`TODO.phase-1/14-USER-canary-dispatches.md`): dispatch a
   fetch and watch the first run — it verifies current-main ca parsing.
2. Seed-commit the fetched `processed/` corpus.
3. Run `harmonize ca` — the first-ever exercise of the ca transformer;
   fix what it surfaces (first-run correctness is priced into the
   size).
4. Reconcile the result against the old-schema ~10,558-node committed
   api; stale nodes are purged at the full regeneration
   (`TODO.phase-4/01-full-harvest.md`).

## Where

- data-ca repo: `.gitignore`, `processed/` (empty), `api/` (10,558
  old-schema nodes)
- `lib/ammitto/sources/ca/` — parser/transformer, never exercised on
  real data

## Done when

- Fresh `processed/` corpus committed in data-ca.
- `harmonize ca` yields non-zero real entities that pass the hardened
  health gates.
- The discrepancy against the old committed api is understood and
  queued for the full-harvest purge.

## Size and dependencies

**M** — about a day per work sizing (the fetch-side cron flip itself is
S; the first transformer exercise is the cost). Blocked by:
`TODO.phase-1/02-data-repo-gitignore-alignment.md`,
`TODO.phase-1/14-USER-canary-dispatches.md`; the gates from
`TODO.phase-1/08-iri-nil-raise.md` and
`TODO.phase-1/09-health-gate-hardening.md` make its output
trustworthy. Unblocks: `TODO.phase-4/01-full-harvest.md`.

## ADHD

- 🔴 data-ca empty; committed api = 10,558 stale old-schema nodes (D7)
- 🧨 Canada absent from published sanctions data
- 🔧 Canary fetch → seed commit → first-ever `harmonize ca` → reconcile vs old api
- ✅ Fresh processed/ committed; harmonize ca real entities through gates
- ⛓️ Needs `TODO.phase-1/02-data-repo-gitignore-alignment.md` + `TODO.phase-1/14-USER-canary-dispatches.md`
- 📦 M — ~1 day (first-exercise allowance)
