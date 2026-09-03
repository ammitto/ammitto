# Move the three shape-sniffing dispatchers: nz, un, au

## Why this matters

Three sources cannot name a single model class, because their YAML holds
more than one record shape and the command has to decide which. That
decision is real knowledge about the source's format — and it is the
knowledge most obviously misfiled in a generic CLI command. Today the
harmonize command knows that a UN record with a `fourth_name` key is a
person and one without is an organization. Nothing about that belongs to
a command.

Each of the three sniffs differently, and the differences are the
evidence that these are three separate facts about three separate
sources rather than one missing abstraction:

- **nz** — `transform_nz` reads the YAML's own `type` field —
  `'Individual'` / `'Ship'` / everything else. The source publishes a
  discriminator and only the CLI reads it (design doc L9).
- **un** — `transform_un` has no discriminator at all, so it sniffs six
  person-only keys: `gender`, `date_of_birth`, `place_of_birth`,
  `documents`, `nationalities`, `fourth_name` (L4). It is also the only
  one of the three that calls a *different transformer method* per
  branch — `transform_individual` versus `transform_entity` — rather than
  a single `transform`.
- **au** — `transform_au` sniffs `imo_number` → vessel, `dates_of_birth` →
  individual, else organization (L5).

**au carries a trap and this task must not spring it.** A second,
independent dispatcher exists in
`lib/ammitto/sources/au/transformer.rb` —
`Au::Transformer#transform_from_hash` — and its criteria are *not* the
same. The command tests `imo_number` first; the transformer tests
person-shaped keys first and accepts a wider set (`type`,
`birth_info`, `person_details`, `vessel_details`). A record carrying both
`imo_number` and `dates_of_birth` resolves to a Vessel through the
command and to an Individual through the transformer. Both are pinned
independently — the command path through
`describe 'from_hash/from_yaml model equivalence'` in
`spec/integration/ingestion_robustness_spec.rb`, and `transform_from_hash`
directly under `describe 'Au::Transformer#transform_from_hash'`, whose own
comment records that external callers reach it without going through the
command.

Unifying them is design decision **D2 in the design doc, explicitly
deferred**: it needs an equivalence proof over two differing criteria,
and it is a behaviour change wearing a cleanup's clothes. This task
copies the command's criteria **verbatim** and leaves
`transform_from_hash` alone.

## What to do

1. Move `transform_nz` first, to
   `lib/ammitto/sources/nz/ingestion.rb`. It is the simplest: a
   three-way `case` on `data['type']` with `Nz::Entity` as the else
   branch. Preserve the else branch — an unknown `type` string must keep
   producing an Entity, not an error.
2. Move `transform_un` to `lib/ammitto/sources/un/ingestion.rb`. Keep
   the six-key sniff in its current order and keep **both** transformer
   entry points: the individual branch calls `transform_individual`, the
   entity branch calls `transform_entity`. Collapsing those to one
   `transform` call is the un half of D2 and is not this PR. Move the
   two explanatory comments above the sniff — the one naming the
   person-specific fields and the one about UN's snake_case YAML — with
   the body.
3. Move `transform_au` to `lib/ammitto/sources/au/ingestion.rb` using
   the **command's** criteria character for character, including the
   "Detect record type" comment above the dispatch. Do not consult,
   reuse, or delegate to `Au::Transformer#transform_from_hash`. Do not
   edit it. Do not add a TODO to it — `11`/`13` carry the follow-up.
4. Register all three in `INGESTERS` in the commit that moves each.
5. Add per-source ingestion unit specs (additive). For au, add one
   example that pins the divergence explicitly: a record with both
   `imo_number` and `dates_of_birth` resolves to `Au::Vessel` through
   ingestion. That freezes today's behaviour so D2 later has something
   to argue against instead of a guess.
6. Full suite after each of the three commits.

## Where

- `lib/ammitto/cli/harmonize_command.rb` — `transform_un`, its six-key
  sniff and its dual transformer entry points (`transform_individual`,
  `transform_entity`)
- `lib/ammitto/cli/harmonize_command.rb` — `transform_au`
- `lib/ammitto/cli/harmonize_command.rb` — `transform_nz`
- `lib/ammitto/sources/au/transformer.rb` — `transform_from_hash`, the
  second dispatcher; **read-only for this task**
- Destinations: `lib/ammitto/sources/{nz,un,au}/ingestion.rb` plus their
  `INGESTERS` entries
- `spec/integration/ingestion_robustness_spec.rb` —
  `describe 'from_hash/from_yaml model equivalence'`, the captured-model
  examples that pin class election through the command
- `spec/integration/ingestion_robustness_spec.rb` —
  `describe 'Au::Transformer#transform_from_hash'`, the independent pin

## Done when

- `grep -n 'def transform_\(nz\|un\|au\)' lib/ammitto/cli/
  harmonize_command.rb` returns nothing, and each destination file
  defines its entry point.
- Each moved body differs from its original only by the substitutions
  enumerated in `03-trivial-wrappers.md`. Prove it the same way —
  extract, substitute, `diff -u`, empty. Blame is a sanity check, not
  the proof.
- `git diff --exit-code <task-base>..<task-head> --
  lib/ammitto/sources/au/transformer.rb` is clean. Name the revisions;
  a bare `git diff` reports the working tree and proves nothing about
  the commits.
- `bundle exec rspec` green at each of the three commits, SHAs recorded,
  no existing spec file edited. The captured-model examples pass
  unchanged — they stub `Transformers::Registry.get` and throw on the
  transformer's first call, so they fail loudly if an ingestion module
  builds its own transformer or touches it before handing over the model.
- A new committed example asserts that a record carrying both
  `imo_number` and `dates_of_birth` yields an `Au::Vessel` through
  ingestion, and a sibling example asserts the same record still yields
  an `Au::Individual` through `Au::Transformer#transform_from_hash`.
  Pinning both halves is what makes the divergence a documented fact
  rather than a footnote — those two describe blocks in
  `spec/integration/ingestion_robustness_spec.rb` pin the two paths
  independently and never exercise the conflicting record.
- Normalized full-tree export diff against the Step 0 baseline is empty,
  using `00-golden-baseline.md`'s commands. **BLOCKED**, not passing, if
  the baseline or the pinned snapshots are absent.

## Size and dependencies

**M** — about a day. Three moves is less work than `03`'s nine, but the
au divergence has to be understood before it can be safely left alone,
and un's two-entry-point shape invites exactly the tidy-up that would
break the gate.

Blocked by `02-ingestion-scaffolding.md`. Blocks
`08-delete-the-case.md`. Feeds `13-USER-rulings.md`, which asks the
maintainer whether D2 is ever scheduled or stays deferred indefinitely.

## ADHD

- 🔴 Three sources' record-shape knowledge lives in the CLI command, not with the source
- 🧨 au has a *second* dispatcher with different criteria; "unifying" them silently reclassifies records
- 🔧 Cut-paste nz/un/au verbatim; un keeps `transform_individual`/`transform_entity`; `Au::Transformer#transform_from_hash` untouched
- ✅ Three green commits, `au/transformer.rb` diff empty, new example pins imo+dob → Vessel, empty tree diff
- ⛓️ Blocked by 02; blocks 08; D2 unification stays deferred (see 13)
- 📦 M — a day
