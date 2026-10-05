# Btrfs optimization research — single-NVMe root on CachyOS

> **Status 2026-10-05:** the proposals below were ruled on by the owner — adopted rules now have their one home in `docs/rollback.md` (`## Storage ops`) and `docs/findings.md` (bees replaces the duperemove job; scrub, trigger-only balance and the §8 refusals recorded); this file stays as the evidence base.

*Research-only pass, 2026-10-05. No system state was changed; every live command below was
read-only. Scope: how to optimize and maintain **btrfs** as the root filesystem of this host
(ASUS Zenbook S 16 UM5606WA, Ryzen AI 9 HX 370, WD SN560 NVMe, CachyOS, kernel
`7.2.9-1-cachyos`), under the optimization criteria this repo already commits to.*

**This is research, not adopted tuning** — nothing here is applied, and nothing may be applied
without the repo change flow (`docs/rollback.md` `## Converge a change`) and the gates in
`docs/judgment.md` `## May I change?` (work per joule; race to sleep; never power caps or
throttling — `docs/judgment.md:7-12`) and `## May I claim?` (`docs/judgment.md:58-117`: a
measurement is a claim only when it clears the two gates; everything else in this file is
mechanism, proposal, or live readback, and is labeled as such).

**Why this file lives here.** `docs/research/btrfs-optimization.md` is the path the storage
runbook already names as pending (`docs/rollback.md:178`). The XFS-era sibling is retired to
`docs/archive/XFS-TUNING.md`; adopting its old `docs/<FS>-TUNING.md` campaign-doc slot would
re-create a convention that is being archived. This note is research (not yet a knob-ledger
entry in `docs/findings.md` and not yet a maintenance recipe in `docs/rollback.md`); when
proposals below are adopted, the durable rule gets exactly one home per the anchor rule
(`docs/MEMORY.md`, "Every rule has one doc home").

---

## 0. Live baseline (readback, 2026-10-05 — these are facts, not measurements)

Mount options, from `/proc/mounts` (the consumer readback — arm-identity rule,
`docs/judgment.md:98-104`), every subvolume identical:

```
rw,noatime,compress=zstd:1,ssd,discard=async,space_cache=v2
```

- **Layout** (`sudo btrfs subvolume list /`, `lsblk -f`): one device —
  `/dev/nvme0n1p2` (btrfs, 949.87 GiB), `/dev/nvme0n1p1` vfat `/boot`; plus an unrelated f2fs
  USB disk and zram swap. Subvolumes: `@` (`/`), `@home`, `@root`, `@srv`, `@cache`, `@tmp`,
  `@log` (`/var/log`), `@snapshots` (`/snapshots`), and snapper's `.snapshots/6..31` (~30
  snapshots) under `@`; `@snapshots` also holds `pre-home-restore-20261005` and a
  `baseline-home-restored-20261005` copy of `@`/`@home` (snapshot/reflink sharing is therefore
  large and load-bearing on this host).
- **Space** (`btrfs filesystem usage /`, `btrfs filesystem df /`): used 42.49 GiB of 949.87 GiB;
  `Data,single: 43.01 GiB total / 40.73 GiB used` (data ratio 1.00), `Metadata,DUP: 4.00 GiB /
  903.5 MiB` (metadata ratio 2.00), `System,DUP`, GlobalReserve 93.3 MiB. **Single-device:
  data has no redundancy; metadata does (DUP).**
- **Tooling** (`pacman -Q`, `command -v`, `systemctl list-timers`): `btrfs-progs 7.1-1`
  (ships `btrfs-scrub@.service` + `btrfs-scrub@.timer`, both present but **disabled/never run**);
  `duperemove`, `compsize`, `btrfsmaintenance` **not installed** (all available in the repos —
  install is an owner decision, not done here). `fstrim.timer` is enabled (stock systemd unit:
  `OnCalendar=weekly`, `AccuracySec=1h`, `RandomizedDelaySec=100min`, `Persistent=true`;
  next trigger Mon 2026-10-12 01:05). No `btrfs-scrub`/balance/dedupe automation is live.
- **Health readback** (`sudo btrfs scrub status /`, `sudo btrfs device stats /`): no scrub has
  ever run (`no stats available`, "Total to scrub: 42.49 GiB"); all five device-stat counters
  are 0.
- **IO stack context** (settled elsewhere): NVMe scheduler `none`, `max_sectors_kb=128` (drive
  MDTS), WBT 2000 µs — `docs/findings.md:267-288` (`## io-stack`); APST PS3/PS4 with PS5 gated,
  Gen3 x4 — `docs/findings.md:290-314` (`## nvme`).

**Drift flag (live vs ledger, owner decision needed):** the live mounts carry `discard=async`
(installer default; since kernel 6.2 btrfs enables it by default on capable devices —
btrfs(5) "discard, discard=sync, discard=async, nodiscard"), while the settled knob entry says
"the `discard` mount option is rejected; continuous `discard=async` would keep the device busy
and fight APST" (`docs/findings.md:316-347` `## fstrim`, class **settled**, "do not re-propose
without new evidence"). This is discussed in §5 and in the recommendation table; resolving it
means either converging the mount back to `nodiscard` or formally reopening `## fstrim` with
measurement. Live state is not evidence either way (`docs/judgment.md:106-117`).

---

## 1. Compression (compress=zstd / lzo / none)

