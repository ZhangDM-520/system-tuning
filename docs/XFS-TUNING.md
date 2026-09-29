# XFS advanced/experimental tuning research — root NVMe XFS

*Research-only pass, 2026-09-28. No system state was changed. Sources: kernel
`Documentation/admin-guide/xfs.rst` + `fs/xfs` sources (7.x-era), xfsprogs `xfs(5)` (7.2.0),
host recon (`xfs_info`, sysfs, `/proc/sys/fs/xfs`), and the owner's tuning doctrine. The two
pre-merge repos (`eco-power`, `System-Tuning-Benchmarks`) merged into this tree on 2026-09-28;
citations below use the in-tree paths `docs/…` and `benchmarks/…` (line numbers unchanged by the
merge).*

## 1. Baseline (verified 2026-09-28)

- Kernel `7.3.0-rc4-1-cachyos-cachyos-lto` (host report), XFS V5 on `/dev/nvme0n1p2` (WD PC SN560),
  24 AGs (~40 GiB each), bsize 4096, isize 512, internal log **475 MiB**, sunit/swidth 0/0 (no stripe).
- Features on: reflink, rmapbt, finobt, sparse inodes, bigtime, inobtcount, **nrext64**, **exchange**;
  metadir=0. 7.38 M inodes.
- Mount: `rw,relatime,lazytime,inode64,logbufs=8,logbsize=256k,noquota`.
  **⚠ fstab XFS options are dead** — root is mounted in initramfs; effective `logbsize=256k` comes
  from kernel cmdline `rootflags=logbsize=256k` (benchmarks/TEST-BED.md:77-123). XFS **log geometry
  is chosen at first mount only** — remount "succeeds" and changes nothing
  (benchmarks/studies/03-filesystem-latency/README.md:40-53).
- Stack: IO scheduler `none`, nr_requests 1023, read_ahead 256 KiB but **max_sectors_kb=128**
  (drive MDTS — I/Os split at 128 KiB), WBT 2000 µs, vm.swappiness 150 (udev-enforced),
  vfs_cache_pressure 50, dirty 10/5 with writeback/expire 6000/6000 cs, all CPU policies
  `powersave` + EPP `dynamic` (race-to-sleep doctrine).
- `fs.xfs.*` live: `xfssyncd_centisecs=10000`, `filestream_centisecs=3000`,
  `speculative_prealloc_lifetime=300`, `inherit_*=1`, `rotorstep=1`. (7.x has **no**
  `speculative_prealloc_size/_max` keys.)

## 2. Preference constraints (one home: `docs/judgment.md`)

- Doctrine (work per joule, race to sleep, no caps/throttling), the two-gate adoption bar, and the
  arm-identity/readback rule have one home — `docs/judgment.md` (`## May I change?` /
  `## May I claim?`) — and are not restated here.
- **Two writers per sysfs attribute = silent race** (rule: `docs/findings.md` `## recovery`): TLP
  and the eco converger (600 s) rewrite `vm.dirty_*` and XFS age knobs, so live hand edits here
  are reverted — converge through `docs/rollback.md` `## Converge a change`.
- Hard anti-goals: WBT off, swappiness ≥200, NVMe PS5, online `discard`, `noatime`
  (lazytime already covers), anything breaking **reflink sharing** (xfs_fsr/defrag never automated),
  `norecovery`/root-unsafe options, benchmark-fitted tuning.
- `rm`/`find`-class workloads are serial round-trip bound (QD≈1, device 20-55% busy) —
  no mount knob fixes those (benchmarks/studies/03-filesystem-latency/README.md:106-107).

## 3. Ranked candidates

