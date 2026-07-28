# A-JP: announcement ingestion + jp identity (G1, G2)

## Why this matters

Japan is the audit's TOTAL LOSS: 101 announcement-format files hold
673 real entities; the harvest yields ONE garbage id. G1 — each
announcement file is parsed as a single flat `Jp::Entity` with every
field nil (`harmonize_command.rb:895-905`;
`sources/jp/entity.rb:10-17`). G2 — with the id nil, reference_number
becomes "JP-" and every entity collapses to the constant IRI
`entity/jp/jp` (`jp/transformer.rb:58,71,123`;
`iri_sanitizer.rb:90-102`). Fifteen of the 101 files additionally
crash on the YAML round-trip (G3, fixed in
`TODO.phase-1/07-kill-yaml-roundtrips.md`). Consumer impact: Japan
METI's list is entirely missing from the published data while the
pipeline reports jp as processed. Work sizing is emphatic this is NOT
a cn copy-paste: `schemas/japan/jp-announcement.yml` defines nested
multilingual names (ja/en/zh-Hans/ko objects),
instruments-with-articles, sanction_list — and NO required per-entity
id, so the identity design has no precedent in the repo.

## What to do

1. Build the jp announcement model family and a transformer path
   analogous to cn's — announcement detection at
   `harmonize_command.rb:763-794` is currently cn-only; cn's stack for
   scale reference: `announcement.rb` 269 LOC + transformer 439 LOC.
2. Implement collision-resistant identity (name-slug ids) per the jp
   identity ruling from `TODO.phase-2/09-USER-rulings-f1-f6-jp.md` —
   the HARD completion dependency.
3. Specs across the model, transformer, and identity design.
4. Re-harvest the 101 files / 673 entities and verify.

Scope notes: the loud-reject guards for announcement-shaped input on
ch/us/uk already landed in
`TODO.phase-1/06-announcement-shape-guards.md`. Fetching CURRENT jp
data from METI is a separate problem not covered here (the extractor
is an explicit stub and both documented METI URLs return 403 from the
diagnosis's probe vantage). D9's stray uk announcement file signals
the scope could grow if Ronald confirms a broader migration.

## Where

- `schemas/japan/jp-announcement.yml` — the format definition (no
  required per-entity id)
- `lib/ammitto/cli/harmonize_command.rb:763-794` — cn-only
  announcement detection; `:895-905` — current flat jp parse
- `lib/ammitto/sources/jp/entity.rb:10-17` — flat string model
- `lib/ammitto/sources/jp/transformer.rb:58,71,123` — constant-id
  path

## Done when

- The jp harvest yields ~673 unique entity ids — zero constant-id
  collapse, zero `Psych::AliasesNotEnabled` errors.
- Identity is collision-resistant per the ruling; specs green.

## Size and dependencies

**XL** — a week or more. HARD completion dependency: the jp identity
ruling (`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`) — model/transformer
work is delegable and can START before it. Interacts with the strict
IRIs of `TODO.phase-1/08-iri-nil-raise.md`. Unblocks jp's row in
`TODO.phase-4/01-full-harvest.md`.

## ADHD

- 🔴 Japan = TOTAL LOSS: 673 real entities in files, 1 garbage id out — all collapse to `entity/jp/jp` (G1+G2)
- 🔧 New jp announcement model family + cn-style transformer path + name-slug identity
- ⚠️ NOT a cn copy-paste — schema has no required per-entity id
- ✅ ~673 unique ids, no collapse, no Psych errors
- ⛓️ HARD dep: jp identity ruling (`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`)
- 📦 XL — week+
