# state: live-system state records

This directory records the power-tuning state of the live machine. It is the only part of the repo
that mirrors the running system. All live reading is copy-only: live files are never written from
this repo except through an explicit, backed-up apply step.

## owned/ vs managed/

- `owned/` means whole-file ownership. Each entry is a verbatim mirror of one live file that the
  repo owns end to end. The repo path is `state/owned/<live-path-without-leading-slash>` and the
  content is byte-identical to the live source.
- `managed/` means one anchored line inside a foreign file the repo does not fully own. Each TOML
  record has five keys: `target` (the live path), `match` (an anchored regex selecting the one line
  to own), `line` (the full replacement line exactly as it should appear), `doc` (an anchor
  string pointing at the writeup that explains the knob), and optionally `section` (a regex
  selecting one section header line). Without `section`, `match` must select exactly one line in
  the whole file. With `section`, the region is the lines after that header and before the next
  line starting with `[`, and `match` must select exactly one line in that region: zero or multiple
  matches there is a hard error, nothing is written. All record regexes (`match` and `section`) use
  the POSIX ERE dialect (`grep -E` / bash `=~`), so `?`, `+`, `[[:space:]]` and friends mean what
  ERE says they mean.

## One place per knob

Each tunable appears exactly once under `state/`. If a grep of `state/` finds the same knob twice,
the repo is wrong: give it one home here and delete the other. Two homes means two opinions about
the value, and apply will race them.

## Backup convention

Before any write to a live file, copy the target aside first:

```
cp -p <file> <file>.bak-YYYYMMDD
```

Do this even for a one-line `managed/` edit. The `.bak-YYYYMMDD` suffix is the rollback handle and
the date is the day of the write, not the day of the file.

## File map

| state file | live target |
| --- | --- |
| `state/owned/usr/local/sbin/eco-power.sh` | `/usr/local/sbin/eco-power.sh` |
| `state/owned/home/zhangdm/.reserve/hw-tune.fish` | `/home/zhangdm/.reserve/hw-tune.fish` |
| `state/owned/etc/tlp.d/01-eco.conf` | `/etc/tlp.d/01-eco.conf` |
| `state/owned/etc/systemd/system/eco-power.service` | `/etc/systemd/system/eco-power.service` |
| `state/owned/etc/systemd/system/eco-power.timer` | `/etc/systemd/system/eco-power.timer` |
| `state/owned/etc/udev/rules.d/81-wifi-powersave.rules` | `/etc/udev/rules.d/81-wifi-powersave.rules` |
| `state/owned/etc/udev/rules.d/98-bt-autosuspend.rules` | `/etc/udev/rules.d/98-bt-autosuspend.rules` |
| `state/owned/etc/udev/rules.d/99-eco-power.rules` | `/etc/udev/rules.d/99-eco-power.rules` |
| `state/owned/etc/modprobe.d/99-bt-autosuspend.conf` | `/etc/modprobe.d/99-bt-autosuspend.conf` |
| `state/owned/etc/modprobe.d/99-acp-power-gating.conf` | `/etc/modprobe.d/99-acp-power-gating.conf` |
| `state/owned/etc/sysctl.d/99-eco-writeback.conf` | `/etc/sysctl.d/99-eco-writeback.conf` |
| `state/owned/etc/NetworkManager/conf.d/99-wifi-powersave.conf` | `/etc/NetworkManager/conf.d/99-wifi-powersave.conf` |
| `state/managed/scx.toml` | `/etc/scx_loader.toml` (one anchored line) |
| `state/managed/asusd.toml` | `/etc/asusd/asusd.ron` (one anchored line) |
| `state/managed/journald.toml` | `/etc/systemd/journald.conf` (one anchored line) |
| `state/managed/niri-autostart.toml` | `/home/zhangdm/.config/niri/cfg/autostart.kdl` (one anchored line) |
| `state/README.md` | (none, documentation) |
