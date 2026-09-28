#!/bin/bash
# Phase B single-window driver (resume after driver1 tree was killed mid-W5).
# usage: ab2-phaseB-driver2.sh WNUM
set -u
S=/home/zhangdm/.cache/bench-scratch
RES=$S/ab2-idle-20260928.jsonl
SAMP=$S/ab2-idle-sampler.py
W=$1

case "$W" in
  5)  L=ab2-idle-ctrl;        N=pair3-pos1; SYNCD=10000; PRE=300 ;;
  6)  L=ab2-idle-30000-1800;  N=pair3-pos2; SYNCD=30000; PRE=1800 ;;
  7)  L=ab2-idle-30000-1800;  N=pair4-pos1; SYNCD=30000; PRE=1800 ;;
  8)  L=ab2-idle-ctrl;        N=pair4-pos2; SYNCD=10000; PRE=300 ;;
  9)  L=ab2-idle-ctrl;        N=pair5-pos1; SYNCD=10000; PRE=300 ;;
  10) L=ab2-idle-30000-1800;  N=pair5-pos2; SYNCD=30000; PRE=1800 ;;
  11) L=ab2-idle-ctrl;        N=pair6-pos1; SYNCD=10000; PRE=300 ;;
  12) L=ab2-idle-30000-1800;  N=pair6-pos2; SYNCD=30000; PRE=1800 ;;
  13) L=ab2-idle-30000-1800;  N=pair7-pos1; SYNCD=30000; PRE=1800 ;;
  14) L=ab2-idle-ctrl;        N=pair7-pos2; SYNCD=10000; PRE=300 ;;
  *) echo "bad window $W"; exit 2 ;;
esac

echo "== window W$W $L ($N) arm=$SYNCD/$PRE start $(date '+%H:%M:%S')"
sudo sysctl -w fs.xfs.xfssyncd_centisecs="$SYNCD" fs.xfs.speculative_prealloc_lifetime="$PRE" >/dev/null
echo "  arm-set readback: xfssyncd=$(sysctl -n fs.xfs.xfssyncd_centisecs) prelife=$(sysctl -n fs.xfs.speculative_prealloc_lifetime)"
sudo python3 "$SAMP" --label "$L" --rep "$W" --note "$N" --seconds 750 \
  --expect-syncd "$SYNCD" --expect-prelife "$PRE" --results "$RES" \
  --samples "$S/idle-w$W-samples.jsonl" --xstats "$S/idle-w$W-xstats.jsonl"
RC=$?
echo "  window W$W end $(date '+%H:%M:%S') sampler_rc=$RC readback: xfssyncd=$(sysctl -n fs.xfs.xfssyncd_centisecs) prelife=$(sysctl -n fs.xfs.speculative_prealloc_lifetime)"
exit $RC
