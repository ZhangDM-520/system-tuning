# Action: Convert beesd to Nightly Scheduled Maintenance Window (00:30 to 04:00)

- **Date:** 2026-11-09
- **Scope:** Deduplication, systemd automation, resource reclamation
- **Files Modified/Created:**
  - `/etc/systemd/system/beesd@.service.d/20-nightly-window.conf` (mirrored in `state/owned/`)
  - `/etc/systemd/system/beesd@.timer` (mirrored in `state/owned/`)
  - `/etc/systemd/system/beesd-stop@.timer` (mirrored in `state/owned/`)
  - `/etc/systemd/system/beesd-stop@.service` (mirrored in `state/owned/`)
  - `docs/rollback.md` & `docs/findings.md`

## Summary of Changes

1. **Retired 24/7 Daemon Mode:**
   - Unhooked `beesd@521bbdbd-77e2-4a70-a8f7-9bda99558cde.service` from `basic.target.wants/`.
   - Stopped running live process PID 1417 cleanly (`Deactivated successfully`).
   - Reclaimed ~1.03 GiB RSS RAM and eliminated daytime CPU contention.

2. **Scheduled Window Architecture:**
   - **Start Timer (`beesd@.timer`):** Fires daily at `00:30:00` with `Persistent=false`.
   - **Service Bounding (`20-nightly-window.conf`):** Configured `RuntimeMaxSec=3h 30min` (`Restart=no`), capping execution window at 04:00:00.
   - **Fail-safe Stop Timer (`beesd-stop@.timer`):** Fires daily at `04:00:00` with `Persistent=true` triggering `beesd-stop@.service` (`systemctl stop beesd@%i.service`). Guarantees immediate cleanup upon resume if machine was suspended across 04:00.

3. **Verification:**
   - `systemctl list-timers` verified:
     - `beesd@521bbdbd-77e2-4a70-a8f7-9bda99558cde.timer` armed for `00:30:00 CST`.
     - `beesd-stop@521bbdbd-77e2-4a70-a8f7-9bda99558cde.timer` armed for `04:00:00 CST`.
   - `ps aux | grep bees` confirms 0 bees processes running in daytime.
   - `~/Projects/system-tuning/tests/run`: 119/119 assertions green.

## Status update — 2026-11-10
Repo management of this work was reverted by owner ruling: dedupe is host setup, not
repo-managed. The `state/owned` copies listed above were deleted (the `beesd@.service.d/` dir
included) and the live files were left byte-identical — the live mechanism described here is still
in force. Boundary and live hashes: `.logs/action-2026-11-10-unmanage-bees-smartd.md`,
`docs/rollback.md` `## Storage ops`.
