# Action — 2026-11-10: genarch cutover verified, shell engine retired (guarded, not deleted)

## Cutover state (verified, not assumed)

Live is owned by the native engine at `~/Projects/genarch-settings`:

- `systemctl is-enabled genarch.service genarch-ceil.timer` → enabled/enabled;
  `eco-power.service` / `eco-ceil.timer` → not-found (units and their live files pruned).
- `genarch report` (root) → `ok=10 accepted=1 drift=0 skipped=0 exit=0`; SMU is ACCEPTED
  (firmware preference), `PRUNE 13 declared removal(s), none present`.
- `GENARCH_INTENT=$PWD/intent genarch apply --dry-run` → `PLAN 0 change(s)`.
- Shell artefacts absent: `/usr/local/sbin/eco-power.sh`, `/usr/local/lib/eco-ceil.sh`,
  `~/.reserve/hw-tune.fish`, `/usr/lib/systemd/system-sleep/eco-power`. The genarch sleep hook is
  the only file in that directory (the directory executes every file it contains).

## The double-writer hazard, closed

`eco apply` re-execs through `sudo` when `ECO_ROOT` is empty, so any stale timer or human run
restores the whole shell engine beside `genarch`. Two changes close that:

1. `state/RETIRED.md` — the retirement marker (intent-tree location, so `ECO_STATE` reaches it).
2. `eco` `refuse_retired_apply` — refuses an empty-`ECO_ROOT` apply with exit 2 and names
   `genarch`; dry-run and report stay available (read-only). Fixture applies (`ECO_ROOT` set) are
   allowed on purpose: the gate applies into fixtures. Dispatch order: guard before `cmd_apply`.

`tests/run` case30 (7 assertions) pins the refusal, both message lines, no-fall-through, the
fixture branch, the marker's intent-tree location, and the dispatch order. `ECO_LIB_ONLY=1`
(new sourcing seam in `eco`) lets the case exercise the function without running a verb.

## Incident and recovery (recorded because it will happen again)

Falsifying the earlier verb-level version of case30 by removing the guard **deployed the shell
engine to live from inside the gate** — `cmd_apply`'s sudo re-exec made the test a writer.
Recovered in the same session with `sudo genarch apply` (13 PRUNEs + daemon/udev reload), then
re-verified: `PLAN 0`, report `drift=0`, PRUNE none present. The case was rewritten to test the
function and the dispatch order, never the verb; the second falsification run (guard stubbed with
`return 0`) went red on 4 assertions and wrote nothing live.

## Repo state

- Tag `genarch-cutover-shell-retired` → `fa092af` (last pre-retirement commit; the rollback tree:
  `eco`, `lib/`, `state/` without the marker).
- `state/RETIRED.md` rewritten to match reality: the shell tree stays in the repo as the rollback
  artifact and parity reference; rollback removes the marker (`genarch-settings/docs/CUTOVER.md`
  steps 5 and 7 updated to match).
- Docs: `AGENTS.md` (`## Engine status` + guard fact row + test count), `.github/copilot-instructions.md`
  (status bullet, repo-first bullet), `docs/eco-power-README.md` and `docs/rollback.md` retired
  banners. The case17/case20 SKIPPED contract and every `##` anchor are untouched; case19/20 green.
- Gate: `./tests/run` → 126/126. `genarch-settings`: `cargo test` → all green.

## Not done (deliberate)

- The shell tree is **not** deleted (plan W9's `git rm -r eco lib state tests/fixtures tests/stubs`
  step). Deletion waits for the cross-repo contract file to replace the docs gate's source of
  anchors; until then the gate stays green on the retired tree and the marker is the safety.
- Cross-repo contract file (check IDs + doc anchors owned by this repo, pinned in
  `genarch-settings`) — open item in `genarch-settings/docs/DESIGN.md`.
- Commit disposition for both repos.
