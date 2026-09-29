# Project Memory — system-tuning

Durable facts, pitfalls and lessons for this repository. Established by inspection or decision;
none of it should need re-derivation. Session chronology lives in `docs/NOTE.md`; benchmarks-era
standing decisions stay in their original home at `benchmarks/docs/MEMORY.md` (pointer, not copy —
one fact, one home).

Last reviewed: 2026-09-29.

## What this repository is

The canonical single-host tuning repo (merged 2026-09-28 from `eco-power` +
`System-Tuning-Benchmarks`): eco/power convergence machinery (`eco`, `lib/`, `state/`, `tests/`),
benchmark methodology + studies (`benchmarks/`), filesystem maintenance & XFS tuning. Private: live
paths such as `state/owned/home/...` are expected here, while the `benchmarks/` subtree keeps its
publication privacy rule (see `benchmarks/docs/MEMORY.md`).

## Facts that are easy to get wrong

| Fact | How to check / why it matters |
| --- | --- |
| The test gate is `./tests/run` — one sequential bash script, 18 cases / 87 assertions, no case selector | Run and filter labelled output (`./tests/run \| grep 'case3'`); `tests/work/` is wiped and regenerated every run |
| No build, no lint config, no CI | `bash -n` / ad-hoc `shellcheck`; the suite is the only gate |
| Report IDs are locked to `lib/registry.sh` *and* hardcoded in `tests/run` (case1/case7) | Changing the check set means registry + reader + doc anchor + test list in one change |
| `CHECK_DOC` anchors are shorthand, not filenames: `quirks#asusd` lives in `docs/hardware-quirks.md` | Follow the string from `lib/registry.sh` to the `##` heading, not from the filename |
| Verdict semantics are test-contracted | case17 asserts `SKIPPED` (and its "counted green" semantics) appear in both `docs/eco-power-README.md` and the `eco` usage text |
| Every live read/write goes through `live_path()` with the `ECO_ROOT` seam | Empty `ECO_ROOT` = live root; tests point it at fixture trees; `assert_in_root` refuses any write outside it |
| `state/managed` records are flat TOML (`toml_get` reads top-level `key = 'value'` only) | No tables, arrays, or multi-line values in a record; a missing required key hard-fails |
| `state/README.md`'s File map must cover every `state/owned` file | `find state/owned -type f` is authoritative. Burned once: the FS-maintenance/XFS import added 8 files with no map rows (fixed 2026-09-29) |
