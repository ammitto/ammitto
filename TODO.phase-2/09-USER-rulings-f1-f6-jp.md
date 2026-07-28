# USER/RONALD: rule F1 (domain), F6 (status vocab), jp identity; confirm announcement-migration intent

## Why this matters

Four decisions gating the phase-3/4 work; three are ultimately
Ronald's. F1 — canonical domain and context URL: the docs and code use
three domains and three context paths interchangeably
(www.ammitto.org IRIs in code and READMEs; the code's CONTEXT_URL at
`lib/ammitto/ontology/schema.rb:10` uses ammitto.org/api/v1; the gem
client points at www.ammitto.com; only ammitto.github.io actually
serves anything). The semantic-layer work must know which context URL
it reconciles to, and IRIs are sticky published identifiers — changing
the base later breaks every consumer holding one. F6 — sanction status
vocabulary: four variants across Ronald's own docs; the shipped code
has a 5-value enum (active/delisted/expired/suspended/pending,
`types.rb:84-90`). Open semantic question: is "terminated" an alias of
delisted or a distinct terminal state? It must be answered before CN
measure-modification handling and the EU status fix land. jp identity —
the jp announcement schema has NO required per-entity id, so the jp
ingestion cannot COMPLETE without ruling how jp entities get identities
(name-slug ids are the proposed design; no precedent in the repo).
Announcement migration — data-uk's stray announcement-format file (D9)
suggests Ronald may be migrating more sources to that format; if so,
announcement support quietly becomes the universal ingestion path and
batch A's surface doubles.

## What to read

- `.codex-context/fork-briefs-2026-07-28.md` — section 4 (F1) and
  section 5 (F6).
- `.codex-context/work-sizing-2026-07-28.md` — cluster A row (the jp
  identity design and the D9 migration signal).
- `.codex-context/ronald-sync-pack-2026-07-28.md` — ready to send to
  Ronald whenever (per the converged ordering).

## What to do

1. You send the sync pack / raise these with Ronald.
2. F1: Ronald rules (his domain; the domain decision is
   discussion-queue item 8). Meanwhile you hold the de-facto option —
   IRIs stay opaque www.ammitto.org identifiers served off github.io —
   and normalize the stray context-path variants under it.
3. F6: you adopt the shipped 5-value enum as baseline (delegate-now
   per the brief); Ronald rules on "terminated". Safe default if he
   stays silent: alias of delisted, recorded as provisional.
4. jp identity: settle the identity scheme (name-slug ids proposed) so
   the jp ingestion can complete.
5. You ask Ronald to confirm whether uk/ch intentionally migrate to
   announcement format.

## What saying yes/no implies

- **F1 de-facto (c):** pick ONE context path, fix the two stray doc
  variants and the .com base; IRIs stay non-dereferenceable (a real
  semantic-web wart) but nothing breaks; options stay open.
  **(a) DNS-backed** needs Ronald's DNS action and makes IRIs
  dereferenceable. **(b) github.io everywhere** rewrites every
  published identifier — breaks existing consumers.
- **F6 alias:** no enum change; CN "stop" actions map to delisted;
  forecloses distinguishing whatever "terminated" means without a data
  migration. **Sixth distinct value:** enum + context + facets + site
  filters each grow a value; additive, existing data unaffected.
- **jp identity yes:** the XL jp ingestion
  (`TODO.phase-3/04-a-jp-ingestion.md`) can complete; no: Japan stays
  a total loss (673 real entities, 0 harvested).
- **Migration confirmed:** the announcement guards
  (`TODO.phase-1/06-announcement-shape-guards.md`) grow into ingestion
  paths for uk/ch too — scope roughly doubles; denied: guards stay
  guards.

## Where

- `.codex-context/fork-briefs-2026-07-28.md` — sections 4 (F1) and
  5 (F6); `.codex-context/work-sizing-2026-07-28.md` — cluster A row;
  `.codex-context/ronald-sync-pack-2026-07-28.md` — the pack to send
- Code anchors the rulings touch:
  `lib/ammitto/ontology/schema.rb:10` (CONTEXT_URL),
  `lib/ammitto/ontology/types.rb:84-90` (the 5-value status enum),
  `schemas/japan/jp-announcement.yml` (no required per-entity id)

## Done when

- The sync pack is sent/answered, or provisional defaults are
  explicitly adopted and recorded.
- Rulings recorded for F1 handling, F6 terminated-semantics, jp
  identity, and the uk/ch migration question.

## Size and dependencies

Decision work — reading plus a conversation with Ronald; calendar
latency is unbounded (Ronald silent since Jul 22 per work sizing).
Blocks: `TODO.phase-4/04-k-semantic-layer.md` (needs F6 + F1),
`TODO.phase-3/04-a-jp-ingestion.md` (HARD completion dep on jp
identity), `TODO.phase-3/05-eu-fictions-fix.md` (needs F6), and the ch
format confirmation feeds `TODO.phase-3/01-f-ch-seco-xml.md`.

## ADHD

- 🔴 3 domains + 3 context paths in play; 4 status vocabularies; jp entities have no id scheme
- 📖 You read: fork-briefs §4+§5, work-sizing cluster A; send the sync pack
- 🔧 You rule/relay: F1 (hold de-facto), F6 (5-value + "terminated"?), jp identity, uk/ch migration intent
- ✅ Rulings or explicit provisional defaults recorded
- ⛓️ Blocks `TODO.phase-4/04-k-semantic-layer.md`, `TODO.phase-3/04-a-jp-ingestion.md`, `TODO.phase-3/05-eu-fictions-fix.md`
- 📦 Conversation; unbounded latency — start it early
