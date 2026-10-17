# Forensic Report: Boot-Time Kernel `D`-State Lockup in `eco-power.sh` (`dynamic` EPP Race)

- **Date:** 2026-10-17
- **Kernel:** `7.3.0-rc6-1-cachyos-bore-lto`
- **Affected Files in Repo:**
  - `state/owned/usr/local/sbin/eco-power.sh` (lines 28–30, 83–86)
  - `state/owned/etc/systemd/system/eco-power.service` (lines 1–10)
  - `state/owned/etc/tlp.d/01-eco.conf` (lines 13–15)

---

## 1. Executive Summary

Across three consecutive boots on `2026-10-17` (Boots `-3` at `12:52:13`, `-2` at `12:55:47`, and `-1` at `12:59:08`), the host wedged in uninterruptible kernel sleep (`TASK_UNINTERRUPTIBLE` / `D` state) within 9–10 seconds of boot whenever external power / the USB-C dock (`GODO Metal SDD-Dock`) was attached at boot.

In every wedged boot:
1. `eco-power.service`, `tlp.service`, and `asusd.service` started concurrently at `multi-user.target` (no `After=` ordering exists between them in `state/owned/etc/systemd/system/eco-power.service`).
2. `eco-power.sh` completed `hw-tune.fish quick` and logged `eco-power: hw-tune.fish applied (CO + 31W envelope + SMU eco flags)` (`eco-power.sh:21`), then entered the `policy*/energy_performance_preference` loop (`eco-power.sh:28–30`):
   ```bash
   for pol in /sys/devices/system/cpu/cpufreq/policy*; do
     [ -w "$pol/energy_performance_preference" ] && echo dynamic > "$pol/energy_performance_preference" 2>/dev/null
   done
   ```
3. `eco-power.sh` **never reached line 38** (`log "cpuidle governor=teo"`) in any of the three boots. Both `eco-power.service` and `tlp.service` remained permanently stuck in kernel `D` state, surviving two rounds of `SIGKILL` from `systemd` at shutdown (`Processes still around after final SIGKILL`).
4. Once a writer deadlocked holding `policy->rwsem` / `profile_lock` in the kernel:
   - `niri-session` still launched (it only touches `/dev/dri/card1`, `/dev/input/*`, and Wayland sockets).
   - Any userspace process reading or writing cpufreq/platform-profile/power_supply sysfs (`scxtop`, `scx_pandemonium`, `netease-cloud-music-web-player`, `reboot`) immediately blocked in `D` state on the contended kernel lock, leaving a blinking terminal cursor that ignored `SIGINT` (`^C`) and `SIGKILL`.

---

## 2. Boot-by-Boot Evidence (`journalctl -b -3..0`)

### 2.1 Boot `-3` (`9678ffca355e43a094466bb0c29e3b3f`, `12:52:13`) — Dock Connected at Boot (Wedged)
- `12:52:19.160235` (`[8.308s]`): `systemd[1]: Starting Apply TLP system startup/shutdown...` (`tlp.service`) and `Starting Apply eco power settings...` (`eco-power.service`).
- `12:52:19.342843`: `asusd[1724]: Platform: set_platform_profile — Setting Performance before EPP` (AC online via dock).
- `12:52:20.777722` (`[9.925s]`): `eco-power.sh[1960]: eco-power: hw-tune.fish applied (CO + 31W envelope + SMU eco flags)`.
- `12:52:20.778223` (`+0.501 ms` later): `asusd[1724]: Platform: watch_platform_profile changed` — triggered by `eco-power.sh` writing `dynamic` to `policy0/energy_performance_preference`.
- **No further output from `eco-power.sh` (`cpuidle governor=teo` at line 38 is never reached).**
- At shutdown (`12:53:22`–`12:53:42`), `systemd` timed out waiting for `eco-power.service` (PID 1960) and `tlp.service` (PID 1962), sending two `SIGKILL` waves:
  ```text
  12:52:52.717643 systemd[1]: tlp.service: Stopping timed out. Terminating.
  12:53:22.248441 systemd[1]: eco-power.service: State 'stop-sigterm' timed out. Killing.
  12:53:22.248543 systemd[1]: eco-power.service: Killing process 1960 (eco-power.sh) with signal SIGKILL.
  12:53:22.976268 systemd[1]: tlp.service: State 'final-sigterm' timed out. Killing.
  12:53:22.976554 systemd[1]: tlp.service: Killing process 1962 (tlp) with signal SIGKILL.
  12:53:42.495999 systemd[1]: eco-power.service: Processes still around after final SIGKILL. Entering failed mode.
  12:53:43.246348 systemd[1]: tlp.service: Processes still around after final SIGKILL. Entering failed mode.
  ```

