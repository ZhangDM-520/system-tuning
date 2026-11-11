# Action summary — 2026-11-08/09 — architecture audit, Wave 2 (agreed options A/A/A)

Follows Wave 1 (`b089add`). Owner rulings: C4 option A (capability table), C5 option A (skip, not
hard-fail — an abrupt refusal would brick convergence over a trivial stray), C6 option A (one
table). Plus the three refinements agreed after the report: a **three-valued** apply capability, a
**visible** skip (plan + stderr), and the `ECO_STATE` seam so the filter is testable.

## C5 — deployable filter, visible

- `lib/state.sh`: `eco_deployable_name` refuses `*.bak`, `*.bak-*`, `*~`, `*.orig`, `*.rej`,
  `*.swp`, `.#*`, `*.tmp`; `owned_state_files` now yields deployables only and
  `owned_non_deployable_files` the rest.
- `lib/writers.sh`: those strays become `SKIPPED /<path> (not deployable: …)` in every plan; a
  stray under `usr/lib/systemd/system-sleep/` gets the reason "system-sleep executes every file;
  remove it" **and** a stderr line so it is not a quiet filter.
- New `ECO_STATE` (default `$ECO_HOME/state`) relocates the intent tree — the filter lives in the
  intent walk, which `ECO_ROOT` cannot reach. Tests now have a seam instead of copying the repo.

## C4 — apply scope named, three-valued

- `lib/registry.sh`: `CHECK_APPLY` per check — `full` (CO, ECO, IO), `file-only` (EPP, WIFI, BT,
  TLP, PROFILE, MISC), `none` (CEIL, PPT, TIMER, SCHED, SD).
- `lib/writers.sh`: `plan_scope_line` prints
  `APPLY-SCOPE full=… file-only=… none=…` in every plan (dry-run and real apply), so `PLAN 0` can
  never be read as "the machine is healthy".
- `docs/eco-power-README.md` exit-code section documents the split; `AGENTS.md` gained a facts row.

Measured before the change: the same tree gave `report` exit 1 (`DRIFT TIMER`) and
`apply --dry-run` exit 0. That is now named, not hidden.

## C6 — one registry table

- `lib/registry.sh` is one `TABLE` (`id|reader|doc anchor|managed records|apply reach`);
  `CHECK_IDS`, `CHECK_READER`, `CHECK_DOC`, `CHECK_MANAGED`, `CHECK_APPLY` derive at source time.
- `lib/state.sh` derives `MANAGED_IDS` from `CHECK_MANAGED` (first-seen order) — the last record
  restatement is gone.
- `tests/run` keeps its literal 14-ID list on purpose (the independent oracle) and case19's anchor
  collector now greps bare `prefix#slug` tokens out of the table; its `15` count is the guardrail
  that a reshape cannot hollow the collector.

## Verification

- `tests/run`: 117/117 (was 106) — case26 filter (skip in plan, stderr hazard line, stray not
  written), case27 apply-scope (report exit 1 vs apply exit 0, `APPLY-SCOPE` names TIMER out of
  reach), case28 derivation (14 checks, 8 records, 5 profile records).
- Live: `./eco report` drift=0; `./eco apply --dry-run` → `PLAN 0`, `APPLY-SCOPE
  full=CO,ECO,IO file-only=EPP,WIFI,BT,TLP,PROFILE,MISC none=CEIL,PPT,TIMER,SCHED,SD`.
- No live writes were needed: these three are tooling, not state.

## Notes for the next agent

- `set -e` + a non-zero helper aborts silently; `managed_check_problems` returns 1 by design and
  its callers use `if`/`|| true`.
- The plan prints `APPLY-SCOPE` last; a script parsing `PLAN n` should not assume more `SKIPPED`
  lines follow.
- `ECO_STATE` is test-only in practice; nothing in `state/` may point outside the repo.
