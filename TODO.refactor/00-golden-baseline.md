# Capture the golden baseline before any code moves

## Why this matters

This refactor's failure mode is silent. The whole point of moving each
source's ingestion into its own module is that no output changes — and
the suite cannot tell you whether that held. A run can exit 0, publish
the same number of entities, pass every spec, and still have changed
every `jp` IRI, because nothing in the test suite asserts what the
exported corpus looks like.

The only instrument that catches it is a full export taken before the
first line moves, kept, and diffed against every later export. That is
this task. It produces no product change and is the single most
important step in the board — the 2026-08-06 design doc says so in as
many words, and its reasoning stands.

Four things it must fix from that doc. The first two were found in the
2026-08-10 revalidation; the last two in the 2026-08-11 board review.

**The acceptance count was dead.** The doc pinned "25,128 entities".
The corpus is now roughly 60,901 across 13 sources, so that literal
would fail the gate for reasons unrelated to the refactor. Replacing it
with 60,901 rots identically the next time a data repo grows. The count
must become *whatever this task records*, not a number written into a
plan. (Neither figure is verifiable from the gem checkout — no `data-*`
siblings are present here. Both are quoted from the revalidation and
are recorded as claims to re-derive at capture time.)

**The baseline pinned only one side of the input.** A gem commit alone
does not determine the output — the data repos do too, and they commit
daily. A baseline that does not name every input SHA gates nothing,
because a later diff cannot distinguish "the refactor broke it" from
"data-eu fetched overnight".

**Thirteen sources cannot gate fifteen moves.** `ALL_SOURCES`
(`lib/ammitto/config/defaults.rb`) names fifteen codes and
`DATA_REPO_TO_SOURCE` names fifteen data repositories. Track
A moves all fifteen. A baseline covering thirteen of them leaves two
sources whose move has no gate at all, and an empty tree diff over the
thirteen would be read as proof for all fifteen. Step 7 below closes
that: every source Track A touches gets a baseline fixture or an
explicitly recorded blocked state, and there is no third option.

**The normalization contract was prose, not paths.** "Transformer-
emitted `retrievedAt`" is not a rule a script can apply. Deleting every
`retrievedAt` in the tree would also delete any that a source supplied
in its own data — hiding exactly the kind of change this gate exists to
catch. Step 3 names the JSON paths and replaces values instead of
removing keys, so a key that appears or disappears still shows up as a
difference.

## What to do

