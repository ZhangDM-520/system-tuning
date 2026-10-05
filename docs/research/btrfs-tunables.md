# Btrfs tunables beyond mount options — sysfs, block layer, VM, job caps

*Research-only pass, 2026-10-05. Nothing here is applied; every live command below was read-only.
Companion to `docs/research/btrfs-optimization.md` (mount options, on-disk features, and the
maintenance-policy rulings — that content is **pointed at, never restated** here).*

**Scope.** Tunable parameters for this host's btrfs root (ASUS Zenbook S 16 UM5606WA, Ryzen AI 9
HX 370 hybrid, WD SN560 NVMe, CachyOS, kernel `7.2.9-1-cachyos`, root = single-device btrfs) that
are **not** mount options or on-disk features: (1) `/sys/fs/btrfs/<FSID>/`, (2) block-layer and IO
scheduler knobs on the NVMe backing it, (3) VM/sysctl interplay, (4) kernel/module parameters,
(5) job-time caps for scrub/balance/defrag, (6) anything touching the suspend/wake + APST hazard.

**Status vocabulary** (same spirit as the sibling doc):

- **(a) documented tunable** — semantics sourced to a man page, kernel documentation, or a
  kernel-source comment at the store/consumer site; safe to reason about, still not adopted here.
- **(b) diagnostic** — read-only state; useful for the re-check block, never a tuning surface.
- **(c) undocumented / avoid** — exists and may be writable, but semantics are unverified,
  experimental, or blast radius exceeds the reason to touch it.

**Source-verification convention.** Every handle is marked `[verified]` (text read in this session:
installed man pages, live readbacks, or upstream kernel source at `torvalds/linux@a90ee4305c4a`
via GitHub) or `[not retrieved]` (named as the source of record but unreachable this session —
external HTTP was DNS-sinkholed; see Unknowns). Adopting anything below still routes through
`docs/judgment.md` `## May I change?`, and every performance/energy statement routes through
`## May I claim?` (two gates in order, n ≥ 5 per arm, interleave + rotate, discard rep 0,
two-source arm identity). Maintenance facts need no measurement but are labeled as such.

**One home per knob.** If a proposal below is ever adopted: block-layer/queue knobs →
`docs/findings.md` `## io-stack`; NVMe power-state knobs → `## nvme`; async-discard pacing →
`## fstrim`; dirty/writeback VM knobs → `## writeback`; job caps and their automation →
`docs/rollback.md` `## Storage ops`. This file stays the evidence base and is never the rule home.

---

## 0. Live baseline (readback, 2026-10-05 — facts, not measurements)

**Filesystem sysfs.** One FSID directory, `/sys/fs/btrfs/521bbdbd-77e2-4a70-a8f7-9bda99558cde/`
(`btrfs filesystem show /` cross-checks the UUID), plus global `/sys/fs/btrfs/features/`.
**`/proc/fs/btrfs/` does not exist** (`ls /proc/fs/btrfs` → ENOENT). The tree contains:
`allocation/{data,metadata,system}/` (plus per-profile subdirs `data/single`, `metadata/dup`,
`system/dup`), `bdi` (symlink to `bdi/btrfs-1`), `devices/nvme0n1p2`, `devinfo/1/`, `discard/`,
`features/`, and top-level `bg_reclaim_threshold`, `checksum`, `clone_alignment`, `commit_stats`,
`exclusive_operation`, `generation`, `label`, `metadata_uuid`, `nodesize`, `quota_override`,
`read_policy`, `sectorsize`, `temp_fsid`. Writable (root) files, per `find -printf '%M'`:
`bg_reclaim_threshold`, `allocation/*/bg_reclaim_threshold`, `allocation/*/chunk_size`,
`allocation/*/dynamic_reclaim`, `allocation/*/periodic_reclaim`, `devinfo/1/scrub_speed_max`,
`discard/{iops_limit,kbps_limit,max_discard_size}`, `label`, `quota_override`, `read_policy`,
`commit_stats`, `features/extended_iref`. Everything else in the tree is `-r--r--r--` (b).

**Block queue** (`cat /sys/block/nvme0n1/queue/…`): `scheduler` = `none mq-deadline [kyber] adios
bfq` (**kyber is active**), `nr_requests` 256, `read_ahead_kb` 256, `max_sectors_kb` 128 =
`max_hw_sectors_kb` (drive MDTS), `rq_affinity` 1, `nomerges` 0, `write_cache` = `write back`,
`rotational` 0, `io_poll` 0, `iostats` 1, `wbt_lat_usec` 2000. Kyber's `iosched/` = `read_lat_nsec`
2000000 (2 ms), `write_lat_nsec` 10000000 (10 ms). The btrfs BDI (`/sys/devices/virtual/bdi/btrfs-1/`)
carries its **own** `read_ahead_kb` = 4096 — a different knob from the queue's 256 (§2.4).

**DRIFT FLAGS vs the ledger (owner decisions, not fixed here).** `docs/findings.md:267-288`
(`## io-stack`, class tunable) says "NVMe scheduler `none` … applied … `nr_requests=1023`" with
check `cat /sys/block/nvme0n1/queue/{scheduler,nr_requests,…}`. That check now reads **kyber /
256**. Both mismatches are exactly what the ledger's own check exists to catch. Nothing in this
repo's `state/` sets either value live (`## io-stack` records scheduler persistence as a foreign
udev rule, `/etc/udev/rules.d/60-ioschedulers.rules`); which event moved the values is
undetermined. Do not "fix" either side by hand: `docs/rollback.md` `## Converge a change` first,
or reopen `## io-stack` with measurement. Read back the same way before trusting either source.

**Module parameters.** `/sys/module/btrfs/parameters/` **does not exist** (btrfs exposes no module
parameters on this kernel). `nvme` and `nvme_core` do (§4). Scheduler code (kyber/mq-deadline/bfq)
is built-in here: no `kyber_iosched`/`mq_deadline`/`bfq_iosched` module parameter dirs.

