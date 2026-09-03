# Move cn ingestion and route the group side-channel through the context

## Why this matters

cn is the third source the maintainer named, and it is structurally
unlike every other one. Three things happen in `transform_cn`
(`lib/ammitto/cli/harmonize_command.rb`) that happen nowhere else in the
file:

1. **One file becomes many results.** A cn announcement carries several
   entities, so `transform_cn_announcement` zips
   `result[:entities]` against `result[:entries]` and returns an
   **Array** of pairs. `ingest_results` is built for that —
   its array handling and its designed-nil-skip are shaped by cn
   (design doc L10, sanctioned, "STAY untouched").
2. **A side channel to the exporter.** `transform_cn_announcement` calls
   `@exporter.add_group(result[:group], source: :cn)` directly, out of
   band from the entity/entry return value. This is the only place in
   any transform method that writes to the exporter. It is why `02`'s
   context facade has an `add_group` at all, and why that method is
   documented **cn only**.
3. **A designed no-op result.** `transform_cn_modification`
   returns `entity: nil, entry: nil` on purpose — a
   measure modification is not an entity — and `ingest_results`
   skips it silently. That silence is correct and must stay silent.

There is a fourth thing, and it is the one to be careful with. The
modification result also carries `modifications:` and
`announcement:`. **Nothing reads them.** `ingest_results` only
touches `r[:entity]` and `r[:entry]`; a grep across `lib/`
and `spec/` finds no other consumer. They are dead keys.

And one of them is worse than dead.
`transform_cn_modification` reads `result[:announcement]`, but
`Cn::Transformer#transform_modification` returns
`official_announcement:` — see
`lib/ammitto/sources/cn/transformer.rb`, which returns exactly
`official_announcement:`, `modifications:` and `legal_citations:`. So
the `announcement:` field in `transform_cn_modification` has **always
evaluated to nil**: it reads a key the transformer never sets.
(`legal_citations` is not read at all.)

Carry all of it anyway, unchanged. Deleting dead code inside a move-only
commit is exactly the "while I'm here" edit the design doc's implementer
obligations forbid, and fixing the key would be worse — it would turn a
nil into a real object inside a commit whose diff is supposed to prove
nothing changed. Move it wrong-key and all, **label the defect in the
PR body**, and take it to `09-REFINE-harmonize-command.md`, where the
disposition question is a real one: the choice is between deleting three
keys nobody reads and repairing a key that was meant to carry data.

**cn is the least spec-covered move in Track A.** The robustness suite's
`source_fixtures` table (`spec/integration/ingestion_robustness_spec.rb`)
covers fourteen sources and omits cn entirely, and no spec anywhere
calls `transform_cn`, `transform_cn_announcement` or
`transform_cn_modification`. A green suite proves almost nothing here.
The export byte-diff over data-cn is the gate.

## What to do

1. Move all three methods to `lib/ammitto/sources/cn/ingestion.rb` in
   one commit: `transform_cn`,
   `transform_cn_announcement`,
   `transform_cn_modification`, with their comment blocks.
2. Replace `@exporter.add_group(result[:group], source: :cn)` in
   `transform_cn_announcement` with `ctx.add_group(result[:group])`.
   The context was built knowing its source code and forwards `source:`
   itself — the exporter's signature
   (`lib/ammitto/serialization/json_ld_graph_exporter.rb`) still
   receives exactly `(group, source: :cn)`. Keep the `if result[:group]`
   guard.
3. Keep the legacy-format raise verbatim, message included:
   `'Unsupported CN source format (expected announcement-based YAML)'`
   together with the comment explaining that
   `Cn::SanctionedEntity` was removed with `cn/sanctions_list`. That
   message reaches an operator through the per-file error collector.
4. Carry `modifications:` and `announcement:` unchanged, including the
   `rescue StandardError` inside the `map` block, and including
   `announcement:`'s wrong key. Add a line to the PR body naming the
   defect (`transform_cn_modification` reads `:announcement`;
   `lib/ammitto/sources/cn/transformer.rb` sets
   `:official_announcement`) so it is recorded as known-and-deferred
   rather than unnoticed.
5. Preserve the shape-dispatch order in `transform_cn`: `announcement` +
   `sanction_details` first, then `announcement` +
   `measure_modifications`, then the raise. A file carrying all three
   keys goes down the announcement path today and must keep doing so.
