# Unified findings — host system tuning (merged truth)

**Purpose.** This is the canonical, merged truth for tuning this host (ASUS Zenbook S 16 UM5606WA,
Ryzen AI 9 HX 370, CachyOS, XFS root on WD SN560), reconciling three bodies of knowledge that are
being merged into `system-tuning`: the eco-power repo (**EP** = `~/Projects/eco-power`), the System
Tuning Benchmarks repo (**STB** = `~/Projects/System-Tuning-Benchmarks`), and the host doc set
(`~/docs/FS-MAINTENANCE.md`, `~/docs/XFS-TUNING.md`, `~/docs/NOTE.md`, `~/.cache/bench-scratch/ab2-report-20260928.md`).
Where they overlap, this document states one current truth; where they disagree, §3 says which side
won and why. Every non-obvious claim carries an evidence handle (`path:line`, verified against the
sources). Core doctrine, unchanged across all three bodies: **efficiency is work per joule, not watts;
race to sleep; reduce wakeups, never capability; no power caps or forced throttling; stability and
tty-login recovery outrank everything** (`EP docs/doctrine.md:5-33`).

---

## 1. Truth table, by tuning area

### (a) Writeback & background wakeups

**Current truth.** Longer writeback intervals are a wakeup reduction, not a cap (fsync and journal
are unaffected): `vm.dirty_writeback_centisecs=6000`, `vm.dirty_expire_centisecs=6000` (60 s / 60 s).
`fs.xfs.xfssyncd_centisecs=10000` (100 s; kernel default is 30 s = 3000) is live and lowering it is
measured-worse; raising it to 30000 (300 s) is untested. `fs.xfs.speculative_prealloc_lifetime=300`
(300 s) is live; 1800 s is a candidate that has never produced a measurable mechanism. The runtime
values are single-writer: TLP must not manage them (`MAX_LOST_WORK_SECS_ON_AC/BAT=0`), because TLP's
`set_dirty_parms()` rewrote dirty_* and the XFS age knobs to 1500/1500-class values on every power
event (root cause found 2026-09-25).

**Applied state.** Live now: 6000/6000 (`state/owned/etc/sysctl.d/99-eco-writeback.conf:1-2`),
xfssyncd 10000 + speculative_prealloc_lifetime 300 (verified post-AB2 readback,
`ab2-report-20260928.md:200-202`), TLP neutralized (`state/owned/etc/tlp.d/01-eco.conf:59-64`),
eco converger belt re-asserts 6000/6000 on every trigger (`state/owned/usr/local/sbin/eco-power.sh:71-72`).

**Evidence handles.** `EP docs/fleet-findings.md:55-73` (TLP resetter root cause + fix),
`EP docs/fleet-findings.md:13`, `EP README.md:75` (IO check), `STB studies/03-filesystem-latency/README.md:83`
(xfssyncd 10000 → 1000 refused: 8.35 s vs 8.16 s, log forces 135 vs 191, more wakeups),
`STB METHODOLOGY.md:140-141` (snapshot era: writeback/expire 1500/3000), `~/docs/XFS-TUNING.md:22-24`,
`~/docs/XFS-TUNING.md:50` (30 s → 100 s raise history; 300 s+ untested), `ab2-report-20260928.md:12,127-134`
(timer-policy pair 30000/1800: n=2/arm, minimum achievable two-sided MW p = 0.333 → INCONCLUSIVE-lean).

**Status.** applied (6000/6000, xfssyncd 10000, prelife 300); refuted (lowering xfssyncd);
open question (300 s xfssyncd, prelife 1800 s — idle-drain campaign needed).

### (b) NVMe power (WD SN560)

**Current truth.** APST stays armed two-stage: PS3 after 100 ms idle, PS4 after 2 s; PS5 is gated out
by `nvme_core.default_ps_max_latency_us=100000`. PS5 unlock is rejected: root-disk exit-latency stall
risk, exit latency unmeasured. The link runs Gen3 x4 (downgraded from the Gen4 cap) and stays there —
forcing Gen4 costs watts. `nvme set-feature -f 0x0c` is never used: `nvme-cli` writes a zeroed 256-byte
buffer and wipes the entire APST table; `-v 1` cannot restore it (recovery = controller reset,
`echo 1 > /sys/class/nvme/nvme0/reset_controller`, then read the table back). The drive carries the
`simple_suspend` platform quirk — it affects the system-sleep path only, not APST.

