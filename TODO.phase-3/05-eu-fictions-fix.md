# G19 production fix: eu status/effects from source data

## Why this matters

G19, rated SEVERE by the audit — the EU transformer hardcodes every
entry's status to "active" and its effects to a single asset_freeze
(the hardcodes sit at `eu/transformer.rb:134`, `:129`, and
`:252-258`), while the real source data holds 88 suspended-since files
and 10 travel-ban mentions. Consumer impact: an EU entry whose
sanctions are suspended is published as active with an asset freeze —
a false legal status on a sanctions data service. The research half
(field identification + fixtures, no invented mappings) is
`TODO.phase-1/12-eu-fictions-research.md`; this card is the production
mapping, which additionally needs the F6 status-vocabulary ruling so
the emitted statuses come from an agreed enum.

## What to do

1. Implement the status mapping from the source fields identified by
   the phase-1 research, using the vocabulary settled by the F6 ruling
   (`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`).
2. Implement effects mapping from source data — travel bans and
   whatever else the research surfaced — replacing the hardcoded
   single asset_freeze.
3. Turn the research fixtures into specs.
4. Re-harvest eu and record regression counts (88 suspended, 10
   travel-ban as the known ground truth).

Note: the audit records smaller hardcode analogues in au (3) and
uk (5) — flag them; they are not this card's scope.

## Where

- `lib/ammitto/sources/eu/transformer.rb:134, 129, 252-258` — the
  hardcoded status/effects (work-sizing region: 120-147, 249-256)

## Done when

- After re-harvest, the entries backed by the 88 suspended-since
  source files emit `suspended` — verify against those files (the
  audit counts files, not entries; do not assert an entry count).
- Travel bans are emitted where the source records them (10 known
  mentions).
- No hardcoded active/asset_freeze defaults remain in the eu
  transformer.

## Size and dependencies

**M-L** — one to a few days (work sizing decomposes batch H as
"eu M-L", noting real EU field research and vocabulary rulings).
Blocked by: the F6 ruling
(`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`) and the fixtures from
`TODO.phase-1/12-eu-fictions-research.md`. Re-harvest feeds
`TODO.phase-4/01-full-harvest.md`.

## ADHD

- 🔴 EU publishes fictions: everything "active" + asset_freeze vs 88 suspended files (G19)
- 🧨 Suspended sanctions shown as active — false legal status
- 🔧 Map status+effects from researched source fields under the F6 vocabulary
- ✅ Suspended-file-backed entries emit suspended; travel bans emitted; hardcodes gone
- ⛓️ Needs F6 ruling (`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`) + fixtures (`TODO.phase-1/12-eu-fictions-research.md`)
- 📦 M-L
