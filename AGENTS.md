# AGENTS.md — global memory (system-tuning)

Last reviewed: 2026-10-31 (migrated from `docs/MEMORY.md`; per-row fact dates preserved below).

## Memory architecture

- **Global memory — this file:** project overview, pitfalls, long-term rules. Established by
  inspection or decision; none of it should need re-derivation.
- **Active buffer — `.logs/scratchpad.md`:** current task state and working scratch; reset after
  each action.
- **Historical log — `docs/JOURNAL.md`:** chronological action journal, newest entry first; new
  entries are one-line summary pointers to `.logs/action-<date>-<name>.md` summaries.
- `benchmarks/` keeps its own memory pair (`benchmarks/docs/MEMORY.md`, `benchmarks/docs/NOTE.md`)
  under its stricter publication privacy rule — pointer, not copy; one fact, one home.
- Single source of truth: never duplicate rules or lists across docs — link with explicit
  Markdown pointers. Stamp entries `Last reviewed: YYYY-MM-DD` and re-verify on edit.

## Project overview

The canonical single-host tuning repo (merged 2026-09-28 from `eco-power` +
`System-Tuning-Benchmarks`): eco/power convergence machinery (`eco`, `lib/`, `state/`, `tests/`),
benchmark methodology + studies (`benchmarks/`), filesystem maintenance (XFS campaign archived
2026-10-05 at `docs/archive/XFS-TUNING.md`; root is btrfs since the reinstall). Public since
2026-10-17 (owner decision): live paths such as `state/owned/home/...` are exposed in-tree (they
are load-bearing, e.g. the `eco-power.service` ExecStart), while the `benchmarks/` subtree keeps
its stricter publication privacy rule (see `benchmarks/docs/MEMORY.md`) since that material is
republished outside the repo.

## Facts that are easy to get wrong

