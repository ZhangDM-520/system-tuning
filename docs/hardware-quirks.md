# Hardware quirks

When to read: before diagnosing any odd readback or any "it worked yesterday" power behavior.
This machine lies in specific, documented ways. Read this before concluding a setting failed.

## stapm

**The STAPM LIMIT readback is firmware-managed and sits below the written 31 W (17-20 W class),
and it drifts between consecutive reads.** A foreground `ryzenadj --stapm-limit=31000` prints
`Successfully set` and the readback stays floored: same for 28000. Value-independent: this is a
dynamic derate (STT skin model or EC-latched battery floor), not a rejected number. The
`STAPM VALUE` row pinning at the limit while under load is the clamp being real; at idle VALUE is
far below the limit and nothing is being throttled. Owner ruling (Q16): ACCEPTED as firmware
preference, the write stays 31000, no diagnosis. Never "fix" this with re-write storms.

Related readback artifacts:
- `StapmTimeConst` sometimes reads 0.000 despite `--stapm-time=128` being applied and holding on
  other boots. Artifact class, not drift.
- `CCLK Boost SETPOINT` fluctuates with load (that is what `--power-saving` moves).
- ryzenadj errors are structurally invisible in the convergence path (hw-tune.fish exits 0
  unconditionally and its output is discarded): the journal line "hw-tune.fish applied" certifies
  nothing about SMU acceptance. Verify claims with `sudo ryzenadj --info`, never with the log.

## asusd

- `platform_profile` choices on this firmware are only `balanced` and `performance`. The Quiet
  profile does not exist anymore, so any config mapping Quiet fails with EOPNOTSUPP (fixed:
  mapped to Balanced, decisions#asusd-profile).
- **Writing `platform_profile` resets the SMU limits and EPP through the EC**, even when writing
  the same value. asusd writes it on every AC/battery event. This is why eco-power re-converges
  after power events and why the 600s backstop exists.
- **asusd rewrites its own `asusd.ron` on restart** (map keys reordered, values preserved).
  Compare by value, never by whole-file hash.
- asusd reports "AC profile Balanced" and "FanCurves: Not supported" / "Backlight: No backlights
  found" errors at startup: benign on this model.

## ec

**EC and power source.** The EC has misread AC state before (an AC-off window presented as AC-on; fixed by one plug cycle
after resume). Treat sysfs `AC0/online` as advisory during weirdness and re-plug before
diagnosing anything power-source-dependent. Firmware derates (the stapm floor above) can latch
across a replug and clear only at some charge threshold or a full power-off (EC discharge).

## SMU (Strix Point, BIOS IF 21)

- Silently rejected setters (tool reports success, firmware ignores): `--set-cogfx`, all PSI
  current setters, `--prochot-deassertion-ramp`.
- Family-gated in ryzenadj (message never sent): all min/max clock-domain tunables, OC setters,
  `apu-skin-temp`.
- `--power-saving` works and is visible via the CCLK boost setpoint.
- `--dump-table` returns undecoded offsets only.
- Curve Optimizer packing: 16-bit two's complement; per-core payload `core_idx * 2^20 + offset`.
  hw-tune.fish is the single writer; never write CO values from anywhere else.

## GPU / display

The amdgpu device is **card1**, not card0 (`/sys/class/drm/card1/...`): scripts targeting card0
fail with ENOENT and look "silently ignored". `power_dpm_state` is cosmetic on this SMU APU and
root-only; the working lever is `power_dpm_force_performance_level=auto` (TLP sets it). A
`amdgpu_dm_freesync` WARNING at boot/resume is cosmetic and fires on every resume, not just boot.

## Input / I2C

The I2C-C bus (`AMDI0010:02`, i2c-2) top-IRQ identity is the touchpad: `i2c-ASUP1207:00`
(PixArt 093A:3012) via i2c_hid_acpi and hid-multitouch. It is interrupt-driven and idles at 0/s;
historical hundreds-per-second counts are touch activity, not a poller. The paired GPIO IRQ
(pinctrl_amd / ASUP1207) is the same physical source. No fingerprint reader exists on this unit.
The AT keyboard is i8042 (PS/2, not USB), which is why all XHC wake sources can stay disarmed.

## Capacity and misc

- `cpu_capacity` values lie on this hybrid; use `acpi_cppc/highest_perf` for core ranking.
- Battery charge cap is 80% (asusd `charge_control_end_threshold`), charge stops there
  ("Not charging" at 80% is normal, not a fault).
- The SD reader (GL9755, sdhci-pci) never runtime-suspends on its own; unbinding it while empty is
  safe (standard surprise-removal teardown) and is runtime-only (see rollback#sd).
- NVMe has the `simple_suspend` platform quirk: affects system-sleep path only, not APST.