**Applied state.** Two-stage APST live, PS5 gated, Gen3 x4 kept (settled), udev-persisted IO choices
below; the 0x0c rule is standing (never touch).

**Evidence handles.** `EP docs/fleet-findings.md:46-53` (storage: APST two-stage, PS5 gate,
scheduler none, XFS/lazytime, weekly fstrim, zram swap), `EP docs/fleet-findings.md:40-41` (Gen3 x4
keep), `EP docs/fleet-findings.md:139` (rejection table: NVMe PS5 unlock), `EP docs/hardware-quirks.md:77`
(`simple_suspend`), `STB studies/02-boot-and-power/README.md:96` (PS3 = 0.015 W / 2.5 ms exit,
PS4 = 0.005 W / 6 ms exit vs 0.3 W in PS0–2; +26 µs/request transition, ~285 mW idle power bought),
`STB studies/02-boot-and-power/README.md:170-198` (§8 hazard: 0x0c wipes the APST table).

**Status.** applied (two-stage APST, Gen3 x4); rejected (PS5 unlock, APST-gap tuning);
standing hazard rule (never `set-feature 0x0c`).

### (c) IO stack

**Current truth.** NVMe scheduler `none` (race-to-idle: bursts drain immediately so the APST timer
can start), `nr_requests=1023`, `read_ahead_kb=256`, `wbt_lat_usec=2000` — all keep. `max_sectors_kb=128`
is the drive's MDTS limit: I/Os split at 128 KiB, so `read_ahead_kb=256` is not a request size and
prealloc sizes are about extents, not I/O size. Refuted by measurement: raising read-ahead (256 → 2048
identical on a 1M-file cold metadata walk — XFS metadata reads use fixed buffers), lowering
`nr_requests` (1023 → 256: 3.90 s vs 3.75 s, queue latency 2404 µs vs 1978 µs — worse), and disabling
WBT (`wbt_lat_usec=0`: browser launch under write load 30% slower, p = 0.009, queue latency 12–24×
worse — WBT is load-bearing; 1000/10000 indistinguishable from 2000).

**Applied state.** `none`/1023/256 live and udev-persisted; WBT 2000 untouched; swappiness stays 150
(udev-enforced), ≥200 is a hard anti-goal (150 → 200 reproduced catastrophic: wall 11.25 → 13.55 s,
mean power 10.07 → 12.07 W, p = 0.004).

**Evidence handles.** `EP docs/fleet-findings.md:48-49`, `STB TEST-BED.md:119-121`,
`STB studies/03-filesystem-latency/README.md:81-82` (read_ahead, nr_requests refusals),
`STB studies/02-boot-and-power/README.md:91,99-102` (WBT 0 refusal + warning),
`STB studies/02-boot-and-power/README.md:90` (swappiness 200), `STB studies/02-boot-and-power/README.md:112`
(`max_sectors_kb == max_hw_sectors_kb` 128 KB MDTS), `~/docs/XFS-TUNING.md:18-19`,
`~/docs/NOTE.md:3910-3911` (bios split at 128 KiB).

**Status.** applied (`none`, 1023, 256, WBT 2000, swappiness 150); refuted (read-ahead ↑,
nr_requests ↓, WBT off, swappiness ≥200).

### (d) Discard / fstrim policy

**Current truth.** Weekly `fstrim.timer` (systemd stock, enabled and active) is the design; the
`discard` mount option is rejected (kernel docs: performance impact "quite severe"; periodic batch
TRIM beats per-operation discard latency on NVMe; continuous `discard=async` would keep the device
busy and fight APST). A one-off `sudo fstrim -av` after very large deletions is acceptable; post-dedupe
fstrim is not automated (weekly timer suffices). Free space can drift down after a dedupe sweep — never
attribute freed space to dedupe without `COUNT(DISTINCT poff)` per digest.

**Applied state.** `fstrim.timer` weekly active; no `discard` anywhere in the root mount line.

**Evidence handles.** `~/docs/FS-MAINTENANCE.md:10-11,33-40,73`, `EP docs/fleet-findings.md:49-50`,
`STB studies/02-boot-and-power/README.md:108`, `~/docs/XFS-TUNING.md:61-62` (discard mount opt
root-unsafe/forbidden), `~/docs/XFS-TUNING.md:38` (hard anti-goal list).

