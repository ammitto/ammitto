# USER: seven rulings the refactor cannot make for you

## Why this matters

Track A is fully specified and needs nothing from you: it moves code and
proves the output did not change. Track B is not, and cannot be, because
four of its questions are product decisions wearing a refactor's
clothes, and three more are decisions about how you want to review and
land the work.

Nothing here asks you to confirm a decision the board has already made.
Where the board can decide, it has.

Each ruling below is a sentence or two of your time. Rulings **1, 4 and
5** are blocking: `11` and `09` cannot start without them. Ruling 3
blocks landing rather than starting. The rest can be made later, but
making them now is cheaper than making them mid-PR.

None of these are asking you to re-litigate the design. Design B, the
eight-step migration, the deferral of issue #13 and the cut of the
fetch-side work are all settled and are not reopened here.

## What to read

- `TODO.refactor/README.md` — the two-track discipline and the four
  standing constraints. Two pages; everything below depends on it.
- Nothing else. Each ruling below carries its own evidence inline.

The design doc's §4 classified seven decisions as D1–D7; ruling 6 below
is that document's D2. The label is recorded here only so the two can be
matched if someone has the note open — it is not required reading, and
that document is not in this repository (see the README's "Sources of
truth"). Everything ruling 6 needs is stated in ruling 6.

## What to do

### 1. What documentation does an output-changing refinement owe? (blocking)

`README.md` already answers the general question — Track B output
changes are "allowed here only where a task file says so explicitly and
says why" — so this is not asking whether they are permitted. It is
asking what "documented" has to mean, because constraint 2 spells that
out for the public API and nothing spells it out for output.

- **(a) The task file's statement is enough**, since the tree diff will
  show the change anyway.
- **(b) Task file, PR body, and changelog**, each carrying a
  before/after of the exact changed bytes, and a golden fixture
  regenerated in its own commit.
- **(c) Task file plus PR body**; no changelog entry for CLI-only
  changes that write no artifacts.

**Recommendation: (b)** for anything touching exported artifacts,
**(c)** is defensible for `ammitto sources`, which writes nothing to
disk. What matters is that the bar is stated once rather than argued per
PR. Ruling 4 is the first thing it applies to.

### 2. Is the `transform_jp` shim permanent, or scheduled?

Four examples call `transform_jp` directly
(`spec/ammitto/cli/harmonize_command_spec.rb`, the `#transform_jp with
an announcement that carries no ids` block). Because Track A forbids
editing existing specs, the command
keeps a one-line `transform_jp` delegating to the jp ingestion module.
After Track A it is the only `transform_<source>` method left on the
command.

- **(a) Permanent.** It is a supported entry point; document it as one
  and stop calling it a shim.
- **(b) Scheduled.** A follow-up PR migrates the four examples to the jp
  ingestion module's own spec and deletes it. One session's work.
- **(c) Undecided** — leave it and revisit.

**Recommendation: (b).** The four examples test jp id minting, which is
now the ingestion module's job; testing it through a command method is a
leftover, not a contract. But (a) is defensible if you consider the
command's private surface something external tooling reaches, and (c)
means it survives by default, which is how (a) happens without anyone
choosing it.

**Not blocking, despite appearances.** Track A keeps the shim under
every answer, so `06-jp-ingestion.md` implements identically either way.
Only the *write-up* — whether the card calls it permanent or
provisional — and any later removal wait on this.

### 3. Does the stack squash-merge, or land as a sequence? (blocking)

`README.md` constraint 3 says everything stacks and lands as one
decision. It does not say what the git history looks like afterwards.
This matters more than usual here, because the whole verification story
rests on per-commit bisectability: `03` is nine commits precisely so a
non-empty tree diff can be bisected to one source.

- **(a) One squash.** `main` gets a single clean commit. Bisectability
  is lost the moment it lands.
- **(b) Merge commit preserving the sequence.** History keeps ~20 small
  commits and every move stays individually revertible.
- **(c) Sequence of separate PRs, each merged to `main`.** Contradicts
  constraint 3.

**Recommendation: (b).** The per-source commits are the artifact that
makes a later regression cheap to find; squashing them discards the main
thing this plan bought. If the concern is a noisy `main`, (b) with a
descriptive merge commit gives you both.

### 4. `ammitto sources` — two output changes and one definition (blocking for `11`)

`11-REFINE-duplicate-metadata.md` looks like pure deduplication and
hides two behaviour changes. Both are in a documented operator command
(`README.adoc`, the `ammitto sources` documentation) that has **no spec
at all** today and a
possible-but-unverified external JSON consumer.

**4a. Row order.** `Config::Defaults::ALL_SOURCES`
(`defaults.rb`, `ALL_SOURCES`)
runs `… ru, tr, nz, jp …`; `sources_command.rb`, the `sources_data`
table, runs `… ru, nz,
tr, jp …`. `tr` and `nz` are swapped, so deriving rows from
`ALL_SOURCES` reorders two of them.

- **(a) Preserve today's order** — derive the rows, keep an explicit
  display order. Output unchanged; one more thing to maintain.
- **(b) Adopt `ALL_SOURCES` order** and document the change.
- **(c) Sort alphabetically** and document the change.

**Recommendation: (a).** The rows carry no meaning in any order, so
there is nothing to buy with an output change.

**4b. What does `machine_readable` mean?** This is the one that matters,
because the obvious derivation is wrong and looks right.
`machine_readable` is **not** the inverse of `FETCHABLE_SOURCES`:

| | `machine_readable: false` | not fetchable |
|---|---|---|
| cn, ru | yes | yes |
| jp, un_vessels | yes | **no — both are fetchable** |

It tracks the `format` column exactly instead: XML / JSON / XLSX are
true; PDF and HTML (cn, ru, jp, un_vessels) are false.

- **(a) It means "the upstream publishes a structured format"** — the
  current behaviour. Derive it from `format` and pin that with a spec.
- **(b) It means "an automated fetch path exists"** — then jp and
  un_vessels flip from false to true, which is an output change **and**
  arguably a correctness fix, since both do have fetch paths.
- **(c) They are two different facts** — keep the flag declared by hand
  and add a second column rather than deriving either.

**Recommendation: (a).** It matches every current row, it makes the flag
derivable, and it keeps the output unchanged. (b) is the trap: it reads
as a bug fix and silently changes what the CLI tells operators about two
sources.

### 5. How does `09` handle the 51 `send` calls?

Specs reach 14 private methods of `HarmonizeCommand` through `send`, 51
times (the table is in `09-REFINE-harmonize-command.md`). Extracting
input discovery or the health gates breaks them.

- **(a) Delegating shims** for all 14. Zero spec edits; 14 permanent
  shims and a class that stays wide.
- **(b) Migrate the specs** to test the extracted collaborators
  directly, showing each migrated example asserts the same thing.
- **(c) Do not extract**; improve the file in place.

**Recommendation: (b).** A spec that reaches a private method is
evidence the object is wrong, and this is the moment that becomes fixable
cheaply. (a) trades a structural problem for a bigger one.

Whichever you pick applies to one more case:
`10-REFINE-naming-and-readability.md` wants to rename `transform_data`,
which after Track A dispatches rather than transforms, and which five
`send` calls pin (`spec/integration/ingestion_robustness_spec.rb`, the
examples that call `command.send(:transform_data, ...)`;
`spec/ammitto/cli/harmonize_command_spec.rb`, the tr/ch examples that
call `command.send(:transform_data, ...)`). Under (a) it keeps its name
and gets a comment; under (b) it is
renamed and those five migrate with the rest.

### 6. Is D2 ever scheduled, or permanently deferred?

`Au::Transformer#transform_from_hash`
(`lib/ammitto/sources/au/transformer.rb`, `def transform_from_hash`) and
the command's au
dispatch (`harmonize_command.rb`, `def transform_au`) use different
criteria: a
record carrying both `imo_number` and `dates_of_birth` becomes a Vessel
through one and an Individual through the other. Both are spec-pinned
independently. The design doc defers unification as D2, pending an
equivalence proof.

- **(a) Permanently deferred** — record it as intentional and stop
  raising it.
- **(b) Scheduled** as a follow-up with the equivalence proof as its
  first deliverable.

**Recommendation: (b).** Two dispatchers that disagree about what a
record is will eventually be reached by a record that carries both keys,
and today nobody would notice. `04` adds a spec pinning the current
divergence so a future proof has something concrete to argue against.

### 7. cn's `announcement:` key — delete, or repair?

`harmonize_command.rb`, `def transform_cn_modification` builds
`announcement:
result[:announcement]`, but `Cn::Transformer#transform_modification`
returns `official_announcement:`
(`lib/ammitto/sources/cn/transformer.rb`, `def transform_modification`).
The key has always
been nil. Nothing reads it, or `modifications:`, or the transformer's
`legal_citations:`.

- **(a) Delete all three keys.** Output-neutral; the modification result
  becomes an honest nil pair.
- **(b) Repair the key** so it carries the announcement it was meant to
  carry, then decide what consumes it.

**Recommendation: (a).** Nothing downstream reads a result hash beyond
`:entity` and `:entry` (`harmonize_command.rb`, `def ingest_results`),
so (b) would
build a channel with no receiver. If cn modifications *should* be
exported, that is a feature with a design, not a one-line key fix.

## What saying yes/no implies

- **Ruling 1 (b) vs (c):** (b) sets one bar and applies it everywhere;
  (c) accepts that a CLI listing which writes no artifacts does not need
  a changelog entry. Either way the bar stops being argued per PR.
- **Ruling 2 (b):** costs one small follow-up PR and leaves the command
  with no source-named methods at all. **(a)** costs nothing now and
  makes `transform_jp` a promise you are keeping indefinitely. Nothing
  in Track A changes either way.
- **Ruling 4b (a) vs (b):** (a) keeps the CLI saying exactly what it says
  today and makes the flag derivable from `format`. **(b)** tells
  operators that jp and un_vessels are machine-readable, which is
  arguably truer and is definitely a change — and it is the answer
  anyone would reach by accident, which is why it is worth ruling
  deliberately.
- **Ruling 3 (a):** a clean `main`, and the next regression in this area
  is bisected across ~2,000 changed lines instead of one source.
  **(b)** costs a noisier log and keeps that cheap.
- **Ruling 5 (b):** edits ~51 existing examples — visible churn in the
  PR, and the reason each card insists the before/after assertion is
  shown. **(a)** ships faster and leaves `09` having improved the file
  without improving the object.
- **Ruling 6 (a):** the divergence becomes documented behaviour and any
  future difference in classification is on the source data, not on us.
  **(b)** commits to an equivalence proof nobody has scoped yet.

## Where

- `TODO.refactor/README.md` — constraints 2 and 3; the task index
- `TODO.refactor/09-REFINE-harmonize-command.md` — the `send` table
  (ruling 5)
- `TODO.refactor/11-REFINE-duplicate-metadata.md` — both output changes
  (ruling 4)
- `TODO.refactor/10-REFINE-naming-and-readability.md` — the
  `transform_data` rename that rides on ruling 5
- `spec/ammitto/cli/harmonize_command_spec.rb` — the shim's four callers
  (ruling 2)
- `lib/ammitto/config/defaults.rb` and
  `lib/ammitto/cli/sources_command.rb` — the swapped rows
  (ruling 4a)
- `lib/ammitto/config/defaults.rb` and
  `lib/ammitto/cli/sources_command.rb` — jp and un_vessels,
  fetchable but marked not machine-readable (ruling 4b)
- `lib/ammitto/sources/au/transformer.rb` and
  `lib/ammitto/cli/harmonize_command.rb` — the au divergence
  (ruling 6)
- `lib/ammitto/cli/harmonize_command.rb` and
  `lib/ammitto/sources/cn/transformer.rb` — the wrong key
  (ruling 7)

## Done when

- Rulings 1, 4 and 5 are recorded — a sentence each is enough. These are
  the three that stop work: `11` cannot start without 1 and 4, `09`
  cannot start without 5.
- Ruling 3 is recorded before the stack is put up for review. It does not
  block starting.
- Rulings 2, 6 and 7 are recorded, or explicitly deferred with the card
  that waits on each one named.

## Size and dependencies

Decision-only — perhaps twenty minutes to read the seven questions; no
code.

**Blocking:** ruling 1 (the documentation bar) and ruling 4 (both
`ammitto sources` changes) gate `11`; ruling 5 gates `09`. **Blocking at
landing, not at starting:** ruling 3. **Non-blocking:** ruling 2 — Track
A keeps the shim under every answer, so only the write-up and any later
removal depend on it. Rulings 6 and 7 gate nothing immediately, but each
has a card waiting on the answer.

## ADHD

- 🔴 Track A needs nothing from you. Three rulings stop Track B; four more are worth answering now
- 📖 You read: `README.md` (2 pages). Nothing else — each ruling carries its own evidence inline
- 🔧 Blocking: (1) what documentation an output-changing refinement owes; (4) `ammitto sources` — row order AND what `machine_readable` means; (5) how `09` handles 51 spec `send` calls
- 🔧 Then: (3) squash vs sequence (blocks landing, not starting), (2) jp shim lifetime, (6) is D2 ever scheduled, (7) cn dead key delete-vs-repair
- ⚠️ The trap: `machine_readable` is NOT `FETCHABLE_SOURCES` — jp and un_vessels are fetchable but marked false, so the obvious "fix" silently changes what the CLI tells operators about two sources
- 📦 Decision-only — ~20 minutes, no code