| # | Candidate | Expected effect | Power | Risk | Evidence |
|---|-----------|-----------------|-------|------|----------|
| 1 | **`filestreams`** — mount-wide, or surgical first: `xfs_io chattr +S` on `~/Projects` build dirs | Per-directory AG pinning → less AG contention & better locality for parallel creation (builds, package-tree untars, many small files) | ~0 (MRU aging only while streams exist) | Low; placement-only, no reflink interaction. Long-term free-space scatter (anecdotal) | Mechanism: `fs/xfs/xfs_filestream.c` + admin-guide/xfs.rst:57-60. **Benefit claimed/anecdotal — no rigorous public numbers.** Untested on this host (left "deliberately untouched" in benchmarks/studies/03-filesystem-latency/README.md:138-141). **MEASURED 2026-09-28 → REJECT, see §8** |
| 2 | **`fs.xfs.speculative_prealloc_lifetime` 300 → 1800–3600 s** | Fewer `xfs-blockgc` trim runs (post-6.18 this timer also covers COW-staging prealloc shared with duperemove) | Positive (fewer background wakeups) | Space held longer after write bursts; watch free-space dip after duperemove runs | admin-guide/xfs.rst:293-298,373; `xfs_icache.c:219-231`. Must be applied repo-first (converger co-writer; `docs/rollback.md` `## Converge a change`) |
| 3 | **`fs.xfs.xfssyncd_centisecs` 10000 → 30000+** | Fewer periodic metadata-flush wakeups (already raised 30 s→100 s; this is the next step) | Positive | Dirty metadata held longer; umount flush longer. Diminishing returns past 100 s | admin-guide/xfs.rst:284-287; prior raise measured "no latency win" for *lowering* (benchmarks/studies/03-filesystem-latency/README.md:83) — raising further is untested. Repo-first (runbook) |
| 4 | **`allocsize=1m`** (only if a sequential-growth workload matters) | Fixed EOF prealloc → fewer allocation transactions, better extent contiguity for large files | Fewer allocs = CPU win; oversize on small files = blockgc churn + write amp | Medium: turns OFF dynamic preallocation heuristic; mixed small-file workloads can regress | admin-guide/xfs.rst:24-35 (dynamic default). **No published numbers.** Note 128 KiB max bio — prealloc >128k is about extents, not I/O size |
| 5 | **XFS workqueue nice/cpumask** (`/sys/bus/workqueue/devices/xfs-*!<dev>/{nice,cpumask}`) — pin GC workers to Zen5c cores, nice +10 | Keeps inodegc/blockgc/reclaim work off the fast cores during interactive use | Positive (race-to-sleep aligned) | **Experimental**: unstable ABI ("may change at any time"); over-throttling delays unlinked-inode freeing | admin-guide/xfs.rst:498-535 (names in the doc are stale — verify actual wq names live before touching) |
| 6 | `logbsize`/`logbufs` tuning | Bigger iclogs = fewer log writes (19034→1561 forced commits already measured at 256k) | Positive | **Already at the ceiling** (8×256k = 2 MiB, explicit max). Changing requires `rootflags=` + reboot; fstab is dead | benchmarks/studies/03-filesystem-latency/README.md:55-57, benchmarks/TEST-BED.md:118. Not a candidate — a closed question |

## 4. Skip / avoid list

- **Doesn't exist in Linux XFS** (fstab experiments will fail the mount): `ikeepnoquota`, `sendbuf`.
- **Dead/no-op since 6.18** (parsed, ignored, warn): `ikeep`/`noikeep`, `attr2`/`noattr2`
  (immutable on V5 anyway). `inode64` is default since v3.7 — current fstab entry is a no-op restatement.
- **Root-unsafe or catastrophic**: `norecovery` (RO-only), `wsync` (log force per namespace op —
  kills builds and power), `discard` mount opt (kernel docs: "performance impact … quite severe";
  weekly `fstrim.timer` is the right design and already active).
- **Wrong hardware / inert**: `dax` (SN560 is not a DAX device), `swalloc`/`noalign`/`sunit`/`swidth`
  (single non-striped NVMe), `largeio` (pessimizes st_blksize-trusting apps), `inode32`.
