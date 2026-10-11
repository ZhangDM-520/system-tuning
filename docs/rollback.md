# Operations runbook — run, verify, undo

When to read: before converging a change, before a reboot, immediately after one, around
suspend/resume, before undoing anything, and when storage automation comes up. Recovery operates
in the tty domain and must never depend on this repo's tooling working: raw commands live here on
purpose, this is the one accepted leak across the seam.

Invariants: the recovery domain is sacred — rule in `docs/judgment.md` (Derived rules, item 7),
never restated here; backups are never deleted (`## Undo: universal mechanism`); the verify
recipes speak the report's row vocabulary (OK/ACCEPTED/WARN/DRIFT/SKIPPED), defined in
`docs/eco-power-README.md`, not here.

## Converge a change

The one change flow — sysctl, owned file, or managed foreign line: edit `state/` →
`./eco apply --dry-run` → `./eco apply` → commit with the check ID. One place per knob; owned/
vs managed/ record semantics and the state layout are in `docs/eco-power-README.md`
(`## State layout`).

- `./eco apply --dry-run` writes nothing; read the convergence plan before the real run.
- `./eco apply` converges live to repo and takes dated pre-images first (see
  `## Undo: universal mechanism`).
- `./eco harvest` captures deliberate live experiments before the converger reverts them.
- Never hand-edit live sysctls (converger/TLP race).
- Undo of a converged change: `git revert` + re-apply.

## Before a reboot

The convergence run (boot -> eco-power.service; the 600s backstop timer and AC-event trigger were
dropped 2026-10-11) re-asserts nearly
everything, so this is a confirmation walk, not a repair session.

1. Nothing to do for the power stack: everything durable is in repo state/ and re-applied at boot.
2. If you are mid-experiment on a live value: capture it first (`./eco harvest`, see
   `## Converge a change`), or it is gone.
3. If the firmware/EC was misbehaving and you want the discharge path: shut down fully (not
   reboot); the EC clears only on a real power-off.

## Verify after boot

