# B: replace from_yaml(data.to_yaml) round-trips (G3)

## Why this matters

G3 / audit batch B — harmonize re-parses already-loaded YAML data by
dumping it back to YAML and re-reading it (`X.from_yaml(data.to_yaml)`).
The re-dump re-emits YAML anchors into a loader that has aliases
disabled (lutaml `standard_adapter.rb:22`), raising
`Psych::AliasesNotEnabled`. Today this kills 15 of Japan's 101 input
files; the other 13 sources are latently exposed — cn alone is immune
because it already uses `from_hash`. Consumer impact: any source file
that happens to contain YAML anchors silently drops its entities from
the published data. Found by the 2026-07-28 harvest audit against real
data.

## What to do

1. Replace the 19 `from_yaml(data.to_yaml)` sites in
   `lib/ammitto/cli/harmonize_command.rb` (spread over lines 607-914)
   and the 3 in `lib/ammitto/sources/au/transformer.rb`
   `transform_from_hash` (lines 128-133) with `from_hash` — the pattern
   cn already uses (`harmonize_command.rb:781`).
2. Regression-check per source with real data — this is the dominant
   cost: Date/Time coercion behaves differently across the two paths.
3. Add a spec with an anchored-YAML fixture exercised on every source
   path.

## Where

- `lib/ammitto/cli/harmonize_command.rb:607-914` — 19 round-trip sites
  (cn's `from_hash` reference at `:781`)
- `lib/ammitto/sources/au/transformer.rb:128-133` — 3 more sites

## Done when

- An anchored-YAML fixture harmonizes cleanly on every source path
  (no `Psych::AliasesNotEnabled`).
- Per-source outputs are unchanged by the switch (Date/Time coercion
  regression checked against real data).

## Size and dependencies

**M** — about a day (the edit is mechanical; the per-source coercion
regression dominates). Blocked by nothing; its verification overlaps
the jp re-harvest done in `TODO.phase-3/04-a-jp-ingestion.md` (the 15
crashing jp files are the same defect's visible half).

## ADHD

- 🔴 `from_yaml(data.to_yaml)` re-emits anchors into an aliases-off loader → `Psych::AliasesNotEnabled`
- 🧨 15/101 jp files crash now; 13 more sources latently exposed
- 🔧 `from_hash` everywhere (cn's pattern): 19 sites in `harmonize_command.rb:607-914` + 3 in `au/transformer.rb:128-133`
- ✅ Anchored fixture passes on every source path; coercion regression checked per source
- ⛓️ Nothing blocks it; verify alongside `TODO.phase-3/04-a-jp-ingestion.md`
- 📦 M — ~1 day (coercion regression is the cost)