- **Refuted or forbidden (do not re-propose without new evidence)**: online `discard=async`,
  `noatime`, `io_poll`, bigger `read_ahead_kb`, `nr_requests` changes, `wbt_lat_usec=0`,
  swappiness ≥200, smaller `xfssyncd` intervals (measured worse + wakeups), quota options
  (`noquota` is correct), anything requiring live remount to change **log geometry** (silently dead).
- **Debug-only**: `always_cow` (never a mount option; DEBUG sysfs global; pessimizes every write),
  `errortag`, `panic_mask`. **Removed options** (`delaylog`, `ihashsize`, `osyncisdsync`, `barrier`
  …) fail the mount outright.
- **Anti-goal**: xfs_fsr / defrag of reflink-shared files (breaks sharing, undoes duperemove).

## 5. Conflicts & uncertainties (cross-source)

1. `ikeep`/`attr2`: admin-guide calls them "removed v6.18"; the parser still accepts them as no-ops
   with deprecation postponed to 2030. Practical answer is the same — don't use them.
2. `allocsize` default: admin-guide still says "64 KiB" in one line, "dynamic" in another; current
   xfs(5) says dynamic heuristic. Treat 64 KiB as the heuristic base.
3. Workqueue names in admin-guide (`xfs-iwalk`, `xfs-gc`) don't match the code
   (`xfs-inodegc/$dev`, `xfs-blockgc/$dev`, …). Verify live before any knob (candidate 5).
4. Benchmark evidence for `filestreams`/`allocsize`/`lazytime` gains is claimed/anecdotal everywhere;
   the only hard "measured" doc claim is discard-vs-fstrim severity. Everything above must clear
   the two-gate A/B bar (`docs/judgment.md` `## May I claim?`) before adoption — that is the whole
   point of this host's methodology.
5. Kernel-version drift: 7.3-rc custom (CachyOS-patched) — trust `xfs_fs_parameters[]` of the running
   build over any blog; unknown options fail the mount, so test via `mount -o remount` before reboot.

## 6. Measurement recipe (protocol home: `docs/judgment.md`)

Gates, run design (interleave/rotate, discard rep 0, cache state, within-pass), arm identity via
consumer readback, and recording conditions have one home: `docs/judgment.md` (`## May I claim?`).
This module contributes only the campaign workload set and the XFS arm-readback points — both in §7.

## 7. Application & rollback recipe (NOT applied in this pass)

The one change flow is `docs/rollback.md` `## Converge a change` (edit `state/` → apply → commit);
the mechanics below are XFS-specific.

- **Campaign workload set** (`benchmarks/tools/wl.sh`, work data under `$BENCH_SCRATCH`):
  `mkstorm` + untar of package trees (filestreams), `coldmeta`, `rm`, `wbig` (allocsize),
  `pressure`. Snapshot every arm's live tunables with `benchmarks/tools/fslat.py` (`capture_settings()`
  is the arm-identity enforcement point). XFS arm-readback points: `/proc/mounts` (mount opts),
  `cat /proc/sys/fs/xfs/*` (sysctls), XFS `stats/stats` (forced-log-commit counter), workqueue
  `nice`/`cpumask` reads.
- **filestreams (candidate 1)**: start surgical — `sudo xfs_io -c 'chattr +S' ~/Projects/<build-dir>`
  (removable with `chattr -S`; zero boot risk). ⚠ `chattr +f` is **no-defrag** on current xfsprogs —
  the filestreams flag letter is **`+S`** (verified from `xfs_io help chattr`, 2026-09-28).
  Mount-wide: `mount -o remount,filestreams /` + readback check — **INERT on kernel 7.3-rc4** (see
  §8); roll back `remount,nofilestreams` is itself unimplemented (`nofilestreams` = unknown param).
- **sysctl candidates 2-3**: edit `~/Projects/system-tuning/state/owned/etc/sysctl.d/` (new file or
  extend), then converge through `docs/rollback.md` `## Converge a change` — which also owns the
  never-hand-edit-live rule (converger/TLP race) and the revert path.
