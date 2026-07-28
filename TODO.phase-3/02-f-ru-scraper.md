# F-ru: wire + test the mid.ru scraper in CI (never run)

## Why this matters

D8 — data-ru has no input files and its committed `api/` contradicts
itself: stats claim 1,995 entities while the graph holds 4. The fetch
workflow step is a stub: `echo "RU source not yet implemented"`
followed by a bare `ammitto` call (not `bundle exec`) that dies with
`command not found` — swallowed by `|| true` (observed in the 05-11
run log). Meanwhile the gem carries a real 278-line Mechanize scraper
for mid.ru (upstream answers HEAD 200) that has NEVER run in CI, and a
parse-script route exists too: `scripts/parse_ru_sanctions_list.rb`
over the reference-docs markdown. The ru transformer (219 lines) has
never been exercised. Consumer impact: Russia's MID list is absent,
and the committed api actively misleads anyone who reads its stats.

## What to do

1. Fix the workflow: real `bundle exec` invocation instead of the
   echo-stub with `|| true`.
2. Produce a corpus by one (or both) of the documented routes: test
   the 278-line Mechanize scraper end-to-end, and/or run
   `scripts/parse_ru_sanctions_list.rb` on the reference-docs
   markdown.
3. First exercise of the 219-line ru transformer — note it has no
   schema guard beyond model loading (`harmonize_command.rb:823-826`).
4. Diagnose the stats-1995-vs-graph-4 contradiction in the committed
   api; regenerate. This is diagnostic work, not a rerun (work
   sizing's phrasing).
5. Seed-commit the corpus (write authorization required).

## Where

- data-ru repo: fetch.yml (echo-stub + `|| true`), empty inputs,
  self-contradictory `api/`
- Gem: the 278-line mid.ru Mechanize scraper;
  `scripts/parse_ru_sanctions_list.rb`
- `lib/ammitto/cli/harmonize_command.rb:823-826` — ru dispatch, no
  schema guard beyond model loading

## Done when

- ru fetch (or the parse script) produces a tracked, committed corpus.
- `harmonize ru` yields non-zero real entities through the gates.
- The 1995-vs-4 contradiction is explained and gone from regenerated
  api.

## Size and dependencies

**L** — 2-4 days, med-low confidence (diagnostic first-exercise work).
Blocked by: data-repo write authorization
(`TODO.phase-1/14-USER-canary-dispatches.md`). Unblocks:
`TODO.phase-4/01-full-harvest.md`.

## ADHD

- 🔴 ru workflow = echo-stub + `|| true`; scraper never ran; api says 1,995 but holds 4 (D8)
- 🧨 Russia MID list absent; committed stats lie
- 🔧 `bundle exec` wiring → scraper and/or parse script → first-ever transformer run → diagnose 1995-vs-4
- ✅ Tracked corpus committed; harmonize ru real entities; contradiction resolved
- ⛓️ Needs write auth (`TODO.phase-1/14-USER-canary-dispatches.md`)
- 📦 L — 2-4 days, diagnostic
