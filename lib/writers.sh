# writers.sh: deploy adapter (repo to live) for `apply`, collect adapter (live to
# intent) for `harvest`, the apply lock, and the dated backup convention.

BACKUPS=()
APPLIED=()
PLAN_KIND=()
PLAN_TARGET=()
PLAN_SRC=()
PLAN_ID=()
PLAN_ANOMALY=()

die3_partial() {
  # Exit 3: apply step failed. Nothing after the failing step runs; report the
  # partial state plus the rollback anchors so the owner can unwind.
  local t a done pending=()
  for t in "${PLAN_TARGET[@]:-}"; do
    [[ -z $t ]] && continue
    done=0
    for a in "${APPLIED[@]:-}"; do [[ $a == "$t" ]] && done=1; done
    (( done )) || pending+=("$t")
  done
  printf 'eco: apply: step failed: %s\n' "$1" >&2
  printf 'applied: %s\n' "$(join_by ' ' "${APPLIED[@]:-none}")" >&2
  printf 'not-applied: %s\n' "$(join_by ' ' "${pending[@]:-none}")" >&2
  printf 'rollback anchors: %s\n' "$(join_by ' ' "${BACKUPS[@]:-none}")" >&2
  exit 3
}

assert_in_root() {
  # Defense in depth for the fixture seam: every write must land under ECO_ROOT.
  if [[ -n $ECO_ROOT && $1 != "$ECO_ROOT"/* ]]; then
    die3_partial "refusing write outside ECO_ROOT: $1"
  fi
}

lock_acquire() {
  LOCKFILE="${ECO_ROOT}/run/lock/eco-power-apply.lock"
  mkdir -p "$(dirname "$LOCKFILE")"
  exec 9>>"$LOCKFILE"
  if ! flock -n 9; then
    local holder
    holder=$(tail -n1 "$LOCKFILE" 2>/dev/null || true)
    printf 'eco: apply: lock held by %s (%s)\n' "${holder:-unknown holder}" "$LOCKFILE" >&2
    exit 2
  fi
  printf 'pid=%s start=%s\n' "$$" "$(date -Is)" >&9
}

lock_release() {
  flock -u 9 2>/dev/null || true
}

# Plan step: compute every pending change and every hard anomaly. Writes nothing.
# With dry=1 (the read-only plan) a root-only file that cannot be read degrades to
# a SKIPPED note instead of a write plan or hard error: a plan never needs root.
PLAN_SKIP=()
plan_collect() {
  local dry=${1:-0}
  PLAN_KIND=() PLAN_TARGET=() PLAN_SRC=() PLAN_ID=() PLAN_ANOMALY=() PLAN_SKIP=()
  local src rel live id lp
  while IFS= read -r src; do
    rel=${src#"$OWNED_DIR"/}
    live=$(live_path "/$rel")
    if [[ -e $live && ! -r $live ]]; then
      if (( dry )); then
        PLAN_SKIP+=("/$rel (unreadable without root)")
        continue
      fi
    fi
    if [[ ! -e $live ]] || ! cmp -s "$src" "$live"; then
      PLAN_KIND+=(owned) PLAN_TARGET+=("$live") PLAN_SRC+=("$src") PLAN_ID+=("/$rel")
    fi
  done < <(owned_state_files)
  for id in "${MANAGED_IDS[@]}"; do
    managed_load "$id"
    lp=$(live_path "$MG_TARGET")
    if [[ -e $lp && ! -r $lp ]]; then
      if (( dry )); then
        PLAN_SKIP+=("$MG_LABEL: $MG_TARGET (unreadable without root)")
        continue
      fi
    fi
    managed_probe "$id"
    lp=$MP_LIVE
    case $MP_STATE in
      missing-target)
        PLAN_ANOMALY+=("$MG_LABEL: target $MG_TARGET missing (foreign file is never created)")
        continue
        ;;
      nomatch | multimatch)
        PLAN_ANOMALY+=("$MG_LABEL: $MP_MSG in $MG_TARGET")
        continue
        ;;
    esac
    if [[ $MP_STATE == differs ]]; then
      PLAN_KIND+=(managed) PLAN_TARGET+=("$lp") PLAN_SRC+=("$id") PLAN_ID+=("$MG_LABEL")
    fi
  done
}

# Runtime re-assert: owned sysctl.d files are the intent, but runtime values drift
# (TLP rewrites vm.dirty_* on every power-source event). Collect key/value pairs
# whose runtime value disagrees with the owned file. Matching dialect is ERE (bash =~).
RUNTIME_KEY=()
RUNTIME_WANT=()
RUNTIME_CUR=()

runtime_collect() {
  RUNTIME_KEY=() RUNTIME_WANT=() RUNTIME_CUR=()
  local f line key want cur
  while IFS= read -r f; do
    case $f in
      "$OWNED_DIR"/etc/sysctl.d/* | "$OWNED_DIR"/etc/sysctl.conf) ;;
      *) continue ;;
    esac
    while IFS= read -r line || [[ -n $line ]]; do
      [[ $line =~ ^[[:space:]]*([A-Za-z0-9_.]+)[[:space:]]*=[[:space:]]*([^[:space:]#]+) ]] || continue
      key=${BASH_REMATCH[1]} want=${BASH_REMATCH[2]}
      cur=$(sysctl -n "$key" 2>/dev/null || true)
      cur=$(trim "$cur")
      [[ $cur == "$want" ]] && continue
      RUNTIME_KEY+=("$key") RUNTIME_WANT+=("$want") RUNTIME_CUR+=("${cur:-unreadable}")
    done <"$f"
  done < <(owned_state_files)
}

runtime_print() {
  (( ${#RUNTIME_KEY[@]} )) || return 0
  local i
  printf 'RUNTIME %d sysctl re-assert(s)\n' "${#RUNTIME_KEY[@]}"
  for i in "${!RUNTIME_KEY[@]}"; do
    printf '  SYSCTL %s runtime=%s want=%s\n' \
      "${RUNTIME_KEY[$i]}" "${RUNTIME_CUR[$i]}" "${RUNTIME_WANT[$i]}"
  done
}

runtime_apply() {
  (( ${#RUNTIME_KEY[@]} )) || return 0
  local i
  if [[ -n $ECO_ROOT ]]; then
    for i in "${!RUNTIME_KEY[@]}"; do
      printf 'RUNTIME sysctl -w %s=%s (suppressed under ECO_ROOT)\n' \
        "${RUNTIME_KEY[$i]}" "${RUNTIME_WANT[$i]}"
    done
    return 0
  fi
  for i in "${!RUNTIME_KEY[@]}"; do
    sysctl -w "${RUNTIME_KEY[$i]}=${RUNTIME_WANT[$i]}" >/dev/null 2>&1 \
      || die3_partial "runtime sysctl re-assert failed: ${RUNTIME_KEY[$i]}=${RUNTIME_WANT[$i]}"
  done
}

plan_print() {
  local i
  printf 'PLAN %d change(s)\n' "${#PLAN_TARGET[@]}"
  for i in "${!PLAN_TARGET[@]}"; do
    case ${PLAN_KIND[$i]} in
      owned) printf '  OWNED %s (from state/owned%s)\n' "${PLAN_ID[$i]}" "${PLAN_ID[$i]}" ;;
      managed) printf '  MANAGED %s %s\n' "${PLAN_ID[$i]}" "${PLAN_TARGET[$i]}" ;;
    esac
  done
  for i in "${!PLAN_SKIP[@]}"; do
    printf '  SKIPPED %s\n' "${PLAN_SKIP[$i]}"
  done
}

# Backup step: cp -p <file> <file>.bak-YYYYMMDD alongside every target about to be
# written. Dated, never deleted: an existing same-day anchor is kept as-is.
# Exception: systemd-sleep executes EVERY file in system-sleep/ regardless of name,
# so sibling backups there run on every resume (burned 2026-09-29: a stale .bak hook
# stalled the thaw and re-ran SMU writes). Those anchors go to a -backups sibling
# directory instead, which nothing scans.
backup_step() {
  local i tgt bak date dir base
  date=$(date +%Y%m%d)
  for tgt in "${PLAN_TARGET[@]}"; do
    [[ -e $tgt ]] || continue
    dir=$(dirname "$tgt"); base=$(basename "$tgt")
    if [[ $dir == */usr/lib/systemd/system-sleep ]]; then
      bak="$dir-backups/$base.bak-$date"
      mkdir -p "$dir-backups" || die3_partial "backup dir failed: $dir-backups"
    else
      bak="$tgt.bak-$date"
    fi
    if [[ -e $bak ]]; then
      BACKUPS+=("$bak")
      continue
    fi
    assert_in_root "$bak"
    cp -p "$tgt" "$bak" || die3_partial "backup failed: $bak"
    BACKUPS+=("$bak")
  done
}

