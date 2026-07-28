# Nonzero exit on fetch source failure

## Why this matters

`ammitto fetch` reports success and exits 0 even when a source fails.
Runtime-verified during the 2026-07-28 fetch diagnosis:
`bundle exec exe/ammitto fetch cn` prints "Fetch complete: 0 succeeded,
1 failed" and exits **0**. In CI this let data-eu (2026-06-30) and
data-us (2026-05-11) runs log `ERROR: String namespace URIs are not
supported` and still conclude `success`. The consequence for consumers:
repos went dark behind green checkmarks — per the diagnosis, Canada and
the UN spent weeks (03-01 to 05-11, the observed run windows)
downloading thousands of sanctions records per day and discarding them
while every run reported success, so the published data silently went
stale with no alarm. The diagnosis calls this the fetch layer's worst
failure mode: its worst failure "isn't an error; it's a success report".

Scope note: invalid arguments already raise `Thor::Error` and exit
non-zero — the hole is per-SOURCE failures. A related documented gap: a
source that saves 0 files counts as SUCCEEDED (`fetch jp` locally:
"Saved 0 files" then "1 succeeded", exit 0) — there is no minimum-yield
gate.

## What to do

1. In `lib/ammitto/cli/fetch_command.rb`, the per-source rescue at line
   123 catches `StandardError` and collects an `error_result`;
   `print_summary` (line 396) prints the failed-source list and falls
   off the method end without ever setting an exit status. Set a
   non-zero exit when any requested source's result is an error.
2. Keep invalid-argument behavior unchanged (`Thor::Error` already
   exits non-zero).
3. Add specs: a failing source exits non-zero; a run with only passing
   sources still exits 0.
4. Decide with the lead whether to also close the zero-files-saved gap
   (no minimum-yield gate) here or as a follow-up — the diagnosis
   records it as a related gap of the same mechanism.

## Where

- `lib/ammitto/cli/fetch_command.rb:123` — per-source StandardError rescue
- `lib/ammitto/cli/fetch_command.rb:396` — `print_summary`, no exit status set

## Done when

- Running

  ```bash
  bundle exec exe/ammitto fetch cn
  ```

  (the hard-blocked source) exits non-zero — today it prints
  "0 succeeded, 1 failed" and exits 0.
- A fetch of only healthy sources still exits 0.
- A data-repo CI run whose source fails turns red instead of logging the
  error and concluding `success`.

## Size and dependencies

**S** — a few hours. Blocked by nothing. Unblocks
`TODO.phase-1/14-USER-canary-dispatches.md`: canary runs are only
trustworthy once failures turn the run red. Together with
`TODO.phase-1/02-data-repo-gitignore-alignment.md` this is one of the
two cross-cutting fixes behind the dark repos (they do not by themselves
fix dependency conflicts, dead schedules, or stub extractors).

## ADHD

- 🔴 `fetch` exits 0 while sources fail — "0 succeeded, 1 failed" still = green CI
- 🧨 Weeks of sanctions data silently lost behind success reports (ca, un)
- 🔧 Set non-zero exit from the collected per-source error results (`fetch_command.rb:123`, `:396`)
- ✅ `fetch cn` exits non-zero; healthy-only runs still exit 0
- ⛓️ Blocks canary dispatches (`TODO.phase-1/14-USER-canary-dispatches.md`)
- 📦 S — hours
