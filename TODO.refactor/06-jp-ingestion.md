# Move jp ingestion, and keep the transform_jp shim

## Why this matters

This is the identity-critical move. jp is a ~170-line announcement-
ingestion subsystem occupying `lib/ammitto/cli/harmonize_command.rb` —
nine methods, most of the file's remaining comment mass, and the only
IRI-minting policy that lives outside the IRI layer.

`jp_record_id` mints
`jp.<authority>.<list>.<entry_number|position>` for records the source
published without an identifier. Its 26-line comment in
`jp_record_id`, beginning "The derivation exists because data-jp's
fefta-list/20250131.yml", is the most load-bearing prose in the file and
every clause of it is a constraint:

- data-jp's `fefta-list/20250131.yml` holds **748 records with no
  identifier field at all**; without derivation the whole source is
  unharmonizable, because the IRI layer correctly refuses to mint
  "unknown".
- **Position, not name, is the disambiguator** — `IriSanitizer` strips
  non-ASCII, so four of those 748 names sanitize to the same empty
  string and a name-derived id would silently merge four distinct
  sanctioned entities into one.
- Position is also what keeps a jp IRI **stable across republications**:
  `mof-asset-freeze/01-milosevic`'s `20260305.yml` and `20260306.yml`
  reuse `jp.mof.milosevic.1..10` verbatim.
- `entry_number` is the trailing number rather than the id outright
  because it is unique only within a list.
- Blank segments are dropped instead of aborting, because returning nil
  raises `MissingLocalIdError` and takes the whole source down.

So the failure mode here is precisely the one the whole two-track
discipline exists to catch: the entity count stays identical while every
jp IRI quietly shifts by one, or merges, or gains a segment. Nothing in
the suite would notice. Only the tree diff would.

**The `transform_jp` shim is mandatory for Track A. Its lifetime is not
this card's to decide.** Four
examples call it directly, bypassing `transform_data` entirely —
`spec/ammitto/cli/harmonize_command_spec.rb`, in
`describe '#transform_jp with an announcement that carries no ids'`,
with examples covering "publishes every record instead of refusing the
whole file", "mints positional ids in the convention the list already
uses", "keeps an explicit id in preference to a minted one", and
"numbers by entry_number when the record carries one". This is the
discovery that retracted the design doc's original "zero spec edits are
structurally guaranteed" claim (revision note 3, 2026-08-06). Since
Track A permits **no edits to existing spec files**, `transform_jp` stays
on the command as a one-line delegation to the jp ingestion module.
Deleting it, or migrating those four examples, is **not part of this
work**.

Whether it is permanent, scheduled for removal, or left undecided is
**ruling 2 in `13-USER-rulings.md`**, and this card must not pre-empt it.
`06`, `08` and `10` implement identically under every answer — the shim
survives Track A regardless — so write it up as "mandatory here, lifetime
unresolved" rather than as permanent. An earlier draft of this card
called it "not temporary", which quietly answered a question the
maintainer was being asked.

One trap that a careless split would spring:
`transform_jp_announcement` constructs `Jp::Entity` but has **no
`require_relative` of its own**. The require lives one method up, inside
`transform_jp`. Separate the two entry points into different files, or
reach the announcement path without going through `transform_jp` first,
and `Jp::Entity` is undefined at runtime.

## What to do

1. Move all nine methods into one file,
   `lib/ammitto/sources/jp/ingestion.rb`, in one commit, verbatim:
   `transform_jp`, `jp_announcement?`,
   `jp_announcement_entities`,
   `transform_jp_announcement`, `jp_flatten_record`,
   `jp_record_id`, `jp_id_segment`,
   `jp_record_remarks`, `jp_note_texts`.
2. Move **every comment** with its method. The nine comment blocks span
   `transform_jp`, `jp_announcement?`, `transform_jp_announcement`,
   `jp_flatten_record`, `jp_record_id`, `jp_id_segment`,
   `jp_record_remarks`, and `jp_note_texts`. The `jp_record_id`
   block in particular is the only written record of why the ids look
   the way they do; losing it costs the next maintainer a day and a
   regression.
3. Keep `require_relative` for `Jp::Entity` reachable from **both**
   entry points, or keep the two entry points in the same file with the
   require where it is. Do not "optimise" it to a top-level require —
   `02`'s loads-cleanly spec forbids that.
4. Leave the shim on the command — it survives this card and all of
   Track A, and nothing here decides whether it survives beyond that
   (ruling 2). It must accept
   `(transformer, data)` positionally and return exactly what the module
   returns — a Hash for a flat record, an Array of pairs for an
   announcement. The four direct callers pass a real
   `Transformers::Registry.get(:jp)` instance
   (`spec/ammitto/cli/harmonize_command_spec.rb`), not a double.

   **The shim must reach the module through the same context factory
   `transform_data` uses.** If it builds its own context, or hands the
   module a differently-configured one, the four direct callers exercise
   a path that production never takes — and the shim silently stops
   being a compatibility shim. Extract the "build a context for this
   source" step into one private method and have both call it.
