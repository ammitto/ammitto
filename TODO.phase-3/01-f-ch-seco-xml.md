# F-ch: process the 36.7MB SECO consolidated XML (D4)

## Why this matters

D4 — data-ch holds ONE sample input file while the full 36.7MB SECO
consolidated XML (dated 2026-02-18) sits unprocessed in
`reference-docs/`. On top, the ch transformer crashes on the current
announcement-format data (G4 — the nil-parse `NoMethodError 'any?'`
guarded in `TODO.phase-1/06-announcement-shape-guards.md`), and its
correct-schema path has NEVER been exercised on real data (audit:
quality UNKNOWN). The expected yield is on the order of ~8k identities
(the historic claim was 8,254; Ronald's own expected floor says
10,900+ — one of the F5 count contradictions). Consumer impact:
Switzerland is effectively absent from the published data.

## What to do

1. Possibly add a local-file input affordance so harmonize can consume
   the reference-docs XML (work sizing lists this as part of the row).
2. First real exercise of the 158-line ch transformer — the dispatch
   assumes bare Identity records (`harmonize_command.rb:743-748`);
   expect first-exercise fixes.
3. Watch memory/runtime behavior at 36.7MB.
4. Verify ~8k IDs and output integrity through the hardened gates.
5. Freshness afterwards comes from the restored ch fetch
   (`TODO.phase-1/03-ch-uk-json-schema-dep.md` + canary) — this card
   is about processing the corpus that already exists.

## Where

- data-ch repo: `reference-docs/` (36.7MB SECO XML, 2026-02-18),
  `processed/` (1 sample file)
- `lib/ammitto/cli/harmonize_command.rb:743-748` — ch dispatch
- `lib/ammitto/sources/ch/` — 158-line transformer, never exercised on
  real data

## Done when

- The ch harvest produces entities at the ~8k order with real content,
  passing the hardened gates.
- Memory/runtime at 36.7MB is acceptable and recorded.

## Size and dependencies

**L** — 2-4 days. Blocked by:
`TODO.phase-1/06-announcement-shape-guards.md` (work sizing: "A first
(ch crash)"), the ch-format confirmation from
`TODO.phase-2/09-USER-rulings-f1-f6-jp.md` (is ch intentionally
migrating to announcement format?), and data-repo write authorization
(`TODO.phase-1/14-USER-canary-dispatches.md`). The canary/cron side
matters only for freshness. Unblocks:
`TODO.phase-4/01-full-harvest.md`.

## ADHD

- 🔴 36.7MB of Swiss SECO data sits unprocessed; repo has 1 sample file (D4)
- 🧨 Switzerland absent from published sanctions data
- 🔧 Local-file affordance → first-ever run of the 158-line transformer at 36.7MB → verify ~8k IDs
- ✅ ~8k-order entities with real content through gates
- ⛓️ Needs `TODO.phase-1/06-announcement-shape-guards.md` + `TODO.phase-2/09-USER-rulings-f1-f6-jp.md` (ch format intent) + write auth
- 📦 L — 2-4 days