| Fact | How to check / why it matters |
| --- | --- |
| The test gate is `./tests/run` — one sequential bash script, 17 cases / 92 assertions (as of 2026-10-10; four section-scoping cases retired with the scx record — `docs/findings.md` `## sched`), no case selector | Run and filter labelled output (`./tests/run \| grep 'case3'`); `tests/work/` is wiped and regenerated every run |
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
| `beesd@.service`'s instance is the btrfs **filesystem UUID**, not a path: beesd greps `/etc/bees/*.conf` for `UUID=<instance>` and mounts subvolid=5 itself (hash DB lives in a `.beeshome` subvol it creates) | Dated 2026-10-05 (duperemove retired same day). bees has **no per-directory exclusion** — the old duperemove known-bad-tree mitigation does not transfer (`docs/rollback.md` `## Storage ops`) |
| Two concurrent `./tests/run` runs corrupt each other: the gate wipes and rebuilds `tests/work/` at start | In fleet work, exactly one agent runs the gate (the manager); all others use `bash -n`/grep checks only |
| Persistence outside `state/` dies silently at reinstall and is invisible to the repo: the NVMe queue drifted to vendor `kyber`/256 because the ledger's "foreign file" `/etc/udev/rules.d/60-ioschedulers.rules` was never owned | Burned 2026-10-05 (found by `docs/research/btrfs-tunables.md` §0). Now owned `state/owned/etc/udev/rules.d/61-eco-ioschedulers.rules` (61- keeps vendor sda/mmcblk rules; scheduler line first — elevator switches reset queue depth). Any knob whose persistence is "a foreign file" is a future repeat: check `docs/findings.md` Evidence lines for non-`state/` persistence |
| `ionice`/`IOSchedulingClass=idle` is dispatch-inert unless the elevator is mq-deadline or bfq (kernel doc `Documentation/block/ioprio.rst` + `block/mq-deadline.c`; zero `ioprio` use in kyber/NVMe driver) | Dated 2026-10-05, evidence in `docs/research/btrfs-tunables.md` §2.1. The installed `btrfs-scrub(8)` `-c/-n` deprecation note claims the opposite — man page is wrong; the flags are deprecated anyway |
| Git file modes are load-bearing for deploy: `lib/writers.sh` `write_owned` is `cp src tgt` — source mode wins when the target is new, old mode is kept when it exists | Burned 2026-10-05: `eco-power.sh`/`hw-tune.fish` sat at 100644 in git; a fresh deploy made them non-executable (service 203/EXEC; hw-tune's `[ -x ]` gate skips silently). Exec-bit drift is invisible to the suite and masked while the old live file pre-exists |
| `kernel.sysrq` bitmask: the task-dump group (p/t/m/l) is 0x08 — the popular "safe" value 438 omits it | Read the bitmask table in `Documentation/admin-guide/sysrq.rst` before choosing a mask; the repo's capture+rescue mask and its rationale live in `state/owned/etc/sysctl.d/97-sysrq.conf` (dated 2026-10-08) |
| A "knob is inert" claim needs the installed entrypoint and clean stderr: the 2026-10-08 claim "TLP never calls `set_sound_power_mode`" came from grepping `/usr/share/tlp/tlp` (does not exist) with `2>/dev/null`, which hid the error — the entrypoint is `/usr/sbin/tlp:47` and the knob is live | Burned 2026-10-08, caught by an independent diff review. Grep call sites in the real entrypoint (`grep -n <fn> /usr/sbin/tlp`), never silence stderr when searching for absence, and read the consumer (`cat /sys/module/snd_hda_intel/parameters/power_save{,_controller}`) before declaring any knob decorative |
| A managed foreign file dies silently when its owning package changes layout (scx_loader → scx-tools-git, 2026-10-10: `/etc/scx_loader.toml` removed) — and a missing managed target hard-fails **all** of `./eco apply`, so every wave stops, not just the scx one | Burned 2026-10-10: convergence halted ~10 h and live silently kept old values (it looked like "the daemon restored my edits"). After any package update run `./eco apply --dry-run`; `pacman -Qo <target>` names the owner of a foreign file; verify live == state by consumer readback, never by assumption |
| Benchmark arms must interleave + rotate inside one window; merging rows across windows is unsound | Dated 2026-10-14: 5 h of continuous load moved the energy floor (bore light phase_J 670→758 J; the 04:42 anchor fell outside the night control's own spread in 20/43 cells). Falsify drift with a same-arm anchor series before merging; evidence `benchmarks/studies/05-sched-comprehensive-benchmark/README.md` `### Sensitivity and robustness` |
| Direct-attach `sched_ext` needs root (CAP_BPF/RLIMIT_MEMLOCK); `scxctl stop` hangs while a direct-attach scheduler holds sched_ext | Burned 2026-10-14: a non-root start dies at `libbpf -EPERM` before any kernel event, and a restore step that sent its evidence to `/dev/null` looked successful. Kill direct-attach first and verify it died, then `scxctl stop`; a restore must log its own output and poll `sched_ext/state` for `enabled` |
| `scx_mlfq` 1.3.11 crashes at attach on this kernel: kernel runtime error `non-existent DSQ 0x100c`/`0x101b` in `mlfq_sched_switch`, sched_ext auto-disables | Dated 2026-10-14: 4/12 starts survived the night run, 3/50 in a top-up — REJECT, upstream bug candidate. Any slot harness must treat a failed attach as one invalid marker row and never let it poison later arms (`benchmarks/studies/05-sched-comprehensive-benchmark/README.md`) |
| Version strings in a report must be read from the live source at write time, never copied from an older doc | Burned 2026-10-14: study 05's intro shipped `7.3-rc4` copied from study 04 (September) while the run kernel was `7.3.0-rc6-1-cachyos-bore-lto`. `uname -r` + `who -b` (prove the kernel spans the measurement window) before writing any kernel claim |
| The owner's scheduler identity is deliberately never recorded in repo docs (owner policy, 2026-10-14) | Refer to "the owner's direct-attach scheduler" only. Tooling resolves the command at runtime: `$BENCH_RESTORE_CMD` or the uncommented `scx_*` session-autostart entry (`benchmarks/tools/night-run.sh`) — never hardcode or name it in scripts, logs, or prose |
| Dated volatile snapshots (kernel, RAM, disk, host config state) live in `AGENTS.md` `## Current state` (folded from host-level `~/docs/CURRENT.md`, retired 2026-10-31) | Entries are dated and replaced on re-measure, never accumulated; never bake volatile values into static doctrine docs. Burned 2026-10-15: a session handoff pointed its read-order at a repo `docs/CURRENT.md` that never existed — know which home a file lives in before writing a path |
| TLP is not a `scaling_max_freq` writer on this box: `CPU_SCALING_MAX_FREQ_*` unset → "not_configured", `CPU_MAX_PERF_*` is intel_pstate-only → no-op on amd-pstate | Dated 2026-10-29. Probe `/usr/share/tlp/func.d/10-tlp-func-cpu` (the real module — the entrypoint delegates) before blaming TLP for cpufreq cap clobbers; the observed overwriter is still unidentified and the ceil watch logs `CEIL DRIFT policyN <old> -> <new>` to name it (`docs/findings.md` `## timer`) |
| TLP also self-defers EPP to power-profiles-daemon: with PPD running, `set_cpu_perf_policy` returns early (`nop_ppd_active`) and warns instead of writing | Dated 2026-10-30. `/usr/share/tlp/func.d/10-tlp-func-cpu`; the repo's `CPU_ENERGY_PERF_POLICY_*` lines were removed the same day anyway (PPD sole writer — `docs/findings.md` `## epp`) |
| `asusd.ron` must never end with an empty line: asusd reverts the config when it finds one (owner warning) | Dated 2026-10-30. After every patch verify EOF bytes (`tail -c 2 /etc/asusd/asusd.ron \| od -An -tx1` → must not be `0a 0a`); check PROFILE now guards this (`docs/findings.md` `## asusd`) |
| A drop-in `Conflicts=` (empty assignment) does NOT clear a vendor unit's list on systemd 262 — the vendor value survives | Dated 2026-10-30. To remove one entry from a package unit's list, use a managed line-patch of the vendor file (`state/managed/`), not a drop-in; burned while neutering PPD's `Conflicts=tlp.service` (`docs/findings.md` `## epp`) |

## Current state (volatile dated snapshots)

Folded from host-level `~/docs/CURRENT.md` at the 2026-10-31 memory-architecture migration (host file retired). Dated snapshots of volatile host values that must not be baked into static docs (architecture: `~/.copilot/copilot-instructions.md` §0). Every entry is dated; re-probe before trusting. When a value here is re-measured, replace the entry — no history accumulation.

### Host snapshot — 2026-10-29 (probes: `uname -r`, `free -h`, `df -h /`, `pacman -Qkk pacman`, `snapper list`)

- kernel: `7.3.0-4-cachyos-lto`
- RAM: 30Gi total / 15Gi available
- `/`: 920G btrfs (181G used / 721G avail)
- `/etc/makepkg.conf`: locally modified (`pacman -Qkk pacman` → modification time + size mismatch) — not stock
- snapper `root`: 6 number snapshots (NUMBER_LIMIT 24 + 6 important; bulk prune 1620→6 on 2026-10-29; timer cadence fixed)

### Compositor config state — 2026-10-22 (re-probe: `ps -eo comm= | grep -E 'niri|umbriel'`, `ls /run/user/1000/wayland-*`, `busctl --user status org.freedesktop.ScreenSaver`)

- Active WM: **umbriel** (`umbriel-git`, `umbriel msg <action> …`) on `wayland-0`; the Noctalia
  shell stack (`noctalia msg …`, plugins, idle chain) runs on it. **Niri retired 2026-10-22**
  (no niri process; `~/.config/niri/` unchanged, kept for rollback).
- umbriel config at `~/.config/umbriel/` — `umbriel config validate` → `config: ok`;
  terminal **ghostty** (`Mod+Return`), full theme palette in `noctalia.toml` (now
  `[include.optional]`), output has `tearing`/`bit_depth=10`/`xwayland_native_resolution`,
  touchpad retuned.
- Open items for the owner: `Ctrl+Shift+3` screenshot-window bind (needs slurp or an upstream
  action), `Mod+Ctrl+C` center-visible-columns, mouse `scroll-factor 2`. Rationale lives in
  `~/docs/NOTE.md` 2026-10-19 — the config files carry no comments by request.
- `~/.config/noctalia/config.toml` + `~/.local/state/noctalia/settings.toml` are **not** part of
  this translation; Noctalia also pushes a theme at runtime that can override `[colors]`.
- Verified on umbriel 2026-10-22 (plugin work): idle chain logs in the journal
  (`[idle] …` from `umbriel[...]`), `org.freedesktop.ScreenSaver` exposes only
  `Inhibit`/`UnInhibit` (no `SimulateUserActivity`), logind blocker suppresses behaviours
  (`screen-off suppressed (screensaver inhibit locks=1)`).

### Boot config state — 2026-10-21

- `/boot/limine.conf` regenerated mid-session by `limine-entry-tool` (ALPM hook, 2026-10-21 11:48–11:49):
  172,881 B / 204 `protocol: linux` entries (sha256 `e13ec7eb…`) — was 172,814 B at 10:26. The 6 MB
  failing artifact stays preserved as `/boot/limine.conf.full-20261020` (7de97d12…, unchanged).

### Ananicy rules state — 2026-10-21

- `ananicy-cpp.service` enabled+active (re-enabled by owner same day; had been disabled+masked since
  2026-10-06 for set_priority spam). Config: `check_freq=60`, `loglevel=critical`, `log_applied_rule=false`.
- Rule corpus 15828 = package 15813 + `/etc/ananicy.d/10-local.rules` 17; IN_DIFF count now **0**
  (was 10). Local files: `10-local.rules`; package files locally edited (9) — pre-images in
  `~/docs/backups/2026-10-21-ananicy/`. Owner's own edit: `00-types.types` `Game` nice -8→-6 (+`Launcher` type).
- Not covered by name (runtime argv[0] is dynamic): zen contentprocs, netease gpu/renderer/utility
  (main+zygote ARE covered via `app.asar` / zygote alias). Unruled by choice: systemd core, kernel
  threads, copilot CLI, the owner's direct-attach scheduler (sched_ext **enabled** — re-probed
  2026-10-21, supersedes the 2026-10-15 "disabled" note; identity never recorded here — owner policy).

### Aranicy daemon state — 2026-10-28 (probes: `pacman -Q aranicy`, `systemctl is-active aranicy`, `ls /var/lib/aranicy`)
- Host package: **aranicy 0.2.1-1** scratch build from the local working tree
  (~/Workspace/aranicy-pkgbuild; local-tarball PKGBUILD variant) — official
  v0.2.1 tag/package NOT cut (disposition pending). Rollback:
  `sudo pacman -U ~/Projects/gentoo-style-arch/packages/stable/aranicy/aranicy-0.2.0-1-x86_64.pkg.tar.zst`.
- aranicy.service active (eBPF exec events; StateDirectory=aranicy).
  The owner's direct-attach scheduler runs manually (command never recorded here — owner policy;
  tooling resolves it at runtime).