write_owned() {
  local src=$1 tgt=$2
  assert_in_root "$tgt"
  # state/ paths may nest (e.g. unit drop-in dirs) where live has no parent yet;
  # cp alone fails there. mkdir -p keeps cp's mode semantics (source mode wins on a
  # new target; an existing target keeps its mode) — see AGENTS.md mode lesson.
  mkdir -p "$(dirname "$tgt")" || return 1
  cp "$src" "$tgt" || return 1
  return 0
}

write_managed() {
  local id=$1
  managed_probe "$id"
  [[ $MP_STATE == differs ]] || return 0
  assert_in_root "$MP_LIVE"
  # a real failure status must reach the caller so die3_partial can report the
  # applied/not-applied split and the backup rollback anchors (exit 3)
  managed_replace_line "$MP_LIVE" "$MP_IDX" "$MG_LINE" || return 1
  return 0
}

# Reload step: daemon-reload / sysctl --system only when a target they cover changed.
# Under ECO_ROOT the reload is suppressed (the fixture seam must not touch the live
# systemd or sysctl state); the trigger decision is still reported.
reload_step() {
  local tgt do_daemon=0 do_sysctl=0
  for tgt in "${APPLIED[@]}"; do
    case $tgt in
      */systemd/system/* | *.service | *.timer | *.socket | *.target) do_daemon=1 ;;
      */sysctl.d/* | *sysctl.conf*) do_sysctl=1 ;;
    esac
  done
  (( do_daemon == 0 && do_sysctl == 0 )) && return 0
  if [[ -n $ECO_ROOT ]]; then
    (( do_daemon )) && printf 'RELOAD systemctl daemon-reload (suppressed under ECO_ROOT)\n'
    (( do_sysctl )) && printf 'RELOAD sysctl --system (suppressed under ECO_ROOT)\n'
    return 0
  fi
  if (( do_daemon )); then
    printf 'RELOAD systemctl daemon-reload\n'
    systemctl daemon-reload || die3_partial "systemctl daemon-reload failed"
  fi
  if (( do_sysctl )); then
    printf 'RELOAD sysctl --system\n'
    sysctl --system || die3_partial "sysctl --system failed"
  fi
}

cmd_apply() {
  local dry=$1 i n_planned n_applied
  require_state
  # --dry-run is a read-only plan: no root escalation, no lock (README contract).
  # Real apply keeps the sudo re-exec and the apply lock.
  if (( ! dry )) && [[ -z $ECO_ROOT && ${EUID:-$(id -u)} -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || die2 "apply requires root (sudo unavailable)"
    exec sudo "$ECO_HOME/eco" apply
  fi
  if (( ! dry )); then
    lock_acquire
    trap lock_release EXIT
  fi

  # plan: file targets (plan_collect) plus runtime sysctl drift (runtime_collect)
  plan_collect "$dry"
  plan_print
  runtime_collect
  runtime_print
  if (( ${#PLAN_ANOMALY[@]} )); then
    for i in "${!PLAN_ANOMALY[@]}"; do
      printf 'eco: apply: hard error: %s\n' "${PLAN_ANOMALY[$i]}" >&2
    done
    printf 'applied: none\nnot-applied: %s\n' "$(join_by ' ' "${PLAN_ID[@]:-all pending targets}")" >&2
    printf 'eco: apply: refusing, nothing written\n' >&2
    exit 3
  fi
  if (( dry )); then
    printf 'DRY-RUN nothing written\n'
    exit 0
  fi
  n_planned=$(( ${#PLAN_TARGET[@]} + ${#RUNTIME_KEY[@]} ))
  if (( n_planned == 0 )); then
    printf 'SUMMARY planned=0 applied=0 failed=0 exit=0\n'
    exit 0
  fi

  # backup
  backup_step

  # owned writes
  for i in "${!PLAN_TARGET[@]}"; do
    [[ ${PLAN_KIND[$i]} == owned ]] || continue
    write_owned "${PLAN_SRC[$i]}" "${PLAN_TARGET[$i]}" \
      || die3_partial "owned write failed: ${PLAN_TARGET[$i]}"
    APPLIED+=("${PLAN_TARGET[$i]}")
  done

  # managed edits
  for i in "${!PLAN_TARGET[@]}"; do
    [[ ${PLAN_KIND[$i]} == managed ]] || continue
    write_managed "${PLAN_SRC[$i]}" \
      || die3_partial "managed edit failed: ${PLAN_TARGET[$i]}"
    APPLIED+=("${PLAN_TARGET[$i]}")
  done

  # reloads
  reload_step

  # runtime re-assert (no file is written; the printed runtime= value is the
  # rollback anchor). Runs even when no owned file changed, because the runtime
  # drifts independently of the files (see docs/findings.md#writeback).
  runtime_apply
  n_applied=$(( ${#APPLIED[@]} + ${#RUNTIME_KEY[@]} ))

  # verify: a fresh plan must now be empty; residual mismatch is drift that
  # persisted after apply (exit 1), not a step failure
  plan_collect
  runtime_collect
  if (( ${#PLAN_TARGET[@]} )) || (( ${#PLAN_ANOMALY[@]} )) || (( ${#RUNTIME_KEY[@]} )); then
    printf 'eco: apply: drift persisted after apply:\n' >&2
    for i in "${!PLAN_TARGET[@]}"; do printf '  %s\n' "${PLAN_TARGET[$i]}" >&2; done
    for i in "${!PLAN_ANOMALY[@]}"; do printf '  %s\n' "${PLAN_ANOMALY[$i]}" >&2; done
    for i in "${!RUNTIME_KEY[@]}"; do
      printf '  sysctl %s runtime=%s want=%s\n' \
        "${RUNTIME_KEY[$i]}" "${RUNTIME_CUR[$i]}" "${RUNTIME_WANT[$i]}" >&2
    done
    printf 'SUMMARY planned=%d applied=%d failed=0 exit=1\n' "$n_planned" "$n_applied"
    exit 1
  fi

  # verdict
  printf 'SUMMARY planned=%d applied=%d failed=0 exit=0\n' "$n_planned" "$n_applied"
  exit 0
}

# --- harvest: live -> intent proposal. Reads both sides, writes nothing. ---

toml_quote() {
  local s=$1
  if [[ $s != *\'* ]]; then
    printf "'%s'" "$s"
  else
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '"%s"' "$s"
  fi
}

toml_with_line() {
  local file=$1 val=$2 line
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ ^line[[:space:]]*= ]]; then
      printf 'line = %s\n' "$(toml_quote "$val")"
    else
      printf '%s\n' "$line"
    fi
  done <"$file"
}

cmd_harvest() {
  local count=0 src rel live id
  require_state
  while IFS= read -r src; do
    rel=${src#"$OWNED_DIR"/}
    live=$(live_path "/$rel")
    if [[ ! -e $live ]]; then
      printf '# note: live /%s missing, state/owned/%s kept as-is\n' "$rel" "$rel"
      continue
    fi
    if ! cmp -s "$src" "$live"; then
      diff -u --label "state/owned/$rel" --label "live /$rel (proposed intent)" "$src" "$live" || true
      count=$((count + 1))
    fi
  done < <(owned_state_files)
  for id in "${MANAGED_IDS[@]}"; do
    managed_probe "$id"
    case $MP_STATE in
      differs)
        diff -u --label "state/managed/$id.toml" \
          --label "proposed: line = live ${MG_TARGET}:${MP_IDX}" \
          "$MG_FILE" <(toml_with_line "$MG_FILE" "$MP_CUR") || true
        count=$((count + 1))
        ;;
      nomatch | multimatch)
        printf '# note: %s: %s in %s, no proposal\n' \
          "$(managed_label "$id")" "$MP_MSG" "$MG_TARGET"
        ;;
      missing-target)
        printf '# note: %s: target %s missing, no proposal\n' "$(managed_label "$id")" "$MG_TARGET"
        ;;
    esac
  done
  if (( count == 0 )); then
    printf 'harvest: intent state and live agree, nothing to land\n'
    exit 0
  fi
  printf 'DECISION-RECORD %s harvest: adopt live values for %d intent file(s); record why in docs/findings.md, land with an ordinary edit and git commit\n' \
    "$(date +%Y-%m-%d)" "$count"
  exit 1
}
