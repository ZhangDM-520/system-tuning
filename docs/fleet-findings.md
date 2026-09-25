# Fleet findings

When to read: before researching or proposing any new tuning candidate. The rejection table
answers most "should we try X" questions with no. Source: 8 parallel read-only research agents,
2026-09-24, plus the implementation wave that followed.

## Ranked findings (all resolved)

| Rank | Finding | Resolution |
|------|---------|------------|
| 1 | BT autosuspend dead: older `btusb-no-autosuspend.conf` shadowed our modprobe file | old file renamed `.disabled`, param Y (decisions#bt) |
| 2 | NM global `wifi.powersave=2` would disable PS on any future profile | set to 3 (Q2) |
| 3 | dirty writeback 6000/6000 unpersisted, reverted at every sysctl load | `/etc/sysctl.d/99-eco-writeback.conf` |
| 4 | eco-power timer at 60s = 719 runs/day of SMU writes and wake bursts | stretched to 600s, canary-verified (decisions#timer) |
| 5 | STAPM readback 17-20 W despite 31 W writes | ACCEPTED as firmware preference (decisions#ppt, quirks#stapm) |
| 6 | I2C-C bus top IRQ source with 5k/s bursts | identified: ASUP1207 touchpad, interrupt-driven, idle 0/s; no rogue poller |
| 7 | SD reader awake all day with no card | unbound at runtime (rollback#sd) |
| 8 | `acp_power_gating=0` suspected non-default | module inert (device held by snd_acp_pci); set 1 + persisted |
| 9 | scx_loader `powersave_mode=["--efficiency"]` referenced a nonexistent flag | changed to `--powersave` |
| 10 | localsearch-3 indexer running | masked (owner-approved app-search degradation) |
| 11 | asusd `platform_profile_on_battery: Quiet` not in firmware choices | mapped to Balanced (quirks#asusd) |
| 12 | journald near its 50M cap, self-restart on cap hit | SystemMaxUse=32M |

## wifi

WiFi power-save is verified ON end to end, on the **MT7925** chipset (mt7925e/mt76, not iwlwifi:
every iwlwifi knob is N/A here). Layers that agree: `iw dev wlan0 get power_save`=on, NM profile
`802-11-wireless.powersave=3`, NM global `wifi.powersave=3`, udev `81-wifi-powersave.rules`, TLP
`WIFI_PWR_ON_AC/BAT=on`, mt76 `deep-sleep=1` and `runtime-pm=1`, PCIe ASPM L1. Not tunable on
mt7925: fw_pwr_table (mt7966-class only), interrupt coalescing (no ethtool support). bgscan is
dormant at good signal (fires only below -65 dBm). Keep everything.

## pcie

Global ASPM policy `powersave` (L1 enabled on 30/35 links; the 5 BIOS-disabled links all
runtime-suspend anyway). Runtime PM `auto` on all 40 PCI devices, zero armed wake sources.
**L1.2 is capable on the NVMe/SD/WLAN paths but disabled everywhere, and the only enabler is the
global `powersupersave`, which is instability-proven on this box; per-device `aspm_mask` does not
exist in this kernel. Dead end: do not chase.** The iGPU (1002:150e) has NO L1 PM Substates
capability at all: the "iGPU L1.2 win" does not exist on this hardware. NVMe link runs Gen3 x4
(downgraded from Gen4 cap): keep, forcing Gen4 costs watts. No `pcie_aspm=` cmdline: BIOS _OSC
already grants OS control.

## storage

Single WD SN560 NVMe (no SATA, no MMC card). APST armed two-stage (PS3 after 100ms, PS4 after 2s;
PS5 gated out by `default_ps_max_latency_us=100000`, and unlocking it risks root-disk exit-latency
stalls: REJECT). Scheduler `none` (race-to-idle: bursts drain immediately so the APST timer can
start), persisted by udev. XFS with lazytime (zero atime wakeups), weekly fstrim (continuous
discard=async would keep the device busy), xfssyncd 100s. Swap is zram lz4: pageouts never touch
the SSD. NVMe PCI function shows 0ms runtime-suspended despite `auto`: root-disk reality, link L1
still applies. Dirty writeback 6000/6000 is a wakeup reduction, not a cap (fsync and journal
unaffected).

**Dirty writeback runtime resetter, root cause (found 2026-09-25)**: the runtime values drift back
to 1500/1500 even though `/etc/sysctl.d/99-eco-writeback.conf` (owned mirror) sets 6000/6000 and
nothing reboots. The resetter is **TLP itself**: `set_dirty_parms()` in
`/usr/share/tlp/func.d/15-tlp-func-disk` writes `vm.dirty_writeback_centisecs`,
`vm.dirty_expire_centisecs` (and the XFS age knobs) from `MAX_LOST_WORK_SECS * 100` on every
power-source event and at startup. Our `/etc/tlp.d/01-eco.conf` leaves `MAX_LOST_WORK_SECS`
unset, so the shipped defaults win (`/usr/share/tlp/defaults.conf`: 15 s on AC, 60 s on BAT),
which is exactly the observed 1500/1500 on AC. This also explains why the same file
`20-xfs-sync-interval.conf` (`xfssyncd_centisecs = 10000`) keeps getting overridden to 1500.
Convergence consequence: `eco apply` re-asserts the runtime values whenever they drift (even when
the owned file is unchanged), and `eco-power.sh` re-asserts them on every trigger (boot, resume,
AC event, 600s timer). Candidate one-shot fix, not applied (would need a fresh owner decision):
`MAX_LOST_WORK_SECS_ON_AC=0` and `MAX_LOST_WORK_SECS_ON_BAT=0` in `01-eco.conf` makes TLP skip
`set_dirty_parms` entirely (`cage=0` is its do-nothing path), leaving 99-eco-writeback.conf the
single writer of those knobs and unblocking the XFS sync interval too.

## sched

Running scheduler is **scx_lavd 1.1.3 with `--powersave --per-cpu-dsq --enable-cpu-bw`**
(core compaction: fewest awake cores, the race-to-sleep pairing). scx_pandemonium is installed but
must NOT be used for power: its own README shows +23.9% J/op versus EEVDF on its test workload.
scx_rusty spreads load across domains: structurally anti-compaction. All `sched_*` sysctls,
uclamp, prefcore (hw-disabled), and core parking: touch nothing (teo + C3 already parks cores in
microseconds; hotplug churns sched_ext domains for no gain). C3 residency measured 69% (Zen5) /
90% (Zen5c): nothing blocks deep idle.

## cpu

Stack verified optimal as configured: amd-pstate-epp active mode (firmware-autonomous V/f within
our bounds), EPP dynamic, min freq 605264 = lowest_nonlinear (the V/f knee), boost ON but clipped
by the per-class ceilings, no module params to tune (`/sys/module/amd_pstate` does not exist).
Kernel: NO_HZ_IDLE (NO_HZ_FULL not compiled), PREEMPT_LAZY stock CachyOS, HZ=600 irrelevant to
idle because ticks stop. `zswap` not compiled and pointless here (swap is already compressed zram).
Cmdline needs nothing added.

## smu

ryzenadj tunable survey on Strix Point (SMU IF 21). Used: CO (decisions#co), envelope
(decisions#ppt), `--power-saving` (decisions#eco). **Family-gated in ryzenadj source (cannot even
reach the SMU): all min/max clock-domain tunables (socclk/fclk/vcn/lclk/gfxclk), oc-clk/oc-volt,
enable-oc, apu-skin-temp.** SMU-rejected (tool accepts, firmware refuses): `--set-cogfx`, all
PSI setters, `--prochot-deassertion-ramp`. Rejected by doctrine: TDC/EDC changes, thermal limits,
skin-temp-limit (it is a power cap), gfx-clk (forced clock), max-performance. See quirks for
readback artifacts.

## display

GPU is **card1** (`/sys/class/drm/card1`), not card0: earlier `power_dpm_state` writes targeted a
nonexistent path. The real lever `power_dpm_force_performance_level=auto` is correctly applied by
TLP. On this SMU APU `power_dpm_state` is cosmetic and `pp_power_profile_mode` does not exist.
Screen-on idle sits at mid DPM levels (sclk ~631-752 MHz, mclk never 400 MHz, ~15 W at 2-3% busy)
because the 2880x1800@120 VRR panel is lit: no safe write lever exists, and the 70s screen-off
chain is the correct remedy. ABM panel_power_savings=1 active. VRR always-on lets idle refresh
drop: keep. Backlight via amdgpu_bl1, no cap. Audio: power_save=1s + controller power gating on
(baseline "10" was stale); HDMI HDA suspends for hours when unused. Camera USB device suspends;
7 of 8 xHCI hubs suspend; no `control=on` offenders exist.

## kernel

No cmdline additions recommended. Rejections: `zswap.enabled=0` is inert (not compiled),
`nohz_full` not compiled, `pcie_aspm=force` unneeded (BIOS grants control), THP on madvise is
power-neutral. Deep C-states POLL/C1/C2/C3 only (firmware-defined), all enabled, zero blocked.
Interrupt noise at idle: I2C-C (touchpad), amdgpu, WiFi beacons; all expected and activity-driven.

## daemons

No timer storm: 9 system + 1 user timer, all daily/weekly/night-clustered (the eco-power backstop
was the only sub-minute timer, now 600s). PPD masked, TLP single owner (runs once at boot, exits).
asusd is epoll/uevent-driven (1.27s CPU over 13h), no EC polling interval exists to tune. 0 armed
ACPI wake sources, RTC wakealarm empty, no cron/anacron, no monitoring agents, fprintd absent.
Inhibitors are all delay-mode (swayidle/noctalia lock chain): nobody blocks suspend indefinitely.

## Rejection table (do not re-propose without new evidence)

| Candidate | Why rejected |
|-----------|--------------|
| ASPM powersupersave / L1.2 forcing | instability-proven here; no per-device lever exists |
| iGPU L1.2 | capability absent on this chip |
| zswap | not compiled; swap is already zram |
| nohz_full | not compiled; NO_HZ_IDLE already stops ticks |
| NVMe PS5 unlock | root-disk exit-latency stall risk, exit latency unmeasured |
| boost off | hardware max drops to ~2.0 GHz base, below the 4.6 GHz sweet spot |
| core parking / hotplug | teo + C3 already park; hotplug churns sched_ext |
| ryzenadj min/max clocks, OC, forced gfx clock | family-gated or doctrine-forbidden |
| TDC/EDC / thermal-limit changes | caps or safety-margin erosion, zero joule gain |
| scx_pandemonium / scx_rusty for power | +24% J/op; load spreading is anti-compaction |
| GPU DPM manual pinning | stalls bursts; screen-off chain already handles idle |
| power caps / throttling of any kind | cheating (doctrine) |
