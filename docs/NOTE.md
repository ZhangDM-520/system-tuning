# NOTE — session journal

Running log of work on this repository. Durable knowledge is mined upward into `docs/MEMORY.md`;
this file keeps chronology and in-flight state. Newest entry first.

---

## 2026-10-17 — kernel attribution research landed; mechanism corrected

### What changed

- Background research delivered `docs/research/2026-10-17-epp-deadlock-kernel-attribution.md`
  (primary sources: mainline `platform_profile`/`amd-pstate`/kernfs code, local `vmlinux` address
  mapping, MARC prior art). **Verdict: kernel-blamed YES** — lock-order inversion in the
  platform_profile core: `profile_lock` held across `device_register`/`device_unregister`/
  `sysfs_update_group` (which drain kernfs active refs) vs sysfs callbacks taking `profile_lock`
  under their active ref. Triggered from the cpufreq store path under `policy->rwsem` by the
  in-tree amd-pstate dynamic-EPP feature (mainline commits `e30ca6dd5345`, `798c47593cca`,
  `b7294b627598`); no CachyOS patch involved. Same cycle independently patched upstream by Daniel
  Lezcano (2026-10-14 series, unmerged as of 2026-10-17; Message-IDs in the report — MARC is
  unreachable from this host, so the thread was not re-fetched here).
- **Correction to the earlier 2026-10-17 entry and to `docs/findings.md` `## epp`:** the ABBA via
  `amd_pstate_profile_set` wanting `policy->rwsem` is REFUTED — the callback acquires zero locks
  (mainline source + local disassembly). The `735d392` mitigation stands unchanged (exposure
  reduction: fewer register/remove cycles and needless `policy->rwsem` acquisitions); only the
  mechanism claim moved. Findings points at the attribution report as the mechanism's one home.

### Open (owner decides)

- Reply to the Lezcano series with the reproduction and the secondary ask (amd-pstate should not
  register platform-profile devices under `policy->rwsem`)? Paste-ready block in the report's
  recommended-fix section.

### Gate

- `./tests/run` 93/93 green (2026-10-17) after the docs edits in this entry.

## 2026-10-17 — boot D-state deadlock (dynamic EPP vs asusd): ordered + drift-only

### What changed

- Owner-side forensic report landed at `docs/research/2026-10-17-boot-epp-deadlock-report.md`:
  3/3 dock-at-boot boots (2026-10-17) wedged in kernel `D` state inside `eco-power.sh`'s EPP loop.
  Root cause per its `vmlinux` analysis: the default→`dynamic` transition registers per-CPU
  platform-profile handlers while holding `policy->rwsem` and fires the platform_profile notify;
  asusd's woken handler walks those handlers under `profile_lock` wanting the same rwsem (ABBA).
- **Fix (exposure reduction, not a guarantee):** `eco-power.service` is now
  `After=multi-user.target tlp.service asusd.service` — tlp's boot pass is the single boot
  transition writer and eco-power runs last (ordering verified acyclic: no cycle lines in the
  boot journals, `systemd-analyze verify` clean). `eco-power.sh`'s EPP loop is drift-only: it
  matches the rendered `dynamic*` and writes only on drift — the report's proposed `!= dynamic`
  comparison would never suppress on this kernel (`dynamic(profile:…)` is the rendered value), and
  a same-value write still takes `policy->rwsem`.
- Fixture mirrors re-synced in lockstep (`tests/fixtures/usr/local/sbin/eco-power.sh`,
  `tests/fixtures/etc/systemd/system/eco-power.service`; the latter also picked up the missing
  second `ExecStart` — pre-existing mirror drift). Ledger updated: `docs/findings.md` `## epp`.

### Not claimed / open

- The wedge is unreproduced under the fix (needs dock-at-boot reboot cycles): verification here is
  code paths + suite + unit verification only. tlp's boot pass still transitions 24 policies under
  the same kernel race — the durable fix is kernel-side lock ordering; upstream report candidate.

### Gate

- `./tests/run` 93/93 green (2026-10-17) after the docs edits in this entry.

## 2026-10-15 — session refresh from handoff; CURRENT.md pointer drift fixed

### What changed

- Session refreshed from `/tmp/handoff-20261015.md`. Prior campaign state confirmed complete and
  pushed (0 commits ahead of `origin/master`); tree clean except the owner's untracked
  `TEMP-benchmark-candidates` (untouched).
- **Pointer drift fixed:** the handoff's read-order pointed at repo `docs/CURRENT.md`, which does
  not exist — dated host snapshots live in host-level `~/docs/CURRENT.md` (global path-anchoring:
  host facts win there). Handoff corrected; `docs/MEMORY.md` gained the pointer row so future
  handoffs stop repeating it. No repo code or state changes.
- Handoff commit list was one behind: `89fa15e` (bees verbosity cap, 2026-10-14) postdates the
  newest listed `f80c918`; recorded in the handoff.

### Open (owner decides)

- Upstream bug candidate: the scx attach-time kernel runtime error (`non-existent DSQ` in
  `mlfq_sched_switch`) — evidence in study 05; report not yet written.
- Adaptive-scheduler thesis untested by phase-mode data; instrument is the `alt` mode of
  `benchmarks/tools/scx_deep.py`.

### Gate

- `./tests/run` 93/93 green (2026-10-15) after the docs edits in this entry.

## 2026-10-14 — scx_loader masked; scheduler-identity policy for the repo

### What changed

- **`scx_loader` stopped and masked** (owner-approved). It was only D-Bus-activated
  (`Type=dbus`, `org.scx.Loader`) — disabled at boot already, revived by any `scxctl` call. The
  owner's scheduler is a direct-attach via session autostart and is unaffected. While masked:
  `scxctl` is unusable, and `benchmarks/tools/night-run.sh` preflight now fails fast with a clear
  message (it needs `scxctl` to switch arms — unmask before any scheduler benchmark).
  Leftover `/run/systemd/system/scx_loader.service.d/` drop-in removed.