**Status.** applied (weekly fstrim); rejected (mount `discard`).

### (e) XFS filesystem

**Current truth.**
- Root is XFS V5 with reflink=1; live mount line is
  `rw,relatime,lazytime,inode64,logbufs=8,logbsize=256k,noquota`. **fstab XFS options are dead** —
  root mounts in the initramfs; effective `logbsize=256k` comes from `rootflags=` on the kernel
  command line. XFS log geometry is chosen at first mount; a remount "succeeds" and changes nothing
  (proved on a loopback image: forced log commits 19034 → ~1561 for the same 15× metadata storm at
  256k — mechanism confirmed, end-to-end speed benefit still unproven). `inode64` is default since
  v3.7 (the fstab entry is a restatement); `lazytime` stands (zero atime wakeups; `noatime` rejected
  as redundant).
- **`allocsize=1m` is falsified on this host's big-sequential workload class and was rolled back.**
  AB3: root cross-pass n=5/arm wall −1.4% (inside the 8.1% control spread), pkg J −6.8% (p=0.117,
  n.s., cross-pass confounded); loopback within-pass A/B (mount-time arms, readback-proven, n=4/arm)
  exactly zero (wall 0.83 s vs 0.83 s, 4.43 J vs 4.43 J, 3 extents both arms). The mechanism is
  contradicted: sync transactions +189% and log writes +76% with the setting, identical write ios
  (32,819 vs 32,861) and request sizes. Both limine backups restored (rollback effective next boot).
- **`filestreams`: the mount option is inert on kernel 7.3-rc4** (`mount -o remount,filestreams /`
  returns rc=0, never appears in `/proc/mounts`, zero `xfs_filestream_*` tracepoints for unflagged
  dirs; `nofilestreams` is an unknown parameter). The measurable unit is the per-directory inode
  flag `xfs_io chattr +S` (`+f` is **no-defrag**). The A/B (mkstorm 15 × 5/arm) was a Pareto trade,
  not a win: wall −8.9% (p=0.009), NVMe read ios −71.7%, write ios −47.3%, device busy −28.5%,
  log FORCE −23.6%, log no-space −41.4%, pkg J −2.1% (p=0.347, n.s.) — but PSI io-some +112.9%,
  io-full +114.3%, cpu-some +91.1%, mean queue latency +86.9% (all p=0.009, beyond control spread).
  It fails the "nothing significantly worse" rule; the owner override nonetheless applied
  `chattr -D +S` to `~/Projects` + `~/Workspace` (verified `[S]`, new dirs inherit), accepting the
  ~2× stall trade deliberately.
- **Remount-inert pitfall (generalized):** on this kernel `mount -o remount,<xfs-opt>` silently no-ops
  for at least `filestreams` and `allocsize`; the working mechanism is boot-time `rootflags=` (AB3
  proved it: `allocsize=1024k` read back in 6/6 rows). Any future XFS mount-option A/B must prove arm
  identity via readback before burning runs, or use a loopback image with mount-time arms.
- **Hard rules:** reflink sharing is load-bearing (65 GiB recovered by duperemove, verified by
  physical offsets) — `xfs_fsr`/defrag is never automated (it rewrites extents and un-does dedupe);
  `xfs_repair` is offline/rescue-media only; `xfs_scrub` (monthly, online) is the scheduled check.
  duperemove pitfalls: silently scans 0 files as non-root and exits 0; identical-file groups are
  quadratic-ish (87k-member group pegged a core >55 min — such trees excluded); `dedupe_seq` resume
  semantics (files below the config marker are permanently skipped; seq == max are never processed;
  setting all seq=0 hides files *below* the marker); `--read-hashes` is a different, non-SQLite hash
  format and does nothing on a `--hashfile` DB.

**Applied state.** lazytime/inode64/logbufs=8/logbsize=256k/noquota live via `rootflags=logbsize=256k`
(AB3 rollback removes `allocsize=1m` at next boot); `chattr +S` on `~/Projects` + `~/Workspace`;
daily duperemove.timer, weekly fstrim.timer, monthly xfs-scrub.timer, smartd active;
`ikeep`/`attr2`/`noikeep`/`noattr2` unused (deprecated no-ops since 6.18, deprecation postponed to
2030; the admin-guide calls them "removed" — either way, do not use); `ikeepnoquota`/`sendbuf` do not
exist in Linux XFS and fail the mount.

