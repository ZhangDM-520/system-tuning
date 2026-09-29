# system-tuning — Copilot instructions

Single-host system tuning for this machine (CachyOS, Ryzen AI 9 HX 370, hybrid Zen 5 / Zen 5c,
XFS on NVMe). Three bodies of work in one tree:

- **eco/power convergence** — `eco` (CLI), `lib/` (its modules), `state/` (intent), `tests/` (the
  gate). The live system converges to this repo every 600 s (`eco-power.timer`; `eco apply` runs as
  the second, failure-tolerant `ExecStart=-` of the same chain), so live is never the place to make
  a change.
- **benchmarks** — `benchmarks/`: `METHODOLOGY.md`, `TEST-BED.md`, `tools/` (recording + analysis
  scripts), `data/` (append-only jsonl rows), `studies/01..04`.
- **filesystem maintenance / XFS tuning** — `docs/XFS-TUNING.md` (XFS campaign module) and the
  storage ops runbook (`docs/rollback.md` `## Storage ops`), plus the `state/owned` units behind
  them (duperemove and xfs-scrub timers, smartd + `smart-alert.sh`, the XFS sync-interval sysctl)
  — converged by the same `eco apply` like every other owned file.

Merged 2026-09-28 from the `eco-power` and `System-Tuning-Benchmarks` repos (both histories
preserved; old checkouts are read-only backup). This repo is canonical.

**Precedence: when this file and a doc disagree, the doc wins and this file is what gets fixed.**
The docs carry the contract — tool (`docs/eco-power-README.md`), knob ledger (`docs/findings.md`),
judgment (`docs/judgment.md`), runbook (`docs/rollback.md`); this file only carries the seams
between them.

## Commands (agent workflow)

| Command | Effect |
|---|---|
| `./tests/run` | the only test gate: plain bash, no framework. Wipes and rebuilds `tests/work/` every run; takes tens of seconds |
| `bash -n <script>` | syntax check; there is no lint config in the repo (`shellcheck` appears ad hoc) |

There is no build step. **Single test:** `tests/run` is one sequential script with no case
selector — run the suite and filter its labelled output (`./tests/run | grep 'case3'`), or
comment out later cases while iterating on one. `tests/work/` is generated output, never source.
The eco verbs, exit codes, and verdict classes are contract (`docs/eco-power-README.md`), never
restated here.

Benchmark re-analysis needs no setup and no root:
`FSLAT_RESULTS=$PWD/data/tuning-results.jsonl python3 benchmarks/tools/perf-stats.py show|cmp|test LABEL...`.
Run `show` on the control first: an effect inside the control's own spread is not a result. The
recording tools need root, hardware, and about an hour; per-tool dependencies and the
"learned the hard way" list are in `benchmarks/tools/README.md`.

## Architecture

How a change propagates (none of this is visible from a single file):

1. **`state/` is the intent.** Two ownership models: byte-exact owned mirrors of live files, and
   managed records that own one anchored line inside a foreign file. The layout (naming rule +
   record spec) is contract: `docs/eco-power-README.md` `## State layout`; `find state/owned
   -type f` is authoritative for owned files.
2. **`lib/` is the machinery**, sourced by `eco` in glob order; modules define functions and call
   each other only at run time. `registry.sh` = check vocabulary (`CHECK_IDS` order is report
   order; `CHECK_READER`, `CHECK_DOC`, `CHECK_MANAGED`). `readers.sh` = one read-only reader per
   check, each emitting exactly one verdict line. `report.sh` = verdict formatting + exit-code
   derivation. `writers.sh` = apply/harvest adapters, the apply lock, backup convention.
   `managed.sh` = the line-patch engine. `state.sh` = state layout and the `ECO_ROOT` seam.
3. **`ECO_ROOT` is the test seam.** Every live path goes through `live_path()`; an empty
   `ECO_ROOT` means the live root, and `assert_in_root` refuses any write outside it. The suite
   points it at fixture trees copied from
   `tests/fixtures/`, stubs `systemctl`/`sysctl`/`iw`/`lspci`/`ryzenadj` via `PATH`
   (`tests/stubs/`), and asserts on exit codes, report text, and byte-level write guarantees.
4. **Report ↔ registry ↔ docs ↔ tests are locked together.** Adding or renaming a check touches
   `lib/registry.sh`, a reader in `lib/readers.sh`, a real `##` doc anchor, and `tests/run`
   (case1/case7 hardcode the 14-ID list). `CHECK_DOC` values like `findings#epp`,
   `findings#wifi`, `findings#asusd`, `rollback#sd` are evidence handles into the docs, not
   decoration. Verdict semantics are test-contracted: case17
   fails if `docs/eco-power-README.md` stops defining `SKIPPED`.
5. **Benchmarks flow is rows in, claims out.** Recording tools append identity-checked rows to
   `data/*.jsonl` (append-only; `scx-relabel.py` is the only rewriter and demands an explicit
   path), analysis tools answer questions from those rows with the standard library only, and
   `studies/` publish tables that are re-derived from the shipped data rather than transcribed.

## Conventions

- **Repo first.** Live hand edits are reverted by the 600 s convergence chain by design; the one
  change flow is `docs/rollback.md` `## Converge a change`, and `./eco harvest` captures
  deliberate live experiments before the converger reverts them.
- **Pre-images before every live write** — the mechanism is `docs/rollback.md`
  `## Undo: universal mechanism`.
- **Commit messages carry the check ID** (`CEIL: Zen5c ceiling 2.9 -> 3.0GHz`) so
  `git log --grep CEIL` is the history of one knob; every commit also carries the
  `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` trailer.
- **Recovery domain is sacred** (tty login, bootloader, initramfs) — rule home `docs/judgment.md`
  (Derived rules).
- **Proposing tuning or making claims** goes through `docs/judgment.md` (`## May I change?` /
  `## May I claim?`) — doctrine, the adoption gates, and what is not a measurement all live there.
- **`benchmarks/` keeps its publication privacy rule** (`benchmarks/docs/MEMORY.md`): hardware
  identity stays, personal identity is stripped — new `benchmarks/` prose names no home paths,
  machine name, user, UUID, IP, or private host log. The repo root is private by design and holds
  live paths such as `state/owned/home/...`.
- **Hybrid CPU topology is hardcoded**: `ceil_for_cpu` in `lib/readers.sh` maps Zen 5 =
  CPUs 0–3,12–15 (4.6 GHz ceiling) and Zen 5c = 4–11,16–23 (3.0 GHz). Per-CPU logic must reuse
  that mapping; `benchmarks/TEST-BED.md` has the fuller machine picture.
- **Project memory**: durable facts go to `docs/MEMORY.md`, session chronology to `docs/NOTE.md`
  (newest entry first); `benchmarks/` keeps its own pair at `benchmarks/docs/` under its stricter
  publication rules. Mine journal entries upward into memory instead of duplicating them.
- **Cold start**: `docs/eco-power-README.md` `## Cold start and change flow`.
- **Contract rules have one home and are never restated here**: commands, exit codes, verdict
  classes (including never "fixing" an `ACCEPTED` row), state layout, one place per knob,
  idempotence, backups, foreign-file patching — `docs/eco-power-README.md` + `docs/rollback.md`;
  registry policy labels (`settled`/`tunable`/`habit`/`recovery-only`) — `docs/findings.md`.
