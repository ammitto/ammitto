# E: dedupe search index + facets (G12, G10)

## Why this matters

G12 — the search-index exporter appends one row per entity/entry PAIR
and increments facet counts immediately
(`search_index_exporter.rb:75-113`), so sources whose input contains
duplicate pairs ship duplicate search rows: cn 390 rows vs 322 unique
entities, jp 86 vs 1, tr 275 vs 239 — while stats.json reports the
deduped numbers. G10 — cosmetic but corrosive: harmonize prints
"1 succeeded" for ch despite its crash, and log counts disagree with
deduped stats (`harmonize_command.rb:239, 962-975`). Consumer impact:
search shows the same sanctioned entity multiple times, facet counts
are inflated, and the numbers on different endpoints disagree with each
other. This is audit batch E ("endpoint alignment").

## What to do

1. Dedupe with aggregation semantics, NOT naive keep-one-by-id: one
   entity legitimately holds multiple entries, so authority / regime /
   listType / status need per-entity-row aggregation semantics — a
   decision to settle with the lead before coding (work-sizing flags it
   lead-inline).
2. Recount facets after aggregation.
3. Update the consumer/spec contracts — 13 existing exporter examples.
4. Fix the "1 succeeded" print and the log-vs-stats inconsistency
   (`harmonize_command.rb:962-975`).

## Where

- `lib/ammitto/serialization/search_index_exporter.rb:75-113` — per-pair
  `add` + immediate facet increments
- `lib/ammitto/cli/harmonize_command.rb:239, 962-975` — success print +
  count logging

## Done when

- Search-index rows equal unique entity ids per source (cn 322,
  tr 239); facet counts match the aggregated rows.
- ch's crash no longer prints "1 succeeded"; log counts agree with
  stats.
- The 13 exporter examples are updated and green.

## Size and dependencies

**M** — about a day; delegable once the aggregation semantics are
chosen. Note: cn's duplicate pairs disappear at the source when
`TODO.phase-2/05-f-cn-typo-dir.md` deletes the typo directory — this
task still must fix the exporter so any remaining duplicate pairs
cannot inflate search.

## ADHD

- 🔴 Search index ships one row per PAIR: cn 390 rows vs 322 real entities (G12)
- 🔴 ch crash still prints "1 succeeded" (G10)
- 🔧 Aggregate per entity (semantics = lead call), recount facets, fix the print (`search_index_exporter.rb:75-113`)
- ✅ Rows == unique ids per source; endpoints agree; 13 specs updated
- ⛓️ Semantics decision first; source-side dups die in `TODO.phase-2/05-f-cn-typo-dir.md`
- 📦 M — ~1 day
