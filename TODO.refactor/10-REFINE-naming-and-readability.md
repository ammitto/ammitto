# Fix the names Track A was forbidden to fix

## Why this matters

Track A moves code verbatim on purpose: a commit that moves *and*
renames turns an empty tree diff from "you broke nothing" into "which of
my two intentions caused this?" So every naming problem Track A meets,
it carries forward untouched — including the ones it creates.

The result is a set of names that were correct where the code used to
live and are wrong where it now lives, plus one genuine collision. None
of these are cosmetic; each one costs a reader time, and two of them are
capable of causing a real bug.

**The collision, and it is the dangerous one.** Task `02` gives the
ingestion context a `serialize_entity(entity)` method. There is already
a `serialize_entity` on `Ammitto::Serialization::JsonLdSerializer`
(`lib/ammitto/serialization/json_ld_serializer.rb`, alongside
`serialize_entry`), and the two do not return the same thing: the
context's version is the body of `entity_to_hash`, which is
`json_ld_serializer.serialize_entity(entity).except('@context')`. Same
name, one drops `@context` and one does not. Someone will eventually
call the wrong one, and the failure will be a subtly malformed node
rather than an exception.

**Names that were right in a command and are wrong in a module.** After
Track A, `Sources::Jp::Ingestion` holds seven methods prefixed `jp_` —
`jp_announcement?`, `jp_announcement_entities`, `jp_flatten_record`,
`jp_record_id`, `jp_id_segment`, `jp_record_remarks`, `jp_note_texts`
(all in `harmonize_command.rb`). The prefix existed to
disambiguate them from fourteen other sources' helpers sharing one
class. Inside a class already namespaced `Jp`, it is noise on every
line. Same for `ch_target_shape?` inside `Sources::Ch::Ingestion`
and `transform_cn_announcement` / `transform_cn_modification` inside
`Sources::Cn::Ingestion`.

This is the clearest possible illustration of why the two tracks exist.
Renaming those seven jp methods during the move would have been one
keystroke each and would have destroyed `git blame -C` across the most
identity-critical code in the pipeline.

**A name that becomes a lie.** After `08`, `transform_data` transforms
nothing — it looks up a transformer, looks up an ingester, and
delegates. It is a dispatcher. But five `send` calls pin the name
(two in `spec/integration/ingestion_robustness_spec.rb`, three in
`spec/ammitto/cli/harmonize_command_spec.rb`), so
renaming it edits existing spec files — allowed in Track B, but a
decision, not a tidy-up.

**A fifth thing called Registry.** `Ingestion::Registry` joins
`Options::Registry` (`lib/ammitto/options/registry.rb`),
`Sources::Registry` (`lib/ammitto/sources/registry.rb`),
`Extractors::Registry` (`lib/ammitto/extractors/registry.rb`) and
`Transformers::Registry` (`lib/ammitto/transformers/registry.rb`),
plus `Utils::ListTypesRegistry` and
`Ontology::AuthorityRegistry`. "The registry" is now ambiguous in every
conversation about this codebase.

**Nine files that are one file.** `03` produces nine ingestion modules
differing by one line — the model class — plus a guard on two of them.
`03` explicitly defers the collapse to here.

## What to do

Each item is its own commit with its own justification. Take them in
this order; the first two are the ones with a bug behind them.

1. Rename the context's serialization methods so they cannot be confused
   with `JsonLdSerializer`'s. Something that names the difference, e.g.
   `entity_node` / `entry_node` — "node" is already the vocabulary the
   exporter uses (`add_node`, in `json_ld_graph_exporter.rb`). Update
   all fifteen ingestion modules in the same commit.
2. Comment the `transform_jp` shim in place. After Track A it is the
   only `transform_<source>` method left on the command and reads as an
   oversight. Three lines saying it is a deliberate compatibility shim
   for four direct callers, naming
   `spec/ammitto/cli/harmonize_command_spec.rb`, and pointing at
   `13-USER-rulings.md` for its lifetime.
3. Drop the redundant per-source prefixes: the seven `jp_*` methods,
   `transform_jp_announcement` → `announcement` (it carries the same
   redundant prefix and the same `transform_` verb; leaving it is
   half a rename), `ch_target_shape?` → `target_shape?`, and the two
   `transform_cn_*` → `announcement` / `modification`.

   Keep them private in the ingestion classes. Note this is not a change
   of visibility — every one of them is already below the command's
   `private` in `harmonize_command.rb`, so they were never public
   surface; the point is not to *make* them public by moving them.

   Verify with `grep -rn` that no caller outside the class exists before
   each rename, and re-run the source's own export slice afterwards:
   these helpers decide source classification and jp identifiers, so a
   missed or misdirected call changes artifacts rather than raising.
   Grep alone is weaker than a per-source export comparison.
