# Freeze the public API with an executable guard

## Why this matters

The maintainer's delegate set this as an absolute constraint on
2026-08-10: *"we can't change the behavior of the Public API at any
cost or stage, if we do, we need to get things documented throughly at
every step."*

Right now nothing enforces that. The gem is published (v1.0.0, an
annotated tag by the maintainer, ~345 downloads on RubyGems), so a
consumer exists whose code breaks if a constant moves or a method
signature changes. The refactor's whole purpose is relocating code
between files, which is exactly the change most likely to move a
constant or drop a method by accident — and the full-tree export diff
does **not** catch it, because the exported data can be byte-identical
while `Ammitto::PersonEntity` has quietly stopped resolving.

The 2026-08-06 design doc relies on "moves are pure cut-paste" plus
back-compat aliases to keep the surface intact. That is a promise about
care. This task turns it into a failing spec.

It is a gate, not a step: **no Track A task may start until this is in
the stack**, because its value is catching a drift the moment it
happens, not at the end.

**The snapshot must classify, not just enumerate.** An earlier draft
said every addition fails the guard and needs the maintainer's ruling,
full stop. That rule and `02-ingestion-scaffolding.md` cannot both hold:
`02` adds `Ammitto::Ingestion::{Base,Registry,Context,AnnouncementFormat}`,
so the first Track A task would be stuck waiting on a ruling about a
seam the maintainer already approved, and the board's own sequencing
would be self-defeating. The resolution is not to weaken the guard —
every difference still turns the spec red — but to make the snapshot say
*what kind of surface* each symbol is, so the failure on an internal
addition tells the author to regenerate rather than to go and ask. See
step 2.

## What to do

