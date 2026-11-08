# state.sh: repo state layout, live-path seam, mirror comparison helpers.
#
# ECO_ROOT (default empty = live root) prefixes all live paths for reads and writes: the internal test seam.
# ECO_STATE (default $ECO_HOME/state) relocates the intent tree: the test seam for the
# deployable filter, which lives in the intent walk and cannot be reached through ECO_ROOT.

: "${ECO_ROOT:=}"
if [[ -n $ECO_ROOT ]]; then
  ECO_ROOT=$(cd -- "$ECO_ROOT" && pwd)
fi
: "${ECO_STATE:=$ECO_HOME/state}"

STATE_DIR="$ECO_STATE"
OWNED_DIR="$STATE_DIR/owned"
MANAGED_DIR="$STATE_DIR/managed"

# state/managed/<file>.toml basename (load key) and the record ID the spec names it by.
# scx dropped 2026-10-10 (scx-tools-git layout change, rework deferred) — restore with its record.
# asusd power-profile handling muted 2026-10-30 (owner: all profile handling to power-profiles-
# daemon): five records patch one anchored line each in asusd.ron — EPP/governor casts plus the
# AC/battery platform_profile switching. The Q10 battery-mapping record was retired with the
# switching (inert once change_platform_profile_on_* is false).
# trash-purge timer-cadence record retired 2026-11-03 (owner ruling: eco never controls systemd
# timers — see docs/findings.md ## daemons).
# Record IDs derive from the registry's CHECK_MANAGED table (one list; first-seen order).
MANAGED_IDS=()
for _cid in "${CHECK_IDS[@]}"; do
  for _rid in ${CHECK_MANAGED[$_cid]:-}; do
    case " ${MANAGED_IDS[*]:-} " in
      *" $_rid "*) ;;
      *) MANAGED_IDS+=("$_rid") ;;
    esac
  done
done
unset _cid _rid
managed_label() {
  case "$1" in
    asusd-epp | asusd-ac-cmd | asusd-bat-cmd | asusd-profile-ac | asusd-profile-bat) printf 'asusd.ron' ;;
    ppd-conflict) printf 'power-profiles-daemon.service' ;;
    journald) printf 'journald.conf' ;;
    niri-autostart) printf 'niri-autostart.kdl' ;;
    *) printf '%s' "$1" ;;
  esac
}

die2() { printf 'eco: %s\n' "$*" >&2; exit 2; }

# Map an absolute live path through the ECO_ROOT seam (empty ECO_ROOT = live root).
live_path() { printf '%s%s' "$ECO_ROOT" "$1"; }

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

# Whitespace-normalized comparison form for a sysctl value: `sysctl -n` renders
# multi-value keys with tabs (3\t3\t3\t3), a file may hold spaces. Both sides go
# through this so equality is about values, not separators.
norm_sysctl_value() {
  local s=$1
  s=${s//$'\t'/ }
  s=${s//$'\n'/ }
  s=$(trim "$s")
  while [[ $s == *'  '* ]]; do s=${s//  / }; done
  printf '%s' "$s"
}

join_by() {
  local sep=$1 out='' e
  shift
  for e in "$@"; do
    out+="${out:+$sep}$e"
  done
  printf '%s' "$out"
}

# Minimal TOML value reader for the flat key = 'value' / key = "value" records in
# state/managed. toml_get_opt prints empty for an absent key (optional keys);
# toml_get hard-fails on absence (required keys).
toml_get_opt() {
  local file=$1 key=$2 line val
  line=$(grep -E "^${key}[[:space:]]*=" "$file" 2>/dev/null | head -1 || true)
  [[ -n $line ]] || return 0
  val=${line#*=}
  val=${val#"${val%%[![:space:]]*}"}
  val=${val%"${val##*[![:space:]]}"}
  if [[ $val == \'*\' ]]; then
    val=${val:1:${#val}-2}
  elif [[ $val == \"*\" ]]; then
    val=${val:1:${#val}-2}
    val=${val//\\\"/\"}
    val=${val//\\\\/\\}
  fi
  printf '%s' "$val"
}

toml_get() {
  local val
  val=$(toml_get_opt "$1" "$2")
  [[ -n $val ]] || die2 "missing state file key: $2 in $1"
  printf '%s' "$val"
}

# Path encoding: state/owned/<live path without leading slash>.
owned_state_file() { printf '%s/%s' "$OWNED_DIR" "${1#/}"; }

managed_file() { printf '%s/%s.toml' "$MANAGED_DIR" "$1"; }

# Whole-file-owned mirror comparison: 0 when live target is byte-equal to its state/owned mirror.
mirror_equal() {
  local live=$1 rel mirror
  rel=${live#"$ECO_ROOT"}
  mirror=$(owned_state_file "$rel")
  [[ -f $mirror && -e $live ]] && cmp -s "$mirror" "$live"
}

# A file under state/owned is deployable intent unless its name marks it as a backup or
# editor artifact. The walk is filesystem-based (not git), so a local stray would
# otherwise be written to live — and in system-sleep/ that file EXECUTES on every resume
# (burned 2026-09-29).
eco_deployable_name() {
  case ${1##*/} in
    *.bak | *.bak-* | *~ | *.orig | *.rej | *.swp | .#* | *.tmp) return 1 ;;
  esac
  return 0
}

# All deployable state/owned files, one absolute path per line, sorted (stable plan order).
owned_state_files() {
  local f
  while IFS= read -r f; do
    eco_deployable_name "$f" && printf '%s\n' "$f"
  done < <(find "$OWNED_DIR" -type f | sort)
}

# The strays the walk refuses, one per line. The plan prints them as SKIPPED: a silent
# filter would just move the silent failure.
owned_non_deployable_files() {
  local f
  while IFS= read -r f; do
    eco_deployable_name "$f" || printf '%s\n' "$f"
  done < <(find "$OWNED_DIR" -type f | sort)
}

# Preconditions shared by every verb: nothing may run against a half-present state tree.
require_state() {
  local f id
  for f in "$(owned_state_file "/home/zhangdm/.reserve/hw-tune.fish")" \
           "$(owned_state_file "/etc/tlp.d/01-eco.conf")"; do
    [[ -f $f ]] || die2 "missing state file $f"
  done
  for id in "${MANAGED_IDS[@]}"; do
    f=$(managed_file "$id")
    [[ -f $f ]] || die2 "missing state file $f"
  done
}
