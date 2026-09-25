# Reboot checklist

When to read: before any reboot, and immediately after one. The convergence chain (boot ->
eco-power.service, plus the 600s backstop) re-asserts nearly everything, so this is a confirmation
walk, not a repair session.

## After boot (in order)

1. `./eco report` (unprivileged is fine; `sudo` adds the SMU rows).
   Expect: exit 0 with OK rows, one ACCEPTED row for PPT (STAPM firmware floor, quirks#stapm),
   possibly a WARN on SD (reader re-binds at boot: runtime-only unbind, rollback#sd), and possibly
   SKIPPED rows where a check needs root or a user session (counted green, means unverified).
2. `systemctl list-timers eco-power.timer` shows the 600s backstop armed.
3. AC state sanity: `cat /sys/class/power_supply/AC0/online`. If the state looks wrong versus
   reality, do one physical plug cycle (known EC misread, quirks#ec) before diagnosing anything.
4. Only if PPT shows DRIFT instead of ACCEPTED: run `sudo ./eco apply` and re-report.
5. acp_power_gating applies fully at boot (module load parameter): expect OK on MISC from the
   first report onward.

## Before reboot

1. Nothing to do for the power stack: everything durable is in repo state/ and re-applied at boot.
2. If you are mid-experiment on a live value: capture it first (`./eco harvest`), or it is gone.
3. If the firmware/EC was misbehaving and you want the discharge path: shut down fully (not
   reboot); the EC clears only on a real power-off.

## Around suspend/resume (the common path)

Resume re-triggers eco-power via the sleep hook and the udev rule. Expected resume anomalies, all
documented and harmless: the freesync VRR warning (cosmetic), asusd WARN lines (only if the
profile mapping is broken again), and a transient STAPM readback while the envelope re-converges.

## The two human-only items

1. Bluetooth: power the radio off when not in use (`bluetoothctl power off`); the USB device only
   suspends then (decisions#bt).
2. SD reader: after a reboot it is bound again. Leave it (WARN is expected) or re-run the unbind
   one-liner from rollback#sd.
