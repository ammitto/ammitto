# Align data-repo gitignores with fetch output

## Why this matters

Every data repo's `fetch.yml` runs `ammitto fetch <src> --output-dir
processed`, but 14 of the 15 repos gitignore that very directory
(`processed/*` + `!processed/.gitkeep` — every repo except data-cn).
Gitignore does not untrack existing files, so repos with a previously
force-added corpus (au, eu, nz, tr, uk, wb, eu-vessels; ch's `_index`
only) keep committing updates to those exact files — which hid the bug.
It bites two ways. (a) Where nothing was ever tracked — ca, un,
un-vessels post-merge — the fetch "succeeds", writes hundreds of files,
`git status --porcelain` sees nothing, and the run commits nothing.
Proven in the 2026-07-28 fetch diagnosis: data-un's 2026-05-11 run
logged "Saved 1009 files to processed" then `has_changes=false`;
data-ca the same day saved 500+ files and committed nothing. (b) Even
in "working" repos, any NEW file — a newly designated entity's YAML —
is ignored and never committed (a latent listing-lag defect; code-read
consequence, not yet observed in a diff). Consumer impact: a person
newly added to a sanctions list can never appear in the published data
even while daily runs stay green.

## What to do

1. For each affected data repo, prepare a PR aligning `.gitignore` with
   the pipeline's output dir (stop ignoring `processed/`).
2. Where the corpus was never tracked (ca, un, un-vessels), plan a seed
   commit tracking `processed/` with the first successful run.
3. Data-repo pushes are remote writes — the maintainer authorizes them
   (see `TODO.phase-1/14-USER-canary-dispatches.md`).
4. Verify via a canary run that fetch output actually commits.

## Where

- `.gitignore` in each of the 14 affected `data-{source}` repos
  (all except data-cn): the `processed/*` + `!processed/.gitkeep` pair.

## Done when

- A canary fetch in a previously-dark repo (data-ca or data-un)
  produces a commit containing the fetched `processed/` files.
- A new file appearing in a "working" repo's fetch output gets
  committed instead of silently ignored.

## Size and dependencies

**S per repo** — hours each, mechanical. Blocked by: maintainer write
authorization (`TODO.phase-1/14-USER-canary-dispatches.md`). Unblocks:
the canary dispatches themselves and all four phase-2 restores
(`TODO.phase-2/01-f-ca-restore.md`, `TODO.phase-2/02-f-un-restore.md`,
`TODO.phase-2/03-f-eu-refresh.md`, `TODO.phase-2/04-f-us-restore.md`).
The second of the two cross-cutting fixes behind the dark repos (with
`TODO.phase-1/01-fetch-exit-honesty.md`).

## ADHD

- 🔴 14/15 data repos gitignore the fetch output dir — fetched data discarded
- 🧨 data-un: "Saved 1009 files" → `has_changes=false`; new designations never commit
- 🔧 PR per repo: unignore `processed/`; seed commit where nothing was tracked
- ✅ Canary run commits fetched files
- ⛓️ Needs write auth (`TODO.phase-1/14-USER-canary-dispatches.md`)
- 📦 S per repo — mechanical
