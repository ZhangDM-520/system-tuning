#!/usr/bin/env fish

# hw-tune.fish — single source of truth for all ryzenadj hardware-level tuning.
# Formerly undervolt.fish (Curve Optimizer only). Renamed + extended 2026-09-23 (session 023).
# Triggers: niri autostart (login, TTY-recoverable failure domain) AND
# /usr/local/sbin/eco-power.sh (boot, resume — the power-source udev trigger and the 60 s
# backstop timer were dropped 2026-10-11) — asusd re-asserts its profile's limits on power
# events, so this re-runs to converge.
# All writes are idempotent.
#
# Doctrine: work-per-joule / race-to-sleep. No power caps, no clock caps, no OC.
# Rollback: ~/.reserve/undervolt.fish.bak holds the original CO values.

# ---- Configuration ----
# CPU Curve Optimizer — owner ruling 2026-10-08: loosened one step (coall -7 -> -6; per-core
# +3 +3 +3 +3 +1 +1 +1 +1). Rationale: CPU stalls at too-low voltage are a hard-freeze suspect
# and can explain the "ryzen_smu out of sync" symptoms; loosening is the safe direction
# (docs/judgment.md: never step CO deeper than validated). See docs/findings.md ## co.
set -l coall -3
# 2026-10-11 owner ruling: every offset loosened 2 units (stability direction).
# 2026-10-26 owner ruling: every offset loosened 1 unit (stability direction).
set -l per_core_offsets -17 -17 -14 -14 -5 -7 -4 -2

# Ensure ryzenadj binary exists before execution
if not type -q ryzenadj
    echo "Error: ryzenadj binary not found in PATH." >&2
    exit 1
end

# Self-elevate privileges if not running as root
if test (id -u) -ne 0
    exec sudo fish (status current-filename) $argv
end

# 1. CPU Curve Optimizer: global offset first, then per-core (16-bit two's complement packing)
if test $coall -ne 0
    set -l smu_coall_val (math "($coall + 65536) % 65536")
    ryzenadj --set-coall=(printf "0x%08X" $smu_coall_val)
end

for array_idx in (seq (count $per_core_offsets))
    set -l core_idx (math "$array_idx - 1")
    set -l offset $per_core_offsets[$array_idx]
    set -l smu_offset (math "($offset + 65536) % 65536")
    set -l packed_val (math "$core_idx * 1048576 + $smu_offset")
    ryzenadj --set-coper=(printf "0x%08X" $packed_val)
end

# 2. iGPU Curve Optimizer — NOT AVAILABLE: "set_cogfx is not supported on this family"
#    (Strix Point exposes no iGPU CO; verified 2026-09-23). Tried -5 and -10, both rejected.

# 3. Flat power envelope at platform max: STAPM = FAST = SLOW = 31 W.
#    The 17 W sustained dip was a cap — a cap is not efficiency.
ryzenadj --stapm-limit=31000 --fast-limit=31000 --slow-limit=31000
#    Sane time constants (stapm-time readback showed 0.0 — anomaly; keep restoring 128 s)
ryzenadj --stapm-time=128 --slow-time=1

# 4. SMU behavioral flag: hidden eco behavior (normally applied on AC unplug).
#    Observable effect: CCLK Boost SETPOINT 24.0 -> 6.8 in --info.
ryzenadj --power-saving

# NOT AVAILABLE on Strix Point (verified 2026-09-23, ryzenadj 0.19):
#   --psi0-current / --psi0soc-current / --psi3cpu_current / --psi3gfx_current
#     -> "set_psiX_current is not supported on this family"
#   --prochot-deassertion-ramp -> "rejected by SMU"

exit 0
