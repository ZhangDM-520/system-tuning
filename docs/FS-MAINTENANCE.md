# Filesystem maintenance — host (CachyOS, XFS root)

Written 2026-09-26 after the full-filesystem duperemove work. Companion to
`~/docs/NOTE.md` (session detail) and `~/docs/MEMORY.md` (host facts). This file is the
operational summary: what runs automatically, what must never run, and why.

## Storage facts (baseline 2026-09-26)

- Root: XFS with `reflink=1` on `/dev/nvme0n1p2`, 950G total, ~39% used, inodes 2%.
- fstab opts: `lazytime,inode64,logbsize=256k,noquota`. **No `discard` mount option — by
  design**: periodic batch TRIM beats per-operation discard latency on NVMe.
- NVMe health: `percentage_used` 2%, `available_spare` 100%, `media_errors` 0,
  1371 power-on hours, 41 C. This is the baseline to compare future readings against.
- Journal 47.9M (SystemMaxUse=32M), pacman pkg cache 0 bytes — both healthy.

## duperemove (dedupe) — automated

- Daily timer 03:30 (+ random delay), script `/usr/local/sbin/duperemove-daily.sh`,
  service `/etc/systemd/system/duperemove.{service,timer}`.
- Hashfile `/var/lib/duperemove/root.hash` makes runs incremental (unchanged files are not
  re-hashed); logs rotate in `/var/lib/duperemove/daily.log*` (keep 7).
- Full-filesystem sweep on 2026-09-26 recovered ~65 GiB; verified by physical-offset
  (`poff`) measurement, not by duperemove's self-report.
- Four pitfalls that cost hours (details in `~/docs/NOTE.md`, 2026-09-26 entries):
  1. duperemove silently scans **0 files as non-root** (`libblkid` UUID lookup) and exits 0.
  2. Duplicate-group comparison is quadratic-ish: an 87k-member identical-file group pegged
     a core for >55 min with zero progress. Huge identical-file trees get excluded.
  3. Hashfile `dedupe_seq` resume semantics: files below the config marker are permanently
     skipped; the sweep loop also never anchors the top seq value (upstream off-by-one).
  4. `--read-hashes` is a *different*, non-SQLite hash format and does nothing on a
     `--hashfile` database.

## fstrim — already covered, leave as-is

- `fstrim.timer` (systemd, weekly) is enabled and active. Nothing to add.
- One-off `sudo fstrim -av` is worth running after very large deletions; the weekly timer
  would catch up anyway, this just returns the blocks to the FTL sooner.
- Measurement caution: free space can keep drifting down *after* a dedupe sweep (delayed
  block freeing). Never attribute freed space to dedupe without measuring duplicates
  directly (`COUNT(DISTINCT poff)` per digest in the hashfile).

## xfs_scrub vs xfs_repair

- `xfs_scrub`: **online** verification of metadata and data checksums, safe on a mounted
  filesystem. This is the scheduled one (see Automation below).
- `xfs_repair`: **offline only**. Never run it on the mounted root — it can destroy data.
  Rescue-media territory only.

## xfs_fsr: never auto-defrag (it un-does dedupe)

- `xfs_fsr` defragments by rewriting file data into fresh contiguous extents. That
  **destroys reflink sharing**: every defragged file re-materializes its own private
  blocks, undoing exactly what duperemove bought. Defrag-after-dedupe is self-defeating.
- Policy: no automatic defrag, ever. If one specific file is *measured* to be badly
  fragmented and that matters (rare on NVMe), defrag it deliberately and accept that its
  shared extents go away; re-run duperemove afterwards if the space matters.

## Backups — known gap (out of scope 2026-09-26)

- No backup tool is installed (no borg/restic/snapper/partclone), and XFS has no
  snapshots. Dedupe, TRIM and scrub protect against none of the failure modes backups
  protect against.
- Recommendation for the next maintenance window: borg or restic to off-host or external
  storage. Until then, anything not backed up is one `rm -rf` or one firmware bug away
  from gone.

## Automation

Installed 2026-09-26 (all verified live, not just installed):

- **duperemove.timer** (daily 03:30 + random delay, `Persistent=true`) ->
  `duperemove.service` -> `/usr/local/sbin/duperemove-daily.sh`. Incremental dedupe.
- **fstrim.timer** (weekly, systemd stock) — pre-existing, left as-is.
- **xfs-scrub.timer** (`OnCalendar=*-*-01..07 05:00:00`, `RandomizedDelaySec=2h`,
  `Persistent=true`) -> `xfs-scrub.service` -> `xfs_scrub -v /`, `Nice=10` +
  best-effort/ionice 7. Monthly online verification; nonzero exit fails the unit so
  `systemctl --failed` shows it. Units: `/etc/systemd/system/xfs-scrub.{service,timer}`.
- **smartd.service** (enabled + active) — `/etc/smartd.conf`: `DEVICESCAN -a -o on -S on
  -n standby,q -s (S/../../7/04) -W 5,45,55 -m /dev/null -M exec
  /usr/local/sbin/smart-alert.sh`. Weekly short self-test Sunday 04:00 (`7` = Sunday;
  `.` in the day field means *every* day — a code-review catch), temp thresholds 5/45/55 C.
  No MTA on this box: alerts go to `/var/log/smartd-alert.log` plus a marker file
  `/var/lib/smart-alert/NEEDS-ATTENTION`. smartd `-M exec` delivers the alert as a
  mail-style message: body on STDIN, `-s "$SMARTD_SUBJECT" $SMARTD_ADDRESS` as args,
  and `SMARTD_SUBJECT`/`SMARTD_MESSAGE`/`SMARTD_FULLMESSAGE` in the environment — the
  alert script captures all three forms plus a `smartctl -a` snapshot (logging only
  `"$1"` would record the literal `-s`). Original config backed up as
  `/etc/smartd.conf.bak-20260926-pre-smartd-replace`.
- Note: smartd 7.5 rejects `smartd -qone`; the config-query flag is `-qonecheck`.
- Not automated on purpose: monthly health report (declined), backups (gap above),
  xfs_fsr (see policy above), post-dedupe fstrim (weekly timer suffices).

## Re-check commands

```
df -h / ; df -i /                     # capacity + inodes
nvme smart-log /dev/nvme0 | grep -iE 'percentage_used|available_spare|media_errors|temperature'
smartctl -H /dev/nvme0                # overall health
systemctl list-timers --all | grep -E 'duperemove|fstrim|xfs-scrub|smartd'
journalctl --disk-usage
xfs_info / | tr ' ' '\n' | grep reflink   # must stay 1
```