6. Register `cn` in `INGESTERS`.
7. Add a cn ingestion unit spec (additive) — the first direct coverage
   this path has ever had: an announcement with two entities returns two
   pairs and calls `add_group` once; a modification returns a nil pair
   and calls `add_group` zero times; an unrecognised shape raises with
   the exact message.

## Where

- `lib/ammitto/cli/harmonize_command.rb` — the three methods
  and their comments
- `transform_cn_announcement` — the `@exporter.add_group`
  side channel
- `transform_cn_modification` — the dead
  `modifications:` / `announcement:` keys
- `ingest_results` in `lib/ammitto/cli/harmonize_command.rb`,
  whose array handling and nil-skip exist for this source; **must not be
  edited**
- `lib/ammitto/serialization/json_ld_graph_exporter.rb` —
  `add_group(group, source:)`, the facade's target
- Destination: `lib/ammitto/sources/cn/ingestion.rb`, plus its
  `INGESTERS` entry
- `spec/integration/ingestion_robustness_spec.rb` — the fixture
  table that has no cn row
- `00-golden-baseline.md` step 6 — the per-input-file ingestion-result
  manifest this card's skip criterion reads; without it that criterion
  is uncheckable and this task is **BLOCKED**

## Done when

- `grep -n 'def transform_cn' lib/ammitto/cli/harmonize_command.rb`
  returns nothing, and all three methods are defined in
  `lib/ammitto/sources/cn/ingestion.rb`.
- The three moved bodies differ from their originals only by the
  substitutions enumerated in `03-trivial-wrappers.md` — extract,
  substitute, `diff -u`, empty. That check is what proves the three
  comment blocks and both dead keys came through intact; do not assert
  "comments included" by reading.
- `git diff --exit-code <task-base>..<task-head> -- <ingest_results
  extract>` is clean. Extract the method from both revisions; the file
  itself changes in this task, so a whole-file diff proves nothing.
- No `@exporter` reference remains in any file under
  `lib/ammitto/sources/`; `grep -rn '@exporter' lib/ammitto/sources/`
  returns nothing.
- `bundle exec rspec` green, no existing spec file edited.
- **Export byte-diff over data-cn is empty**, and every group node in the
  Step 0 baseline is present with an identical body.
- The silent modification skips are unchanged. **This is not observable
  from the exported tree** — a skipped file produces no node naming its
  input, so nothing downstream distinguishes "skipped" from "never
  seen". Check it against the **per-input-file ingestion-result
  manifest** that `00-golden-baseline.md` step 6 captures: re-capture it
  here and diff the data-cn rows. Every modification file that was a
  designed nil-pair skip at Step 0 must still be one, with the same
  `results_returned` and the same zero ingested; every announcement file
  must still return the same number of pairs. A row that changed from
  skip to error, or that vanished from the manifest entirely, is the
  regression this criterion exists to catch, and the tree diff would
  show neither.
- Normalized full-tree export diff against the Step 0 baseline is empty,
  per `00-golden-baseline.md`. **BLOCKED**, not passing, without the
  baseline and the pinned data-cn snapshot.

## Size and dependencies

**S** — a few hours of moving. The risk is disproportionate to the size:
this is the one Track A move where the existing suite would stay green
through a real regression, so budget the time in the data-cn export diff
rather than in the edit.

Blocked by `02-ingestion-scaffolding.md`, which must have shipped
`ctx.add_group`. Blocks `08-delete-the-case.md`. The dead-key disposition
goes to `09-REFINE-harmonize-command.md`, not here.

## ADHD

- 🔴 cn's array fan-out, exporter side-channel and designed no-op all sit in the CLI command
- 🧨 No spec anywhere calls `transform_cn` — a green suite proves nothing; only the data-cn byte-diff does
- 🔧 Move three methods verbatim; `@exporter.add_group` → `ctx.add_group`; dead keys ride along, including the bug in `transform_cn_modification` (reads `:announcement`, transformer sets `:official_announcement` — always nil). Carry it, label it, fix in 09
- ✅ Empty data-cn export diff, group nodes identical, `ingest_results` diff empty, no `@exporter` under `sources/`, data-cn rows in `00`'s per-input-file manifest unchanged
- ⛓️ Blocked by 02 (needs `ctx.add_group`) and by `00`'s per-input-file manifest (the skip criterion is uncheckable without it); blocks 08
- 📦 S — hours to move, the time is in the diff