**VM/sysctl readback** (`sysctl …`): `vm.dirty_bytes` 268435456 (256 MiB),
`vm.dirty_background_bytes` 67108864 (64 MiB) — the ratio pair reads 0 (byte form is active,
kernel-doc semantics in §3), `vm.dirty_expire_centisecs` 6000, `vm.dirty_writeback_centisecs`
6000 (repo-owned: `state/owned/etc/sysctl.d/99-eco-writeback.conf`), `vm.vfs_cache_pressure` 50,
`vm.swappiness` 150, `vm.zone_reclaim_mode` 0, `fs.aio-max-nr` 65536,
`fs.inotify.max_user_watches` 524288 / `max_user_instances` 1024. Ownership attribution (why the
distinction matters — one writer per state): the dirty *bytes* pair and `vfs_cache_pressure=50`
come from the **vendor drop-in `/usr/lib/sysctl.d/70-cachyos-settings.conf`** (foreign file,
CachyOS default), inotify limits from `/usr/lib/sysctl.d/10-arch.conf`, and only the dirty
*centisecs* pair is repo-owned (`docs/findings.md` `## writeback`).

**Job state** (`sudo btrfs scrub limit /`): no scrub speed limit set (device 1, limit `-`), i.e.
`devinfo/1/scrub_speed_max` = 0 (unlimited). Swap is zram (`swapon --show`), as the ledger says.

---

## 1. btrfs sysfs — `/sys/fs/btrfs/<FSID>/`

**Where the semantics live.** There is **no kernel Documentation/ABI entry for the btrfs sysfs
tree** at `torvalds/linux@a90ee4305c4a`: `Documentation/ABI/testing/` lists `sysfs-block-{aoe,
bcache,device,dm,loop,rnbd,rssd,zram}` and `sysfs-class-bdi` but no `sysfs-fs-btrfs`
[verified — directory listing]. So for this subsystem the sources of record are (1) the btrfs-progs
man pages where they mention a file, and (2) the kernel source implementing it — `fs/btrfs/sysfs.c`
(show/store + validation comments) plus the consumer in `fs/btrfs/{space-info,discard,scrub}.c`.
How to check a knob's contract on this host:

```
sudo sh -c 'find /sys/fs/btrfs -maxdepth 4 -printf "%M %p\n"'   # what exists + writability
cat /sys/fs/btrfs/*/bg_reclaim_threshold                         # fs-wide knob
cat /sys/fs/btrfs/*/allocation/*/bg_reclaim_threshold            # per-type knobs
```

### 1.1 Job caps (a — documented): `devinfo/<DEVID>/scrub_speed_max`

Per-device scrub bandwidth cap, bytes/s, `memparse`-style value (`100m`), 0 = unlimited;
**not persistent — lasts until unmount**; displayable/settable via `btrfs scrub limit`
(btrfs-scrub(8) 7.1, "Bandwidth and IO limiting" + `limit` subcommand) [verified — man page];
store implementation `btrfs_devinfo_scrub_speed_max_store` [verified — `fs/btrfs/sysfs.c`].
Full job-cap story in §5. Doctrine note (not a measurement): a rate-capped trickle runs counter
to race-to-sleep (`docs/judgment.md:14-21`); the cap exists for *interactive protection*, not for
efficiency — the same stance the sibling doc records for the shipped scrub unit.

### 1.2 Async-discard pacing (a — documented in source): `discard/{iops_limit,kbps_limit,max_discard_size}`

The `discard=` mount family is out of scope (pointer: sibling §5, and the `## fstrim` drift item);
these three files are the **runtime pacing of the async-discard worker** and are squarely in scope,
especially for the APST question (§6). Mechanism [verified — `fs/btrfs/discard.c` header comment
and `btrfs_discard_calc_delay`]:

- Async discard is a single delayed-work item; its timeout is the max of (i) the iops-rate delay,
  (ii) the byte-rate delay, (iii) up to `BTRFS_DISCARD_MAX_DELAY_MSEC` (1000 ms). Freed space is
  only eligible after `BTRFS_DISCARD_DELAY` (120 s) so blocks can be reused first.
- `iops_limit`: `delay = 1000 ms / iops_limit`, clamped to [1 ms, 1000 ms]; **0 = no pacing**
  (delay 0). Default `BTRFS_DISCARD_MAX_IOPS` = 1000 [verified — source constant + live value].
- `kbps_limit`: per-work-item byte-rate delay; 0 = off (live 0).
- `max_discard_size`: max bytes trimmed per issued discard; default
  `BTRFS_ASYNC_DISCARD_DEFAULT_MAX_SIZE` (live 64 MiB).

Diagnostics in the same directory (b): `discardable_bytes`, `discardable_extents`,
`discard_bitmap_bytes`, `discard_extent_bytes`, `discard_bytes_saved` — the queue-depth view of
the backlog the worker is draining (how to check: `cat /sys/fs/btrfs/*/discard/discardable_bytes`
before/after an idle window; it is the honest readback of "is async discard still working").

### 1.3 Background block-group reclaim (a per-type; mixed — see text): `allocation/*/bg_reclaim_threshold`,
`dynamic_reclaim`, `periodic_reclaim`, `chunk_size`, `reclaim_{bytes,count,errors}`

New-ish reclaim machinery; semantics [verified — `fs/btrfs/space-info.c`, `fs/btrfs/sysfs.c`]:

- `bg_reclaim_threshold` (per type): percentage of a block-group's length; the reclaim sweep marks
  a group for reclaim when `used < length × thresh%` on a second pass (`do_reclaim_sweep`:
  `thresh = mult_perc(bg->length, thresh_pct)`), plus an "urgent" mode that reclaims even fresh
  groups when unallocated chunk space drops below one effective data chunk. Store accepts 0..100
  and refuses writes while `dynamic_reclaim` is on. Live: 0 per type.
- `dynamic_reclaim` (0/1): when set, the threshold is computed per space_info
  (`calc_dynamic_reclaim_threshold`) instead of read from `bg_reclaim_threshold`. Live: 0.
- `periodic_reclaim` (0/1): enables a periodic reclaim readiness gate; explicitly **excluded for
  `BTRFS_BLOCK_GROUP_SYSTEM`** groups (`btrfs_should_periodic_reclaim`). Live: 0. This one is a
  wakeup source if turned on — treat as (c) until someone measures the wake pattern it adds.
