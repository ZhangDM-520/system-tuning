# 04 — XFS tuning A/B campaigns (2026-09-28)

Root-level report, data, and helper scripts from the XFS mount-option / idle-policy A/B
campaigns on the root NVMe XFS filesystem (kernel 7.3-rc4-cachyos-lto). Bulk measurement
data and scratch trees (`~/.cache/bench-scratch/{tree,tree.tar,allocloop,ab3-loop,...}`,
~15 GB) intentionally stay out of git.

## Campaigns

- **AB1 — filestreams (`chattr +S` / `filestreams`): REJECT.** A Pareto trade, not a win:
  some metrics improved, others regressed past gate thresholds. Verdict: do not adopt.
- **AB2 — `allocsize=1m` + XFS timer policy: NOTHING ADOPTED.** Phase A (allocsize,
  n=5/arm) failed every gate AND the treatment rows carry no `allocsize=1m` readback —
  arm-identity failure, so the null result is not a valid refutation either. Phase B
  (`xfssyncd_centisecs`/`speculative_prealloc_lifetime`, write-burst + idle windows) was
  screen-confounded and stopped at n=2/arm; the hard n≥5 ceiling makes it INCONCLUSIVE-lean.
- **AB3 — `allocsize=1m` via boot cmdline: NO DIFFERENCE → rolled back.** Same candidate
  re-tested with a reliable application path; deltas inside control spread; rolled back.

## Files

| File | What it is |
|---|---|
| `ab2-report-20260928.md` | Full AB2 analysis report (verdicts, arm readbacks, evidence handles) |
| `ab-xfs-20260928.jsonl` | AB1 filestreams benchmark rows |
| `ab2-allocsize-20260928.jsonl` | AB2 Phase A rows: allocsize=1m vs dynamic default, `wbig` workload |
| `ab2-idle-20260928.jsonl` | AB2 Phase B rows: XFS idle/timer-policy arms |
| `ab3-allocsize-20260928.jsonl` | AB3 rows: allocsize via boot cmdline |
| `ab3-combined-20260928.jsonl` | AB3 combined/merged dataset |
| `ab3-loop-20260928.jsonl` | AB3 loopback-device allocsize probe rows |
| `diag-*.jsonl`, `idle-w*-samples/xstats.jsonl` | Diagnostic runs and per-window idle sampler/xstats series (w0–w5) |
| `ab2-idle-sampler.py` | Idle-period sampler used in AB2 Phase B |
| `ab2-phaseB-driver*.sh`, `ab3-loop-driver.sh` | Campaign driver scripts (write-burst + idle phases, loopback probe) |

## Pitfalls (apply to any future campaign here)

1. **Remount-inert on 7.3-rc4:** `filestreams` and possibly `allocsize` accept a remount
   (rc=0) but never appear in `/proc/mounts` and have no effect. Verify at the consumer.
2. **Arm-identity readback rule:** a treatment arm is only valid if the setting is read
   back from where the consumer reads it (e.g. `fslat.py capture_settings()` →
   `/proc/mounts`). AB2 Phase A violated this — hence "not a result", not "a null result".
3. **`wbig` produces no speculative prealloc:** the large-block workload never triggers
   XFS speculative preallocation, so prealloc-lifetime knobs cannot show an effect on it.
4. **Cross-pass caveat:** AB2 Phase B's two windows are screen-confounded; n=2/arm cannot
   reach p<0.05 on Mann-Whitney, and passes are not directly comparable across campaigns.

Full write-ups (baseline, ranked candidates, recipes, per-campaign detail):
`docs/XFS-TUNING.md` in the repo root; host ops context in `docs/FS-MAINTENANCE.md`.
