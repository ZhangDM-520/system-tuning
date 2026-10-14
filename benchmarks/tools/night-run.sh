#!/usr/bin/env bash
# night-run.sh — unattended overnight sched_ext benchmark (05-sched-comprehensive-benchmark).
#
# Design constraints (each from the campaign rules):
#   * arms interleave and rotate inside every rep (scx_deep.py), rep 0 is the warm-up that
#     analysis discards -> REPS=6 yields n=5 usable per arm per phase class;
#   * the display must stay in ONE regime for every slot: the panel is blanked before slot 1 and
#     rows carry bl=0 (a display-blank regime shift moves both anchors by ~13 W);
#   * sleep/idle are inhibited for the whole run (the machine is left alone overnight);
#   * no scheduler may hold sched_ext outside the loader before arm 1 (a direct-attached
#     scheduler makes every scxctl start fail and silently poisons the run);
#   * end state is restored exactly: the owner's direct-attach scheduler, resolved at
#     runtime and deliberately never recorded in this repo (owner policy 2026-10-14).
#
# Owner identity and home are derived at runtime — this file must stay free of personal identity.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOLS="$ROOT/benchmarks/tools"
DATA="$ROOT/benchmarks/data"
LOGDIR="$DATA/logs"
mkdir -p "$LOGDIR"
STAMP=$(date +%Y%m%d-%H%M)
LOG="$LOGDIR/night-$STAMP.log"

OWNER="${BENCH_USER:-${SUDO_USER:-$(id -un)}}"
OWNER_HOME=$(getent passwd "$OWNER" | cut -d: -f6)
export BENCH_USER="$OWNER"
export BENCH_SCRATCH="${BENCH_SCRATCH:-$OWNER_HOME/.cache/bench-scratch}"

ARMS="${ARMS:-bore,beerland,bpfland@-p -k -P,cake,cosmos@-g -P -a,flash@-T,flow,lavd@--per-cpu-dsq --enable-cpu-bw,mlfq,pandemonium,p2dq@-a -y --dhq-enabled true --wakeup-llc-migrations --fork-balance true --enable-pelt true --latency-priority --wakeup-preemption --enable-eas true,tickless}"
REPS="${REPS:-6}"
DUR="${DUR:-30}"
PREFIX="${PASS_PREFIX:-night}"

log() { echo "[$(date +%T)] $*" | tee -a "$LOG"; }

