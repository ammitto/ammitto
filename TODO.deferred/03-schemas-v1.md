# M3: schemas/v1 program — phantom claim; build (~5-8d post-K) or descope — Ronald ruling

## Why this matters

The plan issues check off seven schemas/v1 JSON Schema files plus a
README as created — and they exist NOWHERE. The gap matrix verified
the absence three ways: not in the gem or anywhere in its git history
(`git log -S` empty), not in the ammitto/schemas repo (README-only),
not in the ammitto/data repo (a 72k-path tree grep). Nine
claimed-done rows are phantom. Consequence: the plan's "validate all
outputs against schema" story is false until schemas exist — health
gates check counts, not schema — and consumers have no machine-checkable
contract for the published data. Work sizing is blunt: building this
is a schema PRODUCT, not a file-drop.

## What to do

0. Obtain Ronald's build-or-descope ruling first. Route it through the
   standing Ronald conversation
   (`TODO.phase-2/09-USER-rulings-f1-f6-jp.md` is the channel; the
   converged ordering files this whole deferred bucket as
   "Ronald-conversation shaped", and the work-sizing R row lists
   re-marking issues #13/#14/#15 in that same conversation). What
   ruling BUILD implies: ~5-8 focused days of schema-product work
   after the semantic layer settles, plus a home decision. What
   DESCOPE implies: an hours-scale docs edit and honestly re-marking
   the phantom checkmarks.

Then, per the ruling:

1. **Build** (~5-8 focused days AFTER the semantic layer settles): 7
   versioned schemas + shared `$defs`, a home decision (the empty
   ammitto/schemas repo is the natural home), Validation-facade/CI
   integration, fixtures, and compat tests — all authored against the
   CANONICAL vocabulary, which `TODO.phase-4/04-k-semantic-layer.md`
   directly controls (the serializer's emitted names,
   `json_ld_serializer.rb:218`). Attempting it pre-K adds churn on
   top of XL.
2. **Descope** (S — hours): docs edit + re-mark the plan-issue claims
   honestly.

## Where

- ammitto/schemas repo (empty, README-only — the natural home)
- Plan issues #13 (R-069..R-076, R-116, R-125, R-136) — the phantom
  checkmarks to re-mark either way
- `lib/ammitto/serialization/json_ld_serializer.rb:218` — the emitted
  vocabulary the schemas must match

## Done when

- EITHER: 7 schemas + shared $defs live in the chosen home, wired into
  validation/CI with fixtures and compat tests.
- OR: the descope is documented and the plan-issue claims re-marked.

## Size and dependencies

**XL as a build** (~5-8 focused days even post-K — settling K removes
vocabulary churn, not the product work); **S as a descope**. Blocked
by: Ronald's build-or-descope call (routed via
`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`), and on the build path
additionally `TODO.phase-4/04-k-semantic-layer.md`, the F1 ruling
(same USER card), and the home decision.

## ADHD

- 🔴 7 schemas checked off as done — exist NOWHERE (gem history, schemas repo, data repo all verified)
- 🧨 "Validated against schema" story is false; no machine-checkable data contract
- 🔧 Ronald picks: build the schema product post-K (~5-8d) or descope (docs + re-mark, hours)
- ✅ Schemas live + wired into CI, OR descope recorded + issues re-marked
- ⛓️ Ruling via `TODO.phase-2/09-USER-rulings-f1-f6-jp.md`; build path needs `TODO.phase-4/04-k-semantic-layer.md` + F1 + home decision
- 📦 XL (build) / S (descope)