- **allocsize / workqueue (candidates 4-5)**: measure first (§6); apply only with A/B evidence.
  Workqueue knobs are sysfs-per-boot — persist via an eco-power owned udev/tmpfiles rule if adopted.
- **Never**: fstab edits for XFS options (dead), remount for log geometry (no-op), reboot-free
  assumption for anything on `rootflags=`.
- **Re-apply recipe for `allocsize=1m`** (prepared 2026-09-28, deliberately unapplied — AB3
  measured no difference, §8): remount is inert on this kernel, so the only working route is the
  boot cmdline. Edit **both** `/etc/default/limine` (the durable source — limine-entry-tool
  regenerates `/boot/limine.conf` from it at every kernel install) and `/boot/limine.conf` (all 3
  kernel entries; `rootflags=` appears 3× there and 1× in the default file), setting
  `rootflags=logbsize=256k,allocsize=1m`. Take pre-images first (mechanism:
  `docs/rollback.md` `## Undo: universal mechanism`; `/rewind` cannot stage /boot). Effective at
  next boot; verify `grep ' / ' /proc/mounts` → `allocsize=1024k` (boot-time `rootflags=` parsing
  is proven where remount is inert). Rollback = restore the two pre-images. Glob pitfall:
  `sudo ls /boot/limine.conf*` expands the glob unprivileged and fails — use
  `sudo bash -c 'ls /boot/limine.conf*'` or explicit paths. Clean within-pass option A/B on this
  host = loopback image with mount-time arms (pattern: `benchmarks/tools/loopback-logbsize.sh`).

## 8. A/B campaign results (2026-09-28, 40-min budget, n=5/arm, cold cache, interleaved+rotated)

Full data: `benchmarks/studies/04-xfs-tuning/ab-xfs-20260928.jsonl` (fslat rows) — stats reproducible with
`FSLAT_RESULTS=… benchmarks/tools/perf-stats.py test fs-ctrl-mkstorm fs-fstream-S-mkstorm`.

### filestreams → **REJECT** (Pareto trade, not a win)
- **Mount option is INERT on kernel 7.3-rc4-cachyos-lto**: `mount -o remount,filestreams /` returns
  rc=0 but `filestreams` never appears in `/proc/mounts` and unflagged dirs fire **zero**
  `xfs_filestream_*` tracepoints. `nofilestreams` is an unknown parameter (cannot unset). Any
  fstab/limine persistence for `filestreams` would silently do nothing on this kernel. The
  measurable unit is the **per-directory `xfs_io chattr +S`** flag (letter `+S`, not `+f` —
  `+f` = no-defrag; `xfs_io help chattr` verified).
- Measured (`mkstorm 15` × 5/arm, treatment = scratch tree with `chattr +S`):
  **wins**: wall −8.9% (p=0.009), NVMe read ios −71.7%, write ios −47.3%, device busy −28.5%,
  log FORCE −23.6%, log no-space −41.4%. **Energy**: pkg J −2.1% (p=0.347, n.s.).
  **Significantly worse**: PSI io-some +112.9%, io-full +114.3%, cpu-some +91.1%,
  mean queue latency +86.9% (all p=0.009, all beyond control spread).
- Mechanism: AG pinning collapses metadata scatter (fewer/looser I/O, fewer log stalls) but
  concentrates load into fewer AGs → deeper per-request queues and ~2× system stall time.
  Adoption rule ("nothing significantly worse") **fails → not applied**. This is a throughput/
  stall trade — reconsider only for a workload where wall time dominates and stall is invisible
  (e.g. batch jobs), with a fresh n≥5 A/B.
- ftrace attribution proof: treatment 118800 filestream lookups / 1200 picks vs control 0/0.

### allocsize=1m → **NOT TESTED** (budget gate: <12 min remained after candidate 1 + analysis)
Follow-up candidate for a longer campaign (`wbig` workload); `allocsize` IS remount-visible
(module show-format confirmed), restore path (`remount,allocsize=64k`) untested.

