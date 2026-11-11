# Action summary — 2026-11-01 — kernel-kconfig adaptation to eco tuning

## What the new kernel changes (evidence)

Kernel recipe `~/Projects/linux-cachyos` commit `806fcac` (2026-10-31) flipped PKGBUILD defaults
for the 7.3.1 KISS build. Against the running `7.3.0-4-KISS-cachyos-lto` (`/proc/config.gz`
probe; saved `config-7.3.1-1-KISS-cachyos-lto` is a pre-flip snapshot — only the version banner
differs), exactly three parameters change:

| Parameter | Running kernel | 7.3.1 KISS default | Eco impact |
|---|---|---|---|
| `X86_AMD_PSTATE_DEFAULT_MODE` | 3 (active/EPP) | 4 (guided) | EPP attrs never register (`epp_visibility()` gates on `AMD_PSTATE_ACTIVE`, `drivers/cpufreq/amd-pstate.c`) — profile path degrades to platform_profile; dynamic-EPP wedge trigger structurally gone |
| `PCIEASPM_DEFAULT*` | `DEFAULT` (BIOS) | `POWER_SUPERSAVE` | boot default now matches the `## pcie` ruling; covers hotplug; TLP's boot write redundant (kept for fallback boots) |
| `CPU_MITIGATIONS` | y | off (`MITIGATION_*` menu stripped) | perf/security tradeoff (kernel repo's knob); kernel change = new baseline |

Unchanged/already live: `_zswap=off`, `_zram_comp=zstd` (live `zram0` already `[zstd]`),
`io_uring=on`, `kstack_erase=off`, HZ 600, PREEMPT_LAZY, `SCHED_CLASS_EXT=y`.

## What changed in eco

- `lib/readers.sh` `check_epp`: mode-aware — a mode-labelled (guided/passive) EPP absence is
  health (OK row), an unlabelled absence stays DRIFT. Active-mode behavior byte-stable.
- `lib/readers.sh` `check_tlp`: live ASPM policy assert added (writer-agnostic: guards both TLP's
  write and the future kernel default).
- `tests/fixtures/sys/module/pcie_aspm/parameters/policy`: mirrored from live (fixture rule).
- `tests/run` case22 (4 assertions): guided-absence OK, unlabelled-absence DRIFT, ASPM-policy
  DRIFT catch. Gate: 97/97.
- `docs/findings.md`: `## epp` mode-scoping + wedge structural retirement; `## cpu` kernel-mode
  scoping (guided = bounds-only; `mitigations=off`; new-baseline rule); `## pcie` kernel-default
  note + TLP-line retirement trigger; `## recovery` open item = `_capture_chain` proposal.
- `AGENTS.md`: new facts row (EPP active-mode-only trap) + host snapshot kernel line re-probed
  (`7.3.0-4-KISS-cachyos-lto`, boot 2026-11-01 08:17).

## Dropped / deferred / augmented (the ask)

- **Dropped (deferred trigger):** TLP `PCIE_ASPM_*` lines — redundant on the supersave-default
  kernel but kept until old `PCIEASPM_DEFAULT` boot entries retire (fallback boot would silently
  lose supersave). Trigger + mechanism recorded in `## pcie`.
- **Augmented:** TLP check now asserts the live policy writer-agnostically.
- **Nothing to drop** for zram/swappiness (zstd already live), EPP writers (already retired),
  ceil watch (still the bound enforcer under guided), asusd mute, recovery sysctl set.

## 2026-11-01 pm — full runtime-parameter audit (post-kernel-fix, pre-reboot)

Scope: every active runtime parameter writer in `state/` + scripts + managed records vs the
rebuild kernel (guided / supersave-default / mitigations-off).

**Verified live, all at intent (no dead keys on 7.3.1):** 6 sysctl keys (swappiness 150, sysrq
190, hung_task 120/1, dirty 6000/6000); modprobe params (`acp_power_gating=1`, btusb `Y`); NVMe
queue `[none]`/1023/256/2000; cpuidle `teo`; sound `power_save=1`/controller `Y`; zram `[zstd]`;
wifi/bt/wake-trim/USB-autosuspend passes; managed records (asusd mute, ppd-conflict, journald,
niri, trash-purge); hw-tune SMU chain. Vendor companions (`70-cachyos-settings.conf`) conflict
only on swappiness (known, pinned). `mitigations=off` has no runtime surface in eco.

**Two defects found:**

1. **CRITICAL (recovery domain): pstore forensics disarmed.** `CONFIG_EFI_VARS_PSTORE_DEFAULT_DISABLE=y`
   arms nothing by default; the cmdline override `efi_pstore.pstore_disable=0` is gone from both
   limine files (regeneration burn — `## recovery` dual-file rule). `pstore_disable=Y`,
   `/sys/fs/pstore` empty → a hung_task panic loses its stacks. Recorded `## suspend-resume`
   capture-chain correction + AGENTS row; addendum for the kernel recipe agent at
   `/tmp/pstore-arming-gap-20261101.md`. **Ruled 2026-11-01: kernel config flip** (durable);
   pstore stays disarmed until that kernel boots.
2. **HIGH: `scaling_governor` two-writer race (TLP vs PPD).** TLP's
   `CPU_SCALING_GOVERNOR_*=powersave` re-applies on every `power_supply` change (`85-tlp.rules`
   → `tlp auto`; `set_cpu_scaling_governor` lacks the `nop_ppd_active` deferral that EPP has);
   PPD writes `performance` per profile. **Ruled 2026-11-01: dropped** the three lines from
   `state/owned/etc/tlp.d/01-eco.conf` (converged live, apply=1) — PPD is the sole
   `scaling_governor` writer; `## cpu`/`## pcie` stale claims corrected.

**Boot checklist for the rebuild kernel:** `zcat /proc/config.gz` trio (MODE=4 /
POWER_SUPERSAVE / mitigations unset); `amd_pstate/status` (TLP will pin `active` unless the
OPMODE lines change — known aside); if guided ever takes effect: PPD platform_profile path,
`scaling_min_freq`=605264 (driver default — no writer), governor+bounds behavior (guided +
`powersave` = unverified pairing), ceilings hold; ASPM `[powersupersave]`; no stray CEIL DRIFT
outside the boot apply.

**Coverage gaps (written but not check-asserted; registry is frozen — documented only):** sysrq
mask, hung_task pair, swappiness, NVMe quartet, teo, sound power_save, min-freq floor.

## 2026-11-01 23:04 — settled-kernel verification (all checklist items green)

Rebuilt kernel booted (same version string `7.3.1-1-KISS-cachyos-lto` — identify by config, not
string). Verified: `X86_AMD_PSTATE_DEFAULT_MODE=4`, `PCIEASPM_POWER_SUPERSAVE=y`,
`# CONFIG_CPU_MITIGATIONS is not set` (zero `MITIGATION_*` symbols);
`EFI_VARS_PSTORE_DEFAULT_DISABLE is not set` → `pstore_disable=N`, `Registered efi_pstore as
persistent store backend` (dmesg 1.62 s) and the four stale 2026-09 panic records visible again
in `/sys/fs/pstore`. Runtime mode = `active` (TLP OPMODE pin, kept by ruling — guided dormant);
EPP attrs present ×24 (PPD-owned); `scaling_governor=performance` (PPD sole writer — the dropped
TLP lines hold); min floor 605264; ASPM `[powersupersave]`; ceil watch clean (24 catches all at
23:05:33 = boot apply only); `./eco report` drift=0 (SD WARN = known runtime-unbind item).

## Open items for the owner

- ~~`_capture_chain=yes` for the 7.3.1 build~~ — **ruled OFF 2026-11-01** (recovery-domain trade
  declined; recorded in `## recovery`). Kernel PKGBUILD untouched.
- ~~First guided boot: verify PPD's profile path~~ — **moot as shipped 2026-11-01**: the installed
  7.3.1-1 carries MODE=3 (build drift — `/tmp/kconfig-build-drift-20261101.md` handed to the
  kernel recipe agent) and TLP pins runtime mode `active` (`CPU_DRIVER_OPMODE_*` in
  `state/owned/etc/tlp.d/01-eco.conf`). Guided remains conditional.
- ~~TLP `CPU_DRIVER_OPMODE_*` / `CPU_SCALING_GOVERNOR_*`~~ — OPMODE kept (validated EPP world;
  2026-11-01 default), governor lines **dropped by ruling** (converged live).
- ~~pstore re-arm~~ — **ruled: kernel config flip** (`EFI_VARS_PSTORE_DEFAULT_DISABLE=n`,
  `/tmp/pstore-arming-gap-20261101.md` handed to the kernel agent). Verify at the next kernel:
  `pstore_disable` must read `N`.
- ~~Commit disposition~~ — **ruled commit+push 2026-11-01** (all of today's work, see git log).
