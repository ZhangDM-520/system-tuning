# Action — 2026-11-08: Shrink btrfs by 24 GiB, create F2FS partition, and mount /tmp

## Objective
Shrink the primary btrfs filesystem on `/dev/nvme0n1p2` by 24 GiB, allocate the freed 24 GiB space to a new F2FS filesystem on `/dev/nvme0n1p4` tuned for maximum speed and minimized write amplification with fast lz4 compression, and mount `/tmp` onto the new F2FS partition instead of RAM.

## Operations Performed
1. **Pre-flight & Partition Pre-image:**
   - Backed up GPT partition table: `.logs/nvme0n1-partition-table-preimage-20261108.dump`.
   - Verified active mounts, subvolumes, and zram-writeback backing partition `/dev/nvme0n1p3`.
2. **Filesystem & Partition Shrinking:**
   - Shrunk live btrfs filesystem online: `btrfs filesystem resize -25G /` (919.34 GiB -> 894.34 GiB).
   - Modified GPT partition table via `sfdisk --no-reread`:
     - `/dev/nvme0n1p2` shrunk by 50,331,648 sectors (exact 24 GiB) from sector 1,936,445,439 down to 1,886,113,791.
     - Created `/dev/nvme0n1p4` from sector 1,886,113,792 to 1,936,445,439 (50,331,648 sectors, 24 GiB, 1 MiB aligned).
     - Kept partition 3 (zram-writeback swap) untouched at 1,936,445,440.
   - Informed live kernel via `resizepart` and verified partition table recognition.
   - Expanded btrfs to fill exact partition boundary: `btrfs filesystem resize max /` (settling at 895.37 GiB).
3. **F2FS Format & Superblock Tuning:**
   - Formatted `/dev/nvme0n1p4` with `mkfs.f2fs`:
     - Flags: `-f -l f2fs-tmp -H -O extra_attr,compression,inode_checksum,sb_checksum,flexible_inline_xattr,inode_crtime`
     - `-H` enables write hint support for flash FTL wear-leveling and hot/cold separation.
     - Superblock features: `extra_attr`, `compression`, `inode_checksum`, `sb_checksum`, `flexible_inline_xattr`, `inode_crtime`.
   - Configured root directory with `chmod 1777` and `chattr +c` to enable automatic transparent compression inheritance.
4. **Mount Configuration & Live Transition:**
   - Selected mount options for maximum throughput and minimum write amplification:
     - `noatime,lazytime`: eliminate access time writes.
     - `nodiscard`: avoid synchronous/async discard latency fighting APST (conforming to repo storage findings).
     - `nobarrier`, `fsync_mode=nobarrier`: remove write cache barrier stalls on scratch/temporary I/O.
     - `compress_algorithm=lz4:0`: fastest LZ4 level 0 inline compression without CPU bottlenecks.
     - `compress_chksum,compress_mode=fs,compress_cache`: transparent writeback compression with block caching.
     - `atgc,gc_merge,checkpoint_merge,flush_merge`: adaptive garbage collection and checkpoint batching.
     - `inline_xattr,inline_data,inline_dentry`: store small files (<3.4KB) and directories inside inodes to eliminate data block allocations.
   - Updated `state/owned/etc/fstab` and `/etc/fstab` (backed up to `/etc/fstab.bak-20261108`).
   - Ran `systemctl daemon-reload` to update generated `tmp.mount`.
   - Staged live transition without disrupting running compositor/Xwayland sessions by preserving active socket directories.
5. **Systemd Boot Wipe & Periodic GC (Tmpfs Emulation):**
   - Deployed `/etc/tmpfiles.d/tmp.conf` and `state/owned/etc/tmpfiles.d/tmp.conf` to override `/usr/lib/tmpfiles.d/tmp.conf`:
     - `D! /tmp 1777 root root 0`: empties `/tmp` on system boot (`--boot`) to emulate volatile tmpfs behavior.
     - `x /tmp/lost+found`: excludes filesystem recovery directory from removal.
     - `e /tmp - - - 10d`: daily age-based garbage collection via `systemd-tmpfiles-clean.timer`.
     - `q /var/tmp 1777 root root 30d`: retains standard `/var/tmp` cleanup policy.
   - Tested boot removal and GC dry-runs with `systemd-tmpfiles`.
