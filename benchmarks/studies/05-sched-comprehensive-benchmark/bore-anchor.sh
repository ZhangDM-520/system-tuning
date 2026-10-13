#!/bin/bash
# Window-drift anchor: bore control slots collected at the top-up hour (~04:30) to falsify
# time-of-night drift before merging mlfq top-up rows with the night's bore rows. If the
# anchor's bore medians fall inside the night bore's own spread, the window effect is
# bounded and the merged comparison stands; otherwise the study reports windows separately.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TOOLS=$ROOT/benchmarks/tools
DATA=$ROOT/benchmarks/data
LOG=$DATA/logs/bore-anchor-$(date +%Y%m%d-%H%M).log
OWNER="${BENCH_USER:-${SUDO_USER:-$(id -un)}}"


OWNER_HOME=$(getent passwd "$OWNER" | cut -d: -f6)
export BENCH_USER="$OWNER" BENCH_SCRATCH="${BENCH_SCRATCH:-$OWNER_HOME/.cache/bench-scratch}"

log() { echo "[$(date +%T)] $*" | tee -a "$LOG"; }

[ "$(id -u)" = 0 ] || { log "FATAL must run as root"; exit 2; }

# Wait for the mlfq top-up to finish (its "topup done" marker), or for its driver to die.
while ! grep -q 'topup done' "$DATA"/logs/mlfq-topup-*.log 2>/dev/null; do
  pgrep -f '/tmp/mlfq-topup[.]sh' >/dev/null 2>&1 || { log "WARN top-up driver gone without marker"; break; }
  sleep 30
done
for p in $(pgrep -x scx_pandemonium 2>/dev/null); do kill "$p" 2>/dev/null; done
for _ in 1 2 3 4 5; do pgrep -x scx_pandemonium >/dev/null 2>&1 || break; sleep 1; done
timeout 30 scxctl stop >/dev/null 2>&1
sleep 2
grep -qx disabled /sys/kernel/sched_ext/state \
  || { log "FATAL sched_ext not idle: $(cat /sys/kernel/sched_ext/state)"; exit 2; }
log "pre-clean done; bore anchor start (log=$LOG)"

rep=6
while [ "$rep" -le 9 ]; do
  log "anchor night-core rep=$rep"
  python3 "$TOOLS/scx_deep.py" slot --arm bore --rep "$rep" --mode phase \
    --pass night-core --dur 30 --cycles 1 --phases "idle,light,sat,storm,io,mem" >>"$LOG" 2>&1
  rep=$((rep + 1))
done
rep=6
while [ "$rep" -le 9 ]; do
  log "anchor night-real rep=$rep"
  python3 "$TOOLS/scx_deep.py" slot --arm bore --rep "$rep" --mode phase \
    --pass night-real --dur 30 --cycles 1 --phases "web,mixed,media,git" >>"$LOG" 2>&1
  rep=$((rep + 1))
done

scxctl stop >/dev/null 2>&1
sleep 2
nohup scx_pandemonium >/tmp/scx_pandemonium-anchor-restore.log 2>&1 &
for _ in 1 2 3 4 5 6 7 8; do
  sleep 1
  grep -q enabled /sys/kernel/sched_ext/state 2>/dev/null && break
done
log "restored: state=$(cat /sys/kernel/sched_ext/state) ops=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo -)"
log "anchor done"