1. **Write the surface definition into the spec file itself**, as the
   first thing a reader meets. It must cover all of the following, and
   each item exists because it can change without any signature moving:

   - **Constants.** Every constant reachable from `Ammitto` after
     `require "ammitto"`, recursively — plus, for each one, its *kind*
     (class / module / value) and, for value constants, the value
     itself where the value is the promise. Aliases and documented
     enumerations are the cases that matter:
     `Config::Defaults::ALL_SOURCES` and `FETCHABLE_SOURCES`
     (`lib/ammitto/config/defaults.rb`),
     `Config::Defaults::OUTPUT_FORMATS`, and the two ratio
     constants `09-REFINE-harmonize-command.md` moves with the health
     gates (`MIN_UNIQUE_ID_RATIO` and `MIN_NAMED_ENTITY_RATIO`, in
     `harmonize_command.rb`). A constant that keeps its name and changes
     its contents has broken a consumer just as thoroughly as one that
     vanished.
   - **Methods and their visibility.** Public *and* protected instance
     and class methods of each constant, with parameter names, kinds
     (req/opt/keyreq/key/rest/block) and order — `Method#parameters`
     gives this directly. Record the visibility alongside, because
     making a public method private is a breaking change that leaves
     the signature untouched, and `10-REFINE-naming-and-readability.md`
     explicitly moves methods between classes where the `private`
     boundary is easy to lose.
   - **Ancestry.** Each class's superclass and its included and
     prepended modules. A consumer rescuing `Ammitto::ParseError`
     depends on it still descending from `Ammitto::Error`
     (`lib/ammitto/errors/base_error.rb`, classes `Error` and
     `ParseError`); a consumer
     duck-typing on a mixin depends on the mixin still being there.
     Neither is visible in a method list.
   - **Autoload registrations.** `lib/ammitto/models.rb`
     registers 27 autoloads, including a deliberate two-name mapping
     (`NoticeReference` and `StatusChange` both resolve to
     `status_change.rb`, the `autoload :NoticeReference` declaration).
     Record each registered constant name
     **and** that resolving it still succeeds — an autoload pointing at
     a moved file fails only when someone touches the constant, which
     is to say in production rather than in CI.
   - **Documented explicit-require entry points.** `require "ammitto"`
     is not the only front door. The docs tell users to
     `require 'ammitto/serialization/search_index_exporter'` directly
     (`docs/getting-started/quick-start.adoc`,
     `docs/interfaces/ruby-api/index.adoc`), which
     `lib/ammitto.rb` never loads — only `json_ld_serializer` is on the
     default path (`lib/ammitto.rb`, `require_relative
     'ammitto/serialization/json_ld_serializer'`). Snapshot each
     documented require path as its own entry: what it loads and what
     surface that brings with it.
   - **The whole CLI, not just `Ammitto::CLI`.** `exe/ammitto` is as
     public as the library, and it is four Thor classes, not one:
     `Ammitto::CLI` (`lib/ammitto/cli.rb`, `class CLI < Thor`),
     `Ammitto::DataCLI`
     (`class DataCLI < Thor`, mounted via `subcommand 'data', DataCLI`),
     `Ammitto::Cmd::SourceCommand`
     (`lib/ammitto/cli/source_command.rb`, `class SourceCommand < Thor`)
     and `Ammitto::Cmd::ValidateCommand`
     (`lib/ammitto/cli/validate_command.rb`, `class ValidateCommand <
     Thor`). For every command in
     every one of them record: the command name and its **positional
     arguments** as declared in the `desc` usage string (`desc 'get ID'`,
     `desc 'source COUNTRY SUBCOMMAND'`, `lib/ammitto/cli.rb`,
     the `get` and `source` command declarations), each option's name,
     type, default, **requiredness**,
     short alias and any `enum` constraint, the banner/usage line, and
     command aliases — `map %w[--version -v] => :version`
     (`lib/ammitto/cli.rb`) is a promise a consumer's script depends
     on. Options injected by
     `Options::Registry.register_thor_options` count: they
     carry `allowed:` enumerations and `cli_short` aliases from
     `lib/ammitto/options/registry.rb`, so a change there is a CLI
     change even though `cli.rb` did not move.
   - **Documented exceptions.** `lib/ammitto/errors/base_error.rb`
     defines nine classes (`Error`, `NetworkError`, `CacheError`,
     `ValidationError`, `SourceNotFoundError`, `ParseError`,
     `SerializationError`, `NotFoundError`, `ConfigurationError`) and
     the docs instruct users to rescue four
     of them by name (`docs/interfaces/ruby-api/index.adoc`,
     the `Ammitto::NotFoundError` paragraph and the `rescue
     Ammitto::ParseError => e` example). Signatures alone cannot enforce
     "public API behaviour
     cannot change": a method that starts raising `ParseError` where it
     used to raise `ValidationError` has an identical signature and a
     broken consumer. Record, for each documented entry point, which of
     these classes it is documented to raise, and pin that with an
     example rather than only with a name list.

