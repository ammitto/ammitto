# Move ch ingestion: guard first, then shape dispatch

## Why this matters

ch is one of the three sources the maintainer named by hand as needing
its own module, and it is the one whose logic is most obviously a fact
about the source rather than about the command. `transform_ch`
(`lib/ammitto/cli/harmonize_command.rb`) exists because
`fetch ch` and the ch model layer disagree about what a record is:
`Ch::SanctionsList#all_identities` returns parsed `<target>` elements
despite its name, so every file committed to data-ch is a target
wrapper, while the model that reads a bare `<identity>` is a different
class.

The comment inside `transform_ch`, the one beginning "SanctionsList
#all_identities returns `targets`", records what happens when that is
guessed wrong: a Target-shaped hash forced through `Identity.from_hash`
produces an Identity whose every attribute is nil, and `Identity#person?`
then raises `NoMethodError` on `nil.names`. That is not a style note. It
is the reason `ch_target_shape?` decides by the record's own shape
instead of by the method's name, and the design doc classes it
**policy — source-format-compatibility (L6)**: the content moves, the
decision does not get revisited.

Order inside the method is load-bearing too. The `guard_announcement_format!`
call is the first statement after the `require_relative`, **before** the
shape dispatch, with the expected-schema string
`'Ch::Identity or Ch::Target'`. Reversing them would send a
data-cn announcement file into `ch_target_shape?` first, and the refusal
message would change — which three separate spec groups would catch, and
which is exactly the kind of silent reordering a "tidy" move introduces.

ch is the most heavily pinned guard path in the suite: it appears in the
`%i[ch us uk]` refusal loop
(`spec/integration/ingestion_robustness_spec.rb`, under
`describe 'announcement-format guards (ch/us/uk)'`), it is the source
used for all three lone-marker-key examples, and it is the source of the
end-to-end example that proves a refusal surfaces as a non-zero exit with
per-file attribution.

## What to do

1. Move `transform_ch` to
   `lib/ammitto/sources/ch/ingestion.rb`. Keep the statement order
   exactly: `require_relative` for the model, then
   `guard_announcement_format!`, then the shape dispatch, then the
   transformer call, then the pair.
2. Move `ch_target_shape?` with it — including the comment directly
   above it, which is the only written record of what
   distinguishes the two shapes (`individual` / `entity` /
   `sanctions_set_id` at the top level versus `names` and
   `day_month_year`). It is a private helper of the ch path and has no
   other caller; confirm that with a grep before moving, not after.
3. Move the all-nil-crash comment verbatim. It is the tombstone of a
   real crash and the justification for the whole method.
4. Route the guard call through `02`'s
   `Ammitto::Ingestion::AnnouncementFormat`. The `expected:` string
   stays `'Ch::Identity or Ch::Target'` character for character — the
   refusal message interpolates it.
5. Register `ch` in `INGESTERS`.
6. Add a ch ingestion unit spec (additive): a target-shaped hash builds
   `Ch::Target`, a bare identity hash builds `Ch::Identity`, and an
   announcement-shaped hash raises before either class is touched.
7. Full suite. One commit.

## Where

- `lib/ammitto/cli/harmonize_command.rb` — `transform_ch`, containing in
  order: the `require_relative`, the `guard_announcement_format!` call and
  its `expected:` string, the all-nil-crash comment, and the shape dispatch
- `lib/ammitto/cli/harmonize_command.rb` — `ch_target_shape?` and the
  comment directly above it
- Destination: `lib/ammitto/sources/ch/ingestion.rb`, plus its
  `INGESTERS` entry
- `spec/ammitto/cli/harmonize_command_spec.rb` — `context 'with a ch
  record'`; five examples entering at `transform_data`, covering
  target-wrapping-a-person, target-wrapping-an-entity, ssid keying, and
  the bare-identity fallback
- `spec/integration/ingestion_robustness_spec.rb` — under
  `describe 'announcement-format guards (ch/us/uk)'`: the `%i[ch us uk]`
  refusal loop, the three lone-marker examples (all `:ch`), and the
  end-to-end non-zero-exit example

## Done when

- `grep -n 'def \(transform_ch\|ch_target_shape?\)'
  lib/ammitto/cli/harmonize_command.rb` returns nothing, and both are
  defined in `lib/ammitto/sources/ch/ingestion.rb`.
- Both moved bodies differ from their originals only by the
  substitutions enumerated in `03-trivial-wrappers.md` — extract,
  substitute, `diff -u`, empty.
- `bundle exec rspec spec/ammitto/cli/harmonize_command_spec.rb
  spec/integration/ingestion_robustness_spec.rb` green, with no existing
  spec file edited (same diff gate as `02`).
- The `:ch` refusal message is **byte**-identical. The existing pins are
  regexes (the refusal loop matches
  `/announcement-format YAML detected.*ch/m`; the lone-marker examples
  match `/top-level <marker>\b/`) and a regex
  cannot establish byte identity — capture the raised message before and
  after and compare the full strings, for the source case and for all
  three markers.
- The end-to-end example still raises `Thor::Error` with a
  message naming `20261101.yaml`; run that example by name and record it.
- Normalized full-tree export diff against the Step 0 baseline is empty,
  per `00-golden-baseline.md`. **BLOCKED**, not passing, without the
  baseline and the pinned snapshots.

## Size and dependencies

**S** — a few hours. One method plus one private helper, one commit, no
array fan-out and no side channel. The only real work is confirming
`ch_target_shape?` has no other caller and that the guard stays first.

Blocked by `02-ingestion-scaffolding.md`. Blocks
`08-delete-the-case.md`. Independent of `03`, `04`, `06` and `07`.

## ADHD

- 🔴 ch's two-shape knowledge sits in the CLI: `all_identities` returns targets, not identities
- 🧨 Wrong class = an all-nil Identity, then `NoMethodError` on `nil.names`; reordering the guard changes a pinned refusal message
- 🔧 Cut-paste `transform_ch` + `ch_target_shape?` + both comments; guard stays first with `'Ch::Identity or Ch::Target'` intact
- ✅ ch context (5 examples) and all guard pins green untouched; empty tree diff
- ⛓️ Blocked by 02; blocks 08
- 📦 S — hours
