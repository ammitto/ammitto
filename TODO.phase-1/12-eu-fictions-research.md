# G19 research: eu status/effects source fields + fixtures

## Why this matters

G19, rated SEVERE by the audit — the EU transformer hardcodes every
entry's status to "active" and its effects to a single asset_freeze
(the hardcodes sit at `eu/transformer.rb:134`, `:129`, and
`:252-258`). These are fictions: the source data holds 88 suspended-since
files and 10 travel-ban mentions. Consumer impact: an EU entry whose
sanctions are suspended still shows as active with an asset freeze — a
wrong legal status published on a sanctions site. Smaller hardcode
analogues exist in au (3) and uk (5). This phase-1 card is the research
slice ONLY — the converged ordering is explicit: "eu source-field
RESEARCH + fixtures only — no invented mappings". The production fix is
`TODO.phase-3/05-eu-fictions-fix.md`, gated on the status-vocabulary
ruling.

## What to do

1. Research which EU source fields actually carry status and effects —
   ground truth: the 88 suspended-since files and the 10 travel-ban
   mentions in the real data.
2. Build fixtures capturing the real field shapes.
3. Write up the proposed field mapping for the phase-3 fix.
4. Do NOT change production output and do NOT invent mappings.

## Where

- `lib/ammitto/sources/eu/transformer.rb:134, 129, 252-258` — the
  hardcoded status/effects (work-sizing cites the region 120-147,
  249-256)
- EU source data — the 88 suspended-since files, 10 travel-ban mentions

## Done when

- Fixtures exist covering suspended and travel-ban source records.
- A written field-mapping proposal exists for
  `TODO.phase-3/05-eu-fictions-fix.md`.
- Production output is unchanged.

## Size and dependencies

**S-M** — hours up to about a day (the full eu fix is sized M-L inside
audit batch H; this is only its research front). Blocked by nothing —
it runs in week-1 parallel per the converged ordering. Unblocks:
`TODO.phase-3/05-eu-fictions-fix.md` (which additionally needs the F6
status-vocabulary ruling from
`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`).

## ADHD

- 🔴 EU: every entry hardcoded "active" + asset_freeze vs 88 suspended files (G19)
- 🧨 Suspended sanctions shown as active — wrong legal status, public site
- 🔬 THIS CARD = research + fixtures only; no mapping invented, no prod change
- ✅ Fixtures for suspended/travel-ban records + written mapping proposal
- ⛓️ Feeds `TODO.phase-3/05-eu-fictions-fix.md` (that one also needs the F6 ruling)
- 📦 S-M