- `chunk_size` (bytes): future chunk allocation size per type. Store comment, verbatim semantics:
  "Can be called on a read-only filesystem. If the new chunk size value is larger than 10% of free
  space it is reduced to match that limit. Alignment must be to 256M and the system chunk size
  cannot be set." Live: data 10 GiB, metadata 1 GiB. Documented-in-source (a) but blast radius is
  large (allocation granularity → ENOSPC/fragmentation behavior) → do not tune without a
  measured failure to fix.
- `reclaim_bytes`, `reclaim_count`, `reclaim_errors`, `size_classes` (b): what the reclaim path
  has done so far (all zero live; `size_classes` buckets block groups none/small/medium/large).

**Gap recorded honestly:** the fs-wide (top-level) `bg_reclaim_threshold` (live 75) accepts 0 or
51..100 on non-debug kernels (`btrfs_bg_reclaim_threshold_store`, [verified — `fs/btrfs/sysfs.c`])
and is initialized to `BTRFS_DEFAULT_RECLAIM_THRESH` (`fs/btrfs/disk-io.c:2921` [verified — line
hit]), but **which consumer reads the fs-wide value on non-zoned filesystems was not located**
(the `free-space-cache.c` consumer found is the zoned path). Treat the fs-wide knob as
**(c) undocumented — do not write** until the consumer is traced in `fs/btrfs/` on the kernel
that ships with the next upgrade.

### 1.4 Per-device directory `devinfo/1/` (b, except scrub_speed_max)

`error_stats` (write/read/flush/corruption/generation error counters — the sysfs mirror of
`btrfs device stats`), `fsid`, `in_fs_metadata`, `missing`, `replace_target`, `writeable`
[verified — `fs/btrfs/sysfs.c` show functions]. All-zero counters is a health check
(`docs/rollback.md` `## Storage ops — re-check commands`), not a knob.

### 1.5 The rest of the tree — classification

| Attribute | Class | Contract (source) |
|---|---|---|
| `label` | (a) | filesystem label; same as `btrfs filesystem label` (btrfs-filesystem(8) [verified — man]) |
| `quota_override` | (c) | requires `CAP_SYS_RESOURCE`, sets `BTRFS_FS_QUOTA_OVERRIDE`; the flag's consumer was not traced. qgroups are refused by default anyway (pointer: `docs/rollback.md` `## Storage ops — never-run rules`) |
| `read_policy` | (c) | multi-device read balancing; guarded by `CONFIG_BTRFS_EXPERIMENTAL` (`btrfs_read_policy_init`) [verified — `fs/btrfs/sysfs.c`]. Single device: no effect. Never a first thing to tune |
| `commit_stats` | (b) | transaction-commit latency stats (`commits`, `cur/last/max/total_commit_ms`); writing resets (store gated by `CAP_SYS_RESOURCE`) |
| `exclusive_operation` | (b) | shows a running exclusive op (`none` live) |
| `generation`, `nodesize`, `sectorsize`, `checksum`, `clone_alignment`, `metadata_uuid`, `temp_fsid` | (b) | fs geometry/identity |
| `allocation/{data,metadata,system}/{bytes_*,disk_*,flags,total_bytes}` | (b) | per-type allocation accounting (the `btrfs filesystem usage` numbers, raw) |
| `allocation/<type>/<profile>/{total_bytes,used_bytes}` | (b) | per-profile accounting |
| `features/*` (per-fs) and `/sys/fs/btrfs/features/*` (global) | (b) | on-disk/kernel feature flags; **features are the sibling doc's territory** (pointer only). Note `features/extended_iref` is oddly writable on a mounted fs — semantics untraced, leave alone |
| `bdi` symlink | (b→tunable) | points at `bdi/btrfs-1`, whose `read_ahead_kb` *is* a knob — see §2.4 |

---

## 2. Block layer / IO scheduler (the NVMe under btrfs)

### 2.1 Scheduler choice — pointer + drift, and the ionice verdict

Settled policy is **`none`**, race-to-idle so bursts drain immediately and the APST timer can
start — `docs/findings.md:267-288` (`## io-stack`), class tunable. **Pointer, not a re-proposal.**
Reopen condition: a measured A/B on the *current* kernel with APST residency in the arm identity.
Two live facts sit against the ledger today (§0): the active elevator is **kyber**, and
`nr_requests` reads **256**. That is a state question for `docs/rollback.md` `## Converge a change`
/ the owner, not a research verdict. Available elevators on this kernel: `none`, `mq-deadline`,
`kyber`, `adios`, `bfq` (the live `scheduler` file; `adios` semantics were not researched —
unknown).

**ionice: verified, with a documentation contradiction.** The sibling doc left this open
("likely inert on `none` — verify or refute"). Verified answer [kernel source + kernel doc,
`torvalds/linux@a90ee4305c4a`]:

- `Documentation/block/ioprio.rst` [verified]: "Support for io priorities is io scheduler
  dependent and **currently supported by bfq and mq-deadline**."
- `block/mq-deadline.c` [verified]: `ioprio_class_to_prio[]` maps `IOPRIO_CLASS_{RT,BE,IDLE}` to
  per-priority request queues (`DD_RT_PRIO`/`DD_BE_PRIO`/`DD_IDLE_PRIO`) with aging
  (`prio_aging_expire`) — ionice is real under mq-deadline.
- `block/kyber.c` and `drivers/nvme/` contain **no** `ioprio` usage [verified — code search
  returns no matches]: kyber throttles to latency targets only (§2.2), and the NVMe driver does
  not map ioprio onto NVMe command priority.
- **Contradiction to record:** the installed btrfs-progs 7.1 `btrfs-scrub(8)` deprecation note for
  `-c/-n` says the opposite ("only supported by BFQ or Kyber … not supported by mq-deadline")
  [verified — man page]. Two primary sources agree against the man sentence; the flags are
  deprecated anyway. Practical verdict for **this** host: under `none` **and** under the current
  kyber, `ionice`/`IOSchedulingClass=idle` changes nothing in dispatch; it becomes meaningful only
  if the elevator is mq-deadline or bfq. If ever relied on, verify on the running kernel first
  (host kernel is newer than the indexed upstream source; see Unknowns).

