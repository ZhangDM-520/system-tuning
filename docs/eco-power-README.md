# eco-power

Source of truth for the power-efficiency stack of this machine (ASUS Zenbook S 16 UM5606WA,
CachyOS, Ryzen AI 9 HX 370). **Doctrine: efficiency is work per joule. Race to sleep. Never power
caps or throttling; V/f sweet-spot ceilings are legitimate.** The live system converges to this
repo at boot (the resume hook re-asserts the SMU runtime knobs; the 600 s backstop timer and the
AC-event trigger were dropped 2026-10-11, and the 4.7/3.2 ceiling has its own drift-only watch —
`eco-ceil.timer` + power-event udev — since 2026-10-29). Live is never the place to make a
change: edit here, apply, commit.

## Commands

| Command | Effect | Writes | Root |
|---------|--------|--------|------|
| `./eco` (same as `./eco report`) | read-only verdict: one line per check | no | no (SMU lines SKIP without it) |
| `./eco report --json` | same verdict, machine-readable | no | no |
| `./eco apply --dry-run` | print the convergence plan | no | no |
| `./eco apply` | converge live to repo, verify, report | yes (dated backups first) | yes |
| `./eco harvest` | print a proposal: live drift folded into state files | no (proposal only) | no |
| `./tests/run` | the harness gate (see `tests/run` for the case list) | no | no |

Unknown arguments print this command set and exit 2, so a mistyping cold caller learns the
interface from the failure.

## Exit codes (shared)

| Code | Meaning | Caller action |
|------|---------|---------------|
| 0 | green: no DRIFT (rows may be SKIPPED where a check needs root or a user session) | none |
| 1 | DRIFT present (report) or persisted after apply | read the anchored rows; apply or roll back |
| 2 | precondition failure: bad argument, lock held by a concurrent converge run, missing state file | fix environment, retry |
| 3 | apply failed partway | output lists applied and not-applied targets plus rollback anchors |

## Verdict classes

- `OK`: live matches intent.
- `ACCEPTED`: a settled decision where live legitimately differs (for example the STAPM readback
  sits below the written 31 W: firmware preference, accepted). **Never "fix" an ACCEPTED row.**
- `WARN`: a known quirk or expected transient (for example the SD reader re-bound after a reboot).
  Exit 0, action is a judgment call, anchor explains it.
- `DRIFT`: actionable mismatch between repo and live.
- `SKIPPED`: a check that needs root or a user session; counted green, means unverified.

## Rules of the road

1. **Repo first.** Hand edits to live are reverted at the next convergence run (boot) by design: the
   runtime knobs re-converge via eco-power.sh, and file state converges via the `eco apply`
   appended as the second ExecStart of the same chain (ExecStart=-, so a missing repo or a failed
   apply can never break the boot-critical path). A manual `sudo ./eco apply` holding the lock
   makes a chain run skip its apply step safely (the ExecStart=- prefix swallows that exit), while
   the run still re-asserts the runtime knobs. The change flow is `docs/rollback.md`
   `## Converge a change`; deliberate live experiments: capture them with `./eco harvest` before
   the converger reverts them.
2. **One place per knob.** Each tunable appears exactly once under `state/`. `grep -rn <value> state/`
   must return one hit. If two, the repo is wrong.
3. **Idempotence.** `./eco apply` twice equals once; the second run plans nothing.
4. **Foreign files are edited by one anchored line**, never whole-file rewritten. Unclaimed bytes
   survive. Zero or multiple anchor matches fails hard before any write.
5. **Backups before writes**: every write gets a dated `cp -p` backup alongside, never deleted —
   the universal mechanism is `docs/rollback.md` `## Undo: universal mechanism`.
6. **Tty login is the recovery domain.** Nothing here may touch the bootloader, initramfs, or
   anything tty login depends on. A broken stack must still boot to a tty.
