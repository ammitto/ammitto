# Stop hand-maintaining per-source metadata in two places

## Why this matters

The fifteen sources are enumerated, by hand, in four separate places on
the CLI path:

- `lib/ammitto/config/defaults.rb` — `ALL_SOURCES`, the canonical list
- `lib/ammitto/config/defaults.rb` — `DATA_REPO_TO_SOURCE`, the same
  fifteen codes keyed by repo name
- `lib/ammitto/transformers/registry.rb` — `TRANSFORMERS`, the same
  fifteen codes keyed to classes
- `lib/ammitto/cli/sources_command.rb` — `sources_data`, the same
  fifteen codes plus a display name, a format string and a
  machine-readable flag

Three of those are sanctioned registry points: the design doc blesses
`Config::Defaults`' lists and `Transformers::Registry::TRANSFORMERS`
explicitly, and Track A adds a fourth deliberate one (`INGESTERS`). The
fourth is not. `sources_data` is a **hand-maintained third copy of
per-source metadata** (design doc L23) that no mechanism connects to the
other three, and there is no drift detector: nothing anywhere asserts
that `sources_data`'s codes equal `ALL_SOURCES`.

Adding source #16 therefore means remembering to edit a file that
nothing will remind you about, and forgetting it produces no error — the
new source works everywhere except in the listing that tells operators
it exists.

## What the 2026-08-10 revalidation changed about this finding

The design doc's supporting evidence for L23 was that the table was
*"already drifting (ru flags)"*. **That specific claim is obsolete and
must not be repeated.** Verified at HEAD:

- `sources_data`'s ru row declares `machine_readable: false`.
- `FETCHABLE_SOURCES` excludes ru, with the comment above it recording
  that mid.ru
  serves an F5/TSPD JavaScript anti-bot challenge so Mechanize never sees
  the announcement links.

Those agree, and they agree with the current fetch refusal. The ru drift
was real when the doc was written and has since been fixed. The
**general** finding — metadata hand-maintained in two places with no
drift detector — stands on its own without it.

## The drift that is actually there, and why this card can change output

Looking for the ru drift turned up a different one. The table's row
order is **not** `ALL_SOURCES`' order:

```
ALL_SOURCES   (defaults.rb)          ... ru, tr, nz, jp ...
sources_data  (sources_command.rb)   ... ru, nz, tr, jp ...
```

Same fifteen codes, two positions swapped: `tr` and `nz`. So a
straightforward "derive the rows from `ALL_SOURCES`" refactor **changes
the output of `ammitto sources`** — two rows trade places. That is not a
hypothetical: it is the default outcome of the obvious implementation.

And it is not the only one — see step 5 below, where the equally obvious
derivation of `machine_readable` from `FETCHABLE_SOURCES` would flip two
further rows. **Two** unadmitted output changes are hiding inside a card
whose whole premise is "this is just deduplication". That is the pattern
to be suspicious of.

That matters more than it looks, because the output is unpinned and
possibly consumed:

- There is **no spec for `SourcesCommand` at all**. `spec/ammitto/cli/`
  contains only `fetch_command_spec.rb` and `harmonize_command_spec.rb`.
- `README.adoc` documents `ammitto sources` as an operator command,
  so its output is documented surface.
