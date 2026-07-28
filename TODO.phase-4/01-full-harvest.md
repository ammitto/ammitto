# Full 15-source harvest + reconciliation

## Why this matters

D11 — the committed `api/` trees across the data repos are stale and
schema-obsolete: data-ca's holds 10,558 old-schema nodes, data-ru's
contradicts itself (stats 1,995 vs graph 4), un-vessels claims 32 vs
1 pair, and every non-cn tree carries the injected cn nodes until the
G8 fix's output regenerates them. This is the collector run that makes
the published data honest: regenerate all 15 `api/` trees plus the
aggregate repo AFTER the per-repo fixes land, and verify everything.
Consumer impact: this is the moment published counts match reality —
no stale nodes, no unknown ids, no cross-source contamination.

## What to do

1. Run the regeneration across all 15 data repos plus the aggregate
   `data` repo — 16 commit+push cycles (pushes are user-gated remote
   actions).
2. Verify stale-node removal: ca's old-schema nodes gone, ru's
   contradiction gone, the cn-injection (G8) purged from every non-cn
   tree.
3. Verify per-source totals against data-repo evidence, unique-id
   ratios, cross-links, and facets. Cross-link scope note: entry→entity
   references exist today, but entity→entry (`hasSanctionEntry`) is
   never emitted — that is G26, fixed by
   `TODO.phase-4/04-k-semantic-layer.md`, which is NOT one of this
   card's prerequisites. Verify cross-links as they exist and record
   the known G26 gap unless K has already landed.
4. Reconcile the aggregate: the audit's method — the all.jsonld total
   must equal the exact sum of per-source unique ids.

## Where

- All 15 `data-{source}` repos' `api/` trees + the aggregate
  `ammitto/data` repo
- Gem: `ammitto harmonize` / the exporters (already fixed by the
  phase-1 tasks this depends on)

## Done when

- Per-source counts match data-repo evidence; unique-id ratio is 1.0
  per source; zero `unknown` ids anywhere.
- ca's 10,558 old-schema nodes and ru's 1995-vs-4 contradiction are
  gone; non-cn trees carry no cn nodes.
- The aggregate reconciles exactly (sum of per-source unique ids).

## Size and dependencies

**L** — 2-4 days per work sizing, and only because the per-repo
discovery costs are booked in the restore tasks it depends on; run
WITHOUT them it absorbs their first-exercise costs and becomes XL (the
sizing review adjudicated exactly this). Blocked by: the gem
correctness set `TODO.phase-1/04-de-hardcode-cn-dirs.md`,
`TODO.phase-1/06-announcement-shape-guards.md`,
`TODO.phase-1/08-iri-nil-raise.md`,
`TODO.phase-1/09-health-gate-hardening.md`,
`TODO.phase-1/10-search-index-dedupe.md`, and
`TODO.phase-1/11-stale-matchers.md`, plus all applicable restore cards
in TODO.phase-2/ and TODO.phase-3/,
plus write authorization
(`TODO.phase-1/14-USER-canary-dispatches.md`). Unblocks:
`TODO.phase-4/02-allow-empty-shrink.md` and
`TODO.phase-4/03-site-retune-ship.md`.

## ADHD

- 🔴 Committed api/ trees stale + self-contradictory + cn-contaminated (D11)
- 🔧 Regenerate all 15 + aggregate; 16 commit+push cycles (pushes user-gated)
- ✅ Counts match evidence; unique-id ratio 1.0; zero unknowns; aggregate sums exactly
- ⛓️ AFTER the TODO.phase-1 gem fixes + the TODO.phase-2/TODO.phase-3 restores — else this balloons to XL
- 📦 L — 2-4 days (as the collector, not the discoverer)