4. Collapse the nine trivial wrappers into a declaration. Something
   like a `SimpleIngester` that takes the model class and an optional
   guard, so `sources/tr/ingestion.rb` becomes a line rather than a
   file. Keep uk and us's guard call explicit in the declaration — it is
   a pipeline invariant, not a default, and it must stay visible at each
   call site.

   **This one is not output-neutral by construction**, unlike the rest of
   the card. A declarative collapse can change when the model's
   `require_relative` fires, how the model constant resolves, whether
   the guard still runs before the parse for uk and us, and the shape of
   the transformer call. Every one of those can move an exported byte or
   a refusal message. Hold it to Track A's bar: per-source normalized
   export comparison plus exact guard-message equality, not the card's
   general claim below.
5. Decide on `transform_data`. Either rename it to what it is
   (`dispatch`, `ingest`) and migrate the five `send` calls, or leave it
   and document why in the class comment. Do not leave it renamed *and*
   shimmed — a shim named `transform_data` that calls `dispatch` is
   worse than either.
6. Disambiguate `Ingestion::Registry`, or record a deliberate decision
   not to. Given four existing `Registry` classes the honest options are
   a distinct name (`Ingesters`) or a project-wide convention stated
   once in `CLAUDE.md`. Do not rename the four existing ones — that is
   public API and belongs to `01`'s guard, not to a readability pass.

## Where

- `lib/ammitto/ingestion/context.rb` — the colliding method names
- `lib/ammitto/serialization/json_ld_serializer.rb` — the other
  `serialize_entity`; `entity_to_hash` shows the `.except`
  that distinguishes them
- `lib/ammitto/sources/jp/ingestion.rb` — seven `jp_*` methods, from
  `harmonize_command.rb`
- `lib/ammitto/sources/ch/ingestion.rb` — `ch_target_shape?`
- `lib/ammitto/sources/cn/ingestion.rb` — `transform_cn_announcement`,
  `transform_cn_modification`
- `lib/ammitto/sources/{uk,eu,us,wb,ca,ru,tr,eu_vessels,un_vessels}/
  ingestion.rb` — the nine collapse candidates
- `lib/ammitto/cli/harmonize_command.rb` — `transform_data`, the
  `transform_jp` shim
- `lib/ammitto/{options,sources,extractors,transformers}/registry.rb` —
  the four existing `Registry` classes

## Done when

- No two methods reachable from an ingestion module share a name with
  different return contracts. Prove it for the `serialize_entity` case
  specifically: grep both names and show each call site resolves to the
  intended one.
- No method inside `Sources::X::Ingestion` is prefixed with `x_`.
- `bundle exec rspec` green. Any existing spec file this card edits is
  listed in the PR body with what the example asserted before and after.
- `bundle exec rubocop` clean with no new `.rubocop_todo.yml` entries.
- **Output unchanged.** Items 1, 2, 3, 5 and 6 are internal renames and
  comments; none touch a serialized value. Re-run the normalized
  full-tree diff against the Step 0 baseline and show it empty. If any
  rename turns out to reach an exported string, it is not a rename —
  stop and take it to `13-USER-rulings.md`.
- **Item 4 (the wrapper collapse) carries the Track A bar instead**, per
  its own note: a per-source normalized export comparison for all nine
  sources, plus exact equality on the uk and us guard messages. An empty
  whole-tree diff is the outcome, not the method — nine sources
  collapsing at once is exactly the change where a whole-tree pass could
  hide two offsetting errors.
- `spec/ammitto/public_api_spec.rb` passes, or its snapshot is
  regenerated with each addition and removal explained in the PR body.
- The `transform_data` decision and the `Registry` decision are both
  recorded in writing, including if the decision was "leave it".

## Size and dependencies

**M** — about a day. Mechanical once decided; the day goes into the
`transform_data` and `Registry` calls, and into proving each rename has
no caller left.

Blocked by all of Track A (`08`) — these names do not exist until the
modules do. Independent of `09` and `11`, though it reads better after
`09` and should not be interleaved with it: both edit
`harmonize_command.rb`, and two refactors in one file at once is the
thing `README.md` warns about.

## ADHD

- 🔴 Track A is forbidden to rename anything, so it ships names that are wrong where the code landed
- 🧨 `Context#serialize_entity` collides with `JsonLdSerializer#serialize_entity` and drops `@context` — same name, different output, silent malformed nodes
- 🔧 Rename the context methods; strip seven redundant `jp_` prefixes; collapse nine one-line wrappers; comment the jp shim; decide on `transform_data` and a fifth `Registry`
- ✅ No colliding names, no `x_` prefix inside `Sources::X`, suite + rubocop green, **tree diff still empty**
- ⛓️ Blocked by 08; do not interleave with 09 (same file)
- 📦 M — a day
