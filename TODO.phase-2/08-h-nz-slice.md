# H-nz: add alias + address attributes to model (G14, 452+107 records)

## Why this matters

G14, the NZ slice of audit batch H — the NZ source model simply has no
attributes for aliases or addresses, so 452 alias records and 107
address records present in the source data are dropped on the floor
(`nz/sanctions_list.rb`; the entity constructors in
`nz/transformer.rb` never receive them). Consumer impact: alias
screening — the main reason sanctions lists carry aliases — misses NZ
designees who appear under alternate names, and their addresses are
absent. NZ covers the Russia register only (per the fetch diagnosis),
so this is Russia-related data quality.

## What to do

1. Add alias and address attributes to the NZ model
   (`nz/sanctions_list.rb`).
2. Map them through every entity constructor in the transformer
   (`nz/transformer.rb:83-99`; work sizing notes the mapping is absent
   from every constructor, entry point `:43`).
3. Fixtures for known alias/address records; re-harvest check that the
   452/107 records materialize in output.

## Where

- `lib/ammitto/sources/nz/sanctions_list.rb` — model lacks the
  attributes
- `lib/ammitto/sources/nz/transformer.rb:43, 83-99` — constructors
  that must carry them

## Done when

- Known fixtures show aliases and addresses in harmonized output.
- A re-harvest materializes the 452 alias and 107 address records.

## Size and dependencies

**S-M** — hours to about a day (work sizing decomposes batch H as
"nz S-M"). No blockers. Re-harvest feeds
`TODO.phase-4/01-full-harvest.md`.

## ADHD

- 🔴 NZ drops 452 aliases + 107 addresses — model has no fields for them (G14)
- 🧨 Alias screening misses NZ/Russia designees under alternate names
- 🔧 Add model attributes + wire through every constructor (`nz/transformer.rb:83-99`)
- ✅ Fixtures show aliases/addresses; re-harvest materializes 452+107
- ⛓️ Nothing blocks it
- 📦 S-M