**Evidence handles.** `~/docs/XFS-TUNING.md:14-24` (baseline, dead fstab, stack),
`~/docs/XFS-TUNING.md:57-72` (skip/avoid list), `~/docs/XFS-TUNING.md:76-77` (ikeep/attr2 conflict),
`~/docs/XFS-TUNING.md:104-108` (+S letter, mount-opt inert), `~/docs/XFS-TUNING.md:122-139`
(filestreams REJECT with numbers + ftrace proof 118800 lookups / 1200 picks vs 0/0),
`~/docs/XFS-TUNING.md:149-154` (limine persistence pitfall), `~/docs/XFS-TUNING.md:169-171`
(arm-identity lesson), `~/docs/XFS-TUNING.md:173-179` (owner override applied),
`~/docs/XFS-TUNING.md:181-187` (AB3 falsified → rolled back), `~/docs/NOTE.md:3983-3995` (override +
sudo-glob pitfall), `~/docs/NOTE.md:3997-4013` (AB3 numbers, `rootflags=` parsing works),
`STB studies/03-filesystem-latency/README.md:40-69` (first-mount-only log geometry; mechanism
19034 → ~1561; benefit NOT established), `STB TEST-BED.md:123-125`, `~/docs/FS-MAINTENANCE.md:16-31,49-56`
(duperemove pitfalls; xfs_fsr rule), `~/docs/NOTE.md:3773-3794` (dedupe_seq semantics source-read).

**Status.** applied (rootflags logbsize, `chattr +S` override, maintenance automation);
refuted (`allocsize=1m` for big-sequential writes); rejected (filestreams as a win — Pareto trade,
kept by owner override only); inert/never (mount-wide `filestreams` on 7.3-rc4, fstab XFS opts);
open question (`allocsize` for random/mixed writes; logbsize end-to-end benefit).

### (f) CPU / power policy

**Current truth.** amd-pstate-epp active mode, `scaling_governor=powersave` on every policy, EPP
`dynamic` on every policy (it follows platform profile and power source and currently resolves
performance-biased — race-to-sleep correct; `power`/`balance_power` makes firmware creep, which is
mechanism-opposite to the doctrine). Per-class ceilings are legitimate V/f sweet-spot trims, not caps:
Zen5 4.6 GHz, Zen5c 3.0 GHz; boost stays ON (the ceiling already clips it). Curve Optimizer is frozen
at CoreCycler-validated depth: `coall -7`, per-core `-24 -24 -21 -21 -9 -11 -8 -6` (never step deeper
opportunistically). Envelope flat 31/31/31 W, `stapm-time=128`, `slow-time=1`; the STAPM readback sits
at 17–20 W and is ACCEPTED firmware preference (never "fix" it with re-write storms). SMU
`--power-saving` asserted (CCLK boost setpoint 24 → ~5-7). Scheduler: **scx_lavd 1.1.3 with
`--powersave --per-cpu-dsq --enable-cpu-bw`** (core compaction); `scx_pandemonium` is not to be used
for power per EP (its README claims +23.9% J/op vs EEVDF on its workload); `scx_rusty` spreads load
(anti-compaction). Race-to-sleep doctrine governs all of it.

**Applied state.** TLP policy file: powersave governor + EPP `dynamic` + boost on
(`state/owned/etc/tlp.d/01-eco.conf:9-23`); eco-power.sh re-asserts EPP `dynamic` and the two ceilings
after every event (`eco-power.sh:22-25,38-44`) because asusd's platform_profile writes reset SMU
limits and EPP through the EC (`EP docs/hardware-quirks.md:29-30`); hw-tune.fish is the single SMU
writer (CO, 31/31/31, `--power-saving`) (`state/owned/home/zhangdm/.reserve/hw-tune.fish:13-54`).

**Evidence handles.** `EP docs/doctrine.md:7-20,43-50`, `EP docs/decisions.md:8-12` (EPP dynamic),
`EP docs/decisions.md:16-22` (ceilings), `EP docs/decisions.md:24-30` (CO), `EP docs/decisions.md:34-40`
(PPT + ACCEPTED readback), `EP docs/decisions.md:44-46` (SMU --power-saving),
`EP docs/fleet-findings.md:77-83` (scx_lavd; pandemonium/rusty rejected),
`EP docs/hardware-quirks.md:8-18` (STAPM readback artifacts), `EP README.md:66-68` (EPP/CEIL/CO checks).

