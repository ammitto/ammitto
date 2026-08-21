# Delete the 15-branch case and close Track A

## Why this matters

The fifteen-way `case` at `harmonize_command.rb`, `def transform_data`
is the thing
the whole track exists to remove. It has no knowledge in it — every
branch is `when :<code> then transform_<code>(transformer, data)` — and
it exists only because the registries never grew a hash-level entry
point (design doc L1). It is also the mechanism the maintainer's concern
was actually about: while it stands, adding source #16 means editing a
generic CLI command, and the next generic layer will accumulate its own
copy of the same list.

By the time this task starts, all fifteen branches call ingestion
modules and the case is pure ceremony. Deleting it turns
`transform_data` from a 42-line dispatcher into an ~8-line facade, and
turns "adding a source touches `sources/{code}/` plus the sanctioned
registries" from a claim into a fact.

This is also the task that closes Track A, so it carries the full
acceptance bar rather than a per-source one. Everything before it was
provable one source at a time; this is where the composed proof runs.

Two things must survive it, and both are easy to lose in a cleanup:

- **`ingest_results` is sanctioned and untouched.** Its
  array handling and its designed-nil-skip in `def ingest_results` are
  the health-gate
  boundary (design doc L10, "STAY untouched"). It looks adjacent to the
  work and it is not part of it. The `git diff` for this task must show
  it unchanged, and that is an acceptance criterion, not a habit.
- **The `transform_jp` shim survives.** Four examples call it directly
  (`spec/ammitto/cli/harmonize_command_spec.rb`, the `#transform_jp with
  an announcement that carries no ids` block) and Track A permits no
  spec edits. Deleting the shim here
  would fail the suite; deleting it *and* editing those four examples
  would violate the track's own rule. See `06-jp-ingestion.md` and
  `13-USER-rulings.md`.

## What to do