1. **Pin the effective date first. Normalization cannot reach it, and
   the preflight is invalid without it.**

   `Wb::Transformer#determine_status`
   (`lib/ammitto/sources/wb/transformer.rb`) returns `'expired'`
   when `parse_wb_date(firm.debar_to_date) < Date.today`. That status is
   not a timestamp inside a file — it becomes a **filename**
   (`by-status/{status}.jsonld`, built at
   `json_ld_graph_exporter.rb`) and changes set membership in the
   status facets and search index rows.

   So a World Bank debarment lapsing overnight rewrites the tree with no
   code change whatsoever, and no timestamp-stripping absorbs it because
   it is a semantic transition, not a stamp. A baseline taken on Monday
   and diffed on Tuesday can fail for a reason that has nothing to do
   with the refactor — and worse, it can fail in a way that *looks*
   exactly like the identifier drift this gate exists to catch.

   **Pin it, do not enumerate around it.** The method:

   - The capture script writes `AS_OF_DATE` into the input manifest
     (step 5) and preloads a small Ruby helper that redefines
     `Date.today` to that date, then loads `exe/ammitto` **in the same
     process** — e.g. `ruby -r<pin helper> exe/ammitto harmonize …`.
     `Date.today` is a singleton method on `Date`, so the override is
     process-local and touches no production file.
   - The helper **raises** if `AS_OF_DATE` is absent, unparseable, or
     not `YYYY-MM-DD`. A missing pin must abort the run, never silently
     fall back to the real clock — a baseline that quietly un-pinned
     itself is worse than no baseline.
   - Every later comparison run uses the same helper and the same
     `AS_OF_DATE` read back out of the manifest.
   - Do **not** pin `Time.now`. The three clock-derived stamps are
     handled by normalization (step 3), and pinning them would make the
     normalization rule untestable — a pinned `Time.now` produces
     identical bytes whether or not the code still emits the field.

   An earlier draft of this card left pinning as "preferred, but
   enumerate the near-expiry WB entities if it proves impractical". It
   is not impractical; the enumerated-exception fallback is withdrawn,
   because an enumerated exception is one more thing a later run gets
   wrong silently.

   **The clock reads on the harmonize/export path, enumerated at
   2026-08-11:**

   | Site | Read | Disposition |
   |---|---|---|
   | `json_ld_graph_exporter.rb` (in `#initialize`; written by `#export_stats`) | `Time.now` | normalize `stats.json` `generated_at` |
   | `search_index_exporter.rb` (in `#export_search_index`) | `Time.now` | normalize `metadata.generated` |
   | `sources/{jp,nz,tr,eu_vessels,un_vessels}/transformer.rb` | `Time.now` → `retrieved_at` | normalize `$.sourceReferences[*].retrievedAt` |
   | `sources/wb/transformer.rb` (`#determine_status`) | `Date.today` | **pin** — semantic, not a stamp |

   `Wb::SanctionedFirm#active?` (`sources/wb/sanctioned_firm.rb`)
   also reads `Date.today`, but no harmonize-path caller was found:
   `lib/ammitto/serialization/`, `lib/ammitto/exporter/` and
   `lib/ammitto/cli/harmonize_command.rb` call none of `active?`,
   `expired?`, `current?` or `days_until_expiry`. The same check clears
   `lib/ammitto/identification.rb`, `lib/ammitto/entity_link.rb` and
   `lib/ammitto/temporal_period.rb`, whose only in-`lib` caller is
   `lib/ammitto/sanction_entry.rb`, itself uncalled from the export
   path.

   Full paths, not basenames: all four names exist twice, once in the
   flat `lib/ammitto/` layer the transformers instantiate and once under
   `lib/ammitto/ontology/`. A grep on the basename alone lands in the
   wrong layer half the time, and this card is the safety gate — every
   symbol it names has to resolve to one thing.

   This table was **missed** by the 2026-08-06 design doc and by the
   2026-08-10 revalidation, both of which called the three-path
   normalization list complete. Treat "the volatile list is complete" as
   a claim to re-derive at capture time, not a settled fact — including
   this table.

2. **Determinism preflight.** With the date pinned, run harmonize and
   verify twice from clean state into two separate empty output
   directories. Normalize both, then diff. If they differ anywhere
   outside the values named in step 3, STOP — a nondeterministic
   baseline gates nothing, and fixing determinism becomes the task
   instead. Do not proceed on the theory that the difference looks
   harmless.

3. **Normalize exactly these values, by substitution — never by
   deleting a key.** Replace each with a fixed sentinel (e.g. the string
   `"NORMALIZED"`), so that a field appearing or disappearing is still a
   visible difference. Anything else that differs is a failure, not
   noise:

   | File | JSON path | Emitted by |
   |---|---|---|
   | `stats.json` | `$.generated_at` | `json_ld_graph_exporter.rb` |
   | `search-index.json` | `$.metadata.generated` | `search_index_exporter.rb` |
   | every entity node file, `sources/{code}.jsonld`, and `all.jsonld` | `$.sourceReferences[*].retrievedAt` (and the same path under `$.@graph[*]` in the aggregates) | `json_ld_serializer.rb`, reached from `#serialize_entity` |

   Three constraints on that third row, all verified in the tree:

   - **Only that path.** `retrievedAt` is emitted in exactly one place,
     `#serialize_source_references`,
     and entries carry no `sourceReferences` at all — `#serialize_entry`
     has no such key. A `retrievedAt` anywhere else in the
     tree is either source-supplied data or a new code path, and either
     one is a difference the diff must report.
   - **Only five sources put a clock value there.** `retrieved_at` is
     set from `Time.now` by jp, nz, tr, eu_vessels and un_vessels only.
     For the other ten, `.compact` drops the field entirely, so its
     *presence* is itself a change worth failing on — which is why the
     rule replaces rather than deletes.
   - **`all.ttl` is not JSON.** Normalize it by literal substitution of
     the same captured timestamp strings, and confirm in the preflight
     that its serialization order is stable; it is generated from
     `all.jsonld` by `TurtleExporter.export`
    .

