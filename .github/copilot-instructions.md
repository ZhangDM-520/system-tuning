# system-tuning — Copilot instructions

Single-host system tuning for this machine (CachyOS, Ryzen AI 9 HX 370, hybrid Zen 5 / Zen 5c,
XFS on NVMe). Three bodies of work in one tree:

- **eco/power convergence** — `eco` (CLI), `lib/` (its modules), `state/` (intent), `tests/` (the
  gate). The live system converges to this repo every 600 s (`eco-power.timer`; `eco apply` runs as
  the second, failure-tolerant `ExecStart=-` of the same chain), so live is never the place to make
  a change.
- **benchmarks** — `benchmarks/`: `METHODOLOGY.md`, `TEST-BED.md`, `tools/` (recording + analysis
  scripts), `data/` (append-only jsonl rows), `studies/01..04`.
- **filesystem maintenance / XFS tuning** — `docs/FS-MAINTENANCE.md`, `docs/XFS-TUNING.md`,
  `benchmarks/studies/04-xfs-tuning/`, and the `state/owned` units behind them (duperemove and
  xfs-scrub timers, smartd + `smart-alert.sh`, the XFS sync-interval sysctl) — converged by the
  same `eco apply` like every other owned file.

Merged 2026-09-28 from the `eco-power` and `System-Tuning-Benchmarks` repos (both histories
preserved; old checkouts are read-only backup). This repo is canonical.

Contract docs: `docs/eco-power-README.md` (the eco tool: commands, exit codes, verdict classes,
check registry), `docs/unified-findings.md` (merged truth: applied / rejected / refuted / open —
read first). When this file and a doc disagree, the doc wins and this file is what gets fixed.

## Commands

| Command | Effect |
|---|---|
| `./tests/run` | the only test gate: 18 cases / 87 assertions, plain bash, no framework. Wipes and rebuilds `tests/work/` every run; takes tens of seconds |
| `./eco report` (bare `./eco` is the same) | read-only verdict over the 14 checks; no root (checks needing root or a user session report `SKIPPED`) |
| `./eco report --json` | same verdict, machine-readable |
| `./eco apply --dry-run` | print the convergence plan, write nothing |
| `./eco apply` | converge live to repo state; root, idempotent, dated backups first |
| `./eco harvest` | print a unified-diff proposal folding live drift into `state/`; writes nothing |
| `bash -n <script>` | syntax check; there is no lint config in the repo (`shellcheck` appears ad hoc) |

There is no build step. **Single test:** `tests/run` is one sequential script (case1..case18) with
no case selector — run the suite and filter its labelled output (`./tests/run | grep 'case3'`), or
comment out later cases while iterating on one. `tests/work/` is generated output, never source.

Exit codes are shared by every verb: `0` green (SKIPPED rows allowed), `1` DRIFT present, `2`
precondition failure (bad argument, apply lock held, missing state file), `3` partial apply —
the output then lists applied, not-applied, and rollback anchors.

Benchmark re-analysis needs no setup and no root:
`FSLAT_RESULTS=$PWD/data/tuning-results.jsonl python3 benchmarks/tools/perf-stats.py show|cmp|test LABEL...`.
Run `show` on the control first: an effect inside the control's own spread is not a result. The
recording tools need root, hardware, and about an hour; per-tool dependencies and the
"learned the hard way" list are in `benchmarks/tools/README.md`.

## Architecture

How a change propagates (none of this is visible from a single file):

1. **`state/` is the intent.** Two ownership models. `state/owned/<live-path-without-leading-slash>`
   is a byte-exact whole-file mirror the repo owns end to end. `state/managed/<id>.toml` owns
   exactly **one anchored line** inside a foreign file (`target`, `match`, `line`, `doc`, optional
   `section`); regexes are POSIX ERE. Records are **flat** TOML: `toml_get` reads only top-level
   `key = 'value'` lines and hard-fails on a missing required key, so no tables, arrays, or
   multi-line values inside a record. The live target map is `state/README.md` — keep it in sync
   with `state/owned/` (`find state/owned -type f` is authoritative).
