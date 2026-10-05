#!/bin/bash
# duperemove-daily.sh - incremental dedupe sweep of the root filesystem (reflink-capable:
# XFS reflink=1 until the 2026-10-05 reinstall, btrfs since).
# Installed 2026-09-26 at the owner's request (daily systemd timer).
#
# Design notes (see ~/docs/NOTE.md for the full write-up):
#  - The SQLite hashfile makes runs incremental: unchanged files are not re-hashed.
#  - Must run as root: unprivileged duperemove silently scans 0 files (libblkid UUID lookup).
#  - fs-latency trees are excluded: their 87k/24k-member identical-file groups trigger a
#    quadratic CPU stall in duperemove's group comparison (measured: 1 core pegged >55 min).
#  - Files with newlines in their names: none on this fs (verified 2026-09-26).
set -euo pipefail

STATE_DIR=/var/lib/duperemove
HASHFILE=$STATE_DIR/root.hash
LOG=$STATE_DIR/daily.log

# Rotate on disk before each run: the owner workflow reads/tails $LOG as a file, so logging
# stays file-based rather than journald-only; 7 generations = one week of daily runs.
for i in 6 5 4 3 2 1; do
  [[ -f "$LOG.$i" ]] && mv -f "$LOG.$i" "$LOG.$((i+1))"
done
[[ -f "$LOG" ]] && mv -f "$LOG" "$LOG.1"

EXCLUDES=(
  --exclude="/proc*"
  --exclude="/sys*"
  --exclude="/dev*"
  --exclude="/run*"
  --exclude="/tmp*"
  --exclude="/boot*"
  --exclude="/efi*"
  --exclude="/mnt*"
  --exclude="/media*"
  --exclude="/lost+found*"
  --exclude="/var/lib/duperemove*"
  --exclude="/home/zhangdm/Workspace/fs-latency*"
  --exclude="/root/Workspace/fs-latency*"
)

{
  echo "=== duperemove-daily start: $(date -Is) ==="
  df -B1 / | tail -1 | awk "{printf \"before: used=%s avail=%s\n\", \$3, \$4}"
  duperemove -drh --hashfile="$HASHFILE" "${EXCLUDES[@]}" /
  rc=$?
  echo "duperemove exit=$rc"
  df -B1 / | tail -1 | awk "{printf \"after:  used=%s avail=%s\n\", \$3, \$4}"
  echo "=== duperemove-daily end: $(date -Is) ==="
} > "$LOG" 2>&1
