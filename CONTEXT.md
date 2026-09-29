# CONTEXT — domain model of the documentation architecture

Written 2026-09-29 during the architecture review. This file names the concepts the docs
restructure talks about; it is the vocabulary shared by every design dossier and migration wave.
Status: **implemented 2026-09-29** — the modules below are the live doc set (gated by `./tests/run`
and the anchor/one-home guards).

## The domain

This repository governs one live host's power/tuning stack. The docs *are* the domain model:
each module answers reader questions, and the repo's own doctrine governs them — "one fact, one
home", and "docs teach HOW to check, never restate current state" (state is measured, not written).

## Proposed modules

1. **Findings ledger** (`docs/findings.md`) — one entry per knob. Interface fields: Verdict ·
   Why · Evidence (handles + how to check) · Rejected here · Reopen · Open · Machine lies.
   Implementation absorbs the former per-area decisions, fleet-research, quirks and unified-truth
   docs (deleted 2026-09-29). Knob vocabulary = the 14 check IDs plus named non-registry topics.
2. **Judgment gate** (`docs/judgment.md`) — may I change, may I claim. Implementation absorbs the
   former doctrine and measurement-protocol docs (deleted 2026-09-29). Two questions at the
   interface; the rest is depth.
3. **Operations runbook** (`docs/rollback.md`, retitled) — run, verify, undo. Interface = operator
   questions (ship a change · before reboot · verify after boot · verify after suspend · undo one
   target · escape · storage ops). `## sd` / `## misc` stay byte-verbatim.
4. **Eco contract** (`docs/eco-power-README.md`) — tool semantics: commands, exit codes, verdict
   classes, rules of the road, state layout, check registry, finding the writeup. Its test surface
   is real: case17 strings and the 14-ID vocabulary are asserted in `tests/run`.
5. **XFS campaign module** (`docs/XFS-TUNING.md`) — campaigns, recipes, results. Verdicts live in
   the ledger; the module stays the evidence/campaign home.

## Seams and adapters

- **Undo seam** — `docs/rollback.md` carries raw commands on purpose: recovery must never depend
  on this repo's tooling working ("the one accepted leak across the seam"). The anchor strings
  `rollback#sd` / `rollback#misc` are byte-stable contract.
- **Publication seam** — `benchmarks/` is a publishable unit; the privacy rule works in both
  directions (no home paths, host names, UUIDs, credentials in either direction's prose).
  `benchmarks/METHODOLOGY.md` is the deep implementation behind the judgment gate's rules: two
  adapters at one seam, joined by a seam-contract line.
- **Report ↔ docs seam** — every report row names its doc anchor (`CHECK_DOC`); the wired adapter
  makes the report the doc-finding interface.
- **Agent-instructions adapter** — `.github/copilot-instructions.md` holds runtime-only knowledge.
  On disagreement the repo doc wins; the instructions file is what gets fixed.

## Vocabulary (codebase-design)

module · interface · implementation · depth · deep · shallow · seam · adapter · leverage ·
locality. **Deletion test:** a module earns its keep only if deleting it makes its content
reappear at N callers; interface ≈ content means shallow — merge it. One adapter at a seam is
hypothetical; two adapters make the seam real.

## Load-bearing tested interfaces (never break silently)

- case17 (`tests/run:405–424`): the `SKIPPED` verdict class and its "counts green but means
  unverified" caveat have exactly two homes — `docs/eco-power-README.md` and the `./eco` usage
  text — and a uniqueness guard keeps it that way.
- 14 check IDs `EPP CEIL CO PPT ECO WIFI BT TLP TIMER IO SCHED PROFILE SD MISC`
  (`lib/registry.sh:3`, `tests/run:61`).
- Report row `findings#ppt` (`tests/run:63–64, 293–294`) — renames only in lockstep with tests.