**Mechanism, what primary sources actually say.** Btrfs compresses file extents transparently;
data are split into 128 KiB chunks before compression so random rewrites stay possible; chunks
compress in parallel; **metadata consumption is higher** because of the increased extent count
(https://btrfs.readthedocs.io/en/latest/Compression.html). Algorithm trade-offs, same source:
ZLIB "slower, higher compression ratio"; LZO "faster … worse compression ratio, designed to be
fast"; ZSTD "comparable to ZLIB with higher compression/decompression speeds and different
ratio". Levels: ZSTD 1..15 (−15..−1 since 6.15), default 3; **"levels 1..3 are near real-time
with good compression, 4..8 are slower with improved compression and 9..15 try even harder
though the resulting size may not be significantly improved"** and "higher levels also require
more memory and as they need more CPU the system performance is affected"
(https://btrfs.readthedocs.io/en/latest/Compression.html, "Compression levels").

**The ratio/CPU question has no primary universal number.** The wiki states plainly: "The
differences depend on the actual data set and cannot be expressed by a single number or
recommendation. Higher levels consume more CPU time and may not bring a significant improvement,
lower levels are close to real time." (`Compression.html`.) The measurable proxy on this host is
`compsize` (package `compsize 1.5-2`, not installed here) per tree, and wall/J counters per §9.
Any ratio number in a later writeup must come from this host's own `compsize`/write tests, not
from folklore.

**compress vs compress-force (worth pinning).** Plain `compress` applies heuristics: "If the
first blocks written to a file are not compressible, the whole file is permanently marked to
skip compression"; `compress-force` "will compress most of the files at the cost of some wasted
CPU cycles on failed attempts" (btrfs(5), "compress, compress-force", btrfs-progs 7.1 man
page). Since 4.15 the heuristics use "frequency sampling, repeated pattern detection and
Shannon entropy" (same section). The wiki is explicit: **"Using the forcing compression is not
recommended, the heuristics are supposed to decide that"**; a file marked incompressible gets a
sticky NOCOMPRESS flag (`chattr +m`), and fallocate-touched files are always excepted from
compression even under force (https://btrfs.readthedocs.io/en/latest/Compression.html,
"Incompressible data", "Exceptions"). Also pin: compression options are **filesystem-wide** —
"only options in the first mounted subvolume will take effect … you can't set per-subvolume
`nodatacow`, `nodatasum`, or `compress` using mount options" (btrfs(5), MOUNT OPTIONS note);
surgical per-file policy is `btrfs property set <file> compression zstd` (level not settable
that way — `Compression.html`).

**Live state:** `compress=zstd:1` is already the near-real-time end of the ZSTD range — the
race-to-sleep-consistent choice per the level guidance above; going to `zstd:3+` trades CPU
time for ratio and is not free under the doctrine.

**Energy framing (explicit gap).** No primary source quantifies joules for btrfs compression;
kernel docs and the wiki quantify neither energy nor SSD write amplification. The mechanism is
directionally favorable — less host write traffic means less device work and fewer NAND
program/erase cycles (the Trim page frames device cell lifetime and firmware-level relocation as
the wear mechanism, https://btrfs.readthedocs.io/en/latest/Trim.html) — but "compression saves
energy" is a **proposal, not a claim**, until a RAPL work-per-joule A/B clears
`docs/judgment.md:58-87`. Note the counterweight: CPU cycles spent compressing at write time,
and decompression on every read of compressed data (compressed data falls back to buffered
reads for O_DIRECT readers — `Compression.html`, "Compatibility"). For a *write-heavy* fixed
task the J/work delta is the thing to measure; the read-side cost is part of the workload and
must be inside the measured task (same-input rule, `docs/judgment.md:63-76`).

---

## 2. Copy-on-write + reflink/dedupe vs NOCOW

**How dedupe reaches the kernel.** Btrfs provides only **out-of-band** deduplication; tools
find candidates and call the kernel ioctl
(https://btrfs.readthedocs.io/en/latest/Deduplication.html). `duperemove -d` "will submit those
regions for deduplication using the Linux kernel FIDEDUPERANGE ioctl" and "only works on btrfs
and xfs" (duperemove man page, http://markfasheh.github.io/duperemove/duperemove.html — the
tool's own doc). The ioctl semantics: exact-match only — "If even a single byte in the range
does not match, the deduplication request will be ignored"; the kernel locks the pages and
compares byte-by-byte before sharing; shares are ordinary COW-shared extents ("If a file write
should occur to a shared region, the filesystem must ensure that the changes remain private");
no overlapping ranges within one file on btrfs/XFS; swap files cannot share
(`ioctl_fideduperange(2)`, https://man7.org/linux/man-pages/man2/ioctl_fideduperange.2.html).
The wiki confirms the safety story: blocks "are compared byte by byte and not using any
hash-based approach" (`Deduplication.html`, "Safety of block comparison").

**Incremental dedupe (the retired daily job) transfers cleanly.** duperemove's `--hashfile`
"will only compute hashes for those files which have changed since the last run" (duperemove
man, OPTIONS `--hashfile`) — the same incremental mechanism the XFS-era
`duperemove-daily.sh` used (hashfile `/var/lib/duperemove/root.hash`, daily 03:30 —
`docs/rollback.md:124-128`). Tool-state caveats stay with it: run as root (it silently scans
0 files otherwise), never concurrent on one hashfile, `--read-hashes` is the wrong format,
dedupe self-reports are estimates and free-space lags ("It is common for space reporting to be
'behind' … bookending") — `docs/findings.md:316-347` (`## fstrim`, Machine lies) and duperemove
man FAQ. The btrfs-native accounting replacement for the XFS-era `poff` physical-offset check is
`btrfs filesystem du` ("total … shared … set shared" via FIEMAP — btrfs-filesystem(8),
"du", btrfs-progs 7.1) plus `btrfs filesystem df /` before/after.

**NOCOW costs (all primary-sourced).**

- `nodatacow` **implies `nodatasum` and disables compression**; files created under it get the
  NOCOW attribute (btrfs(5), "datacow, nodatacow" / "datasum, nodatasum"). With compression
  enabled (our live state), `nodatacow`/`nodatasum` are disabled — the two policies are
  mutually exclusive per file ("If compression is enabled, `nodatacow` and `nodatasum` are
  disabled", btrfs(5)).
- Scrub does **not** validate NOCOW file data: "setting the NOCOW file attribute (by `chattr
  +C`) on a file implicitly enables NODATASUM … the actual file data is not [validated]"
  (btrfs-scrub(8) WARNING; identical text at https://btrfs.readthedocs.io/en/latest/Scrub.html).
  On this host's single-device `Data,single` profile that trades the one integrity mechanism
  data has (checksums) for in-place-write performance. The trade is real but narrow: "Updates
  in-place improve performance for workloads that do frequent overwrites, at the cost of
  potential partial writes, in case the write is interrupted (system crash, device failure)"
  (btrfs(5), "datacow").
- Dedupe/reflink require **matching COW status**: "Files that are subject to deduplication must
  have the same status regarding COW" (`Deduplication.html`, "Limitations, compatibility"); a
  NOCOW source cannot reflink to a COW target and vice versa (https://btrfs.readthedocs.io/en/latest/Reflink.html).
  A mixed tree therefore cannot be deduped as one pool.
- Notable defaults to know: **systemd sets `+C` on journal files by default** and libvirt ≥ 6.6
  on pool dirs (btrfs-scrub(8) WARNING) — journald data on `@log` is (a) unchecksummed and (b)
  outside any dedupe benefit; that is accepted behavior, not a defect to "fix".

**Is NOCOW advisable for databases/VM images *here*?** The primary sources give the mechanism
but no host-specific verdict. VM images are the classic dedupe/reflink beneficiary and the
duperemove man page even names "virtual machines etc" as the `--batchsize=1` case; snapshotting
VM images via `cp --reflink` requires COW files. The repo's load-bearing value is sharing
(recovered ~65 GiB on the XFS-era sweep — `docs/findings.md:316-347`), and this host now holds
~30 snapshots plus two full backup subvolumes; a NOCOW island forfeits checksums, compression
and pool-wide dedupe. **Proposal shape (not adopted):** keep everything COW+compressed by
default; only a specific file proven (measured) to be write-amplification-bound (a hot DB
journal class of file) becomes `chattr +C`, with the checksum/compression/dedupe costs accepted
in writing. Per-file, never mount-wide `nodatacow` (see §8).

---

## 3. Scrub — the online-verification replacement for xfs_scrub

**Semantics.** "Scrub is a validation pass over all filesystem data and metadata that detects
data checksum errors, basic super block errors, basic metadata block header errors, and disk
read errors" — run per-device or per-path (all devices in parallel); on replicated profiles it
auto-repairs from good copies (btrfs-scrub(8), btrfs-progs 7.1; same text at
https://btrfs.readthedocs.io/en/latest/Scrub.html). This is the same duty the retired
`xfs_scrub -v /` monthly job performed (`docs/rollback.md:121-136`), so **scrub is the correct
transplant for monthly online verification**. Scoping note for this host: with `Data,single`
there is **no good data replica to repair from** — scrub *detects* data corruption but can only
auto-repair metadata (DUP); auto-repair needs "another valid copy" (https://btrfs.readthedocs.io/en/latest/Auto-repair.html).
Detection is still the point: it converts silent corruption into a logged, actionable event.

**Cadence and cost (primary numbers).** "The recommended period is a month but it could be
less. The estimated device bandwidth utilization is about 80% on an idle filesystem."
(btrfs-scrub(8) / Scrub.html). For a 42.49 GiB used filesystem that is minutes of IO at NVMe
speeds, not an endurance event; it is read-dominated (verification), with writes only where a
replica is repaired. Status lands in `/var/lib/btrfs/scrub.status.UUID` and is updated every 5 s
(Scrub.html) — the re-check surface (§9).

**Suspend interaction (directly relevant to this host).** "Scrub can be interrupted by various
events after v6.19 kernel, including but not limited to power management suspend/hibernate …
The running scrub will be cancelled after such interruption, and can be resumed by `btrfs scrub
resume`" (btrfs-scrub(8), Note; Scrub.html). This kernel is 7.2.9, so this applies: a scrub that
straddles a suspend is *cancelled*, and only a `scrub resume` (or a re-run) finishes the
verification pass. Any schedule must therefore (a) prefer windows where no suspend is expected,
and (b) make the re-check block notice a cancelled/postponed scrub (§9). This is the storage
analogue of the wake-window discipline the suspend/resume work taught us (`docs/findings.md:634`
ff. `## suspend-resume`; the resume-window SMU/EC contention chain in `docs/NOTE.md`
`## 2026-09-29 — recurrence 21:14 …`): maintenance must never be in flight during the
suspend-entry or the first minute after wake.

**What ships on Arch (verified live).** `btrfs-progs 7.1-1` ships `btrfs-scrub@.service` +
`btrfs-scrub@.timer` (`pacman -Ql btrfs-progs`); the template unit is:

```
[Service] Nice=19, IOSchedulingClass=idle, KillSignal=SIGINT,
          ExecStart=/usr/bin/btrfs scrub start -B %f
[Timer]   OnCalendar=monthly, AccuracySec=1d, RandomizedDelaySec=1w, Persistent=true
```

(`%f` = the instance, i.e. the mount point; enable as `btrfs-scrub@-.timer` for `/`.)
`btrfsmaintenance` (extra package, not installed) is the upstream *scripts* alternative with
scrub/balance/trim timers; it is not needed if the btrfs-progs template suffices. The
`xfs_scrub*` units still present on disk come from xfsprogs and are inert for a btrfs root —
do not enable them. Note `RandomizedDelaySec=1w` spreads the monthly run over a wide window;
if the owner wants a *predictable* idle window, a repo-owned unit modeled on the retired
`xfs-scrub.timer` (`OnCalendar` first-week 05:00 + `RandomizedDelaySec=2h`, `Nice`/ionice,
`Persistent=true` — `docs/rollback.md:121-136`) is the closer analog.

**Throttling caveat (matches our IO stack).** "The ionice(1) may not be generally supported by
all IO schedulers" — since CFQ is gone, cgroup v2 IO controller or the btrfs-specific
`/sys/fs/btrfs/FSID/devinfo/DEVID/scrub_speed_max` are the real tools (btrfs-scrub(8),
"Bandwidth and IO limiting"). With the host's `none` scheduler (`docs/findings.md:267-288`),
`IOSchedulingClass=idle` on the shipped unit is likely inert; `Nice=19` still deprioritizes the
CPU-side verification. Do not *add* speed caps as a default: a rate-capped trickle is the
anti-pattern of race-to-sleep (`docs/judgment.md:14-21`) — let the minutes-long pass finish at
full speed in an idle window instead.

---

## 4. Balance — when (if ever) on a single device

**Balance does not break sharing (contrast with defrag).** Primary text, twice: "Balance works
only on a mounted filesystem. **Extent sharing is preserved and reflinks are not broken.** Files
are not defragmented nor recompressed, file extents are preserved but the physical location on
devices will change." (btrfs-balance(8), DESCRIPTION, btrfs-progs 7.1; identical text at
https://btrfs.readthedocs.io/en/latest/Balance.html). So a balance does **not** un-do duperemove
the way defrag does — the never-defrag rule (§6) does not extend to balance on that ground.

**But cost and need are real.** "Balancing operations are very IO intensive and can also be
quite CPU intensive, impacting other ongoing filesystem operations" (btrfs-balance(8),
"Performance implications"); an unfiltered balance "will take a lot of time as it basically move
data/metadata from the whole filesystem" and needs free workspace or it reports ENOSPC
(btrfs-balance(8) WARNING + Note; Balance.html, "Balance does not have enough workspace" trouble
entry). The primary purpose is multi-device: "spread block groups across all devices so they
match constraints defined by the respective profiles" (btrfs-balance(8)) — **there is nothing to
spread on a single NVMe**. What remains useful is the `usage` filter: compacting partially used
block groups ("Chunks utilized up to 50% can be relocated … basically only moved" beyond that —
Balance.html examples) and `usage=0` to clean fully-empty block groups when ENOSPC appears
despite free space.

**Free-space fragmentation reality.** Btrfs allocates in block groups and can report ENOSPC
while `df` shows free space (trouble page: "Space handling on a COW filesystem is tricky …
dynamic chunk allocation"; https://btrfs.readthedocs.io/en/latest/trouble-index.html,
"Error: No space left on device (ENOSPC)"). With ~4% used on a 950 GiB device and ~898 GiB
unallocated (§0), that state is far away today. So: **no scheduled balance.** Trigger-based
only: (a) `btrfs filesystem usage /` shows unallocated-but-unusable space or chunk-level
ENOSPC; (b) a metadata-conversion or device add/replace needs it. A `usage`-filtered,
chunk-limited (`limit=`) balance is the surgical form (Balance.html, filter list).

**Never-run candidate:** unfiltered `btrfs balance start /` on a timer — full-device rewrite
(IO + CPU + write amplification) for a condition this host does not have; and balance of
`system`/redundancy-reducing conversions needs `-f` on purpose (btrfs-balance(8)).

---

## 5. TRIM/discard: fstrim.timer vs `discard=async`

**The three mechanisms (primary).** (1) `discard`/`discard=sync`: trim immediately on free —
"lack of asynchronous queued TRIM on the backing device TRIM can severely degrade performance,
because a synchronous TRIM operation will be attempted instead"; (2) `discard=async`: freed
extents "are first tracked in memory and after a period or enough ranges accumulate the trim is
started, expecting the ranges to be much larger and allowing to throttle the number of IO
requests which does not interfere with the rest of the filesystem activity … The overhead and
performance impact should be negligible compared to the previous mode and it's supposed to be
the preferred mode if needed"; (3) `fstrim`: batch over all free space, "suitable for running it
as periodic service", and scheduling it "during a period of low system activity will prevent
latent interference"; also, "a device may ignore the TRIM command if the range is too small, so
running a batch discard has a greater probability of actually discarding the blocks"
(btrfs(5), "discard…", btrfs-progs 7.1; https://btrfs.readthedocs.io/en/latest/Trim.html).
Since 6.2 btrfs enables `discard=async` by default on capable devices (btrfs(5), same section).
"The trim is considered only a hint to the device … Running trim periodically could prevent
[internal relocation] too" (Trim.html) — i.e. periodic trim has a role even alongside async.

**The two knobs are complementary in upstream's design** — async handles the steady trickle,
`fstrim.timer` (weekly, stock systemd unit with `RandomizedDelaySec=100min`, verified live)
sweeps the residue in one batched window. That is materially different from the XFS-era
`discard` mount option ("performance impact … quite severe" per the XFS admin guide), which is
what the settled rejection in `docs/findings.md:316-347` was reasoned from. The ledger's
second clause — "`discard=async` would keep the device busy and fight APST" — is a hypothesis
about this host's APST behavior (`docs/findings.md:290-314`: PS3 after 100 ms, PS4 after 2 s),
not a measurement; upstream claims the async batching "does not interfere with the rest of the
filesystem activity".

**Doctrine read.** Energy-wise, weekly batch trim is one short periodic wake doing bulk work
(fewer wakeups — `docs/judgment.md:14-21`); async trim spreads small throttled trims across the
day and can extend drive-awake time into idle (devices-sleep rule, `docs/judgment.md:14-21`).
Which wins is **not decidable from the sources** — it depends on how often the batched windows
actually fire under this workload, which is observable (tracepoints/`nvme` smart counters) but
not yet observed here. Until measured: do not touch either side casually. The live
`discard=async` drift (§0) needs an explicit owner ruling: keep upstream default (reopening
`## fstrim` with new evidence) or converge to `nodiscard` (settled policy enforced). Note the
XFS-era ban on *sync* discard transfers as-is and is not in dispute.

---

## 6. autodefrag vs the never-auto-defrag policy

**What autodefrag actually does.** "When enabled, small random writes into files (in a range of
tens of kilobytes, currently it's 64KiB) are detected and queued up for the defragmentation
process. May not be well suited for large database workloads. The read latency may increase due
to reading the adjacent blocks that make up the range for defragmentation" (btrfs(5),
"autodefrag, noautodefrag", btrfs-progs 7.1; default **off**). Crucially, the very same man
section carries the reflink warning: defragmentation "will break up the reflinks of COW data
(for example files copied with `cp --reflink`, snapshots or de-duplicated data). This may cause
considerable increase of space usage". The wiki states it flatly: "Defragmentation does not
preserve extent sharing, e.g. files created by `cp --reflink` or existing on multiple
snapshots" (https://btrfs.readthedocs.io/en/latest/Defragmentation.html); btrfs-filesystem(8)
"defragment" carries the same warning ("break up the reflinks of COW data … considerable
increase of space usage").

**Conflict assessment.** Yes — `autodefrag` is structurally incompatible with this repo's
never-auto-defrag rule (`docs/rollback.md:151-168`: defrag "destroys reflink sharing … undoing
exactly what duperemove bought"; no automatic defrag, ever). An autodefrag-triggered rewrite is
an *automatic defrag* the repo cannot schedule, audit, or scope, and it would silently un-share
data across the ~30 snapper snapshots and the `@snapshots` backups as well as across duperemove
extents. Extra CoW cost: each queued 64 KiB-range rewrite is a fresh copy (write amplification)
plus the read of adjacent blocks the man page warns about. **Proposal: keep `autodefrag` off
forever and add it to the never-run list** — it is already off by default and absent from live
mounts (§0); the only action needed is to record the rule when the never-run section is
rewritten.

---

## 7. Scheduling heuristics (race-to-sleep + suspend-window hygiene)

**What the repo already fixed (cite, don't restate as new):** duperemove-daily at 03:30 daily
with `Persistent=true`; the retired xfs-scrub unit ran `Nice=10` + best-effort/ionice 7 in the
first week of the month at 05:00 with `RandomizedDelaySec=2h` (`docs/rollback.md:121-136`);
smartd's weekly short self-test is Sunday 04:00 (`docs/rollback.md:133-145`); fstrim lands
randomized within 100 min after its weekly slot (stock unit, §0).

**Doctrine-derived heuristics for the btrfs jobs:**

1. **Compact the work, don't trickle it.** Race-to-sleep: a scrub/dedupe/balance pass should
   finish quickly at full speed and then leave everything idle — heavy IO is a real idle-floor
   cost, so it belongs in one bounded window, not rate-capped into a day-long hum
   (`docs/judgment.md:14-21`; the anti-pattern framing is the doctrine's own). `Nice`/ionice
   protect *interactivity if the owner is present*; they are not an efficiency tool, and on the
   `none` scheduler ionice is likely inert (§3).
2. **Window choice.** Plugged-in (AC), idle, screen-off windows — and never near the
   suspend-entry/resume zone. This host has a measured history of wake-window contention
   (SMU/EC/AMDGPU chain — `docs/findings.md:634` ff.; `docs/NOTE.md` `## 2026-09-29 — recurrence
   21:14 …`), and kernel ≥ 6.19 cancels a running scrub at suspend (§3). Timers with
   `Persistent=true` fire their make-up runs at/after boot — exactly the fragile window — so a
   make-up run should be deferrable (the shipped scrub timer's `RandomizedDelaySec=1w` is
   blunt but does spread it; a repo unit can encode "first Sunday 05:00 + random 2h" like the
   xfs-scrub precedent).
3. **Collision map to keep:** smartd self-test Sun 04:00, fstrim randomized ~Mon 01:05±100 min,
   (proposed) scrub monthly in a fixed early window, (proposed) duperemove daily 03:30 as
   before. The missing constraint is **AC**: a laptop that suspends at 03:30 runs nothing;
   make-up runs then hit the boot/wake window. A small wrapper that skips/defers unless
   `/sys/class/power_supply/AC0/online` is 1 (with the known EC misread caveat —
   `docs/rollback.md:38-46`) is the honest way to express "idle plugged-in windows", and is an
   owner decision because it changes automation semantics.
4. **Scrub/balance vs dedupe order:** balance preserves sharing (§4), defrag destroys it (§6);
   so the only forbidden adjacency is defrag-after-dedupe. Running dedupe and scrub back-to-back
   is merely IO-heavy — fine inside one compact night window if the job design keeps the window
   bounded.
5. **Wakeups rule** (`docs/judgment.md:14-21`): prefer one nightly/weekly/monthly oneshot over
   polling; the eco converger's 600 s backstop is unrelated but the converger window must never
   straddle a short measurement (`docs/judgment.md:106-117`) — same rule applies to any future
   J/work measurement of storage jobs.

---

## 8. What NOT to do — never-run candidates for btrfs

Each with primary backing:

1. **`btrfs check --repair` on the mounted root (or at all without expert guidance).** "It is
   recommended to unmount the filesystem prior to running the check"; "Do not use `--repair`
   unless you are advised to do so by a developer or an experienced user" (btrfs-check(8),
   DESCRIPTION + WARNING, btrfs-progs 7.1). Already policy-adjacent in
   `docs/rollback.md:151-158` ("filesystem repair: offline only"); scrub, not check, is the
   scheduled online verification (§3).
2. **Any automatic defrag — `btrfs filesystem defrag -r /`, `autodefrag` mount option.** Breaks
   reflink/dedupe/snapshot sharing (btrfs-filesystem(8) warning; Defragmentation.html) —
   policy: `docs/rollback.md:160-168`.
3. **Unfiltered `btrfs balance start /` on a schedule.** Whole-filesystem rewrite, very IO+CPU
   intensive, needs workspace (btrfs-balance(8) WARNING/Performance); single device has no
   layout to fix (§4).
4. **RAID5/RAID6 profiles.** "There are some implementation and design deficiencies that make
   it unreliable for some corner cases and the feature should not be used in production, only
   for evaluation or testing. The power failure safety for metadata with RAID56 is not 100%." —
   including the unjournaled "write hole" (btrfs(5), "RAID56 STATUS AND RECOMMENDED PRACTICES",
   btrfs-progs 7.1). Moot on one device today; never convert to it.
5. **`btrfs quota enable` (qgroups) unless a real limit is wanted.** "When quotas are activated,
   they affect all extent processing, which takes a performance hit. Activation of qgroups is
   not recommended unless the user intends to actually use them." (btrfs-quota(8), "STABILITY
   AND PERFORMANCE IMPLICATIONS"). Snapshot-tidying tools that want qgroups (snapper quotas)
   inherit that cost — owner decision, measured before adoption.
6. **Mount-wide `nodatacow`/`nodatasum`.** Implies loss of data checksums and disables
   compression (btrfs(5)); on `Data,single` it removes scrub's ability to even *detect* data
   corruption for those files (btrfs-scrub(8) WARNING). Per-file `chattr +C` only, with the §2
   costs on the record.
7. **`discard` / `discard=sync` mount option.** Severe performance degradation without queued
   TRIM (btrfs(5), "discard…"). Not in dispute even though `discard=async` is (§5).
8. **`compress-force` as the default.** "Using the forcing compression is not recommended"
   (Compression.html) — wasted CPU cycles on incompressible data; `compress` heuristics plus
   `chattr +m`/properties are the right tools (§1).
9. **Rate-capping scrub by default.** Not a safety rule but a doctrine rule: capped trickle =
   longer awake time (§3, §7). Limits exist (`scrub_speed_max`, cgroup IO) for interactive
   protection only.
10. **The standing NVMe hazards stay**: `nvme set-feature -f 0x0c` wipes the APST table
    (`docs/findings.md:290-314`), and no firmware/PS5 fiddling in the name of storage tuning.
11. **Trust `df`/duperemove self-reports for savings claims.** "Space reporting [is] 'behind'"
    and bookending leaves partially deduped extents (duperemove man FAQ); use
    `btrfs filesystem du`/`df` deltas and the two-gates protocol before any claim
    (`docs/judgment.md:78-87`).

---

## 9. Re-check commands (btrfs replacement for the storage re-check block)

`docs/rollback.md:170-180` marks this block as pending this document. Proposal (supersedes the
XFS-era block in `docs/archive/XFS-TUNING.md`; `nvme`/`smartctl` lines are filesystem-agnostic
and stay as-is):

```
df -h / ; df -i /                          # capacity + inodes (df lags after dedupe — see below)
btrfs filesystem usage /                   # chunk-level truth: unallocated vs usable
btrfs filesystem df /                      # profile totals (Data single / Metadata DUP)
sudo btrfs scrub status /                  # last run, errors, unfinished/cancelled state
sudo btrfs device stats -c /               # all-zero check (exit 64+ if nonzero)
sudo btrfs subvolume list /                # layout + snapshot inventory drift
findmnt -no OPTIONS /                      # compress=zstd:1; NO autodefrag; discard policy per owner ruling
nvme smart-log /dev/nvme0 | grep -iE 'percentage_used|available_spare|media_errors|temperature'
smartctl -H /dev/nvme0                     # overall health
systemctl list-timers --all | grep -E 'btrfs|fstrim|duperemove|smartd'
journalctl --disk-usage
```

Notes to carry with it: `btrfs scrub status` on a filesystem with **no run yet** prints
"no stats available" (current state, §0) — after the first scheduled run it must show a
completed pass with `Error summary: no errors found`; a scrub cancelled by suspend shows a
non-completed status and needs `btrfs scrub resume` (§3). Dedupe savings are measured by
`btrfs filesystem du <tree>` (shared/set-shared) and `btrfs filesystem df /` deltas — never by
duperemove's printed estimate and never immediately after the run (`docs/findings.md:316-347`
Machine lies). `btrfs device stats` counters (write/read/flush_io_errs, corruption_errs,
generation_errs) are the btrfs-side mirror of the nvme media-error line (btrfs-device(8),
"stats", `--check` returns bit-set exit codes for scripting).

## Policy transfer map — `docs/rollback.md` storage ops → btrfs

| XFS-era policy (`docs/rollback.md:121-180`) | Transfer verdict |
|---|---|
| duperemove incremental dedupe, daily 03:30 (hashfile, Nice/ionice) | **Transfers as-is mechanically** (FIDEDUPERANGE works on btrfs; incremental hashfile unchanged — §2), but tool+units are currently *not installed* (reinstall is an owner decision) and the AC/idle gating question is open (§7) |
| weekly `fstrim.timer` | **Transfers as-is** (enabled live; btrfs fstrim works without mount options — Trim.html). Paired question: live `discard=async` vs settled `## fstrim` (§0, §5) |
| smartd weekly self-test + alerting | **Transfers unchanged** (device-level, not filesystem-level — `docs/rollback.md:133-145`) |
| monthly online scrub (`xfs_scrub`) | **Needs btrfs equivalent:** `btrfs scrub start -B /` monthly — ship the btrfs-progs `btrfs-scrub@.timer` or a repo unit in the xfs-scrub time shape (§3) |
| never auto-defrag (xfs_fsr era) | **Transfers unchanged and strengthens:** btrfs defrag breaks snapshot sharing too; `autodefrag` joins the ban (§6) |
| `xfs_repair` never on mounted root | **Obsolete wording, same rule:** `btrfs check --repair` never on mounted root / without expert guidance (§8.1) |
| re-check block (`xfs_info … reflink`) | **Replaced** by the block in §9 |
| — (new for btrfs) | balance is trigger-only, never scheduled (§4); quota/RAID56/nodatacow/`compress-force`/`discard=sync` bans (§8) |

---

## Recommendations (proposals, not adopted)

None of the following is applied or claimed. Each row's "measure" column is the only path to a
claim, per `docs/judgment.md` `## May I claim?` (two gates in order, n ≥ 5 per arm, interleave +
rotate, discard rep 0, read back the arm from the consumer — `docs/judgment.md:78-104`).

| Proposal | Expected effect (work-per-joule framing) | Risk | How to measure before adopting |
|---|---|---|---|
| Keep `compress=zstd:1` as-is (level 1 is the near-real-time band) | Fewer bytes to the NVMe per unit of write work → less device energy per J of *useful* work, at small CPU cost (mechanism only — §1) | CPU cost on incompressible data (mitigated by heuristics); read-side decompression is part of the workload | Fixed write+read workload, RAPL `measure-power.sh` J/op, `compress=zstd:1` vs `compress=no` arms (remount arms, read back via `/proc/mounts`), n ≥ 5/arm, Gate 1 = effect outside control spread, Gate 2 = MW-U p < 0.05; `compsize` per tree for the ratio side |
| Resolve the `discard=async` drift: either converge mounts to `nodiscard` (settled policy) or reopen `## fstrim` for a measured A/B | Decides whether idle-time TRIM trickle extends drive-awake time (devices-sleep rule) or whether async batching is free as upstream claims | Touching mount options changes live behavior of a settled knob without measurement | Owner ruling first (settled vs reopen). If measured: idle-floor windows (screen-off, ≥ 15 min/arm, never spanning the 600 s converger — `docs/judgment.md:106-117`) + APST residency counters + a fixed delete/write workload's J/op; two-source arm identity (`/proc/mounts` + kernel default readback) |
| Monthly `btrfs scrub` (btrfs-progs `btrfs-scrub@-.timer` or a repo unit in the retired xfs-scrub time shape, first-week early-morning + `RandomizedDelaySec=2h`, `Persistent=true`, `Nice`) | Restores the lost online-verification duty at minutes of IO per month on 42 GiB used; compact window = race-to-sleep | Make-up runs land at boot/wake (fragile window — §7); scrub cancelled by suspend needs resume | Not an efficiency claim — maintenance (measurement optional per `docs/judgment.md:58-62`). Verify behavior instead: run once manually, confirm `scrub status` completes with 0 errors; confirm a suspend mid-scrub shows cancelled and `scrub resume` completes it |
| Reinstall duperemove + daily incremental timer (hashfile `/var/lib/duperemove/root.hash`, 03:30 shape), optionally with AC-gating wrapper | Re-buys the ~65 GiB-class sharing win on the btrfs tree; incremental daily keeps per-night work small (compact, low-nice window) | Quadratic identical-file groups (87k-member precedent); hashfile semantics pitfalls; a dedupe pass is real IO+CPU | Owner decision to install first. Measure with `btrfs filesystem du` deltas (never self-report); J/op of the dedupe pass itself via RAPL to size the window; exclude known-bad trees as before (`docs/findings.md:316-347`) |
| Never-run list additions: `autodefrag`, unfiltered scheduled balance, RAID5/6, mount-wide nodatacow, qgroups-by-default, `compress-force`, `discard=sync`, `btrfs check --repair` online | Prevents un-measured write amplification and loss of the sharing/checksum/compression stack — negative risk, zero cost | None (these are refusals, not tunings) | None needed for recording the ban; any future exception returns only with new evidence (`docs/findings.md` "Do not re-propose without new evidence") |
| Balance: trigger-only, `usage`-filtered + `limit=` when chunk ENOSPC or unallocated-but-unusable appears in `btrfs filesystem usage` | Avoids a scheduled whole-device rewrite (huge J cost, no work needed on one device) | Deferred maintenance myth: chunk fragmentation can strand space when the fs gets full | Adopt as maintenance policy (not a measurement); if ever used, record before/after `btrfs filesystem usage` and job wall time; sharing must be checked unchanged via `btrfs filesystem du` (balance promises it — §4) |
| Schedule all heavy storage work in plugged-in idle windows away from suspend/resume; keep smartd Sun 04:00 / fstrim Mon ~01:05 shape | One compact awake window beats an all-night trickle (race to sleep); zero contention with the measured wake-window hazard | AC-gating adds wrapper semantics; timers may drift if the lid is closed | Behavior verification (journal timestamps vs suspend events), not a power claim; if a power claim is wanted: idle-drain windows with/without job, ≥ 15 min/arm, per `docs/judgment.md` run-design |

## Sources

Primary sources (all read 2026-10-05):

- `docs/judgment.md` (`## May I change?`:7-56, `## May I claim?`:58-133) — doctrine and claim gates.
- `docs/rollback.md` (`## Storage ops — what runs automatically`:121-149, `## Storage ops — never-run rules`:151-168, `## Storage ops — re-check commands`:170-180) — storage policy being adapted.
- `docs/findings.md` — `## io-stack`:267-288, `## nvme`:290-314, `## fstrim`:316-347, `## sched`:181-201, `## suspend-resume`:634 ff.; `docs/NOTE.md` (`## 2026-09-29 — recurrence 21:14 …`); `docs/MEMORY.md` (one-doc-home rule; sleep-hook pitfalls).
- btrfs-progs 7.1 man pages (installed locally at `/usr/share/man/man{5,8}/`, dated Jul 15 2026):
  `btrfs(5)` (MOUNT OPTIONS: autodefrag, compress/compress-force, datacow/datasum, discard,
  space_cache, ssd; "RAID56 STATUS AND RECOMMENDED PRACTICES"), `btrfs-scrub(8)`,
  `btrfs-balance(8)`, `btrfs-check(8)`, `btrfs-quota(8)`, `btrfs-qgroup(8)`,
  `btrfs-filesystem(8)` (df/du/defrag/usage), `btrfs-device(8)` (stats).
  HTML edition: https://btrfs.readthedocs.io/en/latest/btrfs-man5.html
- The btrfs documentation site (the canonical community-maintained wiki, successor to the
  kernel.org btrfs wiki): https://btrfs.readthedocs.io/en/latest/ — pages used:
  [Compression](https://btrfs.readthedocs.io/en/latest/Compression.html),
  [Deduplication](https://btrfs.readthedocs.io/en/latest/Deduplication.html),
  [Defragmentation](https://btrfs.readthedocs.io/en/latest/Defragmentation.html),
  [Scrub](https://btrfs.readthedocs.io/en/latest/Scrub.html),
  [Balance](https://btrfs.readthedocs.io/en/latest/Balance.html),
  [Trim/discard](https://btrfs.readthedocs.io/en/latest/Trim.html),
  [Quota groups](https://btrfs.readthedocs.io/en/latest/Qgroups.html),
  [Reflink](https://btrfs.readthedocs.io/en/latest/Reflink.html),
  [Auto-repair on read](https://btrfs.readthedocs.io/en/latest/Auto-repair.html),
  [Troubleshooting (ENOSPC, balance workspace)](https://btrfs.readthedocs.io/en/latest/trouble-index.html).
  The kernel.org landing page `Documentation/filesystems/btrfs.rst` explicitly defers
  administration/mount-option detail to this site (https://docs.kernel.org/filesystems/btrfs.html).
- `ioctl_fideduperange(2)` — Linux man-pages project,
  https://man7.org/linux/man-pages/man2/ioctl_fideduperange.2.html (kernel FIDEDUPERANGE
  semantics: exact-match-only, COW-share, error codes).
- duperemove upstream docs (tool semantics: FIDEDUPERANGE submission, hashfile incrementality,
  btrfs+xfs support, FAQ on estimates/bookending/fragmentation):
  README https://github.com/markfasheh/duperemove and man page
  http://markfasheh.github.io/duperemove/duperemove.html.
- systemd/btrfs-progs unit files verified live: `/usr/lib/systemd/system/btrfs-scrub@.{service,timer}`
  (btrfs-progs 7.1-1), `/usr/lib/systemd/system/fstrim.{service,timer}` (systemd).
- Live readbacks (read-only, 2026-10-05): `/proc/mounts`, `btrfs filesystem usage/df /`,
  `btrfs subvolume list /`, `btrfs scrub status /`, `btrfs device stats /`, `lsblk -f`,
  `pacman -Q/-Ql`, `systemctl list-timers/list-unit-files`, `uname -r`.

Explicitly not used: ArchWiki (not consulted; every claim above is backed by a man page, the
btrfs documentation site, kernel/driver docs, or tool upstream docs), blogs and third-party
benchmarks (no quantitative energy claim in this file rests on one — there are no primary
energy numbers for btrfs compression/dedupe/scrub, which is why every recommendation routes
through the `docs/judgment.md` measurement protocol).