- The design doc flags a **possible external consumer** of
  `ammitto sources --format json` that it could not verify from the
  sandbox (§6, and B3's own note).

So this card cannot honestly promise "output unchanged" the way `09` and
`10` do. It has a real output-change decision inside it, and
`13-USER-rulings.md` asks it rather than this card assuming it.

**Scope note — settled, not pending.** The design doc packages L23 as
**B3**, inside the fetch stream that `README.md` lists under "What is
deliberately NOT in this board". L23's code is not in
`fetch_command.rb` — it is `sources_command.rb` — so it is CLI metadata
rather than fetch restructuring. `README.md` states that carve-out
explicitly in its "What is deliberately NOT in this board" section, so
this card is in scope and no ruling is outstanding on the question. The
only decisions this card waits on are the two output changes below,
which are ruling 4 in `13-USER-rulings.md`.

## What to do

1. **Golden-pin first, before any change.** Capture the exact current
   output of both `bundle exec exe/ammitto sources` and
   `bundle exec exe/ammitto sources --format json` as committed fixtures,
   and add the spec that this command has never had. Nothing else in this
   card may start until that spec is green — it is the only thing that
   can tell you the output moved.
2. Add the drift spec that should exist regardless of what else happens:
   `sources_data`'s codes, as a **set**, equal
   `Config::Defaults::ALL_SOURCES`. That alone closes the "add source #16
   and forget" hole and is worth shipping even if steps 3–5 are declined.
3. Take the ordering question to the maintainer via
   `13-USER-rulings.md`. Three answers, all defensible: preserve today's
   order (derive the rows but keep an explicit display order),
   adopt `ALL_SOURCES`' order and document the change, or sort
   alphabetically and document it. Do not pick one silently.
4. Derive what is genuinely derivable and leave the rest declared. The
   `code` column comes from `ALL_SOURCES`. The `name` and `format`
   columns are display metadata that lives nowhere else and should get
   one home — per-source declaration next to the source, or a single
   table in `Config::Defaults`, but not both.
5. **Do not derive `machine_readable` from `FETCHABLE_SOURCES`.** They
   look like the same fact and are not:

   | | `machine_readable: false` | excluded from `FETCHABLE_SOURCES` |
   |---|---|---|
   | cn, ru | yes | yes |
   | jp, un_vessels | yes | **no — both are fetchable** |

   `sources_data`'s jp and un_vessels rows mark both not
   machine-readable, while `FETCHABLE_SOURCES` excludes only cn and ru. So
   the obvious derivation would flip **two more rows**, on top of the
   tr/nz reorder — an output change hiding inside what looks like
   deduplication.

   The flag is not about fetchability at all. It tracks the `format`
   column exactly: every XML / JSON / XLSX source is true, and every PDF
   / HTML source (cn, ru, jp, un_vessels) is false. If anything derives
   it, derive it from `format`, and pin that with a spec so the two
   columns cannot drift apart. Whether that is the intended meaning is
   a question for `13-USER-rulings.md`, not an assumption to encode.
6. Do **not** heal any drift you find silently. The design doc's
   implementer obligations are explicit: every drift is either preserved
   as two visible declared fields or fixed deliberately with the change
   named in the PR body.

## Where

- `lib/ammitto/cli/sources_command.rb` — `sources_data`, the
  hand-maintained copy; note the ru row follows the cn row, and the two
  carry different rationales
- `lib/ammitto/config/defaults.rb` — `ALL_SOURCES`
- `lib/ammitto/config/defaults.rb` — the `FETCHABLE_SOURCES` exclusion
  and its ru rationale
- `lib/ammitto/config/defaults.rb` — `DATA_REPO_TO_SOURCE`
- `lib/ammitto/transformers/registry.rb` — `TRANSFORMERS`
- `README.adoc` — `ammitto sources` as documented operator surface
- `spec/ammitto/cli/` — contains no sources command spec; the new golden
  spec goes here

## Done when

- A golden spec pins both the table and the JSON output of
  `ammitto sources`, and it was committed and green **before** any
  production edit in this card.
- A drift spec fails when a code is added to `ALL_SOURCES` without
  reaching `sources_data`. Prove it by adding a fake sixteenth code
  locally, watching it go red, and reverting.
- Per-source display metadata has exactly one home, and the PR body says
  where and why.
- The ordering ruling from `13-USER-rulings.md` is recorded, and the
  implementation matches it. If the ruling was "preserve today's order",
  the golden spec passes unmodified; if it was "change it", the golden
  fixture is regenerated in its own commit whose body shows the before
  and after rows.
- `bundle exec rspec` and `bundle exec rubocop` green.
- `spec/ammitto/public_api_spec.rb` (from `01`) passes, or its snapshot
  is regenerated with the change explained.
- The full-tree export diff is untouched by this card — `ammitto sources`
  writes no artifacts, so the harmonize baseline is not involved. Say so
  in the PR body rather than leaving reviewers to wonder.

## Size and dependencies

**M** — about a day. Half of it is the golden pin and the drift spec,
which is the half that has to exist first. The derivation itself is
small; the ordering ruling may make it smaller still.

Blocked by all of Track A (`08`) only in the sense that Track B sits on
top of it — this card touches neither `harmonize_command.rb` nor the
ingestion modules, so it is the most independent of the three Track B
tasks and could be pulled forward if the maintainer wants an early win.
Blocked in substance by the ordering ruling in `13-USER-rulings.md`.

## ADHD

- 🔴 15 sources hand-listed in 4 places; `sources_data` is a third metadata copy with no drift detector
- 🧨 Add source #16, forget one file, and nothing errors — the source just never appears in the listing
- 🔧 Golden-pin `ammitto sources` first (no spec exists today), add a set-equality drift spec, then derive the code column
- ⚠️ TWO hidden output changes: row order differs from `ALL_SOURCES` (tr/nz swapped), and `machine_readable` is NOT `FETCHABLE_SOURCES` (jp + un_vessels are fetchable but marked false). Both need rulings, see 13
- ✅ Golden spec green before any edit; drift spec red when a code is added to only one list
- 📦 M — a day; ru-is-drifting evidence from the design doc is **obsolete**, verified fixed in `sources_data`'s ru row
