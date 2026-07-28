# F-tr: backfill 37 missing reference_numbers (D2)

## Why this matters

D2 — 37 of data-tr's 275 files lack a `reference_number`. Paired with
G6 (the IRI sanitizer's silent nil fallback,
`iri_sanitizer.rb:91`), they all collapse into one shared
`entity/tr/unknown` (`tr/transformer.rb:46,58`), silently dropping 36
real persons and organizations from the published data. Consumer
impact: 36 real Turkish designees are invisible to anyone screening
against the list. Complication from work sizing: the source of truth
for the missing refs is UNKNOWN — the TR XML in `downloaded/` may hold
them; if the upstream truly lacks them, a name-slug fallback changes
identity semantics consumed by the strict IRIs of
`TODO.phase-1/08-iri-nil-raise.md`.

## What to do

1. Investigate the TR XML in data-tr `downloaded/` for the missing
   reference numbers.
2. Run a collision analysis for the chosen identity scheme.
3. Backfill the 37 files (data-repo PR; write authorization needed).
4. Verify all 275 files: unique ids, zero unknown.
5. If the upstream genuinely lacks refs: escalate the name-slug
   fallback decision to the lead — it changes identity semantics
   (lead-inline per work sizing), do not decide it inside the task.

## Where

- data-tr repo: the 37 `processed/` files without `reference_number`;
  `downloaded/` TR XML (possible ref source)
- `lib/ammitto/sources/tr/transformer.rb:46,58` — where missing refs
  collapse
- `lib/ammitto/utils/iri_sanitizer.rb:91` — the silent nil fallback

## Done when

- The tr slice yields 275 unique ids with zero `unknown`.
- The strict-IRI mode from `TODO.phase-1/08-iri-nil-raise.md` passes
  for tr (it fails loudly until this backfill lands — expected).

## Size and dependencies

**M** — about a day, but LOW confidence (the source-of-truth unknown is
the risk). Blocked by/sequenced with:
`TODO.phase-1/08-iri-nil-raise.md` (tr goes red between that raise and
this backfill — deliberate sequencing), data-repo write authorization
(`TODO.phase-1/14-USER-canary-dispatches.md`), and possibly a refetch
if the current `downloaded/` XML lacks the refs.

## ADHD

- 🔴 37/275 tr files without reference_number → all merge into `entity/tr/unknown` (D2+G6)
- 🧨 36 real Turkish designees invisible
- 🔧 Mine `downloaded/` XML for refs → collision check → backfill PR → verify 275
- ⚠️ If upstream lacks refs: name-slug fallback = lead decision (identity semantics)
- ✅ 275 unique ids, zero unknown; strict IRIs green for tr
- 📦 M — ~1 day, low confidence
