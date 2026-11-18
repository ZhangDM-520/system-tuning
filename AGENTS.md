# AGENTS.md — system-tuning

Single-host Linux tuning in one tree: the retired shell converger (`eco`, `lib/`, `state/`, `tests/`), four publishable benchmark campaigns (`benchmarks/`), and the storage/ops documentation. The repository is public, so nothing here may carry personal identifiers, hostnames, UUIDs, IP or MAC addresses, or credentials.

## Engine status (read first)

Live convergence belongs to the `genarch-settings` repository since 2026-11-10: it owns the installed engine, units and manifest, and live changes follow its `docs/CUTOVER.md`. The shell `eco` here is **retired, not deleted** — `./eco apply` refuses a live run with exit `2` (`state/RETIRED.md`), while `./eco report` and `apply --dry-run` still work as the parity and rollback reference. Never revive live convergence in this tree.

## Mental model

- `state/` is intent: byte-exact `state/owned/<live-path>` mirrors plus flat-TOML `state/managed/*.toml` anchored line records. `find state/owned -type f` is authoritative.
- `lib/` is the shell engine, sourced in glob order by `eco`; `lib/registry.sh` is the single check table every derived map reads.
- `tests/run` is the gate: fixtures plus `PATH` stubs, pointed at the tree through `ECO_ROOT` (empty means the live root) and `ECO_STATE` (intent root).
- `benchmarks/` is a self-contained publishable unit: methodology, a time-stamped test bed, append-only `data/*.jsonl`, and studies re-derived from the shipped data.
- `docs/` is the prose: engine contract (`eco-power-README.md`), knob ledger (`findings.md`, one `##` entry per knob), change/claim gates (`judgment.md`), operator runbook (`rollback.md`), archived XFS campaign (`archive/XFS-TUNING.md`), primary-sourced mechanism reports (`research/`).

## How to work here

1. Read the knob's entry in `docs/findings.md` before touching it; the owning module carries the depth.
2. Edit intent under `state/`. Never hand-edit live configuration.
3. Dry-run the plan, apply, then run `./tests/run` and read it.
4. Commit one knob per commit, with its check ID in the subject line.

The docs teach how to check a claim; current state is measured on the host, never written down here.

## Durable rules

- **Repo first, one place per knob.** A live value has exactly one home under `state/`; `grep -rn <value> state/` returns one hit. Two writers on one attribute is a silent race.
- **The contract is four-way.** `lib/registry.sh`, `tests/run`, `docs/contract.tsv` and `genarch-settings/tests/contract.tsv` move together; anchors are `##` headings, not filenames.
- **Run the gate before claiming anything.** `./tests/run` is sequential and wipes `tests/work/`; never run two at once. Live failures (a dead sysctl, an absent foreign target) turn it red on a clean tree, so dry-run live before blaming the tree.
- **Gate claims through `docs/judgment.md`.** Work per joule, no power caps, stability outranks everything; a claim needs a measurement that clears both statistical gates, and a kernel change is a new baseline.
- **The recovery domain is sacred.** Nothing may endanger tty login, the bootloader or the initramfs. Bootloader cmdline edits touch both `/boot/limine.conf` and `/etc/default/limine`, with a pre-image first.
- **Backups before writes, never deleted.** Pre-images are dated `cp -p` siblings; the one exception is `system-sleep/`, whose pre-images go to a sibling directory because systemd executes every file in it.
- **Return codes and verdicts are contract.** 0 green · 1 drift · 2 precondition · 3 partial apply. `SKIPPED` is unverified, not healthy; `ACCEPTED` is settled and never "fixed".
- **Benchmarks privacy.** Strip personal and host identifiers from prose, JSONL `cmd` fields and scripts; hardware identity is the product, personal identity is not.

## Pitfalls

- `cmd_apply` re-execs through `sudo`, so a falsified retirement guard deploys the shell engine from inside the gate. Test the guard through `refuse_retired_apply`, never through the verb.
- A second `apply` plans nothing, and `PLAN 0` is not a health claim; `APPLY-SCOPE` names each row's reach.
- `tests/work/` is generated output, never source, and is gitignored.
- A test-bed figure is scoped to its kernel: a re-run elsewhere is a new baseline, not a reproduction, and historical numbers are never edited to match.
- Two engines must never own one file; that is the failure mode the retirement exists to prevent.

## Memory

Durable agent memory, action logs, distilled lessons, research digests and open decisions live in the maintainer's private warehouse. Start with its `AGENTS.md`: the knob ledger and the judgement/measurement lessons answer most "why is it like this" questions before the long-form docs do. Nothing from it is copied back into this tree.
