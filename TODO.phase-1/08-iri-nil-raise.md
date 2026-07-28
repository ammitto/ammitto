# C: IriSanitizer raises on nil local ids (G2,G5,G6)

## Why this matters

The IRI sanitizer silently maps nil/empty local ids — and non-nil
strings that sanitize to empty — to a shared DEFAULT_ID "unknown"
(`utils/iri_sanitizer.rb:90-102`). Three audit defects ride on that
fallback. G2 — every Japanese entity collapses to the constant IRI
`entity/jp/jp` (its id is nil, so reference_number becomes "JP-").
G6 — 37 Turkish records without a reference_number collapse into one
`entity/tr/unknown`, silently dropping 36 real persons/organizations.
G5 — the served US garbage entity is `entity/us/unknown`. Consumer
impact: distinct sanctioned parties are merged into one meaningless
record — someone screening a name against the Turkish list will not
find 36 real designees. This is audit batch C ("raise on nil local ids
in IriSanitizer").

## What to do

1. Design an exception type; make the sanitizer raise on nil/empty
   local ids instead of returning "unknown", carrying source context
   and preserving per-file error attribution.
2. Audit every caller — every IRI constructor in the codebase.
3. Specs proving the intended hard failures on jp/tr/us fixtures.
4. Sequencing decision (lead-inline): once this lands, tr goes red at
   the health gate until `TODO.phase-2/06-f-tr-refs-backfill.md`
   backfills the 37 files — that redness is correct, but when to flip
   must be decided deliberately.

## Where

- `lib/ammitto/utils/iri_sanitizer.rb:90-102` — the DEFAULT_ID fallback
- Collapse consumers: `lib/ammitto/sources/tr/transformer.rb:46,58`;
  `lib/ammitto/sources/jp/transformer.rb:58,71,123`

## Done when

- A nil/empty local id raises with source context instead of producing
  an "unknown" IRI.
- The tr slice fails loudly pre-backfill; jp/tr/us fixture specs prove
  the hard failures.
- Fresh output contains no `.../unknown` entity IRIs.

## Size and dependencies

**M** — about a day. Lands with or after
`TODO.phase-1/09-health-gate-hardening.md` (the audit pairs batches C
and D). Pairs with `TODO.phase-2/06-f-tr-refs-backfill.md` (tr stays
red between the raise and the backfill). Listed as a prerequisite of
`TODO.phase-2/04-f-us-restore.md`.

## ADHD

- 🔴 nil id → shared "unknown" IRI: 37 tr records merge into one, jp all → `entity/jp/jp`
- 🧨 36 real Turkish designees invisible to consumers
- 🔧 Raise (with source context) instead of defaulting; audit every IRI constructor (`iri_sanitizer.rb:90-102`)
- ✅ nil id raises; tr fails loudly pre-backfill; zero `unknown` IRIs in output
- ⛓️ Sequence with `TODO.phase-1/09-health-gate-hardening.md` + `TODO.phase-2/06-f-tr-refs-backfill.md`
- 📦 M — ~1 day
