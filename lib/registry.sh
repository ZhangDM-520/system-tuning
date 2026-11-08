# registry.sh: check vocabulary. ONE table; every map below derives from it.
#
# Row fields: id | reader | doc anchor | managed records (space-separated) | apply reach
# CHECK_IDS order is report order. Adding a check is one row here plus its reader
# function and a real `##` heading at the anchor. tests/run keeps its own literal ID
# list on purpose: that is the independent oracle (a check that silently vanishes must
# fail the gate), not a restatement.
#
# apply reach (printed as APPLY-SCOPE by the planner):
#   full      — apply's own writes can turn the row green
#   file-only — apply owns the file/intent half; the live effect has another owner
#   none      — apply cannot reach the row at all
declare -A CHECK_READER=() CHECK_DOC=() CHECK_MANAGED=() CHECK_APPLY=()
CHECK_IDS=()
while IFS='|' read -r _id _reader _doc _records _apply; do
  [[ -n $_id ]] || continue
  CHECK_IDS+=("$_id")
  CHECK_READER[$_id]=$_reader
  CHECK_DOC[$_id]=$_doc
  if [[ -n $_records ]]; then
    CHECK_MANAGED[$_id]=$_records
  fi
  CHECK_APPLY[$_id]=${_apply:-none}
done <<'TABLE'
EPP|check_epp|findings#epp|ppd-conflict|file-only
CEIL|check_ceil|findings#ceil||none
CO|check_co|findings#co||full
PPT|check_ppt|findings#ppt||none
ECO|check_eco|findings#eco||full
WIFI|check_wifi|findings#wifi||file-only
BT|check_bt|findings#bt||file-only
TLP|check_tlp|findings#pcie||file-only
TIMER|check_timer|findings#timer||none
IO|check_io|findings#writeback|journald|full
SCHED|check_sched|findings#sched||none
PROFILE|check_profile|findings#asusd|asusd-epp asusd-ac-cmd asusd-bat-cmd asusd-profile-ac asusd-profile-bat|file-only
SD|check_sd|rollback#sd||none
MISC|check_misc|rollback#misc|niri-autostart|file-only
TABLE
unset _id _reader _doc _records _apply