### 2.2 Boot `-2` (`046dcbe440ef48e5becd8d0be656c2a2`, `12:55:47`) — Dock Connected at Boot (Wedged)
- `12:55:53.038354`: `asusd[1646]: Platform: set_platform_profile — Setting Performance before EPP`.
- `12:55:54.375304` (`[9.011s]`): `eco-power.sh[1922]: eco-power: hw-tune.fish applied (CO + 31W envelope + SMU eco flags)`.
- `12:55:54.375890` (`+0.586 ms` later): `asusd[1646]: Platform: watch_platform_profile changed`.
- **No further output from `eco-power.sh` (`cpuidle governor=teo` never reached).**
- `scx_pandemonium` (PID 2470) also wedged in `D` state (`12:58:23.384950 systemd[1951]: niri.service: Unit process 2470 (scx_pandemonium) remains running after unit stopped`).

### 2.3 Boot `-1` (`ccac979ba8e2421290b96008fc7f375e`, `12:59:08`) — Dock Connected at Boot (Wedged)
- `12:59:14.234538`: `asusd[1688]: Platform: set_platform_profile — Setting Performance before EPP`.
- `12:59:15.320496` (`[8.959s]`): `eco-power.sh[1906]: eco-power: hw-tune.fish applied (CO + 31W envelope + SMU eco flags)`.
- `12:59:15.321048` (`+0.552 ms` later): `asusd[1688]: Platform: watch_platform_profile changed`.
- **No further output from `eco-power.sh` (`cpuidle governor=teo` never reached).**

### 2.4 Boot `0` (`c8c807c0792b49428b46ab136e5fa3df`, `13:03:45`) — Dock Unplugged at Boot (Succeeded)
- In Boot `0`, the USB-C dock was unplugged at boot (only plugged in 19 minutes later at `13:22:29`).
- `13:03:52.142423`: `asusd[1729]: Platform: set_platform_profile — Setting Balanced before EPP` (battery mode).
- `13:03:52.497972` (`[8.537s]`): `eco-power.sh[1880]: eco-power: hw-tune.fish applied (CO + 31W envelope + SMU eco flags)`.
- `13:03:52.534981` (`[8.574s]`, `+37 ms` later): `eco-power.sh[1880]: eco-power: cpuidle governor=teo`, followed by all `policy0..23 scaling_max_freq`, wake disables, writeback sysctl, and `Finished Apply eco power settings` at `13:03:58.969356`.

---

## 3. Kernel Root Cause (`7.3.0-rc6-1-cachyos-bore-lto` `vmlinux` Analysis)

Disassembly of `store_energy_performance_preference` (`0xffffffff823de900`), `platform_profile_register` (`0xffffffff8209ed40`), and `amd_pstate_profile_set` (`0xffffffff823df6c0`) in `/usr/lib/modules/7.3.0-rc6-1-cachyos-bore-lto/build/vmlinux` reveals why concurrent `dynamic` EPP writes and `platform_profile` operations deadlock:

1. **Sysfs write acquires `down_write(&policy->rwsem)`:**
   When `eco-power.sh` (or `tlp`) writes `dynamic` to `/sys/devices/system/cpu/cpufreq/policyX/energy_performance_preference`, the cpufreq sysfs store wrapper takes `down_write(&policy->rwsem)` before calling `store_energy_performance_preference`.
2. **CachyOS `amd-pstate` `dynamic` EPP registers 24 `platform_profile` handlers and 24 `power_supply` notifiers inside `policy->rwsem`:**
   When `policyX` transitions into `dynamic` mode (`cpudata->dynamic_epp == false` → `true`), `store_energy_performance_preference` executes (while still holding `policy->rwsem`):
   - Hardcodes `cpudata->current_profile = PLATFORM_PROFILE_BALANCED (3)` (`movl $0x3, 0x110(%r12)` at `0xffffffff823deab9`).
   - Calls `power_supply_is_system_supplied()` (`0xffffffff823deac2`), which iterates `power_supply_class` devices and calls into the ACPI/UCSI power_supply get_property callbacks.
   - Calls `devm_kasprintf(dev, GFP_KERNEL, "amd-pstate-epp-cpu%u", policy->cpu)` (`0xffffffff823deadf`) and `platform_profile_register(&amd_pstate_profile_ops, cpudata)` (`0xffffffff823deb0b`), creating `/sys/class/platform-profile/platform-profile-0` through `platform-profile-23`.
   - Inside `platform_profile_register`: takes `mutex_lock(&profile_lock)` (`0xffffffff8209edbb`), registers the class device, and fires `sysfs_notify(acpi_kobj, NULL, "platform_profile")` (`0xffffffff8209ee7e`).
   - Calls `power_supply_reg_notifier(&cpudata->psy_nb)` (`0xffffffff823deb2d`), acquiring the atomic/blocking notifier chain lock on `power_supply_notifier`.
