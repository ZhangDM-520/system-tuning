# NOTE — session journal

Running log of work on this repository. Durable knowledge is mined upward into `docs/MEMORY.md`;
this file keeps chronology and in-flight state. Newest entry first.

---

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
