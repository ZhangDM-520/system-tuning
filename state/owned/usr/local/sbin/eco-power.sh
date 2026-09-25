#!/usr/bin/env bash
# Convergence + eco settings (doctrine v2: work-per-joule, race-to-sleep).
# Triggers: boot (eco-power.service), resume (system-sleep hook), power-source udev,
# eco-power.timer backstop.
#
# Ordering note: any platform_profile write (asusd does one per power-source event)
# makes the EC reset SMU limits and EPP — so the CPU-power block runs twice, with a
# short delay, to land AFTER such handlers and converge.
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
  # EPP dynamic: driver adapts the bias per events/power source. Re-asserted here
  # because asusd writes a static "Power" EPP on every platform-profile event.
  for pol in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -w "$pol/energy_performance_preference" ] && echo dynamic > "$pol/energy_performance_preference" 2>/dev/null
  done
}

apply_cpu_power

# cpuidle governor teo: better idle-state prediction, deeper sleep more often
[ -w /sys/devices/system/cpu/cpuidle/current_governor ] \
  && echo teo > /sys/devices/system/cpu/cpuidle/current_governor 2>/dev/null \
  && log "cpuidle governor=teo"

# Per-core-class ceilings (owner 2026-09-23): Zen5 = 4.6 GHz, Zen5c = 3.1 GHz.
for pol in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -w "$pol/scaling_max_freq" ] || continue
  if [ "$(cat "$pol/cpuinfo_max_freq")" -gt 4400000 ]; then
    echo 4600000 > "$pol/scaling_max_freq" 2>/dev/null \
      && log "$(basename "$pol") scaling_max_freq=4600000"
  else
    echo 2900000 > "$pol/scaling_max_freq" 2>/dev/null \
      && log "$(basename "$pol") scaling_max_freq=2900000"
  fi
done

# Trim wake sources: internal keyboard (i8042 AT) + lid stay wake-capable (lid is EC-
# handled, i8042 is not in the ACPI table); disarm USB/USB4/WLAN-root wakes.
for w in GPP3 XHC0 XHC1 XHC3 XHC4 NHI0 NHI1; do
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
# (fail-soft, see docs/fleet-findings.md#storage).
sysctl -w vm.dirty_writeback_centisecs=6000 vm.dirty_expire_centisecs=6000 >/dev/null 2>&1 \
  && log "dirty writeback/expire re-asserted=6000"

# Convergence pass: re-apply CPU power after event handlers (asusd resets SMU/EPP
# whenever the platform profile is touched by a power-source event).
sleep 5
apply_cpu_power
exit 0
