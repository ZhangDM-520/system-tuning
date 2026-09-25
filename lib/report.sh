# report.sh: verdict formatting (text and --json) and shared exit-code derivation.

R_VERDICT=()
R_ID=()
R_EV=()
R_DOC=()

emit() {
  R_VERDICT+=("$1")
  R_ID+=("$2")
  R_EV+=("$3")
  R_DOC+=("${4:-}")
}

report_count() {
  local want=$1 n=0 v
  for v in "${R_VERDICT[@]}"; do
    [[ $v == "$want" ]] && n=$((n + 1))
  done
  printf '%s' "$n"
}

report_exit() {
  local v
  for v in "${R_VERDICT[@]}"; do
    if [[ $v == DRIFT ]]; then
      printf '1'
      return 0
    fi
  done
  printf '0'
}

report_summary_line() {
  printf 'SUMMARY ok=%s accepted=%s warn=%s drift=%s skipped=%s exit=%s' \
    "$(report_count OK)" "$(report_count ACCEPTED)" "$(report_count WARN)" \
    "$(report_count DRIFT)" "$(report_count SKIPPED)" "$(report_exit)"
}

report_print() {
  local i doc
  for i in "${!R_ID[@]}"; do
    doc=${R_DOC[$i]}
    printf '%s %s %s%s\n' "${R_VERDICT[$i]}" "${R_ID[$i]}" "${R_EV[$i]}" "${doc:+ $doc}"
  done
  report_summary_line
  printf '\n'
}

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

report_json() {
  local i sep=''
  printf '{\n  "checks": ['
  for i in "${!R_ID[@]}"; do
    printf '%s\n    {"id": "%s", "verdict": "%s", "evidence": "%s", "doc": "%s"}' \
      "$sep" "$(json_escape "${R_ID[$i]}")" "$(json_escape "${R_VERDICT[$i]}")" \
      "$(json_escape "${R_EV[$i]}")" "$(json_escape "${R_DOC[$i]}")"
    sep=','
  done
  printf '\n  ],\n'
  printf '  "summary": {"ok": %s, "accepted": %s, "warn": %s, "drift": %s, "skipped": %s},\n' \
    "$(report_count OK)" "$(report_count ACCEPTED)" "$(report_count WARN)" \
    "$(report_count DRIFT)" "$(report_count SKIPPED)"
  printf '  "exit_code": %s\n}\n' "$(report_exit)"
}