6. **User RAM Tmpfs (80% RAM) & `~/tmp` Symlink:**
   - Configured logind drop-in `/etc/systemd/logind.conf.d/20-runtime-dir-size.conf` (`RuntimeDirectorySize=80%`) and mirrored to `state/owned/etc/systemd/logind.conf.d/20-runtime-dir-size.conf`.
   - Remounted live `/run/user/1000` tmpfs to `size=80%` (25 GiB out of 30 GiB RAM).
   - Created `/etc/systemd/system/user-runtime-dir@.service.d/10-user-tmp.conf` and `/etc/tmpfiles.d/10-user-tmp.conf` to automatically establish `/run/user/1000/tmp` (mode 0700) on login/boot.
   - Created symlink `~/tmp -> /run/user/1000/tmp`, providing user-dedicated in-memory temporary storage protected from rogue system trash dumps.
7. **Verification:**
   - `findmnt /tmp` confirms `/dev/nvme0n1p4` (F2FS) mounted at `/tmp`.
   - `df -hT /home/zhangdm/tmp` confirms `tmpfs` sized at 25 GiB.
   - Verified file creation and inheritance of `+c` attribute on `/tmp` and RAM writes in `~/tmp`.
   - Ran `./tests/run`: 97 run, 97 passed, 0 failed.

## Reconciliation — 2026-11-09 (ownership review before commit)

- **Compression works; the accounting hides it.** A first read of `df`/`stat` said "inert", and
  that was wrong. The space accounting is nominal on f2fs: `df`, `stat %b` and `du` all report
  every 16 KiB cluster as four 4 KiB blocks, and the ENOSPC path reserves the same way (a 3.75 GiB
  write into a 2 GiB fs dies at ~2 GiB nominal). The real saving is in bytes written to the
  device. Evidence: live `/sys/fs/f2fs/nvme0n1p4/compr_{written,saved}_block` before/after a 1 GiB
  `f` write moved +65 544 / +196 608 of 262 144 nominal blocks (exactly 3/4 saved — the 4:1
  ceiling, since one cluster floors at one block); an f2fs image hosted on tmpfs grew by ~270 MB
  of real pages for 1 GiB written. `f2fs_io get_cblocks` returns the saved-block count
  (`i_compr_blocks`), not a size — hence its "~75%". Written up as `docs/findings.md`
  `## f2fs-tmp` (with a `Machine lies` line) and a fact row in `AGENTS.md`. No mount option was
  changed: the set is correct and the write reduction is real; what is open is what the 4:1 write
  reduction buys on this NVMe.
- **Dead duplicate rule removed.** `/etc/tmpfiles.d/10-user-tmp.conf` (and its owned mirror)
  was dropped: `systemd-tmpfiles-setup` runs before logind mounts `/run/user/<uid>`, so the
  directory it created was immediately hidden — it never produced the persistent `tmp/`.
  The `user-runtime-dir@.service` drop-in is the single writer (it runs when the runtime dir
  exists). Pre-images: `.logs/10-user-tmp.conf.preimage-20261109` (live) and
  `.logs/10-user-tmp.conf.service-dropin.preimage-20261109` (the drop-in before the next bullet).
- **Login hook made non-fatal.** `ExecStartPost=-/usr/bin/install …` in
  `state/owned/etc/systemd/system/user-runtime-dir@.service.d/10-user-tmp.conf`: a failed
  courtesy directory must never fail `user-runtime-dir@` and block the login chain. Verified
  parsed as `ignore_errors=yes` via `systemctl show user-runtime-dir@1000.service`.
- **Docs repointed:** `docs/findings.md` `## f2fs-tmp` (new), `docs/rollback.md`
  `## Storage ops` (automation rows, `/tmp` volatile-by-contract rule, re-check commands),
  `AGENTS.md` (two fact rows + refreshed host snapshot).
