# Action summary — 2026-10-31 — memory architecture migration

## What changed

Old memory layout (`docs/MEMORY.md`, `docs/NOTE.md`, host `~/docs/CURRENT.md`) migrated to the
memory architecture (`AGENTS.md` = global memory, `.logs/scratchpad.md` = active buffer,
`docs/JOURNAL.md` = historical log), matching the reference implementation at `~/Projects/aranicy`
(same-day migration there).

| Old | New | Disposition |
|---|---|---|
| `docs/MEMORY.md` (61 L facts table) | `AGENTS.md` | content preserved row-for-row (+ memory-architecture section, `Last reviewed: 2026-10-31`); the dated-snapshots row rewritten to the new home |
| `docs/NOTE.md` (1188 L journal) | `docs/JOURNAL.md` | verbatim history preserved below the migration note; new-format one-line entry appended at top (newest-first convention kept) |
| `~/docs/CURRENT.md` (85 L volatile host snapshots) | `AGENTS.md` `## Current state` | folded verbatim with `## `→`### ` demotion; 3 scheduler-identity mentions genericized to "the owner's direct-attach scheduler" per owner policy (never name it in repo prose); host file deleted (transient pre-image `/tmp/CURRENT.md.preimage-20261031`) |

Old files deleted (retired, not stubbed — single source of truth). Repointed living references:
`tests/run` case21 (`docs/JOURNAL.md` entry-merge guard + comment), `lib/writers.sh:200` comment,
`docs/findings.md` (4 journal handles), `docs/research/btrfs-optimization.md` (4),
`docs/research/btrfs-tunables.md` (1), `.github/copilot-instructions.md` (Fact home + Project
memory bullet), owned drop-in `beesd@.service.d/10-log-rate-limit.conf` comment (live convergence
pending — see Open items). Host-side living pointers in `~/docs/MEMORY.md` (reading order, tier row)
and `~/docs/NOTE.md` (header) repointed to the new home; host journal history left verbatim.

## Re-verification done on edit

- Lossless-migration diff: `diff docs/MEMORY.md AGENTS.md | grep '^<'` shows only the intentionally
  replaced header block, `## What this repository is` heading, and the snapshots row — every other
  byte carried over.
- `tests/run` case21 guards the journal shape (dated `## ` entries, section placement) and now
  targets `docs/JOURNAL.md`; the migration entry is a dated one-liner, so invariants hold.
- Sanitization scope check: `AGENTS.md` retains package-level scheduler facts (scx_mavd kernel
  compat, scx-scheds-git version) but no owner-identity links, per the AGENTS.md facts-table row.

## Open items for the owner

- Commit disposition for this migration (`AGENTS.md` + `docs/JOURNAL.md` new, 2 repo docs deleted,
  repointed refs across 7 files, `.logs/` untracked).
- The `beesd` drop-in comment edit drifts the owned mirror from live until `./eco apply` (comment
  only; converger or the boot chain will pick it up).
- Policy tension to reconcile: `~/Projects/aranicy` (public) names the owner's scheduler directly,
  and `benchmarks/studies/05` says "pandemonium (owner's current)" — this repo's policy row says
  never name the identity in repo docs. The fold sanitized per policy; owner may relax.