1. Replace the body of `transform_data` with the facade.
   Keep the ordering exactly as it is today: **transformer lookup first,
   nil-pair return if absent (the first `return { entity: nil, entry:
   nil }` in `def transform_data`), then ingester lookup, then
   nil-pair return if absent (today's final `else` in `def
   transform_data`).**

   Preserve that order because it is the current behaviour, not because
   a spec catches it — **no existing spec does.** The recorder at
   `spec/integration/ingestion_robustness_spec.rb`, the
   `Transformers::Registry.get` recorder example, stubs
   `Transformers::Registry.get` for every source and never exercises an
   unregistered one, so both orders pass it. `02` adds the spec that
   makes the order a contract; confirm it is present and asserting
   before relying on it here.
2. Delete the `case`. Nothing else in the method changes:
   the lazy `require_relative '../transformers/registry'` in
   `def transform_data` stays
   where it is.
3. Leave the `transform_jp` shim in place, and leave
   `guard_announcement_format!`'s delegation from `02` in place.
4. Run the grep gate and put its output in the PR body, not in a private
   check:

   ```bash
   grep -nE '\b:(uk|eu|un|us|wb|au|ca|ch|cn|ru|nz|tr|jp|eu_vessels|un_vessels)\b' \
     lib/ammitto/cli/harmonize_command.rb
   ```

   Every remaining hit must be a comment. **The shim needs no exemption**
   — the gate matches symbol literals such as `:jp`, and the shim's name
   is `transform_jp`, which is not one. The design doc's talk of
   exempting the shim from this gate is confusion carried forward; do
   not write an exception into the grep for something it never matched.

   The discovery layer was checked and is clean: it builds
   `data-#{source}` names generically in `data_repo_names`, and its
   country-specific references in nearby comments are all comments, not
   branches.
5. Run the composed proof in the operator environment, with the data-*
   siblings present. Not in gem CI — CI has no data repos and cannot
   arbitrate this.
6. Diff the full normalized export tree and **all three** manifests
   against the Step 0 baseline — entity `@id`, entity→entry edge, and
   the per-input-file ingestion-result manifest
   (`00-golden-baseline.md` step 6). The third one is the only
   instrument that sees a designed skip turning into an error, or an
   input file silently ceasing to be read; the tree shows neither.

## Where

- `lib/ammitto/cli/harmonize_command.rb` — `transform_data`;
  the two nil-pair returns inside `def transform_data` must both survive
- `lib/ammitto/cli/harmonize_command.rb` — the case to delete
- `lib/ammitto/cli/harmonize_command.rb` — `ingest_results`,
  must be untouched
- `lib/ammitto/cli/harmonize_command.rb` — the `transform_jp` shim
  left by `06`
- `lib/ammitto/ingestion/registry.rb` — the `INGESTERS` map the facade
  looks through
- `spec/integration/ingestion_robustness_spec.rb` — the
  `Transformers::Registry.get` recorder stub. It does **not** make
  lookup order observable, and an earlier draft of this card labelled it
  as if it did, contradicting step 1 above: it stubs every source, so it
  never reaches an unregistered one and both orders pass it. It is
  listed here because `02`'s new order spec has to sit beside it without
  disturbing it
- `00-golden-baseline.md` step 6 — the per-input-file ingestion-result
  manifest this card's acceptance compares corpus-wide

## Done when

- `transform_data`'s body is exactly five steps — transformer lookup,
  nil-pair guard, ingester lookup, nil-pair guard, ingester invocation —
  and contains no source-code literal. State the structure, not a line
  count: "~8 lines" is a formatting fact and cannot fail a review.
- The grep gate returns only comments. Paste its output.
- `git diff --exit-code <track-a-base>..HEAD -- <ingest_results extract>`
  is clean. Name the Track A base commit; extract the method from both
  revisions rather than diffing the whole file, which this task edits.
- `bundle exec rspec` green, and **no existing spec file was edited
  anywhere across `02`–`08`**. Verify that every path in
  `git diff --name-only <track-a-base>..HEAD -- spec/` was added by this
  stack (`git log --diff-filter=A`), not modified.
- `02`'s registry-completeness assertion is now switched on and green:
  every one of the 15 codes in `Config::Defaults::ALL_SOURCES` resolves
  in `INGESTERS`, and every registered module is covered by the opacity
  shared example.
- Composed proof in the operator environment: `harmonize` exits 0,
  `verify` exits 0, and the entity count equals **the number Step 0
  recorded** — not a literal carried from an older document. See
  `README.md`, "Acceptance, and the number that used to be wrong".
- Normalized full-tree export diff against the Step 0 baseline is empty,
  and **all three** sorted manifests — every entity `@id`, every
  entity→entry edge, and every per-input-file ingestion result — are
  identical. The third is not optional here: `07` checks only the
  data-cn rows, so this card is the first and only place the whole
  corpus's skip/error classification is compared. Run
  `00-golden-baseline.md`'s
  normalization; **BLOCKED**, not passing, if the baseline or the pinned
  sibling-repo snapshots are absent.
- Guard refusal messages and `ammitto sources` output are byte-identical
  to their golden pins, compared as exact strings.
- `require "ammitto"` still loads no ingestion files: assert the set of
  loaded per-source ingestion constants is exactly empty.

### Baseline hazard to check before blaming the diff

If the full-tree diff comes back non-empty, rule this out **before**
bisecting `03`–`07`. `Wb::Transformer#determine_status`
(`lib/ammitto/sources/wb/transformer.rb`, `def determine_status`)
compares
`debar_to_date` against `Date.today`, and that value is exported: it
becomes `entry.status` (`json_ld_serializer.rb`, the `status` field
serialization), a search-index row
and status facet (`search_index_exporter.rb`, the status export paths),
and a `by-status/{status}.jsonld` slice whose **filename is the status**
(`json_ld_graph_exporter.rb`, the `by-status` export code). A WB
debarment expiring between
the baseline capture and this run changes the tree with no code change
at all — and it is a semantic transition, so no timestamp normalization
can absorb it.

`00-golden-baseline.md` step 1 makes this impossible rather than
detectable: the capture and every comparison run under a preloaded
`Date.today` pinned to the `AS_OF_DATE` recorded in the input manifest,
and the pin helper raises if that value is missing or malformed. So the
check here is not "did the date move" but "did this run actually use the
pin" — confirm the helper was loaded and the `AS_OF_DATE` matches the
manifest before treating a non-empty diff as a regression. A run that
somehow bypassed the pin is not evidence of anything and must be
repeated, not interpreted.

## Size and dependencies

**S** — a few hours of editing. The task is small; the *gate* is not.
Budget separately for running the composed proof and the tree diff in
the operator environment, and for the review-and-rework round the design
doc explicitly budgets for. If the tree diff comes back non-empty, the
cost is bisecting `03`–`07`, which is why those were nine, three, one,
one and one commits rather than five.

Blocked by `03`, `04`, `05`, `06` and `07` — all fifteen sources must
already route through `INGESTERS`. Blocks all of Track B: `09`, `10` and
`11` sit on top of a completed Track A and are meaningless before it.

## ADHD

- 🔴 A 15-branch `case` with no knowledge in it; source #16 still edits a generic CLI command
- 🧨 Delete it carelessly and you also "tidy" `ingest_results` or drop the jp shim — one breaks the health-gate boundary, the other breaks four specs
- 🔧 `transform_data` becomes an ~8-line facade: transformer lookup, then ingester lookup, both nil-pair fallthroughs, order preserved
- ✅ Grep gate clean, `ingest_results` diff empty, composed proof green against Step 0's own count, empty tree diff + all THREE manifests identical (incl. per-input-file results — the only corpus-wide skip/error check)
- ⛓️ Blocked by 03–07; unblocks all of Track B
- 📦 S to edit, but this is where the full acceptance bar runs
