# 2026-11-11 — genarch 0.2.0: profiles, layered intent, release

## Outcome

- `genarch-settings` v0.2.0 tagged and pushed (`568353a`, four commits on `bb9a5b2`).
- Package `genarch 0.2.0-1` built from the recipe (`makepkg -f`, tag clone) and installed;
  `/etc/genarch/profile` selects `zenbook-s16`, `/usr/lib/genarch/profiles/zenbook-s16` carries
  the machine facts that used to be package data and code defaults.
- Live after upgrade: `report` drift=0 (PROFILE/MIRROR/MANAGED/SYNC/CEIL/CO/POWER/WIFI/TIMER/
  PRUNE green, SMU SKIPPED unprivileged), `apply --dry-run` PLAN 0, `apply` in post_install
  planned 0 changes, `converge ceil` clean exit.
- Recipe: `packages/stable/genarch` 0.2.0, MIT, drops its own `install.sh` copy (sourced from the
  tag), copies `intent/` whole and ships `/etc/genarch/profile` as a pacman backup file.

## Ledger delta

`docs/contract.tsv`: `PROFILE	findings#intent` added first, `IO	findings#writeback` removed
(SYNC already reports every sysctl from `converge::plan`). Eleven rows.

## Engine waves (all in `genarch-settings`)

1. `3d89fa9` host seam: `RunResult`, `write_file` over `Fs`/`SystemFs` with a recording fixture.
2. `b205d77` layers: base/profile/operator, per-key merge, `[omit]` tombstones, `[requires]` →
   PROFILE drift, ceilings/passes/SMU/units as data, `tree` module, manifest-only prune,
   dormant ownership so a deselected profile cannot prune `/etc/fstab`.
3. `2f76d4e` report: `Planned` carries the record, `sysctl_drift` is the only derivation,
   JSON schema 2 with a top-level `profile`.
4. `568353a` release: MIT, LICENSE/SCOPE/CONTRIBUTING, `install.sh` in-tree, README truth, 0.2.0.

Gate at each wave: `cargo test` (65 green at the end: 22 unit / 27 behavioural / 12 layer /
4 contract), `cargo clippy --all-targets` clean, live `report` drift=0 and `apply --dry-run`
PLAN 0.

## Rollback

The 0.1.1 intent tree is at `/var/backups/genarch-0.1.1-intent-20261111.tar.gz`; the engine's own
dated pre-images are beside every file it rewrote. Reverting means reinstalling 0.1.1 and restoring
that tarball, then `genarch apply` (0.1.1 reads schema 2 — the current intent is schema 3).
