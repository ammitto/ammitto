# Fix NAME_SCRIPTS enum corruption (M2)

## Why this matters

M2 (the audit's shorthand for this fix) — the `NAME_SCRIPTS` enum in
`lib/ammitto/ontology/types.rb:109-122` was written as a `%i[]` array
with inline comments, and Ruby keeps the comment tokens as symbols: the
enum holds 37 members of which only 12 are intended ISO 15924 script
codes — the rest are prose words plus eleven `:"#"` symbols.
`valid_script?('#')` returns true (direct membership test at line 175).
On top: "Greek" should be the ISO 15924 code "Grek", and the jp
transformer emits script 'Jpan' (`sources/jp/transformer.rb:90`) which
the intended list lacks. Consumer impact: name records can claim their
writing script is "#" and validation accepts it. Discovered during the
2026-07-28 gap-matrix verification (a NEW defect not in the audit
catalog; filed as gap-matrix row R-035, runtime-verified).

## What to do

1. Rewrite the enum without inline comments inside `%i[]`; correct
   Greek → Grek; add Jpan.
2. Add a guard spec: `valid_script?('#')` must be false; every member
   must be a plausible ISO 15924 code.
3. Sweep the repo's other `%i[` blocks for the same bug — only 17
   exist, so the sweep is bounded.
4. Reconcile the scripts transformers actually emit against the fixed
   enum.

## Where

- `lib/ammitto/ontology/types.rb:109-122` — the corrupted enum
- `lib/ammitto/ontology/types.rb:175` — `valid_script?` membership test
- `lib/ammitto/sources/jp/transformer.rb:90` — emits 'Jpan'

## Done when

- `valid_script?('#')` returns false; `Grek` and `Jpan` are valid.
- Guard spec green; the `%i[` sweep finds no other comment-corrupted
  enums.

## Size and dependencies

**S** — hours; high confidence. Blocked by nothing. Unblocks: the
ontology migration (`TODO.deferred/02-phase4-ontology-migration.md`)
depends on clean enums — models must not be built against corrupt ones.

## ADHD

- 🔴 37-member script enum: 11 are `:"#"`, rest include prose words; `valid_script?('#')` == true
- 🔧 Rewrite `%i[]` without inline comments; Greek→Grek; add Jpan (`types.rb:109-122`)
- 🔎 Sweep the other 17 `%i[` blocks for the same trap
- ✅ `valid_script?('#')` false; Grek/Jpan valid; guard spec green
- ⛓️ Ontology migration (`TODO.deferred/02-phase4-ontology-migration.md`) waits on this
- 📦 S — hours