4. **Define "the full export tree" literally, and require `--combine`.**
   The tree is everything under `--output-dir`:

   - `node/{entity,entry,legal-instrument,regime,authority,group,document-type,organization}/`
     — every node file and every `index.jsonld`. Eight directories,
     written by `export_entity_nodes` through `export_organization_nodes`
     and indexed by
     `export_index_files`.

     **`node/list/` is created and never written.** `create_directories`
     makes nine directories but the ninth,
     `File.join(@output_dir, 'node', 'list')`, has no writer:
     no `export_list_nodes` exists and `export_index_files` emits eight
     indexes, not nine. So the baseline holds an empty `node/list/` and
     the comparison must treat "empty directory, still present" as the
     expected state. Do not write a completion criterion demanding node
     files or an index there — it would be unsatisfiable. Note also that
     an empty directory is not a git-trackable artifact, so if the
     baseline is stored in git the comparison has to assert the
     directory's emptiness some other way (a recorded listing) rather
     than by its presence in a checkout.
   - the slice indexes `by-authority/`, `by-regime/`, `by-list/`,
     `by-status/`, `by-type/`, and `by-organization/` and
     `by-document-type/`, which the page-slice work added later and
     which an earlier draft of this card omitted. Seven families, not
     five: a baseline that lists five would let a refactor drop the two
     page-slice trees and still pass its own gate.
   - `index.jsonld`, the root catalogue naming every published artefact
     with its media type and byte size (`export_manifest`). It is
     written LAST, after the search index and the ontology, so a
     comparison that snapshots the tree mid-export will not see it.
   - `stats.json` and `context.jsonld`
   - `sources/{code}.jsonld`, the per-source aggregates
    
   - `search-index.json` and the
     `facets/` directory
   - `ontology/classes.jsonld`, `ontology/properties.jsonld`,
     `ontology/hierarchy.json` and `ontology/examples/*.jsonld`
    
   - `all.jsonld` and `all.ttl`

   That last line is conditional and the condition is easy to miss.
   `export_aggregated_files` runs only `if @combine`; and
   `harmonize_command.rb` sets
   `combine: options[:combine] == true`; and `lib/ammitto/cli.rb`
   declares `option :combine, type: :boolean, default: false`. So
   **without `--combine` there is no `all.jsonld` and no `all.ttl`**,
   and a criterion elsewhere in the board that names `all.jsonld` would
   be checking a file that was never written. **`--combine` is mandatory
   for the baseline run and for every comparison run**, and the manifest
   records the exact argv.

5. **Pin every input in a manifest** committed alongside the baseline:
   gem commit SHA; Ruby version and `Gemfile.lock` digest; the included
   source set; the exact argv (including `--combine`); `AS_OF_DATE`; and
   the commit SHA plus path of every participating data repository.
   Without this the baseline is unreproducible.

