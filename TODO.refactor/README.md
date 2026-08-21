# TODO board — source-module refactor

Task files for the source-module refactor.

**The convention, stated here rather than by reference.** One PR
completes a task AND deletes its file in the same change, so
`ls TODO.refactor/` is the live status and the git log of deletions is
the completion history. A `USER` prefix means the task needs a
maintainer ruling, not code. Every task file uses the same sections in
this order: `# Title`, `## Why this matters`, `## What to do`,
`## Where`, `## Done when`, `## Size and dependencies`, `## ADHD`.

This convention was first written down in `TODO.README.md`, which
**does not exist on this branch** — it lives on `chore/todo-task-board`,
which is unmerged (`git merge-base --is-ancestor c34fa0d main` returns
non-zero as of 2026-08-11). So it is restated above rather than cited,
because a cross-branch reference is not a reference a reader can follow.
If that branch lands, this paragraph can become a pointer again.

This README documents the board, the two-track discipline and the four
standing constraints — it is not a task card and does not follow the
task template.

## Sources of truth

**These board files are self-sufficient. The documents below are working
notes that live in `.codex-context/`, which is excluded from git
(`.git/info/exclude`) because it holds AI coordination material — so a
reader of this repository cannot open them.** They are named for
provenance, not as required reading: every fact they establish that
matters to execution has been copied into the cards, with its own
verification. If a card ever needs one of these to be understood, that
card is incomplete and the fix is to move the fact into the card, not to
commit the note.

- `refactor-source-modules-design.md` — the 2026-08-06 design doc:
  35-finding leak inventory (L1–L35), the three designs compared,
  Design B chosen, the eight-step Phase A migration.
- Its 2026-08-10 revalidation, which found that doc **not safe to
  execute unchanged**: the acceptance count was dead, three fetch-side
  findings had gone stale, and the size estimate was wrong. Those
  repairs are folded into these task files rather than left in prose.
- `work-sizing-2026-07-28.md` — the S/M/L/XL scale used here, restated
  so it needs no lookup: **S** ≈ hours, **M** ≈ one day, **L** ≈ 2–4
  days, **XL** ≈ a week or more.

## The four standing constraints

These come from the maintainer's delegate on 2026-08-10 and are not
re-negotiated per task.

### 1. This is not a code move. It is a refactor.

The 2026-08-06 plan was pure cut-paste — deliberately, because that is
what makes byte-identical output provable. The delegate's direction is
broader: *"it should be refinements, it should be improvements, better
readability, better design/structure."*

Both are true and they conflict, so they are separated rather than
blended. See **The two tracks** below.

### 2. The public API cannot change. At any cost, at any stage.

Not "should not" — cannot. Where a change is genuinely unavoidable it
is documented at every step, in the task file, in the PR body, and in
the changelog, before it happens.

This is enforced mechanically, not by care: task `01` adds a checked-in
snapshot of the public surface and a spec that fails when it drifts.
Until that guard exists, no move task may start.

### 3. Nothing merges. Everything stacks.

Each PR targets its predecessor, never `main`. The stack is reviewed as
one artifact and lands as one decision. A green PR mid-stack is not
permission to merge it.

### 4. The process is tooled, not improvised.

The previous three weeks delivered roughly a week and a half of work,
and the delegate named the cause: every session re-derived the same
context and re-ran the same manual steps by hand. Task `12` builds three
scripts that remove that — baseline capture and diff, API snapshot and
diff, and session orientation — so the expensive repeated steps are
scripts before they are instructions.

`12` used to propose seven items including two execution agents. Those
were cut on 2026-08-11 because they addressed friction nobody had
measured; the card says so and says what evidence would bring them back.
Tooling is a lever, not a virtue.

## The two tracks

The refactor's failure mode is silent: the entity count can stay
identical while every `jp` IRI quietly changes. The only thing that
catches that is exporting the full corpus before and after and diffing
the trees byte-for-byte.

