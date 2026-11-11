# Action summary — 2026-11-03 — timer control removed from eco

## What changed (owner ruling: eco must never control systemd timers — they are essential)

The 2026-10-13 "wakeup reduction" timer-cadence work is fully reverted:

| Old control | Mechanism | Disposition |
|---|---|---|
| `state/owned/etc/systemd/system/snapper-cleanup.timer.d/10-cadence.conf` (1h→6h) | owned drop-in | **removed** repo + live (whole drop-in dir incl. two stale `.bak` pre-images) |
| `state/managed/trash-purge.toml` (user timer 1h→1d) | managed line-patch | **record retired**; live `~/.config/systemd/user/trash-purge.timer` restored to its own `OnUnitActiveSec=1h` |
| `lib/state.sh` `MANAGED_IDS` + `managed_label` | machinery | `trash-purge` removed |

Pre-images: `/tmp/10-cadence.conf.preimage-20261103`, `/tmp/trash-purge.timer.preimage-20261103`.
The state drop-in additionally carried an **uncommitted** `OnBootSec=10m` "fix" that never
converged (nothing checks that file — silent live/state divergence; it dies with the control).

## The burn (mechanism)

`snapper-cleanup.timer` was schedule-dead on systemd 262: `NextElapseUSecMonotonic=infinity`,
`LastTriggerUSec` empty — never fired since the drop-in landed. Consequence: snap-pac `number`
pairs (pacman pre/post) accumulated **3469** snapshots (IDs 6788→10253), and the
`limine-snapper-override.conf` cleanup hook inside `snapper-cleanup.service` (limine boot-entry
sync, MAX_SNAPSHOT_ENTRIES=24) never ran with it. Exact parser semantics of the drop-in's
list-reset (`OnUnitActiveSec=` + override) not pinned — same fragile class as the systemd-262
`Conflicts=` lesson.

## Restoration performed

1. Drop-in dir removed live; `systemctl daemon-reload` + `restart snapper-cleanup.timer`.
2. Timer fired immediately (elapsed `OnBootSec=10m`): cleanup ran, limine hook updated
   `/boot/limine.conf`.
3. Bulk drain needed 5 passes: each `snapper-cleanup` run aborts `number cleanup` with
   `Config is locked` after 15–60 s (batch 197–1147) — the lock contender is a user-session cron
   worker (`hermes-worker-cron` jobs hit snapperd at random intervals; also my first-pass
   `snapper list` probe). The package's per-delete plugin
   (`/usr/lib/snapper/plugins/10-limine-snapper-sync` → transient `limine-snapper-delete-*.service`
   per deletion) compounds it and trips `flock: 200: Bad file descriptor` (package bug worth
   reporting). Plugin paused (pre-image `/tmp/10-limine-snapper-sync.preimage-20261103`) for the
   final drain, then restored + one final `limine-snapper-sync`.
4. **Drained 3469 → 31** (= NUMBER_LIMIT 24 + 6 important + current); `/boot/limine.conf` trimmed
   172+KB → 105KB / 125 `protocol: linux` entries. `snapper-cleanup.timer` SubState=waiting with a
   finite next elapse; `trash-purge.timer` waiting on its own `OnUnitActiveSec=1h`; `./eco report`
   drift=0.
5. `trash-purge.timer` restored to `OnUnitActiveSec=1h` and restarted.

## Doc updates

`docs/findings.md` `## daemons` (verdict rewritten + `Timer-control retired` record; also fixed
the stale "PPD masked" / "TLP runs once at boot" claims in the same sentences), `AGENTS.md` new
facts row (eco never controls systemd timers), `docs/JOURNAL.md` entry, `lib/state.sh` comment.

## Open items for the owner

- Commit disposition (gate 96/96 — case19 count 16→15 with the retired record's anchor).
- `limine-snapper-sync` package: its per-delete plugin contends snapperd's config lock
  (`Config is locked` aborts long cleanup batches) and its per-delete sync runs fail with
  `flock: 200: Bad file descriptor` — worth fixing upstream/your build.
- Observation: `plocate-updatedb.timer` is masked system-wide (NOT eco state — external choice);
  since "systemd timers are essential", you may want it unmasked (`systemctl unmask
  plocate-updatedb.timer`) — left untouched.
- `limine-snapper-watcher.path` alias is dangling (`not-found`) — package-side, not eco.