6. **Stash the artifacts**: the normalized full export tree as defined
   in step 4, plus three sorted manifests —

   - every entity `@id`;
   - every entity→entry edge;
   - **a per-input-file ingestion-result manifest** (new, and required
     by `07-cn-ingestion.md`). One row per input YAML file, keyed by the
     file's path relative to its source's input directory, carrying:
     source code, how many results `transform_data` returned (1, or N
     for an array), how many pairs were ingested, how many were
     designed nil-pair skips, how many were rejected as invalid, and the
     exact text of any per-file error. Counts, not a verdict — see below.

   That manifest is the only thing that can prove a *designed* skip
   still happens. A skipped file produces no node naming it, so the
   exported tree cannot distinguish "skipped as designed" from "never
   read" — and cn's `transform_cn_modification` skip is exactly that
   case.

   **Capture it without touching production code — and classify, do not
   infer.** Most of the facts live in
   `ingest_results(result, source, source_graph, errors, filename)` in
   `harmonize_command.rb`: it receives the filename and the
   transform result, returns the number ingested, and appends to the
   error collector. A module prepended by the same preload helper that
   pins the date records a row per call.

   That alone is not enough, and the gap is the kind that produces a
   confidently wrong manifest. **Two different outcomes both produce no
   `ingest_results` call**: a YAML file that parses to nil or false is
   dropped by `next unless data` in `harmonize_command.rb`, right after
   the load, and a file whose load or transform raises is caught by the
   per-file `rescue` in the same loop. "No row means it was a designed
   skip" is
   therefore **false** — it would silently reclassify every errored
   input as a skip, which is precisely the distinction `07` needs.

   So record the classification directly rather than deducing it from
   absence. The preload prepends three things:

   - `YAML.safe_load_file` (on the `YAML` singleton) — one record per
     input path: the value's truthiness, or the class and message of the
     exception it raised. That separates parse-to-nil from load failure
     with no inference at all.
   - `harmonize_command.rb`'s `transform_data` — one record per
     file that got past the nil guard, so a raise inside transform is
     attributable to its file rather than to the source.
   - `ingest_results` — the row: results returned, pairs
     ingested, designed nil-pair skips, and the error strings it
     appended.

   Wrap `find_input_dir` as well, to record the discovery list.

   **A row is a set of counts, not a single verdict.** One cn
   announcement file legitimately produces ingested pairs *and* designed
   nil-pair skips at once — `ingest_results` walks an array and
    skips the nil pairs inside it — so "each file lands in exactly
   one bucket" would be false for the very source that motivated this
   manifest. Each row therefore carries four independent numbers plus a
   list:

   `results_returned`, `ingested`, `skipped_nil`, `invalid` (the two
   error paths inside `ingest_results` — the non-Hash result branch and
   the incomplete entity/entry pair branch), and `errors[]` (the exact
   strings, including any raised out of the per-file `rescue` in
   `harmonize_source`).

   The single-verdict rule applies only to files with **no**
   `ingest_results` row at all, and there it is exact rather than
   inferred: the `YAML.safe_load_file` record says parse-to-nil or
   load-raised, and the `transform_data` record says whether the raise
   happened before or during transform. Every discovery-list path must
   be accounted for by one of those two shapes, and **a path accounted
   for by neither is a capture bug, not a fact about the corpus**. Make
   the script fail on that rather than emit a manifest with a hole.

   One hazard to record while you are there: the per-file error strings
   are prefixed with `File.basename(file)`, and `ingest_results` is
   handed a basename rather than a path, so two input files with the same
   basename in different subdirectories are indistinguishable in the
   error text. Key the manifest by the path relative to the source's
   input directory, and have the capture detect and report basename
   collisions instead of guessing which file an error belongs to.

   The entity count comes from `stats.json`, recorded as an output,
   never asserted as an input.

7. **Cover every source Track A moves — all fifteen.** For each code in
   `Config::Defaults::ALL_SOURCES`, the baseline
   directory holds either:

   - a baseline fixture: that source's slice of the normalized tree,
     its rows in all three manifests, and its data-repo SHA in the input
     manifest; **or**
   - an explicitly recorded blocked state naming the source, the reason
     (no `data-*` sibling, empty repo, source currently failing its
     health gate), and the date recorded.

   A source with neither is a hole in the gate, and this task is not
   done. A source in the blocked state means every Track A card that
   moves it reports **BLOCKED** for that source rather than passing —
   `03`, `04`, `05`, `06`, `07` and `08` all inherit this. Write the
   list into the baseline directory as a checked-in file so a later step
   reads it instead of re-deriving it.

8. **Record the suite result** as a number observed at this commit, not
   as a permanent constant. It was **1,458 examples, 0 failures, 4
   pending, 4.1s wall** at `0f8afc6` on 2026-08-11; the design doc's
   "1,349" is stale, and any number written here will be stale
   eventually too — say so where it is written. Note also what that
   timing means for the rest of the board: the suite is seconds, so
   "run the full suite after every commit" is free, and no card may
   price the suite as a cost.

9. **Script it, do not document it.** This card alone runs it three
   times (two preflight runs and one reproduce-from-pinned-inputs), and
   `02`–`08` run it once each — **ten runs before Track A closes**,
   before any rerun. A manual procedure will drift between runs and the
   drift will be invisible. See `12-tooling-scripts.md` item 1 — the
   capture, the date pin, the ingestion-result recorder and the diff
   belong in one committed script from the first use, not the third.

