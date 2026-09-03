# Break HarmonizeCommand into its actual responsibilities

## Why this matters

This is the card the delegate's direction was actually about —
*"refinements, improvements, better readability, better
design/structure."* Track A does not deliver that. Track A relocates
source knowledge and leaves a smaller version of the same class behind.

`harmonize_command.rb` is **1,459 lines and 74 methods** today, of which
19 are `transform_*` (all three counts measured at `0f8afc6`,
2026-08-11). Track A leaves roughly **930 lines and 49 methods in one
class**, still one of the largest files in the gem.

That figure is derived, not quoted, because an earlier draft of this
card got it wrong. It said "~890 lines and 48 methods", reached by
subtracting the whole `transform_data`-through-`transform_un_vessels`
span — but `transform_data` and `guard_announcement_format!` sit inside
that span and **stay**, so the span cannot be subtracted whole. The
arithmetic that holds:

| Step | Lines | Methods |
|---|---|---|
| Today | 1,459 | 74 |
| Remove `transform_uk`'s comment through `transform_un_vessels`' `end`, the 26 methods Track A moves | −507 | −26 |
| `06` leaves the `transform_jp` shim, and `10` adds its three-line comment | +7 | +1 |
| `08` replaces `transform_data`'s 15-branch case (34 lines) with a facade of about 8 | −26 | 0 |
| **After Track A** | **≈933** | **49** |

The method count is exact; the line count is ±10 depending on how the
facade and the shim are formatted. And the file is not long because
harmonizing is complicated. It is long because six unrelated jobs share
a class:

| Responsibility | Methods |
|---|---|
| CLI orchestration (`initialize`, `run`, `normalize_sources`, `validate_sources!`, `harmonize_all`, `harmonize_source`) | 6 |
| Health gates and quality floors | 15 |
| Aggregate writing (`write_source_aggregate`) | 1 |
| Exporter ingestion (`ingest_results`, `entry_ids_by_entity`, `link_sanction_entry`) | 3 |
| Input discovery | 14 |
| Serialization helpers (`json_ld_serializer`, `entity_to_hash`, `entry_to_hash`) and `cache_dir` | 4 |
| Reporting (`print_summary`, `print_source_problems`, `print_graph_totals`) | 3 |

Input discovery alone is 252 lines and 14 methods that never touch a
transformer, an exporter, or a source model — it answers one question
("which directory and which YAML files for this source?") and answers it
through five fallback tiers. Health gating is another 215 lines that
never touch the filesystem. Neither needs to be in a class named
`HarmonizeCommand`, and while they are, the class has no describable
invariant: you cannot say what `HarmonizeCommand` *is* in one sentence.

**The constraint that makes this L instead of M.** The command's private
methods are not private in practice. Specs reach 14 of them through
`send`, 51 times:

| Method | `send` calls | Where |
|---|---|---|
| `enforce_health_gates` | 8 | `spec/integration/harmonize_pipeline_spec.rb` |
| `print_summary` | 7 | `spec/ammitto/cli/harmonize_command_spec.rb` |
| `find_supporting_dirs` | 7 | `harmonize_command_spec.rb` |
| `find_instruments_dirs` | 5 | `harmonize_command_spec.rb` |
| `find_input_dir` | 5 | `harmonize_command_spec.rb` |
| `transform_jp` | 4 | `harmonize_command_spec.rb` |
| `transform_data` | 3 | `harmonize_command_spec.rb` |
| `quality_floor_failures` | 3 | `harmonize_command_spec.rb` |
| `harmonize_source` | 3 | `harmonize_command_spec.rb` |
| `allowed_empty_sources` | 2 | `harmonize_pipeline_spec.rb` |
| `link_sanction_entry` | 1 | `harmonize_command_spec.rb` |
| `harmonize_all` | 1 | `harmonize_command_spec.rb` |
| `eligible_yaml_files` | 1 | `harmonize_command_spec.rb` |
| `aggregate_name_metrics` | 1 | `harmonize_command_spec.rb` |

**51 calls across 14 methods**, counted on `origin/main` on 2026-08-20 by
grepping `send(:` in both spec files. Line numbers are deliberately
absent: they moved twice while this board sat unmerged, and a table of
stale line numbers is worse than no table.

