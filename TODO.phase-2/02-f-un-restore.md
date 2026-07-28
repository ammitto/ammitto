# F-un: restore UN data path (1009 files fetched 05-11, discarded)

## Why this matters

D5 — data-un has no input files. The 2026-05-11 run logged "Saved 1009
files to processed" and then `has_changes=false`: everything the fetch
produced was discarded by the gitignore, and the cron has been dead
since. `downloaded/un-data.xml` is a 0-byte tombstone from the legacy
cron (2.2MB on 2025-06-19, zeroed by the legacy cron's final run on
2025-06-20 — it predates the current pipeline and was never touched
since). The upstream is alive: consolidated.xml 302-redirects to an
Azure blob (a HEAD 404 is a gateway artifact; the extractor uses
open-uri, which follows redirects — the 05-11 run proves the full path
worked). Caveats: `sources/un` changed on main since (PRs #12/#16,
07-22) with no spec on the un parse, and the 421-line UN transformer
has NEVER been exercised (audit: quality UNKNOWN). Consumer impact: UN
Security Council designations are entirely absent from the published
data.

## What to do

1. After gitignore alignment and canary approval
   (`TODO.phase-1/02-data-repo-gitignore-alignment.md`,
   `TODO.phase-1/14-USER-canary-dispatches.md`): dispatch a fetch and
   watch the first run — it verifies current-main un parsing.
2. Seed-commit the fetched `processed/` corpus.
3. Delete the 0-byte `downloaded/un-data.xml` tombstone (diagnosis
   recommendation).
4. Run `harmonize un` — first-ever exercise of the 421-line UN
   transformer with its heuristic individual/entity dispatch
   (`harmonize_command.rb:638-657`); fix first-run correctness issues;
   verify the full output.

## Where

- data-un repo: `.gitignore`, `processed/` (empty),
  `downloaded/un-data.xml` (0-byte tombstone)
- `lib/ammitto/cli/harmonize_command.rb:638-657` — heuristic
  individual/entity dispatch
- `lib/ammitto/sources/un/` — 421-line transformer, never exercised

## Done when

- Fresh `processed/` corpus committed in data-un.
- `harmonize un` yields non-zero real entities passing the hardened
  gates; output verified.
- The tombstone file is gone.

## Size and dependencies

**L** — 2-4 days per work sizing (the cron flip itself is S per the
diagnosis; the first-ever exercise of the UN transformer carries the
multi-day first-run-correctness allowance). Blocked by:
`TODO.phase-1/02-data-repo-gitignore-alignment.md`,
`TODO.phase-1/14-USER-canary-dispatches.md`. Unblocks:
`TODO.phase-4/01-full-harvest.md`.

## ADHD

- 🔴 UN: 1009 files fetched daily, all discarded; repo has zero inputs (D5)
- 🧨 UN Security Council list absent from published data
- 🔧 Canary → seed commit → delete 0-byte tombstone → first-ever `harmonize un`
- ✅ processed/ committed; harmonize un real entities through gates
- ⛓️ Needs `TODO.phase-1/02-data-repo-gitignore-alignment.md` + `TODO.phase-1/14-USER-canary-dispatches.md`
- 📦 L — 2-4 days (never-exercised 421-line transformer)
