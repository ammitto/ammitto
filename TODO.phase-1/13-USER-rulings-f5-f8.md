# USER: rule F5 (unique-ID counting) + F8 provisional (two-track layout)

## Why this matters

Two rulings only you can make, both sitting on week 1 of the converged
plan. F5 — completion accounting: the project's own documents publish
four irreconcilable entity totals (46,584 / 91,090 / 56,791 fetched /
83,916 harmonized), while the audited fresh harvest reconciles to
exactly 19,997 unique entities from 10 live sources; every "harmonized"
table turns out to double-count entities+entries. Until one counting
definition is official, every number shown anywhere — site stats,
READMEs, the plan issues — is contestable. F8 — data-repo layout:
ARCHITECTURE.adoc mandates one uniform layout for every data repo with
`sources/` as the canonical shape, but no repo today satisfies it;
reality is two tracks (announcement-track repos: `sources/` primary;
entity-track repos: `processed/` primary). Fetch restoration cannot
define what "restored" means per repo until this is ruled.

## What to read

- `.codex-context/fork-briefs-2026-07-28.md` — section 2 (F5) and
  section 1 (F8): question, positions, evidence, consequences,
  reversibility, who-rules. Nothing else is required.

## What to do

1. You rule F5: adopt unique-entity-id counting (the brief's
   evidence-favored option — the audit's 19,997 baseline) or name
   another definition. The brief classifies this delegate-now
   arithmetic hygiene; your ruling makes it official.
2. You rule F8 provisionally for the two-track layout. The brief says
   Ronald ideally rules (it amends his ARCHITECTURE.adoc), but a
   provisional two-track ruling is recommended if he stays silent —
   the evidence is one-sided and fetch restoration should not wait —
   with the ARCH amendment presented to him for ratification.

## What saying yes/no implies

- **F5 yes (unique ids):** stats.json, site stats, README claims, and
  issues #13/#14/#15 get re-stated on one definition; entries become a
  separately stated count; the legacy totals (46k/56k/83k/91k) are
  retired as method artifacts. Forecloses nothing. **No:** no
  audit-reconcilable basis exists; every externally shown number stays
  contestable.
- **F8 yes (two-track):** ARCHITECTURE.adoc is amended to describe both
  tracks and settle the api-vs-api/v1 variance; per-repo restoration
  targets become definable immediately. Forecloses the "one uniform
  layout" simplification — aggregator/CI keep a two-case branch.
  **No (retrofit ARCH everywhere):** every entity-track repo must grow
  `sources/` plus schemas/scripts/update.log and a derivation step —
  large data + gem work before restoration can start; delays it
  substantially. Ruling before restoring matters: repos restored under
  one ruling create migration cost if it flips later.

## Where

- `.codex-context/fork-briefs-2026-07-28.md` — sections 2 (F5) and
  1 (F8), the ruling briefs
- Downstream targets of the rulings: stats.json / site stats / README
  counts (F5); ARCHITECTURE.adoc in the data program (F8 amendment)

## Done when

- Both rulings are recorded (a sentence each is enough), F8 marked
  provisional pending Ronald's ratification.

## Size and dependencies

Decision-only — minutes to read two brief sections; no code. Blocks:
every externally shown number, the restoration targets of
`TODO.phase-2/01-f-ca-restore.md` through
`TODO.phase-2/04-f-us-restore.md` ("restored to N entities" is
meaningless until N has a definition, and "restored" needs the layout
ruling), and the sync pack sent in
`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`.

## ADHD

- 🔴 Four contradictory published totals; audited truth = 19,997 unique entities
- 🔴 No definition of what a "restored" data repo must look like
- 📖 You read: fork-briefs sections 2 (F5) + 1 (F8) — that's all
- 🔧 You rule: unique-entity-id counting; two-track layout (provisional)
- ✅ Two one-sentence rulings recorded
- ⛓️ Blocks restore targets + every public number