3. **Why AC/Dock at Boot Triggers the Collision:**
   - Because `store_energy_performance_preference` hardcodes initial `cpudata->current_profile = PLATFORM_PROFILE_BALANCED (3)` and fires `sysfs_notify(acpi_kobj, NULL, "platform_profile")` on every CPU (`0..23`), `asusd` (which just set `Performance (5)` on AC and monitors `/sys/firmware/acpi/platform_profile` via inotify) immediately wakes (`Platform: watch_platform_profile changed` at `+0.5 ms` after `hw-tune.fish applied`).
   - At the exact same moment, three concurrent writers are hammering the same interconnected locks (`policy->rwsem`, `profile_lock`, `power_supply_notifier`, and ACPI/EC/UCSI locks):
     1. **`eco-power.sh`** writing `dynamic` across `policy0..23` twice (pass 1 at line 33, pass 2 at line 85).
     2. **`tlp` (`tlp.service`)** ALSO writing `dynamic` across `policy0..23` (`CPU_ENERGY_PERF_POLICY_ON_AC=dynamic` in `state/owned/etc/tlp.d/01-eco.conf:13–15`) while concurrently toggling PCIe ASPM, runtime PM, USB autosuspend, and probing power supplies.
     3. **`asusd` (`asusd.service`)** writing/reading `/sys/firmware/acpi/platform_profile` (which takes `mutex_lock(&profile_lock)` and walks all registered `platform-profile-*` handlers, including the `amd-pstate-epp-cpu*` handlers being registered/updated).

---

## 4. Architectural Findings & Fix Options for `system-tuning`

### Finding 1: Zero systemd ordering between `eco-power.service`, `tlp.service`, and `asusd.service`
`state/owned/etc/systemd/system/eco-power.service` currently specifies:
```ini
[Unit]
Description=Apply eco power settings (ryzenadj caps + amdgpu dpm state)
After=multi-user.target
```
Because `tlp.service` and `asusd.service` are WantedBy `multi-user.target` (or start alongside it), `systemd` launches `eco-power.sh` in parallel with `tlp init start` and `asusd`'s initial profile setup.
- **Ordering fix:** Add `After=multi-user.target tlp.service asusd.service` to `state/owned/etc/systemd/system/eco-power.service` so `eco-power.sh` never runs concurrently with `tlp`'s boot pass or `asusd`'s startup profile write.

### Finding 2: Redundant/unconditional `echo dynamic > energy_performance_preference` writes
In `state/owned/usr/local/sbin/eco-power.sh:28–30`:
```bash
  for pol in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -w "$pol/energy_performance_preference" ] && echo dynamic > "$pol/energy_performance_preference" 2>/dev/null
  done
```
And `apply_cpu_power` is called **twice** on every boot (`line 33` and `line 85` after `sleep 5`), while `tlp` (`01-eco.conf:13–15`) *also* writes `dynamic` to all 24 policies at boot.
Because `asusd` already has `platform_profile_linked_epp: false` (`docs/findings.md ## asusd`), `asusd` no longer overwrites EPP with `BalancePerformance` or `Power` on profile events. Moreover, writing `dynamic` unconditionally when `energy_performance_preference` already reads `dynamic` still enters `store_energy_performance_preference` under `down_write(&policy->rwsem)` 24 times per pass.
- **Idempotency guard fix in `eco-power.sh`:** Only write `dynamic` to `$pol/energy_performance_preference` if `[ "$(cat "$pol/energy_performance_preference" 2>/dev/null)" != dynamic ]`.
- **Single-writer consideration:** If `tlp` (`01-eco.conf:13–15`) already sets `CPU_ENERGY_PERF_POLICY_ON_AC=dynamic` / `ON_BAT=dynamic` during `tlp.service` startup (and `eco-power.service` runs `After=tlp.service asusd.service`), `eco-power.sh`'s check-before-write guard becomes a zero-write no-op on any policy that `tlp` has already converged to `dynamic`, eliminating the 48 extra sysfs write lock acquisitions at boot.
