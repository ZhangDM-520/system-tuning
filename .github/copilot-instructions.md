# system-tuning — Copilot instructions

Repo rules only. Canonical prose lives in `docs/`: engine contract `docs/eco-power-README.md`, knob ledger `docs/findings.md`, change/claim gates `docs/judgment.md`, runbook `docs/rollback.md`. On disagreement the doc wins and this file gets fixed.

## Scope

- Single-host tuning: the retired shell converger (`eco`, `lib/`, `state/`, `tests/`) plus four publishable benchmark campaigns (`benchmarks/`).
- Live convergence moved to the `genarch-settings` repo on 2026-11-10. `./eco apply` refuses live with exit `2`; `report` and `apply --dry-run` are the parity and rollback reference. Never revive live convergence here.
- Public repo: no personal identifiers, hostnames, UUIDs, IP or MAC addresses, credentials.

## Commands

- Test gate: `./tests/run` — plain bash, sequential, wipes `tests/work/`, no case selector (`./tests/run | grep 'case3'` to filter). Never run two concurrently.
- Syntax check: `bash -n <script>`. No build step, no lint config, no CI.
- Benchmark analysis (no root, no setup): `FSLAT_RESULTS=$PWD/data/tuning-results.jsonl python3 benchmarks/tools/perf-stats.py show|cmp|test LABEL...`. Run `show` on the control first: an effect inside the control's own spread is not a result.
- Live parity readback: `./eco report`, `./eco apply --dry-run` (root adds the SMU rows; drift there is the retirement, not a fault).

## Architecture

1. `state/` — intent: `state/owned/<live-path>` byte mirrors; `state/managed/*.toml` anchored single-line records (`target`, `match`, `line`, `doc`, optional `section`).
2. `lib/` — shell engine, sourced in glob order; `lib/registry.sh` holds the one check table.
3. Test seams — all live I/O goes through `live_path()`/`assert_in_root()`; `ECO_ROOT` repoints the live tree (empty = live), `ECO_STATE` relocates intent.
4. Contract — `lib/registry.sh` ↔ `tests/run` ↔ `docs/contract.tsv` ↔ `genarch-settings/tests/contract.tsv`; anchors are `##` headings. A new or renamed check ID edits all four at once.
5. Benchmarks — append-only `data/*.jsonl`, stdlib-only analysis, `studies/` tables re-derive from the shipped data.

## Conventions

- **Repo first.** Never hand-edit live tuning; the converger and TLP re-write it. Capture a deliberate experiment (`./eco harvest`) before it reverts.
- **One place per knob.** `grep -rn <value> state/` returns one hit. Two writers on one sysfs attribute is a silent race.
- **Idempotence.** A second `apply` plans nothing; `PLAN 0` is not a health claim (`APPLY-SCOPE` names each row's reach).
- **Backups are never deleted.** Dated `cp -p` sibling per write; `system-sleep/` pre-images go to a sibling directory, because systemd executes every file there.
- **Return codes:** 0 green · 1 drift · 2 precondition · 3 apply failed partway. `SKIPPED` is unverified, not healthy; `ACCEPTED` is settled — never "fix" it.
- **Recovery domain:** nothing may block tty login; bootloader cmdline edits touch `/boot/limine.conf` + `/etc/default/limine` with a pre-image; FS repair is offline only.
- **Judgment gates:** `docs/judgment.md` before proposing a change (work per joule, no caps, stability first) or publishing a claim (two statistical gates, n floors, arm identity). A kernel change is a new baseline.
- **Commits** carry the check ID (`CEIL: …`); no `Co-authored-by` trailer.
- **Benchmarks:** strip personal and host identifiers from prose, JSONL `cmd` fields and scripts. Never name the owner's direct-attach scheduler.
- **Hybrid topology:** Zen 5 = CPUs `0–3,12–15`; Zen 5c = `4–11,16–23` (`eco_ceil_want_for_policy`, `benchmarks/TEST-BED.md`).