## Where

Line numbers are deliberately absent throughout this card. They moved
twice while this board sat unmerged, and a citation pointing at the
wrong line is worse than a name you have to grep for. Find each by
symbol.

- `lib/ammitto/serialization/json_ld_graph_exporter.rb` — the
  `generated_at` stamp, the `--combine` condition, the output
  directories, `all.jsonld` and `all.ttl`, `export_stats`, the
  `by-status/{status}.jsonld` filename, `context.jsonld`, and
  `export_manifest` writing the root `index.jsonld`.
- `lib/ammitto/serialization/search_index_exporter.rb` —
  `metadata.generated`, `search-index.json`, and the facets.
- `lib/ammitto/serialization/json_ld_serializer.rb` — the only emitter
  of `retrievedAt`, reached from `#serialize_entity`.
- `lib/ammitto/serialization/ontology_exporter.rb` — the `ontology/`
  subtree.
- `lib/ammitto/sources/wb/transformer.rb` — the `Date.today` read
  the pin exists for.
- `lib/ammitto/cli.rb` — `option :combine … default: false`.
- `lib/ammitto/cli/harmonize_command.rb` — `combine:` wiring;
  `write_source_aggregate` for the per-source aggregates; the two
  per-file skip paths; `ingest_results`, the recorder's seam;
  `find_input_dir`, the discovery list.
- `lib/ammitto/config/defaults.rb` — `ALL_SOURCES`, the fifteen
  codes step 7 must account for, and `DATA_REPO_TO_SOURCE`.
- The data repositories, as siblings of this checkout per
  `Config::Defaults`.

## Done when

- The date pin is in place: the helper raises on a missing or malformed
  `AS_OF_DATE`, and that refusal is demonstrated once before it is
  trusted.
- Two consecutive normalized exports from clean state are byte-identical.
- The manifest names every input SHA plus `AS_OF_DATE` and the exact
  argv, and a third run from those pinned inputs reproduces the same
  normalized tree.
- Every path listed in step 4 is present in the stashed tree, including
  `all.jsonld` and `all.ttl` — their absence means `--combine` was
  omitted and the baseline is incomplete, not merely smaller.
- Normalization replaced values and removed no keys: grep the normalized
  tree and confirm `retrievedAt` still appears wherever it appeared in
  the raw export, and nowhere else.
- All three manifests — entity `@id`, entity→entry edge, and per-input-
  file ingestion result — are present and sorted.
- Every one of the fifteen `ALL_SOURCES` codes has either a baseline
  fixture or a recorded blocked state, and the list is checked in.
- The recorded entity total came from `stats.json` and is written down
  as an observation with its date.
- Nothing about the product changed — `git diff` against `main` shows
  only the baseline tooling, and the pin and the recorder live in the
  preload helper, not in `lib/`.

## Size and dependencies

**M** — about a day, dominated by the two full 60k-entity exports and
by making normalization exact rather than approximate. The suite is not
part of that cost: it is 4.1s. **XL risk**: if the preflight fails,
fixing determinism is unbudgeted work that must happen before anything
else, and the design doc explicitly warns about this.

Blocked by nothing, but the capture script from `12-tooling-scripts.md`
item 1 ships *with* this task, not after it. **Blocks every Track A
task** (`02`–`08`). Pairs with `01-public-api-freeze.md`: this one
freezes the output, that one freezes the interface, and neither catches
what the other catches.

## ADHD

- 🔴 A refactor can change every IRI while the suite stays green and counts match
- 🧨 Silent identifier drift ships to a published sanctions API, uncaught
- 🔧 Pin `Date.today` via a preload helper, run twice with `--combine`, replace (never delete) 3 stamp paths, stash the tree + 3 manifests incl. per-input-file results, cover all 15 sources
- ✅ Two runs byte-identical; a third from pinned inputs reproduces them; every source has a fixture or a recorded BLOCKED
- ⛓️ Gate — blocks tasks 02–08; ships with `12` item 1; count is recorded, never asserted
- 📦 M — a day, XL if the preflight fails