**Status.** applied (governor/EPP/ceilings/CO/envelope/scx_lavd); accepted (STAPM readback floor);
rejected (pandemonium/rusty for power, boost off, caps, core parking, min/max clock setters).

### (g) Measurement doctrine

**Current truth.** Claims ship only through this protocol. (1) **Two gates, in order:** Gate 1 — the
effect must exceed the control's own min/max spread (an effect inside it is not a result, whatever
the p-value); Gate 2 — Mann-Whitney U, tie-corrected, two-sided, p < 0.05. Medians relative to the
control's median, never means. (2) **Adoption rule:** separates on ≥1 relevant metric, no metric
significantly worse, mechanism understood. (3) **RAPL is the energy oracle** — package
`energy_uj` deltas per slot (root-only); the battery is unusable here (AC with an 80% charge cap,
`power_now` reads 0). Report J per unit of work, not watts alone. (4) **Interleave arms inside every
repetition and rotate the starting arm**; cache state is part of the arm; within-pass comparisons
only (a display-blank regime shift moved both anchors +4.6% between passes — cross-pass deltas are
invalid). (5) **Discard the warm-up:** repetition 0 is excluded (first-slot contamination read
88–124 J idle against a ~29 J baseline); a discarded warm-up slot belongs at the front of any run.
(6) **n floor:** n ≥ 3 screening, **n ≥ 5 per arm for adoption or refutation** (n=2 verdicts are
capped at INCONCLUSIVE; MW-U cannot reach p<0.05 at n=2 vs 2 — minimum two-sided p = 0.333).
(7) **Arm-identity readback rule:** verify each arm twice, from two independent sources — read the
setting back **from where the consumer reads it** (`/proc/mounts`, sysfs, `/proc/cmdline`,
`NetworkManager --print-config`), never from the file that was edited; a row whose two sources
disagree is invalid; exit codes are never trusted. This is the single most transferable rule in the
whole merge — two XFS mount-option campaigns (filestreams, allocsize) were silently inert while
`remount` returned rc=0.

**Applied state.** Standing protocol for every future A/B on this host; `tools/fslat.py`'s per-row
tunable snapshot + `tools/verify-adopted-settings.sh` are the enforcement points.

**Evidence handles.** `STB METHODOLOGY.md:18-29` (interleave + rotate), `:33-40` (n floor),
`:42-68` (arm identity; dead-settings incidents), `:70-93` (two gates), `:95-105` (RAPL J/work),
`:107-116` (adoption rule), `:164-173` (first-slot contamination, rep-0 exclusion),
`:185-190` (cross-pass caveat), `ab2-report-20260928.md:12,127-129` (n=2 ceiling arithmetic),
`~/docs/XFS-TUNING.md:169-171` (prove arm identity before burning runs), `STB METHODOLOGY.md:153-162`
(~13 W display-blanking confound).

**Status.** standing/applied (protocol); the failures it caught are recorded as refuted claims.

### (h) Recovery-safety rules

**Current truth.**
1. **Bootloader/limine dual-file cmdline rule.** `/boot/limine.conf` is machine-generated by
   limine-entry-tool from `/etc/default/limine`; editing only limine.conf is silently reverted at the
   next kernel install. A cmdline change must edit BOTH (`rootflags=` appears 3× in limine.conf — one
   per kernel entry — and 1× in /etc/default/limine), with `cp -p` backups first (`*.bak-YYYYMMDD`);
   `/rewind` cannot stage /boot. AB3-era backups remain on disk for the allocsize rollback/re-apply.
2. **`sudo` + glob pitfall.** `sudo ls /boot/limine.conf*` fails: the glob expands as the unprivileged
   user before sudo runs (root-owned /boot). Use `sudo bash -c 'ls /boot/limine.conf*'` or explicit paths.
3. **Repo-first convergence / two-writer rule.** Live is never the place to make a change: TLP and the
   eco converger (600 s backstop + boot/resume/AC udev triggers) co-write runtime knobs; hand edits
   are reverted by design. Change `state/` → `./eco apply --dry-run` → `./eco apply` → commit with the
   check ID; capture deliberate live experiments with `./eco harvest` before the converger eats them.
   One place per knob (a `grep -rn <value> state/` returning two hits means the repo is wrong).
   Two daemons writing one sysfs attribute is a silent race (the asusd/PPD precedent).
