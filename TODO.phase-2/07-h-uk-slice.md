# H-uk: field mapping — effects (G9), isPrimary casing (G16), nameless variants (G13)

## Why this matters

The UK slice of audit batch H (field-mapping completeness) — three
defects in the biggest working source (5,738 entities). G9 — the UK
source defines 22 sanction indicators but `to_effect_types` maps only
13 (`uk/sanctions_indicators.rb:17, 134-149`), so 567 of 5,738 entries
emit `effects: []` despite real free-text sanctions: a consumer sees a
UK entry with no sanctions effects at all. G16 — the primary-name match
is case-sensitive against the data's "Primary name" spelling
(`uk/name.rb:53-55`): 2,367 of 5,738 entities carry NO isPrimary name,
so consumers have no authoritative display name for them. G13 — 22
nameless NameVariants ship in output, and 5 entities carry multiple
isPrimary names (`uk/name.rb:59-61`; `uk/transformer.rb:255-263` — the
transformer currently accepts empty full_name).

## What to do

1. Map the 9 unmapped indicators in `to_effect_types` — the mapping
   semantics are lead-inline per work sizing (G9's vocabulary calls
   arrive mid-flight).
2. Make the primary-name match case-insensitive (fixes the
   "Primary name" casing miss).
3. Reject or repair nameless variants and resolve multiple-isPrimary
   entities.
4. Fixtures, regression counts, and a uk re-harvest to prove the
   deltas.

Note: the data-side counterparts (the 22 degenerate name records and
mixed casing inside data-uk itself, plus the structured-DOB/identifier
schema design — D10/D12/D13) belong to the separate F-uk data-repo
ops in the work-sizing table and are NOT covered by this card.

## Where

- `lib/ammitto/sources/uk/sanctions_indicators.rb:17, 134-149` — 22
  indicators, 13 mapped
- `lib/ammitto/sources/uk/transformer.rb:365-373` — effects emission;
  `:255-263` — variant handling
- `lib/ammitto/sources/uk/name.rb:53-55` — case-sensitive isPrimary;
  `:59-61` — nameless variants

## Done when

- The 567 empty-effects entries carry real effects after re-harvest.
- isPrimary is present across the 5,738 entities (no case-miss cohort
  of 2,367).
- The 22 nameless variants are handled; no entity has multiple
  isPrimary.
- Regression counts recorded against the audit's numbers.

## Size and dependencies

**M-L** — one to a few days (work sizing decomposes batch H as
"uk M-L"). No blockers to start; the G9 mapping semantics need the
lead mid-flight. Re-harvest feeds
`TODO.phase-4/01-full-harvest.md`.

## ADHD

- 🔴 567 UK entries show ZERO effects; 2,367 entities have no primary name (G9, G16)
- 🔴 22 nameless name variants; 5 entities with multiple primaries (G13)
- 🔧 Map the missing 9 indicators; case-insensitive primary match; reject nameless variants
- ✅ Effects on the 567; isPrimary on all 5,738; degenerates handled
- ⛓️ Mapping semantics = lead call mid-flight; data-side D10/D12/D13 live elsewhere
- 📦 M-L
