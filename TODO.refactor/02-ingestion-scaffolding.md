# Build the ingestion seam and prove it is opaque

## Why this matters

Everything in Track A moves through a seam that does not exist yet.
`transform_data` (`lib/ammitto/cli/harmonize_command.rb`, `def
transform_data`) reaches straight into command state: it calls the
command's own `entity_to_hash`/`entry_to_hash` and, for cn,
`@exporter.add_group`. Move a body out of the command as-is
and it takes those private couplings with it — at which point the
"ingestion module" is a file that still needs the whole command, and
nothing has actually been separated.

The seam is also the load-bearing piece of a decision already made and
not up for renegotiation: **issue #13 (the ontology migration) is
deferred, and this refactor must neither start it nor foreclose it.**
That only stays true if ingestion treats whatever a transformer returns
as opaque — never instantiating a model, never `is_a?`-ing one, never
sniffing `respond_to?` to decide a branch. Written as a rule in a design
doc, that lasts until the first person who finds a type check
convenient. Written as a failing spec, it lasts.

The opacity contract test is therefore not a nice-to-have. It is the
only executable evidence that the model layer can later be swapped
underneath the transformers without reopening a single ingestion module.

Two spec pins constrain the design before a line is written, and both
were verified in the tree:

- `spec/integration/ingestion_robustness_spec.rb`, the example that sets
  `@exporter` with `instance_variable_set` **after**
  construction. So the context cannot capture the exporter at command
  construction time — it must read the command's current `@exporter`
  when ingestion runs.
- `spec/integration/ingestion_robustness_spec.rb`, the example that
  stubs `Transformers::Registry.get` with a recorder whose
  `method_missing` throws on the *first* call and keeps `args.first`.
  So an ingestion module must be **handed** the transformer, must call
  it with the model as the first positional argument, and must call
  nothing else on it first — not even `respond_to?`.

**This task adds constants, and that is allowed by prior arrangement,
not by exception.** `01-public-api-freeze.md`'s snapshot classifies
every entry as `public`, `documented-explicit-require` or
`internal-excluded`, and it declares the whole `Ammitto::Ingestion`
namespace `internal-excluded` — with the reason written into the
snapshot header — **before this task runs**. So the four modules below
are additions the guard accepts rather than rejects.

Three obligations follow, and all three are obligations rather than
conveniences:

- Nothing here may be reached by a documented require. If it is, it is
  `documented-explicit-require` surface and the exclusion does not
  apply to it.
- **This task regenerates the snapshot and commits it**, with `01`'s
  machine-readable change summary alongside. Excluded does not mean
  unrecorded: a symbol that never enters the snapshot can never be
  found missing later, so leaving the modules out would hand the seam
  permanent immunity from the removal check — the opposite of the
  intent. Under `01`'s rules the spec goes red first and its message
  says "regenerate the snapshot"; that red is expected here and is not
  a public-API break.

  The change summary must contain **only `internal-excluded` additions
  and nothing at all in the other two buckets**. A single `public` or
  `documented-explicit-require` entry means this task changed the
  published API — stop and take it to `13-USER-rulings.md`.

  Expect **four or five entries** and know which before you look:
  `Base`, `Registry`, `Context` and `AnnouncementFormat`, plus the
  `Ammitto::Ingestion` namespace itself, which comes into existence as a
  constant the moment the first of them is defined. `01`'s snapshot
  header states whether namespace containers are recorded as entries;
  read it and assert that number rather than assuming four.
- From that regeneration onward, a *removal* or a signature change
  inside `Ammitto::Ingestion` turns `01`'s spec red, because the moves
  `03`–`08` make through this seam are supposed to be
  behaviour-preserving too.

Restate the classification in this task's PR body so the reviewer does
not have to go and find it.

## What to do

1. Add `lib/ammitto/ingestion/context.rb`. It is a narrow facade over
   the exporter — never the command. Exactly this surface, nothing more:
   - `serialize_entity(entity)` — the body of
     `harmonize_command.rb`, `def entity_to_hash`,
     including the nil guard and `.except('@context')`.
   - `serialize_entry(entry)` — the body of
     `harmonize_command.rb`, `def entry_to_hash`.
   - `add_group(group)` — forwards to `@exporter.add_group(group,
     source: <the code this context was built for>)`. The exporter's
     signature (`json_ld_graph_exporter.rb`, `def add_group`) takes
     `source:` as a required keyword, so the context carries the source
     code rather than dropping the argument. **cn only**; no other
     source may call it without a design change.
   - Nothing else. No exporter internals, no command state, no IO.

   **One body, two callers — not two bodies.** Every unmigrated
   `transform_*` method still calls the command's `entity_to_hash` and
   `entry_to_hash` until `07` lands
   (`harmonize_command.rb`, from `def guard_announcement_format!`
   through `def entry_to_hash`),
   so both must keep working throughout the stack. Put the serialization
   body in exactly one place and have the context and the command's two
   methods both call it; the command's become one-line delegations for
   the duration of the stack, and `09` disposes of them once nothing
   calls them. Two copies would be two things to keep in step across six
   commits.

   Note that serialization needs **no source code** — only `add_group`
   does (`harmonize_command.rb`, `@exporter.add_group(result[:group],
   source: :cn)`). So the shared body can be a
   plain collaborator the command reaches without constructing a
   per-source context, which is what makes the delegation trivial.

   **Lifetime is part of the contract.** Build the context at dispatch
   time from the command's *current* `@exporter`; never capture the
   exporter at command construction. Add a spec that swaps `@exporter`
   between two transforms of the same source and asserts the second
   exporter — not the first — receives the cn group.
