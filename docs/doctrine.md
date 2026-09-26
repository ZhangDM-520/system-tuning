# Doctrine

When to read: before proposing any new tuning, and whenever a change feels like it "saves power".

## The one rule

**Power efficiency is work produced per joule, not watts consumed.** A setting that lowers draw
while lowering output proportionally more is a regression wearing a green costume.

## Derived rules

1. **Race to sleep.** Finish the work fast at the V/f sweet spot, then let everything drop into
   deep idle. Long slow execution at low voltage is the anti-pattern: worse efficiency for bursty
   desktop work and it keeps devices awake longer.
2. **No power caps, no forced throttling.** STAPM/PPT caps, thermal-limit lowering, forced
   downclocks, current limits: all "cheating". They bound watts without improving efficiency.
   Ceilings at the V/f sweet spot are legitimate: they remove only the inefficient tail of the
   curve (5.1+ GHz on Zen5) while bursts still reach the ceiling instantly. Zen5c is the
   counter-example: it sits below the V/f hill near its sweet point, so its settled 3.0 GHz
   ceiling is an owner compromise, not a tail trim.
3. **Devices must sleep.** Autosuspend, runtime PM, ASPM, radio power-save, audio codec power-down.
   Idle silicon burns watts for zero work. But never break a device to save its watts (see below).
4. **Reduce wakeups, not capability.** Fewer timer wakeups, fewer flusher runs, fewer daemons
   polling: these are real efficiency wins. Disabling a feature the owner uses is a usability
   cost, not an efficiency win, and needs an explicit owner decision (see decisions).
5. **Firmware floors are policy, not defects.** When firmware clamps us (battery derating, STT
   skin models), we keep our intent expressed in state/ and report the readback as ACCEPTED.
   Fighting firmware floors with re-write storms is not tuning.
6. **Stability outranks everything.** Undervolt/CO depth is validated empirically (CoreCycler
   class testing) and then frozen. Silent instability corrupts data; a boot failure at least
   announces itself. Never step CO deeper than validated.
7. **Recovery domain is sacred.** Nothing in this repo may endanger tty login, the bootloader, or
   the initramfs. TTY login is how this machine gets fixed.

## What counts as cheating (rejected by default)

- Lowering thermal limits (tctl, skin) to force earlier throttling
- Sustained power limits as a goal (28 W total draw was the *envelope*, not a metric)
- Disabling boost outright (drops the hardware ceiling to base clocks, below the sweet spot)
- Forcing fixed clocks (kills the idle tail and burst headroom)
- Turning off features the owner uses to move watts off the meter

## What counts as legitimate

- V/f ceilings at measured sweet spots
- Curve Optimizer at validated depth (free efficiency at the same temperature)
- SMU behavioral flags that lower idle setpoints (`--power-saving`)
- Longer STAPM time constants (fewer mid-burst corrections, not a cap)
- Sleep/wakeup hygiene: autosuspend, ASPM, longer writeback intervals, fewer timers
- Schedulers that compact work (fewer awake cores), given the EPP and ceilings already race to sleep