5. Register `jp` in `INGESTERS`.
6. Add a jp ingestion unit spec (additive) covering both shapes — top-
   level `entities` and `entities` nested under `sanction_details` — and
   the four id paths: published id wins, `entry_number` used, position
   used, blank segments dropped.
7. Run the targeted jp export diff, not just the suite. This is the one
   step where the design doc calls for a source-scoped byte diff on top
   of the full-tree gate.

## Where

- `lib/ammitto/cli/harmonize_command.rb` — the whole jp subsystem,
  comments included
- `transform_jp` — the lone `require_relative` for `Jp::Entity`,
  reached only via `transform_jp`
- `jp_record_id` — the IRI-minting policy comment beginning
  "The derivation exists because data-jp's fefta-list/20250131.yml"
- Destination: `lib/ammitto/sources/jp/ingestion.rb`, plus its
  `INGESTERS` entry, plus the shim left behind on the command
- `spec/ammitto/cli/harmonize_command_spec.rb` —
  `describe '#transform_jp with an announcement that carries no ids'`
- `spec/ammitto/cli/harmonize_command_spec.rb` —
  `context 'with a jp announcement file'`, entering at
  `transform_data`: one result per entity, published-id-wins,
  nested-`sanction_details` reading, derived IRI shape

## Done when

- All nine methods are gone from `harmonize_command.rb`; the only
  `jp`-named method left is the shim, and its body contains exactly one
  expression — a call into `Sources::Jp::Ingestion`. State it that way,
  not as "one line": a line count is a formatting fact, not a structural
  one.
- The nine moved bodies differ from their originals only by the
  substitutions enumerated in `03-trivial-wrappers.md` — extract,
  substitute, `diff -u`, empty. This matters more here than anywhere
  else in the stack.
- `bundle exec rspec spec/ammitto/cli/harmonize_command_spec.rb` is green
  with the file unedited. A green run does **not** by itself prove the
  four examples in
  `describe '#transform_jp with an announcement that carries no ids'`
  went through the shim — they would also pass if the old body were
  still there. Add a spy expectation that
  `Sources::Jp::Ingestion` receives the call, or have a dedicated unit
  spec assert the shim's return value is the module's.
- **Every jp IRI is byte-identical to the Step 0 baseline.** Diff the
  sorted entity-`@id` manifest restricted to `entity/jp/`; the diff must
  be empty, not "same count".
- The republication case is proven, not assumed: harmonize
  `mof-asset-freeze/01-milosevic`'s `20260305.yml` and `20260306.yml` and
  confirm both still yield `jp.mof.milosevic.1` through `.10`, matched to
  the baseline.
- The 748-record `fefta-list/20250131.yml` still harmonizes to 748
  entities with 748 **distinct** IRIs — count both the entities produced
  from that one input file and the size of the deduplicated `@id` set,
  and assert they are equal. The four empty-sanitizing names must still
  be four entities, not one.
- All three jp bullets above require the **exact** `data-jp` snapshot the
  Step 0 baseline was captured over, pinned by commit SHA. If it is not
  available, this task reports **BLOCKED** — never "passed" and never
  "failed"; an unavailable input cannot arbitrate a code change.
- Normalized full-tree export diff against the Step 0 baseline is empty,
  per `00-golden-baseline.md`.

## Size and dependencies

**M** — about a day, and the day is not in the typing. The move itself
is one large cut-paste; the time goes into the jp-scoped export diff and
into the republication and 748-record checks, which need the data-jp
snapshot the Step 0 baseline was captured over. If that snapshot is not
available, this task is blocked, not slower.

Blocked by `02-ingestion-scaffolding.md`. Blocks
`08-delete-the-case.md`, which must leave the shim standing. Feeds
`13-USER-rulings.md` on the shim's lifetime.

## ADHD

- 🔴 ~170 lines of jp announcement ingestion + IRI-minting policy live in the CLI command
- 🧨 Entity count can stay identical while every jp IRI shifts, merges 4 empty-sanitizing names into 1, or breaks republication stability — no spec would notice
- 🔧 Move nine methods + nine comment blocks verbatim to `sources/jp/ingestion.rb`; leave a one-line `transform_jp` shim — mandatory for Track A, lifetime is ruling 2 in `13`
- ✅ Four direct callers in `describe '#transform_jp with an announcement that carries no ids'` green unedited; jp `@id` manifest byte-identical; milosevic.1..10 stable; 748 → 748 distinct IRIs
- ⛓️ Blocked by 02; blocks 08; needs the data-jp snapshot or it stalls
- 📦 M — a day, mostly verification not typing
