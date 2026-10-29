# readers.sh: one reader per registry check. Each reader emits exactly one verdict
# line via emit() and never writes anything.

# Zen 5 = CPUs 0-3,12-15 (ceiling 4700000); Zen 5c = CPUs 4-11,16-23 (ceiling 3200000).
ceil_for_cpu() {
  local c=$1
  if (( (c >= 0 && c <= 3) || (c >= 12 && c <= 15) )); then
    printf '4700000'
  elif (( c >= 4 && c <= 11 || c >= 16 && c <= 23 )); then
    printf '3200000'
  fi
}

check_epp() {
  local dir f val n=0 bad=()
  dir=$(live_path "/sys/devices/system/cpu/cpufreq")
  if [[ ! -d $dir ]]; then
    emit DRIFT EPP "no cpufreq policies found at $dir"
    return 0
  fi
  for f in "$dir"/policy*/energy_performance_preference; do
    [[ -f $f ]] || continue
    n=$((n + 1))
    val=$(trim "$(cat "$f")")
    [[ $val == dynamic* ]] || bad+=("$(basename "$(dirname "$f")")=$val")
  done
  if (( n == 0 )); then
    emit DRIFT EPP "no energy_performance_preference files found"
  elif (( ${#bad[@]} )); then
    emit DRIFT EPP "$(join_by ' ' "${bad[@]}") not dynamic ($((n - ${#bad[@]}))/$n ok)"
  else
    emit OK EPP "all $n policies dynamic"
  fi
}

check_ceil() {
  local dir d cpu raw exp smax imax n=0 bad=() all_zen5=1 cpus=()
  dir=$(live_path "/sys/devices/system/cpu/cpufreq")
  if [[ ! -d $dir ]]; then
    emit DRIFT CEIL "no cpufreq policies found at $dir"
    return 0
  fi
  for d in "$dir"/policy*/; do
    [[ -d $d ]] || continue
    n=$((n + 1))
    smax=$(trim "$(cat "$d/scaling_max_freq" 2>/dev/null || true)")
    imax=$(trim "$(cat "$d/cpuinfo_max_freq" 2>/dev/null || true)")
    raw=$(trim "$(cat "$d/related_cpus" 2>/dev/null || true)")
    exp=''
    if [[ -n $raw ]]; then
      read -ra cpus <<<"$raw"
      all_zen5=1
      for cpu in "${cpus[@]}"; do
        [[ $(ceil_for_cpu "$cpu") == 4700000 ]] || all_zen5=0
      done
      if (( all_zen5 )); then
        exp=4700000
      else
        exp=3200000
        for cpu in "${cpus[@]}"; do
          [[ $(ceil_for_cpu "$cpu") == 3200000 ]] || exp=4700000
        done
      fi
    fi
    # Classify by related_cpus; fall back to cpuinfo_max_freq > 4400000 = Zen5.
    if [[ -z $exp ]]; then
      if [[ -n $imax ]] && (( imax > 4400000 )); then exp=4700000; else exp=3200000; fi
    fi
    if [[ $smax != "$exp" ]]; then
      bad+=("$(basename "${d%/}")=$smax want $exp")
    fi
  done
  if (( n == 0 )); then
    emit DRIFT CEIL "no cpufreq policies found"
  elif (( ${#bad[@]} )); then
    emit DRIFT CEIL "$(join_by ' ' "${bad[@]}")"
  else
    emit OK CEIL "all $n policies capped 4700000 (Zen5) / 3200000 (Zen5c)"
  fi
}

check_co() {
  local f missing=()
  f=$(owned_state_file "/home/zhangdm/.reserve/hw-tune.fish")
  grep -qF 'set -l coall -7' "$f" 2>/dev/null || missing+=("set -l coall -7")
  grep -qF 'set -l per_core_offsets -24 -24 -21 -21 -9 -11 -8 -6' "$f" 2>/dev/null \
    || missing+=("set -l per_core_offsets -24 -24 -21 -21 -9 -11 -8 -6")
  if (( ${#missing[@]} )); then
    emit DRIFT CO "state/owned hw-tune.fish missing: $(join_by ', ' "${missing[@]}")"
  else
    emit OK CO "state/owned hw-tune.fish has coall -7 and the 8 per-core offsets"
  fi
}

smu_value() {
  # First decimal number on the table line naming $2 in ryzenadj --info output.
  grep -F -- "$2" <<<"$1" | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || true
}

check_ppt() {
  local out fast slow stapm
  out=$(ryzenadj --info 2>&1 || true)
  fast=$(smu_value "$out" "PPT LIMIT FAST")
  slow=$(smu_value "$out" "PPT LIMIT SLOW")
  stapm=$(smu_value "$out" "STAPM LIMIT")
  if [[ -z $fast || -z $slow ]]; then
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
      emit SKIPPED PPT "needs sudo"
    else
      emit DRIFT PPT "ryzenadj --info returned no power table"
    fi
    return 0
  fi
  if [[ $fast != 31.000 || $slow != 31.000 ]]; then
    emit DRIFT PPT "PPT FAST=$fast SLOW=$slow want 31.000"
    return 0
  fi
  if [[ $stapm == 31.000 ]]; then
    emit OK PPT "PPT FAST/SLOW/STAPM 31.000"
    return 0
  fi
  # Contract (findings#ppt): ACCEPTED is scoped to a STAPM readback BELOW 31 W
  # (firmware floor class, findings#ppt). Parse numerically: anything above the
  # 31 W envelope is DRIFT, and an empty or unparseable readback is DRIFT too
  # (the output format changed and needs eyes). StapmTimeConst readback
  # artifacts (0.000) are likewise expected and never a verdict input.
  if [[ ! $stapm =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    emit DRIFT PPT "STAPM readback unparseable: '${stapm:-empty}' (format changed)"
    return 0
  fi
  if awk -v v="$stapm" 'BEGIN{exit !(v < 31)}'; then
    emit ACCEPTED PPT "STAPM $stapm W, firmware preference" "findings#ppt"
    return 0
  fi
  if awk -v v="$stapm" 'BEGIN{exit !(v > 31)}'; then
    emit DRIFT PPT "STAPM $stapm W above the 31 W envelope (want 31.000)"
    return 0
  fi
  emit DRIFT PPT "STAPM readback '$stapm' is 31 but not the 31.000 format (want 31.000)"
}

check_eco() {
  local f
  f=$(owned_state_file "/home/zhangdm/.reserve/hw-tune.fish")
  if grep -qF -- '--power-saving' "$f" 2>/dev/null; then
    emit OK ECO "state/owned hw-tune.fish has --power-saving"
  else
    emit DRIFT ECO "--power-saving missing from state/owned hw-tune.fish"
  fi
}

check_wifi() {
  local iw nm bad=()
  iw=$(iw dev wlan0 get power_save 2>&1 || true)
  nm=$(live_path "/etc/NetworkManager/conf.d/99-wifi-powersave.conf")
  grep -qiE 'power save:[[:space:]]*on' <<<"$iw" || bad+=("iw power_save=$(trim "$iw")")
  grep -qF 'wifi.powersave = 3' "$nm" 2>/dev/null || bad+=("NM wifi.powersave != 3")
  if (( ${#bad[@]} )); then
    emit DRIFT WIFI "$(join_by ' ' "${bad[@]}")"
  else
    emit OK WIFI "iw power_save on, NM wifi.powersave = 3"
  fi
}

check_bt() {
  local sysf legacy bad=()
  sysf=$(live_path "/sys/module/btusb/parameters/enable_autosuspend")
  legacy=$(live_path "/etc/modprobe.d/btusb-no-autosuspend.conf")
  [[ $(trim "$(cat "$sysf" 2>/dev/null || true)") == Y ]] || bad+=("enable_autosuspend != Y")
  [[ ! -e $legacy ]] || bad+=("btusb-no-autosuspend.conf present")
  if (( ${#bad[@]} )); then
    emit DRIFT BT "$(join_by ' ' "${bad[@]}")"
  else
    emit OK BT "btusb autosuspend enabled, legacy conf absent"
  fi
}

check_tlp() {
  local live
  live=$(live_path "/etc/tlp.d/01-eco.conf")
  if mirror_equal "$live"; then
    emit OK TLP "/etc/tlp.d/01-eco.conf byte-equal to state/owned mirror"
  else
    emit DRIFT TLP "/etc/tlp.d/01-eco.conf differs from state/owned mirror"
  fi
}

check_timer() {
  # SMU paths boot-only (owner 2026-10-11): the 600 s backstop timer and the AC-event udev
  # trigger for the full pass stay dropped. Ceil watch active (owner 2026-10-29): the 4.7/3.2
  # cap was observed overwritten to the hardware max between passes, so it gets a drift-only
  # watch (eco-ceil.timer + 82-eco-ceil.rules -> `eco-power.sh ceil`; no SMU writes). The
  # frozen TIMER id guards this whole contract.
  local svc st bad=()
  svc=$(live_path "/etc/systemd/system/eco-power.service")
  [[ -e $(live_path "/etc/systemd/system/eco-power.timer") ]] \
    && bad+=("eco-power.timer present (dropped 2026-10-11)")
  [[ -e $(live_path "/etc/udev/rules.d/99-eco-power.rules") ]] \
    && bad+=("udev power trigger present (dropped 2026-10-11)")
  grep -qF 'WantedBy=multi-user.target' "$svc" 2>/dev/null \
    || bad+=("eco-power.service not boot-enabled")
  # systemd's own state is the consumer: a WantedBy= line is not proof of enablement
  # (burned 2026-10-13 — the timer used to start the service, so the unit was never
  # enabled; after the timer drop nothing ran at boot while this check read OK).
  st=$(trim "$(systemctl is-enabled eco-power.service 2>&1 || true)")
  [[ $st == enabled ]] || bad+=("eco-power.service is-enabled=${st:-unreadable}")
  # The convergence promise (README rule 1) lives in the service chain: the
  # second ExecStart must run eco apply after eco-power.sh (ExecStart=- so a
  # missing repo or apply failure can never fail the boot-critical chain).
  grep -qF 'ExecStart=-/home/zhangdm/Projects/system-tuning/eco apply' "$svc" 2>/dev/null \
    || bad+=("eco apply ExecStart missing from eco-power.service")
  [[ -e $(live_path "/etc/systemd/system/eco-ceil.timer") ]] \
    || bad+=("eco-ceil.timer missing")
  [[ -e $(live_path "/etc/systemd/system/eco-ceil.service") ]] \
    || bad+=("eco-ceil.service missing")
  [[ -e $(live_path "/etc/udev/rules.d/82-eco-ceil.rules") ]] \
    || bad+=("udev ceil trigger missing")
  st=$(trim "$(systemctl is-enabled eco-ceil.timer 2>&1 || true)")
  [[ $st == enabled ]] || bad+=("eco-ceil.timer is-enabled=${st:-unreadable}")
  if (( ${#bad[@]} )); then
    emit DRIFT TIMER "$(join_by ' ' "${bad[@]}")"
  else
    emit OK TIMER "eco-power.service boot-only for SMU paths, eco-ceil watch active (timer + udev), chains eco apply"
  fi
}

check_io() {
  local wb ex bad=()
  wb=$(trim "$(sysctl -n vm.dirty_writeback_centisecs 2>/dev/null || true)")
  ex=$(trim "$(sysctl -n vm.dirty_expire_centisecs 2>/dev/null || true)")
  [[ $wb == 6000 ]] || bad+=("vm.dirty_writeback_centisecs=${wb:-unreadable}")
  [[ $ex == 6000 ]] || bad+=("vm.dirty_expire_centisecs=${ex:-unreadable}")
  managed_probe journald
  case $MP_STATE in
    ok) ;;
    differs) bad+=("$(managed_label journald) claimed line differs") ;;
    nomatch | multimatch) bad+=("$(managed_label journald) $MP_MSG") ;;
    missing-target) bad+=("$(managed_label journald) target missing") ;;
  esac
  if (( ${#bad[@]} )); then
    emit DRIFT IO "$(join_by ' ' "${bad[@]}")"
  else
    emit OK IO "dirty writeback/expire 6000, journald record matches"
  fi
}

check_sched() {
  # scx management dropped 2026-10-10 (owner: drop it entirely, update later): the scx-tools-git
  # 1:1.1.3 layout change removed /etc/scx_loader.toml and the missing managed target hard-failed
  # every apply. Scheduling is owner-managed until the scx rework lands (findings#sched).
  emit SKIPPED SCHED "scx record dropped 2026-10-10 — scx tooling rework pending"
}

check_profile() {
  # asusd config is repo-owned again (owner 2026-10-13, superseding the 2026-10-11
  # owner-managed ruling): four records claim the cast surface that collided with repo intent —
  # platform_profile_linked_epp (was casting BalancePerformance EPP on the AC profile),
  # ac_command/bat_command (were casting the governor), and the battery-profile mapping.
  # The platform_profile value itself stays asusd's runtime choice.
  local pf id bad=()
  pf=$(trim "$(cat "$(live_path "/sys/firmware/acpi/platform_profile")" 2>/dev/null || true)")
  for id in asusd asusd-epp asusd-ac-cmd asusd-bat-cmd; do
    managed_probe "$id"
    case $MP_STATE in
      ok) ;;
      differs) bad+=("$(managed_label "$id"):$id claimed line differs") ;;
      nomatch | multimatch) bad+=("$(managed_label "$id"):$id $MP_MSG") ;;
      missing-target) bad+=("$(managed_label "$id"):$id target missing") ;;
    esac
  done
  case $pf in
    balanced | performance | custom) ;;
    *) bad+=("platform_profile=${pf:-unreadable}") ;;
  esac
  if (( ${#bad[@]} )); then
    emit DRIFT PROFILE "$(join_by ' ' "${bad[@]}")"
  else
    emit OK PROFILE "asusd records match (EPP/governor casts off), platform_profile=$pf"
  fi
}

check_sd() {
  local out
  out=$(lspci -nnk -s c2:00.0 2>&1 || true)
  if [[ -z $(trim "$out") ]]; then
    emit SKIPPED SD "lspci unavailable" "rollback#sd"
    return 0
  fi
  if grep -qF 'Kernel driver in use' <<<"$out"; then
    emit WARN SD "reader re-bound (runtime-only unbind lost at reboot)" "rollback#sd"
  else
    emit OK SD "no kernel driver in use" "rollback#sd"
  fi
}

# systemctl --user must speak to the invoking user's session bus. Under sudo that
# context is gone (root cannot use the user bus at all), so re-attach to SUDO_USER's
# runtime dir and query from there; without sudo, query directly. Read-only either way.
user_is_enabled() {
  local unit=$1 uid
  if [[ -z $ECO_ROOT && ${EUID:-$(id -u)} -eq 0 && -n ${SUDO_USER:-} ]] \
    && uid=$(id -u "$SUDO_USER" 2>/dev/null); then
    sudo -u "$SUDO_USER" env \
      "XDG_RUNTIME_DIR=/run/user/$uid" \
      "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus" \
      systemctl --user is-enabled "$unit" 2>&1 || true
  else
    systemctl --user is-enabled "$unit" 2>&1 || true
  fi
}

check_misc() {
  local gate out bad=() skipped=() ok=()
  gate=$(trim "$(cat "$(live_path "/sys/module/snd_rn_pci_acp3x/parameters/acp_power_gating")" 2>/dev/null || true)")
  if [[ $gate == 1 ]]; then
    ok+=("acp_power_gating=1")
  else
    bad+=("acp_power_gating=${gate:-unreadable}")
  fi
  out=$(user_is_enabled localsearch-3)
  out=$(trim "$out")
  if [[ $out == masked ]]; then
    ok+=("localsearch-3 masked")
  elif [[ -z $out || $out == *'Failed to connect'* || $out == *'No medium found'* \
        || $out == *'No such file or directory'* ]]; then
    skipped+=("localsearch-3 needs user session")
  else
    bad+=("localsearch-3=$out")
  fi
  managed_probe niri-autostart
  case $MP_STATE in
    ok) ok+=("niri record matches") ;;
    differs) bad+=("$(managed_label niri-autostart) claimed line differs") ;;
    nomatch | multimatch) bad+=("$(managed_label niri-autostart) $MP_MSG") ;;
    missing-target) bad+=("$(managed_label niri-autostart) target missing") ;;
  esac
  if (( ${#bad[@]} )); then
    emit DRIFT MISC "$(join_by ' ' "${bad[@]}")"
  elif (( ${#skipped[@]} )); then
    emit SKIPPED MISC "$(join_by ' ' "${skipped[@]}")" "rollback#misc"
  else
    emit OK MISC "$(join_by ', ' "${ok[@]}")"
  fi
}