- **Owner policy recorded: the owner's scheduler identity is never named in repo docs.** Scrubbed
  the existing owner-usage claims (`docs/findings.md` `## sched` observed lines + owner-runs
  clause; this journal's 2026-10-10/2026-10-13 wave entries; study 05 prose). Arm names remain
  only as benchmark/analysis subjects. `benchmarks/tools/night-run.sh` and the study drivers now
  resolve the end-state command at runtime (`$BENCH_RESTORE_CMD`, else the uncommented `scx_*`
  session-autostart entry) and log `ops=set/none` instead of the ops name.
- `./tests/run` 93/93 green after the findings edits.

### Known residue

The 2026-09-20 forensics entry quotes pstore kernel evidence that contains the scheduler ops
string verbatim (literal evidence — deliberately not rewritten). Say the word if those quotes
should be redacted too.

## 2026-10-14 — 05-sched-comprehensive-benchmark: overnight 12-arm scheduler campaign

### Outcome

- Study landed: `benchmarks/studies/05-sched-comprehensive-benchmark/README.md` — per-phase ranked
  tables (medians + MW-U p vs bore, Gate-1+2), wake-latency axis, sensitivity runs, recommendation.
  Rows: `benchmarks/data/scx-deep.jsonl` passes `night-core`/`night-real` (00:02–03:42), plus an
  mlfq top-up series and a bore window-drift anchor (03:58–04:54).
- **Verdict: no adoption.** Every scx arm significantly regresses desktop-feel latency (light wake
  p99: bore 29 µs vs 459–6664 µs; storm t2/energy) while its batch wins (media/git/web/io) fail the
  "no metric significantly worse" clause. BORE stays the default. Workload-scoped candidates
  documented, not adopted: **tickless** (encode/build session: media fps +5.7% at −5.2% J, git
  −23%, web wall −28%; idle J +71%, storm t2 2.5x) and **cosmos `-g -P -a`** (best scx wake tails;
  storm 2x).
- **mlfq REJECT (reliability):** `scx_mlfq` 1.3.11 crashes at attach with kernel runtime error
  `non-existent DSQ 0x100c`/`0x101b` in `mlfq_sched_switch` (4/12 starts overnight, 3/50 post-run)
  — upstream bug candidate. Achieved n: 5 usable per arm per pass except mlfq 4/3 (screening only).
- **pandemonium arm (benchmarked):** not justified over BORE on phase-class data (light wake p99
  459 vs 29 µs; storm t2 5.18 vs 4.30), wins web energy −19%, git status, io meta. Adaptivity
  claim untested — phase mode only; `scx_deep.py alt` mode is the instrument. The owner's
  end-state scheduler was restored and verified after the run — identity deliberately not
  recorded here (owner policy, 2026-10-14).

### Harness changes (uncommitted, ask-first)

`benchmarks/tools/{scx_deep.py,scx_deep_analyse.py,night-run.sh,README.md}`: real-world phases
web/mixed/media/git + derived EDP; `LOWER_BETTER` gaps fixed (`sb_wk_max`, `sb_rq_pct50_0` were
mis-annotating verdicts); night-run restore hardening (direct-attach needs root/CAP_BPF; log
evidence + poll for `enabled` + retry); tools README dependency row.

### Lessons (MEMORY candidates)

- **Version strings in a report must be read from the live source at write time.** The study 05
  intro shipped `7.3-rc4` copied from study 04's September text while the machine had run
  `7.3.0-rc6-1-cachyos-bore-lto` all along (owner caught it 2026-10-14; fixed the same day).
  `uname -r` (and `who -b` to prove the kernel spans the run) before writing any kernel claim.

- **Cross-window drift is real:** 5 h of continuous load moved the energy floor (bore light
  phase_J 670→758 J, anchor outside night spread in 20/43 cells). Interleave+rotate within a run
  is mandatory; cross-window row merging is unsound. The anchor falsification caught it.
- **Direct-attach sched_ext requires root** (user: `libbpf -EPERM`); `scxctl stop` hangs while a
  direct-attach scheduler holds sched_ext — kill direct-attach first, verify death, then stop.
- **Restore steps must log and verify**: the failed 03:42 restore sent its evidence to `/dev/null`.
- **Completion watchers must target exact marker filenames** — a stale `.done` from an earlier run
  false-positived the first watcher.

## 2026-10-13 — scan applied: nodiscard + ASPM revert + wake/hygiene wave

### What changed

- **btrfs `nodiscard` on all 8 mounts** (owner-approved): `state/owned/etc/fstab` is now a
  repo-owned mirror carrying `nodiscard` — the ledger's documented design, while the kernel default
  `discard=async` had been silently active since the reinstall. Runtime remounted the same day.
- **ASPM arm (f) closed**: `PCIE_ASPM_*` back to `powersave` (record + fixture, TLP restarted);
  readback `[powersave]`.
- **Wake trim**: GPP0/GPP1 (USB4 bridges) added to `eco-power.sh`'s loop (record + fixture);
  readback `*disabled` on both.
- **Wakeup hygiene**: `snapper-cleanup.timer` hourly → 6h (owned drop-in), user `trash-purge.timer`
  hourly → 1d (managed record), `man-db.timer` disabled-but-active → enabled (capability kept).
- **Login dedupe**: XDG autostart duplicates of fcitx5/kdeconnectd hidden in
  `~/.config/autostart` (owned) — niri's spawns are the single-instance path.
- **One-writer claim**: `vm.swappiness=150` claimed in
  `state/owned/etc/sysctl.d/95-zram-swappiness.conf` (vendor writes 100, zram udev writes 150).
- **Housekeeping**: `/etc/cron.hourly/snapper` → `.disabled` (latent double-run if cronie lands),
  `/etc/locale.gen.pacsave` removed, the two `.bak-20261011` pre-image copies removed (git history
  holds the originals).
- Ledger updated: `## fstrim` (drift closed), `## pcie` (arm (f) closed), `## io-stack`
  (swappiness claim), `## daemons` (cadences, bpftune owner-kept, wake trim, dedupe), `## sched`
  (pandemonium rejection qualified).

### Findings recorded

- btrfs option-display trap: `nodiscard` is **invisible** in `findmnt`/`mount` — `discard=async` is
  the only discard token ever printed. Verify by its absence (or by dmesg "turning on async
  discard" at boot meaning the default was on).
- Owner rulings this wave: a deliberately chosen out-of-tree scheduler runs (identity not
  recorded, owner policy 2026-10-14; ananicy-cpp auto-nice is disabled;
  the old scheduler benchmark may have been confounded by it — with nice already optimised there is
  little scheduling room left; full benchmark pending owner's call), and bpftune is owner-kept
  (watch as a possible sysctl co-writer and as the lead for the unidentified `snd_hda_intel`
  writer).

### Open

- Not selected, owner keeps for now: `sched_util_clamp_min=1024`, bpftune masking, capability cuts
  (HDR/120 Hz, kdeconnectd/print-applet, Bettbox identification).
- Scheduler benchmark when the owner calls it; at-spi-dbus-bus login failure still untriaged.

## 2026-10-13 — asusd re-claimed: the EPP/governor cast collision closed

### What changed

- asusd config is repo-owned again (owner: "take over the asusd config"). Four managed records now
  patch `/etc/asusd/asusd.ron`, one anchored line each: `platform_profile_linked_epp: false`
  (asusd stops casting EPP), `ac_command: ""` + `bat_command: ""` (asusd stops casting the cpufreq
  governor), `platform_profile_on_battery: Balanced,` (the Q10 mapping). Applied with pre-images;
  `./eco report` PROFILE = OK; consumer readback EPP `dynamic(profile:performance)`, governor
  `powersave`.
- `check_profile` asserts all four records plus a sane profile value (balanced/performance/custom);
  `MANAGED_IDS`/`managed_label`/`CHECK_MANAGED` rewired; the fixture
  `tests/fixtures/etc/asusd/asusd.ron` restored to mirror converged intent; `findings.md` `## asusd`
  and the README PROFILE row updated.

### Findings recorded

- The flagged collision was structural: `platform_profile_linked_epp: true` made asusd cast
  `BalancePerformance` on the AC-on profile at every profile event (seen 2026-10-11 as the EPP
  drift), and `ac_command`/`bat_command` cast the governor via cpupower — racing TLP's
  "MUST stay powersave". With the boot-only backstop nothing re-converged until the next boot.
  Claiming the cast surface restores one writer per knob: the kernel's `dynamic` EPP does the
  profile-following now.

### Open

- The 4-surface scan synthesis is still to be presented; its asusd items are superseded by this
  takeover.

## 2026-10-13 — system scan under way; boot-apply drift found and fixed (check blind spot)

### What changed

- `eco-power.service` **enabled** (live): it sat `disabled`/`inactive` — the retired 600 s timer,
  not the unit's `[Install]`, used to start it, so the 2026-10-11 boot-only wave left nothing
  running at boot. Consumer readback after the fix: `scaling_max_freq` 4700000/3200000, cpuidle
  governor `teo`, EPP `dynamic(profile:performance)`.
- `check_timer` now asks systemd (`systemctl is-enabled`) instead of only grepping the unit file,
  and the assertion was mutation-proved (stub returning `disabled` → `DRIFT … is-enabled=disabled`);
  `tests/stubs/systemctl` gained the matching arm. Gate 92/92.

### Findings recorded

- **Verify from the consumer — again**: the check read `WantedBy=multi-user.target` in the unit
  file and reported OK while systemd's own state was `disabled`, so every boot-applied knob
  (ceilings, teo, EPP, wake-trim) silently drifted to hardware defaults after each reboot.
- Owner ruling during the scan: beesd's log level was 8 before the owner's own change to 5 — the
  "lower beesd verbosity" proposal is closed as already-done.

### Open

- Scan synthesis over 4 surfaces (boot/kernel, systemd/udev, storage/daemons, user-space) pending
  the user-space agent's report; all findings are proposals for owner ruling, nothing applied.

## 2026-10-11 — asusd config excluded from the backstop (owner-managed)

### What changed

- `state/managed/asusd.toml` + `tests/fixtures/etc/asusd/asusd.ron` deleted (owner: "leave the asusd
  config to me, exclude it from our backstop"); `CHECK_MANAGED[PROFILE]` and the `asusd` arm of
  `managed_label`/`MANAGED_IDS` removed. `check_profile` now emits **ACCEPTED** with the observed
  `platform_profile` value only — accepted-class semantics: never "fix" this row.
- `docs/eco-power-README.md` PROFILE row + `docs/findings.md` `## asusd` rewritten; a stale trigger
  comment in `hw-tune.fish` (record + fixture) now matches the boot-only reality.
- The line the repo previously claimed (`platform_profile_on_battery: Balanced,`) stays in the live
  `asusd.ron` untouched — the file is the owner's from here.

### Findings recorded

- With asusd out of the backstop and the backstop itself boot-only, the whole `platform_profile`
  domain — which resets SMU limits and EPP through the EC on every write — is owner-controlled.
  The 2026-10-11 `performance` profile's `balance_performance` EPP write is exactly that, and now
  stands until the owner or a boot changes it.

### Open

- Unchanged: scx rework later; freeze attribution window (now also boot-only + CO step 3); commit
  disposition ask-first — all waves uncommitted.

## 2026-10-11 — eco-power.service goes boot-only; undervolt loosened 2 units

### What changed

- **Boot-only service (owner ruling)**: deleted `state/owned/etc/systemd/system/eco-power.timer`
  and `state/owned/etc/udev/rules.d/99-eco-power.rules` (state + fixtures + the live copies, dated
  `.bak-YYYYMMDD` pre-images taken beside each live file first; `systemctl daemon-reload`,
  `udevadm control --reload`). `eco-power.service` now runs at boot only and still chains
  `eco-power.sh` + `eco apply`; the resume hook keeps re-asserting the SMU runtime knobs
  (`eco-power.sh resume` — it never started the service). `check_timer` was re-purposed under the
  frozen TIMER id to guard the boot-only contract (timer + udev trigger absent, service
  boot-enabled, eco apply chained). Contract docs updated: `docs/eco-power-README.md`
  (convergence promise + TIMER row), `docs/rollback.md`, `docs/findings.md` `## timer`, and the
  instruction file's convergence bullet.
- **Undervolt loosened 2 units (owner ruling)**: `coall -6 → -4`; per-core
  `-20 -20 -17 -17 -8 -10 -7 -5 → -18 -18 -15 -15 -6 -8 -5 -3` — `hw-tune.fish` record + fixture +
  `check_co` + `## co`. SMU write acks decode exactly (65532 = −4; 65518/1114094 = −18/−18;
  2162673/3211249 = −15/−15; then −6/−8/−5/−3).

### Findings recorded

- The boot-only trade surfaces immediately: after asusd applied its **performance** profile
  (platform_profile=performance — an owner toggle since yesterday's `custom`), all 24 policies read
  `balance_performance` EPP. asusd's static EPP write used to be re-asserted to `dynamic` by the
  udev/timer paths; now it persists until the next boot or a manual
  `sudo ./eco apply` / `eco-power.sh` run. This is the recorded cost of the ruling
  (`findings.md` `## timer`), not drift to fix silently.
- `./tests/run` 92/92 after the change. `./eco report`: TIMER OK (boot-only), CO OK (new vector),
  PROFILE OK, and the EPP row above as the only DRIFT.

### Open

- scx rework later (unchanged).
- Freeze investigation: the attribution window now also carries the boot-only change (far fewer
  SMU re-asserts/wakeups) and CO step 3.
- Commit disposition: ask-first — all waves sit uncommitted.

## 2026-10-10 — ceilings raised to 4.7/3.2, CO step two, scx dropped (convergence outage)

### What changed

- Per-class ceilings raised (owner ruling): Zen 5 4.6 → 4.7 GHz (4600000 → 4700000), Zen 5c 3.0 →
  3.2 GHz (3000000 → 3200000) — `state/owned/usr/local/sbin/eco-power.sh` + fixture mirror +
  `lib/readers.sh` `ceil_for_cpu`/`check_ceil` pins + `docs/findings.md` `## ceil` +
  `.github/copilot-instructions.md`. Applied live and verified: all 24 policies read back
  4700000 (Zen 5 = 0–3,12–15) / 3200000 (Zen 5c = 4–11,16–23), both under the hardware max
  readback (5157895 / 3289474).
- CO second loosening step (owner ruling): per-core `-21 -21 -18 -18 -8 -10 -7 -5` →
  `-20 -20 -17 -17 -8 -10 -7 -5` (cores 0–3 one step looser to carry the higher ceilings), coall
  stays −6 — `hw-tune.fish` record + fixture + `check_co` + `## co`. SMU write acks decode exactly
  (65516/1114092 = −20/−20; 2162671/3211247 = −17/−17; then −8/−10/−7/−5).
- **scx dropped entirely** (owner: "drop the scx part entirely, it needs updates later"):
  `state/managed/scx.toml` and `tests/fixtures/etc/scx_loader.toml` deleted; `CHECK_MANAGED[SCHED]`
  and the `scx` arm of `managed_label`/`MANAGED_IDS` removed; `check_sched` now emits `SKIPPED`
  (the 14-ID contract is untouched); `tests/run` cases 5/6/15/16b ported to the journald record and
  cases 9–11 (section scoping) retired with the record — `docs/findings.md` `## sched` holds the
  full account and the restore path.

### Findings recorded

- **Convergence outage (~10 h, 2026-10-10)**: the `scx-tools-git` 1:1.1.3 install at 07:17 removed
  `/etc/scx_loader.toml`; the managed record's missing target made every `./eco apply` hard-fail
  ("foreign file is never created") and write nothing. Live therefore kept the 2026-10-08
  `hw-tune.fish` while the repo record moved on 10-10 — which is exactly what looked like "the
  daemon restored my edits". Lesson (→ `docs/MEMORY.md`): the record is intent; live follows only
  when apply succeeds.
- Live sched_ext was an unmanaged out-of-tree scheduler (`enabled+all`; identity not recorded,
  owner policy 2026-10-14) — drifting from the repo-documented state; a freeze-hypothesis input
  (2026-10-08 H5).
- Observed after the wave: `./eco report` PROFILE reads `platform_profile=custom` (DRIFT). This
  wave only converged `asusd.ron`'s `platform_profile_on_battery: Balanced`, so the custom profile
  is most likely a manual toggle — owner to confirm before anything treats it as tuning.

### Open

- scx rework later (new scx-tools-git config layout): rebuild the record, restore the
  section-scoping test block from git history, re-run the scheduler A/B.
- Freeze investigation continues; arm (f) (ASPM `performance`) is still live from 2026-10-08 and
  the attribution window now also carries the 4.7/3.2 + CO-step-2 pair.
- Commit disposition: ask-first — all waves sit uncommitted.

## 2026-10-08 — CO loosened one step (freeze suspect); freeze investigation opened

### What changed

- Curve Optimizer loosened one step (owner ruling): `coall -7` → `-6`; per-core
  `-24 -24 -21 -21 -9 -11 -8 -6` → `-21 -21 -18 -18 -8 -10 -7 -5`. Single writer
  `state/owned/home/zhangdm/.reserve/hw-tune.fish` (fixture mirrored), policy pinned in
  `lib/readers.sh` `check_co`, ledger `docs/findings.md` `## co`. Converged via `./eco apply`, then
  applied to the SMU at once (write acks: coall 65530 = −6; per-core 65515/65515/65518/65518/
  65528/65526/65529/65531 = −21/−21/−18/−18/−8/−10/−7/−5).
- Experiment arm (f) applied (freeze investigation, owner suspect "ACPI powersave"):
  `PCIE_ASPM_ON_AC/BAT/SAV` `powersave` → `performance` (= ASPM off) in
  `state/owned/etc/tlp.d/01-eco.conf` + fixture mirror, converged, `systemctl restart tlp`;
  consumer readback `/sys/module/pcie_aspm/parameters/policy` = `[performance]`. Revert = git
  back to `powersave` + restart tlp. Kept only if freezes stop and the owner accepts the
  idle-watts cost.
- Owner rationale: CPU stalls at too-low voltage are a hard-freeze suspect and can explain the
  `ryzen_smu` "out of sync" symptoms; loosening is the stability direction.
- Third wave (evidence protection): beesd journal bleed stopped — owned drop-in
  `state/owned/etc/systemd/system/beesd@.service.d/10-log-rate-limit.conf`
  (`LogRateLimitIntervalSec=30s`, `LogRateLimitBurst=300`), converged via `./eco apply` +
  `systemctl restart beesd@…` (property verified live: `LogRateLimitBurst=300`). The limit is on
  the unit's log intake only; bees' work is untouched.
- `lib/writers.sh` `write_owned` now `mkdir -p`s the target's parent before `cp` — the drop-in path
  exposed the gap (nested state path with no live parent → `cp` failed and the wave aborted with
  `applied: none`). cp mode semantics unchanged (source mode wins on a new target).

### Findings recorded

- Machine truth: `ryzenadj --info` on Strix Point (0.19, SMU IF 21) exposes **no CO fields** —
  there is no consumer-side readback for CO, so the evidence is the SMU write ack only and the
  `## co` check line is aspirational (dated 2026-10-08).
- Attribution caveat: the freeze-attribution window now carries two changes — arm (d) sound power
  save 0 (01:46) and CO one step looser (~07:50). If freezes stop, the credit is shared; a clean
  one-variable attribution would need reverting one of them on purpose.

### Ranked freeze hypotheses (falsifiable)

1. **CO undervolt too deep → CPU stall** (owner's theory): explains `ryzen_smu` "out of sync" and
   silent wedges that survive kernel changes + reinstall. Prediction: with CO one step looser the
   stall/freeze class stops recurring; if it recurs, H1 loses weight. Mitigation applied today.
2. **ACPI/PCIe power save → D3 transition wedge** (owner's second suspect): ASPM `powersave`
   (L1 on 30/35 links) + runtime PM `auto` + wake disarms. Matches vector A
   (`Refused D0→D3hot`, `pci_pm_suspend` timeouts). Prediction: probe markers/freeze stop with
   `PCIE_ASPM=performance` (or runbook arm (c) TB/USB4 neutralize) while nothing else changes.
3. **Resume-window SMU contention** (ours + asusd + amdgpu at T0): the documented 21:14 timeline.
   Prediction: keeping hw-tune out of the resume window stops it — the runbook's own first
   mitigation.
4. **Audio codec reload** (vector B, `azx_get_response` after cs35l56 DSP reload): arm (d) applied
   01:46 today. Prediction: no recurrence while `power_save=0`.
5. **sched_ext scx_lavd** (out-of-tree BPF scheduler, `enabled+all`): the 09-20 hung_task happened
   with an out-of-tree scheduler live. Prediction: freeze stops under EEVDF.

Attribution caveat stands: H1 and H4 mitigations landed the same day, so a clean attribution needs
a deliberate revert of one of them if freezes stop.

### Open

- Freeze root cause still open. Evidence state: all pre-reinstall captures are gone with the
  2026-10-05 reinstall (`~/Workspace/suspend-forensics/`, pstore now empty) and the current boot
  has no hard freeze — only two 9 s f2fs checkpoint stalls on the external USB f2fs disk
  (03:21, 05:37, informational f2fs stack dumps) and five clean s2idle rehearsals through the
  new loop (`~/Workspace/freeze-probe/probe.sh`, pm_test stages freezer/devices/platform: green).
  journald has been losing kernel lines today (beesd progress spam, ~34 msg/s) — snapshot `dmesg`
  before any reboot, and never trust the journal alone for kernel markers.
- Probe gap closed: `pmtest` drives `/sys/power/state` directly and bypasses the systemd-sleep
  hooks; the new `hook` mode (logind `systemctl suspend` + RTC wake) exercises the documented
  resume window including the repo's hw-tune writes at T0 — verified by journal readback
  (`System returned from sleep` → `eco-power: hw-tune.fish applied` → `Successfully thawed`,
  thaw 183 ms). Three `hook` cycles green so far with the loosened CO (thaw assert ≤ 1.5 s).
- Probe status: `pmtest` 8 rehearsals clean (freezer/devices/platform), `hook` 3 cycles clean
  before the arm and **5/5 clean under arm (f)** (thaw 119–130 ms, no wedge markers). The freeze
  does not reproduce in short-cycle rehearsal — consistent with a rare, condition-dependent
  failure (documented fires came after long idle/AC-flap/lid sequences), so the arm now needs
  real-use observation (and 5 battery-side cycles) rather than more short loops.
- Commit disposition: ask-first; all waves today sit uncommitted.

## 2026-10-08 — risk pass: three tuning knobs narrowed to safer values

### What changed

- `kernel.sysrq` 1 → 190 (`state/owned/etc/sysctl.d/97-sysrq.conf`): keeps console-log, keyboard, the
  p/t/m/l dump group and the s/u/b rescue path; drops bit 64 (e/i/f mass process signalling) so one
  accidental chord cannot kill the session.
- hung-task panic bar 120 s (default) → 300 s (`state/owned/etc/sysctl.d/98-hung-task-panic.conf`,
  new `kernel.hung_task_timeout_secs=300`): `kernel.hung_task_panic=1` stays, so the pstore capture
  intent is unchanged — a slow-but-alive stall just cannot be panicked into a data-losing reset.
- `SOUND_POWER_SAVE_ON_AC/BAT` 1 → 0 (`state/owned/etc/tlp.d/01-eco.conf`, fixture mirrored at
  `tests/fixtures/etc/tlp.d/01-eco.conf`): runbook arm (d) applied prospectively — codec power-down
  cycles the cs35l56 DSP firmware reload that freeze vector B wedged in.
- `docs/findings.md` `## suspend-resume` updated to match (capture set, arm (d), machine truth).

### Findings recorded

- The 2026-09-20 hung_task pstore record fired at 122 s of D-state — on the 120 s default line. The
  panic knob was the riskiest armed parameter in the repo (any long D-state = whole-machine panic +
  dirty loss); the 300 s bar keeps the forensics and raises the certainty requirement.
- `kernel.sysrq` bitmask: the task-dump group is 0x08, which the popular "safe" value 438 omits —
  that is why this file historically pinned 1. 190 = 2|4|8|16|32|128 keeps dumps + rescue, drops
  signalling (64) and nice-RT (256).
- Correction (same day, independent diff review): the sound knob is **live**, not decorative —
  `/usr/sbin/tlp:47` calls `set_sound_power_mode` from `apply_common_settings`, and the module
  default is 10 s (`CONFIG_SND_HDA_POWER_SAVE_DEFAULT=10`), so the runtime `power_save=0` was a
  write, not a default. The original "TLP 1.10.2 never calls it" claim came from grepping the
  non-existent `/usr/share/tlp/tlp` with stderr silenced (pitfall → `docs/MEMORY.md`); the
  `## gpu-display` `power_save=1s` note is the old value's `(1, Y)` TLP outcome, not stale. Arm (d)
  therefore has real runtime effect. Open: an unidentified second boot-time writer of `power_save`
  (01:14:17.218, 0.7 s after TLP's write; observed `(0, Y)` matches no single TLP outcome) — it
  writes 0, the safe value, but breaks the one-writer rule (`docs/findings.md` `## suspend-resume`).

### Assessed and kept

- `USB_AUTOSUSPEND=1`: doctrine rule 3 lists autosuspend under "devices must sleep"; built-in input is
  i8042/PS2 (`## input-i2c`) so tty login is not in the blast radius, and the current device set
  suspends cleanly (`## gpu-display`: camera + 7/8 xHCI hubs, no `control=on` offenders). Future
  caveat: a USB HID or USB-serial recovery console would need a targeted exclusion (TLP
  `USB_ALLOWLIST`), the same pattern as the targeted BT rule.
- Curve Optimizer per-core offsets: CoreCycler-validated and frozen (`## co` — "never opportunistically").
- `vm.dirty_*` 6000/6000: exposure is bounded by btrfs's ~30 s transaction commits on the current
  root; the single-writer design is measured (`## writeback`).
- Flat 31 W envelope, `--power-saving`, scx_lavd `--powersave`: settled owner rulings (`## ppt`,
  `## eco`, `## sched`) — nothing here introduces a power cap.

### Live + gate evidence

- The 600 s converger tick at 01:46:43 applied the wave itself: `SUMMARY planned=5 applied=5 failed=0
  exit=0`; both sources agree afterwards (owned file + `sysctl -n`): `kernel.sysrq=190`,
  `kernel.hung_task_timeout_secs=300`, `kernel.hung_task_panic=1`, `SOUND_POWER_SAVE_ON_*=0`.
  Arm (d) verified at the consumer after `sudo systemctl restart tlp` + `sudo ./eco apply` (the
  comment correction): `snd_hda_intel` `power_save=0`, `power_save_controller=N` — TLP's `(0, N)`
  outcome, no codec suspend/wake reload cycle armed (before the restart: `(0, Y)`).
- `./tests/run`: 112 run / 112 passed, 0 failed (re-run after the review corrections).

### Open

- Commit disposition not taken (ask-first rule): the wave sits uncommitted for owner review.
- If a freeze recurs, the ladder continues at (b) quiet asusd / (c) TB-USB4 neutralize / (e) kernel A/B
  (`docs/findings.md` `## suspend-resume`); arm (d) is now permanently applied.

---

## 2026-10-05 — btrfs tunables research: io-stack drift found and converged

### What changed

- `docs/research/btrfs-tunables.md` (agent-written, 565 lines, primary-sourced): btrfs sysfs,
  block layer/IO scheduler, VM/sysctl interplay, module params, job caps — mount options
  excluded by scope. Owner rulings applied the same evening: the io-stack drift converged
  (live kyber+256 → ledger `none`+1023) and made durable as owned
  `state/owned/etc/udev/rules.d/61-eco-ioschedulers.rules` via `./eco apply` + udev trigger
  (verified `none`/1023/256/2000); the tunables-domain refusals (research §7) recorded in
  `docs/rollback.md` never-run rules; unowned vendor VM state (`dirty_bytes` 256 MiB,
  `dirty_background_bytes` 64 MiB, `vfs_cache_pressure` 50 — `/usr/lib/sysctl.d/70-cachyos-settings.conf`)
  recorded as foreign state in `docs/findings.md`, values unchanged.

### Findings recorded

- Drift mechanism: vendor `/usr/lib/udev/rules.d/60-ioschedulers.rules` pins NVMe to kyber;
  the pre-reinstall `/etc` override was a foreign file and died at the reinstall — the queue
  silently reverted to kyber/256. The research doc's baseline readback caught it.
- ionice verified inert under `none`/kyber (kernel doc + mq-deadline/kyber/NVMe source); the
  `btrfs-scrub(8)` `-c/-n` note has the scheduler claim inverted (recorded §2.1).
- Async-discard pacing knobs (`discard/{iops_limit,kbps_limit,max_discard_size}`) are the
  concrete arm design for the deferred `## fstrim` A/B — owner chose to keep it deferred.

### Next action

Watch bees' first heavy scan (no per-directory exclusion); the `## fstrim` async-discard A/B
stays deferred until the owner reopens it; `adios` elevator semantics remain unresearched.

## 2026-10-05 — btrfs rulings applied: bees replaces duperemove, scrub + balance policy recorded

### What changed

- Owner decoded `docs/research/btrfs-optimization.md` into rulings and they are applied:
  dedupe switched to **bees** (official `extra/bees` 0.11, upstream-default continuous
  `beesd@<FSUUID>.service` with shipped throttling; config `/etc/bees/beesd.conf`, now an owned
  state file), duperemove retired entirely (3 state files, live units + script + hashfile with
  dated pre-images, and the orphaned package), stock `btrfs-scrub@-.timer` enabled as the
  monthly online-verification duty (verified: instance `-` expands to mountpoint `/`).
- Policy written into `docs/rollback.md` (bees/scrub rows, trigger-only usage-filtered balance,
  the btrfs refusal list incl. `autodefrag` and NOCOW-anywhere, scrub-suspend semantics, new
  re-check block) and `docs/findings.md` (dedupe accounting adapted to bees; the
  `discard=async` drift recorded as deliberately deferred). Gate: 112/112.

### Decisions recorded

- Left alone on purpose: the `discard=async` vs `## fstrim` drift (deferred, may settle only by
  owner ruling or measured A/B) and `compress=zstd:1` (upstream default band). NOCOW is banned
  everywhere — COW stays for checksums + compression + reflink.

### Next action

bees watch-items (findings `## fstrim`): no per-directory exclusion exists, so the old
87k-member quadratic-group hazard is bounded only by bees' shipped throttling — watch the first
heavy scan; commit disposition for this wave is the only open ask.

## 2026-10-05 — post-reinstall reconvergence: XFS retired, stack restored, EPP kernel-locked

### What changed

- Root FS is now btrfs (was XFS; all hardware unchanged). XFS-era state retired per owner
  ("archive the XFS docs, retire it from our live docs"): deleted
  `state/owned/etc/sysctl.d/20-xfs-sync-interval.conf` and the `xfs-scrub.{service,timer}` units,
  moved `docs/XFS-TUNING.md` to `docs/archive/XFS-TUNING.md` behind a retirement banner, and
  scrubbed XFS framing from `docs/rollback.md` (storage ops, never-run rules now FS-agnostic),
  `docs/findings.md` and `docs/MEMORY.md`.
- Post-reinstall package restore (owner: install ALL missing, official+AUR): tlp 1.10.2,
  duperemove 0.15.2, asusctl 6.5.0, ryzenadj 0.19.0, ryzen_smu-dkms-git 191.d298366-1; PPD
  masked; `/var/lib/duperemove/root.hash` seeded; `scx_loader.toml` rebuilt from the test
  fixture with a provenance comment (scx_loader 1.1.3 reads `/etc/scx_loader/config.toml` >
  `/etc/scx_loader.toml` > `/usr/share/…`). `./eco apply` SUMMARY planned=24 applied=24
  failed=0, with dated pre-images.
- Exec-bit defect fixed in the repo (git had `eco-power.sh` and `hw-tune.fish` at 100644, so a
  fresh deploy ran a 203/EXEC service and hw-tune gated on `[ -x ]`): mode 755 on the state
  files and their fixture mirrors, plus explicit `chmod` on live (`cp` preserves the
  destination mode on existing targets).

### Findings recorded

- EPP `dynamic` is kernel-branch-locked, not a state defect: the running 7.2.9-1-cachyos
  rejects `echo dynamic` (EINVAL) while vmlinux string tables show the `dynamic(profile:…)`
  mode present in 7.3.0-rc5-1-cachyos-bore-lto and absent from 7.2.9 (the old readback
  `dynamic(profile:performance)` came from that mode). The knob cannot converge on the running
  kernel; bootloader choice stays in the recovery domain and is the owner's call.
- PPT readback now works end-to-end (ryzen_smu interface `/sys/kernel/ryzen_smu_drv`), so the
  report is ok=11 / accepted=1 (PPT — the STAPM firmware floor) / warn=1 (SD, expected) /
  drift=1 (EPP).
- btrfs tuning research landed at `docs/research/btrfs-optimization.md` (proposals only, no
  state changes); it flags owner decisions: live `discard=async` vs `findings##fstrim`,
  duperemove AC-gating, adopting `btrfs-scrub@.timer` over a repo unit, and NOCOW islands.

### Next action

Owner decisions (2026-10-05): EPP stays a known DRIFT on 7.2.9 (no boot change); wave committed
and pushed as `a291aa0`. Remaining open: the four btrfs-research questions (live `discard=async`
vs `findings##fstrim`, duperemove AC-gating, `btrfs-scrub@.timer` vs a repo unit, NOCOW islands).

## 2026-09-29 — eco tunings restored at resume (owner directive); experiment closed

### What changed

- `state/owned/usr/local/sbin/eco-power.sh`: the resume-path `hw-tune.fish` skip is removed —
  CO + 31 W envelope + SMU eco flags apply at resume again (owner: "fixed, now restore our
  former eco tunings" after clean cycles post stale-hook removal). The resume path stays
  single-pass (no `sleep 5` — that was the stall bug and its fix stands). Fixture re-synced;
  `./eco apply` planned=1 applied=1; live grep confirms the unconditional hw-tune invocation.

### Findings recorded

- The restore doubles as the A/B "on" arm: the 15:28/18:13 freezes predate the stale `.bak`
  hook (created 18:59), so the stale hook cannot explain those; hw-tune's SMU writes at resume
  remain an unexonerated suspect despite the owner's fixed call. Capture tooling (SysRq=1,
  hung_task_panic=1, efi_pstore, 256M journals) stays armed, and `docs/findings.md`
  `## suspend-resume` records the contingency ladder (re-skip hw-tune first, then asusd, then
  TB/USB4) with this restore date-stamped.

### Next action

Routine: if a freeze recurs, press Alt+SysRq+C and re-apply the hw-tune resume skip as the
first mitigation; the contingency experiments in the findings runbook only then.

## 2026-09-29 — the surviving ~5 s stall: stale .bak hook in the exec dir; writers.sh fixed

### What changed

- Root cause (owner report "stall still but no freeze", 5 cycles): the converger's pre-image
  `/usr/lib/systemd/system-sleep/eco-power.bak-20260929` sat INSIDE the hooks directory, and
  systemd-sleep executes every file there regardless of name — so the old full two-pass hook
  (`sleep 5` + hw-tune, no resume arg) ran on every resume alongside the new one (journal:
  PIDs 848541 skipped hw-tune at 22:10:57.844 while 848542 applied it at .882). It both kept
  the stall alive and contaminated experiment #1.
- Fix: backup moved to `/var/lib/eco-backups/system-sleep-eco-power.bak-20260929` (dated, kept);
  `lib/writers.sh` `backup_step` now routes pre-images of `system-sleep/` targets to a
  `system-sleep-backups/` sibling directory (nothing executes it). Rule home:
  `docs/rollback.md` `## Undo: universal mechanism` (exception added); pitfall in
  `docs/MEMORY.md`. Other `.bak` files (systemd units, tlp.d, NM conf.d) are inert — those
  loaders filter by extension; only system-sleep executes everything.

### How it was verified

Forced-drift probe: appended a marker to the live hook → `./eco apply` planned=1 applied=1,
hook restored, exec dir contains only `eco-power` + `tlp`, pre-image landed in
`system-sleep-backups/eco-power.bak-20260929`. `bash -n lib/writers.sh`; `./tests/run` 112/112.

### Findings recorded

- Experiment accounting correction: the 5 freeze-free cycles ran with hw-tune STILL writing the
  SMU at resume (via the stale hook) — encouraging but contaminated. The pure single-variable
  test of experiment #1 starts with the next cycle. The stall itself should now be gone too
  (the `sleep 5` second pass had no remaining runner).

### Next action

Owner: one cycle to confirm the stall is gone (expect `Successfully thawed` < 1 s after
`System returned from sleep`), then ~10 pure cycles (AC + battery) for the experiment #1 verdict.

## 2026-09-29 — recurrence 21:14: SMU no-response evidence; hw-tune off the resume path; SysRq armed

### What changed

- `state/owned/usr/local/sbin/eco-power.sh`: `apply_cpu_power` now takes the mode arg and
  **skips `hw-tune.fish` at resume** (logs `hw-tune.fish skipped at resume (SMU contention
  suspect)`); EPP re-assert stays; timer/udev/boot paths keep the full two-pass. Experiment #1
  per `docs/findings.md` `## suspend-resume` runbook, armed 2026-09-29 ~21:35 after the owner
  approved on the new evidence. Fixture mirror re-synced; `./eco apply` planned=1 applied=1.
- `state/owned/etc/sysctl.d/97-sysrq.conf` (new): `kernel.sysrq = 1` — the 21:14 freeze proved
  the kernel was alive (it logged `sysrq: This sysrq operation is disabled` at the user's
  keypresses); now Alt+SysRq+C crash-dumps into the armed efi_pstore and Alt+SysRq+T dumps tasks.
  Undo: delete the state file + `./eco apply` + `sysctl -w kernel.sysrq=16` (pre-image from
  `/usr/lib/sysctl.d/50-default.conf:19`).

### Findings recorded

- **21:14 freeze signature (richest yet):** resume → cs35l56 DSP reload → `ucsi_acpi
  GET_CURRENT_CAM failed` → `amdgpu SMU: No response msg_reg: 32 resp_reg: 0` → `Failed to
  power gate VPE!/JPEG!/VCN` (`DPM disable ... ret = -62`) → `AE_AML_LOOP_TIMEOUT` on
  `\_SB.A018/A032/ALIB/EC0._QDA` → freeze. Prime suspect chain: SMU mailbox contention —
  ryzenadj (our hw-tune) + amdgpu DPM + asusd's EC-mediated profile write all talk to the same
  APU SMU/EC firmware in the wake window.
- Pitfall: two concurrent `./tests/run` runs clobber each other's `tests/work/` (wiped every
  run) — a fleet agent's suite run produced 3 false reds in mine; the uncontended re-run was
  112/112. Never run the gate twice in parallel; re-run before believing reds after a dispatch.

### Next action

Owner runs ~10 suspend/lid cycles (AC + battery) on the armed experiment; report instant /
~5 s stall / hard freeze per cycle, and press Alt+SysRq+C on any hard freeze. Persistent freezes
→ next variable is quieting asusd's platform-profile writes.

## 2026-09-29 — retro landing: journal-merge guard + steering rules

### What changed

- `tests/run` case21 (5 assertions): `docs/NOTE.md` entry-merge guard — per dated `## 20..-..`
  entry, every `### ` section title appears at most once; every `### ` sits under a dated entry;
  every `## ` is dated. Catches the twice-burned swallowed-heading merge. Red-first proven on
  three simulated corruptions (deleted heading → dup-section FAIL; first-entry heading →
  orphan FAIL; undated heading → FAIL), journal restored byte-identical (`cmp`).
- `.github/copilot-instructions.md` (landed as `170c7ba`): journal insert discipline (anchor
  edits on the entry below, preserved headings out of the edit span) and the test-seam clause of
  one-place-per-knob (fixtures mirror converged live; expectations derive from records).
- Repaired the pre-existing merge the new guard caught: restored the swallowed heading
  `## 2026-09-29 — round 2: instructions revised, state/README.md File map completed` at
  `docs/NOTE.md:223` (provenance `git show HEAD~3:docs/NOTE.md`).

### How it was verified

`./tests/run` → 112 run / 112 passed / 0 failed (was 111/112 with the live merge, i.e. the guard
caught a real defect on its first run — the failure stayed red until the journal was repaired).

### Next action

Owner decides commit disposition for the two uncommitted files (`docs/NOTE.md` merge fix,
`tests/run` case21).



## 2026-09-29 — docs-unification implementation: 8 sub-waves landed; independent verification green

### What landed (module set, deletions, renames, adapter)

- Unified modules: `docs/findings.md` (30 knob entries), `docs/judgment.md` (may-I-change /
  may-I-claim), `docs/rollback.md` (operations runbook), `docs/eco-power-README.md` (tool
  contract), `docs/XFS-TUNING.md` (campaign module).
- Absorbed sources deleted: decisions.md, fleet-findings.md, hardware-quirks.md,
  unified-findings.md, doctrine.md, measurement.md, reboot-checklist.md, FS-MAINTENANCE.md,
  state/README.md. Listing apparatus gone (README directory index/start-here, Doc map, File map,
  index pointers, copilot-instructions doc listings); routing is the anchor scheme itself
  (eco-power-README `## Finding the writeup`: "Anchors are the doc map (there is no map table)").
- Anchor renames with test lockstep: quirks#* / decisions#* / fleet-findings#* → findings#*
  (state/managed/*.toml `doc =` repointed). Frozen and untouched: `rollback#sd` / `rollback#misc`.
- Adapter: `lib/report.sh` emit()/report_json default the doc handle to `CHECK_DOC[ID]` — every
  `./eco report` row self-locates (live: 14 rows, all carry findings#*/rollback#*).
- New doc-contract gates: case19 (every PREFIX#slug consumer anchor resolves to a real `##`
  heading) and case20 (SKIPPED-semantics one-home allowlist) → 20 cases / 107 assertions.

### Waves executed

gates ∥ privacy ∥ 3 authors (judgment / runbook / ledger) → sweep-core (SW1 adapter → SW2 anchor
renames → SW3 deletions → SW4 contract → SW5 doc trims → SW6 XFS absorption → SW7 one-home
greps) ∥ sweep-bench → verify.

### Pitfalls

- **Power-loss kill mid-wave**: battery death destroyed the first sweep-core agent mid-SW5; the
  repo survived consistently (suite green on resume); successor finished SW5-SW7 + the cross-lane
  pointers from a measured remainder list.
- **case20 phrase-pin race**: parallel lanes raced on the case17 SKIPPED-semantics phrase; a
  measure-and-pin guard re-baselined on transient copies. Resolved as a churn-proof allowlist
  contract — content rules (one fact, one home) are the authority, pins follow them. (This
  journal entry nearly re-tripped the guard by quoting the phrase: quote it by name, never by
  literal.)
- **Rewrap tokenizer bugs**: greedy `**…**` tokenizers fused spans during ≤100-col rewraps; awk
  width checks caught 171/1867-col offenders (fixed in follow-ups).

### Verification (impl-verify, fresh eyes, re-executed)

- `./tests/run`: 107 run, 107 passed, 0 failed (20 cases / 107 assertions).
- Dead-file grep (`--include='*.md'`): only dated journal hits. `bak-YYYYMMDD` literal only in
  rollback.md `## Undo: universal mechanism`; `apply --dry-run` only there + the contract Commands
  table; `EP `/`STB ` dead prefixes clean.
- Frozen contract: case17 strings present in eco-power-README + ./eco; 14 IDs EPP..MISC at
  `lib/registry.sh` CHECK_IDS (line 4) and `tests/run` (line 61); `rollback#sd`/`rollback#misc`
  4 emit sites byte-stable (git diff empty on those lines) and resolving (case19). `## sd`
  byte-identical to HEAD; `## misc` differs in exactly 2 mandated outbound-anchor repoints
  (decisions#config-fixes→findings#misc, decisions#bt→findings#bt), no undo text changed.
- Privacy: documented benchmarks/ scan → exactly 1 self-line; JSONL spot-check
  (ab2-allocsize-20260928.jsonl vs HEAD): 12 string-leaf path substitutions, 0 numeric diffs.
- Locality: BT verdict + live check from findings.md alone; undo-one-target from rollback.md
  alone; may-I-claim from judgment.md alone.
- Verifier fixes (missed non-md pointers only; tests untouched): `lib/writers.sh:291` and
  `state/owned`+fixture `eco-power.sh:74` comment `docs/fleet-findings.md#storage` →
  `docs/findings.md#writeback`; harvest message `docs/decisions.md` → `docs/findings.md`.

### Open cross-workstream item (not a unification defect)

A concurrent suspend/resume-forensics workstream mutated the same tree mid-verification
(SystemMaxUse 32M→256M in state/managed/journald.toml 19:02 + fixture/tests/run 19:09; new
findings.md `## suspend-resume` entry; new journal rows). A transient 99/107 red window at
~19:07 was its half-landed state (record moved before fixture/tests), not a regression.
Standing inconsistency as of this entry: `docs/findings.md` `## journald` still says
`SystemMaxUse=32M` while state says `256M` — that workstream must land the verdict update
(rationale is already in its `docs/MEMORY.md` row).

### Next action

Owner decides commit disposition.

## 2026-09-29 — suspend/resume freeze: owner decisions, hung_task auto-capture armed

### What changed

- `state/owned/etc/sysctl.d/98-hung-task-panic.conf` (new): `kernel.hung_task_panic = 1` — a
  task wedged >120 s now panics into the armed efi_pstore backend instead of ending in a
  power-button reset with no evidence. `./eco apply` → planned=2 applied=2; live readback
  `kernel.hung_task_panic = 1`; `./eco report` exit 0 (12 OK / 1 WARN SD / 1 SKIPPED).
- `docs/findings.md` `## suspend-resume`: owner defers the asusd/TB experiment matrix until a
  freeze recurs; the entry now carries the flip/revert runbook (one variable, ≥5 resume cycles
  AC + 5 battery: quiet asusd profile re-apply → TB/USB4 wakeup+runtime-PM neutralize →
  `SOUND_POWER_SAVE=0` → `linux-cachyos-lts` A/B as last escalation).
- Tests: `tests/fixtures/etc/systemd/journald.conf` moved with the 256M knob (fixture tree =
  converged live mirror) and `tests/run` case12 now derives its expected line from
  `state/managed/journald.toml` instead of hardcoding it (one place per knob). The earlier
  8-failure red run was this fixture/record skew — proof the suite catches knob drift.

### How it was verified

`./tests/run` → 107 run / 107 passed / 0 failed (after the fixture sync; red-first captured:
99/107 with all 8 failures tracing to the journald fixture skew).

### Next action

Owner commits the full tree (restructure + freeze work) on instruction; experiments stay parked
until the owner reports a recurrence.

## 2026-09-29 — suspend/resume freeze: journal + pstore forensics, stall fix landed, evidence ledger

### What changed

- `state/managed/journald.toml`: `SystemMaxUse=32M` → `256M` (boot -5's journal was already
  vacuumed mid-investigation — the 32 M cap destroyed freeze forensics). `./eco apply` applied it
  (only planned change; the 600 s converger had already auto-deployed the fix-resume-stall owned
  files).
- Forensics preserved to `~/Workspace/suspend-forensics/` (18 files + `pstore-existing/`): boot
  journals -4..0, dmesg, `/proc/acpi/wakeup`, TLP/asusd state, and 36 stale efi_pstore records
  from 2026-09-19/20 recovered before curation.
- pstore armed: `efi_pstore.pstore_disable=0` appended to limine cmdline (`/etc/default/limine`,
  `/boot/limine.conf`, backups `*.bak-20260929`); runtime probe registered the backend and
  exposed the old records. Reboot still pending to prove cmdline auto-enable.

### Findings recorded

- **Proven (ours): the ~5 s stall on every wake** — `eco-power.sh` ran `hw-tune.fish` twice with
  `sleep 5` between inside the systemd-sleep post hook; systemd thaws `user.slice` only after the
  hook exits. Fixed by `fix-resume-stall` (resume = single pass). Thaw-delta re-measurement is the
  acceptance test on the next resume.
- **Hard freeze, three evidence vectors:**
  1. boot -2 (09-29 15:28): resume → `ucsi_acpi GET_CURRENT_CAM failed` + asusd AC flap →
     asusd platform_profile write → 30 s silence → `AE_AML_LOOP_TIMEOUT` aborting
     `\_SB.A018/A032/ALIB/EC0._QDA` → `thunderbolt c6:00.5/6: Refused D0→D3hot` → hard cut.
  2. boot -1 (09-29 18:13): hard cut **during suspend entry** (no `PM: suspend entry`).
  3. pstore `crash-20260920-panic1.txt` (kernel 7.3.0-rc3, sched_ext "pandemonium" enabled+all):
     `hung_task: blocked tasks` — the blocked task `data-loop.0` sat 122 s in
     `snd_pcm_ioctl → playback_pcm_prepare → cs35l56_hda_play → azx_get_response` (HDA codec
     command never answered) right after a cs35l56 DSP firmware reload (i.e. after resume).
     boot -5's freeze also cut mid-cs35l56 firmware reload — corroborates the audio-amp vector.
- **New suspects from this evidence:** `SOUND_POWER_SAVE_ON_AC/BAT=1` in our own
  `state/owned/etc/tlp.d/01-eco.conf:56-57` (codec power-down ↔ cs35l56 re-init) and the
  sched_ext BPF scheduler (`enabled+all`, out-of-tree "pandemonium" was live on 09-20;
  `state/managed/scx.toml` only pins lavd `powersave_mode`). Neither is covered by the
  owner-approved experiment set yet.
- `kernel.hung_task_panic=0` today but the 09-20 record panicked on hung_task — the setting was
  different then; a hung-task panic would auto-capture pstore evidence instead of a silent freeze.

### How it was verified

- `./tests/run` re-run by hand after the fleet edit: 107 run / 107 passed / 0 failed.
- `diff /usr/local/sbin/eco-power.sh state/owned/...` byte-equal and live sleep hook carries the
  `resume` arg (converger deployed); `./eco apply` → planned=1 applied=1; live journald.conf now
  `SystemMaxUse=256M`.

### Next action

Owner-run experiment matrix (suspend/lid cycles) for `experiment-quiet-asusd` and
`experiment-tb-runtime-pm`, plus a decision on the two new suspects (audio power-save A/B,
hung_task_panic=1 for auto-capture). Then `freeze-verdict-findings` + `docs-memory-update`.

## 2026-09-29 — fix-resume-stall: resume path drops the 5 s delayed pass; sleep hook owned

### What changed

- `state/owned/usr/local/sbin/eco-power.sh:80-84`: trailing `sleep 5` + second `apply_cpu_power`
  now runs only when `$1 != resume`; header comment (:6-12) documents why. All log texts intact
  (tests/humans grep `hw-tune.fish applied (CO + 31W envelope + SMU eco flags)` etc.).
- New `state/owned/usr/lib/systemd/system-sleep/eco-power` (mode 755) — the previously untracked
  live hook brought under repo ownership; differs from live byte-wise in exactly one line
  (call site gains the `resume` arg). `tests/fixtures/usr/lib/systemd/system-sleep/eco-power`
  mirrors it; `tests/fixtures/usr/local/sbin/eco-power.sh` re-synced to the state copy (fixture
  tree = converged live).
- Contract: `eco-power.sh resume` runs the tuning pass exactly once (no `sleep 5`, no second
  CPU-power pass) so the systemd-sleep post-hook returns immediately and `user.slice` thaw is not
  blocked (was ~5.1 s per resume: journal "Successfully thawed unit 'user.slice'" 5.1 s after
  "System returned from sleep"). Timer/udev/boot invocations keep the two-pass re-assert.

### Verification

`bash -n` clean on all four touched scripts; `./tests/run` 107 run / 107 passed / 0 failed
(no test asserted on the script text, so zero test edits). RED-first note: the suite cannot
execute eco-power.sh (it writes live /sys), so the resume single-pass shape is verified by
diff/`bash -n` only — the thaw-delta measurement stays with the master after `eco apply`.

### Next action

Master: `./eco apply` (deploys hook + updated eco-power.sh to live), then verify journal thaw
delta on the next resume (expect < 1 s from "System returned from sleep" to "Successfully thawed
unit 'user.slice'"). No commit made (todo FORBADE commits).

## 2026-09-29 — architecture review: docs-unification design, five dossiers, grilling round

### What changed

- No doc/module restructure landed (design-only session). New file: `CONTEXT.md` — the domain
  vocabulary (five proposed modules, seams, adapters, deletion test) for the pending restructure.
- `/improve-codebase-architecture` executed: recon inventories (core + benchmarks), HTML review
  report with five candidate cards, then five parallel design dossiers (findings ledger,
  judgment gate, operations runbook, eco contract, XFS campaign module), each with a design tree,
  deletion tests, migration waves, and an owner frontier. Consolidated into one grilling round.

### Findings recorded

- Measured fragmentation: 28 md modules, 30+ duplication clusters; three conflicting cold-start
  orders (`README.md:15-19` vs `docs/eco-power-README.md:85-92` vs
  `.github/copilot-instructions.md:124-126`); broken pointer `docs/README-eco-power.md`
  (`docs/unified-findings.md:333`); `README.md:28` "5-min backstop" stale (live timer 600 s);
  dangling anchor `doc = "fleet-findings#io"` (`state/managed/journald.toml:4` — no `## io`
  heading exists); privacy rule `benchmarks/docs/MEMORY.md:6-8` violated by
  `benchmarks/studies/04-xfs-tuning/ab2-report-20260928.md:210,226` plus `cmd` fields in 7 JSONLs
  and `/home/...` literals in 4 campaign scripts.
- Pitfalls: tool results arrive in completion order, not call order — map background agents by
  their dossier's self-identified candidate, not by dispatch position; `current_intent` labels
  are unreliable (showed "XFS" while the agent produced the eco-contract dossier).
- Cross-dossier conflicts recorded for the owner: backup-rule and change-flow canonical homes
  (runbook vs contract); File map fate (keep in `state/` vs delete); anchor byte-stability
  policy; code-scope of the report↔docs seam.

### Next action

Owner answers the grilling round (11 consolidated decisions with recommendations).
Implementation waves start only after the owner confirms shared understanding.

## 2026-09-29 — round 2: instructions revised, state/README.md File map completed

### What changed

- `.github/copilot-instructions.md` revised per owner feedback ("2-4"): added the flat-TOML
  constraint on `state/managed` records, the hardcoded hybrid CPU mapping in `ceil_for_cpu`, the
  FS-maintenance/XFS owned units to the scope, the `docs/MEMORY.md` / `docs/NOTE.md` journal
  convention, the commit trailer, and the map-sync rule (`find state/owned` is authoritative).
- `state/README.md` File map completed: 8 rows added for files the FS-maintenance/XFS import
  landed without map entries (`etc/smartd.conf`, `etc/sysctl.d/20-xfs-sync-interval.conf`,
  `etc/systemd/system/{duperemove,xfs-scrub}.{service,timer}`,
  `usr/local/sbin/{duperemove-daily,smart-alert}.sh`). Map now covers all 25 state entries.
- `docs/MEMORY.md` drift note converted into a standing rule with its burn history.

### How it was verified

- Map completeness: every `find state/owned -type f` path greps exactly in `state/README.md`
  (25 rows = 20 owned + 4 managed + the README); all 8 new targets confirmed present on the live
  system first, so the map documents deployed reality, not intent alone.

### Next action

None. Both rounds committed on owner instruction.

## 2026-09-29 — copilot-instructions.md authored for the unified repo

### What changed

- `.github/copilot-instructions.md` created (no prior AI-instruction files existed anywhere in the
  tree — checked CLAUDE.md, AGENTS.md, .cursorrules, .windsurfrules, .clinerules, CONVENTIONS.md).
  Content: commands (`./tests/run`, the `eco` verb/flag/exit-code table, benchmark re-analysis via
  `perf-stats.py`), the propagation chain (state/ ownership models → `lib/` modules → `ECO_ROOT`
  test seam → registry/docs/tests lockstep → benchmarks rows-in-claims-out), and repo-specific
  conventions (repo-first + converger, one place per knob, idempotence, dated backups, anchored
  line-patch semantics, recovery domain, check-ID commit messages, doctrine/measurement gates,
  `benchmarks/` privacy rule, cold-start read order).
- `docs/MEMORY.md` and `docs/NOTE.md` created for the unified repo. The old journals from the
  benchmarks history live at `benchmarks/docs/` and stay there; `docs/MEMORY.md` points at them
  instead of copying (one fact, one home).

### How it was verified

- `./tests/run` → 87 assertions, 87 passed (also confirms the documented suite size and that
  `tests/work/` is regenerated).
- `./eco report` on the live host → exit 0, 14 rows (12 OK, 1 WARN SD, 1 SKIPPED PPT), matching the
  documented verdict vocabulary and check registry order.
- Every claim in the instructions file traced to a file in the tree (registry, state/README.md,
  eco-power-README.md, doctrine.md, measurement.md, benchmarks/tools/README.md,
  benchmarks/docs/MEMORY.md).

### Findings recorded

- `state/README.md` File map is stale (12 owned rows vs 20 files in `state/owned/`); details in
  `docs/MEMORY.md`. Not fixed in this session — this task was documentation-only.
- `tests/run` has no single-case selector; documented the grep-filter workaround rather than
  inventing a runner.

### Next action

None for this task. Open follow-ups for the owner: refresh the `state/README.md` File map; decide
whether the state map drift deserves its own doc-drift test (the suite already guards SKIPPED
semantics the same way).
