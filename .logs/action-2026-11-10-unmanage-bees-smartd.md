# Action — 2026-11-10: unmanage beesd and smartd/SMART alerting

## Decision (owner ruling)
Dedupe (`beesd@`) and SMART monitoring (`smartd` + `/usr/local/sbin/smart-alert.sh`) are the
host's own setup. Another session added the beesd nightly-window work and the repo had adopted
both objects into `state/owned`; the owner did not steer that, and it is now out of project scope.
The package-level statement of the boundary is `docs/rollback.md` `## Storage ops` ("Scope
boundary (owner ruling 2026-11-10)"), with the durable rule row in `AGENTS.md`.

## Removed from `state/owned` (git rm for tracked, rm for the untracked session additions)
- `etc/bees/beesd.conf`
- `etc/systemd/system/beesd@.service.d/10-log-rate-limit.conf` (tracked) and
  `20-nightly-window.conf` (untracked, added 2026-11-09 by the other session) — dir removed
- `etc/systemd/system/beesd@.timer`, `beesd-stop@.service`, `beesd-stop@.timer` (all untracked)
- `etc/smartd.conf`, `usr/local/sbin/smart-alert.sh` (both tracked)

## Live left byte-identical (nothing was deployed or deleted)
`eco apply` only ever writes; it cannot delete a live file, so unmanaging is a no-op on the system.
Live sha256 at removal time (the recovery anchor now that the repo no longer carries the content):

```
7af4930278296c8d98bcb04d389eac514adf244439772efde9f22a72b7bed064  /etc/bees/beesd.conf
535427f3327e11d9b9c8d9473e251d244d6863f53f60bb02391b9850ffc69d0d  /etc/smartd.conf
0fcfca5f3f7a52d507458a4173dc2b1a5a4fe08b4a6b8b9e4a92d80f51610c29  /usr/local/sbin/smart-alert.sh
623096f1c403e1ea275e8f495fbea24d4a36e25817b1010bb0b38b2e144fff61  /etc/systemd/system/beesd@.service.d/10-log-rate-limit.conf
21a09c2796e03cfe97acdac12b6b5d691ddc381410902e2448de10edd66749fc  /etc/systemd/system/beesd@.service.d/20-nightly-window.conf
32e67e58d7467d15f22e63654f6ca4b1a0d5caa14362717e1790e0297d181e95  /etc/systemd/system/beesd@.timer
ceef51b48dc23ded6c4e76bb183b5c1ac842e89da97d73e60293b2a216591526  /etc/systemd/system/beesd-stop@.service
0c85339ebf2528b49839be1730d5babab8f5df7c2de923d40268521fa0930f8f  /etc/systemd/system/beesd-stop@.timer
```

Tracked content is still recoverable from git history (`git log -- state/owned/etc/bees`).

## Docs updated to match
- `docs/rollback.md` — scope boundary paragraph at the head of `## Storage ops — what runs
  automatically`; beesd and smartd rows marked *host setup, not repo-managed*; re-check commands
  labelled observation-only (new `systemctl show 'beesd@*' -p RuntimeMaxSec -p Restart`).
- `docs/findings.md` — `## fstrim` (bees is no longer repo-written) and `## daemons` (dedupe +
  SMART are out of `eco report`).
- `AGENTS.md` — new fact row stating the scope boundary with the removal hashes; the beesd
  instance-is-FSUUID row kept as a **host fact only**.
- `.github/copilot-instructions.md` — the storage bullet no longer claims `state/owned` units
  behind dedupe/SMART (the scrub timer and fstrim remain stock systemd units).
- `docs/JOURNAL.md` — new 2026-11-10 entry; the other session's 2026-11-09 beesd entry kept as
  history with a "reversed repo-side" clause.
- Left alone: `docs/research/btrfs-{optimization,tunables}.md` (dated research records; they
  describe the wave as it happened, and rewriting them would falsify the record).

## Verification
- `find state -ipath '*bees*' -o -ipath '*smart*'` → empty.
- Live files still present with the hashes above; beesd timers still scheduled
  (`list-timers 'beesd*'`), so the host behaviour is unchanged.
- `./eco apply --dry-run` → `PLAN 0 change(s)`; `./eco report` → `drift=0` (unchanged).
- `./tests/run` → 119 / 119.
