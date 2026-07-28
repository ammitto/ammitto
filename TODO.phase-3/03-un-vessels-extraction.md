# F-un_vessels: extract from committed 335KB HTML (easier than PDF)

## Why this matters

D6 — the daily un-vessels run downloads the UN 1718 Committee PDF and
then saves 0 files: `Sources::UnVessels`' `from_pdf` is an empty-list
stub (the same pattern as jp — and it is the path `fetch_command.rb`
actually takes). A parseable 335KB HTML version sits committed in
`reference-docs/`, never extracted; the diagnosis judges the HTML
table "likely easier than PDF". The committed api claims 32 entities
while its own all.jsonld holds 1 pair — self-contradictory. Commits
stopped on 07-21 when merge #4 removed the last tracked
`processed/_index.yaml`, so runs stay green while nothing lands.
Consumer impact: DPRK-related vessel designations are absent and the
committed api misleads.

## What to do

1. Run the unproven `scripts/parse_un_vessels_list.rb` on the
   committed 335KB HTML; fix what breaks (first run ever).
2. First exercise of the un_vessels transformer.
3. Apply the list-identity fix from
   `TODO.phase-1/11-stale-matchers.md` — G25's hyphen/underscore key
   mismatch is latently identical for un_vessels.
4. Resolve the committed-api contradiction (claims 32 vs 1 pair);
   regenerate.
5. Seed-commit the corpus (write authorization required).

## Where

- data-un-vessels repo: `reference-docs/` (335KB HTML; PDFs), no
  `processed/` corpus, contradictory `api/`
- Gem: `scripts/parse_un_vessels_list.rb` (unproven);
  `Sources::UnVessels` `from_pdf` empty-list stub
- `lib/ammitto/utils/list_types_registry.rb` — G25 key format (fixed
  in phase-1/11)

## Done when

- The un_vessels harvest yields real vessel entities with real list
  identity (not "unknown"), and the count reconciles against what the
  335KB HTML actually contains — derive the expected number from the
  source; do NOT assert the committed api's "32", which its own
  all.jsonld (1 pair) already disproves.
- The api is internally consistent (stats match the graph).

## Size and dependencies

**M** — about a day per work sizing (the diagnosis brackets the
extraction implementation M-L). Blocked by:
`TODO.phase-1/11-stale-matchers.md` (list identity) and data-repo
write authorization (`TODO.phase-1/14-USER-canary-dispatches.md`).
Unblocks: `TODO.phase-4/01-full-harvest.md`.

## ADHD

- 🔴 un_vessels: PDF downloaded daily, 0 files saved (stub); api claims 32, holds 1 (D6)
- 🧨 DPRK vessel designations absent
- 🔧 Run `parse_un_vessels_list.rb` on the committed 335KB HTML; first transformer exercise; fix list identity
- ✅ Real vessel entities, count derived from the HTML source; real lists; api consistent
- ⛓️ Needs `TODO.phase-1/11-stale-matchers.md` (list keys) + write auth
- 📦 M (extraction itself M-L per diagnosis)