That gate works **only** while the change is behaviour-preserving. The
moment a commit both moves code and renames a method, a diff stops
meaning "you broke something" and starts meaning "which of my two
intentions caused this?" — and the gate is gone.

So:

**Track A — move.** Byte-identical output required.

"Pure cut-paste" is the intent, not a literal description, and the task
cards say so precisely because the difference matters. A move
necessarily changes four things: the require path, `entity_to_hash` →
`ctx`, the guard call, and `@exporter.add_group` → `ctx.add_group`.
Each of those weakens `git blame -C`'s copy detection, so blame is a
sanity check here and **not** the proof. The proof is an enumerated
substitution table per move — every difference between the old body and
the new one named in advance — plus an extract-and-substitute `diff -u`
showing nothing else changed.

Acceptance is an empty normalized tree diff against the Step 0
baseline. Tasks `02`–`08`.

**Track B — refine.** Sits *on top* of a completed Track A. Each
refinement is its own small commit with its own justification and its
own evidence. Output changes are allowed here only where a task file
says so explicitly and says why. Tasks `09`+.

A commit that does both is a defect, not a shortcut. If a move makes a
refinement obvious, the refinement waits for Track B.

## Acceptance, and the number that used to be wrong

The 2026-08-06 doc pinned "25,128 entities" as the pass condition. The
corpus is now ~60,901 across 13 sources, so that literal would have
failed the gate for reasons having nothing to do with the refactor.

Replacing it with 60,901 would rot the same way. **The acceptance count
is whatever Step 0 recorded**, and Step 0 pins both sides of the input:
the gem commit, the Ruby and lockfile identity, the included source
set, and the commit SHA of every participating data repository. A
baseline that does not name its inputs gates nothing.

**And a baseline over thirteen sources cannot arbitrate fifteen moves.**
`Config::Defaults::ALL_SOURCES` (`lib/ammitto/config/defaults.rb`)
names fifteen codes and Track A moves every one of them, so a corpus
covering thirteen leaves two moves ungated while an empty tree diff
reads like proof for all fifteen. `00-golden-baseline.md` step 7 closes
this: each of the fifteen gets a baseline fixture or an explicitly
recorded blocked state, and a source in the blocked state makes every
card that moves it report **BLOCKED** for that source rather than
passing. There is no third option, and "the diff was empty" is not one.

## Task index

**Files `00`–`11` are numbered by execution order. `12` and `13` are
not, and neither is a mistake.** `00`–`08` run in that sequence, Track A
being blocking and sequential; `09`–`11` follow once Track A is
complete and are independent of each other, except that `09` runs
before `10` (both edit `harmonize_command.rb`).

The two exceptions:

- **`12` partly precedes `00`, `01` and `03`.** Its item 1 (the
  baseline capture and diff script) ships *with* `00`, its item 2 (the
  API snapshot script) ships *with* `01`, and its item 3 (session
  orientation) is worth having before `03`, the first repeated step.
  Building them afterwards means doing `00` and `01` by hand once,
  which is exactly the habit `12` exists to end. Its number is high
  because it is support work, not because it comes last.
- **`13` has no position at all.** It is a decision card, not an
  execution step. Rulings 1 and 4 gate `11`; ruling 5 gates `09`;
  ruling 3 gates landing rather than starting. Read it early; answer it
  whenever.

| File | Track | Size |
|---|---|---|
| `00-golden-baseline.md` | gate | M |
| `01-public-api-freeze.md` | gate | L |
| `02-ingestion-scaffolding.md` | A | M |
| `03-trivial-wrappers.md` | A | L |
| `04-dispatchers.md` | A | M |
| `05-ch-ingestion.md` | A | S |
| `06-jp-ingestion.md` | A | M |
| `07-cn-ingestion.md` | A | S |
| `08-delete-the-case.md` | A | S |
| `09-REFINE-harmonize-command.md` | B | L |
| `10-REFINE-naming-and-readability.md` | B | M |
| `11-REFINE-duplicate-metadata.md` | B | M |
| `12-tooling-scripts.md` | tooling | M (marginal) |
| `13-USER-rulings.md` | ruling | — |