7. **Commit messages carry the check ID** (`CEIL: Zen5c 3.0 -> 2.8GHz`), so `git log --grep CEIL`
   is the history of one knob. Co-author trailer on every commit.

## State layout

- **Owned** state is whole-file mirrors of foreign config at
  `state/owned/<live-path-without-leading-slash>` (e.g.
  `state/owned/etc/systemd/system/eco-power.service`). Byte-identical to live; apply is a
  full-file rewrite.
- **Managed** state is one record per anchored edit inside a foreign file
  (e.g. `state/managed/niri-autostart.toml`). Record keys: `target` (live path),
  `match` (POSIX ERE whose *first* hit names the exact line to edit), `line` (replacement text),
  `doc` (anchor), optional `section` (context hint: the record targets a line inside that
  region). Exactly one match must exist in the file (or within the section region: lines after
  its header until the next line starting with `[`); zero or multiple matches is a hard error
  before any write. Multi-line values are not supported inside a record.
- One place per knob and the backup guarantee are Rules 2 and 5 above — no second copy here.

## Check registry

| ID | Asserts | Anchor |
|----|---------|--------|
| EPP | power-profiles-daemon owns the profile/EPP path (active; EPP sane on every policy) | findings#epp |
| CEIL | cpufreq ceilings: Zen5 4.6 GHz, Zen5c 3.0 GHz (V/f sweet spots) | findings#ceil |
| CO | curve optimizer final: coall -7, per-core -24 -24 -21 -21 -9 -11 -8 -6 | findings#co |
| PPT | envelope 31/31/31 W, stapm-time 128; STAPM readback ACCEPTED below 31 | findings#ppt |
| ECO | SMU `--power-saving` asserted (CCLK boost setpoint lowered) | findings#eco |
| WIFI | WiFi power-save on (iw + NM + udev + TLP layers agree) | findings#wifi |
| BT | btusb `enable_autosuspend=Y`, old no-autosuspend file stays disabled | findings#bt |
| TLP | TLP policy file intact (ASPM powersupersave, PM auto; EPP yielded to PPD) | findings#pcie |
| TIMER | eco-power.service boot-only for SMU paths (backstop timer + AC trigger dropped 2026-10-11), chains eco apply; eco-ceil watch active (timer + power-event udev) | findings#timer |
| IO | dirty writeback/expire 6000/6000, journald cap 256M | findings#writeback |
| SCHED | scx management dropped 2026-10-10 (scx-tools layout change, rework deferred) — reports `SKIPPED`, scheduling is owner-managed | findings#sched |
| PROFILE | asusd power-profile handling muted (casts + AC/battery switching off) and platform_profile sane | findings#asusd |
| SD | SD reader unbound (runtime only, lost at reboot) | rollback#sd |
| MISC | acp power gating on, localsearch masked, niri autostart spawns hw-tune | rollback#misc |

Settled/tunable/habit verdicts live in each finding's `Class:` field in `docs/findings.md`.

## Cold start and change flow

1. This file, top to bottom.
2. `./eco report`. Facts before prose about facts. Every row names its own doc anchor.
3. `git log --oneline -n 20` only if the report surprises you.
4. Exactly one doc, chosen by the anchor (below). Never read `state/` end to end — grep it.
5. Ship any change through `docs/rollback.md` `## Converge a change` (edit -> apply -> commit),
   which is the single home of that flow.

## Finding the writeup

Anchors are the doc map (there is no map table):

- `findings#<slug>` → entry `## <slug>` in `docs/findings.md` — settled judgments, machine lies,
  rejected probes, evidence; one entry per knob, the slug is the entry heading.
- `rollback#sd`, `rollback#misc` → `## sd` / `## misc` in `docs/rollback.md`, the operations
  runbook (undo, convergence, reboot/suspend habits, storage ops).
- Methodology and rules: `docs/judgment.md` (cheating vs legitimate variance, derived rules).

If an anchor is missing or wrong, the heading list is the escape hatch:
`grep -n '^#' docs/*.md`.
