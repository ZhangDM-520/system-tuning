# Action — 2026-11-09: digest cachyos-settings and adopt its settings into state/owned

## Objective
`cachyos-settings 1:1.4.1` hard-depends on `ananicy-cpp` and `cachyos-ananicy-rules`; the local
`aranicy 0.2.3-1` declares `Conflicts With : ananicy-cpp`, so every `-Syu` fails on the dependency
chain. The owner decided to drop the package. This action digests everything the package owns and
carries the useful, live settings into the repo so nothing regresses at removal.

## What the package actually owned on this host (`pacman -Ql`, 1.4.1)
~20 config files under `/usr/lib` plus `/etc/security/limits.d`, one zram-generator config, and
ten helper binaries. Upstream `CachyOS/CachyOS-Settings` @ `3691abc` (2026-11-08) was read for the
current set (it has since moved `user/session.slice` drop-ins and added an xswap systemd
generator — neither applies here).

## Adopted (24 files, all `state/owned/…`, deployed by `./eco apply`)
- `etc/sysctl.d/10-eco-kernel-base.conf` — vfs_cache_pressure, dirty_bytes, dirty_background_bytes,
  page-cluster, nmi_watchdog, unprivileged_userns_clone, printk, kptr_restrict,
  netdev_max_backlog, file-max. 10- so every later owned sysctl file still wins.
- `etc/tmpfiles.d/50-eco-thp.conf`, `50-eco-thp-shrinker.conf`, `50-eco-coredump.conf`.
- `etc/modprobe.d/99-eco-watchdog-blacklist.conf`, `etc/modules-load.d/ntsync.conf`.
- `etc/systemd/journald.conf.d/99-eco-size.conf`.
- `etc/systemd/{system,user}.conf.d/10-eco-{timeout,limits}.conf`.
- `etc/systemd/system/{system.slice,user-.slice}.d/` OOM defaults +
  `session.slice.d/10-eco-oomd-omit.conf` + `user@.service.d/10-eco-delegate.conf` +
  `rtkit-daemon.service.d/10-eco-loglevel.conf`.
- `etc/security/limits.d/20-audio.conf`, `etc/NetworkManager/conf.d/99-eco-dns.conf`,
  `etc/systemd/timesyncd.conf.d/10-eco-ntp.conf`.
- `etc/udev/rules.d/70-eco-audio-pm.rules` + `usr/local/lib/audio-pm-ctl`.
- `usr/local/lib/iw-set-regdomain` + `etc/systemd/system/eco-wireless-regdom.{service,path}`
  (ISC headers preserved; helper moved under `/usr/local`; service also `WantedBy` at boot).
- `etc/systemd/zram-generator.conf` — local `/etc` file that the repo never owned (persistence gap).

## Refused (repo ruling wins)
- `vm.swappiness=100` → `95-zram-swappiness.conf` pins 150.
- `kernel.sysrq=1` → `97-sysrq.conf` pins the 190 capture+rescue mask.

## Not applicable here (verified, not assumed)
xswap generator (`/sys/kernel/mm/xswap` absent), `CONFIG_ZSWAP` unset (so `30-zram.rules` is
inert), no SATA disk/HDD (sata + hdparm rules), Strix Point iGPU and no NVIDIA (amdgpu/nvidia
modprobe), `pci-latency` disabled+inactive, hpet/cpu_dma_latency permission grants (no
latency-critical audio path), X11 touchpad + glib login-screen schema (Wayland).

## Two bugs surfaced by the adoption
1. **journald effective cap was 50M, not 256M.** `/etc/systemd/journald.conf` carried the managed
   `SystemMaxUse=256M` (and `eco report` was green) while
   `/usr/lib/systemd/journald.conf.d/00-journal-size.conf` (cachyos) capped it at 50M: drop-ins
   are read after the main file. Fixed by owning `99-eco-size.conf`; `systemd-analyze cat-config`
   now ends at 256M; journald restarted.
