# Judgment — may I change, may I claim

When to read: before proposing any tuning; before claiming any saving.

## May I change?

### The one rule — work per joule

**Power efficiency is work produced per joule, not watts consumed.** A setting that lowers draw
while lowering output proportionally more is a regression wearing a green costume. A change ships on
mechanism + judgment; it *stays* only if a measurement confirms it or the owner rules it settled
(`docs/findings.md` records which of the two applies).

### Derived rules: race-to-sleep / no caps / devices sleep / wakeups / firmware floors / stability / recovery domain

1. **Race to sleep.** Finish the work fast at the V/f sweet spot, then let everything drop into deep
   idle. Long slow execution at low voltage is the anti-pattern: worse efficiency for bursty desktop
   work, and it keeps devices awake longer.
2. **No power caps, no forced throttling.** STAPM/PPT caps, thermal-limit lowering, forced
   downclocks, current limits: all "cheating" — they bound watts without improving efficiency.
   Ceilings at the V/f sweet spot are legitimate: they remove only the inefficient tail of the curve
   (5.1+ GHz on Zen5) while bursts still reach the ceiling instantly. Zen5c is the counter-example:
   it sits below the V/f hill near its sweet point, so its settled 3.0 GHz ceiling is an owner
   compromise, not a tail trim.
3. **Devices must sleep.** Autosuspend, runtime PM, ASPM, radio power-save, audio codec power-down.
   Idle silicon burns watts for zero work, but never break a device to save its watts (see below).
4. **Reduce wakeups, not capability.** Fewer timer wakeups, fewer flusher runs, fewer daemons
   polling: real efficiency wins. Disabling a feature the owner uses is a usability cost, not an
   efficiency win, and needs an explicit owner decision (see `docs/findings.md`).
5. **Firmware floors are policy, not defects.** When firmware clamps us (battery derating, STT skin
   models), we keep our intent expressed in state/ and report the readback as ACCEPTED. Fighting
   firmware floors with re-write storms is not tuning.
6. **Stability outranks everything.** Undervolt/CO depth is validated empirically (CoreCycler class
   testing) and then frozen. Silent instability corrupts data; a boot failure at least announces
   itself. Never step CO deeper than validated.
7. **Recovery domain is sacred.** Nothing in this repo may endanger tty login, the bootloader, or
   the initramfs. TTY login is how this machine gets fixed.

### What counts as cheating

Rejected by default:

- Lowering thermal limits (tctl, skin) to force earlier throttling
- Sustained power limits as a goal (28 W total draw was the *envelope*, not a metric)
- Disabling boost outright (drops the hardware ceiling to base clocks, below the sweet spot)
- Forcing fixed clocks (kills the idle tail and burst headroom)
- Turning off features the owner uses to move watts off the meter

### What counts as legitimate

- V/f ceilings at measured sweet spots
- Curve Optimizer at validated depth (free efficiency at the same temperature)
- SMU behavioral flags that lower idle setpoints (`--power-saving`)
- Longer STAPM time constants (fewer mid-burst corrections, not a cap)
- Sleep/wakeup hygiene: autosuspend, ASPM, longer writeback intervals, fewer timers
- Schedulers that compact work (fewer awake cores), given the EPP and ceilings already race to sleep

## May I claim?

Measurement is mandatory for claims, optional for maintenance. Claims ship only through this
protocol.

### The honest metric (J/work; idle floor; work efficiency)

**Work produced per joule.** Wall-plug or RAPL watts alone say nothing: a throttle that cuts watts
20% and throughput 30% is a regression. The two honest measurements are:

1. Idle draw: watts at screen-on idle and screen-off idle (the floor).
2. Work efficiency: throughput of a fixed task divided by package energy for that task (joules per
   operation is the inverse; lower is better).

RAPL is the energy oracle: package `energy_uj` deltas per slot (root-only); the battery is unusable
here (AC with an 80% charge cap, `power_now` reads 0). Report J per unit of work, not watts alone.
When measuring work efficiency, fix the work: same input, same warm-up, same core placement
expectations (the compacting scheduler deliberately parks work on few cores). Baseline numbers are
anchors for regression checks, not targets — never "optimize" toward a watt number.

### The two gates, the n floors, the adoption rule

1. **Two gates, in order.** Gate 1 — the effect must exceed the control's own min/max spread (an
   effect inside it is not a result, whatever the p-value). Gate 2 — Mann-Whitney U, tie-corrected,
   two-sided, p < 0.05. Medians relative to the control's median, never means.
2. **Adoption rule.** Separates on ≥1 relevant metric, no metric significantly worse, mechanism
   understood.
3. **n floors.** n ≥ 3 screening; n ≥ 5 per arm for adoption or refutation. An n=2 verdict is capped
   at INCONCLUSIVE: MW-U cannot reach the Gate 2 threshold at n=2 vs 2 — minimum two-sided p =
   0.333.

### Run design — interleave, rotate, discard rep 0, cache state, within-pass

- Interleave arms inside every repetition and rotate the starting arm; cache state is part of the
  arm.
- Discard the warm-up: repetition 0 is excluded (first-slot contamination); a discarded warm-up slot
  belongs at the front of any run.
- Within-pass comparisons only: a display-blank regime shift moved both anchors between passes, so
  cross-pass deltas silently mix the treatment with the regime change.

### Arm identity — read back from the consumer (two sources; exit codes never trusted)

Verify each arm twice, from two independent sources — read the setting back **from where the
consumer reads it** (`/proc/mounts`, sysfs, `/proc/cmdline`, `NetworkManager --print-config`), never
from the file that was edited. A row whose two sources disagree is invalid; exit codes are never
trusted. Mechanism evidence: two XFS mount-option campaigns (filestreams, allocsize) were silently
inert while `remount` returned rc=0.

### Conditions and non-measurements (AC/battery/screen; silent-failure readback ≠ measurement; converger-600s window; kernel change = new baseline)

- Record conditions with every number: AC state, battery %, screen on/off, scheduler, EPP, whether
  the convergence timer had just fired (it can perturb a short window).
- AC/battery/screen state and the 80% charge cap change the firmware floor and decide which energy
  source is usable (findings#ppt).
- The eco converger fires on a 600 s window: never let a short measurement window span it.
- Never benchmark while an undervolt/CO stability campaign is running: the benchmark load interferes
  with the stability test and the numbers lie twice.
- Silent-failure checks (SMU readback, verify runs) are not measurements and must not be reported as
  savings (findings#ppt: the firmware lies in specific documented ways).
- A kernel change is a new baseline, not a reproduction.

### The harness (power-lab interface only; RAPL domain)

`~/Workspace/power-lab/` is kept there as a scratch lab; this repo records its interface only:

| Tool | Purpose |
|------|---------|
| `rapl-watts.sh` | sample RAPL package power over a window (idle floor, quick checks) |
| `measure-power.sh` | scripted load + RAPL integration -> joules for a fixed unit of work |
| `bench-perf.sh` | throughput runs for the denominator (stress-ng/hyperfine based) |
| `results/` | dated measurement records |

RAPL domain: package energy on the Strix Point APU (`powercap/intel-rapl` style counters exposed by
the kernel; verify the domain path before trusting numbers). Battery state, screen state, and AC
state must be recorded with every measurement: they change the firmware floor (findings#ppt).

## Behind the seam

Published implementation + confound catalogue: `benchmarks/METHODOLOGY.md` §8 — measured magnitudes
live there (:153-190); cite, never copy.
