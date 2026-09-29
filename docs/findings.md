# Findings — one entry per knob

**Purpose.** The only knob-truth home for this host (ASUS Zenbook S 16 UM5606WA, Ryzen AI 9 HX 370,
  CachyOS, XFS root on WD SN560). One `##` entry per knob; each entry answers, with nothing else
  read: what is true/applied and why (mechanism, owner rulings with their grilling-Q trail,
  superseded claims with their scope); what backs it and how to check it live; what has been
  refused; and what would reopen it. Operational modules keep their own depth: undo commands in
  `docs/rollback.md` (rollback#sd, rollback#misc), storage operations in `docs/rollback.md`
  (`## Storage ops`), campaigns and recipes in `docs/XFS-TUNING.md`, measurement protocol in
  `benchmarks/METHODOLOGY.md`, judgment rules in `docs/judgment.md`. A few entries name the `./eco report`
  check that observes the knob; the check registry itself stays in the eco contract module.

**How to read Evidence.** Handles name surviving artifacts (`state/owned/…`, `state/managed/…`,
  `benchmarks/studies/…`, `benchmarks/METHODOLOGY.md`, `docs/XFS-TUNING.md`,
  `docs/rollback.md`, `./tests/run`) plus the live readback command that settles the claim on
  this host — you verify with the command, never with a log line. Kernel-scoped claims per
  `benchmarks/docs/MEMORY.md`: benchmark numbers are stamped to the campaign kernel
  `7.2.5-1-cachyos-rt-bore-lto` and the host has since moved on; a re-run on a different kernel is a
  new baseline, not a reproduction, and historical figures are never edited to match. XFS
  mount-option behaviour is kernel-version-specific.

**Do not re-propose without new evidence.** Every `Rejected here` line is a refusal with its scope;
  the same candidate returns only with new evidence (usually a measurement on the current kernel).
  Most refusals come from the 2026-09-24 research wave (8 parallel read-only agents) plus the
  implementation wave that followed. An odd readback is not evidence that a setting failed until the
  entry's `Machine lies` field is consulted.

**Class.** labels are the policy vocabulary of `docs/eco-power-README.md`: **settled** = do not
  reopen without new owner validation; **tunable** = change it through the repo flow (`state/` →
  `./eco apply`); **habit** = the human acts by hand and the report only observes; **recovery-only**
  = the entry exists to undo, not to tune; **mixed** = more than one of these applies.

## epp

**Verdict.** Energy preference `dynamic` on every cpufreq policy (amd-pstate-epp active mode) —
  applied (check EPP) · **Class:** tunable
**Why.** `dynamic` follows platform profile and power source and currently resolves
  performance-biased, which is race-to-sleep correct (fast ramp to the ceiling, then deep idle). A
  `power`/`balance_power` EPP makes firmware creep slowly: mechanism-opposite to the doctrine. Owner
  ruling (grilling Q: plan v2). Superseded with scope: the benchmark era's `balance_power` uniform
  (test bed) and `balance_performance`-optimal (study 02) — both stamped to the campaign kernel and
  superseded by owner-settled `dynamic`.
**Evidence.** `state/owned/etc/tlp.d/01-eco.conf` (governor + EPP + boost policy);
  `state/owned/usr/local/sbin/eco-power.sh` re-asserts EPP after every event. Check:
  `cat /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference` (every policy reads
  `dynamic`) and the `./eco report` EPP row.
**Reopen.** only with measured joules-per-op evidence.

## ceil

**Verdict.** Per-class `scaling_max_freq` ceilings: Zen 5 4.6 GHz, Zen 5c 3.0 GHz; boost stays ON —
  applied (check CEIL) · **Class:** settled
**Why.** Zen 5 5.1 → 4.6 buys a stable undervolt (avg CO −20 vs −10): a real V/f sweet-spot win, not
  a cap. Zen 5c caps at 3.1/3.0/2.9 were all voltage-sensitive — Zen 5c sits near its sweet point,
  below the V/f hill, so lower caps lose real performance for minimal power saving; settled at 3.0
  GHz (owner, voltage-sensitivity testing 2026-09-26 — supersedes the earlier 3.1 → 3.0 → 2.9
  step-down). Boost stays ON because the ceiling already clips it; disabling boost would drop the
  hardware max to ~2.0 GHz base.
**Evidence.** `state/owned/usr/local/sbin/eco-power.sh` (re-asserts 4.6/3.0 per policy by
  `cpuinfo_max_freq`); the CPU map `ceil_for_cpu` in `lib/readers.sh` (Zen 5 = CPUs 0–3,12–15; Zen
  5c = 4–11,16–23; mirrored in `.github/copilot-instructions.md`). Check:
  `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq` and the `./eco report` CEIL row.
**Rejected here.** boost off (hardware max drops to ~2.0 GHz base, below the 4.6 GHz sweet spot).
**Reopen.** new voltage-sensitivity data showing the Zen 5c knee moved.

## co

**Verdict.** Curve Optimizer frozen: `coall -7`, per-core `-24 -24 -21 -21 -9 -11 -8 -6` — applied
  (check CO) · **Class:** settled
**Why.** Free efficiency at unchanged temperature; the owner margin rule is one step and the tested
  point sits at that margin edge. Owner ruling Q6: the deep list was CoreCycler-validated
  ("validated-keep"). Cores 8–11 (Zen 5c remainder) fall back to `coall -7` by the packing rule.
  Packing mechanism: 16-bit two's complement, per-core payload `core_idx * 2^20 + offset`;
  `hw-tune.fish` is the single writer — never write CO values from anywhere else.
**Evidence.** `state/owned/home/zhangdm/.reserve/hw-tune.fish` (single SMU writer). Check:
  `sudo ryzenadj --info` — never the journal log (see `## ppt` Machine lies).
**Reopen.** never opportunistically; only a new full stability campaign may move it.

## ppt

**Verdict.** Envelope flat 31/31/31 W (stapm/fast/slow), `stapm-time=128`, `slow-time=1` — applied;
  the STAPM readback below 31 W (17–20 W class) — accepted as firmware preference (check PPT) ·
  **Class:** settled
**Why.** The flat envelope replaced the asusd 28/28/17 profile (Q3-era) to kill throttle
  oscillation. `stapm-time=128` smooths the leaky bucket so bursts are not interrupted mid-work: it
  is a time constant, not a cap. Q5/Q14/Q16: replug tested; the 28 W hypothesis tested (write
  succeeds, readback re-floored, value-independent); owner ruling: keep writing 31000 and treat the
  readback as firmware policy.
**Evidence.** `state/owned/home/zhangdm/.reserve/hw-tune.fish`. Check: `sudo ryzenadj --info`, never
  the log.
**Rejected here.** "fixing" the readback floor with re-write storms (never).
**Reopen.** only if the floor appears while on AC with battery full.
**Machine lies.** STAPM LIMIT reads below the written 31 W (17–20 W class) and drifts between
  consecutive reads — a dynamic derate (STT skin model or EC-latched battery floor), not a rejected
  number; `STAPM VALUE` pinning at the limit under load is the clamp being real (at idle VALUE is
  far below the limit and nothing is throttled); `StapmTimeConst` sometimes reads 0.000 despite
  `--stapm-time=128` applied and holding on other boots (artifact class, not drift);
  `CCLK Boost SETPOINT` fluctuates with load (that is what `--power-saving` moves); ryzenadj errors
  are structurally invisible in the convergence path (`hw-tune.fish` exits 0 unconditionally and its
  output is discarded) — the journal line "hw-tune.fish applied" certifies nothing about SMU
  acceptance.

## eco

**Verdict.** SMU `--power-saving` asserted — applied (CCLK boost setpoint 24 → ~5–7) (check ECO) ·
  **Class:** tunable
**Why.** Lowers the CCLK boost setpoint, so the SMU itself delays boost entry: idle race-to-sleep
  without any cap.
**Evidence.** `state/owned/home/zhangdm/.reserve/hw-tune.fish` (asserted by the single SMU writer).
  Check: `sudo ryzenadj --info`, `CCLK Boost SETPOINT` row (never the log).
**Reopen.** if a workload shows measurable harm.

## timer

**Verdict.** eco-power backstop `OnUnitActiveSec=600s` — applied, canary-verified (one 11-minute
  window, zero drift) (check TIMER) · **Class:** settled
**Why.** Q4/Q15: all known SMU-reset events are already event-driven (boot, resume, AC uevent —
  `state/owned/etc/udev/rules.d/99-eco-power.rules` triggers on power-source change); the timer
  guards unknown drift only. Fallback policy: if a canary ever shows drift inside the window,
  auto-settle at 300s and report. Superseded with scope: the older "5-min backstop" claim is
  falsified by the unit file itself (`OnUnitActiveSec=600s`); the previous 60 s cadence was 719
  runs/day of SMU writes and wake bursts before it was stretched to 600 s.
**Evidence.** `state/owned/etc/systemd/system/eco-power.timer`;
  `state/owned/etc/systemd/system/eco-power.service`. Check: `systemctl cat eco-power.timer`,
  `systemctl list-timers eco-power.timer`.
**Reopen.** any observed drift recurrence.

## wifi

**Verdict.** WiFi power-save ON end to end — applied (MT7925) (check WIFI) · **Class:** tunable
**Why.** Verified ON at every enforcement point: `iw` power_save=on, NM profile
  `802-11-wireless.powersave=3`, NM global `wifi.powersave=3` (Q2: the global was 2, which would
  silently disable power-save on any future profile), udev `81-wifi-powersave.rules`, TLP
  `WIFI_PWR_ON_AC/BAT=on`, mt76 `deep-sleep=1` and `runtime-pm=1`, PCIe ASPM L1. The chipset is
  **MT7925** (mt7925e/mt76) — every iwlwifi knob is N/A here, and on mt7925 neither fw_pwr_table
  (mt7966-class only) nor interrupt coalescing (no ethtool support) is tunable. bgscan is dormant at
  good signal (fires only below −65 dBm). Keep everything. Superseded with scope: study 02 adopted
  power-save **off** (idle RTT 24.8 → 15.4 ms, no measurable energy cost) — superseded by ON
  (owner-settled for wakeup/radio-sleep doctrine); the latency cost is the recorded known trade.
  That era's NM files were also self-contradictory (a `d`-sorting file silently won).
**Evidence.** `state/owned/etc/NetworkManager/conf.d/99-wifi-powersave.conf`;
  `state/owned/etc/udev/rules.d/81-wifi-powersave.rules`; `state/owned/etc/tlp.d/01-eco.conf`.
  Check: `iw dev wlan0 get power_save`, `grep -R powersave /etc/NetworkManager/`, and the
  `./eco report` WIFI row.

## bt

**Verdict.** btusb `enable_autosuspend=Y` stays (old `btusb-no-autosuspend.conf` remains
  `.disabled`) — applied; the radio itself is an owner habit (check BT) · **Class:** habit
**Why.** Q1/Q13: the adapter reads `Powered:yes` while bluetoothd runs, so the USB device only
  suspends once the radio is off. Owner ruling: manual habit — `bluetoothctl power off` when not
  using BT — no automation, no config beyond the module param. History: the autosuspend flag was
  dead because an older `btusb-no-autosuspend.conf` shadowed the modprobe file (fixed by renaming
  the old file `.disabled`).
**Evidence.** `state/owned/etc/modprobe.d/99-bt-autosuspend.conf`;
  `state/owned/etc/udev/rules.d/98-bt-autosuspend.rules`. Check: `ls /etc/modprobe.d/` (old file
  must stay `.disabled`), `bluetoothctl show` (`Powered` follows the radio), and the `./eco report`
  BT row.
**Reopen.** if the habit proves annoying.

## pcie

**Verdict.** Global ASPM policy `powersave` (L1 on 30/35 links; the 5 BIOS-disabled links
  runtime-suspend anyway), runtime PM `auto` on all 40 PCI devices, zero armed wake sources —
  applied (check TLP observes the policy file) · **Class:** tunable
**Why.** L1.2 is capable on the NVMe/SD/WiFi paths but disabled everywhere, and the only enabler is
  the global `powersupersave`, which is instability-proven on this box; per-device `aspm_mask` does
  not exist in this kernel. Dead end: do not chase. The NVMe link runs Gen3 x4 (downgraded from the
  Gen4 cap) and stays there — forcing Gen4 costs watts. No `pcie_aspm=` cmdline: BIOS _OSC already
  grants OS control. TLP is the single owner of the policy file (it runs once at boot and exits —
  see `## daemons`).
**Evidence.** `state/owned/etc/tlp.d/01-eco.conf` (ASPM powersave + PM auto). Check:
  `cat /sys/module/pcie_aspm/parameters/policy`, `lspci -vv` (`LnkSta` per link),
  `grep . /sys/bus/pci/devices/*/power/control`, and the `./eco report` TLP row.
**Rejected here.** ASPM `powersupersave` / L1.2 forcing (instability-proven here; no per-device
  lever exists).
**Reopen.** a kernel with a per-device ASPM lever (none exists today).

## sched

**Verdict.** scx_lavd 1.1.3 with `--powersave --per-cpu-dsq --enable-cpu-bw` (core compaction) —
  applied (check SCHED) · **Class:** tunable
**Why.** Compaction keeps the fewest cores awake — the race-to-sleep pairing. All `sched_*` sysctls,
  uclamp, prefcore (hardware-disabled) and core parking: touch nothing — teo + C3 already park cores
  in microseconds and hotplug churns sched_ext domains for no gain; measured C3 residency 69% (Zen
  5) / 90% (Zen 5c) shows nothing blocks deep idle. The loader value
  `powersave_mode=["--efficiency"]` referenced a nonexistent flag and was changed to `--powersave`.
  Superseded with scope: study 01 adopted scx_pandemonium (Pareto versus BORE: −11% idle / −35%
  I/O-burst / −30% reclaim power, throughput tie) — applied state is resolved (scx_lavd live, newer
  kernel + owner-settled); the comparative claim is not (see Open).
**Evidence.** `state/managed/scx.toml` (`powersave_mode = ["--powersave"]` under
  `[scheds.scx_lavd]`). Check: `grep -A2 scx_lavd /etc/scx_loader.toml`, the `./eco report` SCHED
  row; C3 residency via turbostat windows per `benchmarks/METHODOLOGY.md`.
**Rejected here.** scx_pandemonium for power (its own README: +23.9% J/op versus EEVDF on its
  workload); scx_rusty (spreads load across domains — structurally anti-compaction); core parking /
  hotplug (teo + C3 already park; hotplug churns sched_ext).
**Reopen.** a fresh scheduler A/B on the current kernel.
**Open.** pandemonium versus scx_lavd was never A/B'd on the current kernel; the two verdicts use
  different baselines (BORE vs EEVDF) and different workloads, so both claims stand recorded.

## asusd

**Verdict.** asusd `platform_profile_on_battery: Balanced` (was Quiet) — applied (check PROFILE) ·
  **Class:** settled
**Why.** Q10: this firmware exposes only `balanced` and `performance`, so the Quiet write failed
  EOPNOTSUPP on every battery event; mapping to Balanced restores the designed behavior. Superseded
  with scope: the TEST-BED/study-02 era "battery → Quiet" — Quiet no longer exists on this firmware.
  Mechanism to know: writing `platform_profile` resets the SMU limits and EPP through the EC even
  when writing the same value, and asusd writes it on every AC/battery event — this is why
  `## timer`'s event set and the eco converger re-assert after power events.
**Evidence.** `state/managed/asusd.toml` (anchored line `platform_profile_on_battery: Balanced,`).
  Check: `grep platform_profile_on_battery /etc/asusd/asusd.ron` and
  `cat /sys/firmware/acpi/platform_profile` — compare by value (see Machine lies).
**Rejected here.** mapping the battery profile to Quiet (EOPNOTSUPP on every battery event).
**Reopen.** if firmware re-exposes quiet.
**Machine lies.** asusd rewrites its own `asusd.ron` on restart (map keys reordered, values
  preserved) — compare by value, never by whole-file hash; startup noise "AC profile Balanced",
  "FanCurves: Not supported", "Backlight: No backlights found" is benign on this model.

## writeback

**Verdict.** `vm.dirty_writeback_centisecs=6000`, `vm.dirty_expire_centisecs=6000` (60 s / 60 s) —
  applied (check IO observes this + journald) · **Class:** tunable
**Why.** Longer writeback intervals are a wakeup reduction, not a cap (fsync and journal are
  unaffected). Root cause (found 2026-09-25): TLP's `set_dirty_parms()` rewrote `vm.dirty_*` and the
  XFS age knobs from `MAX_LOST_WORK_SECS * 100` on every power-source event and at startup — with
  `MAX_LOST_WORK_SECS` unset in our TLP policy the shipped defaults won (15 s AC / 60 s BAT) and the
  runtime values drifted to 1500/1500 despite the owned sysctl file. Fix:
  `MAX_LOST_WORK_SECS_ON_AC=0` and `MAX_LOST_WORK_SECS_ON_BAT=0` (TLP convention 0 = do not manage;
  `set_dirty_parms` returns early before any sysctl write), so `99-eco-writeback.conf` is the single
  writer of 6000/6000 and the XFS sync interval is unblocked. Belt: `eco-power.sh` re-asserts
  6000/6000 on every trigger (boot, resume, AC event, 600s timer). Before persistence (Q2/Q3/Q11)
  the values were lost at every sysctl load. Superseded with scope: the 1500/1500 drift state and
  the 30-second-class default (the TLP-clobbered class) are gone; `fs.xfs.xfssyncd_centisecs=10000`
  stays live from the same single-writer fix (lowering it to 10 s is measured-worse: 8.35 s vs 8.16
  s, log forces 135 vs 191, more wakeups).
**Evidence.** `state/owned/etc/sysctl.d/99-eco-writeback.conf`; `state/owned/etc/tlp.d/01-eco.conf`
  (`MAX_LOST_WORK_SECS_ON_AC/BAT=0`); `state/owned/etc/sysctl.d/20-xfs-sync-interval.conf`;
  `state/owned/usr/local/sbin/eco-power.sh` (re-assert belt). The resetter's source:
  `/usr/share/tlp/func.d/15-tlp-func-disk` (`set_dirty_parms()`) with the shipped defaults in
  `/usr/share/tlp/defaults.conf` (15 s AC / 60 s BAT). Check:
  `sysctl vm.dirty_writeback_centisecs vm.dirty_expire_centisecs` — read the runtime values, never
  the files alone (TLP was the resetter).
**Rejected here.** lowering `xfssyncd_centisecs` (measured-worse, more wakeups).
**Open.** no measured J/min confirmation for the whole writeback/wakeup family (6000/6000, xfssyncd,
  `speculative_prealloc_lifetime`): the timer-policy pair (xfssyncd 10000 → 30000, prelife 300 →
  1800) was INCONCLUSIVE at n=2/arm usable (MW-U minimum p = 0.333; one window
  owner-session-contaminated; the campaign was cut short when the host battery died — recorded
  INCONCLUSIVE-lean) and neither mechanism appeared (0 trim events in every window — the
  `wbig` workload never creates post-EOF speculative prealloc; idle log FORCE ≈ 8/min in both arms).
  Needs a quiet-machine idle-drain/wake-count campaign (powertop/turbostat windows ≥ 15 min/arm,
  deliberate panel blanking).

## journald

**Verdict.** journald `SystemMaxUse=32M` — applied (check IO observes writeback + this) · **Class:**
  tunable
**Why.** The journal sat near its 50M cap with a self-restart on cap hit; the cap was lowered to 32M
  (Q2/Q3/Q11). Dated baseline readback (2026-09-26): `journalctl --disk-usage` 47.9M against the 32M
  cap — healthy.
**Evidence.** `state/managed/journald.toml` (anchored line `SystemMaxUse=32M`). Check:
  `journalctl --disk-usage`, `grep SystemMaxUse /etc/systemd/journald.conf`.

## io-stack

**Verdict.** NVMe scheduler `none`, `nr_requests=1023`, `read_ahead_kb=256`, `wbt_lat_usec=2000`
  kept; `vm.swappiness=150` (udev-enforced) — applied · **Class:** tunable
**Why.** `none` is race-to-idle: bursts drain immediately so the APST timer can start.
  `max_sectors_kb=128` is the drive's MDTS limit — I/Os split at 128 KiB, so `read_ahead_kb=256` is
  not a request size and prealloc sizes are about extents, not I/O size. WBT is load-bearing. Swap
  is zram lz4: pageouts never touch the SSD.
**Evidence.** `benchmarks/studies/03-filesystem-latency/README.md` (read-ahead, nr_requests
  refusals); `benchmarks/studies/02-boot-and-power/README.md` (WBT 0 refusal + warning, swappiness
  200, MDTS 128 KB); `docs/XFS-TUNING.md` (stack baseline). Persistence: scheduler `none` is
  udev-persisted (`/etc/udev/rules.d/60-ioschedulers.rules`, foreign file — not repo-managed);
  `vm.swappiness=150` is udev-enforced (`/usr/lib/udev/rules.d/30-zram.rules`, zram0-ready hook).
  Check:
  `cat /sys/block/nvme0n1/queue/{scheduler,nr_requests,read_ahead_kb,max_sectors_kb,wbt_lat_usec}`,
  `sysctl vm.swappiness`, `swapon --show` (zram).
**Rejected here.** raising read-ahead 256 → 2048 (identical on a 1M-file cold metadata walk — XFS
  metadata reads use fixed buffers); lowering `nr_requests` 1023 → 256 (3.90 s vs 3.75 s, queue
  latency 2404 µs vs 1978 µs — worse); disabling WBT (`wbt_lat_usec=0`: browser launch under write
  load 30% slower, p = 0.009, queue latency 12–24× worse; 1000/10000 indistinguishable from 2000);
  swappiness ≥ 200 (hard anti-goal: 150 → 200 reproduced catastrophic — wall 11.25 → 13.55 s, mean
  power 10.07 → 12.07 W, p = 0.004).

## nvme

**Verdict.** Two-stage APST armed (PS3 after 100 ms, PS4 after 2 s); PS5 gated out by
  `nvme_core.default_ps_max_latency_us=100000`; Gen3 x4 link kept — applied/settled;
  `nvme set-feature -f 0x0c` is a standing hazard (never use) · **Class:** settled
**Why.** PS5 unlock is rejected: root-disk exit-latency stall risk, exit latency unmeasured. The
  link runs Gen3 x4 downgraded from the Gen4 cap and stays there — forcing Gen4 costs watts. The
  0x0c hazard: `nvme-cli` writes a zeroed 256-byte buffer and wipes the entire APST table; `-v 1`
  cannot restore it (recovery = controller reset `echo 1 > /sys/class/nvme/nvme0/reset_controller`,
  then read the table back). The drive carries the `simple_suspend` platform quirk — it affects the
  system-sleep path only, not APST. Single WD SN560 (no SATA, no MMC card). Dated device baseline
  (2026-09-26): `percentage_used` 2%, `available_spare` 100%, `media_errors` 0, 1371 power-on hours,
  41 C — the baseline to compare future readings against.
**Evidence.** `benchmarks/studies/02-boot-and-power/README.md` (PS3 = 0.015 W / 2.5 ms exit, PS4 =
  0.005 W / 6 ms exit vs 0.3 W in PS0–2; +26 µs/request transition, ~285 mW idle power bought; its
  §8 is the 0x0c hazard write-up); `docs/rollback.md` (`## Storage ops — re-check commands`).
  Check: `cat /sys/module/nvme_core/parameters/default_ps_max_latency_us` (stays 100000),
  `lspci -vv` (`LnkSta`: Gen3 x4),
  `nvme smart-log /dev/nvme0 | grep -iE 'percentage_used|available_spare|media_errors|temperature'`,
  `smartctl -H /dev/nvme0`.
**Rejected here.** PS5 unlock (root-disk exit-latency stall risk, exit latency unmeasured); APST-gap
  tuning; forcing Gen4 (costs watts); `set-feature 0x0c` (wipes the APST table).
**Reopen.** PS5 unlock only if exit latency is ever measured.
**Machine lies.** the NVMe PCI function shows 0 ms runtime-suspended despite `power/control=auto` —
  root-disk reality, not a config failure; link L1 still applies.

## fstrim

**Verdict.** Weekly `fstrim.timer` (systemd stock) is the design; the `discard` mount option is
  rejected; free-space accounting under dedupe is measured by physical offsets, never by self-report
  — applied · **Class:** settled
**Why.** Periodic batch TRIM beats per-operation discard latency on NVMe (kernel docs rate the
  discard performance impact as "quite severe"); continuous `discard=async` would keep the device
  busy and fight APST. A one-off `sudo fstrim -av` after very large deletions is acceptable;
  post-dedupe fstrim is not automated (the weekly timer suffices). Reflink sharing is load-bearing:
  the 2026-09-26 full-filesystem dedupe sweep recovered ~65 GiB, verified by physical-offset
  (`poff`) measurement, not by duperemove's self-report — `xfs_fsr`/defrag is therefore never
  automated (it rewrites extents and un-does dedupe; a deliberately defragged file re-materializes
  private blocks, and duperemove must be re-run if the space matters). duperemove findings the
  accounting must know: identical-file groups are quadratic-ish (an 87k-member group pegged a core
  >55 min — such trees are excluded); `dedupe_seq` resume semantics skip files below the config
  marker permanently, `seq == max` are never processed, and setting all seq=0 hides files *below*
  the marker.
**Evidence.** `docs/rollback.md` (`## Storage ops` — duperemove/fstrim operations, automation,
  re-check commands); `docs/XFS-TUNING.md` (reflink / `xfs_fsr` rules);
  `~/docs/NOTE.md:3762-3855` (session chronology behind the 2026-09-26..28 FS/XFS work: dedupe
  semantics, pitfalls, overrides). Dated FS baseline (2026-09-26): `/dev/nvme0n1p2` XFS
  `reflink=1`, 950G total, ~39% used, inodes 2%, pacman pkg cache 0 bytes. Check:
  `systemctl list-timers fstrim.timer duperemove.timer`, `findmnt -no OPTIONS /` (no `discard`),
  `df -h /`; duplicates directly via `COUNT(DISTINCT poff)` per digest in
  `/var/lib/duperemove/root.hash`.
**Rejected here.** mount `discard` (root-unsafe/forbidden; fights APST); post-dedupe fstrim
  automation (the weekly timer suffices).
**Machine lies.** duperemove silently scans 0 files as non-root (libblkid UUID lookup) and exits 0;
  `--read-hashes` is a different, non-SQLite hash format and does nothing on a `--hashfile`
  database; free space keeps drifting down *after* a dedupe sweep (delayed block freeing) — never
  attribute freed space to dedupe without direct duplicate measurement.

## xfs-logbsize

**Verdict.** `logbsize=256k` (with `logbufs=8`) live via `rootflags=logbsize=256k` — applied;
  end-to-end benefit unproven (mechanism only) · **Class:** tunable
**Why.** XFS log geometry is chosen at first mount: a remount "succeeds" and changes nothing (proved
  on a loopback image — forced log commits 19034 → ~1561 for the same 15× metadata storm at 256k:
  mechanism confirmed, speed benefit still unproven). **fstab XFS options are dead** — root mounts
  in the initramfs before fstab is consulted; the effective `logbsize` comes from `rootflags=` on
  the kernel command line. Superseded with scope: (a) the fstab option list is the
  intended/effective option set, not the mechanism (the 32k-vs-256k tunable snapshot proved the
  fstab entry had never been applied); (b) `mount -o remount,<xfs-opt>` as an application path is
  silently inert on kernel 7.3-rc4 (rc=0, nothing in `/proc/mounts`) — boot-time `rootflags=` or
  loopback mount-time arms are the only valid paths. Also settled in the live mount line
  `rw,relatime,lazytime,inode64,logbufs=8,logbsize=256k,noquota`: `lazytime` stands (zero atime
  wakeups; `noatime` rejected as redundant), `inode64` is default since v3.7 (its fstab entry is a
  restatement). Mount-option hygiene: `ikeep`/`attr2`/`noikeep`/`noattr2` are deprecated no-ops on
  this kernel (the admin-guide calls them "removed" — either way, never use);
  `ikeepnoquota`/`sendbuf` do not exist in Linux XFS and fail the mount. Superseded with scope: the
  "ikeep/attr2 removed in v6.18" reading loses to observed parser behaviour (still accepted with a
  warning, deprecation postponed to 2030) — the practical answer is identical (root is XFS V5 with
  `reflink=1`; `attr2` is immutable on V5 anyway).
**Evidence.** `docs/XFS-TUNING.md` (baseline, skip/avoid list, campaign results);
  `benchmarks/studies/03-filesystem-latency/README.md` (first-mount-only log geometry; the 19034 →
  ~1561 mechanism; benefit NOT established); `benchmarks/tools/fslat.py` (per-row tunable snapshot —
  the 32k-vs-256k proof) and `benchmarks/tools/verify-adopted-settings.sh` (adoption readback).
  Check: `grep -o 'rootflags=[^ ]*' /proc/cmdline`, `findmnt -no OPTIONS /`, `xfs_info /`.
**Reopen.** only with a completed end-to-end A/B on the current kernel.
**Open.** `logbsize=256k` end-to-end benefit is mechanism-only; the on-metal 32k A/B is half
  complete (the 32k comparison row was cache-mixed and rejected as evidence). The xfssyncd 10000 →
  30000 half of the timer-policy pair is unmeasured (same idle-drain campaign as `## writeback`'s
  Open).

## xfs-allocsize

**Verdict.** `allocsize=1m` falsified for the big-sequential workload class — refuted and rolled
  back (both limine backups restored; rollback effective next boot) · **Class:** settled
**Why.** AB3: root cross-pass n=5/arm wall −1.4% (inside the 8.1% control spread), pkg J −6.8% (p =
  0.117, n.s., cross-pass confounded); loopback within-pass A/B (mount-time arms, readback-proven,
  n=4/arm) exactly zero (wall 0.83 s vs 0.83 s, 4.43 J vs 4.43 J, 3 extents both arms). The
  mechanism is contradicted: sync transactions +189% and log writes +76% with the setting, identical
  write ios (32,819 vs 32,861) and identical request sizes. Arm identity: AB3 read `allocsize=1024k`
  back in 6/6 rows from the boot cmdline (a remount would have been silently inert — see
  `## xfs-logbsize`); the AB3-era limine backups stay on disk for rollback/re-apply.
**Evidence.** `docs/XFS-TUNING.md` (AB2 → nothing adopted; AB3 verdict → rolled back);
  `benchmarks/studies/04-xfs-tuning/` (AB3 root/loopback rows); `benchmarks/tools/fslat.py` and
  `benchmarks/tools/verify-adopted-settings.sh` (arm identity / adoption readback). Check:
  `grep -o 'rootflags=[^ ]*' /proc/cmdline` (no `allocsize` after rollback),
  `findmnt -no OPTIONS /`.
**Rejected here.** `allocsize=1m` for big-sequential writes (refuted above); remount-based XFS
  option application (silently inert on this kernel).
**Reopen.** new evidence from an untested workload class.
**Open.** random/mixed/small-file write classes are untested; the known over-reservation cost for
  early-terminating files stands.

## xfs-filestreams

**Verdict.** Mount option `filestreams` is inert on kernel 7.3-rc4 (it never applies — not a knob
  this way); the per-directory inode flag `+S` measured a Pareto trade, not a win — rejected as a
  win, but the owner override deliberately applied `chattr -D +S` to `~/Projects` + `~/Workspace`
  (verified `[S]`, new dirs inherit) · **Class:** mixed
**Why.** `mount -o remount,filestreams /` returns rc=0, never appears in `/proc/mounts`, and fires
  zero `xfs_filestream_*` tracepoints for unflagged dirs; `nofilestreams` is an unknown parameter.
  The measurable unit is the per-directory inode flag `xfs_io chattr +S` — `+f` is **no-defrag**.
  Superseded with scope: docs originally said `+f`, resolved to `+S` (verified from
  `xfs_io help chattr`, not from memory or blogs). The A/B (mkstorm 15 × 5/arm) was a Pareto trade,
  not a win: wall −8.9% (p = 0.009), NVMe read ios −71.7%, write ios −47.3%, device busy −28.5%, log
  FORCE −23.6%, log no-space −41.4%, pkg J −2.1% (p = 0.347, n.s.) — but PSI io-some +112.9%,
  io-full +114.3%, cpu-some +91.1%, mean queue latency +86.9% (all p = 0.009, beyond control
  spread). It fails the "nothing significantly worse" rule; the owner override nonetheless accepted
  the ~2× stall trade deliberately, where wall time dominates and stall is invisible.
**Evidence.** `docs/XFS-TUNING.md` (filestreams REJECT with numbers + ftrace proof 118800 lookups /
  1200 picks vs 0/0; owner override; arm-identity lesson); `benchmarks/studies/04-xfs-tuning/`
  (mkstorm rows); `benchmarks/tools/fslat.py` and `benchmarks/tools/verify-adopted-settings.sh` (arm
  identity). Check: `xfs_io help chattr` (flag letters), `xfs_io -c 'lsattr' -d ~/Projects` (repeat
  for `~/Workspace`: `[S]`), `grep / /proc/mounts` (no `filestreams` — and never trust a remount's
  exit code).
**Rejected here.** mount-wide `filestreams` (inert on 7.3-rc4); `+f` (no-defrag, not filestreams);
  filestreams as a Pareto win (fails "nothing significantly worse").
**Open.** filestreams for batch workloads — the measured stall trade may be acceptable where wall
  time dominates (fresh n ≥ 5 A/B required).

## sd

**Verdict.** SD reader (GL9755, sdhci-pci) unbound at runtime (card absent) — applied, runtime-only;
  a reboot re-binds it and the report shows WARN, not DRIFT (check SD) · **Class:** recovery-only
**Why.** Q8 "investigate-unbind": the facts were confirmed safe — standard surprise-removal
  teardown, no card registered. The reader never runtime-suspends on its own. Boot persistence was
  explicitly left undecided. Undo commands stay in `docs/rollback.md` (`rollback#sd`); this entry
  exists to undo and observe, not to tune.
**Evidence.** `docs/rollback.md` (`## sd` — undo commands). Check: `lspci -k` (no "Kernel driver in
  use" for the SD controller while unbound), `./eco report` SD row (WARN after a reboot is
  expected).
**Reopen.** owner decides persistence.
**Machine lies.** after a reboot the reader is bound again — expected transient, not drift.

## misc

**Verdict.** `acp_power_gating=1` persisted; localsearch-3 masked (owner-approved GNOME app-search
  degradation); niri autostart spawns `hw-tune.fish` — applied/habit (check MISC) · **Class:** mixed
**Why.** `acp_power_gating=0` was suspected non-default; the module is inert (device held by
  snd_acp_pci), so it was set to 1 and persisted. localsearch-3 was an indexer running for nothing;
  the owner accepted degraded app search (Q2/Q3/Q11). The niri autostart record keeps the single SMU
  writer invoked at session start. Undo commands stay in `docs/rollback.md` (`rollback#misc`).
**Evidence.** `state/owned/etc/modprobe.d/99-acp-power-gating.conf`;
  `state/managed/niri-autostart.toml`; `docs/rollback.md` (`## misc` — undo commands). Check:
  `./eco report` MISC row; `pgrep -a localsearch` (nothing running).

## autosuspend

**Verdict.** Noctalia idle auto-suspend stays **disabled** (timeout 900 s exists but
  `enabled=false`) — applied, owner-ruled · **Class:** settled
**Why.** Q7: owner — "my current idle behaviour is good". The 70 s screen-off chain remains the
  deepest-sleep trigger.
**Evidence.** the Noctalia idle config (900 s timeout present, `enabled=false`) — no `state/` mirror
  exists (the knob is not repo-managed). Check: Noctalia's own idle settings read back
  `enabled=false`.
**Reopen.** only owner initiative.

## recovery

**Verdict.** Recovery-safety rules standing/applied · **Class:** settled
**Why.** (1) **Bootloader dual-file cmdline rule.** `/boot/limine.conf` is machine-generated by
  limine-entry-tool from `/etc/default/limine`; editing only limine.conf is silently reverted at the
  next kernel install. A cmdline change must edit BOTH with a pre-image taken first (backup
  mechanism: `docs/rollback.md` `## Undo: universal mechanism`); `rootflags=` appears 3× in
  limine.conf (one per kernel entry) and 1× in `/etc/default/limine`; `/rewind` cannot stage /boot. (2) **`sudo` + glob pitfall.**
  `sudo ls /boot/limine.conf*` fails: the glob expands as the unprivileged user before sudo runs
  (root-owned /boot) — use `sudo bash -c 'ls /boot/limine.conf*'` or explicit paths. (3)
  **Repo-first / two-writer rule.** Live is never the place to make a change: the eco converger and
  TLP co-write runtime knobs and hand edits are reverted by design. Change flow:
  `docs/rollback.md` `## Converge a change`; capture deliberate live experiments with
  `./eco harvest` before the converger eats them. One place per knob
  (`grep -rn <value> state/` returning two hits means the repo is wrong). Two daemons writing one
  sysfs attribute is a silent race (the asusd/PPD precedent). (4) **Backups before every write** —
  pre-image per write, mechanism `docs/rollback.md` `## Undo: universal mechanism`; foreign files
  edited by exactly one anchored line. **TTY login is the recovery domain** — nothing may touch the
  bootloader, initramfs, or
  anything tty login depends on from inside the eco stack; a broken stack must still boot to a tty.
  (5) **Filesystem recovery domain.** `xfs_repair` is offline/rescue-media only — never on the
  mounted root (it can destroy data); `xfs_scrub` is the scheduled online check (monthly
  `xfs-scrub.timer`, see `docs/rollback.md` `## Storage ops`). Owner process ruling Q12: changes
  land in waves
  with dated `cp -p` backups before every write, verified after each wave — no blind parallel bursts
  onto a live system.
**Evidence.** `docs/rollback.md` (`## Undo: universal mechanism` — the backup mechanism home);
  `docs/XFS-TUNING.md` (persistence pitfall + dual-file rule); `docs/eco-power-README.md`
  (repo-first flow, exit-code contract); `benchmarks/README.md` (two-writer race lesson). Check:
  `sudo bash -c 'ls /boot/limine.conf*'`; `grep -c rootflags /boot/limine.conf /etc/default/limine`;
  `grep -rn <value> state/` (exactly one hit).
**Open.** backup gap: no borg/restic/snapper/partclone installed and XFS has no snapshots — dedupe,
  TRIM and scrub protect against none of the failure modes backups protect against; the
  recommendation (borg or restic to off-host or external storage) stands for the next maintenance
  window.

## cpu

**Verdict.** CPU/power stack verified optimal as configured: amd-pstate-epp active mode
  (firmware-autonomous V/f within our bounds), `scaling_governor=powersave` on every policy, min
  freq 605264 = `lowest_nonlinear` (the V/f knee), boost ON but clipped by the ceilings (see
  `## ceil`), EPP per `## epp`; no `amd_pstate` module params exist · **Class:** settled
**Why.** Firmware-autonomous V/f inside the owner-set bounds; the min floor sits exactly on the V/f
  knee. `zswap` is not compiled and pointless here (swap is already compressed zram). Kernel-side
  idle facts live in `## kernel`.
**Evidence.** `state/owned/etc/tlp.d/01-eco.conf`; `benchmarks/TEST-BED.md` (fuller machine
  picture). Check: `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq` (605264),
  `ls /sys/module/amd_pstate` (does not exist).

## kernel

**Verdict.** No cmdline additions recommended; deep C-states POLL/C1/C2/C3 (firmware-defined) all
  enabled, zero blocked; NO_HZ_IDLE (`NO_HZ_FULL` not compiled), PREEMPT_LAZY stock CachyOS, HZ=600
  irrelevant to idle because ticks stop · **Class:** settled
**Why.** The rejections below are compiled-in or measured-neutral. Superseded with scope:
  benchmark-era claims are stamped to the campaign kernel (see preamble) — historical scoping, never
  edited to match; any re-run is a new baseline, and XFS behaviours (the remount-inert options) are
  kernel-version-specific.
**Evidence.** Check: `uname -r`, `cat /proc/cmdline`,
  `cat /sys/devices/system/cpu/cpu0/cpuidle/state*/{name,disable}` (all enabled).
**Rejected here.** `zswap.enabled=0` (inert — zswap is not compiled); `nohz_full` (not compiled;
  NO_HZ_IDLE already stops ticks); `pcie_aspm=force` (unneeded — BIOS grants control); THP on
  madvise (power-neutral); chasing idle interrupt noise (I2C-C touchpad, amdgpu, and WiFi beacon
  interrupts at idle are expected and activity-driven — not tunable noise).
**Reopen.** a kernel change re-scopes every kernel-stamped claim (preamble).

## smu

**Verdict.** ryzenadj tunable survey on Strix Point (SMU IF 21) — settled map: used = CO (`## co`),
  envelope (`## ppt`), `--power-saving` (`## eco`); family-gated in ryzenadj source (message never
  sent) = all min/max clock-domain tunables (socclk/fclk/vcn/lclk/gfxclk), `oc-clk`/`oc-volt`,
  `enable-oc`, `apu-skin-temp`; SMU-rejected (tool accepts, firmware refuses) = `--set-cogfx`, all
  PSI setters, `--prochot-deassertion-ramp` · **Class:** settled
**Why.** The family gates sit in the ryzenadj source — the message never reaches the SMU. The
  rejected setters print success and are ignored. Doctrine rejections: TDC/EDC changes, thermal
  limits, `skin-temp-limit` (it is a power cap), `gfx-clk` (forced clock), `max-performance`.
**Evidence.** `state/owned/home/zhangdm/.reserve/hw-tune.fish` (single SMU writer). Check:
  `sudo ryzenadj --info`; `sudo ryzenadj --dump-table` returns undecoded offsets only; never the
  journal log (see `## ppt`).
**Rejected here.** min/max clock-domain tunables, OC setters, `apu-skin-temp` (family-gated);
  TDC/EDC and thermal-limit changes (caps or safety-margin erosion, zero joule gain).
**Machine lies.** silently rejected setters report success: `--set-cogfx`, all PSI current setters,
  `--prochot-deassertion-ramp`.

## gpu-display

**Verdict.** The amdgpu device is **card1** (`/sys/class/drm/card1`), not card0;
  `power_dpm_force_performance_level=auto` is the working lever (applied by TLP); `power_dpm_state`
  is cosmetic and root-only on this SMU APU and `pp_power_profile_mode` does not exist —
  applied/accepted · **Class:** settled
**Why.** Screen-on idle sits at mid DPM levels (sclk ~631–752 MHz, mclk never 400 MHz, ~15 W at 2–3%
  busy) because the 2880×1800@120 VRR panel is lit — no safe write lever exists, and the screen-off
  chain (see `## autosuspend`) is the correct remedy. ABM `panel_power_savings=1` is active; VRR
  always-on lets idle refresh drop (keep); backlight via `amdgpu_bl1`, no cap. Adjacent device
  truth: audio `power_save=1s` + controller power gating on (the "10" baseline was stale); HDMI HDA
  suspends for hours when unused; the camera USB device suspends; 7 of 8 xHCI hubs suspend; no
  `control=on` offenders exist.
**Evidence.** `state/owned/etc/tlp.d/01-eco.conf` (DPM perf level). Check:
  `cat /sys/class/drm/card1/device/power_dpm_force_performance_level` (=auto),
  `cat /sys/class/drm/card1/device/pp_dpm_sclk` (mid levels while the panel is lit),
  `ls /sys/class/drm/`.
**Rejected here.** the "iGPU L1.2 win" (the iGPU 1002:150e has no L1 PM Substates capability at
  all); GPU DPM manual pinning (stalls bursts; the screen-off chain already handles idle).
**Machine lies.** writes to card0 fail with ENOENT and look "silently ignored" (the device is
  card1); the `amdgpu_dm_freesync` WARNING at boot/resume is cosmetic and fires on every resume, not
  just boot.

## input-i2c

**Verdict.** The I2C-C top-IRQ identity is the touchpad `i2c-ASUP1207:00` (PixArt 093A:3012) via
  i2c_hid_acpi + hid-multitouch — interrupt-driven, idles at 0/s; the paired GPIO IRQ (pinctrl_amd /
  ASUP1207) is the same physical source; no fingerprint reader exists on this unit; the AT keyboard
  is i8042 (PS/2, not USB) · **Class:** settled
**Why.** The bus (`AMDI0010:02`, i2c-2) was the top IRQ source with 5k/s bursts and looked like a
  rogue poller; it is touch activity, and the bus idles at 0/s. The i8042 identity is why all XHC
  wake sources can stay disarmed (the keyboard is not USB).
**Evidence.** Check: `grep -iE 'ASUP1207|AMDI0010' /proc/interrupts`, then watch an idle window
  (counts stay 0/s without touch).
**Machine lies.** hundreds-per-second IRQ counts read like a rogue poller but are touch activity,
  not polling.

## capacity

**Verdict.** `cpu_capacity` values lie on this hybrid (use `acpi_cppc/highest_perf` for core
  ranking); battery charge cap is 80% (`charge_control_end_threshold`) and "Not charging" at 80% is
  normal; dated power anchors (2026-09-23): ~3.7 W RAPL idle floor (screen-on, converged stack),
  ~12.1 W light load · **Class:** settled
**Why.** The dated anchors live here (machine truth about this host, not the CPU configuration
  module `## cpu`): they are regression anchors for the whole converged stack, never targets — never
  "optimize" toward a watt number. The hybrid's capacity ranking must come from CPPC, not the
  `cpu_capacity` readback.
**Evidence.** `docs/judgment.md` (harness interface + rules); `benchmarks/TEST-BED.md` (fuller
  machine picture). Check: `cat /sys/devices/system/cpu/cpu*/cpu_capacity` (lies),
  `cat /sys/devices/system/cpu/cpu*/acpi_cppc/highest_perf` (ranking truth),
  `cat /sys/class/power_supply/BAT0/charge_control_end_threshold` (=80); the power anchors via the
  rapl-watts/measure-power harness whose interface `docs/judgment.md` records (battery state,
  screen state and AC state are recorded with every number).
**Reopen.** any kernel change ⇒ re-baseline the dated anchors (preamble).
**Machine lies.** `cpu_capacity` reads misleading values on this hybrid; "Not charging" at 80% reads
  like a fault but is the cap working; battery `power_now` reads 0 on AC with the cap — RAPL package
  `energy_uj` is the energy oracle; sysfs `AC0/online` has misread AC state before (an AC-off window
  presented as AC-on; fixed by one plug cycle after resume) — treat it as advisory during weirdness
  and re-plug before diagnosing anything power-source-dependent; firmware derates can latch across a
  replug and clear only at some charge threshold or a full power-off (EC discharge).

## daemons

**Verdict.** No timer storm — 9 system + 1 user timer, all daily/weekly/night-clustered (the
  eco-power backstop was the only sub-minute timer, now 600s); PPD masked; TLP single owner (runs
  once at boot, exits); asusd is epoll/uevent-driven (1.27 s CPU over 13 h) with no EC polling
  interval to tune; 0 armed ACPI wake sources, RTC wakealarm empty, no cron/anacron, no monitoring
  agents, fprintd absent; all inhibitors are delay-mode (swayidle/noctalia lock chain) — nobody
  blocks suspend indefinitely · **Class:** settled
**Why.** Nothing in the daemon set competes for wakeups or writes (TLP exits after boot; the
  asusd/PPD two-writer precedent is closed by masking PPD). The scheduled set is maintenance: daily
  duperemove, weekly fstrim, monthly xfs-scrub + smartd self-test (detail in
  `docs/rollback.md` `## Storage ops — what runs automatically`).
**Evidence.** `state/owned/etc/systemd/system/*.timer`; `docs/rollback.md`
  (`## Storage ops — what runs automatically`).
  Check: `systemctl list-timers --all`, `cat /sys/class/rtc/rtc0/wakealarm` (empty),
  `grep . /proc/acpi/wakeup` (nothing armed), `systemd-inhibit --list` (all delay-mode).

## suspend-resume

**Verdict.** RESOLVED-IN-PRACTICE, causal chain uncertain — owner reports fixed (2026-09-29 23:05)
  after the stale `.bak` resume hook was removed; `hw-tune.fish` restored to the resume path
  (single-pass) by owner directive — which also serves as the A/B "on" arm. Capture stays armed
  (SysRq=1, hung_task_panic=1, efi_pstore, 256M journals). If a freeze recurs, the first
  mitigation to re-apply is keeping hw-tune out of the resume window (the 21:14 `amdgpu SMU:
  No response` evidence); quiet asusd / TB-USB4 neutralize are the contingency ladder ·
  **Class:** tunable
**Why.** Evidence, not hypothesis: (1) every wake stalled 5.1 s because
  `eco-power.sh` ran `hw-tune.fish` twice with `sleep 5` in the systemd-sleep post hook and
  systemd thaws `user.slice` only after the hook exits (fixed: `eco-power.sh resume` = single
  pass, `state/owned/usr/lib/systemd/system-sleep/eco-power` now owned); (2) freeze vector A —
  journal boot -2 (2026-09-29 15:28): resume → asusd AC-state flap → platform_profile write →
  30 s AML interpreter give-up (`AE_AML_LOOP_TIMEOUT` on `\_SB.A018/A032/ALIB/EC0._QDA`) →
  `thunderbolt c6:00.5/6: Refused D0→D3hot` → hard cut; boot -1 (18:13) cut mid suspend-entry;
  (3) freeze vector B — pstore `crash-20260920-panic1.txt` (7.3.0-rc3): `hung_task: blocked
  tasks`, the blocked task sat 122 s in `snd_pcm_ioctl → playback_pcm_prepare → cs35l56_hda_play
  → azx_get_response` right after a cs35l56 DSP firmware reload; boot -5's freeze cut mid
  cs35l56 reload too. `docs/findings.md` `## asusd` (EC resets SMU/EPP on every platform_profile
  write) and `## capacity` (AC state misread at resume) make the asusd/EC overlap at resume real.
  (4) The 21:14 recurrence (richest capture) decayed over 48 s from resume T0 in the same
  template as 15:28: our hw-tune SMU writes at T0+18 ms, asusd profile write at +34 ms,
  `ucsi_acpi GET_CURRENT_CAM failed` +8.6 s, **`amdgpu SMU: No response` → power-gate failures
  VPE/JPEG/VCN (`DPM disable … ret = -62`) at +10/+26/+41 s**, `AE_AML_LOOP_TIMEOUT` EC storm
  +30.6 s, journal cut +48 s while the kernel still serviced SysRq. New markers: thunderbolt
  ring-interrupt WARN + PCI config-space timeouts (mid-`pci_pm_suspend`). Progressive, fully
  observable — a wedge race, not an instant crash.
**Evidence.** `state/owned/usr/local/sbin/eco-power.sh` (resume single-pass guard + hw-tune
  skip); `state/owned/usr/lib/systemd/system-sleep/eco-power`; `state/owned/etc/sysctl.d/97-sysrq.conf`
  + `98-hung-task-panic.conf` (capture armed); raw journals + decoded pstore in
  `~/Workspace/suspend-forensics/` incl. `recurrence-2115/SIGNATURE.md` (21:14 timeline + 15:28
  signature diff). Check: `journalctl -b 1 -o short-precise | tail`, `sudo ls /sys/fs/pstore`, and
  on each resume `journalctl -b 0 | grep -E 'System returned from sleep|Successfully thawed|SMU'`
  (thaw delta must stay < 1 s; `SMU: No response` must be absent).
**Suspects not yet A/B'd.** `SOUND_POWER_SAVE_ON_AC/BAT=1` (`state/owned/etc/tlp.d/01-eco.conf`)
  vs the cs35l56 re-init hang; sched_ext BPF scheduler (`enabled+all`; out-of-tree "pandemonium"
  was live during the 09-20 hung_task) vs whole-system freeze. Owner defers all experiments until
  a freeze recurs; runbook then is one variable at a time, ≥5 resume cycles on AC and 5 on
  battery, results to `docs/NOTE.md`: (a) baseline = current state; (b) quiet asusd: hold the
  platform_profile re-apply (asusd.ron `platform_profile_on_battery`) — revert restores the
  managed line via `./eco apply`; (c) TB/USB4: drop `NHI0/NHI1` from the wakeup toggle list in
  `eco-power.sh` and add `thunderbolt` to `RUNTIME_PM_DRIVER_DENYLIST` in `01-eco.conf` — both
  revert by git; (d) `SOUND_POWER_SAVE_ON_*=0` in `01-eco.conf`; (e) kernel A/B on
  `linux-cachyos-lts` (last escalation). Auto-capture is armed meanwhile:
  `kernel.hung_task_panic=1` (`state/owned/etc/sysctl.d/98-hung-task-panic.conf`) turns the next
  silent wedge into a pstore panic record instead of a power-button event.
**Rejected here.** blaming the experimental 7.3 LTO kernel as sole cause: the stall vector was
  provably ours and the freeze vectors interact with repo-owned resume-time writes; a kernel A/B
  is the escalation path only after the tuning-side experiments are clean.
**Reopen.** After the experiment matrix (`docs/NOTE.md` 2026-09-29 suspend/resume entry) names
  the culprit, this entry becomes the settled verdict; any freeze recurrence with pstore evidence
  reopens it with the captured record.