4. **Backups before every write** (`cp -p <file> <file>.bak-YYYYMMDD`, never deleted); foreign files
   edited by exactly one anchored line. **TTY login is the recovery domain** — nothing may touch the
   bootloader, initramfs, or anything tty login depends on from inside the eco stack; a broken stack
   must still boot to a tty.

**Applied state.** eco-power convergence chain live (600 s backstop canary-verified, exit-code
contract 0/1/2/3); AB3 limine rollback staged (both backups restored); no system-tuning change ever
lands outside the repo-first flow.

**Evidence handles.** `~/docs/XFS-TUNING.md:149-154` (dual-file cmdline rule),
`~/docs/NOTE.md:3952-3955,3994-3995` (limine generation + sudo-glob pitfall),
`~/docs/NOTE.md:4008-4012` (re-apply recipe; rootflags parsing works),
`EP README.md:43-60` (repo first, one place per knob, backups, tty domain),
`EP README.md:24-29` (exit codes), `EP docs/fleet-findings.md:55-73` (two-writer TLP incident),
`STB README.md:214-216` (two-writer race lesson), `EP docs/rollback.md:54-61` (universal backup mechanism),
`EP docs/doctrine.md:32-33` (recovery domain sacred).

**Status.** standing/applied (all four rules).

---

## 2. Resolved contradictions

The three bodies disagree in specific places. Resolution rule: **the newer, better-evidenced side wins;
the superseded claim stays recorded with its scope.** EP is the source of truth for live state and
settled decisions; STB is time-stamped evidence scoped to its measurement kernel
(`7.2.5-1-cachyos-rt-bore-lto`, `STB TEST-BED.md:57-59`) — the host has since moved to
`7.3.0-rc4-1-cachyos-cachyos-lto` (`~/docs/XFS-TUNING.md:10`), and a re-run is a new baseline, not a
reproduction (`STB docs/NOTE.md:114-121`, `STB docs/MEMORY.md:31-37`).