2. Add `lib/ammitto/ingestion/announcement_format.rb` holding the error
   class (`harmonize_command.rb`, `class AnnouncementFormatError <
   StandardError`), `ANNOUNCEMENT_FORMAT_KEYS`
   (`ANNOUNCEMENT_FORMAT_KEYS`) and the guard body (`def
   guard_announcement_format!`) verbatim. Leave
   `HarmonizeCommand::AnnouncementFormatError` and
   `HarmonizeCommand::ANNOUNCEMENT_FORMAT_KEYS` as aliases pointing at
   the same objects — `spec/integration/ingestion_robustness_spec.rb`,
   the examples that pin the constant path and its message, so the class
   identity must be preserved, not re-declared.
3. Add `lib/ammitto/ingestion/base.rb`: the common shape (receives an
   injected transformer plus a context, returns a pair or an array of
   pairs) and a `pair(entity, entry)` helper that calls
   `ctx.serialize_entity` / `ctx.serialize_entry`. Keep it small — it is
   a shared body, not a framework.
4. Add `lib/ammitto/ingestion/registry.rb` with an **explicit greppable
   `INGESTERS` map**, source code → ingestion class, lazily required.
   Convention-based loading was evaluated and **rejected on 2026-08-06**:
   a misnamed file degrades silently to nil pairs and surfaces as a
   misleading emptiness-gate message. Do not reintroduce it.

   Note that `TRANSFORMERS` in
   `lib/ammitto/transformers/registry.rb`, constant `TRANSFORMERS`, is
   the house pattern for *shape* but not for *loading*: it maps to bare
   class constants and its file eagerly requires all fifteen
   transformers at the top. A map
   written that way is not lazy, and `require "ammitto"` would then load
   every ingestion module — which step 9 below forbids. Map each code to
   a `[relative_path, constant_name]` pair (or a proc), and have `get`
   require then resolve. Say which form you chose in the PR body; "map,
   lazily required" is not a design.
5. Preserve both of today's nil-pair paths exactly, and their order.
   `transform_data` returns `{ entity: nil, entry: nil }` at the first
   guard after `Registry.get` yields no transformer, and again at the
   final `else` for a source the case does not name. The transformer
   check comes **first** today.
   **No existing spec pins that order** — the recorder at
   `ingestion_robustness_spec.rb`, the `Transformers::Registry.get`
   recorder example, stubs `Registry.get` for every
   source and never exercises an unregistered one, so both orders pass
   it. Treat the order as an intentional contract and *add* the spec that
   makes it one: for an unknown source, the transformer lookup happens
   and the ingester lookup does not. Unknown-source misses reproduce
   today's fallthrough — never a new exception class.
6. Point the command's `guard_announcement_format!` at the new module as
   a delegation. No caller changes in this step.
7. Write the **fake-transformer opacity contract test** as an RSpec
   **shared example**, and apply it here to `Base` plus one fixture
   ingester. It drives an ingester with a transformer returning sentinel
   objects that are deliberately *not* model instances, and asserts the
   sentinels arrive at the context's serialization seam un-inspected —
   no `is_a?`, `kind_of?`, `instance_of?`, or class-`case` on a
   transformer result. A sentinel that responds to nothing but
   `#object_id` is the strongest form: anything that touches it raises.

   It has to be a shared example rather than a loop over "every
   ingestion module", because **no per-source module exists yet** —
   they arrive in `03`–`07`. Each of those tasks includes the shared
   example for the module it adds; `08` asserts every registered code is
   covered by it.
8. Add the registry-resolution spec, but scope it to what can be true
   today: the map's entries all resolve, and no entry names a code
   outside `Config::Defaults::ALL_SOURCES`
   (`lib/ammitto/config/defaults.rb`, `ALL_SOURCES`, 15 codes). The
   **completeness**
   direction — every one of the 15 codes appears in `INGESTERS` — cannot
   pass until `07` registers the last source, so it lands in
   `08-delete-the-case.md`. Writing it here just means committing a red
   spec.
