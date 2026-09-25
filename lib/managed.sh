# managed.sh: line-patch engine for foreign-file partial ownership.
# Regex dialect: POSIX ERE everywhere (grep -E / bash =~); record regexes are ERE.
# Discipline: a managed edit owns exactly ONE anchor-matched line, scoped either to
# the whole file or (with the optional `section` record key) to one section region.
# Zero or multiple matches in scope is a hard error. Unclaimed content survives
# byte-for-byte. A claimed line changed by someone else is surfaced as DRIFT (with
# a dated backup) before it is replaced, never overwritten silently.

managed_load() {
  local id=$1 f
  f=$(managed_file "$id")
  [[ -f $f ]] || die2 "missing state file $f"
  MG_ID=$id
  MG_LABEL=$(managed_label "$id")
  MG_FILE=$f
  MG_TARGET=$(toml_get "$f" target)
  MG_MATCH=$(toml_get "$f" match)
  MG_LINE=$(toml_get "$f" line)
  MG_DOC=$(toml_get "$f" doc)
  MG_SECTION=$(toml_get_opt "$f" section)
  [[ -n $MG_TARGET && -n $MG_MATCH && -n $MG_LINE ]] || die2 "incomplete state file $f"
}

# Print the 1-based line numbers of every anchor match in the live file, or (when
# start/end are given) within that 1-based inclusive line range.
managed_match_lines() {
  local file=$1 match=$2 start=${3:-} end=${4:-}
  [[ -f $file ]] || return 0
  if [[ -n $start ]]; then
    # An empty region (end < start, e.g. a section header immediately followed by
    # another header) has zero lines and therefore zero matches. Never hand it to
    # sed: GNU sed's "N,N-1p" prints line N, which would resolve the region to the
    # NEXT section's header line and patch the wrong line.
    (( end >= start )) || return 0
    sed -n "${start},${end}p" "$file" \
      | grep -nE -- "$match" 2>/dev/null | cut -d: -f1 \
      | awk -v off="$((start - 1))" '{print $1 + off}' || true
  else
    grep -nE -- "$match" "$file" 2>/dev/null | cut -d: -f1 || true
  fi
}

# Resolve the record's section region: lines after the section header (a line
# starting with `[` whose bytes match the record's section ERE) and before the next
# line starting with `[`. Sets SR_OK (0/1), SR_START, SR_END (1-based inclusive),
# SR_MSG (why the region is unusable). The header must match exactly one line.
# A section with no body (next header immediately follows) yields SR_END <
# SR_START: a valid but EMPTY region, which matches nothing (see
# managed_match_lines) and thus fails the one-match rule as a hard error.
managed_section_region() {
  local file=$1 sec=$2
  SR_OK=0 SR_START=0 SR_END=0 SR_MSG=''
  local hdr=() all=() num content total
  total=$(grep -c '' "$file")
  while IFS=: read -r num content; do
    all+=("$num")
    [[ $content =~ $sec ]] && hdr+=("$num")
  done < <(grep -nE -- '^[[]' "$file" 2>/dev/null || true)
  case ${#hdr[@]} in
    0) SR_MSG="section '$sec' matches 0 headers"; return 0 ;;
    1) ;;
    *) SR_MSG="section '$sec' matches ${#hdr[@]} headers"; return 0 ;;
  esac
  SR_START=$((hdr[0] + 1))
  SR_END=$total
  for num in "${all[@]}"; do
    if (( num > hdr[0] )); then SR_END=$((num - 1)); break; fi
  done
  SR_OK=1
}

# Probe one managed record against its live target. Sets:
#   MP_STATE  ok | differs | nomatch | multimatch | missing-target
#   MP_N      number of anchor matches in scope
#   MP_IDX    line number of the single match (when MP_N == 1)
#   MP_CUR    current content of the single match (when MP_N == 1)
#   MP_MSG    hard-error detail for nomatch/multimatch
managed_probe() {
  managed_load "$1"
  local live idxs
  live=$(live_path "$MG_TARGET")
  MP_N=0 MP_IDX=0 MP_CUR='' MP_MSG='' MP_LIVE=$live
  if [[ ! -f $live ]]; then
    MP_STATE=missing-target
    return 0
  fi
  if [[ -n $MG_SECTION ]]; then
    managed_section_region "$live" "$MG_SECTION"
    if (( SR_OK == 0 )); then
      MP_STATE=nomatch
      MP_MSG=$SR_MSG
      return 0
    fi
    idxs=$(managed_match_lines "$live" "$MG_MATCH" "$SR_START" "$SR_END")
  else
    idxs=$(managed_match_lines "$live" "$MG_MATCH")
  fi
  if [[ -z $idxs ]]; then
    MP_STATE=nomatch
    MP_MSG="0 lines match anchor${MG_SECTION:+ in section '$MG_SECTION'}"
    return 0
  fi
  MP_N=$(wc -l <<<"$idxs")
  if (( MP_N > 1 )); then
    MP_STATE=multimatch
    MP_MSG="$MP_N lines match anchor${MG_SECTION:+ in section '$MG_SECTION'}"
    return 0
  fi
  MP_IDX=$idxs
  MP_CUR=$(sed -n "${MP_IDX}p" "$live")
  if [[ $MP_CUR == "$MG_LINE" ]]; then
    MP_STATE=ok
  else
    MP_STATE=differs
  fi
  return 0
}

# Move a verified staging file over the live target, preserving the target's
# owner and mode. Extracted as its own function so tests can drive
# managed_replace_line with a failing stub of exactly this step.
managed_commit_tmp() {
  local tmp=$1 file=$2
  chmod --reference="$file" "$tmp" 2>/dev/null || true
  chown --reference="$file" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$file"
}

# Replace exactly one line in place. All other bytes (including a missing final
# newline and the file's mode/ownership) survive unchanged. The new content is
# built in a staging file and VERIFIED complete (non-empty, same line count as
# the source) before the live file is touched; the commit is an atomic mv, so a
# failed write can never leave a truncated or zeroed target. Returns 0 only on
# success; a real failure status propagates to the caller (never masked by the
# cleanup rm).
managed_replace_line() {
  local file=$1 idx=$2 repl=$3 tmp total last_nl=1
  tmp="${file}.eco-tmp.$$"
  total=$(grep -c '' "$file")
  if [[ -n "$(tail -c1 "$file")" ]]; then
    last_nl=0
  fi
  if ! {
    if (( idx > 1 )); then
      head -n "$((idx - 1))" "$file"
    fi
    if (( last_nl == 0 && idx == total )); then
      printf '%s' "$repl"
    else
      printf '%s\n' "$repl"
    fi
    if (( idx < total )); then
      tail -n "+$((idx + 1))" "$file"
    fi
  } >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  # staging verification: refuse to touch the live file unless the staged copy
  # is non-empty and holds exactly as many lines as the source
  if [[ ! -s $tmp ]] || [[ $(grep -c '' "$tmp") -ne $total ]]; then
    rm -f "$tmp"
    return 1
  fi
  if ! managed_commit_tmp "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
  return 0
}