| # | Contradiction | Claims | Resolution & why | Handles |
|---|---|---|---|---|
| 1 | EPP value | Benchmark era: `balance_power` uniform (TEST-BED) / `balance_performance` verified optimal (study 02) vs current `dynamic` | **Resolved → `dynamic` (EP wins).** Newer, owner-settled; `dynamic` follows platform profile + power source and resolves performance-biased = race-to-sleep correct; `power`/`balance_power` is mechanism-opposite. Reopen only with measured J/op evidence. | `STB TEST-BED.md:97`, `STB studies/02-boot-and-power/README.md:111,124`, `EP docs/decisions.md:8-12`, `state/owned/etc/tlp.d/01-eco.conf:13-15` |
| 2 | WiFi power-save | Study 02 adopted PS **off** (idle RTT 24.8 → 15.4 ms, no measurable energy cost) vs EP settled **ON** (all layers agree) | **Resolved → ON (EP wins).** Owner-settled for wakeup/radio-sleep doctrine; verified ON end-to-end on MT7925 (iw, NM profile+global, udev, TLP, mt76 deep-sleep). The latency cost is recorded as the known trade. Study 02's own §7 shows its era's NM files were self-contradictory (`d`-sorting file silently won). | `STB studies/02-boot-and-power/README.md:21,155-168`, `EP docs/fleet-findings.md:24-31`, `EP README.md:71`, `state/owned/etc/NetworkManager/conf.d/99-wifi-powersave.conf:1-2` |
| 3 | `xfssyncd` interval | 30 s kernel default vs 100 s live vs 300 s proposed | **Resolved for state → 100 s live.** 30 s was the TLP-clobbered default class (1500 cs writes on power events); 100 s is measured-keep (lowering to 10 s: no latency win, more wakeups). **300 s stays open** — AB2 n=2/arm INCONCLUSIVE-lean, mechanism never appeared (idle log FORCE ≈ 8/min in both arms). | `~/docs/XFS-TUNING.md:50`, `EP docs/fleet-findings.md:55-73`, `STB studies/03-filesystem-latency/README.md:83`, `ab2-report-20260928.md:12,138-144` |
| 4 | filestreams chattr letter | Docs originally said `+f` vs actual `+S` | **Resolved → `+S`.** On current xfsprogs `+f` is no-defrag; the filestreams inode flag is `+S`, verified from `xfs_io help chattr` (not from memory/blogs). | `~/docs/XFS-TUNING.md:104-106,127-128`, `~/docs/NOTE.md:3950-3951` |
| 5 | `ikeep`/`attr2` status | admin-guide: "removed v6.18" vs parser: deprecated no-op (warn), deprecation postponed to 2030 | **Resolved → deprecated no-op on this kernel.** Parser still accepts them; they do nothing (attr2 is immutable on V5 anyway). Practical answer identical either way: never use them. | `~/docs/XFS-TUNING.md:57-58,76-77`, `~/docs/NOTE.md:3905-3907` |
| 6 | fstab XFS options: live or dead? | FS-MAINTENANCE lists fstab opts (`lazytime,inode64,logbsize=256k,noquota`) as the storage facts vs XFS-TUNING/STB: fstab is dead | **Resolved → dead (initramfs/rootflags).** Root is mounted in the initramfs before fstab is consulted; effective `logbsize=256k` comes from `rootflags=` (the 32k vs 256k tunable-snapshot evidence proved the fstab entry had never been applied). FS-MAINTENANCE's list is the *intended/effective option set*, not the mechanism. | `~/docs/FS-MAINTENANCE.md:9-11`, `~/docs/XFS-TUNING.md:15-17`, `STB studies/03-filesystem-latency/README.md:40-53`, `STB TEST-BED.md:123-125,154-158` |
| 7 | remount vs boot-cmdline parsing | `mount -o remount,<xfs-opt>` claimed usable (XFS-TUNING §7 even called allocsize "remount-visible") vs AB2: remount silently inert on 7.3-rc4 (filestreams **and** allocsize) vs AB3: boot-time `rootflags=` works | **Resolved → remount inert; boot cmdline (or loopback mount-time arms) is the only valid path.** Both remount treatments were invisible in `/proc/mounts` while rc=0; AB3 read back `allocsize=1024k` in 6/6 rows from the cmdline. Arm identity must be proven before runs. | `~/docs/XFS-TUNING.md:142-143,169-171`, `ab2-report-20260928.md:27-40`, `~/docs/NOTE.md:3967-3970,4010-4012` |
| 8 | Adopted CPU scheduler | Study 01 adopted `scx_pandemonium` (Pareto: −11% idle / −35% I/O-burst / −30% reclaim power vs BORE, throughput tie) vs EP: live `scx_lavd --powersave`, pandemonium must NOT be used for power (+23.9% J/op vs EEVDF per its own README) | **Unresolved — both claims recorded.** Applied state resolved (EP wins: scx_lavd live, newer kernel + owner-settled); the *comparative* claim is open — pandemonium vs lavd was never A/B'd on the current kernel, and the two verdicts use different baselines (BORE vs EEVDF) and different workloads. | `STB studies/01-scheduler-selection/README.md:7-10,212-243`, `EP docs/fleet-findings.md:77-79`, `STB docs/NOTE.md:114-121` |
| 9 | asusd battery profile | TEST-BED/study 02 era: battery → Quiet vs EP: `platform_profile_on_battery: Balanced` | **Resolved → Balanced.** Firmware now exposes only `balanced`/`performance`; Quiet writes fail EOPNOTSUPP; mapping to Balanced restores designed behavior. | `STB TEST-BED.md:100`, `STB studies/02-boot-and-power/README.md:121`, `EP docs/decisions.md:125-130`, `EP docs/hardware-quirks.md:26-28` |
| 10 | Kernel flavour / baseline | Campaign: `7.2.5-1-cachyos-rt-bore-lto` `PREEMPT_RT`+BORE (HZ=300, no THP) vs host now `7.3.0-rc4-1-cachyos-cachyos-lto` | **Resolved → historical scoping.** STB claims are scoped to the campaign kernel and must not be edited to match; any re-run on the current kernel is a new baseline, and XFS behaviours (remount-inert opts) are kernel-version-specific. | `STB TEST-BED.md:57-71`, `~/docs/XFS-TUNING.md:10,85-86`, `STB docs/MEMORY.md:31-37` |

**Counts: 9 resolved (rows 1-7, 9-10), 1 left open (row 8 — applied state resolved, comparative claim
unresolved: both recorded).**

---

## 3. Open questions / not measured

