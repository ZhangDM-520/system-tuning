#!/usr/bin/env python3
"""scoreboard.py -- Gate 1 + Gate 2 verdicts per (phase, metric, arm) vs control, night rows only.

Gate 1: arm median outside control's own [min,max] spread.  Gate 2: MW-U tie-corrected two-sided
p<0.05.  Direction from scx_deep_analyse.LOWER_BETTER.  Stdlib + perf-stats.py only.
"""
import json, os, statistics, sys, collections

TOOLS = "benchmarks/tools"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
os.chdir(ROOT)
sys.path.insert(0, TOOLS)
import importlib.util
spec = importlib.util.spec_from_file_location("perfstats", os.path.join(TOOLS, "perf-stats.py"))
ps = importlib.util.module_from_spec(spec); spec.loader.exec_module(ps)
spec2 = importlib.util.spec_from_file_location("deep_an", os.path.join(TOOLS, "scx_deep_analyse.py"))
an = importlib.util.module_from_spec(spec2); spec2.loader.exec_module(an)

KEEP_REPS = {int(x) for x in (sys.argv[1] if len(sys.argv) > 1 else "1,2,3,4,5").split(",")}
CTL = os.environ.get("G1_CONTROL", "bore")

rows = []
for line in open("benchmarks/data/scx-deep.jsonl"):
    try:
        r = json.loads(line)
    except json.JSONDecodeError:
        continue
    if not r.get("valid", True) or r.get("rep") not in KEEP_REPS:
        continue
    if r.get("pass") not in ("night-core", "night-real"):
        continue
    bl0 = r.get("sched", {}).get("bl_before")
    if bl0 != r.get("sched", {}).get("bl_after"):
        continue
    rows.append(r)

by = collections.defaultdict(lambda: collections.defaultdict(list))
for r in rows:
    by[r["phase"]][an.armkey(r)].append(r)

better = collections.defaultdict(list)
worse = collections.defaultdict(list)
detail = []
for ph in sorted(by):
    for m in an.DEFAULT_METRICS:
        ctl = [v for v in (ps.get(r, m) for r in by[ph].get(CTL, [])) if v is not None]
        if len(ctl) < 3:
            continue
        lo, hi = min(ctl), max(ctl)
        for a in sorted(by[ph]):
            if a == CTL:
                continue
            vals = [v for v in (ps.get(r, m) for r in by[ph][a]) if v is not None]
            if len(vals) < 3:
                continue
            med = statistics.median(vals)
            res = ps.mannwhitney(ctl, vals)
            p = res[2] if res else float("nan")
            lower = m in an.LOWER_BETTER
            improved = (med < statistics.median(ctl)) if lower else (med > statistics.median(ctl))
            outside = med < lo or med > hi
            gate = outside and p < 0.05
            verdict = "-"
            if gate:
                verdict = "BETTER" if improved else "WORSE"
            (better if verdict == "BETTER" else worse if verdict == "WORSE" else {None: []})[a] \
                .append(f"{ph}:{m.split('.',1)[1]}") if verdict != "-" else None
            detail.append((ph, m, a, len(vals), med, statistics.median(ctl), lo, hi, p, verdict))

print("== per-arm scoreboard (night rows, reps 1-5) ==")
arms = sorted({d[2] for d in detail})
for a in arms:
    b = [d for d in detail if d[2] == a and d[9] == "BETTER"]
    w = [d for d in detail if d[2] == a and d[9] == "WORSE"]
    print(f"\n{a}: {len(b)} better / {len(w)} worse")
    for d in b:
        print(f"   + {d[0]}/{d[1].split('.',1)[1]}: med {d[4]:.4g} vs ctl {d[5]:.4g} spread[{d[6]:.4g},{d[7]:.4g}] p={d[8]:.3f}")
    for d in w:
        print(f"   - {d[0]}/{d[1].split('.',1)[1]}: med {d[4]:.4g} vs ctl {d[5]:.4g} spread[{d[6]:.4g},{d[7]:.4g}] p={d[8]:.3f}")