# ---- owner end-state resolution ----------------------------------------------
# $BENCH_RESTORE_CMD if set, else the uncommented scx_* spawn-at-startup entry in the
# owner's niri autostart config. The identity stays out of git by policy.
RESTORE_CMD="${BENCH_RESTORE_CMD:-}"
if [ -z "$RESTORE_CMD" ]; then
  _line=$(grep -v '^[[:space:]]*//' "$OWNER_HOME/.config/niri/cfg/autostart.kdl" 2>/dev/null \
    | grep -m1 'spawn-at-startup.*scx_' || true)
  [ -n "$_line" ] && RESTORE_CMD=$(printf '%s\n' "$_line" | grep -o '"[^"]*"' | tr -d '"' \
    | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  RESTORE_CMD=${RESTORE_CMD#sudo }
fi
RESTORE_BIN=${RESTORE_CMD%% *}
[ -n "$RESTORE_BIN" ] || { log "FATAL cannot resolve the owner's end-state scheduler; set BENCH_RESTORE_CMD"; exit 2; }

# ---- preflight ----------------------------------------------------------------
for b in scxctl hackbench schbench stress-ng ffmpeg zen git python3; do
  command -v "$b" >/dev/null || { log "FATAL missing tool: $b"; exit 2; }
done
[ "$(systemctl is-enabled scx_loader 2>/dev/null)" = masked ] \
  && { log "FATAL scx_loader is masked — arms switch via scxctl over D-Bus; unmask before benchmarking"; exit 2; }
[ -r /sys/class/powercap/intel-rapl:0/energy_uj ] || { log "FATAL RAPL unreadable"; exit 2; }
[ "$(cat /sys/class/power_supply/AC0/online 2>/dev/null)" = 1 ] || log "WARN not on AC — energy numbers carry battery-state confounds"

# ---- pre-clean: nothing may hold sched_ext outside the loader -------------------
for p in $(pgrep -x "$RESTORE_BIN" 2>/dev/null); do kill "$p" 2>/dev/null; done
scxctl stop >/dev/null 2>&1
sleep 2
grep -qx disabled /sys/kernel/sched_ext/state \
  || { log "FATAL sched_ext not idle: $(cat /sys/kernel/sched_ext/state)"; exit 2; }

# ---- one display regime for every slot ----------------------------------------
blank_panel() {
  local uid sock disp
  uid=$(id -u "$OWNER")
  sock=$(ls "/run/user/$uid"/niri.*.sock 2>/dev/null | head -1)
  disp=$(basename "${sock:-niri.}")
  disp=${disp#niri.}
  disp=${disp%%.*}
  [ -n "$disp" ] || return 1
  sudo -u "$OWNER" env "XDG_RUNTIME_DIR=/run/user/$uid" "WAYLAND_DISPLAY=$disp" \
    niri msg action power-off-monitors >/dev/null 2>&1
}
blank_panel || log "WARN could not blank panel — study must filter to the dominant bl regime"

log "start: $(awk -F, '{print NF}' <<<"$ARMS") arms x $REPS reps, dur=$DUR, $PREFIX-core then $PREFIX-real, scratch=$BENCH_SCRATCH owner=$OWNER"
systemd-inhibit --what=sleep:idle --who=night-bench --mode=block \
  --why="overnight sched_ext benchmark" \
  python3 "$TOOLS/scx_deep.py" run --arms "$ARMS" --reps "$REPS" --dur "$DUR" --cycles 1 \
    --pass ${PREFIX}-core --phases "idle,light,sat,storm,io,mem" >>"$LOG" 2>&1
rc_core=$?
log "night-core finished rc=$rc_core"

systemd-inhibit --what=sleep:idle --who=night-bench --mode=block \
  --why="overnight sched_ext benchmark" \
  python3 "$TOOLS/scx_deep.py" run --arms "$ARMS" --reps "$REPS" --dur "$DUR" --cycles 1 \
    --pass ${PREFIX}-real --phases "web,mixed,media,git" >>"$LOG" 2>&1
rc_real=$?
log "night-real finished rc=$rc_real"

# ---- restore the owner's end state --------------------------------------------
# Direct-attach needs root (CAP_BPF / RLIMIT_MEMLOCK): a start that dies before load
# produces no kernel event at all, so the exit code of a brief probe is the only proof.
# Keep the evidence in the log instead of /dev/null and re-attach on failure.
scxctl stop >/dev/null 2>&1
RESTORE_LOG="$LOGDIR/night-$STAMP-restore.log"
restore_end_state() {
  # intentional word-splitting: RESTORE_CMD is a full command line
  nohup $RESTORE_CMD >"$RESTORE_LOG" 2>&1 &
  for _ in 1 2 3 4 5 6; do
    sleep 1
    grep -q enabled /sys/kernel/sched_ext/state 2>/dev/null && return 0
  done
  return 1
}
restore_end_state || { sleep 2; restore_end_state; } \
  || log "FATAL restore failed — see $RESTORE_LOG; start the owner's end-state scheduler manually"
log "restored: state=$(cat /sys/kernel/sched_ext/state) ops=$([ -s /sys/kernel/sched_ext/root/ops ] && echo set || echo none)"

# ---- achieved n per arm/pass, honestly ----------------------------------------
python3 - "$DATA/scx-deep.jsonl" "$PREFIX" >>"$LOG" 2>&1 <<'PY'
import json, sys, collections
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
prefix = sys.argv[2]
for p in (prefix + "-core", prefix + "-real"):
    reps = collections.defaultdict(set)
    for r in rows:
        if r.get("pass") == p and r.get("valid"):
            reps[r.get("arm")].add(r.get("rep"))
    print(f"{p} achieved valid reps:",
          {a: f"{len(rs) - (1 if 0 in rs else 0)} usable / {len(rs)} slots"
           for a, rs in sorted(reps.items())})
PY

log "night-run done rc_core=$rc_core rc_real=$rc_real"
touch "$LOG.done"
