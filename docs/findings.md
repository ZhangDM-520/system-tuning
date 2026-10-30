# Findings — one entry per knob

**Purpose.** The only knob-truth home for this host (ASUS Zenbook S 16 UM5606WA, Ryzen AI 9 HX 370,
  CachyOS, btrfs root on WD SN560 — XFS until the 2026-10-05 reinstall). One `##` entry per knob; each entry answers, with nothing else
  read: what is true/applied and why (mechanism, owner rulings with their grilling-Q trail,
  superseded claims with their scope); what backs it and how to check it live; what has been
  refused; and what would reopen it. Operational modules keep their own depth: undo commands in
  `docs/rollback.md` (rollback#sd, rollback#misc), storage operations in `docs/rollback.md`
  (`## Storage ops`), campaigns and recipes in `docs/archive/XFS-TUNING.md`, measurement protocol in
  `benchmarks/METHODOLOGY.md`, judgment rules in `docs/judgment.md`. A few entries name the `./eco report`
  check that observes the knob; the check registry itself stays in the eco contract module.

**How to read Evidence.** Handles name surviving artifacts (`state/owned/…`, `state/managed/…`,
  `benchmarks/studies/…`, `benchmarks/METHODOLOGY.md`, `docs/archive/XFS-TUNING.md`,
  `docs/rollback.md`, `./tests/run`) plus the live readback command that settles the claim on
  this host — you verify with the command, never with a log line. Kernel-scoped claims per
  `benchmarks/docs/MEMORY.md`: benchmark numbers are stamped to the campaign kernel
  `7.2.5-1-cachyos-rt-bore-lto` and the host has since moved on; a re-run on a different kernel is a
  new baseline, not a reproduction, and historical figures are never edited to match. XFS-era
  mount-option behaviour was kernel-version-specific; the `## xfs-*` entries below are XFS-era
  history (root moved to btrfs 2026-10-05, campaign archived at `docs/archive/XFS-TUNING.md`)
  and no longer describe anything operative.

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

**Verdict.** Energy preference path **owned by power-profiles-daemon** (owner 2026-10-30: all
  profile handling to PPD, asusd muted per `## asusd`) — the repo writes no EPP and asserts
  ownership health (check EPP: PPD active, EPP sane on every policy) · **Class:** settled
**Why.** Superseded with scope: the `dynamic`-everywhere era (owner ruling plan v2; drift-only
  re-assert since 2026-10-17) — with PPD managing the profile path there is exactly one writer
  and the repo's writer is retired. History: `dynamic` followed platform profile and power source
  (performance-biased = race-to-sleep correct); benchmark-era `balance_power`/`balance_performance`
  optima are stamped to the campaign kernel. Boot-wedge mechanism (2026-10-17, still true
  kernel-side): the default→`dynamic` transition registers per-CPU platform-profile devices from
  inside the cpufreq store under `policy->rwsem` while the platform_profile core holds
  `profile_lock` across `device_register`/`sysfs_update_group` (kernfs active-ref drain) — a
  lock-order inversion hit 3/3 dock-at-boot boots; the sibling ABBA claim is refuted;
  `docs/research/2026-10-17-epp-deadlock-kernel-attribution.md` is the mechanism's one home
  (upstream fix = Lezcano 2026-10-14 series). PPD writes plain EPP values, which do not take the
  dynamic-transition path; nothing in the repo writes EPP any more (the drift-only loop in
  `eco-power.sh` and TLP's `CPU_ENERGY_PERF_POLICY_*` lines retired 2026-10-30). Not claimed: the
  kernel inversion itself is unfixed — any future dynamic-mode write re-enters the path.
**Evidence.** `lib/readers.sh` `check_epp` (ownership health + `ppd-conflict` probe) +
  `state/managed/` (profile-path records under `## asusd`);
  `state/managed/ppd-conflict.toml` neuters the stock PPD unit's `Conflicts=tlp.service` — a
  symmetric kill that TERMs whichever side starts second mid-run and fires TLP's
  `ExecStop=tlp init stop` shutdown phase (observed 2026-10-30; a drop-in `Conflicts=` does NOT
  clear a vendor list on systemd 262 — the managed line-patch is the mechanism) — plus
  `state/owned/etc/systemd/system/power-profiles-daemon.service.d/10-eco-coexist.conf`
  (`After=tlp.service`, TLP's one-shot boot pass first);
  `state/owned/etc/tlp.d/01-eco.conf` (EPP lines removed — TLP self-defers to PPD
  anyway: `10-tlp-func-cpu` `nop_ppd_active`); `state/owned/usr/local/sbin/eco-power.sh` (the
  drift-only writer retired). Check: `systemctl is-active power-profiles-daemon`,
  `powerprofilesctl get`, `cat /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference`,
  and the `./eco report` EPP row; for the deadlock: kernel attribution (mechanism truth home)
  `docs/research/2026-10-17-epp-deadlock-kernel-attribution.md`, initial boot forensics
  `docs/research/2026-10-17-boot-epp-deadlock-report.md`.
**Reopen.** measured joules-per-op evidence that a fixed EPP beats PPD's mapping; or PPD failing
  to hold the path (the row DRIFTs).

## ceil

**Verdict.** Per-class `scaling_max_freq` ceilings: Zen 5 4.7 GHz, Zen 5c 3.2 GHz; boost stays ON —
  applied (check CEIL) · **Class:** settled
**Why.** Zen 5 5.1 → 4.6 buys a stable undervolt (avg CO −20 vs −10): a real V/f sweet-spot win, not
  a cap. Zen 5c caps at 3.1/3.0/2.9 were all voltage-sensitive — Zen 5c sits near its sweet point,
  below the V/f hill, so lower caps lose real performance for minimal power saving; settled at 3.0
  GHz (owner, voltage-sensitivity testing 2026-09-26 — supersedes the earlier 3.1 → 3.0 → 2.9
  step-down). Superseded with scope: the 4.6/3.0 pair was the settlement at the deeper CO list;
  owner ruling 2026-10-10 raised both ceilings (4.6 → 4.7, 3.0 → 3.2) together with the second CO
  loosening step (`## co`) — the extra voltage headroom is what carries the higher ceiling, and
  both stay under the hardware max readback (Zen 5 5157895, Zen 5c 3289474 kHz). Boost stays ON
  because the ceiling already clips it; disabling boost would drop the hardware max to ~2.0 GHz
  base.
**Evidence.** `state/owned/usr/local/sbin/eco-power.sh` (re-asserts 4.7/3.2 per policy by
  `cpuinfo_max_freq`); the CPU map `ceil_for_cpu` in `lib/readers.sh` (Zen 5 = CPUs 0–3,12–15; Zen
  5c = 4–11,16–23; mirrored in `.github/copilot-instructions.md`). Check:
  `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq` and the `./eco report` CEIL row.
**Rejected here.** boost off (hardware max drops to ~2.0 GHz base, below the 4.7 GHz sweet spot).
**Reopen.** new voltage-sensitivity data showing the Zen 5c knee moved.

## co

**Verdict.** Curve Optimizer: `coall -7`, per-core `-24 -24 -21 -21 -9 -11 -8 -6` — applied
  (check CO) · **Class:** settled
**Why.** Free efficiency at unchanged temperature; the owner margin rule is one step and the tested
  point sits at that margin edge. Owner ruling Q6: the deep list was CoreCycler-validated
  ("validated-keep"). Cores 8–11 (Zen 5c remainder) fall back to `coall` by the packing rule.
  Superseded with scope: the validated-then-frozen `-7` / `-24 -24 -21 -21 -9 -11 -8 -6` list was
  loosened one step by owner ruling 2026-10-08 (coall −7 → −6; per-core +3 +3 +3 +3 +1 +1 +1 +1) —
  CPU stalls at too-low voltage are a hard-freeze suspect and can explain the `ryzen_smu` "out of
  sync" symptoms (`docs/findings.md` `## suspend-resume`); loosening is the safe direction. A second
  step on 2026-10-10 took the Zen 5 cores one step looser (`-20 -20 -17 -17`) to carry the raised
  4.7/3.2 GHz ceilings (`## ceil`, same-day owner ruling); 2026-10-11 loosened every offset by 2
  units (`coall −4`; per-core `-18 -18 -15 -15 -6 -8 -5 -3`) — the stability direction again;
  2026-10-26 loosened every offset 1 more unit (`coall −3`; per-core `-17 -17 -14 -14 -5 -7 -4 -2`).
  2026-10-29 owner ruling: the freeze is diagnosed as the resume-window race, not the undervolt —
  the whole loosening chain is reverted and every offset is restored to the CoreCycler-validated
  list (`coall −7`; per-core `-24 -24 -21 -21 -9 -11 -8 -6`, the most aggressive point we ran;
  owner Q6 "never opportunistically deeper than validated" is not breached — this IS the validated
  point). Caveat recorded, owner-accepted: the 4.7/3.2 ceilings (`## ceil`) were raised in 2026-10-10
  together with a CO loosening step, so deep-undervolt + raised-ceiling is a new combination whose
  validation predates the ceiling change.
  Packing mechanism: 16-bit two's complement, per-core payload `core_idx * 2^20 + offset`;
  `hw-tune.fish` is the single writer — never write CO values from anywhere else.
**Evidence.** `state/owned/home/zhangdm/.reserve/hw-tune.fish` (single SMU writer); the pinned
  policy mirror in `lib/readers.sh` `check_co`. Check:
  `sudo ryzenadj --info` — never the journal log (see `## ppt` Machine lies).
**Reopen.** never opportunistically; only a new full stability campaign may move it deeper. A
  looser step is always allowed (stability direction) — record it here as a dated owner ruling.

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

**Verdict.** `eco-power.service` is **boot-only for the SMU paths**; the 4.7/3.2 cpufreq ceiling
  has its own **drift-only watch** (`eco-ceil.timer` every 2 min + `82-eco-ceil.rules` on
  power-source events → `eco-power.sh ceil`, no SMU writes) (check TIMER) · **Class:** settled
**Why.** Owner ruling 2026-10-11 — the service runs at boot only: no periodic re-assert, no
  power-event re-assert of the SMU paths. Cost recorded, knowingly: live drift now survives until
  the next boot, and SMU limits lost on AC flaps are no longer re-asserted until then. The resume
  hook still re-asserts the SMU runtime knobs after suspend
  (`state/owned/usr/lib/systemd/system-sleep/eco-power` calls `eco-power.sh resume` directly — it
  does not start the service). Owner ruling 2026-10-29: the cpufreq ceiling was observed
  overwritten to the hardware max (5.1/3.3) between passes — the recorded "drift outlives a boot"
  reopen case — so the ceiling now has a dedicated watch. Deliberately NOT a return of the old
  backstop: the watch pass is drift-only and touches only `scaling_max_freq` (no ryzenadj/SMU
  writes, no EPP writes — EPP is PPD-owned since 2026-10-30 and nothing in the repo writes it).
  The caught-drift log line (`CEIL DRIFT policyN <old> -> <new>`) is also the
  overwriter probe: the overwriter is unidentified (TLP is proven innocent — its
  `CPU_MAX_PERF` is intel_pstate-only and `CPU_SCALING_MAX_FREQ` is unset); correlate catch
  timestamps with journal events to name it. Superseded with scope: the prior design (Q4/Q15) was
  event-driven re-asserts (boot, resume, AC uevent) plus a 600 s timer guarding unknown drift —
  canary-verified zero drift in an 11-minute window; its earlier 60 s cadence had been 719
  runs/day of SMU writes and wake bursts before being stretched to 600 s.
**Evidence.** `state/owned/etc/systemd/system/eco-power.service` (boot chain: `eco-power.sh` then
  `eco apply` as `ExecStart=-`); retired 2026-10-11: `etc/systemd/system/eco-power.timer` and
  `etc/udev/rules.d/99-eco-power.rules` (deleted from state and live); ceil watch since
  2026-10-29: `state/owned/etc/systemd/system/eco-ceil.{service,timer}`,
  `state/owned/etc/udev/rules.d/82-eco-ceil.rules`, `eco-power.sh ceil`. Check:
  `systemctl is-enabled eco-power.service eco-ceil.timer`, `ls
  /etc/systemd/system/eco-power.timer` (absent), `journalctl -u eco-ceil.service | grep 'CEIL
  DRIFT'`, and the `./eco report` TIMER row.
**Reopen.** SMU-limit loss on AC flaps surviving a boot; a CEIL DRIFT catch that never correlates
  with any journal event (a periodic writer — name it from the timestamps).

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

**Verdict.** Global ASPM policy `powersupersave` (L1 + L1 substates on 30/35 links; the 5
  BIOS-disabled links runtime-suspend anyway), runtime PM `auto` on all 40 PCI devices, zero armed
  wake sources — applied (check TLP observes the policy file) · **Class:** tunable
**Why.** Owner ruling 2026-10-29: the freeze is diagnosed as the resume-window race (the 21:14
  `amdgpu SMU: No response` template — `## suspend-resume`), not the aggressive tuning, so the
  freeze-era conservative actions are reverted and the policy goes to the most aggressive point we
  ran: `powersupersave` (it is the only enabler of L1.2 on the capable NVMe/SD/WiFi paths;
  per-device `aspm_mask` does not exist in this kernel). This supersedes, with scope preserved, the
  earlier "instability-proven on this box" attribution — that claim never carried an evidence
  handle outside this section. If link-level instability (NVMe errors, WiFi drops) recurs, the
  L1.2 substates are the first suspect and the policy drops back to `powersave`. The NVMe link runs
  Gen3 x4 (downgraded from the Gen4 cap) and stays there — forcing Gen4 costs watts. No
  `pcie_aspm=` cmdline: BIOS _OSC already grants OS control. TLP is the single owner of the policy
  file (it runs once at boot and exits — see `## daemons`).
**Evidence.** `state/owned/etc/tlp.d/01-eco.conf` (ASPM powersupersave + PM auto). Check:
  `cat /sys/module/pcie_aspm/parameters/policy`, `lspci -vv` (`LnkSta` per link),
  `grep . /sys/bus/pci/devices/*/power/control`, and the `./eco report` TLP row.
**Arm (f) 2026-10-08 → closed 2026-10-13.** `performance` (= ASPM off) ran as the freeze-
  investigation arm (H2, ACPI/PCIe power-state wedge — `docs/JOURNAL.md` 2026-10-08) and ended by
  owner selection: the policy read `[powersave]` again (readback verified 2026-10-13). The arm
  history stays recorded for the freeze work.
**Prior state (superseded, scope preserved).** `powersupersave` / L1.2 forcing was
  "instability-proven here" and rejected (no per-device lever exists) — overturned by the
  2026-10-29 ruling above; the prior text lives in git history.
**Reopen.** link-level instability under L1.2 (NVMe errors, WiFi drops) → policy back to
  `powersave`; a kernel with a per-device ASPM lever (none exists today).

## sched

**Verdict.** scx management **dropped** (owner 2026-10-10: "drop the scx part entirely, it needs
  updates later") — record deleted, SCHED reports `SKIPPED`, live scheduling is owner-managed ·
  **Class:** tunable (suspended)
**Why.** The scx-tools-git 1:1.1.3 layout change (installed 2026-10-10 07:17) moved the config
  sample to `/usr/share/scx_loader/config.toml` and removed `/etc/scx_loader.toml`; the managed
  record's missing target hard-failed **every** `./eco apply` wave — all state→live convergence
  stopped for ~10 h (that outage also hid the 2026-10-10 ceiling/CO wave from live). Dropped
  rather than repaired, per owner; the rework lands later against the new scx-tools layout.
  Retired with it: `state/managed/scx.toml`, `CHECK_MANAGED[SCHED]`, and `tests/run` cases 9–11
  (section-scoping coverage — the `section` engine stays in `lib/managed.sh`, untested until the
  record returns; restore that block from git history with the rework).
**Observed 2026-10-10 (unmanaged).** live sched_ext is an out-of-tree scheduler (`enabled+all`;
  identity owner-managed and deliberately not recorded in this repo) — not
  the scheduler of the prior verdict and not repo-controlled. That matters for the freeze work
  (`docs/JOURNAL.md` 2026-10-08, H5): an out-of-tree scheduler was live during the 2026-09-20
  hung_task record. Check: `cat /sys/kernel/sched_ext/state /sys/kernel/sched_ext/root/ops`.
**Observed 2026-10-14 (unmanaged).** live sched_ext is owner-managed direct-attach via session
  autostart (identity deliberately not recorded, owner policy). `scx_loader` stopped and **masked**
  2026-10-14: it is only D-Bus-activated anyway, `scxctl` is unusable until unmasked, and the
  benchmark harness (`benchmarks/tools/night-run.sh`) fails its preflight while masked. SCHED
  remains dropped/SKIPPED.
**Prior state (superseded, scope preserved).** scx_lavd 1.1.3 `--powersave --per-cpu-dsq
  --enable-cpu-bw` (core compaction) was the applied state; compaction keeps the fewest cores awake
  (the race-to-sleep pairing), `sched_*` sysctls/uclamp/prefcore/core-parking stay untouched (teo +
  C3 already park; measured C3 residency 69% Zen 5 / 90% Zen 5c), and the loader value
  `powersave_mode=["--efficiency"]` referenced a nonexistent flag and was changed to `--powersave`.
  Study 01's scx_pandemonium adoption (Pareto versus BORE) remains a separate, unresolved claim.
**Rejected here.** scx_pandemonium for power (its own README: +23.9% J/op versus EEVDF on its
  workload) — **qualified 2026-10-13 (owner)**: that benchmark may have been confounded by
  ananicy-cpp auto-nice (since disabled — with nice already optimised there is little scheduling
  room left to compete for), and the owner deliberately runs their chosen scheduler to try its
  own heuristics (identity deliberately not recorded in this repo, owner policy 2026-10-14); a
  full scheduler benchmark is planned on the owner's call.
  scx_rusty (spreads load across domains — structurally anti-compaction); core parking /
  hotplug (teo + C3 already park; hotplug churns sched_ext).
**Reopen.** the scx rework: new config path/record against scx-tools-git, then restore the
  section-scoping test block and re-run a scheduler A/B on the current kernel.
**Open.** pandemonium versus scx_lavd was never A/B'd on the current kernel; the two verdicts use
  different baselines (BORE vs EEVDF) and different workloads, so both claims stand recorded.

## asusd

**Verdict.** asusd power-profile handling **muted** — 5 managed records pin the mute surface
  (EPP/governor casts + AC/battery `platform_profile` switching); the profile value is
  power-profiles-daemon's runtime choice (check PROFILE) · **Class:** settled
**Why.** Owner ruling 2026-10-30 ("mute all asusctl power profile handling; all managed by
  power-profiles-daemon") closes the documented asusd/PPD two-writer race the other way: PPD is
  the single profile writer (re-enabled the same day), asusd keeps everything else (charge
  thresholds, keyboard, …) but none of the profile path. The claims: `platform_profile_linked_epp:
  false` (no EPP casting), `ac_command: ""` / `bat_command: ""` (no governor casting),
  `change_platform_profile_on_ac: false` / `change_platform_profile_on_battery: false` (no
  platform_profile writes on power events). Superseded with scope: the 2026-10-13 "take over the
  asusd config" ruling and its Q10 `platform_profile_on_battery: Balanced` record (retired
  2026-10-30 — inert once the switching is off; the Quiet EOPNOTSUPP fact stands in history).
  Mechanism to know, load-bearing for the freeze work: writing `platform_profile` resets the SMU
  limits and EPP through the EC even when writing the same value — that is why exactly one writer
  owns the attribute now.
**Evidence.** `state/managed/asusd-epp.toml`, `asusd-ac-cmd.toml`, `asusd-bat-cmd.toml`,
  `asusd-profile-ac.toml`, `asusd-profile-bat.toml` (one anchored line each in
  `/etc/asusd/asusd.ron`). Check: the `./eco report` PROFILE row,
  `grep -E 'linked_epp|command:|change_platform_profile' /etc/asusd/asusd.ron`, and
  `journalctl -u asusd | grep ThrottlePolicy` (profile writes should stop).
**Rejected here.** letting asusd cast or switch any of the profile path (the two-writer race);
  battery-profile Quiet (EOPNOTSUPP on this firmware, 2026-10-13).
**Reopen.** if the owner wants asusd profile switching back — then PPD must yield first.
**Machine lies.** asusd rewrites its own `asusd.ron` on restart (map keys reordered, values
  preserved) — compare by value, never by whole-file hash; the file must never end with an empty
  line — asusd reverts the config when it finds one (owner warning 2026-10-30; check PROFILE
  guards the EOF shape); startup noise "AC profile Balanced",
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
  writer of 6000/6000 and (in the XFS era) the sync interval was unblocked. Belt: `eco-power.sh` re-asserts
  6000/6000 on every trigger (boot, resume, AC event, 600s timer). Before persistence (Q2/Q3/Q11)
  the values were lost at every sysctl load. Superseded with scope: the 1500/1500 drift state and
  the 30-second-class default (the TLP-clobbered class) are gone; `fs.xfs.xfssyncd_centisecs=10000`
  was live from the same single-writer fix until the XFS era ended — retired 2026-10-05 with the
  btrfs reinstall (lowering it to 10 s had been measured-worse: 8.35 s vs 8.16
  s, log forces 135 vs 191, more wakeups).
**Evidence.** `state/owned/etc/sysctl.d/99-eco-writeback.conf`; `state/owned/etc/tlp.d/01-eco.conf`
  (`MAX_LOST_WORK_SECS_ON_AC/BAT=0`);
  `state/owned/usr/local/sbin/eco-power.sh` (re-assert belt). The resetter's source:
  `/usr/share/tlp/func.d/15-tlp-func-disk` (`set_dirty_parms()`) with the shipped defaults in
  `/usr/share/tlp/defaults.conf` (15 s AC / 60 s BAT). Check:
  `sysctl vm.dirty_writeback_centisecs vm.dirty_expire_centisecs` — read the runtime values, never
  the files alone (TLP was the resetter).
**Rejected here.** lowering `xfssyncd_centisecs` (measured-worse, more wakeups).
**Foreign state (observed 2026-10-05, values unchanged).** vendor
  `/usr/lib/sysctl.d/70-cachyos-settings.conf` also writes `vm.dirty_bytes=256 MiB`,
  `vm.dirty_background_bytes=64 MiB` and `vm.dirty_writeback_centisecs=1500`; the first two are
  unowned (recorded here so a clobber is visible), the third loses to `99-eco-writeback.conf`
  (99 > 70 in sysctl.d order) and to the re-assert belt. Check: `sysctl vm.dirty_bytes
  vm.dirty_background_bytes vm.dirty_writeback_centisecs`.
**Open.** no measured J/min confirmation for the whole writeback/wakeup family (6000/6000, xfssyncd,
  `speculative_prealloc_lifetime`): the timer-policy pair (xfssyncd 10000 → 30000, prelife 300 →
  1800) was INCONCLUSIVE at n=2/arm usable (MW-U minimum p = 0.333; one window
  owner-session-contaminated; the campaign was cut short when the host battery died — recorded
  INCONCLUSIVE-lean) and neither mechanism appeared (0 trim events in every window — the
  `wbig` workload never creates post-EOF speculative prealloc; idle log FORCE ≈ 8/min in both arms).
  Needs a quiet-machine idle-drain/wake-count campaign (powertop/turbostat windows ≥ 15 min/arm,
  deliberate panel blanking).

## journald

**Verdict.** journald `SystemMaxUse=256M` — applied (check IO observes writeback + this) · **Class:**
  tunable
**Why.** The journal sat near its 50M cap with a self-restart on cap hit; the cap was lowered to 32M
  (Q2/Q3/Q11), then raised to 256M on 2026-09-28 after the 32M cap vacuumed an entire freeze boot
  mid-investigation — the journal is forensics capacity, not just disk hygiene. Superseded with
  scope: the 32M verdict and its 2026-09-26 baseline readback (47.9M against a 32M cap).
**Evidence.** `state/managed/journald.toml` (anchored line `SystemMaxUse=256M`). Check:
  `journalctl --disk-usage`, `grep SystemMaxUse /etc/systemd/journald.conf`.

## io-stack

**Verdict.** NVMe scheduler `none`, `nr_requests=1023`, `read_ahead_kb=256`, `wbt_lat_usec=2000`
  kept; `vm.swappiness=150` (claimed in `state/owned/etc/sysctl.d/95-zram-swappiness.conf` since
  2026-10-13; the zram udev rule converges to the same value) — applied · **Class:** tunable
**Why.** `none` is race-to-idle: bursts drain immediately so the APST timer can start.
  `max_sectors_kb=128` is the drive's MDTS limit — I/Os split at 128 KiB, so `read_ahead_kb=256` is
  not a request size and prealloc sizes are about extents, not I/O size. WBT is load-bearing. Swap
  is zram lz4: pageouts never touch the SSD.
**Evidence.** `benchmarks/studies/03-filesystem-latency/README.md` (read-ahead, nr_requests
  refusals); `benchmarks/studies/02-boot-and-power/README.md` (WBT 0 refusal + warning, swappiness
  200, MDTS 128 KB); `docs/archive/XFS-TUNING.md` (stack baseline).   Persistence (2026-10-05): the vendor rule
  `/usr/lib/udev/rules.d/60-ioschedulers.rules` pins NVMe to `kyber`; the pre-reinstall host
  overrode it with a foreign `/etc/udev/rules.d/60-ioschedulers.rules` that died at the
  2026-10-05 reinstall (queue drifted to kyber/256 — found via
  `docs/research/btrfs-tunables.md` §0). Now owned: `state/owned/etc/udev/rules.d/61-eco-ioschedulers.rules`
  (named 61- so the vendor's sda/mmcblk rules stay live; sets scheduler first, then
  nr_requests/read_ahead_kb/wbt — elevator switches reset queue depth).
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
  (`poff`) measurement, not by duperemove's self-report — defrag is therefore never
  automated (it rewrites extents and un-does dedupe; a deliberately defragged file re-materializes
  private blocks, and the dedupe duty must re-catch them if the space matters). Dedupe-tool
  findings the accounting must know: identical-file groups are quadratic-ish (an 87k-member
  group pegged a core >55 min) — the old duperemove script excluded such trees, but **bees
  (the dedupe duty since 2026-10-05) has no per-directory exclusion**, so that mitigation does
  not transfer as-is and the   hazard is bounded only by bees' shipped throttling (watch it —
  `docs/rollback.md` `## Storage ops`). Drift closed 2026-10-13: since the 2026-10-05 reinstall the
  mounts ran the kernel default `discard=async` (dmesg "turning on async discard"); `fstab` now
  carries `nodiscard` on all 8 btrfs mounts, is a repo-owned mirror (`state/owned/etc/fstab`), and
  the runtime was remounted the same day (btrfs shows `discard=async` in the option string only
  when it is on — its absence means `nodiscard`). duperemove-era hashfile semantics (tool retired
  2026-10-05, kept for the archived recipe): `dedupe_seq` resume semantics skip files below the
  config marker permanently, `seq == max` are never processed, and setting all seq=0 hides files
  *below* the marker.
**Evidence.** `docs/rollback.md` (`## Storage ops` — dedupe/fstrim operations, automation,
  re-check commands); `docs/archive/XFS-TUNING.md` (reflink / `xfs_fsr` rules);
  `~/docs/NOTE.md:3762-3855` (session chronology behind the 2026-09-26..28 FS/XFS work: dedupe
  semantics, pitfalls, overrides). Dated FS baseline (2026-09-26): `/dev/nvme0n1p2` XFS
  `reflink=1`, 950G total, ~39% used, inodes 2%, pacman pkg cache 0 bytes (XFS-era history —
  root is btrfs since the 2026-10-05 reinstall). Check:
  `systemctl list-timers fstrim.timer 'btrfs-scrub@*'`, `findmnt -no OPTIONS /`,
  `df -h /`; duplicates directly via physical-offset (`poff`) measurement or
  `btrfs filesystem du` deltas — never via a tool's own estimate
  (`docs/research/btrfs-optimization.md` §9).
**Rejected here.** mount `discard` (root-unsafe/forbidden; fights APST); post-dedupe fstrim
  automation (the weekly timer suffices).
**Open (deferred 2026-10-05).** the `discard=async` drift (btrfs default since kernel 6.2 vs
  this verdict's batch-trim design) is deliberately unresolved: settle it by owner ruling or a
  measured A/B, never by editing this verdict (`docs/research/btrfs-optimization.md` §5).
**Machine lies.** free space keeps drifting down *after* a dedupe sweep (delayed block
  freeing) — never attribute freed space to dedupe without direct duplicate measurement.
  duperemove-era tool lies (tool retired 2026-10-05, kept for the archived recipe): it silently
  scans 0 files as non-root (libblkid UUID lookup) and exits 0; `--read-hashes` is a different,
  non-SQLite hash format and does nothing on a `--hashfile` database.

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
**Evidence.** `docs/archive/XFS-TUNING.md` (baseline, skip/avoid list, campaign results);
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
**Evidence.** `docs/archive/XFS-TUNING.md` (AB2 → nothing adopted; AB3 verdict → rolled back);
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
**Evidence.** `docs/archive/XFS-TUNING.md` (filestreams REJECT with numbers + ftrace proof 118800 lookups /
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
**Foreign state (observed 2026-10-05, value unchanged).** `vm.vfs_cache_pressure=50` from vendor
  `/usr/lib/sysctl.d/70-cachyos-settings.conf` — unowned; recorded so a clobber is visible.
  Check: `sysctl vm.vfs_cache_pressure`.

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
  (5) **Filesystem recovery domain.** Filesystem repair (`xfs_repair`, `btrfs check --repair`) is
  offline/rescue-media only — never on the
  mounted root (it can destroy data); online verification is the only mounted-fs check (the
  XFS-era monthly `xfs-scrub.timer` retired 2026-10-05; btrfs schedule pending
  `docs/research/btrfs-optimization.md` — see `docs/rollback.md` `## Storage ops`). Owner process ruling Q12: changes
  land in waves
  with dated `cp -p` backups before every write, verified after each wave — no blind parallel bursts
  onto a live system.
**Evidence.** `docs/rollback.md` (`## Undo: universal mechanism` — the backup mechanism home);
  `docs/archive/XFS-TUNING.md` (persistence pitfall + dual-file rule); `docs/eco-power-README.md`
  (repo-first flow, exit-code contract); `benchmarks/README.md` (two-writer race lesson). Check:
  `sudo bash -c 'ls /boot/limine.conf*'`; `grep -c rootflags /boot/limine.conf /etc/default/limine`;
  `grep -rn <value> state/` (exactly one hit).
**Open.** backup gap (assessed 2026-09-28 on XFS, which has no snapshots): no
  borg/restic/snapper/partclone installed — dedupe,
  TRIM and scrub protect against none of the failure modes backups protect against; the
  recommendation (borg or restic to off-host or external storage) stands for the next maintenance
  window (the 2026-10-05 btrfs move added local snapshot capability — re-assess alongside
  `docs/research/btrfs-optimization.md`).

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
**Why.** Screen-on idle sits at mid DPM levels (sclk ~631–752 MHz, mclk never 400 MHz) because the
  2880×1800@120 VRR panel is lit. Measured 2026-10-29 (quiet interleaved A/B on battery —
  `energy_now` deltas + 1 Hz `pp_dpm_mclk`, agent load removed; protocol
  `~/Workspace/mclk-vrr-ab.sh`): the 120 Hz scanout floor alone pins mclk at 800 MHz (100/100
  samples) while 60 Hz reaches 400 MHz immediately (200/200; display-off likewise) — the refresh
  premium is **+1.76 W at idle** (paired 8.04/7.96 vs 6.24/6.24 W). Owner ruling 2026-10-29: keep
  the 120 Hz default knowingly (60 Hz is one `mode` line away in
  `~/.config/umbriel/cfg/display.toml`). PSR `self_refresh_active` never engages (250/250
  samples, static screen included) — the "VRR lets idle refresh drop" hope is not observed on
  this panel; VRR stays enabled (owner keep) and the screen-off chain (see `## autosuspend`) is
  the idle remedy. ABM `panel_power_savings=1` is active; backlight via `amdgpu_bl1`, no cap.
  The refresh is the mclk lever — no safe DPM write lever exists. Adjacent device
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

**Verdict.** No timer storm — 9 system + 1 user timer; day/week/month cadences dominate and the two
  hourly outliers are resolved (2026-10-13: snapper-cleanup → 6h via owned drop-in, user
  trash-purge → 1d via managed record; `man-db.timer` disabled-but-active drift fixed by enabling);
  the eco-power backstop is retired (service boot-only since 2026-10-11); PPD masked; TLP single owner (runs
  once at boot, exits); asusd is epoll/uevent-driven (1.27 s CPU over 13 h) with no EC polling
  interval to tune; 0 armed ACPI wake sources, RTC wakealarm empty, no cron/anacron, no monitoring
  agents, fprintd absent; all inhibitors are delay-mode (swayidle/noctalia lock chain) — nobody
  blocks suspend indefinitely · **Class:** settled
**Why.** Nothing in the daemon set competes for wakeups or writes (TLP exits after boot; the
  asusd/PPD two-writer precedent is closed by masking PPD). The scheduled set is maintenance:
  weekly fstrim + smartd self-test and monthly `btrfs-scrub@-.timer` (stock unit); dedupe is the
  continuous `beesd@` service (daily duperemove job retired 2026-10-05; xfs-scrub retired with
  the XFS era). The duty-by-duty record lives in
  `docs/rollback.md` `## Storage ops — what runs automatically`.
**Owner-kept 2026-10-13.** `bpftune.service` (BPF auto-tuner, `sysctl_tuner` among its tuners) runs
  by owner election — kept; watch it as a possible sysctl co-writer (one-writer rule) and as the
  lead candidate for the unidentified second writer of `snd_hda_intel power_save`
  (`## suspend-resume`). Same pass: GPP0/GPP1 (USB4 bridges) were armed and are now in
  `eco-power.sh`'s wake-trim list; duplicate XDG autostart copies of fcitx5/kdeconnectd hidden in
  `~/.config/autostart` (the niri spawns are the kept single-instance path).
**Evidence.** `state/owned/etc/systemd/system/*.timer`; `docs/rollback.md`
  (`## Storage ops — what runs automatically`).
  Check: `systemctl list-timers --all`, `cat /sys/class/rtc/rtc0/wakealarm` (empty),
  `grep . /proc/acpi/wakeup` (nothing armed), `systemd-inhibit --list` (all delay-mode).

## suspend-resume

**Verdict.** RESOLVED-IN-PRACTICE, causal chain uncertain — owner reports fixed (2026-09-29 23:05)
  after the stale `.bak` resume hook was removed; `hw-tune.fish` restored to the resume path
  (single-pass) by owner directive — which also serves as the A/B "on" arm. Capture stays armed
  (SysRq=190, hung_task_panic=1 behind a 120 s hang bar, efi_pstore, 256M journals; the capture
  set was risk-narrowed 2026-10-08 and the tuning knobs restored 2026-10-29 — see the auto-capture
  note below). If a freeze recurs, the first
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
**Suspects not yet A/B'd.** `SOUND_POWER_SAVE_ON_AC/BAT` (1 → 0, applied 2026-10-08 — see arm (d)
  below; the 1 s value was restored 2026-10-29 when the owner attributed the freeze to the race
  and reverted the conservative actions) vs the cs35l56 re-init hang; sched_ext BPF scheduler (`enabled+all`; out-of-tree "pandemonium"
  was live during the 09-20 hung_task) vs whole-system freeze. Owner defers all experiments until
  a freeze recurs; runbook then is one variable at a time, ≥5 resume cycles on AC and 5 on
  battery, results to `docs/JOURNAL.md`: (a) baseline = current state; (b) quiet asusd: hold the
  platform_profile re-apply (asusd.ron `platform_profile_on_battery`) — revert restores the
  managed line via `./eco apply`; (c) TB/USB4: drop `NHI0/NHI1` from the wakeup toggle list in
  `eco-power.sh` and add `thunderbolt` to `RUNTIME_PM_DRIVER_DENYLIST` in `01-eco.conf` — both
  revert by git; (d) `SOUND_POWER_SAVE_ON_*=0` in `01-eco.conf` — **applied prospectively
  2026-10-08** (risk pass: stability outranks the codec's idle watts) **and reverted 2026-10-29**
  (owner ruling: the freeze is the resume-window race; the `(1, Y)` codec reload cycle is accepted
  back — a recurrence that wedges in `azx_get_response` again re-credits arm (d)):
  `apply_common_settings` calls `set_sound_power_mode`, which writes `snd_hda_intel`
  `{power_save,power_save_controller}` (module default is 10 s — `CONFIG_SND_HDA_POWER_SAVE_DEFAULT=10`,
  check `cat /sys/module/snd_hda_intel/parameters/power_save{,_controller}` after
  `systemctl restart tlp`), so 1 = the `(1, Y)` pair and the codec suspend/wake firmware-reload
  cycle is armed again — matching the `## gpu-display` `power_save=1s` note (that outcome, not
  stale); (e) kernel A/B on
  `linux-cachyos-lts` (last escalation). Auto-capture is armed meanwhile:
  `kernel.hung_task_panic=1` (`state/owned/etc/sysctl.d/98-hung-task-panic.conf`) turns the next
  silent wedge into a pstore panic record instead of a power-button event — at the 120 s default
  line (restored 2026-10-29 with the freeze-era reverts; the 2026-10-08 risk pass's 300 s bar is
  superseded — the 2026-09-20 record fired at 122 s of D-state and the owner accepts panicking
  near that line for capture certainty), and
  `kernel.sysrq=190` keeps p/t/m/l dumps plus the s/u/b rescue while dropping the e/i/f
  mass-process-kill chord (bit 64) that one accidental keypress could fire.
**Open (2026-10-08).** a second boot-time writer of `snd_hda_intel` `power_save` is unidentified:
  01:14:17.218, 0.7 s after TLP's write, and the observed `(0, Y)` pair matches no single TLP
  outcome (`pwr=1`→`(1,Y)`, `pwr=0`→`(0,N)`, untouched→`(10,Y)`). It writes 0 — the safe value —
  but it breaks the one-writer rule and would muddy a future arm-(d) A/B; identify it before the
  next audio experiment.
**Rejected here.** blaming the experimental 7.3 LTO kernel as sole cause: the stall vector was
  provably ours and the freeze vectors interact with repo-owned resume-time writes; a kernel A/B
  is the escalation path only after the tuning-side experiments are clean.
**Reopen.** After the experiment matrix (`docs/JOURNAL.md` 2026-09-29 suspend/resume entry) names
  the culprit, this entry becomes the settled verdict; any freeze recurrence with pstore evidence
  reopens it with the captured record.
