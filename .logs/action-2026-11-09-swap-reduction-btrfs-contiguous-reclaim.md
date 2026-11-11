# Action: Swap Reduction to 24 GiB & Contiguous Btrfs Reclaim

- **Date:** 2026-11-09
- **Scope:** Storage, partitioning, zram-writeback, btrfs root expansion
- **Trigger:** Reclaimed ~6.5 GiB from `/dev/nvme0n1p3` (Linux swap) back into contiguous Btrfs root filesystem (`/dev/nvme0n1p2`), reducing swap partition to 24 GiB.

## Key Actions Taken

1. **Partition Table Backup & Transformation:**
   - Pre-image dumped to `.logs/nvme0n1-partition-table-preimage2-20261109.dump`.
   - GPT partition layout updated via `sfdisk --no-reread /dev/nvme0n1`:
     - `p1` (EFI): 4096..8392703 (4 GiB)
     - `p2` (Btrfs root): 8392704..1899745279 (901.9 GiB, contiguously expanded by 6.5 GiB)
     - `p4` (F2FS /tmp): 1899745280..1950076927 (24 GiB, shifted left to match p2 end)
     - `p3` (Linux swap): 1950076928..2000409230 (24 GiB, shrunk from 30.5 GiB)

2. **Boot-Time One-Shot Transition Engine:**
   - Staged [`/usr/local/sbin/prepare-disk-reclaim.sh`](file:///usr/local/sbin/prepare-disk-reclaim.sh) and [`/etc/systemd/system/prepare-disk-reclaim.service`](file:///etc/systemd/system/prepare-disk-reclaim.service) enabled for next boot.
   - Handled unit dependencies:
     - `tmp.mount` ordered after reclaim via [`/etc/systemd/system/tmp.mount.d/reclaim.conf`](file:///etc/systemd/system/tmp.mount.d/reclaim.conf).
     - `systemd-zram-setup@zram0.service` ordered after reclaim via [`/etc/systemd/system/systemd-zram-setup@zram0.service.d/reclaim.conf`](file:///etc/systemd/system/systemd-zram-setup@zram0.service.d/reclaim.conf).
   - Once executed on boot:
     - `btrfs filesystem resize max /` expands root online to 901.9 GiB.
     - `mkfs.f2fs` initializes `p4` with UUID `8f027a2f-ebbc-4b82-a6a5-146c970d40b7`, applies root permissions `1777` and `chattr +c`.
     - `mkswap` formats `p3` with UUID `fca9eaa6-f0a8-4b13-bc4b-bf31255e5eb7` and label `zram-writeback`.
     - Self-destructs the temporary oneshot service, drop-ins, and script.

3. **Verification:**
   - `tests/run` passes 100% (117 run, 117 passed, 0 failed).