- /etc/ananicy.d/ananicy.conf carries `bias_group.build = ^(cc1.*|lto1.*|collect2|as|ld.*)$`
  (backup: ananicy.conf.bak-20261028-1210). bias_* knobs/bias_group need a
  service restart to take effect (--reload swaps rules/config only).
- /var/lib/aranicy/bias-state populated (unprivileged `aranicy dump bias`).
- Evidence tree for the fuzzy/sensitivity wave: ~/Workspace/aranicy-build-val/evidence/;
  open follow-up: sparse-window confidence decay (bias-confidence-sparse).

### Default applications / MIME state — 2026-10-29 (probes: `xdg-mime query default <mime>`, `grep -c ... ~/.config/mimeapps.list`)
- `~/.config/mimeapps.list` active (pre-image backup: `~/.config/mimeapps.list.bak-20261029-2226`).
- Total broken desktop references: **0**.
- Office suite: LibreOffice (`libreoffice-writer`, `libreoffice-calc`, `libreoffice-impress`, `libreoffice-draw`, `libreoffice-math`). OnlyOffice uninstalled and all associations retired.
- Code / markup / configs: VSCodium (`vscodium.desktop` via `/usr/bin/codium %F`).
- Browser / Web: Zen Browser (`userapp-Nightly-XE01W3.desktop` / `zen-browser.desktop`).
- PDF / XPS: `zen-browser.desktop` (PDF), `org.gnome.Evince.desktop` (PostScript/XPS).