2. **Classify every entry, and make the classification part of the
   snapshot.** Three buckets, one per entry, no defaults:

   - **`public`** — reachable from `Ammitto` after `require "ammitto"`,
     or reachable through a documented explicit require, or part of the
     CLI surface. Any change is a breaking change and needs the
     maintainer's ruling.
   - **`documented-explicit-require`** — public, but only reachable
     after a require the docs name. Tracked separately because the
     *require path itself* is the promise, and a file move breaks it
     without touching a single method.
   - **`internal-excluded`** — a namespace declared internal, listed by
     name in the snapshot header with the reason. What is excluded is
     the *maintainer ruling*, not the check: an addition here is still
     drift and still fails, it is just drift the author can clear
     themselves.

   **Every difference fails. The bucket decides the remedy, not whether
   the spec goes red.** An earlier draft said internal additions were
   "reported, not failed" and, two paragraphs later, that an
   unregenerated internal addition must fail as a stale snapshot. Those
   are the same event described twice with opposite outcomes, and a
   guard cannot be implemented from it. One rule instead:

   | | addition | removal | signature / visibility / value change |
   |---|---|---|---|
   | `public` | fail → **maintainer ruling**, then regenerate | fail → **maintainer ruling** | fail → **maintainer ruling** |
   | `documented-explicit-require` | fail → **maintainer ruling**, then regenerate | fail → **maintainer ruling** | fail → **maintainer ruling** |
   | `internal-excluded` | fail → **regenerate and commit in the same PR**; no ruling needed | fail → **regenerate and commit in the same PR**; no ruling needed | fail → **regenerate and commit in the same PR**; no ruling needed |

   The failure message must name the bucket and the remedy, so a red
   spec on an internal addition reads "regenerate the snapshot" and a red
   spec on a public one reads "this needs the maintainer". That is the
   whole practical difference, and it is enough: the author of `02`
   regenerates and moves on, while nobody can regenerate a public change
   without the ruling being visible in the change summary.

   **Excluded also does not mean unrecorded.** Internal symbols are
   captured in the snapshot exactly like public ones. A symbol that is
   never written down cannot later be found missing, so a namespace
   whose additions were merely ignored would be permanently unprotected
   against removal — the opposite of the intent.

   **`Ammitto::Ingestion` is declared `internal-excluded` in this task,
   before `02-ingestion-scaffolding.md` runs.** That is the whole point
   of doing `01` first. Its four modules
   (`base`, `registry`, `context`, `announcement_format`) are a seam
   between the CLI command and the source modules; no documented require
   reaches them; `02`'s own loads-cleanly assertion keeps the per-source
   ingesters off the default require path. Write the exclusion and its
   reason into the snapshot header in this task, and say so in `02`'s
   PR body when it lands.

   Decide and write down one more thing while you are here, because `02`
   depends on it: **does the snapshot record namespace containers?**
   Adding `Ammitto::Ingestion::Base` also brings `Ammitto::Ingestion`
   into existence, so `02`'s four modules are either four entries or
   five depending on this choice. Either answer is fine; an unstated one
   makes `02`'s "exactly four additions" criterion unfalsifiable.

3. Generate a snapshot into `spec/fixtures/public_api.yml` (sorted,
   deterministic) and commit it.

4. Add `spec/ammitto/public_api_spec.rb` that regenerates the surface
   and diffs it against the snapshot, failing with a readable diff that
   names what was added, removed or changed, and in which bucket.

5. **Regeneration requires a reviewed, machine-readable change
   summary.** Not a prose sentence in a PR body — a committed artifact
   the diff produced, listing every added, removed and changed entry
   with its bucket and its before/after value. The PR that regenerates
   the snapshot commits that summary alongside it, and the reviewer
   reads the summary rather than a 5,000-line YAML diff. A removal or a
   signature change in the `public` or `documented-explicit-require`
   buckets additionally needs the maintainer's ruling before the
   regeneration lands.

6. Prove the guard works. Show it failing five ways before you rely on
   it: rename a public method; remove a constant; add a keyword
   argument with a default; change a public method to private; and
   change a Thor option's default. All five must turn the spec red, and
   the failure must name the exact symbol. A guard that only catches
   deletions is not a freeze.

## Where

- `lib/ammitto.rb` — the require graph that defines what "after
  `require "ammitto"`" contains. Note it loads `ammitto/ontology` via
  `require_relative 'ammitto/ontology'`, so `Ammitto::Ontology::*` is
  public surface too, not internal; and it loads only
  `serialization/json_ld_serializer`, so the
  other serialization classes are reachable only through explicit
  requires.
- `lib/ammitto/models.rb` — the 27 autoload registrations,
  including the `NoticeReference`/`StatusChange` two-name mapping at
  the `autoload :NoticeReference` declaration.
- `lib/ammitto/errors/base_error.rb` — the nine error classes.
- `lib/ammitto/cli.rb` — `DataCLI`,
  `CLI`, the `--version`/`-v` alias, the injected shared options, the
  `data` subcommand mount.
