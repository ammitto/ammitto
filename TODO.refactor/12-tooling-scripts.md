# Script the three steps that actually cost the schedule

## Why this matters

The maintainer's delegate named the problem on 2026-08-10: *"we did 1
weeks + few days work in 3 weeks, we can't do the same with the current
work."* That is a fair measurement and this task is the answer to it.

The cause was not effort. It was that every session re-derived the same
context from scratch — which branch, which PR, what the working
agreement is, which facts were already verified — and then re-ran the
same multi-step procedures by hand. Manual procedures drift between
runs, and the drift is invisible until a gate fails for a reason that
turns out to be the procedure rather than the code.

This refactor makes that worse if left alone. The golden-baseline
capture and diff runs at least ten times. The public-API snapshot check
runs on every commit.

**This card was cut down on 2026-08-11, and the reason matters.** It
used to list seven items: three project skills, two generic skills and
two agents. Asked directly whether that plan would have prevented the
schedule problem, the answer was no — most of it addressed friction
that was never measured. What is left is the three items with a causal
line to the loss:

- the baseline capture and diff, because it runs ten times and a
  hand-run variation makes a gate lie;
- the API snapshot and diff, because it runs on every commit;
- session orientation, because re-deriving it was the named cause.

The two that were dropped, and why, so nobody re-adds them by reflex:

- **A per-step Track A execution agent.** The argument for it was that
  `03`–`07` are structurally identical. They are — but they are also
  sequential, so an agent buys consistency, not parallelism, and the
  expensive part of each step is a corpus-scale export the agent still
  has to wait for. It removes no cost. Run `03` manually **through the
  scripted path** once; if that surfaces real repetitive friction, build
  the agent then, with the friction as the evidence. Do not build it on
  the theory that repeated steps are agent-shaped.
- **A separate verification agent.** Its whole job was "never partially
  run the four checks". That is what one deterministic script with one
  exit code does, and item 1 plus item 2 already are that script. An
  agent wrapping two scripts adds a layer that can itself be partially
  run.

The two generic skills (`move-then-refine`, `mutation-check`) are not
dropped — they are **out of this board's completion criteria**. They
belong in `~/ai-skills-rules`, they go through that repo's
present-the-diff-and-wait approval path, and their approval is not on
anybody's critical path here. See "Where".

The rule this task encodes: **anything done more than twice is a
script, and anything a session has to re-derive is a command.**

## What to do

1. **`ammitto-golden-baseline`** — capture, normalize, diff, as one
   command each. It must implement, not describe,
   `00-golden-baseline.md`'s whole contract:

   - the `Date.today` pin, preloaded before `exe/ammitto` loads, raising
     when `AS_OF_DATE` is absent or malformed;
   - the `--combine` requirement, so `all.jsonld` and `all.ttl` exist;
   - normalization by substitution of the three named JSON paths, never
     by deleting a key;
   - the input manifest, written automatically;
   - the three stashed manifests, including the per-input-file
     ingestion-result manifest. Its recorder is **four prepends, not
     two**, and the two easy ones are not sufficient: `ingest_results`
     for the counts and `find_input_dir` for the discovery list, **plus**
     `YAML.safe_load_file` and `transform_data`, because a parse-to-nil
     skip and a load or transform failure both bypass `ingest_results`
     entirely and are otherwise indistinguishable.
     `00-golden-baseline.md` step 6 states the contract; implement all of
     it, including the counts-not-a-
     verdict row shape and the `File.basename` collision check;
   - the per-source coverage list — a fixture or a recorded blocked
     state for each of the fifteen `ALL_SOURCES` codes;
   - a diff mode that exits non-zero with a readable report of what
     moved, including which source and which manifest.

   This is the highest-value item on the board: it is the gate for seven
   tasks and it is the step most likely to be done inconsistently by
   hand. Ship it **with** `00-golden-baseline.md`, not after.

2. **`ammitto-public-api-snapshot`** — regenerate and diff the public
   surface as one command, with `01-public-api-freeze.md`'s rules built
   in: the three-bucket classification; **every difference fails**, with
   the bucket deciding whether the message reads "regenerate the
   snapshot" or "this needs the maintainer"; and the machine-readable
   change summary that a regeneration must commit. Wire the diff into
   CI. Ships **with** `01-public-api-freeze.md`.

3. **`ammitto-session-orientation`** — the standing context a session
   needs before touching anything: current branch and stack shape, open
   PRs and their review state, what is held for the maintainer, what the
   working agreement requires. Today that lives in two local-only notes
   (a handover file and a working-agreement file, both under
   `.codex-context/`, which is git-excluded and therefore not readable
   from this repository) and is consulted by convention; this makes it a
   command with fresh data instead of files that go stale. Read-only —
   it inspects, it does not write.

