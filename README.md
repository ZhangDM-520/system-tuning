# system-tuning

Unified system tuning for this host (CachyOS, Ryzen AI 9 HX 370, XFS/NVMe): eco/power policy + the
convergence machinery that enforces it, benchmark methodology + studies, filesystem maintenance &
XFS tuning.

## Directory index

| Path | Contents |
|------|----------|
| `eco/` `lib/` `state/` `tests/` | eco apply convergence machinery + managed live config. `./tests/run` runs the suite; `./eco apply --dry-run` previews convergence without writing live. |
| `docs/` | doctrine.md, decisions.md, measurement.md; **`unified-findings.md`** = start-here merged truth (applied/rejected/refuted/open); FS-MAINTENANCE.md, XFS-TUNING.md |
| `benchmarks/` | METHODOLOGY.md, TEST-BED.md, tools/, studies/ — incl. `studies/04-xfs-tuning/` XFS A/B campaigns |

## Start here

`docs/unified-findings.md` is the canonical merged statement of what is applied, rejected, refuted,
and still open across the eco/power, benchmark, and filesystem work — with evidence handles into the
other docs. Read it first; `docs/` and `benchmarks/` hold the per-topic depth behind it.

## Provenance + retirement

Content merged from `eco-power` (was private) and `system-tuning-benchmarks` (was public — its
content is now private here). Git history of both is preserved in this repo (subtree under
`benchmarks/` for System-Tuning-Benchmarks). Both GitHub repos are being archived; their local
checkouts at `~/Projects/eco-power` and `~/Projects/System-Tuning-Benchmarks` are kept untouched as
read-only backup. This repo is canonical as of 2026-09-28. The live converger (`eco-power.timer`,
5-min backstop) now executes `~/Projects/system-tuning/eco apply`.