2. **Multi-word sysctl values broke the runtime re-assert.** `runtime_collect` matched
   `([^[:space:]#]+)`, so `kernel.printk = 3 3 3 3` compared `3 3 3 3` against `3`, re-asserted
   every run and ended in "drift persisted" (exit 1). Fixed with an end-of-line capture plus a
   whitespace normalizer (`norm_sysctl_value`, because `sysctl -n` renders tabs while the file has
   spaces). Falsified: reverting the parser turned 8 gate assertions red. New case29 guards it;
   the sysctl stub now resolves multi-value keys the same way.

## Verification
- `./tests/run` → 119 run / 119 passed (was 117; +case29 ×2 assertions).
- `./eco apply` → 24 planned / 24 applied, exit 0; second dry-run `PLAN 0`.
- `./eco report` → `ok=11 accepted=0 warn=1 drift=0 skipped=2 exit=0`; WIFI now prints
  `regdomain TW`, IO prints the bytes caps.
- Live readbacks: `kernel.printk=3 3 3 3`, `vm.dirty_bytes=268435456`,
  `vm.dirty_background_bytes=67108864`, `nmi_watchdog=0`, `vfs_cache_pressure=50`,
  `page-cluster=0`, THP `defer+madvise` / `max_ptes_none=409`, `ManagedOOMPreference=omit` on
  session.slice, `Delegate=yes` on user@1000, `LogLevelMax=6` on rtkit (inert — rtkit disabled),
  `iw reg get` → `country TW`.
- `udevadm verify` on the new rule: 1 checked, 0 failed. `systemd-analyze verify` on the new
  units: only the pre-existing cups.socket legacy-path warning.

## Follow-ups for the owner
- `pacman -R cachyos-settings` (not `-Rns`): keep `wireless-regdb` (regulatory data) and
  `zram-generator` (owns `zram0`); `pacman -D --asexplicit wireless-regdb zram-generator`.
- Lost tools (owner's call): `topmem`, `kerver`, `pci-latency`, `game-performance`, `zink-run`,
  `dlss-swapper`, `paste-cachyos`, `sbctl-batch-sign`, `cachyos-bugreport.sh`, `eac-status`.
- `eco-wireless-regdom.{service,path}` were enabled by hand; `eco apply` writes the files but does
  not enable units (same as the other owned units).

## Post-removal verification (2026-11-09 04:42, live)

The owner removed the package while this action was in progress
(`pacman --remove -- cachyos-settings`, no `-Rns`; pacman.log 04:42:43). That turned the adoption
into a live test rather than a plan. Results:

- Every vendor `/usr/lib` file is gone (`70-cachyos-settings.conf`, `journald.conf.d/`,
  `60-ioschedulers.rules`, `modprobe.d/blacklist.conf`, `zram-generator.conf`) and every value
  still holds from `/etc`: `vfs_cache_pressure=50`, `nmi_watchdog=0`, `page-cluster=0`,
  `kptr_restrict=2`, `netdev_max_backlog=4096`, `file-max=2097152`, `printk=3 3 3 3`.
- `systemd-analyze cat-config systemd/journald.conf` ends at `SystemMaxUse=256M` (the vendor 50M
  drop-in is gone; the owned 99- file carries it either way).
- NVMe still `[none]` (our `61-` rule outlived the vendor `60-`), zram still 89.9G zstd with the
  writeback device from the now-owned `/etc/systemd/zram-generator.conf`.
- `iw reg get` → `country TW` from `eco-wireless-regdom.service`; `eco report` WIFI prints it.
- The removal deleted `/etc/security/limits.d/20-audio.conf` (a package-owned file we had
  modified); `./eco apply` restored it from `state/owned` on the next run — the restore path works
  exactly as designed.
- Cleanup done: one dangling unit symlink
  (`/etc/systemd/system/multi-user.target.wants/cachyos-iw-set-regdomain.path`) removed +
  `daemon-reload`; no failed units, no dangling links remain.
- Orphaned by the removal and still load-bearing: `zram-generator` (owns `zram0`) and
  `wireless-regdb` (regulatory data; `Required By: None`). Both need
  `pacman -D --asexplicit zram-generator wireless-regdb` — NOT run here because the owner had a
  `paru -Syu` transaction holding `db.lck`.
