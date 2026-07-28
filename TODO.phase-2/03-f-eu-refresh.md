# F-eu: refresh EU (frozen 05-01, namespace crash fixed on main but CI-unexercised)

## Why this matters

EU data has been frozen at 2026-05-01. From 05-01 to 06-30 every run
hit a silent lutaml namespace crash (`ERROR: String namespace URIs are
not supported`) and still concluded `success` thanks to the exit-0 bug;
then the cron went dead (06-30). The fix is already on main
(`sources/eu/export_namespace.rb`; lutaml-model pinned `~> 0.8.17`) and
was runtime-verified locally during the diagnosis — class load plus a
minimal namespaced `from_xml` parse succeed — but it has NEVER run in
CI against the real feed. The upstream default-token URL answers
HEAD 200 application/xml. Consumer impact: the EU consolidated list is
almost three months stale — every EU designation since May is missing
from the published data.

## What to do

1. With canary approval (`TODO.phase-1/14-USER-canary-dispatches.md`,
   eu in the second canary wave): dispatch the fetch and watch one run
   against the real feed — the first CI exercise of the namespace fix.
2. Confirm the data moves past 2026-05-01. eu's `processed/` corpus is
   already tracked (it is in the previously-force-added group), so no
   seed commit is needed; the gitignore fix still matters for NEW
   files.
3. Re-enable the cron only after the run produces tracked, reviewable
   changes (the acceptance-test rule).

## Where

- data-eu repo: `processed/` (tracked, frozen at 2026-05-01 content)
- `lib/ammitto/sources/eu/export_namespace.rb` — the crash fix,
  CI-unexercised

## Done when

- The canary run is green against the real feed.
- data-eu `processed/` shows post-2026-05-01 content.
- The cron is re-enabled after tracked changes appeared.

## Size and dependencies

**S** — hours per the diagnosis (dispatch/re-enable + watching one
supervised run). Blocked by:
`TODO.phase-1/14-USER-canary-dispatches.md` (dispatch approval) and
`TODO.phase-1/01-fetch-exit-honesty.md` (so a repeat crash turns the
run red instead of "success"). Unblocks:
`TODO.phase-4/01-full-harvest.md`.

## ADHD

- 🔴 EU frozen at 2026-05-01 — silent namespace crash, then dead cron
- 🔧 Fix already on main but CI-unexercised: dispatch + watch one real-feed run
- ✅ Canary green; processed/ moves past 05-01; cron re-enabled after tracked changes
- ⛓️ Needs `TODO.phase-1/01-fetch-exit-honesty.md` + `TODO.phase-1/14-USER-canary-dispatches.md`
- 📦 S — hours
