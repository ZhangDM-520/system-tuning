# Measurement

When to read: before claiming any tuning saved anything. The doctrine (work per joule) makes
measurement mandatory for claims and optional for maintenance.

## The honest metric

**Work produced per joule.** Wall-plug or RAPL watts alone say nothing: a throttle that cuts watts
20% and throughput 30% is a regression. The two honest measurements are:

1. Idle draw: watts at screen-on idle and screen-off idle (the floor).
2. Work efficiency: throughput of a fixed task divided by package energy for that task
   (joules per operation is the inverse; lower is better).

## The harness

`~/Workspace/power-lab/` (kept there as a scratch lab; this repo records its interface only):

| Tool | Purpose |
|------|---------|
| `rapl-watts.sh` | sample RAPL package power over a window (idle floor, quick checks) |
| `measure-power.sh` | scripted load + RAPL integration -> joules for a fixed unit of work |
| `bench-perf.sh` | throughput runs for the denominator (stress-ng/hyperfine based) |
| `results/` | dated measurement records |

RAPL domain: package energy on the Strix Point APU (`powercap/intel-rapl` style counters exposed
by the kernel; verify the domain path before trusting numbers). Battery state, screen state, and
AC state must be recorded with every measurement: they change the firmware floor (quirks#stapm).

## Baselines (2026-09-23, this machine)

- Idle floor: ~3.7 W RAPL package (screen-on, converged stack).
- Light load: ~12.1 W RAPL.
- These are anchors for regression checks, not targets. Never "optimize" toward a watt number.

## Rules

1. Record conditions with every number: AC state, battery %, screen on/off, scheduler, EPP,
   whether the convergence timer had just fired (it can perturb a short window).
2. Never benchmark while an undervolt/CO stability campaign is running: the benchmark load
   interferes with the stability test and the numbers lie twice.
3. A change ships on mechanism + judgment; it *stays* only if a measurement confirms it or the
   owner rules it settled. Decisions.md entries record which of the two applies.
4. Silent-failure checks (SMU readback, verify runs) are not measurements and must not be
   reported as savings (quirks#stapm: the firmware lies in specific documented ways).
5. When measuring work efficiency, fix the work: same input, same warm-up, same core placement
   expectations (the compacting scheduler deliberately parks work on few cores).
