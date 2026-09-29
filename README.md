# system-tuning

Unified system tuning for this host (CachyOS, Ryzen AI 9 HX 370, XFS/NVMe): eco/power policy + the
convergence machinery that enforces it, benchmark methodology + studies, filesystem maintenance &
XFS tuning.

## Provenance + retirement

Content merged from `eco-power` (was private) and `system-tuning-benchmarks` (was public — its
content is now private here). Git history of both is preserved in this repo (subtree under
`benchmarks/` for System-Tuning-Benchmarks). Both GitHub repos are being archived; their local
checkouts at `~/Projects/eco-power` and `~/Projects/System-Tuning-Benchmarks` are kept untouched as
read-only backup. This repo is canonical as of 2026-09-28. The live converger (`eco-power.timer`,
600s backstop) now executes `~/Projects/system-tuning/eco apply`.
