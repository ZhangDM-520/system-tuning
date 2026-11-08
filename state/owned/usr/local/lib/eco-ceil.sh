# eco-ceil.sh: the ONE ceiling rule. Repo copy lives at
# state/owned/usr/local/lib/eco-ceil.sh and deploys here; the eco CLI loads it via
# lib/ceiling.sh and eco-power.sh sources it at runtime. Never restate the class map
# or the kHz values outside this file (the ledger home is docs/findings.md ## ceil).
#
# Owner 2026-10-10: Zen 5 = 4.7 GHz, Zen 5c = 3.2 GHz (docs/findings.md ## ceil).
# This module exists because the reader and the writer used to classify policies by
# different rules (topology map vs cpuinfo_max_freq), so a low cpuinfo readback could
# cap Zen 5 at 3.2 GHz with no log line while the reader kept reporting DRIFT.

ECO_CEIL_ZEN5=4700000
ECO_CEIL_ZEN5C=3200000

# Class map: Zen 5 = CPUs 0-3,12-15 (the top half of each Zen 5 / Zen 5c pair).
eco_ceil_is_zen5_cpu() {
  local c=$1
  (( (c >= 0 && c <= 3) || (c >= 12 && c <= 15) ))
}

# Ceiling (kHz) for one cpufreq policy directory. `related_cpus` is the truth;
# `cpuinfo_max_freq` is only a fallback when the topology file is unreadable.
# A policy holding any Zen 5 core takes the Zen 5 ceiling: capping it lower would
# bind Zen 5 cores below their own admitted ceiling (a power cap, not a tail trim —
# docs/judgment.md).
eco_ceil_want_for_policy() {
  local dir=$1 raw cpu imax
  if raw=$(cat "$dir/related_cpus" 2>/dev/null) && [[ -n $raw ]]; then
    for cpu in $raw; do
      if eco_ceil_is_zen5_cpu "$cpu"; then
        printf '%s' "$ECO_CEIL_ZEN5"
        return 0
      fi
    done
    printf '%s' "$ECO_CEIL_ZEN5C"
    return 0
  fi
  imax=$(cat "$dir/cpuinfo_max_freq" 2>/dev/null) || imax=''
  if [[ -n $imax ]] && (( imax > 4400000 )); then
    printf '%s' "$ECO_CEIL_ZEN5"
  else
    printf '%s' "$ECO_CEIL_ZEN5C"
  fi
}
