#!/usr/bin/env python3
"""Phase B idle-window sampler: one window = sysctl arm + wbig burst + idle.

Samples every 5s: RAPL package energy_uj, backlight brightness+actual_brightness,
df free KB on target, fs.xfs.* readbacks (contamination detection), big.bin
allocated blocks (post-EOF prealloc / trim detection), PSI totals.
Every 60s: full /sys/fs/xfs/<dev>/stats/stats snapshot + nvme stat line.

At window end appends one fslat-shaped JSONL summary row to --results.
Run under sudo (RAPL + XFS stats are root-only).
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import subprocess
import time

XFS_STATS = "/sys/fs/xfs/nvme0n1p2/stats/stats"
NVME_STAT = "/sys/block/nvme0n1/stat"
RAPL = "/sys/class/powercap/intel-rapl:0/energy_uj"
RAPL_RANGE = "/sys/class/powercap/intel-rapl:0/max_energy_range_uj"
SYNCD = "/proc/sys/fs/xfs/xfssyncd_centisecs"
PRELIFE = "/proc/sys/fs/xfs/speculative_prealloc_lifetime"

NVME_FIELDS = [
    "read_ios", "read_merges", "read_sectors", "read_ticks",
    "write_ios", "write_merges", "write_sectors", "write_ticks",
    "in_flight", "io_ticks", "time_in_queue",
    "discard_ios", "discard_merges", "discard_sectors", "discard_ticks",
    "flush_ios", "flush_ticks",
]


def slurp(path: str) -> str:
    try:
        with open(path) as fh:
            return fh.read().strip()
    except OSError:
        return ""


def number(path: str) -> int:
    txt = slurp(path).split()
    return int(txt[0]) if txt and txt[0].lstrip("-").isdigit() else -1


def backlight() -> tuple[int, int]:
    for d in sorted(glob.glob("/sys/class/backlight/*")):
        return number(d + "/brightness"), number(d + "/actual_brightness")
    return -1, -1


def psi_totals() -> dict[str, int]:
    out: dict[str, int] = {}
    for dom in ("io", "cpu"):
        for line in slurp(f"/proc/pressure/{dom}").splitlines():
            parts = line.split()
            if not parts:
                continue
            tot = 0
            for kv in parts[1:]:
                if kv.startswith("total="):
                    tot = int(kv.split("=", 1)[1])
            out[f"{dom}_{parts[0]}"] = tot
    return out


def xfs_stats() -> dict[str, int]:
    d: dict[str, int] = {}
    for line in slurp(XFS_STATS).splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        for i, raw in enumerate(parts[1:]):
            if raw.lstrip("-").isdigit():
                d[f"{parts[0]}.{i}"] = int(raw)
    return d


def nvme_stat() -> dict[str, int]:
    vals = [int(x) for x in slurp(NVME_STAT).split()]
    return dict(zip(NVME_FIELDS, vals))


def df_free_kb(path: str) -> int:
    st = os.statvfs(path)
    return st.f_bavail * st.f_frsize // 1024


def wrap_delta(after: int, before: int, rng: int) -> int:
    if rng > 0 and after < before:
        return after + rng - before
    return after - before


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True)
    ap.add_argument("--note", default="")
    ap.add_argument("--rep", type=int, default=1)
    ap.add_argument("--seconds", type=int, default=750)
    ap.add_argument("--samples", required=True)
    ap.add_argument("--xstats", required=True)
    ap.add_argument("--results", required=True)
    ap.add_argument("--big", default=os.path.expanduser("~/.cache/bench-scratch/big.bin"))
    ap.add_argument("--target", default="/")
    ap.add_argument("--expect-syncd", type=int, required=True)
    ap.add_argument("--expect-prelife", type=int, required=True)
    ap.add_argument("--burst", default="/home/zhangdm/Projects/System-Tuning-Benchmarks/tools/wl.sh wbig")
    ap.add_argument("--trim-first-s", type=int, default=180,
                    help="seconds trimmed from the head of the window for screen-off-only J/min")
    args = ap.parse_args()

    rng = number(RAPL_RANGE)
    t0 = time.time()
    e0 = number(RAPL)
    psi0 = psi_totals()
    xs0 = xfs_stats()
    nv0 = nvme_stat()
    df_before = df_free_kb(args.target)

    samples: list[dict] = []
    xs_log: list[dict] = []
    contam: list[dict] = []

    def take_sample(i: int) -> dict:
        bl, bl_act = backlight()
        s = {
            "i": i,
            "t": time.time(),
            "e_uj": number(RAPL),
            "bl": bl,
            "bl_act": bl_act,
            "df_free_kb": df_free_kb(args.target),
            "syncd": number(SYNCD),
            "prelife": number(PRELIFE),
            "big_blocks": os.stat(args.big).st_blocks if os.path.exists(args.big) else -1,
        }
        s.update(psi_totals())
        if s["syncd"] != args.expect_syncd or s["prelife"] != args.expect_prelife:
            contam.append({"t": s["t"], "syncd": s["syncd"], "prelife": s["prelife"]})
        return s

    # cold-cache discipline identical per arm: drop caches before each window's burst
    subprocess.run(["sh", "-c", "sync; echo 3 > /proc/sys/vm/drop_caches"],
                   check=True, capture_output=True)
    samples.append(take_sample(0))

    # standardized write burst at window start
    burst_cmd = args.burst.split()
    b0 = time.time()
    bp = subprocess.run(burst_cmd, capture_output=True, text=True)
    b1 = time.time()
    burst_s = round(b1 - b0, 3)
    if bp.returncode != 0:
        print(f"!! burst exited {bp.returncode}: {bp.stderr[-500:]}", flush=True)

    i = 1
    while True:
        now = time.time()
        if now - t0 >= args.seconds:
            break
        time.sleep(max(0.0, min(5.0, t0 + args.seconds - now)))
        if time.time() - t0 >= args.seconds:
            break
        samples.append(take_sample(i))
        if i % 12 == 0:
            xs_log.append({"t": time.time(), "xfs": xfs_stats(), "nvme": nvme_stat()})
        i += 1

    e1 = number(RAPL)
    psi1 = psi_totals()
    xs1 = xfs_stats()
    nv1 = nvme_stat()
    wall = round(time.time() - t0, 3)

    with open(args.samples, "w") as fh:
        for s in samples:
            fh.write(json.dumps(s) + "\n")
    with open(args.xstats, "w") as fh:
        for s in xs_log:
            fh.write(json.dumps(s) + "\n")

    j_full = wrap_delta(e1, e0, rng) / 1e6
    j_per_min_full = j_full / wall * 60 if wall else 0.0

    # screen-off-only: trim head, then take the largest contiguous run with bl==0
    seg = [s for s in samples if s["t"] - t0 >= args.trim_first_s and s["bl"] == 0 and s["bl_act"] == 0]
    best: list[dict] = []
    cur: list[dict] = []
    for s in seg:
        if cur and s["t"] - cur[-1]["t"] > 10.0:
            if len(cur) > len(best):
                best = cur
            cur = []
        cur.append(s)
    if len(cur) > len(best):
        best = cur
    if len(best) >= 2:
        seg_s = best[-1]["t"] - best[0]["t"]
        seg_j = wrap_delta(best[-1]["e_uj"], best[0]["e_uj"], rng) / 1e6
        j_per_min_off = seg_j / seg_s * 60 if seg_s > 0 else 0.0
    else:
        seg_s, seg_j, j_per_min_off = 0.0, 0.0, 0.0

    on_samples = sum(1 for s in samples if s["bl"] > 0 or s["bl_act"] > 0)
    screen_on_frac = on_samples / len(samples) if samples else 0.0

    # post-burst trim events: big.bin allocated-blocks drops >= 1MB (2048 x 512B)
    trims = []
    post = [s for s in samples if s["t"] >= b1]
    for a, b in zip(post, post[1:]):
        if a["big_blocks"] >= 0 and b["big_blocks"] >= 0 and a["big_blocks"] - b["big_blocks"] >= 2048:
            trims.append({"t": b["t"], "drop_blocks": a["big_blocks"] - b["big_blocks"]})
    first_trim_s = round(trims[0]["t"] - b1, 1) if trims else -1
    big_end = post[-1]["big_blocks"] if post else -1
    big_burst_end = post[0]["big_blocks"] if post else -1

    xs_delta = {k: xs1.get(k, 0) - xs0.get(k, 0) for k in set(xs0) | set(xs1)
                if xs1.get(k, 0) - xs0.get(k, 0)}
    nv_delta = {f: nv1.get(f, 0) - nv0.get(f, 0) for f in NVME_FIELDS}
    ops = nv_delta["read_ios"] + nv_delta["write_ios"]
    nv_delta["mean_queue_us"] = round(nv_delta["time_in_queue"] * 1000 / ops, 1) if ops else 0

    psi_delta = {k: psi1.get(k, 0) - psi0.get(k, 0) for k in ("io_some", "io_full", "cpu_some")}

    row = {
        "label": args.label, "rep": args.rep, "note": args.note,
        "cmd": args.burst + " + idle",
        "cfg": {
            "fs.xfs.xfssyncd_centisecs": str(number(SYNCD)),
            "fs.xfs.speculative_prealloc_lifetime": str(number(PRELIFE)),
            "mount_options": next((l.split()[3] for l in slurp("/proc/mounts").splitlines()
                                   if len(l.split()) >= 4 and l.split()[1] == "/"), ""),
        },
        "probe": {},
        "wall_s": wall,
        "rapl_J": round(j_full, 3),
        "avg_W": round(j_full / wall, 3) if wall else 0,
        "psi_us": psi_delta,
        "nvme": nv_delta,
        "xfs": xs_delta,
        "j_per_min_full": round(j_per_min_full, 4),
        "j_per_min_screen_off": round(j_per_min_off, 4),
        "screen_off_seg_s": round(seg_s, 1),
        "screen_on_frac": round(screen_on_frac, 4),
        "trim_events": len(trims),
        "first_trim_s": first_trim_s,
        "big_blocks_burst_end": big_burst_end,
        "big_blocks_end": big_end,
        "df_before_kb": df_before,
        "df_after_burst_kb": post[0]["df_free_kb"] if post else -1,
        "df_min_kb": min(s["df_free_kb"] for s in samples),
        "df_end_kb": samples[-1]["df_free_kb"] if samples else -1,
        "burst_s": burst_s,
        "burst_rc": bp.returncode,
        "contaminated": 1 if contam else 0,
        "contam_detail": contam[:20],
        "n_samples": len(samples),
    }
    with open(args.results, "a") as fh:
        fh.write(json.dumps(row) + "\n")

    print(f"=== {args.label} rep{args.rep} window wall={wall}s burst={burst_s}s "
          f"J={j_full:.1f} J/min_full={j_per_min_full:.2f} J/min_off={j_per_min_off:.2f} "
          f"screen_on_frac={screen_on_frac:.3f} trims={len(trims)} first_trim_s={first_trim_s} "
          f"contaminated={row['contaminated']}", flush=True)
    if contam:
        print(f"    CONTAMINATION: {json.dumps(contam[:10])}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
