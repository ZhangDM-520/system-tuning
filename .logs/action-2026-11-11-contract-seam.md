# Action — 2026-11-11: the cross-repo contract seam lands here

## What changed in this repo
- **New `docs/contract.tsv`** — the owner copy of the engine contract: one `ID<TAB>anchor` row per
  check, anchored into `docs/findings.md`. It is the machine-readable form of "the engine's report
  rows and this repo's ledger must not drift apart".
- **`AGENTS.md`** — new `## Cross-repo contract` section naming the owner copy, the pinned copy
  (`genarch-settings/tests/contract.tsv`) and the three assertions that bind them.
- **`docs/JOURNAL.md`** — the 2026-11-11 entry.

## Why it lives here
The plan's §8 boundary: the ledger is the home of judgement, so the anchor list is owned here and
pinned in the engine repo. Before this, the engine's contract test read a hardcoded path and
**returned green when the file was missing** — a contract that fails open.

## Verification
The engine gate (`cargo test --test contract`, 4 tests) asserts: pinned == compiled registry,
pinned == this owner copy, every anchor resolves to a real `##` heading in `docs/findings.md`.
Falsified by editing one row (`CEIL → findings#nope`): the test went red, restored green.

## Not done here
The shell gate (`tests/run`) still derives its anchor list from `lib/registry.sh`; it does not read
`docs/contract.tsv` yet. Repointing it is part of retiring the shell tree (plan W9), which is
still deferred until the engine's row set replaces the shell registry outright.

Full review findings and engine-side fixes: `genarch-settings/.logs/action-2026-11-11-review-fixes.md`.
