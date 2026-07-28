# M1: Phase 4 ontology migration (pilot plan reviewed: eu_vessels first) — post-green, 2-5wk

## Why this matters

The plan issues' "Phase 4" requires every transformer to emit the
`lib/ammitto/ontology/` models. None does today — all 15 emit the
top-level harmonized layer only, with cn half-migrated and
validator-entangled (gap-matrix rows R-099..R-113, all MISSING except
cn's PARTIAL). This is the one big architectural arc left: a rewrite
of 3,901 measured LOC across 15 transformers. The shared risk is the
serializer boundary: `JsonLdSerializer` type-dispatches on the
top-level entity classes (`json_ld_serializer.rb:106`), so migration
needs an adapter strategy plus a per-source byte-diff regression
harness. Consumer impact: none directly — this is internal
architecture — which is exactly why it is deferred post-green rather
than blocking data recovery.

## What to do

1. Pilot: eu_vessels first (118 LOC) — ≈ M, lead-reviewed. The pilot
   prices the serializer-boundary adapter, which is unpriced until it
   lands.
2. Then per source: 0.5-1.5 days each, 2-3 sources agent-parallel —
   the serializer boundary is the conflict point between parallel
   lanes.
3. cn last (439 LOC, half-migrated, validator-entangled) — the order
   comes from the validator survey.
4. Byte-diff regression harness per source throughout.

## Where

- All 15 transformers under `lib/ammitto/sources/*/transformer.rb`
  (3,901 LOC total)
- `lib/ammitto/serialization/json_ld_serializer.rb:106` — type
  dispatch on top-level classes (the boundary risk)
- `lib/ammitto/ontology/` — the target model layer (validation facade
  from PR #23 exists)

## Done when

- All 15 transformers emit ontology models.
- The per-source byte-diff regression harness is green (or diffs are
  understood and accepted).

## Size and dependencies

**XL** — plan 3-4 focused weeks; the band is honestly 2-5 weeks wide
(work sizing's own uncertainty note). Sequenced AFTER the phase-1
correctness batches and field mappings (else every fix rebases) AND
after `TODO.phase-4/04-k-semantic-layer.md` plus
`TODO.phase-1/05-name-scripts-enum.md` — otherwise the models are
built against corrupt enums and an unsettled vocabulary. Post-green.

## ADHD

- 🔴 0/15 transformers emit the ontology models the plan requires (cn half only)
- 🔧 Pilot eu_vessels (118 LOC) → per-source 0.5-1.5d, 2-3 parallel → cn last
- ⚠️ Serializer type-dispatch (`json_ld_serializer.rb:106`) = the shared risk; pilot prices it
- ✅ 15/15 on ontology models; byte-diff harness green
- ⛓️ After the TODO.phase-1 fixes + `TODO.phase-4/04-k-semantic-layer.md` + `TODO.phase-1/05-name-scripts-enum.md`
- 📦 XL — 3-4 focused weeks (band 2-5)
