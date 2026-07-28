# A0: announcement-shape detection guards (ch/us/uk)

## Why this matters

Some data repos hold "announcement-format" YAML (the format data-cn
uses: one file per official announcement, several entities inside)
while the gem still parses ch/us/uk input as their legacy per-entity
models. Three defects ride on this drift. G4 — Switzerland:
announcement-format data parsed as a bare `Ch::Identity` comes out nil
and crashes with `NoMethodError 'any?'` at
`sources/ch/sanctions_list.rb:136` (reached via `ch/transformer.rb:77`
from `:23`; dispatch at `harmonize_command.rb:743-755`) — the ch
harvest dies. G5 — US: the same drift is SILENT: an `SdnEntry` parse of
announcement YAML yields one garbage entity `entity/us/unknown` with
`names: []`, exit 0, and it is SERVED — a consumer querying the US
data gets a single nameless entity as the entire OFAC dataset. D9 —
data-uk holds one stray announcement-format file, a signal that more
sources may be migrating to this format. A0 is the converged plan's
split of audit batch A (announcement-schema support): ship loud guards
NOW; real announcement ingestion is the deferred XL half
(`TODO.phase-3/04-a-jp-ingestion.md`).

## What to do

1. Add announcement-shape detection for ch/us/uk input in the
   harmonize dispatch; on detection, fail with a useful error that
   names the announcement format and the offending file. NO ingestion —
   reject loudly.
2. Specs proving the ch and us slices fail with actionable messages
   and non-zero exit on announcement-shaped fixtures.

## Where

- `lib/ammitto/cli/harmonize_command.rb:743-755` — ch dispatch
- `lib/ammitto/cli/harmonize_command.rb:669-679` — us dispatch
- `lib/ammitto/sources/ch/sanctions_list.rb:136` — current crash site
- `lib/ammitto/sources/us/transformer.rb:109-180` — silent-garbage path
- data-uk — the D9 stray announcement-format file

## Done when

- Harmonizing announcement-shaped ch/us/uk input exits non-zero with an
  error naming the format — instead of ch's `NoMethodError` crash and
  us's silently served nameless entity.
- Correct-schema input for those sources is unaffected.

## Size and dependencies

**S-M** — hours up to about a day (the converged ordering calls A0
small). Blocked by nothing. Unblocks:
`TODO.phase-2/04-f-us-restore.md` and
`TODO.phase-3/01-f-ch-seco-xml.md` (both list batch-A guards among
their prerequisites) — the guards protect every restore from silent
garbage. Whether uk/ch intentionally migrate to announcement format is
a question for `TODO.phase-2/09-USER-rulings-f1-f6-jp.md`.

## ADHD

- 🔴 Announcement YAML fed to legacy parsers: ch crashes (G4), us serves 1 nameless garbage entity (G5)
- 🔧 Detect the shape, reject loudly with format+file in the error; NO ingestion yet
- ✅ ch/us announcement fixtures → non-zero exit + actionable message
- ⛓️ Blocks nothing to start; protects `TODO.phase-2/04-f-us-restore.md` + `TODO.phase-3/01-f-ch-seco-xml.md`
- 📦 S-M — hours to ~a day
