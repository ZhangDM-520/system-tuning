#!/usr/bin/env bash
# Convergence + eco settings (doctrine v2: work-per-joule, race-to-sleep).
# Triggers: boot (eco-power.service), resume (system-sleep hook), and the ceil watch
# (eco-ceil.timer every 2 min + 82-eco-ceil.rules on power-source events → `eco-power.sh
# ceil`): the watch pass is drift-only and touches only scaling_max_freq — no ryzenadj/SMU
# writes, no EPP writes. Owner 2026-10-11: the 600 s backstop timer and the power-source udev
# trigger for the FULL pass are dropped (SMU paths are boot/resume-only — their register churn
# is the wedge race). Owner 2026-10-29: the 4.7/3.2 ceiling gets its own watch after being
# observed overwritten to the hardware max between passes (docs/findings.md ## timer).
#
# Ordering note: any platform_profile write (asusd does one per power-source event)
# makes the EC reset SMU limits and EPP — so the CPU-power block runs twice, with a
# short delay, to land AFTER such handlers and converge. The resume path (first
# arg "resume", from the system-sleep hook) runs the block once and returns at
# once: systemd thaws user.slice only after the hook exits, so the delayed pass
# would stall every resume (measured 5.1 s). A power-source event around resume
# still gets the full two-pass via the udev-triggered service.
log() { echo "eco-power: $*" >&2; }

apply_cpu_power () {
  # All ryzenadj hardware tuning lives in ~/.reserve/hw-tune.fish (single writer:
  # CO undervolt, iGPU CO, flat 31 W envelope, --power-saving, PSI thresholds).
  # We only invoke it here so state converges after asusd's event-driven re-asserts.
  if [ -x /home/zhangdm/.reserve/hw-tune.fish ]; then
    fish /home/zhangdm/.reserve/hw-tune.fish quick >/dev/null 2>&1 \
      && log "hw-tune.fish applied (CO + 31W envelope + SMU eco flags)" \
      || log "hw-tune.fish failed (ryzen_smu out of sync with kernel?)"
  else
    log "hw-tune.fish missing — firmware power limits stand"
  fi
  # EPP is owned by power-profiles-daemon since 2026-10-30 (owner ruling): the drift-only
  # `dynamic` re-assert that lived here is retired — nothing in the repo writes EPP now.
  # History: that loop was the boot-wedge mitigation (the default->dynamic transition runs
  # platform_profile_register under policy->rwsem; docs/research/2026-10-17-epp-deadlock-
  # kernel-attribution.md). PPD writes plain EPP values, which do not take that path.
}

apply_ceil () {
  # Per-core-class ceilings (owner 2026-10-10): Zen5 = 4.7 GHz, Zen5c = 3.2 GHz (docs/findings.md
  # ## ceil). Single writer of scaling_max_freq. Drift-only, with the caught value logged:
  # the cap was observed overwritten to the hardware max (5.1/3.3) by an unidentified actor
  # (owner 2026-10-29) — "CEIL DRIFT policyN <old> -> <new>" lines give the journal the
  # timestamps that identify the overwriter (findings.md ## timer).
  local pol want cur
  for pol in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -w "$pol/scaling_max_freq" ] || continue
    if [ "$(cat "$pol/cpuinfo_max_freq" 2>/dev/null)" -gt 4400000 ]; then
      want=4700000
    else
      want=3200000
    fi
    cur=$(cat "$pol/scaling_max_freq" 2>/dev/null)
    if [ "$cur" != "$want" ]; then
      echo "$want" > "$pol/scaling_max_freq" 2>/dev/null \
        && log "CEIL DRIFT $(basename "$pol") $cur -> $want"
    fi
  done
}

# Mode dispatch: `ceil` is the watch pass (eco-ceil.service from timer/udev) — ceiling-only,
# drift-only, no SMU writes and no sleep, safe to run every couple of minutes.
if [ "$1" = ceil ]; then
  apply_ceil
  exit 0
fi

apply_cpu_power

# cpuidle governor teo: better idle-state prediction, deeper sleep more often
[ -w /sys/devices/system/cpu/cpuidle/current_governor ] \
  && echo teo > /sys/devices/system/cpu/cpuidle/current_governor 2>/dev/null \
  && log "cpuidle governor=teo"

apply_ceil

# Trim wake sources: internal keyboard (i8042 AT) + lid stay wake-capable (lid is EC-
# handled, i8042 is not in the ACPI table); disarm USB/USB4/WLAN-root wakes. GPP0/GPP1 are the
# USB4 bridges (added 2026-10-13, owner-approved wake trim).
for w in GPP0 GPP1 GPP3 XHC0 XHC1 XHC3 XHC4 NHI0 NHI1; do
  if grep -E "^$w[[:space:]]" /proc/acpi/wakeup | grep -q '\*enabled'; then
    echo "$w" > /proc/acpi/wakeup 2>/dev/null && log "wake disabled: $w"
  fi
done

# MT7925 internal BT (13d3:3608): allow autosuspend when idle
for d in /sys/bus/usb/devices/*; do
  [ -f "$d/idVendor" ] || continue
  if [ "$(cat "$d/idVendor"):$(cat "$d/idProduct")" = "13d3:3608" ] && [ -w "$d/power/control" ]; then
    echo auto > "$d/power/control" 2>/dev/null && log "bt usb autosuspend: $(basename "$d")"
  fi
done

# WiFi power save on (re-assert — the radio must sleep between beacons)
iw dev wlan0 set power_save on 2>/dev/null && log "wlan0 power_save=on"

# Dirty writeback timers (intent 6000/6000 from /etc/sysctl.d/99-eco-writeback.conf):
# TLP's set_dirty_parms rewrites both runtime values on every power-source event
# from its MAX_LOST_WORK_SECS defaults (15s on AC = 1500cs), so re-assert here
# (fail-soft, see docs/findings.md#writeback).
sysctl -w vm.dirty_writeback_centisecs=6000 vm.dirty_expire_centisecs=6000 >/dev/null 2>&1 \
  && log "dirty writeback/expire re-asserted=6000"

# Convergence pass: re-apply CPU power after event handlers (asusd resets SMU/EPP
# whenever the platform profile is touched by a power-source event).
if [ "$1" != resume ]; then
  sleep 5
  apply_cpu_power
fi
exit 0