1. `./eco report` (unprivileged is fine; `sudo` adds the SMU rows).
   Expect: exit 0 with OK rows, one ACCEPTED row for PPT (STAPM firmware floor, findings#ppt),
   possibly a WARN on SD (reader re-binds at boot: runtime-only unbind, rollback#sd), and possibly
   SKIPPED rows where a check needs root or a user session (SKIPPED semantics live in
   `docs/eco-power-README.md`, not here).
2. `systemctl is-enabled eco-power.service` shows the boot run armed (timer dropped 2026-10-11).
3. AC state sanity: `cat /sys/class/power_supply/AC0/online`. If the state looks wrong versus
   reality, do one physical plug cycle (known EC misread, findings#input-i2c) before diagnosing anything.
4. Only if PPT shows DRIFT instead of ACCEPTED: run `sudo ./eco apply` and re-report.
5. acp_power_gating applies fully at boot (module load parameter): expect OK on MISC from the
   first report onward.

## Verify after suspend/resume

Resume re-triggers eco-power via the sleep hook (the udev power-event trigger was dropped
2026-10-11). Expected resume anomalies, all
documented and harmless: the freesync VRR warning (cosmetic), asusd WARN lines (only if the
profile mapping is broken again), and a transient STAPM readback while the envelope re-converges.

## Human habits

1. Bluetooth: power the radio off when not in use (`bluetoothctl power off`); the USB device only
   suspends then (findings#bt).
2. SD reader: after a reboot it is bound again. Leave it (WARN is expected) or re-run the unbind
   one-liner from rollback#sd.

## Undo: universal mechanism

Every live write this stack makes takes a pre-image first: `cp -p <file> <file>.bak-YYYYMMDD`
alongside the target — do this even for a one-line `managed/` edit. The `.bak-YYYYMMDD` suffix is
the rollback handle and the date is the day of the write, not the day of the file. To undo a file
change: diff it against its `.bak-*` sibling and copy the sibling back. Backups are never deleted.
One exception, enforced in `lib/writers.sh` `backup_step`: `/usr/lib/systemd/system-sleep/`
executes EVERY file it contains regardless of name, so pre-images for targets there go to the
`system-sleep-backups/` sibling directory instead (burned 2026-09-29: a sibling `.bak` hook ran
as a stale resume hook for hours).

Whole-file owned targets mirror their live paths under `state/owned/` (naming rule in
`docs/eco-power-README.md` `## State layout`). Foreign-file edits
(anchor-replaced single lines) roll back the same way: restore the line from the dated backup.

## sd

The SD reader (GL9755 on `0000:c2:00.0`, sdhci-pci) was unbound at runtime with no card inserted
(Q8). A reboot re-binds it; the report shows WARN, not DRIFT.

- Undo the unbind (rebind now):

      echo 0000:c2:00.0 | sudo tee /sys/bus/pci/drivers/sdhci-pci/bind

  Re-creates /sys/class/mmc_host/mmc0. Safe to run any time, empty reader.

- Re-apply the unbind (only with no card inserted, check: no /dev/mmcblk*, no mmc0:* child):

      echo 0000:c2:00.0 | sudo tee /sys/bus/pci/drivers/sdhci-pci/unbind

- Boot persistence is intentionally NOT implemented (owner decision pending). Do not add a unit
  or rule for it without deciding first.

## misc

- acp power gating (`acp_power_gating=1`, module inert, /etc/modprobe.d/99-acp-power-gating.conf):
  undo with `echo 0 | sudo tee /sys/module/snd_rn_pci_acp3x/parameters/acp_power_gating` and
  `sudo rm /etc/modprobe.d/99-acp-power-gating.conf`.
- localsearch-3 (masked indexer): `systemctl --user unmask localsearch-3.service` to bring it
  back. Owner accepted losing GNOME app search (findings#misc).
- niri autostart spawn of hw-tune.fish: line is anchored in `~/.config/niri/cfg/autostart.kdl`;
  restore from its backup or remove the spawn line. The stack then relies solely on eco-power.
- BT autosuspend module param: `/etc/modprobe.d/99-bt-autosuspend.conf` (options btusb
  enable_autosuspend=1). The older `btusb-no-autosuspend.conf.disabled` can be renamed back to
  `.conf` to restore the never-suspend behavior (findings#bt).

## Stack-wide escape hatches

- Stop convergence entirely: `sudo systemctl disable eco-power.service`. Everything already applied
  stays applied; nothing reverts on its own except the resume hook
  (`/usr/lib/systemd/system-sleep/eco-power`, SMU runtime knobs only), removable the same way.
- Nuclear reset of a live file: copy its `state/owned` mirror to the live path after reviewing the
  diff, or restore the dated backup next to it.
- If a change makes the machine sad: it must not block tty login (doctrine). Boot, log in on a
  tty, `cd ~/Projects/system-tuning`, `./eco report`, and work from the anchors it prints.

## Storage ops — what runs automatically

Installed 2026-09-26; the btrfs-era rows carry their 2026-10-05 date. Verify live with
`## Storage ops — re-check commands` — this list is the record, not the readback:

- **beesd@\<FSUUID\>.service** (2026-10-05) — continuous dedupe duty: `bees` (extra repo,
  "Best-Effort Extent-Same", btrfs extent-scrub daemon), config `/etc/bees/beesd.conf`,
  upstream-default throttling as shipped in the unit (Nice 19, IOWeight 10,
  IOSchedulingClass idle). Replaces the retired daily duperemove job. **bees has no
  per-directory exclusion** — the old script's known-bad-tree exclusions cannot be carried
  over as-is (`docs/findings.md` `## fstrim`).
- **fstrim.timer** (weekly, systemd stock) — pre-existing, left as-is.
- **btrfs-scrub@-.timer** (2026-10-05) — monthly online verification, the stock btrfs-progs
  unit adopted exactly as shipped (`OnCalendar=monthly`, `RandomizedDelaySec=1w`,
  `Persistent=true`; instance `-` = mountpoint `/`). It replaces the retired monthly
  `xfs_scrub` job; its suspend semantics are in `## Storage ops — re-check commands` below.
- **XFS-era automation retired 2026-10-05** (root moved XFS → btrfs at the reinstall):
  `xfs-scrub.{service,timer}` and the `fs.xfs.xfssyncd_centisecs` sysctl are gone from `state/`
  (record: `docs/archive/XFS-TUNING.md`), as are the daily `duperemove.{service,timer}` +
  `duperemove-daily.sh` (dedupe duty now the bees row above). The btrfs online-verification
  duty is the scrub row above; everything else on this list is filesystem-agnostic and stays.
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
- Not automated on purpose: monthly health report (declined), backups (known gap — see the
  findings ledger), defrag (policy: `## Storage ops — never-run rules`), post-dedupe fstrim
  (weekly timer suffices).

## Storage ops — never-run rules

### filesystem repair: offline only

- Online verification on a *mounted* filesystem is fine (now `btrfs scrub` — the scrub row in
  `## Storage ops — what runs automatically`; the XFS-era `xfs_scrub` was retired with its timer
  on 2026-10-05 — `docs/archive/XFS-TUNING.md`).
- Filesystem **repair** is offline/rescue-media territory only: never run `xfs_repair` or
  `btrfs check --repair` on the mounted root — they can destroy data. Read-only `btrfs check`
  on the mounted root is verification, not repair; `--repair` even unmounted only under expert
  guidance (`docs/research/btrfs-optimization.md` §8).

### defrag: never automated (it un-does dedupe)

- Defrag (`xfs_fsr` in the XFS era, `btrfs filesystem defrag` on btrfs) reworks file data
  into fresh contiguous extents. That **destroys reflink sharing**: every defragged file
  re-materializes its own private
  blocks, undoing exactly what dedupe bought. Defrag-after-dedupe is self-defeating.
- Policy: no automatic defrag, ever — 2026-10-05 this explicitly includes the `autodefrag`
  mount option: it is structurally a scheduled defrag the repo cannot scope or audit, with the
  same snapshot/dedupe sharing damage (`docs/research/btrfs-optimization.md` §6). If one
  specific file is *measured* to be badly fragmented and that matters (rare on NVMe), defrag it
  deliberately and accept that its shared extents go away; the dedupe duty re-catches them over
  time if the space matters (bees row in `## Storage ops — what runs automatically`).

### balance: trigger-only, never scheduled (2026-10-05)

- Balance preserves reflink sharing (unlike defrag), so it is *allowed*; but on a single device
  there is nothing to spread and an unfiltered pass is a whole-filesystem rewrite (IO + CPU +
  write amplification — `docs/research/btrfs-optimization.md` §4).
- Policy: maintenance trigger only — `btrfs filesystem usage /` showing stranded chunks or
  ENOSPC pressure despite reported free space — and then usage-filtered and chunk-limited
  (`usage=`/`limit=`). Never on a timer. When used, record before/after
  `btrfs filesystem usage` and the job's wall time.

### btrfs refusals (2026-10-05 — refusals, not tunings)

Primary sourcing in `docs/research/btrfs-optimization.md` §4–§8; each returns only with new
evidence (`docs/findings.md` preamble):

- **`autodefrag`** — joins the defrag rule above verbatim (§6).
- **Unfiltered or scheduled `btrfs balance`** — see the balance rule above (§4).
- **RAID5/RAID6 profiles** — upstream's own warning: not production-safe (power-failure write
  hole); moot on one device today, never convert (§8).
- **NOCOW anywhere** — owner ruling 2026-10-05: COW everywhere (checksums + compression +
  reflink), so mount-wide `nodatacow`/`nodatasum` *and* per-file `chattr +C` islands are both
  out (§2, §8).
- **qgroups (`btrfs quota enable`) by default** — quota bookkeeping taxes all extent
  processing; return only for a real limit the owner wants, measured first (§8).
- **`compress-force` as the default** — upstream advises against; `compress` heuristics plus
  per-file properties are the right tools (§8).
- **`discard`/`discard=sync`** — already banned (`docs/findings.md` `## fstrim`).

### tunables domain (2026-10-05 — refusals, not tunings)

Primary sourcing in `docs/research/btrfs-tunables.md` §7; each returns only with new evidence
(`docs/findings.md` preamble):

- **Runtime writes to `/sys/module/{nvme,nvme_core}/parameters/*`** — probe-time/policy state;
  the APST-adjacent ones share the hazard class of `nvme set-feature -f 0x0c`.
- **Building on `scrub_speed_max` / `btrfs scrub limit` persistence** — it dies at unmount; a
  limit that vanishes silently is worse than no limit. Re-read after every mount.
- **Rate-capping maintenance jobs as an efficiency measure** — caps turn one compact work
  window into a trickle; a cap may protect interactivity only.
- **`btrfs scrub start -c/-n` (ionice flags)** — deprecated, and the man page's scheduler claim
  is contradicted by kernel doc + source (ionice is real only under mq-deadline/bfq).
- **`allocation/*/chunk_size`, `read_policy`, `quota_override`, fs-wide `bg_reclaim_threshold`,
  `dynamic_reclaim`, `periodic_reclaim`** — no traced consumer, large blast radius; there is no
  defect here they would fix.
- **Disabling `iostats` or `write_cache` "for performance"** — the first blinds the re-check
  commands, the second changes flush semantics without a durability requirement.
- **Treating `ionice`/`IOSchedulingClass=idle` as an energy tool** — interactivity-only, and
  inert under the current elevator (`none`; also under kyber).
- **Re-proposing settled queue/VM knobs from the research file** — scheduler `none`,
  `nr_requests=1023`, `read_ahead_kb=256`, `wbt_lat_usec=2000`, `vm.swappiness=150`, writeback
  centisecs, APST staging are `docs/findings.md` territory with stated reopen conditions.

## Storage ops — re-check commands

```
df -h / ; df -i /                     # capacity + inodes (df lags after dedupe)
btrfs filesystem usage /              # chunk-level truth: unallocated vs usable (balance trigger)
btrfs filesystem df /                 # profile totals (Data single / Metadata DUP)
sudo btrfs scrub status /             # last run, errors, unfinished/cancelled state
sudo btrfs device stats -c /          # all-zero check (exit 64+ if nonzero)
sudo btrfs subvolume list /           # layout + snapshot inventory drift
findmnt -no OPTIONS /                 # compress + no autodefrag (never-run rules above)
systemctl list-timers --all | grep -E 'btrfs|fstrim|smartd'
systemctl status 'beesd@*'            # dedupe duty alive on the right FSUUID
nvme smart-log /dev/nvme0 | grep -iE 'percentage_used|available_spare|media_errors|temperature'
smartctl -H /dev/nvme0                # overall health
journalctl --disk-usage
```

Scrub suspend semantics (2026-10-05, `docs/research/btrfs-optimization.md` §3): since kernel
6.19 a running scrub is **cancelled** by suspend/hibernate and does not continue on its own —
`btrfs scrub status /` shows a non-completed pass, and only `btrfs scrub resume` (or a re-run)
finishes the verification. Check it after any suspend that overlapped a maintenance window.
Dedupe accounting (`docs/findings.md` `## fstrim`): judge savings by physical offsets /
`btrfs filesystem du` deltas, never by tool self-reports.
