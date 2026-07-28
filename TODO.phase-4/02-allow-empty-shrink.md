# Shrink --allow-empty strictly from verified evidence

## Why this matters

`--allow-empty` exempts listed sources from failing when they produce
no output. While repos were broken that exemption was load-bearing —
the work-sizing band notes that without fetch restoration, us/un/ca
"stay --allow-empty exempted". Every entry on the list is a source
allowed to silently serve nothing; after the restores land, each
leftover exemption is a hole in the health gates. Consumer impact: an
exempted source that breaks again disappears from the data without any
red run. The converged ordering's week-4 line is the rule: "shrink
--allow-empty strictly from verified evidence".

## What to do

1. After the full harvest (`TODO.phase-4/01-full-harvest.md`), go
   through the `--allow-empty` list source by source.
2. Remove every source whose repo now demonstrably has data.
3. Keep only sources with proven-empty repos — verified evidence, not
   assumption.
4. Confirm the interaction with the hardened health gates
   (`TODO.phase-1/09-health-gate-hardening.md` flagged the
   `--allow-empty` interaction as part of its design).

## Where

- The `--allow-empty` source list consumed by the harmonize health
  gates (gem side; see `TODO.phase-1/09-health-gate-hardening.md` for
  the gate code at `harmonize_command.rb:131-157`).

## Done when

- The list contains only sources with proven-empty repos.
- A restored source that goes empty again turns the run red instead of
  passing silently.

## Size and dependencies

**S** — hours. Blocked by: `TODO.phase-4/01-full-harvest.md` (the
evidence) and the TODO.phase-2/TODO.phase-3 restore cards that produce it. Related:
`TODO.phase-1/09-health-gate-hardening.md`.

## ADHD

- 🔴 Every --allow-empty exemption = a source allowed to vanish silently
- 🔧 After full harvest: strike every source that now has data; evidence only
- ✅ List == proven-empty repos only; restored source going empty → red run
- ⛓️ Needs `TODO.phase-4/01-full-harvest.md`
- 📦 S — hours
