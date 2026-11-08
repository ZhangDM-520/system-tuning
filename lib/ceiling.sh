# ceiling.sh: load the ONE ceiling rule into the CLI.
#
# The rule's canonical copy is state/owned/usr/local/lib/eco-ceil.sh (the intent for
# /usr/local/lib/eco-ceil.sh, which eco-power.sh sources at runtime). The CLI loads
# that same file, so the reader and the writer cannot drift apart: one module, one
# class map, one ceiling per class.
_eco_ceil_src="$ECO_HOME/state/owned/usr/local/lib/eco-ceil.sh"
if [[ ! -r $_eco_ceil_src ]]; then
  printf 'eco: missing ceiling rule: %s\n' "$_eco_ceil_src" >&2
  exit 2
fi
# shellcheck source=/dev/null
. "$_eco_ceil_src"
