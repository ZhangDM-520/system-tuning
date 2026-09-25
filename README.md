# eco-power

Source of truth for the power-efficiency stack of this machine (ASUS Zenbook S 16 UM5606WA,
CachyOS, Ryzen AI 9 HX 370). **Doctrine: efficiency is work per joule. Race to sleep. Never power
caps or throttling; V/f sweet-spot ceilings are legitimate.** The live system converges to this
repo every 600 seconds and after boot, resume, and AC events. Live is never the place to make a
change: edit here, apply, commit.

## Commands

| Command | Effect | Writes | Root |
|---------|--------|--------|------|
| `./eco` (same as `./eco report`) | read-only verdict: one line per check | no | no (SMU lines SKIP without it) |
| `./eco report --json` | same verdict, machine-readable | no | no |
| `./eco apply --dry-run` | print the convergence plan | no | no |
| `./eco apply` | converge live to repo, verify, report | yes (dated backups first) | yes |
| `./eco harvest` | print a proposal: live drift folded into state files | no (proposal only) | no |

Unknown arguments print this command set and exit 2, so a mistyping cold caller learns the
interface from the failure.

## Exit codes (shared)

| Code | Meaning | Caller action |
|------|---------|---------------|
| 0 | green: only OK / ACCEPTED / WARN rows | none |
| 1 | DRIFT present (report) or persisted after apply | read the anchored rows; apply or roll back |
| 2 | precondition failure: bad argument, lock held by the 600s converger, missing state file | fix environment, retry |
| 3 | apply failed partway | output lists applied and not-applied targets plus rollback anchors |

## Verdict classes

- `OK`: live matches intent.
- `ACCEPTED`: a settled decision where live legitimately differs (for example the STAPM readback
  sits below the written 31 W: firmware preference, accepted). **Never "fix" an ACCEPTED row.**
- `WARN`: a known quirk or expected transient (for example the SD reader re-bound after a reboot).
  Exit 0, action is a judgment call, anchor explains it.
- `DRIFT`: actionable mismatch between repo and live.

## Rules of the road

1. **Repo first.** Hand edits to live are reverted by the 600s convergence chain by design. Want
   it otherwise: change state/, `./eco apply`, commit. Deliberate live experiments: capture them
   with `./eco harvest` before the converger reverts them.
2. **One place per knob.** Each tunable appears exactly once under `state/`. `grep -rn <value> state/`
   must return one hit. If two, the repo is wrong.
3. **Idempotence.** `./eco apply` twice equals once; the second run plans nothing.
4. **Foreign files are edited by one anchored line**, never whole-file rewritten. Unclaimed bytes
   survive. Zero or multiple anchor matches fails hard before any write.
5. **Backups before writes**: `cp -p <file> <file>.bak-YYYYMMDD`, alongside, never deleted.
6. **Tty login is the recovery domain.** Nothing here may touch the bootloader, initramfs, or
   anything tty login depends on. A broken stack must still boot to a tty.
7. **Commit messages carry the check ID** (`CEIL: Zen5c 2.9 -> 2.8GHz`), so `git log --grep CEIL`
   is the history of one knob. Co-author trailer on every commit.

## Check registry

| ID | Asserts | Policy | Anchor |
|----|---------|--------|--------|
| EPP | energy preference `dynamic` on every policy | tunable | decisions#epp |
| CEIL | cpufreq ceilings: Zen5 4.6 GHz, Zen5c 2.9 GHz (V/f sweet spots) | settled | decisions#ceil |
| CO | curve optimizer final: coall -7, per-core -24 -24 -21 -21 -9 -11 -8 -6 | settled | decisions#co |
| PPT | envelope 31/31/31 W, stapm-time 128; STAPM readback ACCEPTED below 31 | settled | decisions#ppt |
| ECO | SMU `--power-saving` asserted (CCLK boost setpoint lowered) | tunable | decisions#eco |
| WIFI | WiFi power-save on (iw + NM + udev + TLP layers agree) | tunable | fleet-findings#wifi |
| BT | btusb `enable_autosuspend=Y`, old no-autosuspend file stays disabled | habit | decisions#bt |
| TLP | TLP policy file intact (ASPM powersave, EPP dynamic, PM auto) | tunable | fleet-findings#pcie |
| TIMER | eco-power backstop at 600s, canary-verified | settled | decisions#timer |
| IO | dirty writeback/expire 6000/6000, journald cap 32M | tunable | fleet-findings#storage |
| SCHED | scx_lavd powersave_mode `--powersave` (not the nonexistent `--efficiency`) | tunable | fleet-findings#sched |
| PROFILE | asusd battery profile maps to a firmware-supported choice | settled | quirks#asusd |
| SD | SD reader unbound (runtime only, lost at reboot) | recovery-only | rollback#sd |
| MISC | acp power gating on, localsearch masked, niri autostart spawns hw-tune | mixed | rollback#misc |

Policy: **settled** means do not reopen without new owner validation; **tunable** means change it
through the repo flow above; **habit** means the human does it by hand and the report only
observes; **recovery-only** means the entry exists to undo, not to tune.

## Cold start order (a future agent, zero memory)

1. This file, top to bottom. Roughly one screen.
2. `./eco report`. Facts before prose about facts. Every row names its own doc anchor.
3. `git log --oneline -n 20` only if the report surprises you.
4. Exactly one doc, chosen by the question (map below).
5. Never read `state/` end to end. Grep it.
6. Ship any change: edit state/ -> `./eco apply --dry-run` -> `./eco apply` -> commit with check ID.

## Doc map

| Doc | The one question it answers |
|-----|------------------------------|
| docs/doctrine.md | may I make this change at all? |
| docs/decisions.md | is this settled, and why? |
| docs/fleet-findings.md | has this been researched, and was it rejected? |
| docs/hardware-quirks.md | is this readback a bug or the hardware lying? |
| docs/reboot-checklist.md | what must I verify around a reboot? |
| docs/rollback.md | how do I undo one target? |
| docs/measurement.md | how do I measure watts honestly? |