### 2.2 Queue knobs — what each is, live value, and ledger status

Source of record for contract details: `block/blk-sysfs.c` [verified — store/show functions];
there is no `Documentation/ABI/testing/sysfs-block` entry at the indexed commit (§1 sources note).

| Knob (path `/sys/block/nvme0n1/queue/`) | Live | What it is | Ledger status |
|---|---|---|---|
| `scheduler` | kyber (ledger: none) | elevator; per-elevator behavior changes everything below | `## io-stack` — pointer + drift flag (§0) |
| `nr_requests` | 256 (ledger: 1023) | per-queue request cap; store clamps below `BLKDEV_MIN_RQ` and is serialized against elevator switching (`queue_requests_store`) | `## io-stack` — pointer + drift flag; ledger already refuses 1023→256 (measured-worse) |
| `read_ahead_kb` | 256 | queue-level read-ahead window | `## io-stack` — pointer; refusal of 256→2048 recorded (measured-identical) |
| `max_sectors_kb` | 128 = `max_hw_sectors_kb` | max request size; hard ceiling is the drive MDTS — leave at hardware value | `## io-stack` (MDTS note) — pointer |
| `wbt_lat_usec` | 2000 | buffered-writeback throttle target latency (µs); 0 = disabled. Mechanism: CoDel-style latency window that scales queue depth down 2× per step (`block/blk-wbt.c` header comment [verified]) | `## io-stack` — pointer; refusals of 0 and of 1000/10000 recorded (measured) |
| `rq_affinity` | 1 | completion affinity bits (`QUEUE_FLAG_SAME_COMP`<<`SAME_FORCE`): 1 = complete on the submitting CPU, 2 = force full affinity | not in ledger; no reason found to change |
| `nomerges` | 0 | 0 = merging on; 1 = no simple merges; 2 = no merges at all (encoding verified in `queue_nomerges_show`) | not in ledger; merging is what makes small writes cheap — no case to disable |
| `write_cache` | `write back` | whether the kernel uses the device's volatile write cache (with FLUSH); `write through` disables it — see `Documentation/block/writeback_cache_control.rst` [not retrieved] | not in ledger; changing it trades durability-vs-latency at the block layer and duplicates what mount/fsync semantics already express — out of scope unless a measured durability need appears |
| `io_poll` / `io_poll_delay` | 0 | polled IO for low-latency queues; costs a busy-poll path (anti race-to-sleep as a default) | not in ledger; avoid |
| `iostats` | 1 | per-disk IO accounting toggle (off = fewer accounting writes at the price of blind re-check blocks) | not in ledger; keep — `docs/rollback.md` re-check blocks depend on counters |

Kyber's own tunables (`iosched/read_lat_nsec` 2 ms, `iosched/write_lat_nsec` 10 ms): the "target
latencies for reads and synchronous writes; Kyber will throttle requests in order to meet these
target latencies" [verified — `Documentation/block/kyber-iosched.rst`]. They only exist while
kyber is the elevator. Do not tune them as a first move: throttling depth is exactly the WBT/ledger
territory that already has measured refusals.

### 2.3 cgroup v2 `io.weight` / `io.latency` / `io.max` — relevant only as job throttles