9. Add the loads-cleanly assertion: `require "ammitto"` defines no
   `Ammitto::Ingestion::*` per-source constants, protecting the lazy-load
   property.

## Where

- `lib/ammitto/ingestion/{base,registry,context,announcement_format}.rb`
  — all new; the directory does not exist today.
- `lib/ammitto/cli/harmonize_command.rb` —
  guard pieces that move.
- `lib/ammitto/cli/harmonize_command.rb` —
  `json_ld_serializer`, `entity_to_hash`, `entry_to_hash`: the
  serialization bodies the context takes over.
- `lib/ammitto/cli/harmonize_command.rb` — `transform_data`, the
  two nil-pair returns in `def transform_data`.
- `lib/ammitto/serialization/json_ld_graph_exporter.rb` —
  `add_group(group, source:)`; `source:` is documented unused in the
  comment immediately above `def add_group`
  but is a required keyword.
- `lib/ammitto/transformers/registry.rb` — the `TRANSFORMERS` map to
  imitate.
- `spec/integration/ingestion_robustness_spec.rb` — the three pins the
  design must satisfy.

## Done when

- `bundle exec rspec` is green, and no existing spec file was edited:

  ```bash
  git diff --name-only <track-a-base>..HEAD -- spec/ | \
    xargs -r git log --diff-filter=A --format=%H -1 --
  ```

  every listed spec path must be newly added by this stack, not modified.
  The three guard-refusal contexts at
  `spec/integration/ingestion_robustness_spec.rb` pass unchanged.
- A committed spec asserts the alias with `equal?`, not `==`:
  `Ammitto::Cmd::HarmonizeCommand::AnnouncementFormatError` and the
  module's error class are the same object.
- The opacity shared example is red when a type check is present. Prove
  it with a **committed** negative fixture — an intentionally
  non-conforming ingester defined in the spec file that the example is
  expected to reject — not by temporarily editing production code.
- A committed spec fails, naming the code, when `INGESTERS` contains an
  entry outside `ALL_SOURCES` or an entry that does not resolve.
- `spec/ammitto/public_api_spec.rb` (from `01`) is green **after** the
  regenerated `spec/fixtures/public_api.yml` is committed in this task,
  **with a change summary containing only `internal-excluded` additions
  and zero entries in the `public` or `documented-explicit-require`
  buckets**. An entry in either of those means this task changed the
  published API; stop and take it to `13-USER-rulings.md`.
- The addition count in that summary matches `01`'s stated rule on
  namespace containers — four modules, or five with
  `Ammitto::Ingestion` itself. State which in the PR body; do not report
  a count without saying which rule produced it.
- Removing one of them now turns `01`'s spec red. Demonstrate it once —
  delete a constant locally, watch it fail, revert — because a namespace
  whose additions are waved through and whose removals are not caught is
  not an exclusion, it is a hole.
- `ruby -e 'require "ammitto"; ...'` shows the set of loaded per-source
  ingestion constants is exactly empty — assert emptiness, do not eyeball
  `constants.inspect`.
- `git diff --exit-code <track-a-base>..HEAD -- <ingest_results extract>`
  is clean. Extract `ingest_results` (`harmonize_command.rb`, `def
  ingest_results`)
  from both revisions and compare; diffing the whole file will not do,
  since this task edits it.
- No behaviour change: this step wires the seam and moves nobody through
  it, so the Step 0 tree diff must be empty for the trivial reason. Run
  the normalization and diff commands `00-golden-baseline.md` defines; if
  the Step 0 artifacts or the pinned data-repo snapshots are absent, this
  task is **BLOCKED**, not passing.

## Size and dependencies

**M** — about a day. The four files are small; the day goes into the
opacity test (designing a sentinel that is genuinely inert) and into
proving the alias preserves class identity rather than shadowing it.

Blocked by `00-golden-baseline.md` and `01-public-api-freeze.md` — both
gates, both must be in the stack first. Blocks every remaining Track A
task (`03`–`08`); nothing moves through a seam that is not built.

## ADHD

- 🔴 No seam exists — every transform body reaches into command privates and `@exporter`
- 🧨 Move code as-is and the "module" still needs the whole command; #13 gets foreclosed by the first `is_a?`
- 🔧 Four files: context facade (serialize_entity/serialize_entry/add_group), guard module + aliases, base, explicit INGESTERS map
- ✅ Suite green with zero spec edits; opacity test goes red when a type check is added; error class is `equal?` to its alias; snapshot regenerated with internal-only additions (4 or 5 — per `01`'s namespace rule) and ZERO public ones
- ⛓️ Blocked by 00 + 01 — `01` must already have declared `Ammitto::Ingestion` internal-excluded, or this task fails its own gate; blocks 03–08
- 📦 M — a day, most of it on the sentinel
