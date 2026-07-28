# D: harden harmonize health gates (G7)

## Why this matters

G7 / audit batch D — the harmonize health gates only check "no errors",
"entities > 0", and "aggregate file exists"
(`harmonize_command.rb:131-157`), so a single garbage entity passes.
That is the US source today: one nameless entity (`names: []`) sails
through the gate, exits 0, and is SERVED as the entire US dataset.
Consumer impact: a source can be effectively empty or corrupt and still
be published as if complete — the audit's verdict line for us is
"passes gates, SERVED".

## What to do

1. Add unique-id-ratio and non-empty-name gates per source.
2. Extend the per-source result contract with quality metrics — the
   result at `harmonize_command.rb:239` carries counts only. Define
   denominators, thresholds, and multi-entity-file semantics, plus the
   interaction with `--allow-empty`.
3. Threshold policy is a decision, not a discovery (the work-sizing
   pass flags it lead-inline) — settle numbers with the lead.
4. Spec: a pre-fix us fixture (1 entity, empty names) must fail the
   gate; healthy sources must pass.

## Where

- `lib/ammitto/cli/harmonize_command.rb:131-157` — the current gates
- `lib/ammitto/cli/harmonize_command.rb:239` — per-source result
  contract (counts only today)

## Done when

- The us garbage fixture fails the gate; au/wb-style healthy fixtures
  pass.
- Unique-id-ratio and non-empty-name thresholds are documented.
- Gate results are part of the per-source result contract.

## Size and dependencies

**M** — about a day. Threshold policy is the only lead decision;
otherwise unblocked. Pairs with
`TODO.phase-1/08-iri-nil-raise.md` (audit lands C and D together).
Makes every TODO.phase-2/TODO.phase-3 restore trustworthy — regenerated data only
counts once real gates guard it — and is a listed prerequisite of
`TODO.phase-2/04-f-us-restore.md`. Interacts with
`TODO.phase-4/02-allow-empty-shrink.md`.

## ADHD

- 🔴 Gates pass garbage: US = 1 nameless entity, exit 0, SERVED (G7)
- 🔧 Unique-id-ratio + non-empty-name gates; quality metrics in the result contract (`harmonize_command.rb:131-157`, `:239`)
- 🗣️ Thresholds = lead decision, not discovery
- ✅ Pre-fix us fixture fails the gate; healthy sources pass
- ⛓️ Pairs with `TODO.phase-1/08-iri-nil-raise.md`; guards all restores
- 📦 M — ~1 day
