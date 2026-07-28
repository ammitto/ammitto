# TODO task board

Task files for the finalization plan (phases 1-4 + deferred).
Convention: one PR completes a task AND deletes its file in the same
change, so `ls TODO.phase-*` is the live status and the git log of
deletions is the completion history. Tasks whose filename carries a
`USER` prefix need a maintainer action or ruling, not code.

This README documents the board and the template — it is not a task
card and does not itself follow the template sections.

## Sources of truth

Every fact in these files traces to the 2026-07-28 audit artifacts in
the local `.codex-context/` directory:

- `harvest-audit-catalog-2026-07-28.md` — gem defects G1-G26, data
  defects D1-D13, the per-source truth table, batch groupings A-K
- `fetch-diagnosis-2026-07-28.md` — the four fetch-layer mechanisms +
  per-source fetch states
- `work-sizing-2026-07-28.md` — the S/M/L/XL sizes and dependencies
- `fork-briefs-2026-07-28.md` — the F1-F9 ruling briefs
- `gap-matrix-2026-07-28.md` — the 646-row requirements-vs-reality
  audit (R-### rows)
- `converged-ordering-2026-07-28.md` — the week-by-week execution
  shape

## File template

Every task file is Markdown (`#`/`##` headers, `-` bullets, backticked
`file/paths.rb:123`, fenced blocks for commands) with exactly these
sections:

- `# Title` — titles are kept from the original board and may carry
  the audit's short codes (G#, D#, F#, batch letters); each such code
  is explained in the first body sentences that use it.
- `## Why this matters` — what is broken or missing, the real-world
  consequence (what a consumer of the sanctions data sees wrong), and
  how it was discovered. Every defect reference (G#, D#, F#, batch
  letters, R-###) is explained inline at its first body use — never a
  bare code in prose.
- `## What to do` — concrete numbered steps a developer can follow,
  naming files with paths and line numbers where known.
- `## Where` — the file:line list.
- `## Done when` — acceptance criteria as testable statements
  ("running X produces Y").
- `## Size and dependencies` — S (a few hours) / M (about a day) /
  L (2-4 days) / XL (a week or more), plus what blocks the task and
  what it unblocks — naming task files, not codes.
- `## ADHD` — 4-6 ultra-compressed emoji bullets: 🔴 what's broken /
  🔧 the fix / ✅ done-when / ⛓️ blocked-by / 📦 size.

USER-prefixed files address the maintainer directly ("You rule…",
"You approve…"), add a `## What to read` section listing exactly the
brief(s) to read, and a `## What saying yes/no implies` section
spelling out the consequences of each ruling.
