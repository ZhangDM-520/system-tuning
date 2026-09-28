#!/bin/bash
# Phase B driver: 1 warmup window (discarded) + 10 measured windows, interleaved+rotated.
# Window = set arm sysctls -> readback -> sampler (drop_caches + wbig burst + 750s idle).
set -u
S=/home/zhangdm/.cache/bench-scratch
RES=$S/ab2-idle-20260928.jsonl
SAMP=$S/ab2-idle-sampler.py

set_arm() {
  sudo sysctl -w fs.xfs.xfssyncd_centisecs="$1" fs.xfs.speculative_prealloc_lifetime="$2" >/dev/null
  echo "  arm-set readback: xfssyncd=$(sysctl -n fs.xfs.xfssyncd_centisecs) prelife=$(sysctl -n fs.xfs.speculative_prealloc_lifetime)"
}

run_win() { # run_win wnum label note syncd prelife
  echo "== window W$1 $2 ($3) arm=$4/$5 start $(date '+%H:%M:%S')"
  set_arm "$4" "$5"
  sudo python3 "$SAMP" --label "$2" --rep "$1" --note "$3" --seconds 750 \
    --expect-syncd "$4" --expect-prelife "$5" --results "$RES" \
    --samples "$S/idle-w$1-samples.jsonl" --xstats "$S/idle-w$1-xstats.jsonl"
  echo "  window W$1 end $(date '+%H:%M:%S') readback: xfssyncd=$(sysctl -n fs.xfs.xfssyncd_centisecs) prelife=$(sysctl -n fs.xfs.speculative_prealloc_lifetime)"
}

run_win 0 ab2-idle-ctrl-warmup warmup-discarded 10000 300
run_win 1 ab2-idle-ctrl        pair1-pos1 10000 300
run_win 2 ab2-idle-30000-1800  pair1-pos2 30000 1800
run_win 3 ab2-idle-30000-1800  pair2-pos1 30000 1800
run_win 4 ab2-idle-ctrl        pair2-pos2 10000 300
run_win 5 ab2-idle-ctrl        pair3-pos1 10000 300
run_win 6 ab2-idle-30000-1800  pair3-pos2 30000 1800
run_win 7 ab2-idle-30000-1800  pair4-pos1 30000 1800
run_win 8 ab2-idle-ctrl        pair4-pos2 10000 300
run_win 9 ab2-idle-ctrl        pair5-pos1 10000 300
run_win 10 ab2-idle-30000-1800 pair5-pos2 30000 1800
echo "== Phase B driver complete $(date '+%H:%M:%S')"
