# Astro 7 migration (plan reviewed, unapproved) — after site ships

## Why this matters

Ronald's later message supersedes the site's Vue-3 stack constraint:
the direction is Astro 7 + Vite 8 + Tailwind 4 (the gap matrix marks
the Vue-stack requirement rows OBSOLETE against it). The migration
restructures the site's route and data-loading architecture wholesale
— which is why the list-aware site program
(`TODO.deferred/04-list-aware-site.md`) must not be built on the
outgoing Vue SPA (week-scale work on whichever stack receives it;
waste on the outgoing one), and why the site performance items
(cache/pagination/lazy-load/service-worker) are, per work sizing, a
DECISION that folds into this program rather than standalone work.
Deferred post-green and Ronald-conversation shaped per the converged
ordering: it comes after the site ships fresh data
(`TODO.phase-4/03-site-retune-ship.md`).

## What to do

1. The stack decision comes FIRST and gates sequencing for
   `TODO.deferred/04-list-aware-site.md` — it is Ronald's direction,
   so route it through the standing Ronald conversation
   (`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`); what to read: the
   work-sizing L2a/L2c rows in
   `.codex-context/work-sizing-2026-07-28.md`. What GO implies: 4-5
   focused days of migration and every new site page lands on Astro.
   What NO-GO / defer implies: the list-aware program stays blocked
   (building its pages on the outgoing Vue stack is documented waste),
   and the current Vue SPA remains the shipped site. Record the
   decision before any new site pages are built.
2. Execute the migration to Astro 7 + Vite 8 + Tailwind 4.
3. Fold the performance program (cache/pagination/lazy-load/
   service-worker scope) into the migration as incremental scope
   there.
4. The semantic-markup/SEO work lands on whichever stack survives.

Note: the six 2026-07-28 artifacts carry the sizing, stack, and
sequencing facts summarized here but not a step-by-step migration
plan — expect to draft that plan (and get it approved) as the first
deliverable of this card.

## Where

- ammitto.github.io — the whole Vue 3 + Vite + vue-router + vite-ssg
  app (verified architecture) to be re-platformed

## Done when

- The stack decision is recorded (before list-aware pages are built).
- The site runs on Astro 7 + Vite 8 + Tailwind 4 with existing pages
  intact.
- The performance scope is executed within the migration program.

## Size and dependencies

**4-5 focused days** per the work-sizing band. Blocked by: the site
shipping fresh data first (`TODO.phase-4/03-site-retune-ship.md`) and
Ronald's direction/approval (routed via
`TODO.phase-2/09-USER-rulings-f1-f6-jp.md`). Gates:
`TODO.deferred/04-list-aware-site.md` sequencing and the site
performance decisions.

## ADHD

- 🔴 Ronald's direction: Astro 7 + Vite 8 + Tailwind 4 — current Vue stack is OBSOLETE
- ⚠️ Decision gates everything site-shaped: don't build new Vue pages first
- 🔧 Decide stack → migrate → fold performance work in → SEO lands on the survivor
- ✅ Site on Astro with pages intact; decision recorded; perf folded in
- ⛓️ After `TODO.phase-4/03-site-retune-ship.md`; Ronald approves (via `TODO.phase-2/09-USER-rulings-f1-f6-jp.md`)
- 📦 4-5 focused days