An earlier draft said 40 calls across 11 methods and named
`find_instruments_dir` and `find_supporting_dir` in the singular. Both
became plural when supplement loading stopped stopping at the first
match, and `transform_jp`, `transform_data` and `harmonize_all` were
missing entirely. The command has also gained `--report` since, which
this card's extraction plan does not yet account for.

Re-derive this table before extracting anything. The count is not the
point — a `send` pin you did not find is an example that goes red at the
worst moment.

Move `find_input_dir` to a collaborator and five examples go red on that
method alone; move the discovery block as a whole and it is fifteen.
That is the real design question this card has to answer, and it is a
question about **who owns the test seam**, not about file length.

## What to do

Answer the seam question first, then extract. Three options; pick one and
record why in the PR body:

- **(a) Extract with delegating shims.** `HarmonizeCommand` keeps a
  one-line private delegation for each of the 14 pinned methods. Zero
  spec edits. Cost: 14 permanent shims, on top of `transform_jp`'s —
  the class stays wide even though it gets thin. This is the Track A
  pattern applied again, and applied 11 times it stops being a shim and
  starts being an anti-pattern.
- **(b) Extract and migrate the specs.** The 51 `send` calls become
  direct tests of `Harmonize::InputDiscovery` and
  `Harmonize::HealthGates`, which is where they belonged. Cost: existing
  spec files are edited — permitted in Track B but **not** in Track A,
  so this cannot start until `08` is complete and below this card in the
  stack, and each migrated example must be shown to assert the same
  thing before and after.
- **(c) Do not extract; improve in place.** Order the methods by
  responsibility, add section comments, extract only genuinely private
  helpers. Cost: the class still has six jobs.

Recommendation: **(b)**, because the `send` calls are themselves the
defect — a spec that reaches a private method is telling you the object
is wrong — and (a) pays for spec stability with permanent structural
debt. But this is the maintainer's call, and `13-USER-rulings.md` asks
it.

Then, whichever option is chosen:

1. Extract input discovery to
   `lib/ammitto/harmonize/input_discovery.rb`. It is already
   source-generic — `data_repo_names` builds
   `data-#{source}` names by string interpolation and the data-cn /
   data-jp knowledge in `candidate_input_dirs`'s
   `sources/sanction-lists` comment and `resolve_yaml_files`'s
   `(data-cn format)` / `(data-jp)` comments is in comments only.

   Two things in here are order-sensitive and are the only realistic way
   this card could move an exported byte. Name them in the PR body and
   pin them with a spec before extracting:

   - `find_supplement_dirs(subdir)` iterates `@sources` in
     **requested order** and takes the first match. Its own comment
     beginning `Resolve every supplement subtree` and the
     `requested-source order` return contract show that discovery
     depends on considerably more than `options[:sources_dir]` and
     `cache_dir`: it also reads the command's `@sources` **and their
     order**, `Config::Defaults::DATA_REPO_TO_SOURCE`, and
     `options[:input_dir]`. Enumerate all of them in the
     collaborator's constructor; a collaborator that rebuilds the source
     list from `ALL_SOURCES` would silently select a different
     supplement directory, and supplements become exported nodes.

     Alternatively, leave `find_instruments_dirs`, `find_supporting_dirs`
     and `find_supplement_dirs` on the command and extract only the
     input-directory and YAML-file half. Note the first two are plural
     and return arrays: they stopped returning the first match when
     supplement loading was widened to every source's directory. That is the smaller, safer
     boundary, and it is the one to pick unless the full contract is
     written down first.
   - `yaml_files_in` globs `*.yaml` and `*.yml` as two
     patterns and concatenates them, so every `.yaml` file sorts before
     every `.yml` file regardless of name. That is the order
     `harmonize_source` ingests in, and ingestion order is load-bearing:
     `JsonLdGraphExporter#add_node`
     (`lib/ammitto/serialization/json_ld_graph_exporter.rb`) stores
     bodies **last-write-wins** (`@entities[entity_id] = entity`) while
     counting **first-seen**. So when two files carry the same `@id`,
     reordering them changes the exported body and leaves the count
     identical — the exact failure mode the tree diff exists to catch,
     and one no entity count would reveal. Preserve the pattern order
     exactly; "tidying" the two globs into one is an output change.
