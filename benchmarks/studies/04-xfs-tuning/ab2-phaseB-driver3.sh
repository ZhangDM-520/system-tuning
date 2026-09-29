#!/bin/bash
# Phase B gated single-window driver.
# Pre-window quiet gate: backlight must be idle-dimmed (120000) and RAPL power low,
# else wait. Then run one window exactly like driver2. Usage: driver3.sh WNUM
set -u
S="${BENCH_SCRATCH:-$HOME/.cache/bench-scratch}"
RES=$S/ab2-idle-20260928.jsonl
SAMP="$(dirname "$0")/ab2-idle-sampler.py"
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

# ---- quiet gate: wait until display idle-dimmed & package power low ----
gate() {
  local deadline=$(( $(date +%s) + 1800 ))  # max 30 min wait
  while [ "$(date +%s)" -lt "$deadline" ]; do
    local out
    out=$(python3 - <<'PY'
import glob, time
def num(p):
    try:
        t = open(p).read().split()
        return int(t[0]) if t and t[0].lstrip("-").isdigit() else -1
    except OSError:
        return -1
bls = []
for d in sorted(glob.glob("/sys/class/backlight/*")):
    bls.append((num(d+"/brightness"), num(d+"/actual_brightness")))
rapl = "/sys/class/powercap/intel-rapl:0/energy_uj"
e0 = num(rapl); t0 = time.time(); time.sleep(30); e1 = num(rapl)
w = (e1 - e0) / 1e6 / (time.time() - t0) if e1 >= e0 else 99
bl_ok = all(b == 120000 and a >= 0 for b, a in bls) and bls
print(f"{'PASS' if bl_ok and w < 4.5 else 'WAIT'} bl={bls} W={w:.2f}")
PY
)
    echo "  [gate] $out"
    case "$out" in
      PASS*) return 0 ;;
    esac
    sleep 60
  done
  return 1
}

echo "== gate before W$W ($L $N) start $(date '+%H:%M:%S')"
if ! gate; then
  echo "  GATE TIMEOUT — machine not idle; window NOT started"
  exit 3
fi

echo "== window W$W $L ($N) arm=$SYNCD/$PRE start $(date '+%H:%M:%S')"
sudo sysctl -w fs.xfs.xfssyncd_centisecs="$SYNCD" fs.xfs.speculative_prealloc_lifetime="$PRE" >/dev/null
echo "  arm-set readback: xfssyncd=$(sysctl -n fs.xfs.xfssyncd_centisecs) prelife=$(sysctl -n fs.xfs.speculative_prealloc_lifetime)"
sudo python3 "$SAMP" --label "$L" --rep "$W" --note "$N" --seconds 750 \
  --expect-syncd "$SYNCD" --expect-prelife "$PRE" --results "$RES" \
  --samples "$S/idle-w$W-samples.jsonl" --xstats "$S/idle-w$W-xstats.jsonl"
RC=$?
echo "  window W$W end $(date '+%H:%M:%S') sampler_rc=$RC readback: xfssyncd=$(sysctl -n fs.xfs.xfssyncd_centisecs) prelife=$(sysctl -n fs.xfs.speculative_prealloc_lifetime)"
exit $RC
