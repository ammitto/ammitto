# J-lite: provenance + determinism (G17, G18) — post-green

## Why this matters

G18 — the published outputs are untraceable and nondeterministic:
`rawSourceData` is always empty, source references carry no URLs, and
`retrievedAt` is stamped `Time.now` at harmonize time (the transformers
invent it — e.g. `jp/transformer.rb:106-113` — and the serializer
exposes it at `json_ld_serializer.rb:272`). That directly contradicts
ARCHITECTURE.adoc's auditability rule, which the gap matrix quotes: a
JSON-LD consumer must be able to trace any field back to the original
source. G17 — only 5 of 15 transformers populate `source_references`
at all: the field is empty on 17,102 of 19,997 entities. Consumer
impact: no way to verify where a sanctions claim came from, and every
harvest run differs byte-wise even on unchanged input, so diffs are
noise. Deferred post-green per the converged ordering (audit batch J).

## What to do

1. Provenance contract decision (lead-inline, crosses the
   fetch/data-repo boundary): where does the URL/retrieval-time truth
   live — fetch metadata, update.log, or a file field? Interacts with
   fetch restoration and the F8 layout ruling.
2. Full J: metadata persistence, migration of all 15 transformers,
   `rawSourceData` population, deterministic stats/output, and a
   two-run byte-identical verification — **XL**.
3. Descoped J-lite (this card's default): deterministic timestamps +
   source_references population, WITHOUT fetch-side persistence —
   **≈ L** per work sizing.

## Where

- `lib/ammitto/sources/jp/transformer.rb:106-113` — Time.now invention
  (pattern across transformers; only 5/15 populate source_references)
- `lib/ammitto/serialization/json_ld_serializer.rb:272` — exposes the
  invented timestamp

## Done when

- (J-lite) Two consecutive harmonize runs over unchanged input are
  byte-identical.
- `source_references` is populated by all 15 transformers (not 5/15;
  not empty on 17,102 entities).

## Size and dependencies

**L** for J-lite (2-4 days); full J is **XL** (a week or more).
Deferred post-green. Blocked by: the provenance contract decision
(lead-inline); interacts with the fetch-restoration program and the F8
ruling (`TODO.phase-1/13-USER-rulings-f5-f8.md`).

## ADHD

- 🔴 Outputs untraceable: empty rawSourceData, URL-less refs, Time.now timestamps (G18)
- 🔴 source_references empty on 17,102/19,997 entities (G17)
- 🔧 J-lite: deterministic timestamps + populate refs in all 15 transformers
- 🗣️ First: provenance-contract decision (fetch metadata? update.log? file field?)
- ✅ Two runs byte-identical; refs populated 15/15
- 📦 L (J-lite) / XL (full J) — post-green