2. Extract health gating (15 methods) to
   `lib/ammitto/harmonize/health_gates.rb`. The design doc records these
   as already correctly caller-parameterized (L12, sanctioned, commit
   `18dd3f4`) — true of the *thresholds*, but the block is not
   state-free, and two details will bite:

   - `evaluate_gates` short-circuits on
     `@gates_evaluated_results.equal?(results)` — **object identity**,
     not equality — and then **mutates the result hashes in place**.
     `print_summary` calls it before `enforce_health_gates` does. A
     collaborator that copies the results array, or that is constructed
     twice, re-evaluates and re-mutates, and the printed classification
     can change even though no file on disk does.
   - It reads `options[:output_dir]` and `@exporter.stats`
     (via `attach_quality_metrics`), so it needs the exporter, not just
     the options.

   The thresholds `MIN_UNIQUE_ID_RATIO` and `MIN_NAMED_ENTITY_RATIO`
   move with them, with back-compat aliases pointing at the same values
   — task `01`'s snapshot fails otherwise.

   Because the risk here is **CLI output and exit status** rather than
   exported files (exports are written before the gate runs, in
   `harmonize_all`'s `@exporter.export` / `print_summary` /
   `write_report` / `enforce_health_gates` sequence), the tree diff will
   not catch a regression. Pin `print_summary`'s stdout and the exit
   status as golden fixtures before extracting.