- **Timer-policy power effect** (`xfssyncd_centisecs` 10000 → 30000 + `speculative_prealloc_lifetime`
  300 → 1800): INCONCLUSIVE at n=2/arm usable (MW-U minimum p = 0.333 at n=2/2; window 5 excluded as
  owner-session-contaminated; campaign cut short, then host battery died). Neither mechanism appeared:
  0 trim events in every window (the `wbig` workload never creates post-EOF speculative prealloc),
  idle log FORCE ≈ 8/min in BOTH arms (background traffic swamps the flush-cadence signal).
  Needs a quiet-machine idle-drain/wake-count campaign (powertop/turbostat windows ≥ 15 min/arm,
  deliberate panel blanking so screen-off J/min exists). Handles: `ab2-report-20260928.md:12,136-151,231-250`,
  `~/docs/XFS-TUNING.md:145-147`.
- **`allocsize` for random/mixed writes.** AB3 falsified `allocsize=1m` only for the big-sequential
  (`wbig` 4 GiB) workload class; small-file, random and mixed-write classes are untested, and the
  known over-reservation cost for early-terminating files stands. Handle: `~/docs/XFS-TUNING.md:181-187`.
- **Idle-drain campaign** (as above) — the entire writeback/wakeup family (6000/6000, xfssyncd,
  prelife) has mechanism evidence but no measured J/min confirmation on this host.
- **Backup gap.** No borg/restic/snapper/partclone installed; XFS has no snapshots. Dedupe, TRIM and
  scrub protect against none of the failure modes backups protect against. Recommendation stands for
  the next maintenance window (borg or restic to off-host/external storage). Handle:
  `~/docs/FS-MAINTENANCE.md:58-65`.
- **logbsize=256k end-to-end benefit** is mechanism-only (forced log commits 19034 → ~1561); the
  on-metal 32k A/B is half complete (the 32k comparison row was cache-mixed and rejected as evidence).
  Handle: `STB studies/03-filesystem-latency/README.md:55-69`.
- **filestreams for batch workloads** — the measured stall trade may be acceptable where wall time
  dominates and stall is invisible (fresh n≥5 A/B required). Handle: `~/docs/XFS-TUNING.md:136-138`.

---

## 4. Index pointers (target `system-tuning` layout)

| Content | Lives at |
|---|---|
| This synthesis (canonical merged truth) | `docs/unified-findings.md` |
| eco-power body: doctrine, settled decisions, measurement rules, fleet findings + rejection table, hardware quirks, rollback, reboot checklist, repo README | `docs/doctrine.md`, `docs/decisions.md`, `docs/measurement.md`, `docs/fleet-findings.md`, `docs/hardware-quirks.md`, `docs/rollback.md`, `docs/reboot-checklist.md`, `docs/README-eco-power.md` |
| Filesystem maintenance policy (duperemove/fstrim/scrub/smartd/xfs_fsr rules, backup gap) | `docs/FS-MAINTENANCE.md` |
| XFS research + A/B verdicts + owner override (candidates, skip list, §8 campaign results) | `docs/XFS-TUNING.md` |
| STB tree: methodology, test bed, study 01 scheduler selection, 02 boot/power, 03 filesystem latency, tools, data | `benchmarks/METHODOLOGY.md`, `benchmarks/TEST-BED.md`, `benchmarks/studies/01-scheduler-selection/`, `benchmarks/studies/02-boot-and-power/`, `benchmarks/studies/03-filesystem-latency/`, `benchmarks/tools/`, `benchmarks/data/` |
| XFS A/B campaign material (filestreams mkstorm rows, AB2 allocsize+timer report and idle windows, AB3 allocsize root/loopback rows, driver scripts) | `benchmarks/studies/04-xfs-tuning/` (from `~/.cache/bench-scratch/ab-xfs-20260928.jsonl`, `ab2-report-20260928.md`, `ab2-*`, `idle-w*`, `ab3-*`) |
| Managed live config (owned whole-file mirrors: sysctl writeback, TLP eco policy, NM wifi powersave, udev eco/wifi/bt rules, modprobe, eco-power.sh, hw-tune.fish, eco units) | `state/owned/etc/…`, `state/owned/usr/local/sbin/…`, `state/owned/home/…` (+ `state/managed/` anchored-line records; `state/README.md` convention) |
| Session chronology behind the 2026-09-26..28 FS/XFS work (dedupe semantics, pitfalls, overrides) | `docs/NOTE.md` excerpts (source: `~/docs/NOTE.md:3762-3855,3891-4013`) |
