# Site list-aware program (~60 rows) — collides with Astro decision

## Why this matters

Ronald's TODO-knowledge-graph.md mandates a list-aware site —
EntryPage, ListPage, BrowseListsPage, a `useListData` composable,
listType search filters — roughly 60 rows, and the gap matrix verified
essentially all of them MISSING: no `/entry`, `/list`, or
`/browse/lists` routes, no `useListData.ts`, the `SearchEntity`
interface lacks `listType`, and facet loading fetches 5 files, never
`list_types.json` (`useSearchIndex.ts:135-139`). The gem half already
ships (listType in the search index, by-list slices,
entry/{source}/{list}/{id} IRIs) — the site never caught up; that
asymmetry is fork F9, and its ruling split is: gem-side completion
delegate-now, site scope and sequencing Ronald's. Consumer impact: no
way to browse a sanctions list as a list, see an entity's per-list
entries, or filter search by list. The trap that defers this: the
imminent Astro rewrite restructures exactly the route/data-loading
architecture these pages sit on — building three new Vue pages weeks
before that migration is waste. Also verified: NO automated site test
harness exists (zero spec/test files outside node_modules), so
verification is manual.

## What to do

0. Obtain the F9 site-scope ruling from Ronald first — route it
   through the standing Ronald conversation
   (`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`); the brief to read is
   `.codex-context/fork-briefs-2026-07-28.md` section 3 (F9). What
   COMMIT-site-side implies: this ~60-row project goes ahead — but
   only on the post-Astro stack (building it in Vue weeks before an
   Astro-7 migration is waste, per the brief). What DROP-the-list-
   concept implies: it aligns with the older spec as-checked but
   orphans the data-cn normalized standard, the shipped
   listType/by-list gem surface, and the TODO program wholesale.

Then, only after the remaining gates below:

1. Contracts first: `useListData.ts` (load node/list, by-list slices,
   list statistics) and the `SearchEntity.listType` field + sixth
   facet request.
2. Three new routes/pages — EntryPage, ListPage, BrowseListsPage; the
   651-LOC waterfall-heavy `EntityPage.vue` is the precedent scale.
   Pages are agent-parallelizable after the contracts land.
3. EntityPage per-list sections + entry links; listType filter +
   result rendering + correct entity-vs-entry link targets in search.
4. Manual verification pass (no harness exists).

Adjacent, separately-gated site programs from the same sizing pass:
semantic markup/SEO (L; after K + F1 + the stack decision; content
negotiation and Link headers are infeasible on GitHub Pages — descope
those explicitly) and the site performance items (a decision that
folds into the Astro program).

## Where

- ammitto.github.io: `src/composables/useSearchIndex.ts:135-139`
  (5-facet fetch), `src/composables/useListData.ts` (absent),
  `src/router/index.ts` (no entry/list routes),
  `src/views/EntityPage.vue` (651 LOC precedent), missing
  EntryPage/ListPage/BrowseListsPage
- Gem side prerequisites: node/list emission (G21) after
  `TODO.phase-1/11-stale-matchers.md`

## Done when

- Entry, list, and browse-lists pages exist and load from the
  regenerated data; search filters by listType with a sixth facet;
  results link to the right entity-vs-entry targets.

## Size and dependencies

**XL** — a week or more. Blocked FIRST by: node/list emission + real
listType data (`TODO.phase-1/11-stale-matchers.md` and the gem-side
list work), the F9 site-scope ruling (Ronald — routed via
`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`, brief in fork-briefs
section 3), and the Astro stack decision
(`TODO.deferred/05-astro-migration.md`) — do NOT build these pages on
the outgoing Vue stack.

## ADHD

- 🔴 ~60 list-aware site rows all MISSING: no entry/list pages, no listType search
- 🧨 Consumers can't browse a sanctions list or see per-list entries
- 🔧 useListData + listType contracts → 3 new pages (parallelizable) → manual verify (no test harness!)
- ⛓️ WAIT for: gem list fixes (`TODO.phase-1/11-stale-matchers.md`), F9 ruling (via `TODO.phase-2/09-USER-rulings-f1-f6-jp.md`), Astro decision (`TODO.deferred/05-astro-migration.md`)
- 📦 XL — week+; waste if built pre-Astro
