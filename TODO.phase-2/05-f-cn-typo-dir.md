# F-cn: remove typo dir unrealiable-entity-list (D1, 9 dup files)

## Why this matters

D1 — data-cn contains a typo directory `unrealiable-entity-list/`
(note the misspelling) holding 9 byte-identical duplicates of files in
the correctly spelled `unreliable-entity-list/`. Those duplicates are
the source of cn's 68 duplicate pairs: the harvest reads 390
entity/entry pairs but only 322 unique entities survive the last-wins
dedup — and the duplicate rows leak into the search index and facets
(G12, fixed exporter-side in
`TODO.phase-1/10-search-index-dedupe.md`). Consumer impact: the same
Chinese entities appear (and are counted) twice in search. Found by
the 2026-07-28 harvest audit; the gap matrix confirmed both spellings
coexist in the repo tree.

## What to do

1. Data-repo PR deleting `unrealiable-entity-list/` (9 byte-identical
   duplicate files). Remote authorization changes calendar latency,
   not size (`TODO.phase-1/14-USER-canary-dispatches.md` covers write
   auth).
2. Regenerate cn output and verify the 390→322 pair collapse is
   resolved at the source: pairs now equal unique ids.

## Where

- data-cn repo: `sources/sanction-lists/unrealiable-entity-list/`
  (typo dir, 9 files) beside the correct
  `unreliable-entity-list/`

## Done when

- The data-cn tree contains only the correctly spelled directory.
- A fresh cn harvest shows pairs == unique entities (322), with no
  last-wins dedup delta.
- Search rows for cn match unique entities.

## Size and dependencies

**S** — hours; high confidence, bounded cleanup. Blocked by: data-repo
write authorization (`TODO.phase-1/14-USER-canary-dispatches.md`).
Complements `TODO.phase-1/10-search-index-dedupe.md` (which fixes the
exporter so any future duplicate pairs cannot inflate search).

## ADHD

- 🔴 Typo dir `unrealiable-entity-list/` = 9 byte-identical dups → cn 390 pairs vs 322 real (D1)
- 🧨 Chinese entities double-counted in search
- 🔧 Data-repo PR: delete the typo dir; regenerate
- ✅ Pairs == unique ids (322); no dedupe delta
- ⛓️ Needs write auth (`TODO.phase-1/14-USER-canary-dispatches.md`)
- 📦 S — hours
