# Action summary — 2026-11-03 — PPD action surface enabled + made persistent

## What changed

Owner ask: enable all PPD actions (the two amdgpu ones were disabled) and turn on battery
awareness. Investigation found the enablement was runtime-only, so this became a persistence fix:

| Item | State before | Disposition |
|---|---|---|
| `trickle_charge` | enabled (persisted in state.ini) | kept on |
| `amdgpu_panel_power` | disabled | enabled |
| `amdgpu_dpm` | disabled | enabled |
| battery-aware dynamics | already ON (state.ini `battery_aware=true`, 18:17) | verified on + asserted |
| persistence | **flags runtime-only**: `configure-action` never touches state.ini and a PPD restart reverts them (verified) | new owned drop-in `power-profiles-daemon.service.d/20-eco-actions.conf` re-asserts the 3 actions + battery-aware via `ExecStartPost` (fail-soft `-`) after every PPD start |
| TLP GPU lines | `RADEON_DPM_PERF_LEVEL_*` + `AMDGPU_ABM_LEVEL_*` wrote the SAME attributes (`power_dpm_force_performance_level`, `amdgpu/panel_power_savings`) | **retired** (two-writer race closed exactly like the governor lines) |

## Verification

- Restart survival (the whole point): PPD restarted → all three actions `Enabled: True`
  (ExecStartPost exit 0 each), `query-battery-aware` True. Before the drop-in, the same restart
  reverted both amdgpu actions to False.
- `./eco report` drift=0; gate 97/97 (new case22d: corrupting the drop-in line DRIFTs).
- Live attrs after enable: `power_dpm_force_performance_level: auto`,
  `amdgpu/panel_power_savings: 0` (per-profile values owned by PPD now).

## Notes

- The initial drop-in landed section-less (no `[Service]` header) and was ignored — fixed and
  re-verified before hand-off.
- Battery-aware means the active profile now moves with charger/battery events (observed
  `Profile=balanced` in state.ini) — the fixed "profile performance" reading is superseded
  (findings `## epp` action-surface note).
- `tests/fixtures/var/lib/power-profiles-daemon/state.ini` mirrors live (fixture rule); the check
  reads only `battery_aware` from it and asserts the drop-in mirror for the action mechanism
  (state.ini's action flags lag reality — do not read them as truth).

## Open items for the owner

- Commit disposition.
- Optional: with battery-aware dynamics now switching profiles, re-observe the power behavior on
  AC vs battery (the benchmark doctrine: kernel/profile changes = new baseline).