### 2026-10-30 — noctalia annotation zoom/pan (delivered, awaiting maintainer actions)

- Upstream PR #5111 open (noctalia-dev/noctalia, from fork ZhangDM-520): zoom/pan for the
  screenshot annotation editor. Awaiting upstream review; rebase the gsa patch when main moves.
- gsa tree commit f2d0e98: `packages/git/noctalia-git/0001-capture-annotate-zoom-pan.patch` +
  PKGBUILD prepare(); built `noctalia-git-5.4.0.r6061.gaa66386ce-1-x86_64.pkg.tar.zst` (makepkg,
  PGO) — NOT installed. Install + live smoke (Ctrl+wheel / Ctrl+drag / toolbar zoom) pending.

### scx scheduler host facts — 2026-10-30 (probes: `scx_mavd` runs, `ps -eo comm=`, socket probe)
- scx-scheds-git 1.1.4.r111.gda3c98b30; the owner's direct-attach scheduler runs manually.
- **scx_mavd is unrunnable on kernel 7.3.0-rc6**: BPF load fails at `scx_lib_init_probe` (-EINVAL, flag-independent) — its experimental sub-scheduler kernel ops are missing. Any future mavd live check needs a newer kernel first.
- aranicy.service = packaged 0.2.1-1 (the multi-scheduler sampler is committed but not yet packaged/released).