### For every script

- Ship it with its own tests, in the `scripts/fleet_health_test.sh`
  mould — 744 lines of harness producing 105 named fixture checks
  against a 515-line script, all passing. That is the working precedent
  in this repo for what "shipped with tests" means here.
- Encode the house measurement rules, because they are what was
  repeatedly got wrong: never verify by counting; never measure the
  output of the thing under test; empty output is not evidence of
  absence; confirm the path and revision queried actually exist.
- Read-only by default. Nothing here performs a remote write.

## Where

- `scripts/` in this repo — where all three executables and their test
  harnesses go, alongside `fleet_health.sh` (515 lines) and
  `fleet_health_test.sh` (744 lines, 105 checks), the precedent.
- The local-only handover and working-agreement notes under
  `.codex-context/` — the two files item 3 replaces with fresh data.
  They are git-excluded, so item 3's value is precisely that the
  orientation stops depending on files a reader cannot open.
- `~/ai-skills-rules` — the canonical home for the two generic skills
  (`move-then-refine`, the two-track discipline from this board's
  README generalized; `mutation-check`, proving a spec has teeth before
  trusting it — earned its place when a spec asserting `/^304 /` passed
  against the exact mutant it existed to catch). Both are **later
  proposals** through that repo's approval path: present the exact diff,
  wait for per-item approval. Neither is a deliverable of this card and
  neither appears in "Done when".

## Done when

- Baseline capture and baseline diff each run as one command, and the
  input manifest is written automatically.
- **`00-golden-baseline.md` names those commands where it now names the
  steps.** The division is deliberate and worth stating so nobody
  "cleans" it: `00` stays the normative contract — what must be pinned,
  what may be normalized, what must be recorded, and why — and the
  script is the executable form of it. `00` is not deleted or shortened
  into a command line; it stops being a *procedure to follow by hand*
  and starts being a *specification the script satisfies*, with the
  invocation written down next to each requirement. A reviewer must be
  able to read `00` and judge whether the script is correct.
- The date pin refuses a missing or malformed `AS_OF_DATE`, and the
  script's own test proves that refusal.
- The API snapshot check runs as one command, is wired into CI, and
  emits the machine-readable change summary on a deliberate mutation.
- A fresh session reaches correct orientation from one command instead
  of by reading the two git-excluded local notes and inferring the rest.
- Each of the three scripts has its own test harness with named checks,
  and all pass.
- `03-trivial-wrappers.md` was executed **through** the scripted path by
  hand, and the PR body records whether repetitive friction actually
  appeared. That record is the input to any later decision about an
  execution agent; without it, the agent stays unbuilt.

## Size and dependencies

**M** — about a day of *marginal* cost, and the word marginal is doing
the work. Items 1 and 2 are the scripted form of contracts that
`00-golden-baseline.md` and `01-public-api-freeze.md` already own and
are already priced for; writing them as a script rather than as a
procedure is the smaller half of that work, and the board estimate
counts it inside those two cards, not twice. What this card's M actually
covers is item 3 and the three test harnesses.

The old **M** was wrong for a different reason: it was priced against
seven items — three project skills, two rules-repo proposals and two
agents — plus tests, which was never a day. Dropping the two agents and
moving the two generic skills off the completion criteria is what makes
M honest, not optimism.

Sequencing — and this is the part that contradicts the board's file
numbering, deliberately: **items 1 and 2 ship WITH `00` and `01`, so
this card partly precedes them**, and item 3 is worth having before
`03`, the first repeated step. Building any of it afterwards means doing
those tasks by hand once, which is the exact habit this card exists to
end. `README.md`'s task index says so.

## ADHD

- 🔴 Three weeks produced ~1.5 weeks of work; every session re-derived context by hand
- 🧨 Baseline runs 10× manually → one run silently differs and a gate lies
- 🔧 Three scripts only: baseline capture/diff (with the date pin, `--combine`, and the per-input-file recorder), API snapshot/diff, session orientation — each with a `fleet_health_test.sh`-style harness
- ✅ Baseline and API checks are one command each, in CI; the date pin's refusal is tested; `03` was run through the scripted path and the friction recorded
- ⛓️ Partly PRECEDES the board — items 1 and 2 ship with `00` and `01`, item 3 before `03`; the two generic skills are later rules-repo proposals, not deliverables here
- 📦 M — a day marginal (item 3 + the three test harnesses); items 1 and 2 are priced inside `00` and `01`
