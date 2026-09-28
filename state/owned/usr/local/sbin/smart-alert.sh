#!/bin/bash
# smart-alert.sh - invoked by smartd on SMART events. Logs the event and leaves a
# marker file (this host has no MTA). Installed 2026-09-26.
#
# Why the triple capture: smartd -M exec delivers the alert as an EMAIL MESSAGE -
# body on STDIN plus mail-style args (-s "$SMARTD_SUBJECT" $SMARTD_ADDRESS) - and
# also exports SMARTD_SUBJECT/SMARTD_MESSAGE/SMARTD_FULLMESSAGE. Reading only "$1"
# would record the literal "-s" (a real bug caught in code review), so log every
# form and keep the smartctl snapshot as the diagnostic of record.
set -euo pipefail
LOG=/var/log/smartd-alert.log
MARKER_DIR=/var/lib/smart-alert
MARKER=$MARKER_DIR/NEEDS-ATTENTION
mkdir -p "$MARKER_DIR"
BODY=$(cat || true)
SUBJECT=${SMARTD_SUBJECT:-${1:-unknown}}
{
  echo "=== smartd alert: $(date -Is) ==="
  echo "subject: $SUBJECT"
  echo "message: ${SMARTD_MESSAGE:-unknown}"
  echo "device: ${SMARTD_DEVICE:-unknown}  failtype: ${SMARTD_FAILTYPE:-unknown}"
  echo "args: $*"
  echo "stdin: $BODY"
  /usr/bin/smartctl -a /dev/nvme0 || true
} >> "$LOG"
echo "$(date -Is) $SUBJECT" >> "$MARKER"
