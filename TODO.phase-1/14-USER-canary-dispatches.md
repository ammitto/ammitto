# USER: canary fetch dispatches (ch/uk -> ca/un/eu -> us)

## Why this matters

Six data-repo crons are dead while showing `state: active`:
ca/cn/ru/un/us last ran on schedule 2026-05-11 and eu on 2026-06-30;
none has fired since, though the workflows have valid cron lines at
HEAD. Best-fit cause (the diagnosis marks it inferred, not proven):
GitHub's 60-day-inactivity auto-disable reacting to the very commit
silence the gitignore discard created. Whatever the cause, the
diagnosis's operational conclusion stands: these six schedules have
not resumed on their own and cannot currently be relied on. Reviving
them takes remote actions only you can approve: a
`workflow_dispatch` is the cheap test; a disable/enable cycle is the
likely fix. The converged plan's rule (Codex's addition): every
restored cron is an ACCEPTANCE TEST — non-zero failure + tracked-output
assertion + seed commit + inactivity monitoring — never a bare schedule
flip. Consumer impact until then: Canada, UN, EU, US data cannot come
back.

## What to read

- `.codex-context/fetch-diagnosis-2026-07-28.md` — mechanisms 2 and 3
  plus the per-source table rows for ca/un/eu/us/ch/uk.
- `.codex-context/converged-ordering-2026-07-28.md` — week 1 (canary
  order and the acceptance-test rule).

## What to do

1. You authorize data-repo writes and seed commits — the gitignore PRs
   (`TODO.phase-1/02-data-repo-gitignore-alignment.md`) and each
   repo's first tracked `processed/` corpus need them.
2. You approve each canary dispatch individually (remote actions,
   per-action approval), in the converged order:
   **ch/uk first, then ca/un/eu, then us.**
3. Per canary: dispatch the workflow, verify the run produces tracked,
   reviewable output commits, and only then re-enable the cron.
4. us goes last and supervised: its ZIP download/extraction path has
   never executed anywhere.

## What saying yes/no implies

- Approving a dispatch runs a real fetch against a government source
  and (once gitignores are aligned) commits sanctions data to the repo.
- Declining leaves that source frozen: uk/ch since 07-25, eu at its
  2026-05-01 data, ca/un/us since 05-11.

## Where

- `fetch.yml` in data-ch, data-uk, data-ca, data-un, data-eu, data-us
  (the six repos whose schedules are dead or dep-blocked)

## Done when

- Each of the six canary targets — ch, uk, ca, un, eu, us — has
  produced a canary run with tracked, committed output, and its cron
  was re-enabled ONLY after those tracked changes appeared. (cn and
  ru are also dead-cron members but are not canary targets: cn is
  manual by design, ru's workflow is a stub —
  `TODO.phase-3/02-f-ru-scraper.md`.)

## Size and dependencies

Minutes per approval; calendar time is run-bound. Blocked by:
`TODO.phase-1/01-fetch-exit-honesty.md` (otherwise a canary can fail
green), `TODO.phase-1/02-data-repo-gitignore-alignment.md` (otherwise
output is discarded), `TODO.phase-1/03-ch-uk-json-schema-dep.md` (ch/uk
cannot even bundle). Unblocks: all four phase-2 restores
(`TODO.phase-2/01-f-ca-restore.md`,
`TODO.phase-2/02-f-un-restore.md`, `TODO.phase-2/03-f-eu-refresh.md`,
`TODO.phase-2/04-f-us-restore.md`).

## ADHD

- 🔴 Six crons dead-but-"active" since 05-11/06-30 — haven't resumed, can't be relied on
- 🔧 You approve: write auth + each dispatch (ch/uk → ca/un/eu → us), per-action
- 🧪 Every cron re-enable = acceptance test: red-on-failure + tracked output + seed commit + monitoring
- ✅ ch/uk/ca/un/eu/us canaries with committed output; crons re-enabled only after
- ⛓️ Needs `TODO.phase-1/01-fetch-exit-honesty.md` + `TODO.phase-1/02-data-repo-gitignore-alignment.md` + `TODO.phase-1/03-ch-uk-json-schema-dep.md` first
- 📦 Minutes per approval; run-time bound
