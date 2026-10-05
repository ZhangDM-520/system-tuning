# Project Memory — system-tuning

Durable facts, pitfalls and lessons for this repository. Established by inspection or decision;
none of it should need re-derivation. Session chronology lives in `docs/NOTE.md`; benchmarks-era
standing decisions stay in their original home at `benchmarks/docs/MEMORY.md` (pointer, not copy —
one fact, one home).

Last reviewed: 2026-10-05.

## What this repository is

The canonical single-host tuning repo (merged 2026-09-28 from `eco-power` +
`System-Tuning-Benchmarks`): eco/power convergence machinery (`eco`, `lib/`, `state/`, `tests/`),
benchmark methodology + studies (`benchmarks/`), filesystem maintenance (XFS campaign archived
2026-10-05 at `docs/archive/XFS-TUNING.md`; root is btrfs since the reinstall). Private: live
paths such as `state/owned/home/...` are expected here, while the `benchmarks/` subtree keeps its
publication privacy rule (see `benchmarks/docs/MEMORY.md`).

## Facts that are easy to get wrong

| Fact | How to check / why it matters |
| --- | --- |
| The test gate is `./tests/run` — one sequential bash script, 21 cases / 112 assertions (as of 2026-10-05), no case selector | Run and filter labelled output (`./tests/run \| grep 'case3'`); `tests/work/` is wiped and regenerated every run |
| No build, no lint config, no CI | `bash -n` / ad-hoc `shellcheck`; the suite is the only gate |
| Report IDs are locked to `lib/registry.sh` *and* hardcoded in `tests/run` (case1/case7) | Changing the check set means registry + reader + doc anchor + test list in one change |
| `CHECK_DOC` anchors are shorthand, not filenames: `findings#asusd` lives in `docs/findings.md` | Follow the string from `lib/registry.sh` to the `##` heading, not from the filename |
| Verdict semantics are test-contracted | case17 asserts `SKIPPED` (and its "counted green" semantics) appear in both `docs/eco-power-README.md` and the `eco` usage text |
| Frozen contract (owner Q1, never move unilaterally): the case17 pair — literal `SKIPPED` and its counted-green semantics sentence (docs/eco-power-README.md + ./eco), `CHECK_IDS` (14 IDs, `lib/registry.sh`), `rollback#sd`/`rollback#misc` emit strings (`lib/readers.sh`, 4 sites) and their `## sd`/`## misc` headings | case17 pins the strings; case19 pins resolution; a `## misc` repoint of *outbound* handles is allowed, the headings/undo text are not; never quote the semantics sentence literally outside the case20 allowlist |
| case19/case20 are the doc-contract guards: case19 = every `PREFIX#slug` consumer anchor (registry, emit 4th args, `doc =` records) resolves to a real `##` heading; case20 = the SKIPPED-semantics phrase has exactly one canonical pair plus allowlisted copies | Added by the 2026-09-29 docs unification (suite was 20 cases / 107 assertions then); they turn the anchor and one-home rules into red tests |
| Every live read/write goes through `live_path()` with the `ECO_ROOT` seam | Empty `ECO_ROOT` = live root; tests point it at fixture trees; `assert_in_root` refuses any write outside it |
| `state/managed` records are flat TOML (`toml_get` reads top-level `key = 'value'` only) | No tables, arrays, or multi-line values in a record; a missing required key hard-fails |
| State layout is a naming rule, not a map: owned = `state/owned/<live-path-without-leading-slash>`; managed = the record's own `target` key (`docs/eco-power-README.md` `## State layout`) | `find state/owned -type f` is authoritative. The File map burned once (rows vs files drift, fixed 2026-09-29) and was deleted in favor of the rule |
| A systemd-sleep hook blocks the `user.slice` thaw — never `sleep` in one | Measured 5.1 s stall per resume from the `sleep 5` second pass in `eco-power.sh`; the resume path is now single-pass (`state/owned/usr/lib/systemd/system-sleep/eco-power`). Verify with the "System returned from sleep" → "Successfully thawed" journal delta |
| Journald `SystemMaxUse` is forensics capacity, not just disk hygiene | The 32 M cap vacuumed a whole freeze boot (2026-09-28) mid-investigation; raised to 256 M. Check `journalctl --disk-usage` and `journalctl --list-boots` before trusting a boot is gone |
| Hard freezes leave evidence only if pstore is armed | `efi_pstore.pstore_disable=0` on the limine cmdline (outside repo state; `docs/findings.md` `## suspend-resume`); stale `hung_task` panic records from 2026-09-19/20 recovered in `~/Workspace/suspend-forensics/pstore-existing/` |
| `AE_AML_LOOP_TIMEOUT` in `dmesg`/journal = ACPI interpreter gave up after ~30 s on a looping method | A stall marker (seen on `\_SB.ALIB`/`EC0._QDA`), not proof of the culprit — correlate with asusd platform_profile writes and TB/USB4 D3 refusals (`docs/findings.md` `## suspend-resume`) |
| systemd-sleep executes EVERY file in `/usr/lib/systemd/system-sleep/`, including `.bak` pre-images | Burned 2026-09-29: a stale backup hook ran the old two-pass resume path for hours (stalled every thaw ~5 s and contaminated the SMU experiment). Pre-images for that dir go to `system-sleep-backups/` (`lib/writers.sh` `backup_step`; rule home `docs/rollback.md` `## Undo: universal mechanism`) |
| Every rule has one doc home (findings / judgment / rollback / eco-power-README / the archived `docs/archive/XFS-TUNING.md`); `.github/copilot-instructions.md` carries agent synthesis only and never restates contract rules | Anchor routing — the only "doc map", there is no map table — is `docs/eco-power-README.md` `## Finding the writeup`; when any instruction file and a doc disagree, the doc wins and the instruction file is what gets fixed |
| A dead key in a `state/owned/etc/sysctl.d/*` file makes `./eco apply` fail **partway** (exit 3): `runtime_apply` runs `sysctl -w … \|\| die3_partial` *after* the file writes, and `reload_step`'s `sysctl --system` hard-fails too | Burned 2026-10-05: the XFS-era `fs.xfs.xfssyncd_centisecs` key died with the btrfs reinstall. Before apply, check every owned sysctl key exists live (`sysctl -n <key>`) |
| `./tests/run` case16 exercises the **live** `./eco apply --dry-run` | A broken live environment (missing managed foreign file, dead sysctl, …) reddens the gate on a pristine tree — run the dry-run before suspecting the repo (burned 2026-10-05: 111/112, red cleared by restoring `/etc/scx_loader.toml`) |
| EPP `dynamic(profile:…)` mode is kernel-branch-locked: the 7.3.0-rc* cachyos branch accepts `echo dynamic` and renders `dynamic(profile:<profile>)`; 7.2.9-1-cachyos rejects the write (EINVAL) and renders `default` as `balance_performance` — its `energy_performance_available_preferences` also lies (lists `custom`, whose store fails) | Dated 2026-10-05. Settled by extracting each `/usr/lib/modules/<k>/vmlinuz` and grepping `dynamic(profile`: present in 7.3.0-rc5-bore-lto, absent in 7.2.9. The check contract wants `dynamic*`, so EPP DRIFTs on 7.2.9 until the owner boots the rc family or reopens findings#epp |
| Git file modes are load-bearing for deploy: `lib/writers.sh` `write_owned` is `cp src tgt` — source mode wins when the target is new, old mode is kept when it exists | Burned 2026-10-05: `eco-power.sh`/`hw-tune.fish` sat at 100644 in git; a fresh deploy made them non-executable (service 203/EXEC; hw-tune's `[ -x ]` gate skips silently). Exec-bit drift is invisible to the suite and masked while the old live file pre-exists |
