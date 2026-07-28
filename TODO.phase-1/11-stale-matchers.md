# I: fix schema-stale matchers (G15, G25)

## Why this matters

Two matcher bugs erase list identity — the core fact of a sanctions
entry: which list it is on. G15 — the cn announcement model matches
list types against Chinese labels while the data stores slugs
(`cn/announcement.rb:120-131`), so ALL 322 Chinese entries land in
`entry/cn/unknown` with `regime/unknown` (the default hash in
`cn/transformer.rb:201-215`). A consumer cannot tell whether a Chinese
entity is on the Unreliable Entity List or the Export Control List.
G25 — the list-types registry keys vessel sources with hyphens while
the pipeline uses underscored codes
(`list_types_registry.rb:161,171,221-226`), so all 597 eu_vessels
entries land in list "unknown" (un_vessels is latently identical). The
hyphen-vs-underscore direction is already settled (fork F3,
evidence-settled: underscores are the gem's contract; site PR #7
aligns the frontend). This is audit batch I.

## What to do

1. cn: make the matcher accept slugs (plus labels) and verify the
   `LIST_TYPE_MAPPING` keys against what the data actually stores.
2. Vessels: normalize the registry's source keys to underscores per
   the settled F3 direction.
3. Regeneration checks: fresh cn entries carry real list ids; fresh
   eu_vessels entries leave "unknown".

## Where

- `lib/ammitto/sources/cn/announcement.rb:120-131` — label-vs-slug matcher
- `lib/ammitto/sources/cn/transformer.rb:201-215` — unknown default hash
- `lib/ammitto/utils/list_types_registry.rb:161,171,221-226` —
  hyphenated source keys (work-sizing cites the region 156-173)

## Done when

- Fresh cn output carries real list ids and regimes — no
  `entry/cn/unknown`, no `regime/unknown`.
- Fresh eu_vessels entries carry their real list instead of "unknown".
- un_vessels inherits the fix (exercised later by
  `TODO.phase-3/03-un-vessels-extraction.md`).

## Size and dependencies

**M** — about a day; med-high confidence, delegable (the F3 ruling it
needed is settled). Unblocks: node/list emission (G21 — by-list slices
currently reference list IRIs that nothing writes; the gem side of the
list-aware program, see `TODO.deferred/04-list-aware-site.md`) and the
list identity of `TODO.phase-3/03-un-vessels-extraction.md`.

## ADHD

- 🔴 ALL 322 cn entries + ALL 597 eu_vessels entries in list "unknown" (G15, G25)
- 🧨 Consumers can't see WHICH sanctions list an entity is on
- 🔧 cn matcher: accept slugs; vessels registry: underscore keys (`announcement.rb:120-131`, `list_types_registry.rb:161,171,221-226`)
- ✅ Fresh cn/eu_vessels output carries real list ids
- ⛓️ Unblocks node/list emission + `TODO.phase-3/03-un-vessels-extraction.md`
- 📦 M — ~1 day