Mapping [verified — `systemd.resource-control(5)`]: `IOWeight=`/`IODeviceWeight=` → `io.weight`;
`IOReadBandwidthMax=`/`IOWriteBandwidthMax=` → `io.max`; `IOLatencySec=` → `io.latency`. This
repo's jobs already sit on them: `beesd@<FSUUID>.service` runs `IOWeight=10`, `Nice=19`,
`IOSchedulingClass=idle`, and the stock `btrfs-scrub@.service` carries `Nice=19` +
`IOSchedulingClass=idle` (live `systemctl show` readback; policy home `docs/rollback.md`
`## Storage ops`). Status: the IOWeight is the upstream-shipped throttling of the dedupe duty
(maintenance fact, not a claim); `IOSchedulingClass=idle` is the ionice path from §2.1 — inert
under the current elevator. `io.latency`/`io.max` remain available as *runtime job caps*
(the man page's own example: `systemd-run -p "IOReadBandwidthMax=/dev/sdx 10M" btrfs scrub start
-B /` — btrfs-scrub(8) [verified]) but §5's doctrine note applies: rate caps protect
interactivity, they are not efficiency tools.

### 2.4 Two read-ahead knobs, not one

Queue `read_ahead_kb` (256) is per-device; **`/sys/devices/virtual/bdi/btrfs-1/read_ahead_kb`
(4096) is the btrfs filesystem's own BDI window** ("Size of the read-ahead window in kilobytes",
`Documentation/ABI/testing/sysfs-class-bdi` [verified]) and is what filemap readahead on btrfs
inodes uses. The same file tree also exposes `min_ratio`/`max_ratio` (+ `_fine`, + `min_bytes`/
`max_bytes`/`strict_limit`) — per-BDI shares of the dirty-page writeback cache (b, except as a
last-resort QoS tool). Any future read-ahead experiment must name *which* knob moved; the ledger's
256→2048 refusal (`## io-stack`) was a queue-level, XFS-era test and does not automatically
transfer to the BDI window on btrfs.

---

## 3. VM/sysctl interplay with btrfs

Mechanism source: `Documentation/admin-guide/sysctl/vm.rst` [verified]. Filesystem-agnostic
knobs are called out; those belong in the general ledger (`docs/findings.md`), not in any
filesystem campaign doc.

- **`vm.dirty_bytes` / `vm.dirty_background_bytes`** (live 256 MiB / 64 MiB, byte form active
  because the ratio pair reads 0 — kernel-doc: "Only one of them may be specified at a time";
  minimum value is two pages): the size thresholds at which a *writing process itself* starts
  writeback (bytes) and at which *background flushers* start (background_bytes). On btrfs, dirty
  pages are copied on writeback (CoW), so these caps bound the burst size of a transaction
  flush — the mechanism interacts with btrfs more than with a page-override filesystem, but the
  knobs themselves are generic. **They are not owned by this repo** (vendor drop-in
  `/usr/lib/sysctl.d/70-cachyos-settings.conf`); if ever adopted, the home is
  `docs/findings.md` `## writeback` alongside the centisecs pair. Reopen condition: a measured
  dirty-cap A/B (the writeback family is already flagged there as having no J/min confirmation).
- **`vm.dirty_expire_centisecs` / `vm.dirty_writeback_centisecs`** (live 6000/6000): flusher
  wakeup interval and dirty age. **Settled/owned — POINTER only** (`docs/findings.md` `## writeback`,
  class tunable; single-writer story `state/owned/etc/sysctl.d/99-eco-writeback.conf` + TLP
  `MAX_LOST_WORK_SECS_* = 0` + eco re-assert belt). Reopen condition: the entry's own Open item —
  a quiet-machine idle-drain/wake-count campaign (≥ 15 min/arm) before any further change.
- **`vm.vfs_cache_pressure`** (live 50, vendor drop-in): reclaim bias for dentry/inode caches;
  kernel-doc warns that values far above the denominator cost lock traffic on reclaim and that
  0 risks OOM. Filesystem-agnostic; btrfs has many inodes/subvolumes so the *value* matters to
  this host, but the knob's home is generic (`docs/findings.md` `## misc` if adopted). Not a
  btrfs tuning. Note the kernel doc now pairs it with `vfs_cache_pressure_denom` [verified text];
  read both before touching.
- **`vm.swappiness`** (live 150): **POINTer** — `docs/findings.md` `## io-stack` (udev-enforced,
  zram swap; the 150→200 refusal is measured and stands). Kernel-doc confirms the rationale for
  >100 with in-memory swap ("For in-memory swap, like zram or zswap … values beyond 100 can be
  considered") [verified]. Nothing btrfs-specific to add; never re-proposed here.
- **`vm.zone_reclaim_mode`** (live 0 = default): NUMA zone-reclaim policy; kernel-doc recommends
  leaving it off for cache-friendly workloads. This APU is a single memory node — the knob is
  **irrelevant here** (b on a single node). Filesystem-agnostic.
- **`fs.aio-max-nr`** (live 65536 = kernel default) and **`fs.inotify.max_user_*`** (live
  524288/1024 = Arch drop-in): global limits on aio contexts / inotify watches. They bound
  *workload* concurrency (how many watchers/submissions may exist), not btrfs behavior; no
  material interaction with compression/CoW/page-cache was found in the primary sources. Verdict:
  **filesystem-agnostic, belongs elsewhere** — no action.

---

## 4. Kernel / module parameters

**btrfs: none.** `/sys/module/btrfs/parameters/` does not exist on this kernel (§0) [verified].
Everything tunable in btrfs is a sysfs attribute (§1), a mount option (sibling doc), or a job
flag (§5).

**NVMe / block** (`cat /sys/module/{nvme,nvme_core}/parameters/*`) [verified — live readback]:

| Parameter | Live | Class / note |
|---|---|---|
| `nvme_core.default_ps_max_latency_us` | 100000 | **settled — POINTER** (`docs/findings.md` `## nvme`: PS5 gated out; reopen only if exit latency is ever measured) |
| `nvme_core.apst_primary_timeout_ms` / `apst_primary_latency_tol_us` | 100 / 15000 | (c) host-kernel APST policy (first stage ≙ the settled "PS3 after 100 ms"); semantics not in any retrievable doc — **boot-time state, never write at runtime** |
| `nvme_core.apst_secondary_timeout_ms` / `apst_secondary_latency_tol_us` | 2000 / 100000 | (c) second stage ≙ the settled "PS4 after 2 s"; same rule |
| `nvme_core.force_apst` | N | (c) bypass of the APST latency gate — never flip; it is the same hazard class as `nvme set-feature -f 0x0c` (pointer: `## nvme`) |
| `nvme_core.iopolicy` | numa | (b/c) per-node IO policy; single-node host → no effect; boot-time |
| `nvme_core.{admin_timeout,io_timeout,max_retries,shutdown_timeout,multipath,multipath_always_on,disable_pi_offsets}` | 60/30/5/5/Y/N/N | (c) error-handling/multipath policy; not tuning surfaces. Note `max_retries=5` interacts with error paths, not performance |
| `nvme.{io_queue_depth,max_host_mem_size_mb,write_queues,poll_queues,sgl_threshold,use_cmb_sqes,use_threaded_interrupts,noacpi,quirks}` | 1024/128/0/0/32768/Y/0/N/"" | (c) queue-layout/registration options — boot-time only (most apply at controller probe); no runtime knob here |

Rule of thumb for this section: `/sys/module/*/parameters` values that only the probe path reads
are **boot-time lore** — writing them post-probe does nothing or destabilizes; the recovery
domain rule (`docs/judgment.md:35`) applies to anything touching the NVMe power policy. The
standing hazard list (`docs/findings.md` `## nvme`) is authoritative and is not restated beyond
the pointers above.

---

## 5. Job-time caps (runtime knobs only; automation policy is already ruled — pointer:
`sibling §3–§7`, `docs/rollback.md` `## Storage ops`)

**Scrub** (btrfs-scrub(8) 7.1 [verified — man page]):

- `btrfs scrub start -B <path>` — `-B` = **do not background** (run to completion and print
  statistics; this is what the shipped systemd unit uses). Background is the default without it.
  `-r` = read-only pass, `-f` = force a second run, `-d` = per-device stats.
- `btrfs scrub limit [--devid N|-a] -l SIZE <path>` — set the per-device throughput cap (bytes/s,
  `KMGT` suffixes, 0 = unlimited); equivalent per-run form `btrfs scrub start --limit <value>`,
  which **restores the old limit when the scrub finishes**. The sysfs twin is
  `devinfo/<DEVID>/scrub_speed_max` (§1.1); neither is persistent across unmount. Display:
  `btrfs scrub limit /`.
- Deprecated `-c <ioprio_class>` / `-n <classdata>` — the ionice path; see the §2.1 verdict and
  the recorded man-page contradiction. Do not build on them.
- Suspend semantics (pointer, already ruled): since v6.19 a running scrub is **cancelled** by
  suspend/hibernate and needs `btrfs scrub resume` — `docs/rollback.md` `## Storage ops —
  re-check commands` carries the policy; the hazard is in §6 here.

**Balance** (btrfs-balance(8) 7.1 [verified — man page]) — the trigger-only policy is ruled
(`docs/rollback.md` `## Storage ops — never-run rules`); the runtime knob set that policy refers
to: filters `-d/-m/-s` with `usage=<n|a..b>` (compact partially used groups; `usage=0` cleans
fully empty groups without needing workspace), `limit=<n|a..b>` ("process only given number of
chunks … just simply limit the amount of work done by a single balance run"), plus
`profiles=`, `devid=`, `drange=`, `vrange=`, `convert=` (needs `-f` when reducing metadata
integrity), `stripes=`, `soft`. Job control: `--background|--bg`, `--enqueue` (wait for another
exclusive op), `pause`/`resume`/`cancel`, `status`. Workspace requirement (ENOSPC) and
IO-intensity warnings are as the sibling doc quotes them.

**Defrag** (btrfs-filesystem(8) 7.1 [verified — man page]) — never automated (ruled:
`docs/rollback.md`; reflink breakage). The runtime knobs for the rare deliberate single-file
case: `-s <start>`/`-l <len>` range, `-t <size>` target extent size (skip larger extents; kernel
default 256 KiB advisory per the man text, tool default 32 MiB), `-f` flush per file (bounds
dirty accumulation — the man's own ENOSPC warning), `--step SIZE` (chunked defrag with per-step
flush), `-c[algo]`/`-L level` compression-while-defrag (level per run), `--nocomp`. Every one of
these is a *scope* control so a deliberate defrag stays one file — they do not make defrag
safer for sharing.

---

## 6. Suspend/wake + APST hazard — the knobs that actually touch it

Host history: APST PS3 after 100 ms / PS4 after 2 s with PS5 gated (`docs/findings.md` `## nvme`,
settled), plus a measured freeze/wake-window record (`docs/findings.md` `## suspend-resume`;
`docs/NOTE.md` wake-window entries). Devices-sleep and reduce-wakeups are doctrine
(`docs/judgment.md:14-21`).

1. **Async discard is the standing trickle-vs-sleep question.** The `## fstrim` entry (settled,
   with the `discard=async` drift deliberately deferred) hypothesizes that async discard "would
   keep the device busy and fight APST" while upstream claims the batching is negligible. This
   research adds the missing mechanism: the trickle is **paced by `discard/iops_limit`
   (default 1000 ops/s → one work item every 1 ms floor), `kbps_limit`, `max_discard_size`, and
   the 120 s post-free delay** (§1.2). So the A/B the ledger asks for has concrete arms: e.g.
   `iops_limit` at default vs reduced vs `nodiscard`-equivalent (mount-side), measured by APST
   residency counters + idle-floor windows (screen-off, ≥ 15 min/arm, never spanning the eco
   converger's 600 s window — `docs/judgment.md:106-117`) + device `discardable_bytes` drain
   rate. Until that exists: **pointer + reopen condition only**; do not tune the pace by feel.
2. **Scrub vs suspend** (pointer): cancelled-at-suspend + `btrfs scrub resume` semantics rule
   the schedule shape — nothing to tune here; job caps (§5) do not change it.
3. **Background reclaim (`dynamic_reclaim`/`periodic_reclaim`) is a potential wakeup source.**
   The reclaim sweep and the periodic-ready gate run off kernel work, not user timers; turning
   either on (both 0 live) would add background churn with no measured need. Class (c): leave
   off; if ENOSPC/fragmentation ever makes reclaim relevant, measure wakeups first.
4. **NVMe APST parameters are frozen ground** (§4): `apst_*`, `force_apst`, and the `0x0c`
   hazard stay in `docs/findings.md` `## nvme` as the only rule home.
5. **Dirty-page batching affects wake shape, not just throughput** (§3): the longer the writeback
   interval (settled 60 s class) and the bigger the dirty caps, the fewer flusher wakeups — but
   the flusher burst is also the moment btrfs does its CoW write amplification; this is exactly
   why the writeback family's Open item is a J/min campaign, not another value tweak.

---

## 7. What NOT to do (never-run candidates in the tunables domain)

1. **Writing any `/sys/module/{nvme,nvme_core}/parameters/*` at runtime.** Probe-time or policy
   state; the APST-adjacent ones share the hazard class of `nvme set-feature -f 0x0c`
   (`docs/findings.md` `## nvme`).
2. **Relying on `scrub_speed_max`/`btrfs scrub limit` persistence.** It dies at unmount
   (btrfs-scrub(8)); a "limit" that vanishes silently is worse than no limit. Re-read after every
   mount: `btrfs scrub limit /`.
3. **Rate-capping jobs as an efficiency measure.** Capping turns one compact work window into a
   day-long trickle (anti race-to-sleep, `docs/judgment.md:14-21`); caps are for protecting
   interactivity only.
4. **Building on `btrfs scrub start -c/-n` (ionice).** Deprecated, and the man page's scheduler
   claim contradicts both kernel doc and kernel source (§2.1).
5. **Touching `allocation/*/chunk_size`, `read_policy`, `quota_override`, `features/extended_iref`,
   fs-wide `bg_reclaim_threshold`, `dynamic_reclaim`, `periodic_reclaim` without a traced consumer
   and a measured failure to fix.** Each is (a)-in-source or (c) with large blast radius (§1.3,
   §1.5); there is no defect on this host these would fix today.
6. **Turning off `iostats` or `write_cache` "for performance".** One blinds the re-check blocks
   (`docs/rollback.md`), the other changes flush semantics without a durability requirement.
7. **Treating `ionice`/`IOSchedulingClass=idle` as an energy tool** — at best it protects
   interactivity under mq-deadline/bfq; here it currently does nothing (§2.1).
8. **Re-proposing settled ledger knobs from this file**: scheduler `none`, `nr_requests=1023`,
   `read_ahead_kb=256`, `wbt_lat_usec=2000`, `vm.swappiness=150`, writeback centisecs,
   `default_ps_max_latency_us`, APST staging. Each is a pointer with a stated reopen condition
   (§9).

---

## 8. Re-check commands (tunables edition)

```
# btrfs sysfs surface + values
find /sys/fs/btrfs -maxdepth 4 -printf '%M %p\n' | sort
cat /sys/fs/btrfs/*/bg_reclaim_threshold
for t in data metadata system; do echo "== $t"; \
  paste -d' ' <(echo bg_reclaim_threshold chunk_size dynamic_reclaim periodic_reclaim) \
              <(cat /sys/fs/btrfs/*/allocation/$t/{bg_reclaim_threshold,chunk_size,dynamic_reclaim,periodic_reclaim}); done
cat /sys/fs/btrfs/*/discard/{iops_limit,kbps_limit,max_discard_size,discardable_bytes}
sudo btrfs scrub limit /                     # per-device scrub caps (none = '-')
cat /sys/fs/btrfs/*/devinfo/*/error_stats    # mirror of `btrfs device stats`

# block layer (arm identity for any IO experiment — read back from the consumer)
cat /sys/block/nvme0n1/queue/{scheduler,nr_requests,read_ahead_kb,max_sectors_kb,rq_affinity,nomerges,write_cache,io_poll,iostats,wbt_lat_usec}
cat /sys/block/nvme0n1/queue/iosched/*       # kyber targets (only valid while kyber active)
cat /sys/devices/virtual/bdi/btrfs-1/read_ahead_kb   # the *other* read-ahead knob

# module params (boot-time state; read-only)
cat /sys/module/nvme_core/parameters/{default_ps_max_latency_us,apst_primary_timeout_ms,apst_secondary_timeout_ms,force_apst,iopolicy}

# VM side (owners: see §3 — verify runtime values, never the files alone)
sysctl vm.dirty_bytes vm.dirty_background_bytes vm.dirty_expire_centisecs vm.dirty_writeback_centisecs \
       vm.vfs_cache_pressure vm.swappiness vm.zone_reclaim_mode
systemctl show 'beesd@*' -p IOWeight -p Nice -p IOSchedulingClass
```

---

## Recommendations (proposals, not adopted)

Nothing below is applied or claimed. Measurement column per `docs/judgment.md` `## May I claim?`.
"Owner decision" rows are state/policy questions, not measurements.

| Proposal | Expected effect (work-per-joule framing) | Risk | How to verify / measure before adopting |
|---|---|---|---|
| Resolve the io-stack drift: scheduler `none`+`nr_requests=1023` (ledger) vs live kyber+256 | The ledger's race-to-idle intent ("bursts drain immediately so the APST timer can start") is not what the queue currently implements | Hand-editing live sysfs gets reverted/discarded; wrong value set permanently would re-open refused territory | Owner decision first (`docs/rollback.md` `## Converge a change` or reopen `## io-stack`). If measured: fixed IO burst task (J/op via RAPL) + idle-floor windows + APST residency, arms = elevators, n ≥ 5/arm, interleave + rotate, discard rep 0; two-source arm identity (`queue/scheduler` + elevator dir contents) |
| Keep `scrub_speed_max` unlimited (default) and the shipped `Nice`/idle class as-is | Monthly pass finishes in minutes at full speed (compact work window) — maintenance fact, not a claim | Interactive slowdown during the pass if the owner is working | No measurement needed to *keep* it (maintenance); if a cap is ever wanted for interactivity, behavior-verify (scrub `Rate:` line shows the limit; wall time) and accept the longer awake window |
| Async-discard pacing A/B (arms: default `iops_limit=1000` vs reduced vs no-async) — only if the owner reopens `## fstrim` | Decides whether the async-discard worker extends device-awake time into idle (APST) or is free as upstream claims | Touching a settled/deferred knob without measurement | Idle-floor windows ≥ 15 min/arm (screen-off, never spanning the 600 s converger), APST residency counters, `discard/discardable_bytes` drain rate, fixed delete/write workload J/op; arm identity = the sysfs files + `/proc/mounts` |
| Record `vm.dirty_bytes`/`dirty_background_bytes` (and optionally `vfs_cache_pressure`) as *observed foreign state* in `docs/findings.md` `## writeback`/`## misc`, without changing them | Removes the "who owns this value" gap that bit this repo before (TLP clobber story) | None (record-only) | No measurement; maintenance fact. Re-check command above |
| Never-run list additions in the tunables domain (§7 items 1–6) | Prevents silent instability (APST wipe class) and vanished limits | None (refusals, not tunings) | None needed to record the ban; exceptions return only with new evidence (`docs/findings.md` preamble) |

---

## 9. Ledger-covered knobs — pointers only (do not re-propose)

| Knob | Ledger home | What new evidence would reopen it |
|---|---|---|
| IO scheduler `none`, `nr_requests=1023`, `read_ahead_kb=256`, `wbt_lat_usec=2000`, `max_sectors_kb=128` (MDTS) | `docs/findings.md` `## io-stack` (tunable; refusals recorded for read-ahead/nr_requests/WBT variants) | a measured A/B on the current kernel (n ≥ 5/arm) — plus, today, an owner ruling on the live kyber/256 drift (§0) |
| APST staging (PS3/PS4), `default_ps_max_latency_us=100000`, Gen3 x4, `set-feature 0x0c` hazard | `docs/findings.md` `## nvme` (settled) | PS5 unlock only if exit latency is ever measured; nothing else |
| Weekly `fstrim.timer` vs `discard` mount option; `discard=async` drift (deferred) | `docs/findings.md` `## fstrim` (settled; drift flagged Open) | the async-discard pacing A/B (§6.1 / Recommendations row 3) or an owner ruling |
| `vm.dirty_writeback_centisecs`/`expire` = 6000 | `docs/findings.md` `## writeback` (tunable; single-writer story) | its own Open item: quiet-machine idle-drain/wake-count campaign |
| `vm.swappiness=150` (zram) | `docs/findings.md` `## io-stack` (udev-enforced; ≥200 refusal measured) | essentially nothing on this host; zram swap is the mechanism |
| Scrub/balance/defrag **automation policy** (monthly scrub unit, trigger-only balance, never-defrag, bees throttling shape) | `docs/rollback.md` `## Storage ops` + `docs/findings.md` `## fstrim` | owner ruling; the sibling doc's policy transfer map |
| NOCOW/quota/RAID bans, mount options & on-disk features | `docs/rollback.md` `## Storage ops — never-run rules`; sibling doc §1–§8 | out of scope here, verbatim |

---

## Sources

All read 2026-10-05. `[verified]` = text read in this session; `[not retrieved]` = named source of
record, unreachable (see Unknowns).

**Repo doctrine** [verified]: `docs/judgment.md` (`## May I change?`:7-56, `## May I claim?`:58-133);
`docs/findings.md` (preamble policy labels; `## writeback`:222-256, `## io-stack`:267-288,
`## nvme`:290-314, `## fstrim`:316-357); `docs/rollback.md` (`## Storage ops` sections); sibling
`docs/research/btrfs-optimization.md` (mount-option/feature scope, policy rulings, §3 scrub
suspend semantics, §5 discard drift, §8 never-run list).

**Installed man pages** (btrfs-progs 7.1, dated Jul 15 2026; util-linux; systemd) [verified]:
`btrfs-scrub(8)` (start/-B/-r/-f/-d/--limit; `limit` subcommand + non-persistence; suspend
cancellation after v6.19; status file cadence; "Bandwidth and IO limiting" incl. the
cgroup2 `IOReadBandwidthMax` example and the `-c/-n` deprecation note),
`btrfs-balance(8)` (filters `usage=`/`limit=`/`convert=`/…, `--background`, `--enqueue`,
pause/resume/cancel, performance/ENOSPC warnings), `btrfs-filesystem(8)` (defragment options
`-s/-l/-t/-f/--step/-c/-L/--nocomp`, reflink-break warning; `du`; `label`),
`ionice(1)`, `ioprio_set(2)`, `systemd.resource-control(5)` (IOWeight→`io.weight`,
IORead/IOWriteBandwidthMax→`io.max`, IOLatencySec→`io.latency`, IOSchedulingClass),
`sysfs(5)`.

**Upstream kernel source and documentation** (`torvalds/linux@a90ee4305c4a`, read via GitHub API)
[verified]: `Documentation/block/ioprio.rst` (ioprio supported by bfq + mq-deadline),
`Documentation/block/kyber-iosched.rst` (`read_lat_nsec`/`write_lat_nsec` = target latencies),
`Documentation/admin-guide/sysctl/vm.rst` (dirty_bytes/ratio pairing + two-page minimum,
dirty_expire/writeback centisecs, swappiness incl. the zram >100 rationale,
vfs_cache_pressure(+denom), zone_reclaim_mode),
`Documentation/ABI/testing/sysfs-class-bdi` (per-BDI `read_ahead_kb`, ratio/bytes writeback
shares), `Documentation/ABI/testing/` directory listing (no `sysfs-fs-btrfs` entry exists),
`fs/btrfs/sysfs.c` (attribute implementations and store-validation comments for
`scrub_speed_max`, `chunk_size`, `bg_reclaim_threshold` per-type + fs-wide, `dynamic_reclaim`,
`periodic_reclaim`, `read_policy`/CONFIG_BTRFS_EXPERIMENTAL, `quota_override`, `commit_stats`),
`fs/btrfs/discard.c` (async-discard design comment; `iops_limit`/`kbps_limit`/`max_discard_size`
semantics and defaults), `fs/btrfs/space-info.c` (`btrfs_calc_reclaim_threshold`,
`do_reclaim_sweep`, urgent reclaim, `periodic_reclaim` gate),
`fs/btrfs/free-space-cache.c` (zoned-only consumer of the per-type threshold),
`block/mq-deadline.c` (`ioprio_class_to_prio`, per-prio queues, aging),
`block/blk-sysfs.c` (queue attribute stores: `nr_requests`, `max_sectors_kb`, `nomerges`,
`rq_affinity`, `write_cache`, `io_poll`, `iostats`), `block/blk-wbt.c` (WBT mechanism comment,
`min_lat_nsec`, 0 = off). Negative results also recorded: no `ioprio` usage in `block/kyber.c`
or `drivers/nvme/` [verified — code search, no matches].

**Live readbacks** (read-only, 2026-10-05) [verified]: `findmnt /`, `ls`/`find`/`cat` over
`/sys/fs/btrfs/**`, `/sys/block/nvme0n1/queue/**`, `/sys/devices/virtual/bdi/btrfs-1/**`,
`/sys/module/{btrfs,nvme,nvme_core}/parameters/**`, `sysctl` VM set + `/etc/sysctl.d` +
`/usr/lib/sysctl.d` ownership greps, `swapon --show`, `sudo btrfs scrub limit /`,
`systemctl show 'beesd@*'/'btrfs-scrub@*'`, `pacman -Q`.

**Explicitly not used:** blogs, benchmark roundups, ArchWiki. No energy or performance number in
this file is a measurement — every effect column is mechanism, and every claim path is the
`docs/judgment.md` protocol.

## Unknowns / unverified this session

- External HTTP was DNS-sinkholed during this pass: the **btrfs documentation site**
  (btrfs.readthedocs.io) could not be re-read; where its pages were already digested by the
  sibling doc, this file points there instead of restating.
- fs-wide `bg_reclaim_threshold`'s non-zoned consumer path (§1.3); `read_policy` value semantics;
  `quota_override`'s effect — all (c) until traced in `fs/btrfs/` on the shipping kernel.
- `nvme_core.apst_{primary,secondary}_*`, `iopolicy`, `disable_pi_offsets`: not present in any
  retrievable upstream doc/source; treated as boot-time policy (§4).
- `adios` elevator (listed by the live `scheduler` file): not researched.
- Host kernel `7.2.9` is newer than the indexed upstream source; the kyber/ioprio verdict is
  source-verified at that index and by kernel-doc, but a runtime check is required before
  relying on ionice behavior under any future elevator switch.
