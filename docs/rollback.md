# Rollback

When to read: before undoing anything. Recovery operates in the tty domain and must never depend
on this repo's tooling working: raw commands live here on purpose, this is the one accepted leak
across the seam.

## Universal mechanism

Every live write this stack makes takes a pre-image first: `cp -p <file> <file>.bak-YYYYMMDD`
alongside the target. To undo a file change: diff it against its `.bak-*` sibling and copy the
sibling back. Backups are never deleted.

Whole-file owned targets and their live paths are listed in `state/README.md`. Foreign-file edits
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
  back. Owner accepted losing GNOME app search (decisions#config-fixes).
- niri autostart spawn of hw-tune.fish: line is anchored in `~/.config/niri/cfg/autostart.kdl`;
  restore from its backup or remove the spawn line. The stack then relies solely on eco-power.
- BT autosuspend module param: `/etc/modprobe.d/99-bt-autosuspend.conf` (options btusb
  enable_autosuspend=1). The older `btusb-no-autosuspend.conf.disabled` can be renamed back to
  `.conf` to restore the never-suspend behavior (decisions#bt).

## Stack-wide escape hatches

- Stop convergence entirely: `sudo systemctl stop eco-power.timer` (and disable eco-power.service
  if needed). Everything already applied stays applied; nothing reverts on its own except the
  udev/power-event path, which can be disabled by removing `/etc/udev/rules.d/99-eco-power.rules`.
- Nuclear reset of a live file: copy its `state/owned` mirror to the live path after reviewing the
  diff, or restore the dated backup next to it.
- If a change makes the machine sad: it must not block tty login (doctrine). Boot, log in on a
  tty, `cd ~/Projects/system-tuning`, `./eco report`, and work from the anchors it prints.
