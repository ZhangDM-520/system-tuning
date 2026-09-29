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

The convergence chain (boot -> eco-power.service, plus the 600s backstop) re-asserts nearly
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
2. `systemctl list-timers eco-power.timer` shows the 600s backstop armed.
3. AC state sanity: `cat /sys/class/power_supply/AC0/online`. If the state looks wrong versus
   reality, do one physical plug cycle (known EC misread, findings#input-i2c) before diagnosing anything.
4. Only if PPT shows DRIFT instead of ACCEPTED: run `sudo ./eco apply` and re-report.
5. acp_power_gating applies fully at boot (module load parameter): expect OK on MISC from the
   first report onward.

## Verify after suspend/resume

Resume re-triggers eco-power via the sleep hook and the udev rule. Expected resume anomalies, all
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

- Stop convergence entirely: `sudo systemctl stop eco-power.timer` (and disable eco-power.service
  if needed). Everything already applied stays applied; nothing reverts on its own except the
  udev/power-event path, which can be disabled by removing `/etc/udev/rules.d/99-eco-power.rules`.
- Nuclear reset of a live file: copy its `state/owned` mirror to the live path after reviewing the
  diff, or restore the dated backup next to it.
- If a change makes the machine sad: it must not block tty login (doctrine). Boot, log in on a
  tty, `cd ~/Projects/system-tuning`, `./eco report`, and work from the anchors it prints.

## Storage ops — what runs automatically

Installed 2026-09-26 (all verified live, not just installed):

- **duperemove.timer** (daily 03:30 + random delay, `Persistent=true`) ->
  `duperemove.service` -> `/usr/local/sbin/duperemove-daily.sh`. Incremental dedupe (hashfile
  `/var/lib/duperemove/root.hash` — unchanged files are not re-hashed; logs
  `/var/lib/duperemove/daily.log*`, keep 7).
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
- Not automated on purpose: monthly health report (declined), backups (known gap — see the
  findings ledger), xfs_fsr (policy: `## Storage ops — never-run rules`), post-dedupe fstrim
  (weekly timer suffices).

## Storage ops — never-run rules

### xfs_scrub vs xfs_repair

- `xfs_scrub`: **online** verification of metadata and data checksums, safe on a mounted
  filesystem. This is the scheduled one (`## Storage ops — what runs automatically`).
- `xfs_repair`: **offline only**. Never run it on the mounted root — it can destroy data.
  Rescue-media territory only.

### xfs_fsr: never auto-defrag (it un-does dedupe)

- `xfs_fsr` defragments by rewriting file data into fresh contiguous extents. That
  **destroys reflink sharing**: every defragged file re-materializes its own private
  blocks, undoing exactly what duperemove bought. Defrag-after-dedupe is self-defeating.
- Policy: no automatic defrag, ever. If one specific file is *measured* to be badly
  fragmented and that matters (rare on NVMe), defrag it deliberately and accept that its
  shared extents go away; re-run duperemove afterwards if the space matters.

## Storage ops — re-check commands

```
df -h / ; df -i /                     # capacity + inodes
nvme smart-log /dev/nvme0 | grep -iE 'percentage_used|available_spare|media_errors|temperature'
smartctl -H /dev/nvme0                # overall health
systemctl list-timers --all | grep -E 'duperemove|fstrim|xfs-scrub|smartd'
journalctl --disk-usage
xfs_info / | tr ' ' '\n' | grep reflink   # must stay 1
```