2. **`lib/` is the machinery**, sourced by `eco` in glob order; modules define functions and call
   each other only at run time. `registry.sh` = check vocabulary (`CHECK_IDS` order is report
   order; `CHECK_READER`, `CHECK_DOC`, `CHECK_MANAGED`). `readers.sh` = one read-only reader per
   check, each emitting exactly one verdict line. `report.sh` = verdict formatting + exit-code
   derivation. `writers.sh` = apply/harvest adapters, the apply lock, backup convention.
   `managed.sh` = the line-patch engine. `state.sh` = state layout and the `ECO_ROOT` seam.
3. **`ECO_ROOT` is the test seam.** Every live path goes through `live_path()`; an empty
   `ECO_ROOT` means the live root. The suite points it at fixture trees copied from
   `tests/fixtures/`, stubs `systemctl`/`sysctl`/`iw`/`lspci`/`ryzenadj` via `PATH`
   (`tests/stubs/`), and asserts on exit codes, report text, and byte-level write guarantees.
4. **Report ↔ registry ↔ docs ↔ tests are locked together.** Adding or renaming a check touches
   `lib/registry.sh`, a reader in `lib/readers.sh`, a real `##` doc anchor, and `tests/run`
   (case1/case7 hardcode the 14-ID list). `CHECK_DOC` values like `decisions#epp`,
   `fleet-findings#wifi`, `quirks#asusd` (that is `hardware-quirks.md`), `rollback#sd` are
   evidence handles into the docs, not decoration. Verdict semantics are test-contracted: case17
   fails if `docs/eco-power-README.md` stops defining `SKIPPED`.
5. **Benchmarks flow is rows in, claims out.** Recording tools append identity-checked rows to
   `data/*.jsonl` (append-only; `scx-relabel.py` is the only rewriter and demands an explicit
   path), analysis tools answer questions from those rows with the standard library only, and
   `studies/` publish tables that are re-derived from the shipped data rather than transcribed.

## Conventions

- **Repo first.** Hand edits to live are reverted by the 600 s convergence chain by design. Change
  `state/`, `./eco apply`, commit. Capture deliberate live experiments with `./eco harvest` before
  the converger reverts them.
- **One place per knob.** Each tunable appears exactly once under `state/`; `grep -rn <value> state/`
  must return one hit. Two homes means two opinions and apply races them.
- **Idempotence is a contract.** `./eco apply` twice equals once; the second run plans nothing
  (`PLAN 0 change`). Tests enforce it.
- **Backups before every write**: `cp -p <file> <file>.bak-YYYYMMDD`, sibling, never deleted. This
  includes one-line `managed/` edits. The date is the day of the write.
- **Foreign files are patched, never rewritten.** One anchor-matched line; zero or multiple matches
  in scope is a hard error *before any write* (exit 3, nothing written, no backup created). Unclaimed
  bytes survive byte-for-byte; a claimed line changed by someone else surfaces as DRIFT with a
  backup, never silently overwritten.
- **Never write outside `ECO_ROOT`** — `assert_in_root` refuses, and the suite checks it.
- **Recovery domain is sacred.** Nothing here may endanger tty login, the bootloader, or the
  initramfs. A broken stack must still boot to a tty.
- **Commit messages carry the check ID** (`CEIL: Zen5c ceiling 2.9 -> 3.0GHz`) so
  `git log --grep CEIL` is the history of one knob; every commit also carries the
  `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` trailer.
- **Never "fix" an `ACCEPTED` row** (a settled decision where live legitimately differs, e.g.
  firmware floors) or a `WARN` row (known quirk / expected transient) without an owner decision.
  `SKIPPED` is counted green but means unverified.
- **Registry policy labels are load-bearing**: `settled` (do not reopen without new owner
  validation), `tunable` (change through the repo flow), `habit` (the human does it; the report only
  observes), `recovery-only` (exists to undo, not to tune).
- **Proposing tuning goes through `docs/doctrine.md` first**: efficiency is work per joule, race to
  sleep, no power caps or forced throttling (V/f sweet-spot ceilings are legitimate), devices sleep,
  never step Curve Optimizer deeper than validated. Claims go through `docs/measurement.md` and
  `benchmarks/METHODOLOGY.md`: record conditions with every number, no single-shot numbers, a
  silent-failure readback (SMU, verify runs) is not a measurement and never a reported saving.
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
- **Cold start order** (from `docs/eco-power-README.md`): `README.md` → `docs/unified-findings.md`
  → `./eco report` (facts before prose about facts) → exactly one doc chosen by the question (the
  "Doc map" table in `docs/eco-power-README.md`). Never read `state/` end to end; grep it.
