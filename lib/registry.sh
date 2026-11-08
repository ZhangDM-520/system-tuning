# registry.sh: check vocabulary. Maps each check ID to its reader function and doc anchor.
# Report IDs are exactly these 14, in this order.

CHECK_IDS=(EPP CEIL CO PPT ECO WIFI BT TLP TIMER IO SCHED PROFILE SD MISC)

declare -A CHECK_READER=(
  [EPP]=check_epp
  [CEIL]=check_ceil
  [CO]=check_co
  [PPT]=check_ppt
  [ECO]=check_eco
  [WIFI]=check_wifi
  [BT]=check_bt
  [TLP]=check_tlp
  [TIMER]=check_timer
  [IO]=check_io
  [SCHED]=check_sched
  [PROFILE]=check_profile
  [SD]=check_sd
  [MISC]=check_misc
)

declare -A CHECK_DOC=(
  [EPP]="findings#epp"
  [CEIL]="findings#ceil"
  [CO]="findings#co"
  [PPT]="findings#ppt"
  [ECO]="findings#eco"
  [WIFI]="findings#wifi"
  [BT]="findings#bt"
  [TLP]="findings#pcie"
  [TIMER]="findings#timer"
  [IO]="findings#writeback"
  [SCHED]="findings#sched"
  [PROFILE]="findings#asusd"
  [SD]="rollback#sd"
  [MISC]="rollback#misc"
)

# Records each check asserts, as space-separated record IDs. This table is the ONE
# list: readers drive managed assertions from it (managed_check_problems), so a check
# never restates its record set. A record-backed check adds its IDs on this line.
declare -A CHECK_MANAGED=(
  [EPP]="ppd-conflict"
  [IO]="journald"
  [PROFILE]="asusd-epp asusd-ac-cmd asusd-bat-cmd asusd-profile-ac asusd-profile-bat"
  [MISC]="niri-autostart"
)
