# NOTE — session journal

Running log of work on this repository. Durable, reusable knowledge is mined out of here into
`docs/MEMORY.md`; this file keeps the chronology and the state of in-flight work.

**Convention:** newest entry first. One `## YYYY-MM-DD — topic` section per change or incident, each
saying what changed, why, and how it was verified. This is a public repository: no home paths, no
machine name, no credentials, no private host logs.

---

## 2026-09-29 — hub listing apparatus folded into deep homes (dossiers C4–C6)

### What changed

`README.md`'s 8-lesson prose and reproduce command sheet, and `data/README.md` §6's regeneration
block, were shallow listings of content that already lives in the study READMEs, `TEST-BED.md` and
`METHODOLOGY.md`. The lessons are now an 8-row lesson → deep-home anchor table — the hub still
answers "what transfers to my hardware?" — the command sheet is a pointer to each study's reproduce
section plus `tools/README.md`, and §6 is a data-index (output → analyser → input rows) with one
example line. Three lesson aphorisms that existed only in the hub moved to their deep homes: study 01
§5 ("best scheduler and best-configured scheduler are different questions"), study 01 §9 ("it adapts"
vs "adapting helps"), METHODOLOGY §8.1 ("measure and record the ambient state, or measure nothing").
Study 02 §11 gained the `cmp mem-swap-150 mem-swap-200` comparison line the hub sheet had carried as
a concrete reproduction command (`tools/README.md` keeps only the syntax example).

Defect C6 is fixed: the hub study index, the repo map and `docs/MEMORY.md`'s "Where things live" now
register `studies/04-xfs-tuning/` like the other studies ("The four studies"; the 326/315 row counts
are explicitly scoped to studies 01–03 so they do not silently absorb study 04's arm-identity-failed
rows). `studies/04-xfs-tuning/README.md` is untouched: its verdict lines and its campaign-module
pointer are the seam contract (accepted Q3).

### Pitfalls worth recording

- A stale inbound anchor surfaced during the fold: `TEST-BED.md` §6 pointed at
  `README.md#what-generalises-off-this-machine`, a heading the hub no longer carries. Rewired to the
  current section anchor. A heading rename needs an anchor sweep in the same wave.
- Markdown anchors convert *each* whitespace character to a hyphen and merely drop punctuation, so an
  em dash between spaces becomes a double hyphen (`#11-the-hybrid-split--and-the-trap-in-it`,
  `#81-display-blanking--13-w`). An anchor checker that collapses whitespace runs reports false
  failures — match the renderer's slug, not intuition.

### Verification

- `grep -rn 'perf-stats.py cmp passA:cake' --include='*.md' .` → exactly one hit (study 01 §12);
  every hub command-sheet copy is gone.
- A slug check over every `path#anchor` link in `benchmarks/**/*.md` → 0 unresolved.
- The identifier scan from `docs/MEMORY.md` run over this tree → exactly one match, the scan
  command's own line in `docs/MEMORY.md`.
- `./tests/run` at the repository root → 107 run, 107 passed.

## 2026-09-19 — docs/ journals created, and the kernel drift recorded

### What changed

`docs/MEMORY.md` and `docs/NOTE.md` were added. The repository had no project memory: the standing
decisions behind it (re-derive every published number; strip personal identity but keep hardware
identity; `data/` as the artefact of record; the source lab left untouched) existed only in the
session that produced the publication, and a reader or a later maintainer had no way to recover them
without re-deriving the whole editorial line.

### The one fact worth recording on the way in

The publication describes a **`PREEMPT_RT` + BORE** test bed — `TEST-BED.md` and study 01 both name
`7.2.5-1-cachyos-rt-bore-lto` — and that remains the correct description *of the campaign*. The
machine has since been moved to a different kernel flavour. Nothing in the published data is
affected and no figure was edited, because the studies are explicitly scoped to the kernel they were
measured on: study 01 declines to claim transfer "to a kernel without `PREEMPT_RT`", and study 02
relies on `CONFIG_TRANSPARENT_HUGEPAGE` being absent. The consequence is for anyone re-running the
harness today — a re-run is a new baseline, not a reproduction. That is now written into
`docs/MEMORY.md` under "facts that are easy to get wrong" rather than left for someone to trip over.

### Verification

- Every path, tool name and claim in `docs/MEMORY.md` was checked against the tree (`TEST-BED.md`,
  `studies/01-scheduler-selection/README.md`, `tools/`, `data/`) rather than written from memory.
- The privacy scan in `docs/MEMORY.md` was run over the repository and returns nothing.
- `docs/` is not matched by `.gitignore`, so both files are tracked.
