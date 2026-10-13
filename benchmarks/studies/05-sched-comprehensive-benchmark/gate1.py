#!/usr/bin/env python3
"""gate1.py -- Gate 1 check per docs/judgment.md: an effect only counts if the arm's median
falls OUTSIDE the control's own [min, max] spread for the same phase/metric. Stdlib only.
Usage: gate1.py PASS PHASE METRIC [ARM ...]  (default: all non-control arms)
"""
import json, os, statistics, sys

ROOT = os.environ.get("BENCH_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESULTS = os.environ.get("SCX_DEEP_RESULTS") or os.path.join(ROOT, "data", "scx-deep.jsonl")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import importlib.util
spec = importlib.util.spec_from_file_location(
    "perfstats", os.path.join(ROOT, "tools", "perf-stats.py"))
perfstats = importlib.util.module_from_spec(spec)
spec.loader.exec_module(perfstats)


def armkey(r):
    return r["arm"] + (f"[{r['args']}]" if r.get("args") else "")


def main():
    pass_name, phase, metric = sys.argv[1:4]
    want = set(sys.argv[4:]) or None
    ctl_name = os.environ.get("G1_CONTROL", "bore")
    exclude = {int(x) for x in os.environ.get("G1_EXCLUDE_REPS", "0").split(",") if x.strip().isdigit()}
    by = {}
    for line in open(RESULTS):
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            continue
        if r.get("pass") != pass_name or r.get("phase") != phase or not r.get("valid", True):
            continue
        if r.get("rep") in exclude:
            continue
        bl0 = r.get("sched", {}).get("bl_before")
        if bl0 != r.get("sched", {}).get("bl_after"):
            continue
        by.setdefault(armkey(r), []).append(r)
    ctl = [v for v in (perfstats.get(r, metric) for r in by.get(ctl_name, [])) if v is not None]
    if len(ctl) < 3:
        print(f"control n={len(ctl)} too small"); return 1
    lo, hi = min(ctl), max(ctl)
    print(f"{pass_name}/{phase} {metric}  control={ctl_name} n={len(ctl)} "
          f"median={statistics.median(ctl):.4g} spread=[{lo:.4g}, {hi:.4g}]")
    for a in sorted(by):
        if a == ctl_name or (want and a not in want):
            continue
        vals = [v for v in (perfstats.get(r, metric) for r in by[a]) if v is not None]
        if len(vals) < 3:
            print(f"  {a:<28} n={len(vals)} too small"); continue
        med = statistics.median(vals)
        outside = med < lo or med > hi
        res = perfstats.mannwhitney(ctl, vals)
        p = res[2] if res else float("nan")
        print(f"  {a:<28} n={len(vals)} median={med:.4g} "
              f"gate1={'PASS' if outside else 'fail'} "
              f"{'BELOW' if med < lo else ('ABOVE' if med > hi else 'inside')} "
              f"MW-U p={p:.3f}{'*' if p < 0.05 else ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
