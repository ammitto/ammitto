# Fix json-schema 4-vs-5 bundler conflict (ch/uk fetch)

## Why this matters

Since 2026-07-25 the Switzerland and UK fetch workflows fail daily at
"Set up Ruby": the gem's gemspec pins `json-schema ~> 4.0` (added in
PR #16 on 07-22, dropped in the #12 rebase churn, restored in commit
8260fdd) while data-ch and data-uk — only those two — pin
`json-schema ~> 5.0` in their Gemfiles. `bundle lock` exits 6. Run logs
(data-ch 30349931201, data-uk 30343326440): "Because every version of
ammitto depends on json-schema ~> 4.0 … Gemfile depends on json-schema
~> 5.0". The timeline matches the gemspec churn exactly (uk also failed
07-22, was green 07-23/24 while the dep was briefly absent). Consumer
impact: the UK list, which commits real entity churn when green (07-24:
15 files, afg/aqd/inu entities), has been frozen since 07-25 — consumers
see out-of-date UK designations. Both repos accumulate auto-filed
failure issues (ch 8 open, uk 11).

## What to do

1. One-line fix, either side, per the fetch diagnosis: relax the
   gemspec to `json-schema >= 4, < 6`, or drop the `~> 5.0` pin from
   the data-ch/data-uk Gemfiles. (Data-repo Gemfile changes need write
   authorization; the gemspec change is local to this repo.)
2. For ch, note only `_index.yaml` is tracked (the gitignore discard —
   its green 07-21..24 runs saved 600+ files that never committed), so
   pair with `TODO.phase-1/02-data-repo-gitignore-alignment.md` plus a
   seed commit for `processed/`.
3. Verify with a ch/uk canary fetch
   (`TODO.phase-1/14-USER-canary-dispatches.md` — ch/uk are first in
   the canary order).

## Where

- `ammitto.gemspec` — the `json-schema ~> 4.0` dependency
- `Gemfile` in data-ch and data-uk — the `json-schema ~> 5.0` pins

## Done when

- `bundle lock` resolves in both data repos' workflows (no exit 6).
- A ch/uk canary fetch runs green.
- data-uk resumes committing real entity churn.

## Size and dependencies

**S** — hours. Blocked by nothing on the gemspec side; the data-repo
side needs write authorization
(`TODO.phase-1/14-USER-canary-dispatches.md`). Unblocks: the ch/uk
canaries (first in the canary order) and, for freshness later,
`TODO.phase-3/01-f-ch-seco-xml.md`.

## ADHD

- 🔴 ch + uk fetch dead since 07-25: gemspec `~> 4.0` vs repo Gemfiles `~> 5.0`
- 🧨 UK designations frozen; 19 auto-filed failure issues piling up
- 🔧 One line: gemspec `>= 4, < 6` OR drop the repo pins
- ✅ `bundle lock` resolves; ch/uk canary green; uk commits churn again
- ⛓️ Data-repo side needs write auth (`TODO.phase-1/14-USER-canary-dispatches.md`)
- 📦 S — hours
