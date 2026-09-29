# NOTE — session journal

Running log of work on this repository. Durable knowledge is mined upward into `docs/MEMORY.md`;
this file keeps chronology and in-flight state. Newest entry first.

---

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