- `lib/ammitto/cli/source_command.rb`,
  `lib/ammitto/cli/validate_command.rb` — the two Thor classes the
  top-level CLI routes into.
- `lib/ammitto/options/registry.rb` — `allowed:` enumerations and
  `cli_short` aliases that reach the CLI without appearing in `cli.rb`.
- `docs/getting-started/quick-start.adoc`,
  `docs/interfaces/ruby-api/index.adoc` — the documented explicit
  require; `docs/interfaces/ruby-api/index.adoc`, the documented
  exceptions examples — the
  documented exceptions.
- `spec/fixtures/public_api.yml` — new, the snapshot.
- `spec/ammitto/public_api_spec.rb` — new, the guard.

## Done when

- `bundle exec rspec spec/ammitto/public_api_spec.rb` passes on an
  unmodified tree.
- Each of the five deliberate mutations above turns it red, and the
  failure message names the exact symbol that moved.
- The snapshot header lists every `internal-excluded` namespace with
  its reason, and `Ammitto::Ingestion` is among them.
- Internal-excluded symbols are **present in the snapshot**, not merely
  ignored — check the committed file, not the spec's exit code.
- A deletion inside an internal-excluded namespace turns the spec red —
  prove it by adding a symbol, regenerating, removing it, and watching
  the spec fail. An exclusion that also excuses removals is not an
  exclusion, it is a hole; so is one that never records what it
  excluded.
- An addition inside an internal-excluded namespace also turns the spec
  red, and the failure message says **"regenerate the snapshot"** rather
  than **"this needs the maintainer"**. Demonstrate both messages once:
  one internal mutation and one public mutation, side by side.
- The snapshot header states whether namespace containers are recorded
  as entries, so `02`'s addition count is checkable.
- Every autoload registration in `lib/ammitto/models.rb` is in the
  snapshot **and** resolves — the spec touches each constant, it does
  not merely list the names.
- The CLI section covers all four Thor classes, and a change to a
  positional argument, an option default, an `enum`, or the
  `--version`/`-v` alias turns it red.
- The snapshot is stable across two consecutive runs (no hash ordering,
  no absolute paths, no timestamps) — run it twice and diff.
- The change-summary generator produces its artifact for a deliberate
  mutation, and the artifact is readable without opening the YAML.
- `TODO.refactor/README.md`'s constraint 2 can point at a spec instead
  of at a promise.

## Size and dependencies

**L** — 2 to 3 days, and it grew for a reason. Enumerating constants
and `Method#parameters` is the easy half and would have been the M this
card used to claim. The other half is the part that actually holds:
visibility, ancestry, constant values, live autoload resolution, four
Thor classes with positionals and enums and aliases, documented
explicit-require entry points, documented exceptions, and a
change-summary generator that makes a regeneration reviewable. Making
all of that deterministic across two runs is where the time goes.

Blocked by nothing. **Blocks every Track A task** (`02`–`08`). Ships
with `12-tooling-scripts.md` item 2, which turns the regenerate-and-
diff into one command. Pairs with `00-golden-baseline.md`: that one
freezes the *output*, this one freezes the *interface*. Neither catches
what the other catches.

## ADHD

- 🔴 Nothing stops the refactor silently breaking the published API
- 🧨 Export diff can be byte-perfect while `Ammitto::PersonEntity` stops resolving — or while a rescue clause quietly changes class
- 🔧 Snapshot constants + values + visibility + ancestry + autoloads + documented-require entry points + all four Thor classes + documented exceptions; classify each as public / documented-explicit-require / internal-excluded; declare `Ammitto::Ingestion` internal HERE so `02` does not fail its own gate
- ✅ Five mutations turn it red naming the symbol; internal symbols are RECORDED (excluded ≠ unrecorded) so their later removal still fails; regeneration ships a reviewed machine-readable change summary
- ⛓️ Gate — blocks tasks 02–08; ships with `12` item 2
- 📦 L — 2–3 days, most of it in the CLI surface and determinism
