#!/bin/bash
# AB3 loopback within-pass A/B for XFS allocsize=1m (mount-time arms).
# Image lives on root fs (which itself has allocsize=1m) -> double-caching caveat.
# Arms: A=allocsize=1m at mount, B=plain mount (dynamic default).
set -euo pipefail
SCRATCH="${BENCH_SCRATCH:-$HOME/.cache/bench-scratch}"
WS=$SCRATCH/ab3-loop
IMG=$WS/img
MNT=$WS/mnt
RES=$SCRATCH/ab3-loop-20260928.jsonl
T="$(cd "$(dirname "$0")/../.." && pwd)"
FSLAT=$T/tools/fslat.py
WL=$T/tools/wl.sh
S='sudo -n'

rm -rf "$WS"; mkdir -p "$MNT"; rm -f "$RES"
truncate -s 4G "$IMG"
mkfs.xfs -f -q -m crc=1,finobt=1,rmapbt=1,reflink=1,bigtime=1,inobtcount=1 \
  -i sparse=1,nrext64=1,exchange=1 -n ftype=1,parent=1 -d agcount=4 "$IMG"

arm() { # arm <label> <mount-opts> <expect: 1m|def>
  local label=$1 opts=$2 expect=$3 got exts
  $S umount "$MNT" 2>/dev/null || true
  $S mount -o loop,$opts "$IMG" "$MNT"
  $S chown "$(id -u):$(id -g)" "$MNT"
  got=$($S findmnt -no OPTIONS --target "$MNT")
  echo "== $label mount options: $got"
  case "$expect" in
    1m) [[ "$got" == *allocsize=1024k* ]] || { echo "ABORT: allocsize missing on $label"; exit 1; } ;;
    def) [[ "$got" != *allocsize=* ]] || { echo "ABORT: unexpected allocsize on $label: $got"; exit 1; } ;;
  esac
  FSLAT_RESULTS=$RES python3 "$FSLAT" run --label "$label" --note "loopback:$got" --drop -- \
    /bin/bash -c "dd if=/dev/zero of='$MNT/big.bin' bs=1M count=2048 status=none; sync" 2>&1 | tail -8
  exts=$($S filefrag "$MNT/big.bin" | tail -1)
  echo "   filefrag: $exts"
}

# warmups (excluded)
arm loop-1m-wbig-warmup  allocsize=1m 1m
arm loop-def-wbig-warmup defaults     def

# counted, interleaved pairs with rotating start
arm loop-1m-wbig  allocsize=1m 1m
arm loop-def-wbig defaults     def
arm loop-def-wbig defaults     def
arm loop-1m-wbig  allocsize=1m 1m
arm loop-1m-wbig  allocsize=1m 1m
arm loop-def-wbig defaults     def
arm loop-def-wbig defaults     def
arm loop-1m-wbig  allocsize=1m 1m

$S umount "$MNT" 2>/dev/null || true
echo DONE
