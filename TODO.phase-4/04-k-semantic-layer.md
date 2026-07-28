# K: JSON-LD semantic layer (G20-G24, G26)

## Why this matters

Audit batch K — the knowledge graph's semantic layer is broken for any
standards-compliant consumer. G22/G24 — serializer↔context term drift:
the serializer emits `date`/`year`/`street`/`type`/`retrievedAt`/
`isIndefinite` while the published `@context` declares
`birthDate`/`streetAddress`/`idType`/`fetchedAt` — 19,996 occurrences.
A compliant JSON-LD processor expands the data to WRONG predicates,
and JSON-LD vs Turtle disagree about the same graph. G26 —
`hasSanctionEntry` is never emitted (the audit's count: 0 of 17,101):
the entity↔entry link is untraversable in both directions for RDF
consumers. G20 — the Turtle exporter turns any URL-prefixed prose into
an IRI, so the shipped all.ttl contains INVALID IRIs that break RDF
toolchains. G23 — cn leaks snake_case `is_primary` into descriptions
(2,120 occurrences). Consumer impact: anyone loading the published
data into an RDF store gets wrong predicates, unlinkable entities, and
unparseable Turtle.

## What to do

Three bundled programs (work sizing: XL even on the cheaper path):

1. **Vocabulary reconciliation** — choose the path:
   (a) align the context to the emitted terms (consumers unbroken,
   semantically muddier) vs (b) rename the emitted terms (cleaner, but
   ripples into search extractors and the site — `useEntityData.ts`
   reads `date`/`year`/`street`/`birth_info` directly at lines
   261-419 — plus specs, README, and the schemas program). The a/b
   choice is the lead's, made under the F1 context-URL ruling.
2. **Entity↔entry linking** — `serialize_document` already embeds
   `hasSanctionEntry` (`json_ld_serializer.rb:64`) but
   `JsonLdGraphExporter` stores hashes separately and never invokes
   that logic (`:315`, `:668`; the emission gap shows at `:668-681`
   and `:895-902`) — needs an exporter two-pass redesign.
3. **Turtle safety** — escaping/validation at
   `turtle_exporter.rb:209-211` plus a TTL validation harness.

Processor-based semantic tests and full regenerated-artifact
validation dominate the effort. Full effect requires a re-harvest and
a site refresh; path (b) adds a coordinated site change.

## Where

- `lib/ammitto/serialization/json_ld_serializer.rb:221-389` — emitted
  terms; `:64` — the embed logic the exporter never calls
- `lib/ammitto/schema/context.rb:172-201` — declared context terms
- `lib/ammitto/serialization/json_ld_graph_exporter.rb:315, 668-681,
  895-902` — separate-hash storage, missing hasSanctionEntry
- `lib/ammitto/serialization/turtle_exporter.rb:209-211` — IRI-from-
  prose

## Done when

- Serializer and context agree on ONE vocabulary; a compliant JSON-LD
  processor expands to the intended predicates.
- `hasSanctionEntry` is emitted (audit baseline: 0 of 17,101) and the
  entity↔entry link is traversable in both directions.
- all.ttl passes TTL validation; JSON-LD and Turtle agree.

## Size and dependencies

**XL** — a week or more on either path (med-low confidence). Blocked
by: the F6 and F1 rulings
(`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`) and the lead's a/b path
choice. Per the converged ordering it starts after F1/F6 and runs in
parallel with phase-3 work — it gates semantic-web claims, not data
recovery. Unblocks: the schemas program
(`TODO.deferred/03-schemas-v1.md` — K controls the emitted names) and
sequences the ontology migration
(`TODO.deferred/02-phase4-ontology-migration.md`).

## ADHD

- 🔴 19,996 term-drift occurrences: compliant processors expand to WRONG predicates (G22/G24)
- 🔴 hasSanctionEntry never emitted (0/17,101) + invalid IRIs in shipped all.ttl (G26, G20)
- 🔧 Reconcile vocabulary (path a/b = lead call) + exporter two-pass + Turtle escaping/validation
- ✅ One vocabulary; entries traversable; TTL validates; JSON-LD == Turtle
- ⛓️ Needs F1+F6 rulings (`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`); runs parallel to phase 3
- 📦 XL — week+
