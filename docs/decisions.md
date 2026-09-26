# Decisions

When to read: before changing any value, to learn whether the question is already settled.
Each entry: verdict, rationale, and what would reopen it. Grilling Q numbers are the audit trail.

## epp

Energy preference `dynamic` on every policy (amd-pstate-epp). Q: plan v2.
Why: `dynamic` follows platform profile and power source and currently resolves performance-biased,
which is race-to-sleep correct (fast ramp to the ceiling, then deep idle). A `power`/`balance_power`
EPP makes firmware creep slowly: mechanism-opposite to the doctrine.
Reopen: only with measured joules-per-op evidence.

## ceil

Zen5 cores 4.6 GHz, Zen5c cores 3.0 GHz (per-class scaling_max_freq). Q: owner, voltage-sensitivity
testing 2026-09-26 (supersedes the earlier 3.1 -> 3.0 -> 2.9 step-down).
Why: Zen5 5.1 -> 4.6 buys a stable undervolt (avg CO -20 vs -10), a real V/f sweet-spot win. Zen5c
caps at 3.1/3.0/2.9 were all voltage-sensitive: Zen5c sits near its sweet point, below the V/f hill,
so lower caps lose real performance for minimal power saving. Settled at 3.0 GHz.
Reopen: new voltage-sensitivity data showing the Zen5c knee moved. Boost stays ON: the ceiling
already clips it, and disabling boost would drop the hardware max to ~2.0 GHz base.

## co

Curve Optimizer FINAL: `coall -7`, per-core `-24 -24 -21 -21 -9 -11 -8 -6`. Q6: owner confirmed the
deep list was CoreCycler-validated ("validated-keep").
Why: free efficiency at unchanged temperature; owner margin rule is one step, and the tested point
is the boundary. Reopen: never opportunistically. Only a new full stability campaign may move it.
Cores 8-11 (Zen5c remainder) fall back to coall -7 by the packing rule.

## ppt

Envelope flat 31/31/31 W (stapm/fast/slow), `stapm-time=128`, `slow-time=1`. Q3-era: the flat
envelope replaced the asusd 28/28/17 profile to kill throttle oscillation. stapm-time 128 smooths
the leaky bucket so bursts are not interrupted mid-work: it is a time constant, not a cap.
**STAPM readback sits below 31 W right now (17-20 W class): ACCEPTED as firmware preference.**
Q5/Q14/Q16: replug tested, the 28 W hypothesis tested (write succeeds, readback re-floored,
value-independent), owner ruling: keep writing 31000, treat the readback as firmware policy.
Reopen: only if the floor appears while on AC with battery full.

## eco

SMU `--power-saving` flag asserted in hw-tune.fish. Lowers the CCLK boost setpoint (24 -> ~5-7),
so the SMU itself delays boost entry: idle race-to-sleep without any cap. Reopen: if a workload
shows measurable harm.

## bt

Bluetooth: `enable_autosuspend=Y` stays (old `btusb-no-autosuspend.conf` remains `.disabled`).
Q1/Q13: the adapter is `Powered:yes` while bluetoothd runs, so the USB device only suspends once
the radio is off. Owner ruling: manual habit ("bluetoothctl power off" when not using BT), NO
automation, no config beyond the module param. Reopen: if the habit proves annoying.

## timer

eco-power backstop `OnUnitActiveSec=600s`, canary-verified (one 11-minute window, zero drift).
Q4/Q15: all known SMU-reset events are already event-driven (boot, resume, AC uevent); the timer
guards unknown drift only. Fallback policy: if a canary ever shows drift inside the window,
auto-settle at 300s and report. Reopen: any observed drift recurrence.

## autosuspend

Noctalia idle auto-suspend stays **disabled** (timeout 900s exists but `enabled=false`). Q7:
owner ("my current idle behaviour is good"). The 70s screen-off chain remains the deepest-sleep
trigger. Reopen: only owner initiative.

## sd

SD reader unbound at runtime (card absent, sdhci-pci). Q8: "investigate-unbind", facts confirmed
safe (standard surprise-removal teardown, no card registered). Runtime-only: a reboot re-binds it,
reported as WARN, not DRIFT. Boot persistence was explicitly left undecided. Reopen: owner decides
persistence; see rollback#sd.

## asusd-profile

asusd `platform_profile_on_battery: Balanced` (was Quiet). Q10: firmware choices are only
balanced/performance, so the Quiet write failed EOPNOTSUPP on every battery event. Fixing it
restores the designed behavior; eco-power re-converges after each platform_profile write (which
resets SMU limits through the EC). Reopen: if firmware re-exposes quiet.

## config-fixes

Q2/Q3/Q11: NM `wifi.powersave=3` (future profiles must not silently disable power-save), dirty
writeback/expire 6000/6000 persisted (the runtime value was being lost at every sysctl reload),
localsearch-3 masked (owner accepted GNOME app-search degradation), journald SystemMaxUse=32M.

## process

Q12: changes land in two waves with `cp -p ... .bak-YYYYMMDD` backups before every write; verify
after each wave; no blind parallel bursts onto a live system.