3. **Extract reporting too. It is not optional, and the
   file-size target is why.** An earlier draft offered it as a choice
   while also demanding the file end under 400 lines. Those two
   statements are not compatible, and offering an option that fails the
   card's own "done when" is worse than picking one. Do the arithmetic
   from the derived post-Track-A figure:

   | | Lines |
   |---|---|
   | After Track A | ≈933 |
   | − input discovery | −252 |
   | − health gates with their leading comment block | −234 |
   | subtotal | **≈447** |
   | − reporting | −48 |
   | subtotal | **≈399** |
   | − `entity_to_hash` and `entry_to_hash` with their comments (step 4's first verify-then-remove) | −20 |
   | **result** | **≈379** |

   So discovery and gates alone land at ~447, comfortably over. Adding
   reporting lands at ~399 — under the target by a margin narrower than
   a class comment, which is not a margin. Only with step 4's
   verify-then-remove of the two serialization helpers does the file
   land at ~379 with real slack. **The intended boundary is therefore
   all three extractions plus that removal**, and the sub-400 target is
   the consequence of that boundary rather than an independent goal.

   Reporting is the extraction with the least structural argument behind
   it — printing genuinely is a command's job — so if the seam decision
   (option (a), shims) makes moving `print_summary`'s 7 pins
   unattractive, the honest move is to change the *target*, not to drop
   the extraction and keep the number. Say which you did in the PR body.

   Whichever way it goes: if reporting moves, acceptance is an exact
   stdout, stderr and exit-status golden captured before the move. Blank
   lines and label order are output.
4. Dispose of the code Track A leaves behind, each verify-then-remove
   and each its own commit:
   - `entity_to_hash` and `entry_to_hash` on the
     command, if `02` moved their bodies to the ingestion context and
     nothing else calls them. Grep-absence is not proof — check the CLI
     paths and the specs, and delete only with the reachability chain
     written into the PR body.
   - The dead `modifications:` and `announcement:` keys carried verbatim
     by `07` before the move. Nothing reads them today; prove that again
     after the move. This one is **not** a plain deletion:
     `transform_cn_modification` reads `result[:announcement]` while
     `Cn::Transformer#transform_modification`
     (`lib/ammitto/sources/cn/transformer.rb`) sets
     `official_announcement:`, so it has always been nil, and
     `legal_citations:` is not read at all. The choice is between
     deleting three keys nobody consumes and repairing a key that was
     meant to carry data — and repairing it would change what the result
     hash contains. Deleting is the output-neutral option and the
     default; repairing is a product question for
     `13-USER-rulings.md`, not a refactor.
5. Do not touch `ingest_results`. It is sanctioned (design doc L10) and
   it is the health-gate boundary. It is 30 lines and it is fine.

## Where

- `lib/ammitto/cli/harmonize_command.rb` — 1,459 lines / 74 methods now
  (measured at `0f8afc6`); ≈933 / 49 after Track A, derived above
- `MIN_UNIQUE_ID_RATIO` / `MIN_NAMED_ENTITY_RATIO` — the two ratio
  constants that move with the gates
- `enforce_health_gates` through `allowed_empty_sources` — health gates
  and quality floors, 15 methods; with their leading comment block the
  extractable span begins at the health-gates comment
- `find_input_dir` through `find_supplement_dirs` — input discovery, 14
  methods
- `data_repo_names` — proof the discovery layer is generic
- `transform_uk` through `transform_un_vessels` — the 26 methods Track A
  removes; `transform_data`'s case — what `08` deletes
- `entity_to_hash` and `entry_to_hash` with their comments — the
  serialization helpers Track A orphans
- `print_summary`, `print_source_problems`, `print_graph_totals` —
  reporting, 48 lines, 3 methods
- `ingest_results`, `entry_ids_by_entity`, `link_sanction_entry` —
  **out of scope**
- `spec/ammitto/cli/harmonize_command_spec.rb` and
  `spec/integration/harmonize_pipeline_spec.rb` — the 51 `send` pins
- Proposed: `lib/ammitto/harmonize/{input_discovery,health_gates}.rb`

## Done when

- The seam decision is recorded in the PR body with its reasoning, not
  implied by the diff.
- All three extractions landed — input discovery, health gates and
  reporting — and step 4's verify-then-remove of `entity_to_hash` /
  `entry_to_hash` is done. That is the boundary; the line count is its
  consequence.
- `wc -l lib/ammitto/cli/harmonize_command.rb` is under 400 (step 3's
  arithmetic puts it at ≈379), **or** the target was deliberately
  restated in the PR body with the boundary that was actually chosen.
  Do not report a number without saying which extractions produced it.
- The class's job can be stated in one sentence in its own class
  comment.
- `bundle exec rspec` green. If option (b) was chosen, every edited
  example is listed in the PR body with a before/after of what it
  asserts.
- `bundle exec rubocop` clean, with no new `.rubocop_todo.yml` entries.
- **Output is unchanged.** This card proposes no output change: every
  step is a relocation, and the two deletions are verify-then-remove of
  code nothing reads. Re-run the composed proof and the normalized
  full-tree diff against the Step 0 baseline; it must still be empty.
  If any step turns out to require an output change, stop and take it to
  `13-USER-rulings.md` — do not absorb it here.
- **The tree diff is necessary but not sufficient for this card.** Two of
  the three extractions put their risk somewhere the tree diff cannot
  see: the health gates decide CLI classification and exit status after
  the files are already written, and reporting is stdout. So acceptance
  also requires an exact stdout / stderr / exit-status golden for a
  representative run, captured before the first extraction. A card whose
  only gate is the tree diff would pass while `harmonize` started
  reporting a failed source as exempted.
- `spec/ammitto/public_api_spec.rb` (from `01`) passes, or its snapshot
  is regenerated with the change explained in the PR body.
- Each extraction is its own commit with its own justification, per
  `README.md`'s Track B rule.

## Size and dependencies

**L** — 2 to 4 days. The extraction itself is a day; the rest is the 40
`send` pins and the two verify-then-remove dispositions, where the
evidence bar is "prove it is unreachable", not "grep found nothing".

Blocked by `08-delete-the-case.md` — the whole of Track A must be
**complete and sitting below this card in the stack** before it starts,
because this card edits the same file every Track A task edits and would
destroy the tree diff's meaning if interleaved. Not "merged": `README.md`
constraint 3 says nothing merges until the stack lands as one decision,
so the dependency is a position in the stack, not a merge event.

**Runs before `10`, not merely "not interleaved with" it.** Both edit
`harmonize_command.rb`, and `10` renames things whose final home this
card decides — there is no point naming a method well and then moving it
to a different class. Independent of `11`, which touches neither file.

## ADHD

- 🔴 Even after Track A, one class holds six jobs in ≈933 lines / 49 methods: orchestration, gates, discovery, ingestion, aggregates, reporting
- 🧨 51 spec `send` calls reach 14 private methods — extract naively and 51 examples go red; shim all 14 and the class stays wide
- 🔧 Extract `InputDiscovery` (252) **and** `HealthGates` (234) **and** reporting (48) — all three, not two plus an option — then verify-then-remove `entity_to_hash`/`entry_to_hash` (20); pick the seam option (shims / migrate specs / in-place) and record why
- ✅ File ≈379 lines (or the target restated with the boundary that was chosen), one-sentence class comment, suite + rubocop green, **tree diff still empty** — this card changes no output
- ⛓️ Blocked by all of Track A (08); the seam choice is a question in 13
- 📦 L — 2–4 days, most of it in the 51 pins and two verify-then-removes
