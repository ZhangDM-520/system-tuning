#!/bin/bash
# mlfq top-up: scx_mlfq 1.3.11 crashes at attach ~2/3 of attempts (non-existent DSQ 0x100c,
# kernel runtime error), so the overnight run only landed n=2 usable per pass. Retry slots
# until each pass reaches 5 usable reps, same phases/dur/cycles as night-run.sh, then restore
# the owner's direct-attach end state (via $BENCH_RESTORE_CMD; identity not recorded here).
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TOOLS=$ROOT/benchmarks/tools
DATA=$ROOT/benchmarks/data
LOG=$DATA/logs/mlfq-topup-$(date +%Y%m%d-%H%M).log
OWNER="${BENCH_USER:-${SUDO_USER:-$(id -un)}}"


OWNER_HOME=$(getent passwd "$OWNER" | cut -d: -f6)
export BENCH_USER="$OWNER" BENCH_SCRATCH="${BENCH_SCRATCH:-$OWNER_HOME/.cache/bench-scratch}"

log() { echo "[$(date +%T)] $*" | tee -a "$LOG"; }

[ "$(id -u)" = 0 ] || { log "FATAL must run as root (CAP_BPF, RAPL, sched sysfs)"; exit 2; }

# pre-clean: kill direct-attach FIRST and prove it died. `scxctl stop` hangs while a
# direct-attach scheduler holds sched_ext -- the loader cannot stop what it does not own.
RESTORE_CMD="${BENCH_RESTORE_CMD:?set BENCH_RESTORE_CMD to the owner direct-attach scheduler command}"
RESTORE_BIN=${RESTORE_CMD%% *}
for p in $(pgrep -x "$RESTORE_BIN" 2>/dev/null); do kill "$p" 2>/dev/null; done
for _ in 1 2 3 4 5; do
  pgrep -x "$RESTORE_BIN" >/dev/null 2>&1 || break
  sleep 1
done
pgrep -x "$RESTORE_BIN" >/dev/null 2>&1 \
  && { log "FATAL direct-attach end-state scheduler survived kill"; exit 2; }
timeout 30 scxctl stop >/dev/null 2>&1

usable() {
  python3 - "$DATA/scx-deep.jsonl" "$1" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
rs = {r['rep'] for r in rows
      if r.get('pass') == sys.argv[2] and r.get('arm') == 'mlfq' and r.get('valid')}
print(len(rs) - (1 if 0 in rs else 0))
PY
}

sleep 2
grep -qx disabled /sys/kernel/sched_ext/state \
  || { log "FATAL sched_ext not idle: $(cat /sys/kernel/sched_ext/state)"; exit 2; }
log "pre-clean done; top-up start (log=$LOG)"

for spec in "night-core:idle,light,sat,storm,io,mem" "night-real:web,mixed,media,git"; do
  pass=${spec%%:*}
  phases=${spec#*:}
  rep=6
  while [ "$(usable "$pass")" -lt 5 ] && [ "$rep" -le 30 ]; do
    log "attempt $pass rep=$rep usable=$(usable "$pass")"
    python3 "$TOOLS/scx_deep.py" slot --arm mlfq --rep "$rep" --mode phase \
      --pass "$pass" --dur 30 --cycles 1 --phases "$phases" >>"$LOG" 2>&1
    rep=$((rep + 1))
  done
  log "$pass finished usable=$(usable "$pass") rep_next=$rep"
done

# restore the owner's end state (direct-attach needs root: CAP_BPF / RLIMIT_MEMLOCK)
scxctl stop >/dev/null 2>&1
sleep 2
nohup $RESTORE_CMD >>/tmp/scx-restore-topup.log 2>&1 &
sleep 5
log "restored: state=$(cat /sys/kernel/sched_ext/state) ops=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo -)"
log "topup done"
