# RETIRED — this tree is no longer the intent for this host

2026-11-10: the host was flipped from the shell `eco` engine to the native `genarch` engine
(`~/Projects/genarch-settings`). The intent now lives there:

- package intent: `/usr/lib/genarch/{intent.toml,sysctl.toml,ryzenadj.toml,passes.toml,managed/,mirror/}`
- machine overrides: `/etc/genarch/`
- ownership record: `/var/lib/genarch/manifest.toml`

`eco-*` units are disabled and their live files were removed by the genarch cutover (every one has
a dated `.bak-20261110` pre-image beside it). The shell files stay in this tree — and in git — on
purpose: they are the rollback artifact and the parity reference for the native engine.

This file is the retirement marker. `./eco apply` refuses while it exists (exit 2), because
re-deploying this tree would restore the shell engine next to `genarch` and give the host two
writers for the same files. Read-only `./eco report` and `./eco apply --dry-run` still work, and
they will show drift — that drift is the retirement, not a fault. Gate: `tests/run` case30.

Rollback: `docs/CUTOVER.md` in `genarch-settings` (`## Rollback`) — it re-enables the shell units
and must remove this marker first (`rm state/RETIRED.md`); a `git checkout` of the pre-retirement
tag restores a tree without it.
