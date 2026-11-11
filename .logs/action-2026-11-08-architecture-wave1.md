# Action summary — 2026-11-08 — architecture audit, Wave 1 (strong findings)

Source: `/tmp/architecture-review-20261108T232052.html` (six deepening candidates). Owner split the
work: Wave 1 implements the Strong findings immediately; Wave 2 only investigates the rest
(`/tmp/architecture-wave2-rationale.md`).

## What changed

### 1 — One ceiling rule (was: reader and writer classified differently)

- NEW `state/owned/usr/local/lib/eco-ceil.sh` — the class map (Zen 5 = CPUs 0–3,12–15), the
  4.7/3.2 GHz constants (`ECO_CEIL_ZEN5`/`ECO_CEIL_ZEN5C`) and `eco_ceil_want_for_policy`
  (topology wins; `cpuinfo_max_freq` only when `related_cpus` is unreadable; any Zen 5 core in a
  policy takes 4.7).
- NEW `lib/ceiling.sh` — the CLI loads that one file (fails fast if missing).
- `lib/readers.sh` `check_ceil` — classification deleted; uses the shared function. `ceil_for_cpu`
  is gone.
- `state/owned/usr/local/sbin/eco-power.sh` `apply_ceil` — sources `/usr/local/lib/eco-ceil.sh`
  (fail-soft: a first boot before deploy skips the pass rather than guessing) and holds no literal.
- Docs: `## ceil` Evidence rewritten; `.github/copilot-instructions.md` topology pointer moved.

Why it mattered: the writer tested `cpuinfo_max_freq > 4400000` alone. A low readback on a Zen 5
policy (boost off, CPB gated, driver change) would cap Zen 5 at 3.2 GHz, see `cur == want`, log
nothing, and leave the reader DRIFTing forever — a silent power cap, which `docs/judgment.md` calls
cheating rather than a tail trim.

### 2 — Managed-record verification collapsed; `CHECK_MANAGED` made live

- `lib/managed.sh`: `managed_problem_text` (one message shape) and `managed_check_problems`
  (records from the registry, appends into the caller's array, returns 1 on any problem).
- `lib/registry.sh`: `CHECK_MANAGED` now carries record **lists** — it was declared and never read,
  so editing it was a silent no-op, and `check_profile` hardcoded five IDs.
- `lib/readers.sh`: the six `case $MP_STATE` blocks in four readers collapse to one call each;
  `check_profile` no longer names its records.

### 3 — CO/ECO assert the live file, not the repo mirror

- `check_co`/`check_eco` now read `live_path(/home/zhangdm/.reserve/hw-tune.fish)` and require
  `mirror_equal`. An intent-only read reported OK while live was stale or missing.

## Live actions

- Found and fixed an unrelated regression the TIMER row caught: `eco-ceil.timer` was **disabled**
  (the `timers.target.wants` symlink dropped 2026-11-07; cause unidentified) — re-enabled with
  `systemctl enable --now`. Recorded in `## timer`.
- `./eco apply` deployed the new `/usr/local/lib/eco-ceil.sh` + the updated
  `/usr/local/sbin/eco-power.sh` (2 owned files, backups taken).
- `sudo /usr/local/sbin/eco-power.sh ceil` on the deployed copy: no `CEIL DRIFT` lines — the shared
  rule classifies all 24 policies exactly as before (behaviour-preserving).
- `./eco report` after: drift=0 (SD WARN is the known runtime-unbind row).

## Tests

`tests/run`: 106/106 (was 97).
- case23: topology beats a low `cpuinfo_max_freq` (the exact divergence) + the writer sources the
  shared rule and restates no literal.
- case24: live `hw-tune.fish` drift and a missing live file both DRIFT CO.
- case25: readers do not restate the asusd record set, `CHECK_MANAGED[PROFILE]` carries five, and a
  drift on the last table record is caught.

Note: `set -e` in `eco` + a non-zero managed result aborted silently on the first run; callers now
use `|| true` (or `if`) — worth remembering for any future `managed_check_problems` caller.

## Pre-existing work in the tree (not mine, left untouched)

`state/owned/etc/fstab` (btrfs shrink + F2FS `/tmp`) and a `docs/JOURNAL.md` entry for it were
already uncommitted when this wave started. They were excluded from this commit; `docs/JOURNAL.md`
holds both entries and is therefore left uncommitted (shared-file rule).

## Wave 2 (investigation only)

See `/tmp/architecture-wave2-rationale.md`: C4 "one definition of converged" (measured: report exit
1 / apply exit 0 on the same tree; 10 of 14 rows are outside apply), C5 deployable filter (a stray
`.bak` in `state/owned/.../system-sleep/` is planned as an owned target — proven on an isolated
copy), C6 registry as a seam (rejecting "tests read IDs from the binary" because it destroys the
independent oracle).