### speculative_prealloc_lifetime / xfssyncd_centisecs → **DEFERRED**
Idle-wakeup/power plays — cannot surface in short throughput runs; need an idle-drain/wake-count
campaign (powertop/turbostat windows ≥ 15 min/arm).

### Persistence pitfall (found while prepping adoption — valid for any future mount-opt win)
`/boot/limine.conf` is **machine-generated by limine-entry-tool from `/etc/default/limine`** —
editing only limine.conf is silently reverted at next kernel install. A cmdline change must edit
BOTH (`rootflags=` appears 3× in limine.conf — 3 kernel entries — and 1× in /etc/default/limine),
with `cp -p` backups first (`/rewind` cannot stage /boot). Full recipe + rollback is now in-repo:
§7 (still unapplied since nothing won).

### Follow-up campaign AB2 (2026-09-28 PM) — `allocsize` + timer-policy → NOTHING ADOPTED
Full report: `benchmarks/studies/04-xfs-tuning/ab2-report-20260928.md` (data: `ab2-allocsize-*.jsonl`,
`ab2-idle-*.jsonl`, `idle-w*-samples/xstats.jsonl`).
- **`allocsize=1m` vs dynamic (wbig, n=5/arm): NOT ADOPTED** — every gate-1 effect inside control
  spread (largest −15.4% PSI vs 36% spread). ⚠ **Arm identity unproven**: treatment rows carry no
  `allocsize=1m` readback — remount was another silent no-op on 7.3-rc4 (same class as `filestreams`).
  Null result ≠ refutation; a real test needs loopback image or `rootflags=`+reboot.
- **Timer policy `xfssyncd=30000`+`prelife=1800` (n=2/arm usable): INCONCLUSIVE-lean → NO adoption**
  (hard ceiling n<5; MW-U min p at n=2/2 = 0.333). Mechanisms never appeared: 0 trim events both arms
  (wbig produced no post-EOF speculative prealloc), idle log FORCE ≈ 8/min in BOTH arms (background
  traffic dominates; no 3× flush reduction visible). No screen-off energy data (panel never blanked
  during windows). Campaign cut short (owner directive) then hit host battery death mid-window-5.
- **Nothing applied; system state verified clean** (sysctls 10000/300, root mount without allocsize).
- **Lesson for any future A/B on this host: PROVE ARM IDENTITY VIA READBACK BEFORE burning runs** —
  two of two `mount -o remount,<xfs-opt>` treatments (filestreams, allocsize) were silently inert on
  this kernel; fslat's per-row `capture_settings()` is the enforcement point.

### Owner override (2026-09-28 17:2x) — applied despite verdicts
Per owner decision: per-directory filestreams (`chattr -D +S` on `~/Projects` + `~/Workspace`,
verified `[S]`, new dirs inherit) and `allocsize=1m` via `rootflags=` in both `/boot/limine.conf`
(3 entries) and `/etc/default/limine` (durable source), backups `*.bak-20260928-pre-xfs-tune`.
Effective after reboot; verify with `grep ' / ' /proc/mounts` → `allocsize=1024k`. Known trade
from §8 still applies to `+S`: faster bursts but ~2× stall during them — acceptable here as a
deliberate owner choice. Rollback: restore the two backups (cmdline) + `xfs_io -c 'chattr -D -S'`.

### AB3 verdict (2026-09-28): allocsize=1m = NO DIFFERENCE → rolled back
Root cross-pass n=5/arm: wall −1.4% (inside spread), J −6.8% (n.s., cross-pass confounded).
Loopback within-pass A/B: exactly zero (wall/energy/ios/extents). Mechanism falsified (sync
transactions +189% with the setting; same 3 extents; same write request sizes). Over-reservation
cost stands. Owner-rule outcome: not a win → **rollback performed** (both limine backups restored,
effective next boot). §4's "allocsize" row is now a measured non-result on this host's big-sequential
workload class (small/random writes still untested). Re-apply recipe: §7.
