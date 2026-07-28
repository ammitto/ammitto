# Scope supporting/instruments dirs per source (G8)

## Why this matters

G8 — the harmonize command's `find_instruments_dir` and
`find_supporting_dir` hardcode paths into the data-cn repo, so Chinese
document-type and organization nodes are injected into every other
source's output tree. A consumer browsing, say, the Australian dataset
finds Chinese legal documents and organizations mixed into it. Found by
the 2026-07-28 harvest audit (converged over 11 review rounds); the
audit classifies it as precisely localized.

## What to do

1. In `lib/ammitto/cli/harmonize_command.rb`, resolve the
   supporting/instruments directories per source (the hardcodes sit at
   lines 512 and 536; the enclosing logic spans roughly 507-548) so
   only cn gets cn supplements.
2. Add focused resolver specs.
3. Note: already-committed api/ trees keep the injected cn nodes until
   the full regeneration (`TODO.phase-4/01-full-harvest.md`) purges
   them — the cleanup is only visible there.

## Where

- `lib/ammitto/cli/harmonize_command.rb:512` — `find_instruments_dir` hardcode
- `lib/ammitto/cli/harmonize_command.rb:536` — `find_supporting_dir` hardcode
  (region 507-548)

## Done when

- Harmonizing any non-cn source produces a tree with no cn
  document-type/organization nodes.
- Resolver specs pass; cn output still carries its own supplements.
- The full-harvest verification (`TODO.phase-4/01-full-harvest.md`)
  confirms the purge in committed trees.

## Size and dependencies

**S** — hours; high confidence, delegable. Blocked by nothing.
Unblocks clean per-source trees for
`TODO.phase-4/01-full-harvest.md` (which verifies the committed-tree
cleanup).

## ADHD

- 🔴 cn document/organization nodes leak into every source's output (G8)
- 🔧 Resolve supporting/instruments dirs per source (`harmonize_command.rb:512,536`)
- ✅ Non-cn trees carry zero cn nodes; resolver specs green
- ⛓️ Nothing blocks it; committed-tree cleanup shows at full harvest (`TODO.phase-4/01-full-harvest.md`)
- 📦 S — hours
