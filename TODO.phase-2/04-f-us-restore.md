# F-us: restore US OFAC (ZIP path never executed anywhere; supervised run)

## Why this matters

D3 — data-us holds ONE sample file, and `downloaded/us-govt-data.xml`
is a 0-byte legacy tombstone (~950KB on 2024-02-24, zeroed by the
legacy cron's final write on 2024-05-04). The 2026-05-11 run hit the
silent namespace crash ("0 succeeded, 1 failed", exit 0) and the cron
has been dead since. The crash cause is removed on main
(`sources/us/sdn_namespace.rb`, class-load-verified in the diagnosis),
but the ZIP download/extraction path and a real `SdnList` parse have
never been executed ANYWHERE — recovery is not yet established, only
the specific May crash's cause is gone. The upstream is healthy:
SDN_ADVANCED.ZIP 302-redirects to presigned S3 (published 2026-07-24).
Meanwhile what the pipeline serves for the US is one garbage entity —
G5, the silent announcement-schema drift: `entity/us/unknown` with
`names: []`, exit 0, SERVED. Consumer impact: the largest sanctions
list in the program (~18k entities in historic claims) is absent,
replaced by a single nameless entity.

## What to do

1. Land the phase-1 guards first — work sizing orders "A, C, D first":
   `TODO.phase-1/06-announcement-shape-guards.md`,
   `TODO.phase-1/08-iri-nil-raise.md`,
   `TODO.phase-1/09-health-gate-hardening.md` — so a bad parse cannot
   silently serve garbage again.
2. Supervised canary dispatch, LAST in the canary order
   (`TODO.phase-1/14-USER-canary-dispatches.md`): the ZIP path runs
   for the first time anywhere.
3. Seed-commit the fetched corpus
   (`TODO.phase-1/02-data-repo-gitignore-alignment.md` first).
4. First exercise of the correct-schema path: the dispatch has so far
   materialized one `SdnEntry` into the 405-line us transformer
   (`harmonize_command.rb:669`); expect schema variance, runtime,
   dedupe, and artifact-integrity work at ~18k entities — a multi-day
   allowance, not an op.
5. Verify counts and quality against the gates; delete the 0-byte
   tombstone.

## Where

- data-us repo: 1 sample file in `processed/`,
  `downloaded/us-govt-data.xml` (0-byte tombstone)
- `lib/ammitto/sources/us/sdn_namespace.rb` — crash fix (class-load
  verified only)
- `lib/ammitto/cli/harmonize_command.rb:669-679` — us dispatch
- `lib/ammitto/sources/us/transformer.rb` — 405-line transformer,
  correct-schema path never exercised

## Done when

- The SDN corpus lands committed in data-us.
- `harmonize us` produces entities at the ~18k order with real names,
  passing the hardened gates — not one `entity/us/unknown`.
- The tombstone is gone; the cron is re-enabled after tracked changes.

## Size and dependencies

**L** — 2-4 days per work sizing ("multi-day allowance, not an op";
the fetch-side flip alone is M per the diagnosis). Blocked by:
`TODO.phase-1/06-announcement-shape-guards.md`,
`TODO.phase-1/08-iri-nil-raise.md`,
`TODO.phase-1/09-health-gate-hardening.md`,
`TODO.phase-1/02-data-repo-gitignore-alignment.md`,
`TODO.phase-1/14-USER-canary-dispatches.md`. Unblocks:
`TODO.phase-4/01-full-harvest.md` and any honest 15/15 claim.

## ADHD

- 🔴 US = 1 nameless garbage entity SERVED; real corpus absent, ZIP path never run anywhere (D3, G5)
- 🧨 The biggest list (~18k entities) missing from published data
- 🔧 Guards first → supervised canary (last) → seed commit → first ~18k-entity run through the 405-line transformer
- ✅ Real-name entities at ~18k order through gates; no `entity/us/unknown`
- ⛓️ Needs `TODO.phase-1/06-announcement-shape-guards.md` + `TODO.phase-1/08-iri-nil-raise.md` + `TODO.phase-1/09-health-gate-hardening.md` + `TODO.phase-1/02-data-repo-gitignore-alignment.md` + `TODO.phase-1/14-USER-canary-dispatches.md`
- 📦 L — 2-4 days
