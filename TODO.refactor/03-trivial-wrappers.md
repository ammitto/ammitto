# Move the nine identical wrappers through the seam

## Why this matters

Nine of the fifteen transform methods are the same method nine times.
Each one requires a model file, optionally runs the announcement guard,
calls `Model.from_hash(data)`, calls `transformer.transform(...)`, and
returns the serialized pair. The only real knowledge in any of them is
**which model class parses this source's YAML** — one line out of
thirteen. The other twelve lines are copied.

That is why the design doc classes them accretion rather than policy
(L3, ~107 lines): nothing was decided here, the shape just got pasted
fourteen more times because there was nowhere else to put it. Moving
them is the cheapest possible proof that the seam built in `02` actually
carries real sources, and it converts the largest block of duplication
in the file into nine one-line declarations.

This card covers the design doc's Step 2 **and** Step 3 as one task. The
doc split them so `tr` could go through first as a pilot; that ordering
survives *inside* this task — `tr` moves in its own commit before the
other eight — but there is no reason for it to be a separate card, and a
separate card would mean two stack entries with one acceptance criterion
between them.

Two of the nine carry more than a model name and must not be flattened:

- `transform_uk` and `transform_us` call
  `guard_announcement_format!` before parsing, the first statement after
  the model require. That guard is a pipeline invariant (design doc L2,
  PR #28 lineage) — it keeps data-cn schema files off paths that would
  crash or silently emit one nameless entity. It moves with the body, in
  the same position, and the refusal message must not shift by a
  character: `spec/integration/ingestion_robustness_spec.rb` matches on
  it.
- `transform_eu` carries a two-line comment recording that
  parsing EU YAML with `ProcessedEntity` collapsed every EU id and
  dropped names — the reason the code names `Eu::SanctionEntity`
  instead. That is a bug's tombstone. Delete it and the next person
  makes the same choice again. It moves verbatim with the body.

## What to do

1. Move `tr` first, alone, in its own commit
   (`lib/ammitto/cli/harmonize_command.rb` →
   `lib/ammitto/sources/tr/ingestion.rb`). It is the simplest of the
   nine and has a dedicated spec context at
   `spec/ammitto/cli/harmonize_command_spec.rb` that enters through
   `transform_data`, so it exercises the whole dispatch path without
   touching the announcement guard. If anything about the seam is wrong,
   it is cheapest to discover here.
2. Move the remaining eight, one commit each, in this order — guardless
   first, guarded last: `wb`, `ca`, `ru`, `eu_vessels`,
   `un_vessels`, `eu`, `uk`, `us`.
3. Each move is a move, not a rewrite — but it is **not literally
   byte-identical**, and pretending otherwise makes the acceptance
   criterion unfalsifiable. Exactly four substitutions are permitted,
   and **no others**. This list governs `04`–`07` as well:

   | From | To |
   |---|---|
   | `require_relative '../sources/x/y'` | the module's own relative path to the same file |
   | `entity_to_hash(...)` / `entry_to_hash(...)` | `ctx.serialize_entity(...)` / `ctx.serialize_entry(...)` |
   | `guard_announcement_format!(...)` | the `02` module's guard, same arguments |
   | `@exporter.add_group(g, source: :cn)` | `ctx.add_group(g)` (`07` only) |

   The `require_relative` stays **inside the method** and stays lazy —
   it is there for a reason, and `02`'s loads-cleanly spec fails if it
   becomes a top-level require. Everything else — statement order,
   comments, whitespace, the EU model-choice warning — is character for
   character.
4. **Ten commits: nine moves, then one spec commit.** One move-and-wire
   commit per source (delete the method, add the module, add its
   `INGESTERS` entry), in the order set by steps 1 and 2 — and then, once
   all nine have moved, a single additive commit carrying all nine unit
   specs. Mixing new test code into a move commit is what makes copy
   detection unreliable and the move unprovable, so the specs wait.

   An earlier draft of this card said "split each source into two
   commits" and then described this structure, which is not two per
   source but nine plus one. The structure above is the one that holds;
   the per-source pairing was wrong and is withdrawn. There is exactly
   one spec commit because the nine specs share the shared example from
   `02` and reviewing them as one set is the point — nine one-spec
   commits would carry the same content and nine times the ceremony.
5. Delete nothing from `transform_data`'s case yet — each case branch
   becomes a call through the registry, and the whole case goes in `08`.
6. The per-source unit specs are additive only: each asserts the module
   builds the right model class, hands it to the injected transformer as
   the first positional argument, and includes `02`'s opacity shared
   example.
7. Run the full suite after every one of the nine move commits, not once
   at the end, and record the commit SHA and result for each. The point
   of nine commits is that a break is bisectable to a single source, and
   that is only true if each was actually run.

## Where

Bodies to move, all in `lib/ammitto/cli/harmonize_command.rb`:

- `transform_uk` — guarded, `Uk::Designation`
- `transform_eu` — model-choice comment
  `# parsing with ProcessedEntity collapsed every EU id and dropped names`,
  `Eu::SanctionEntity`
- `transform_us` — guarded, `Us::SdnEntry`
- `transform_wb` — `Wb::SanctionedFirm`
- `transform_ca` — `Ca::Record`, comment
  `# Determine if vessel or person/entity`
- `transform_ru` — `Ru::SanctionedEntity`
- `transform_tr` — `Tr::Entity`
- `transform_eu_vessels` — `EuVessels::Vessel`
- `transform_un_vessels` — `UnVessels::Vessel`

Destinations: `lib/ammitto/sources/{tr,wb,ca,ru,eu_vessels,un_vessels,
eu,uk,us}/ingestion.rb`, plus their entries in
`lib/ammitto/ingestion/registry.rb`.

Specs that must stay green untouched:

- `spec/ammitto/cli/harmonize_command_spec.rb` — the tr context
- `spec/integration/ingestion_robustness_spec.rb` — uk/us guard
  refusal and the correct-schema counterparts

## Done when

- `grep -n 'def transform_' lib/ammitto/cli/harmonize_command.rb` lists
  none of the nine, and each named destination file defines its
  ingestion entry point.
- **Each moved body differs from its original only by the four
  substitutions in the table above.** Extract the old body from the base
  revision, apply the four substitutions mechanically, and `diff -u`
  against the new file — the diff must be empty. This replaces
  `git blame -C -C` as the proof: blame's copy detection is a heuristic,
  it is weakened by exactly these substitutions, and a green blame does
  not establish that nothing else changed. Run blame as a sanity check;
  do not rely on it.
- `bundle exec rspec` green at each of the nine move commits, with the
  SHAs and results recorded in the PR body, and no existing spec file
  edited (same diff gate as `02`).
- The uk and us refusal messages are byte-identical. The existing pins
  are regexes (`spec/integration/ingestion_robustness_spec.rb`) and do
  **not** prove byte identity — capture each message before and after
  and compare the full strings, or add an exact-equality golden.
- The EU model-choice comment (`# parsing with ProcessedEntity collapsed
  every EU id and dropped names`) is present in
  `lib/ammitto/sources/eu/ingestion.rb`; prove it by diffing against the
  extracted original, not by reading it.
- Normalized full-tree export diff against the Step 0 baseline is empty,
  using the commands `00-golden-baseline.md` defines. **BLOCKED**, not
  passing, if the baseline or the pinned data-repo snapshots are absent.

## Size and dependencies

**L** — about two days, at the low end of the L band. The old **M**
priced this as "nine mechanical moves" and it is not that.

The arithmetic, and one thing it explicitly is *not*:

- **Not the suite.** The full suite is **1,458 examples in 4.1s wall**
  (measured at `0f8afc6`, 2026-08-11). Nine runs is under a minute. Any
  estimate that treats "run the suite nine times" as a cost driver is
  wrong; `00-golden-baseline.md` step 8 records the measurement so no
  card repeats the mistake.
- **Nine substitution proofs.** Each move owes an extract, a mechanical
  application of the four-substitution table, and an empty `diff -u`
  against the new file. That is the acceptance criterion, it is per
  source, and it is where the hours are — roughly an hour each once the
  extraction is scripted, considerably more for the first two while it
  is not.
- **Nine unit specs**, plus wiring `02`'s opacity shared example into
  each — half a day for the set.
- **Two byte-equality captures** for the uk and us refusal messages,
  which the existing regex pins do not establish.
- **One normalized full-tree export diff** against the Step 0 baseline,
  at the end of the card. That is a corpus-scale run, not a suite run,
  and it is the single largest wall-clock item here.

The remaining risk is not schedule, it is discipline: resisting the urge
to collapse the duplication while it is all visible at once.

That urge is the trap this card exists to name: after the move, the nine
modules are nine copies of one body with one line different, and
collapsing them is obviously right. **It is Track B work.** A commit that
moves and collapses in one step destroys the tree diff's meaning — see
`README.md`, "The two tracks". Take the note to
`10-REFINE-naming-and-readability.md` and keep moving.

Blocked by `02-ingestion-scaffolding.md`. Blocks `08-delete-the-case.md`
(the case cannot go while nine branches still need it). Independent of
`04`–`07`, which touch different sources, though the stack keeps them
sequential.

## ADHD

- 🔴 Nine transform methods are one method pasted nine times; only the model class differs
- 🧨 Source #16 means a tenth copy, and the uk/us guard is easy to drop in a hasty move
- 🔧 Cut-paste each body to `sources/{code}/ingestion.rb`, tr first; only 4 substitutions allowed (require path, `entity_to_hash`→`ctx`, guard, `add_group`) — that table governs 04–07 too
- ✅ Ten commits (nine moves + one spec commit), SHAs recorded, extract+substitute+`diff -u` empty, guard messages byte-equal, empty tree diff
- ⛓️ Blocked by 02; blocks 08
- 📦 L — ~2 days; the nine substitution proofs are the cost, NOT the suite (4.1s); do NOT collapse the duplication here, that is task 10