## The estimate, re-derived

**Track A plus both gates plus `12`: 11–17 focused days (~2.5–3.5
calendar weeks), midpoint ≈ 14.** XL if the Step 0 determinism preflight
fails.

The previous figure here was "**L, 4–7 focused days**". It is withdrawn.
It did not survive addition: on this board's own scale (M ≈ one day,
the sizing scale in "Sources of truth" above) the cards alone came to more
than seven days before any gate ran. The arithmetic, using M = 1 day,
S ≈ 0.4 day, L = 2–4 days priced per card:

| Card | Size | Days |
|---|---|---|
| `00-golden-baseline.md` | M | 1.0 |
| `01-public-api-freeze.md` | L | 2.5 |
| `02-ingestion-scaffolding.md` | M | 1.0 |
| `03-trivial-wrappers.md` | L | 2.0 |
| `04-dispatchers.md` | M | 1.0 |
| `05-ch-ingestion.md` | S | 0.4 |
| `06-jp-ingestion.md` | M | 1.0 |
| `07-cn-ingestion.md` | S | 0.4 |
| `08-delete-the-case.md` | S | 0.4 |
| **card subtotal** | | **9.7** |
| `12-tooling-scripts.md`, marginal | M | 1.0 |
| ten corpus exports + normalized diffs (see below) | | 0.6 |
| one review-and-rework round, ≈25% of the card subtotal | | 2.4 |
| **total** | | **≈13.7** |

Two of those sizes changed in the 2026-08-11 board review, and both grew
for stated reasons rather than for safety margin. `01` went M → L: its
surface definition now has to cover visibility, ancestry, constant
values, live autoload resolution, four Thor classes, documented
explicit-require entry points and documented exceptions, plus a
machine-readable change summary. `03` went M → L: nine moves each owing
an extract-substitute-`diff -u` proof is not a day.

**The corpus-export line is the one real unknown.** The count is
certain — `00` runs three (two preflight, one reproduce-from-pinned) and
`02`–`08` run one each, so ten — but the per-run cost is not measurable
from the gem checkout, which has no `data-*` siblings. The 0.6 day above
assumes 20–40 minutes per capture-normalize-diff over a ~60k-entity
corpus. If a run takes two hours, that line alone becomes 2.5 days and
the total moves to ~16. Measure it during `00` and correct this table.

**What is deliberately *not* a cost: the suite.** It is 1,458 examples
in **4.1 seconds** (measured at `0f8afc6`, 2026-08-11). "Run the full
suite after every commit" appears in almost every card and costs under a
minute across the whole of Track A. No card may price it as work, and
the old estimate's implicit assumption that repeated suites were
expensive was simply wrong.

The range 11–17 comes from the L bands (`01` 2–3, `03` 2–3, and whether
`06` behaves), the export unknown above, and whether one rework round is
enough. The estimate assumes the data snapshots stay available and
immutable and that dependencies already work. Track B (`09`–`11`) is
scoped per task and priced separately — it is deliberately not on the
critical path.

## What is deliberately NOT in this board

- **Fetch-side restructuring** (the design doc's B1 and B2). Cut from
  this effort on 2026-08-06 and still cut. It stays specified in the
  design doc so it can stream out later without redesign.

  One carve-out, because the design doc's packaging is misleading: it
  files the duplicated source metadata (L23) under B3 as fetch work,
  but that finding's code is `sources_command.rb`, not
  `fetch_command.rb` — it touches no fetch path. It is therefore in
  scope as Track B task `11`, and only the genuinely fetch-side parts
  of B3 stay out. **This is a board decision, taken here**; it is not
  open, and `13-USER-rulings.md` does not ask it.
- **The ontology migration** (issue #13). Consciously deferred. Every
  ingestion module accepts an *injected* transformer and treats the
  entity/entry objects it returns as opaque, so the model layer can be
  swapped underneath later without touching a single ingestion module.
  Task `02` makes that executable with a fake-transformer contract test
  rather than leaving it as an intention.
