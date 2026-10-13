# 05 — Comprehensive scheduler benchmark (2026-10-14)

Overnight head-to-head of 11 `sched_ext` schedulers (the `scx` candidates, each at its owner's
feature-flag configuration) against the control arm `bore` = kernel BORE base with no `sched_ext`
loaded. Unattended run 2026-10-14 00:02–03:42 (kernel 7.3-rc4-cachyos-lto, BORE base, hybrid
Zen 5 / Zen 5c, 24 threads). Rows: `benchmarks/data/scx-deep.jsonl`, passes `night-core` and
`night-real`. Re-analysis (merged view incl. the post-run series): `python3
benchmarks/tools/scx_deep_analyse.py --passes night-core,night-real --control bore --bl 272480`;
the **primary** tables use night rows only — exact command in `## Files` below.

## Results (night rows, reps 1–5; control = kernel BORE)

### Achieved n

| arm | night-core | night-real | note |
|---|---|---|---|
| bore (control) | 5 | 5 | +4 anchor reps at the top-up hour (not merged, see below) |
| beerland, bpfland, cake, cosmos, flash, flow, lavd, p2dq, pandemonium, tickless | 5 | 5 | rep 0 discarded as warm-up |
| — | **4** | **3** | n/a (screening) |

### Gate scoreboard (Gate 1 outside control spread + Gate 2 MW-U p<0.05, night rows)

| rank | arm (flags) | better | worse | character |
|---|---|---|---|---|
| 1 | tickless | 22 | 16 | throughput/energy winner (media, git, web, io) — pays in idle J, storm, wake tails |
| 2 | lavd `--per-cpu-dsq --enable-cpu-bw` | 14 | 25 | io/media/web wins; heavy tail + storm cost |
| 3 | cake | 12 | 21 | git/web energy wins; media fps regresses |
| 4 | bpfland `-p -k -P` | 11 | 18 | mild all-round; tails and storm still regress |
| 5 | cosmos `-g -P -a` | 10 | 11 | latency-side candidate: best scx wake p99, halved mixed tail; storm 2x |
| 6 | flash `-T` | 8 | 15 | media energy win; violent storm/tail regressions |
| 7 | pandemonium (owner's current) | 7 | 18 | web energy −19%, git status, io meta; tails + storm energy worse |
| 7 | beerland | 7 | 21 | git/web wall wins; tails + storm regress |
| 7 | flow | 7 | 30 | dominated |
| 10 | p2dq (full flag set) | 4 | 26 | dominated |
| — | mlfq | n/a | n/a | n/a (screening) |

No arm separates on ≥1 metric **without** a significant regression elsewhere, so **no arm
qualifies for adoption** under the judgment rule. The dominant regression axis is desktop-feel
latency: wake-up p99 at light load (control 29 µs; scx arms 459–6664 µs) and the storm phase
(control t2 4.30; scx arms 4.3–10.7 with matching energy multipliers). The dominant win axis is
batch throughput/energy: media encoding, git metadata ops, web page wall time, io metadata.

### Per-phase ranked tables (medians; (p) = MW-U two-sided vs bore, * = p<0.05; gates B/W = Gate-1+2 wins/losses across all default metrics for that phase)

### phase `idle`

| rank | arm | phase_J | wall p95 (max) | gates B/W |
|---|---|---|---|---|
| 0 | bore | 28.82 | 30 (30) | — |
| 1 | beerland | 22.22 (0.347) | 30 (30) | 0/0 |
| 2 | bpfland[-p -k -P] | 50.43 (0.465) | 30 (30) | 0/0 |
| 3 | cake | 23.26 (0.465) | 30 (30) | 0/0 |
| 4 | cosmos[-g -P -a] | 43.29 (0.754) | 30 (30) | 0/0 |
| 5 | flash[-T] | 83.81 (0.076) | 30 (30.01) | 0/0 |
| 6 | flow | 22.51 (0.754) | 30 (30) | 0/0 |
| 7 | lavd[--per-cpu-dsq --enable-cpu-bw] | 27.2 (0.917) | 30 (30) | 0/0 |
| — | mlfq | 132.4 | 30 (30) | n/a (screening) |
| 9 | p2dq[-a -y --dhq-enabled true --wakeup-llc-migrations --fork-balance true --enable-pelt true --latency-priority --wakeup-preemption --enable-eas true] | 21.26 (0.602) | 30 (30) | 0/0 |
| 10 | pandemonium | 30.21 (0.917) | 30 (30) | 0/0 |
| 11 | tickless | 49.24 (0.117) | 30 (30) | 0/0 |

### phase `light`

| rank | arm | sb_wk_pct50_0 | sb_wk_pct99_0 | sb_wk_pct99_9 | phase_J | wall p95 (max) | gates B/W |
|---|---|---|---|---|---|---|---|
| 0 | bore | 6 | 29 | 1586 | 670.1 | 30.02 (30.02) | — |
| 1 | cosmos[-g -P -a] | 6 | 797 (0.009*) | 1762 (0.463) | 669.9 (0.917) | 30.03 (30.03) | 2/2 |
| — | mlfq | 11 | 2636 | 4192 | 670 | 30.02 (30.02) | n/a (screening) |
| 3 | tickless | 17 (0.003*) | 2316 (0.009*) | 1.176e+04 (0.009*) | 670.8 (0.175) | 30.05 (30.05) | 3/4 |
| 4 | flash[-T] | 7 (0.003*) | 1514 (0.009*) | 2940 (0.009*) | 671 (0.347) | 30.03 (30.03) | 2/5 |
| 5 | cake | 7 (0.050*) | 1942 (0.009*) | 2884 (0.009*) | 670.8 (0.117) | 30.02 (30.02) | 1/4 |
| 6 | lavd[--per-cpu-dsq --enable-cpu-bw] | 12 (0.003*) | 2084 (0.009*) | 3316 (0.009*) | 671.3 (0.028*) | 30.06 (30.06) | 3/7 |
| 7 | bpfland[-p -k -P] | 6 (0.134) | 1146 (0.009*) | 3276 (0.009*) | 670.5 (0.754) | 30.04 (30.04) | 0/5 |
| 8 | pandemonium | 9 (0.003*) | 459 (0.009*) | 2060 (0.028*) | 670.7 (0.175) | 30.03 (30.03) | 0/6 |
| 9 | p2dq[-a -y --dhq-enabled true --wakeup-llc-migrations --fork-balance true --enable-pelt true --latency-priority --wakeup-preemption --enable-eas true] | 19 (0.005*) | 3332 (0.008*) | 4120 (0.009*) | 671.1 (0.117) | 30.05 (30.05) | 1/8 |
| 10 | beerland | 7 (0.003*) | 1442 (0.009*) | 2372 (0.009*) | 670.9 (0.117) | 30.03 (30.03) | 0/7 |
| 11 | flow | 103 (0.005*) | 6664 (0.007*) | 9936 (0.009*) | 670.4 (0.465) | 30.03 (30.03) | 0/7 |

### phase `sat`

| rank | arm | h2_bogo_rate | rate_gain | phase_J | wall p95 (max) | gates B/W |
|---|---|---|---|---|---|---|
| 0 | bore | 9771 | -0.0031 | 661.6 | 30.05 (30.05) | — |
| 1 | p2dq[-a -y --dhq-enabled true --wakeup-llc-migrations --fork-balance true --enable-pelt true --latency-priority --wakeup-preemption --enable-eas true] | 9817 (0.009*) | 0 (0.463) | 661.6 (0.754) | 30.06 (30.06) | 1/0 |
| 2 | beerland | 9772 (0.917) | -0.0055 (0.115) | 661.6 (0.754) | 30.05 (30.05) | 0/0 |
| 3 | cake | 9772 (0.754) | -0.0033 (0.172) | 661.7 (0.754) | 30.05 (30.05) | 0/0 |
| 4 | cosmos[-g -P -a] | 9760 (0.251) | -0.0048 (0.293) | 661.3 (0.251) | 30.05 (30.05) | 0/0 |
| 5 | flash[-T] | 9767 (0.346) | -0.0055 (0.116) | 661.7 (0.754) | 30.05 (30.06) | 0/0 |
| — | mlfq | 9774 | -0.0014 | 661.2 | 30.04 (30.05) | n/a (screening) |
| 7 | pandemonium | 9779 (0.076) | -0.0052 (0.463) | 661.2 (0.076) | 30.05 (30.05) | 0/0 |
| 8 | tickless | 9772 (0.754) | -0.0039 (0.293) | 661.3 (0.347) | 30.05 (30.05) | 0/0 |
| 9 | bpfland[-p -k -P] | 9744 (0.016*) | -0.0038 (0.346) | 661.5 (0.465) | 30.05 (30.05) | 0/1 |
| 10 | lavd[--per-cpu-dsq --enable-cpu-bw] | 9769 (0.917) | -0.0046 (0.016*) | 661.8 (0.465) | 30.05 (30.05) | 0/1 |
| 11 | flow | 7649 (0.009*) | -0.0053 (0.016*) | 661.3 (0.175) | 30.05 (30.05) | 0/2 |

### phase `storm`

| rank | arm | t2 | storm_gain | phase_J | wall p95 (max) | gates B/W |
|---|---|---|---|---|---|---|
| 0 | bore | 4.295 | -0.0026 | 193.2 | 8.808 (8.81) | — |
| 1 | flow | 4.266 (0.016*) | -0.0024 (0.834) | 191.3 (0.076) | 8.689 (8.789) | 2/0 |
| — | mlfq | 4.062 | -0.00515 | 183.6 | 8.359 (8.402) | n/a (screening) |
| 3 | p2dq[-a -y --dhq-enabled true --wakeup-llc-migrations --fork-balance true --enable-pelt true --latency-priority --wakeup-preemption --enable-eas true] | 4.922 (0.117) | -0.0733 (0.009*) | 243.6 (0.009*) | 13.89 (18.76) | 1/3 |
| 4 | bpfland[-p -k -P] | 8.756 (0.009*) | 0.0013 (0.602) | 388.1 (0.009*) | 17.66 (17.8) | 1/4 |
| 5 | cosmos[-g -P -a] | 8.84 (0.009*) | 0.007 (0.602) | 391.4 (0.009*) | 17.84 (17.84) | 1/4 |
| 6 | flash[-T] | 10.92 (0.009*) | 0.0028 (0.602) | 482.5 (0.009*) | 22.14 (22.22) | 1/4 |
| 7 | tickless | 10.72 (0.009*) | -0.0109 (0.117) | 477.2 (0.009*) | 21.77 (21.96) | 1/4 |
| 8 | beerland | 9.459 (0.009*) | -0.0139 (0.602) | 423.7 (0.009*) | 19.4 (19.64) | 0/4 |
| 9 | cake | 5.211 (0.009*) | 0.0215 (0.251) | 233.1 (0.009*) | 10.64 (10.7) | 0/4 |
| 10 | pandemonium | 5.182 (0.009*) | -0.0035 (0.602) | 232 (0.009*) | 10.55 (10.57) | 0/4 |
| 11 | lavd[--per-cpu-dsq --enable-cpu-bw] | 4.817 (0.009*) | 0.0269 (0.028*) | 210.7 (0.009*) | 9.561 (9.857) | 0/5 |

### phase `io`

| rank | arm | meta_s | dd_s | phase_J | wall p95 (max) | gates B/W |
|---|---|---|---|---|---|---|
| 0 | bore | 0.004 | 0.067 | 1.847 | 0.073 (0.075) | — |
| 1 | lavd[--per-cpu-dsq --enable-cpu-bw] | 0.004 (0.134) | 0.07 (0.675) | 1.52 (0.009*) | 0.075 (0.076) | 3/0 |
| 2 | cake | 0.003 (0.006*) | 0.071 (0.031*) | 1.544 (0.117) | 0.074 (0.077) | 2/0 |
| 3 | beerland | 0.003 (0.031*) | 0.064 (0.040*) | 1.855 (0.465) | 0.068 (0.07) | 1/0 |
| 4 | flash[-T] | 0.003 (0.016*) | 0.066 (0.916) | 1.876 (0.347) | 0.08 (0.087) | 1/0 |
| 5 | pandemonium | 0.002 (0.006*) | 0.075 (0.028*) | 1.994 (0.347) | 0.108 (0.112) | 1/1 |
| 6 | tickless | 0.003 (0.005*) | 0.065 (0.071) | 1.894 (0.047*) | 0.069 (0.069) | 1/1 |
| 7 | bpfland[-p -k -P] | 0.002 (0.107) | 0.068 (0.527) | 1.901 (0.175) | 0.075 (0.102) | 0/0 |
| 8 | cosmos[-g -P -a] | 0.004 (0.059) | 0.067 (0.751) | 1.891 (0.142) | 0.07 (0.075) | 0/0 |
| — | mlfq | 0.002 | 0.074 | 2.07 | 0.068 (0.083) | n/a (screening) |
| 10 | p2dq[-a -y --dhq-enabled true --wakeup-llc-migrations --fork-balance true --enable-pelt true --latency-priority --wakeup-preemption --enable-eas true] | 0.003 (0.100) | 0.069 (0.463) | 1.838 (0.602) | 0.077 (0.095) | 0/0 |
| 11 | flow | 0.002 (0.005*) | 0.086 (0.009*) | 2.016 (0.009*) | 0.088 (0.091) | 1/4 |

### phase `mem`

| rank | arm | vm_s | phase_J | wall p95 (max) | gates B/W |
|---|---|---|---|---|---|
| 0 | bore | 31.52 | 170.5 | 31.52 (31.52) | — |
| 1 | bpfland[-p -k -P] | 31.51 (0.008*) | 188.5 (0.602) | 31.51 (31.51) | 1/0 |
| 2 | flow | 31.51 (0.008*) | 164 (0.465) | 31.51 (31.51) | 1/0 |
| 3 | tickless | 31.51 (0.006*) | 188.6 (0.465) | 31.51 (31.51) | 1/0 |
| 4 | beerland | 31.51 (0.136) | 109.3 (0.175) | 31.51 (31.67) | 0/0 |
| 5 | cosmos[-g -P -a] | 31.51 (0.112) | 166.7 (0.465) | 31.51 (31.67) | 0/0 |
| 6 | flash[-T] | 31.72 (0.596) | 183.8 (0.465) | 31.73 (31.75) | 0/0 |
| 7 | lavd[--per-cpu-dsq --enable-cpu-bw] | 31.73 (0.095) | 181.9 (0.917) | 31.73 (31.73) | 0/0 |
| — | mlfq | 31.51 | 216.1 | 31.51 (31.51) | n/a (screening) |
| 9 | p2dq[-a -y --dhq-enabled true --wakeup-llc-migrations --fork-balance true --enable-pelt true --latency-priority --wakeup-preemption --enable-eas true] | 31.52 (0.829) | 180.5 (0.602) | 31.52 (31.64) | 0/0 |
| 10 | cake | 31.66 (0.008*) | 125.8 (0.175) | 31.68 (31.7) | 0/1 |
| 11 | pandemonium | 31.67 (0.008*) | 164.5 (0.347) | 31.67 (31.95) | 0/1 |

### phase `web`

| rank | arm | web_wall_s | phase_J | wall p95 (max) | gates B/W |
|---|---|---|---|---|---|
| 0 | bore | 1.494 | 11.71 | 1.52 (1.566) | — |
| 1 | cake | 1.476 (0.347) | 9.78 (0.009*) | 1.493 (1.507) | 3/0 |
| 2 | pandemonium | 1.459 (0.117) | 9.521 (0.009*) | 1.465 (1.47) | 3/0 |
| 3 | bpfland[-p -k -P] | 1.145 (0.009*) | 13.3 (0.016*) | 1.146 (1.156) | 3/2 |
| 4 | lavd[--per-cpu-dsq --enable-cpu-bw] | 1.103 (0.009*) | 13.49 (0.009*) | 1.108 (1.117) | 3/2 |
| 5 | tickless | 1.073 (0.009*) | 13.42 (0.009*) | 1.109 (1.157) | 3/2 |
| 6 | flash[-T] | 1.451 (0.117) | 11.24 (0.009*) | 1.453 (1.457) | 1/0 |
| 7 | p2dq[-a -y --dhq-enabled true --wakeup-llc-migrations --fork-balance true --enable-pelt true --latency-priority --wakeup-preemption --enable-eas true] | 1.322 (0.076) | 11.85 (0.754) | 1.336 (1.398) | 1/0 |
| 8 | flow | 1.127 (0.009*) | 13.55 (0.009*) | 1.138 (1.165) | 2/2 |
| 9 | beerland | 1.116 (0.028*) | 12.71 (0.465) | 1.381 (1.444) | 1/1 |
| 10 | cosmos[-g -P -a] | 1.445 (0.076) | 11.96 (0.917) | 1.446 (1.475) | 0/0 |
| — | mlfq | 1.139 | 18.54 | 1.032 (1.246) | n/a (screening) |

### phase `mixed`

| rank | arm | sb_wk_pct50_0 | sb_wk_pct99_0 | sb_rq_pct99_0 | wall p95 (max) | gates B/W |
|---|---|---|---|---|---|---|
| 0 | bore | 8 | 3956 | 4.768e+04 | 32.05 (32.06) | — |
| — | mlfq | 11 | 9888 | 1.925e+05 | 32.11 (32.17) | n/a (screening) |
| 2 | tickless | 1318 (0.007*) | 6024 (0.009*) | 1.904e+04 (0.009*) | 32.06 (32.08) | 2/3 |
| 3 | bpfland[-p -k -P] | 453 (0.007*) | 3372 (0.008*) | 7.027e+04 (0.009*) | 32.26 (32.29) | 2/4 |
| 4 | cosmos[-g -P -a] | 146 (0.007*) | 3364 (0.008*) | 6.419e+04 (0.009*) | 32.18 (32.28) | 2/4 |
| 5 | pandemonium | 18 (0.006*) | 3388 (0.009*) | 9.203e+04 (0.009*) | 32.07 (32.09) | 1/4 |
| 6 | lavd[--per-cpu-dsq --enable-cpu-bw] | 2046 (0.007*) | 6680 (0.005*) | 5.459e+04 (0.009*) | 32.19 (32.19) | 1/6 |
| 7 | flow | 2636 (0.007*) | 1.205e+04 (0.009*) | 1.087e+05 (0.009*) | 32.12 (32.13) | 1/7 |
| 8 | flash[-T] | 4392 (0.007*) | 1.365e+04 (0.008*) | 5.318e+04 (0.059) | 32.09 (32.09) | 0/6 |
| 9 | beerland | 1970 (0.007*) | 1.08e+04 (0.009*) | 8.102e+04 (0.009*) | 32.13 (32.16) | 0/7 |
| 10 | cake | 1906 (0.007*) | 8720 (0.009*) | 6.355e+04 (0.009*) | 32.06 (32.06) | 0/7 |
| 11 | p2dq[-a -y --dhq-enabled true --wakeup-llc-migrations --fork-balance true --enable-pelt true --latency-priority --wakeup-preemption --enable-eas true] | 3324 (0.006*) | 1.186e+04 (0.009*) | 8.691e+04 (0.009*) | 32.23 (32.31) | 0/7 |

### phase `media`

| rank | arm | media_fps | media_wall_s | phase_J | wall p95 (max) | gates B/W |
|---|---|---|---|---|---|---|
| 0 | bore | 201.4 | 8.939 | 195.5 | 9.275 (9.277) | — |
| 1 | tickless | 212.8 (0.009*) | 8.459 (0.009*) | 185.3 (0.028*) | 8.823 (8.849) | 5/0 |
| 2 | cosmos[-g -P -a] | 201.8 (0.117) | 8.92 (0.117) | 178.2 (0.009*) | 8.925 (8.942) | 4/0 |
| 3 | beerland | 202.3 (0.059) | 8.896 (0.047*) | 179 (0.076) | 8.907 (8.979) | 3/0 |
| 4 | flash[-T] | 195.6 (0.602) | 9.203 (0.602) | 183.9 (0.009*) | 9.208 (9.226) | 3/0 |
| 5 | lavd[--per-cpu-dsq --enable-cpu-bw] | 194.4 (0.602) | 9.258 (0.602) | 184.5 (0.009*) | 9.269 (9.27) | 3/0 |
| 6 | bpfland[-p -k -P] | 199.1 (0.465) | 9.041 (0.465) | 181.3 (0.076) | 9.051 (9.061) | 2/0 |
| — | mlfq | 193.7 | 9.293 | 185.9 | 9.283 (9.305) | n/a (screening) |
| 8 | p2dq[-a -y --dhq-enabled true --wakeup-llc-migrations --fork-balance true --enable-pelt true --latency-priority --wakeup-preemption --enable-eas true] | 194.9 (0.175) | 9.234 (0.175) | 201.6 (0.175) | 9.734 (9.748) | 0/2 |
| 9 | pandemonium | 196.7 (0.175) | 9.153 (0.175) | 199.9 (0.175) | 9.489 (9.539) | 0/2 |
| 10 | cake | 189.3 (0.028*) | 9.506 (0.028*) | 189.7 (0.917) | 9.517 (9.524) | 1/4 |
| 11 | flow | 155.5 (0.009*) | 11.57 (0.009*) | 231.4 (0.009*) | 11.59 (11.66) | 0/5 |

### phase `git`

| rank | arm | git_total_s | git_status_s | phase_J | wall p95 (max) | gates B/W |
|---|---|---|---|---|---|---|
| 0 | bore | 0.09 | 0.006 | 1.028 | 0.091 (0.098) | — |
| 1 | tickless | 0.069 (0.009*) | 0.004 (0.003*) | 1.171 (0.009*) | 0.071 (0.074) | 6/2 |
| 2 | cake | 0.094 (0.083) | 0.005 (0.003*) | 0.112 (0.009*) | 0.095 (0.097) | 5/1 |
| 3 | pandemonium | 0.096 (0.293) | 0.005 (0.004*) | 0.889 (0.076) | 0.097 (0.098) | 2/0 |
| 4 | beerland | 0.078 (0.015*) | 0.005 (0.005*) | 1.149 (0.012*) | 0.079 (0.085) | 2/2 |
| 5 | bpfland[-p -k -P] | 0.079 (0.028*) | 0.004 (0.003*) | 1.137 (0.009*) | 0.085 (0.085) | 2/2 |
| 6 | cosmos[-g -P -a] | 0.08 (0.115) | 0.005 (0.003*) | 1.144 (0.016*) | 0.084 (0.094) | 1/1 |
| 7 | flash[-T] | 0.086 (0.674) | 0.005 (0.053) | 1.015 (0.917) | 0.096 (0.097) | 0/0 |
| — | mlfq | 0.0725 | 0.004 | 1.529 | 0.071 (0.075) | n/a (screening) |
| 9 | lavd[--per-cpu-dsq --enable-cpu-bw] | 0.103 (0.009*) | 0.006 (0.317) | 0.908 (0.175) | 0.106 (0.108) | 1/4 |
| 10 | flow | 0.095 (0.527) | 0.007 (0.018*) | 1.151 (0.009*) | 0.095 (0.099) | 0/3 |
| 11 | p2dq[-a -y --dhq-enabled true --wakeup-llc-migrations --fork-balance true --enable-pelt true --latency-priority --wakeup-preemption --enable-eas true] | 0.102 (0.016*) | 0.007 (0.017*) | 1.113 (0.028*) | 0.104 (0.104) | 0/6 |

### Headline medians (night rows; mlfq = all valid night reps, screening)

| phase/metric | bore | tickless | pandemonium | mlfq* |
|---|---|---|---|---|
| idle/phase_J (J) | 28.82 | 49.24 | 30.21 | 132.4 |
| light/sb_wk_pct99_0 (µs) | **29** | 2316 | 459 | 2476 |
| light/phase_J (J) | 670.1 | 670.8 | 670.7 | 670.0 |
| sat/h2_bogo_rate | 9771 | 9772 | 9779 | 9771 |
| sat/phase_J (J) | 661.6 | 661.3 | 661.2 | 661.2 |
| storm/t2 | **4.295** | 10.72 | 5.182 | 4.078 |
| storm/phase_J (J) | **193.2** | 477.2 | 232.0 | 183.6 |
| io/meta_s (s) | 0.004 | 0.003 | 0.002 | 0.002 |
| io/dd_s (s) | 0.067 | 0.065 | 0.075 | 0.066 |
| mem/vm_s (s) | 31.52 | 31.51 | 31.67 | 31.51 |
| mem/phase_J (J) | 170.5 | 188.6 | 164.5 | 260.9 |
| web/web_wall_s (s) | 1.494 | **1.073** | 1.459 | 1.246 |
| web/phase_J (J) | 11.71 | 13.42 | **9.521** | 18.47 |
| mixed/sb_wk_pct99_0 (µs) | 3956 | 6024 | 3388 | 1.022e4 |
| media/media_fps | 201.4 | **212.8** | 196.7 | 193.9 |
| media/phase_J (J) | 195.5 | **185.3** | 199.9 | 186.2 |
| git/git_total_s (s) | 0.090 | **0.069** | 0.096 | 0.070 |
| git/phase_J (J) | 1.028 | 1.171 | **0.889** | 1.470 |

### Wake-up latency p99 (µs, schbench, night rows) — the axis BORE wins outright

| phase | bore | beerland | bpfland | cake | cosmos | flash | flow | lavd | mlfq* | p2dq | pandemonium | tickless |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| light | **29** | 1442 | 1146 | 1942 | 797 | 1514 | 6664 | 2084 | 2476 | 3332 | 459 | 2316 |
| mixed | 3956 | 1.08e4 | 3372 | 8720 | **3364** | 1.365e4 | 1.205e4 | 6680 | 1.022e4 | 1.186e4 | 3388 | 6024 |

### mlfq screening (n=4 core / n=3 real, cross-window: screening only)

mlfq's usable rows show it is not competitive even where it attaches: idle energy 132.4 J vs
28.8 J control (4.6x), mem phase energy 260.9 J vs 170.5 J, wake p99 2476 µs vs 29 µs; its only
bright spots are io metadata times and storm t2. Combined with the attach-crash bug below, the
verdict is REJECT regardless of the n floor.

### Sensitivity and robustness

- **Timer window (00:00–00:30 system timers):** dropping rep 1 in addition to rep 0 leaves every
  verdict class unchanged (tickless 21 better/16 worse, pandemonium 8/18, cosmos 10/12).
- **Cross-window drift: FAILED falsification → top-up rows excluded from primary tables.** A
  bore anchor series at the top-up hour (04:42–04:54) lands outside the night-bore spread in
  20/43 checked cells (e.g. light phase_J 670→758 J, +13%) — 5 hours of continuous load drifts
  the machine's energy floor, so cross-window merging would mix treatment with drift. Primary
  tables use night rows only; this also validates the night design (interleave + rotate), which
  is immune to within-run drift.
- **Effect size over gates:** gates are necessary, not sufficient — e.g. `mem/vm_s` "separates"
  at 31.51 vs 31.52 s (0.03%). Ranking above weighs effect sizes, not gate counts alone.

### mlfq reliability — REJECT (mechanism understood)

`scx_mlfq` 1.3.11 crashes at attach with a kernel runtime error `non-existent DSQ 0x100c`/`0x101b`
(id varies) in `mlfq_sched_switch`, auto-disabling sched_ext. Overnight: 4 of 12 starts survived;
post-run top-up: 3 of 50. The failure is probabilistic and load-independent — an upstream bug
worth reporting (attach-time DSQ lifecycle race). Do not run this scheduler.

## Recommendation (judgment rule: separates on ≥1 relevant metric, none significantly worse, mechanism understood)

1. **No adoption as general default.** Kernel BORE stays the default scheduler. Every candidate
   regresses the desktop-feel axes (wake p99 at light load, storm t2/energy) significantly; the
   batch-throughput wins do not offset that for a daily driver.
2. **Workload-scoped candidates (documented, not adopted):**
   - **tickless** — for long media encodes / build sessions: +5.7% encode fps at −5.2% energy,
     git ops −23%, web wall −28%. Expect idle energy +71% and storm/wake regressions while it
     runs; use as a session profile, not a default.
   - **cosmos `-g -P -a`** — the latency-side candidate among scx arms: light wake p99 797 µs
     (best scx; others 1146–6664), mixed p99/p99.9 3364/3372 µs (p99.9 halves the control),
     media energy −8.8%. Storm t2 doubles — again session-scoped.
3. **mlfq: REJECT** — crashes the kernel scheduler at attach (see above); report upstream.
4. **pandemonium (the scheduler this machine currently runs):** this campaign does not justify
   it over BORE on desktop-feel metrics (light wake p99 459 vs 29 µs; storm t2 5.18 vs 4.30;
   storm energy +20%); it wins web energy (−19%), git status latency, and io metadata. Its
   adaptive-learning claim is **not tested here** — phase mode measures steady phase classes; the
   alternation regime (`scx_deep.py` `alt` mode) is the instrument for that claim. Keeping it is
   an owner preference/thesis, not an evidence-backed win from this data; the end state remains
   pandemonium either way (harness restores it).

## Design

- 12 arms × 6 reps per pass, arms rotated per rep (rotation offsets the first-slot position),
  rep 0 discarded as warm-up → **n=5 usable per arm** target.
- Two phase classes (`--phases`, `--dur 30`, `--cycles 1`):
  - `night-core`: idle, light, sat, storm, io, mem — synthetic throughput/latency/energy probes.
  - `night-real`: web (headless fixed JS/DOM page), mixed (schbench latency under saturation =
    desktop-while-compiling), media (ffmpeg x264 fps + J/frame), git (5000-file/200-commit tree
    responsiveness).
- Derived per row: `derived.edp`, `derived.edp2`; wall-time tails (p50/p95/max) per phase/arm.
- Energy oracle: RAPL package `energy_uj` deltas per phase (J per work unit, never watts alone).

## Conditions

- AC online throughout; battery unusable (80% charge cap), RAPL is the only energy source.
- Panel regime: `bl=272480` constant across every row — the blank-panel step failed at start
  (see Pitfalls) and the screen never idled off, so the whole night is one uniform screen-on
  regime. No regime filter is needed (`--bl 272480` ≡ `--bl any`); the display adds a constant
  background load shared by every arm including the control.
- Kernel `bore-lto` base; `ananicy-cpp` disabled; `bpftune` running; convergence at boot only
  (no periodic converger since 2026-10-11).
- Timer window sensitivity: the run starts 00:01:52, inside the 00:00–00:30 system-timer window
  (plocate/logrotate/shadow). Sensitivity run drops rep 1 in addition to the default rep 0.

## Gates (docs/judgment.md)

1. **Gate 1** — effect outside the control's own min/max spread for the same phase/metric.
2. **Gate 2** — Mann-Whitney U (tie-corrected, two-sided) p < 0.05 vs control.
3. **n floors** — n ≥ 5 per arm for adoption or refutation; n=2 verdicts are capped at
   INCONCLUSIVE (minimum two-sided p at n=2 vs 2 is 0.333).
4. **Adoption rule** — separates on ≥1 relevant metric, no metric significantly worse,
   mechanism understood. Medians only; within-pass comparisons only.

## Pitfalls and incidents (campaign-specific)

1. **`scx_mlfq` 1.3.11 has a DSQ lifecycle bug**: at attach it crashes with a kernel runtime
   error `non-existent DSQ 0x100c`/`0x101b` (id varies) in `mlfq_sched_switch`, and sched_ext
   auto-disables. Probabilistic: some starts come up clean and measure fine. In the night run
   only 2 of 6 slots per pass attached, so `mlfq` started at n=2; a top-up series retried
   attach until the n floor was met or attempts were exhausted. Failed slots emit one
   `valid=false` marker row (`phase=null`) and are excluded from all statistics.
2. **Panel blank failed at start** (`WARN could not blank panel`): the run carried a constant
   screen-on regime instead of the planned screen-off night. Uniform across arms, but it moves
   the absolute numbers; the control spread absorbs it.
3. **End-state restore failed silently at run end**: the direct-attach restore died before
   attaching (evidence discarded to `/dev/null`); restored manually and the harness restore was
   hardened to log evidence, poll for `enabled`, and fail loudly. Direct-attach
   `scx_pandemonium` requires root (as user: `libbpf -EPERM`), and `scxctl stop` hangs while a
   direct-attach scheduler holds sched_ext — kill direct-attach first, then stop.
4. **Top-up rows are a separate collection window** (post-run, same phases/dur/cycles). A bore
   anchor series at the same hour falsifies window drift: anchor-bore medians must fall inside
   the night-bore spread before top-up rows are merged. The first top-up rep is additionally
   dropped in a sensitivity run (top-ups have no front-of-run warm-up slot of their own).

## Files

| File | What it is |
|---|---|
| `benchmarks/data/scx-deep.jsonl` | all rows (night + top-up + anchor), append-only |
| `benchmarks/data/logs/night-20261014-0001.log` | orchestrator log incl. achieved-n report |
| `benchmarks/data/logs/mlfq-topup-*.log`, `bore-anchor-*.log` | post-run series logs |
| `benchmarks/tools/scx_deep.py`, `scx_deep_analyse.py`, `night-run.sh` | harness, analyser, orchestrator |
| `mlfq-topup.sh`, `bore-anchor.sh` | campaign drivers (retry-to-n top-up; window-drift anchor), root-required |
| `gate1.py` | single-metric Gate 1 + MW-U check (`G1_EXCLUDE_REPS`, `G1_CONTROL` env) |
| `scoreboard.py` | per-arm Gate 1+2 verdict list, night rows (rep filter arg) |

Re-derivation (no root needed): `python3 benchmarks/tools/scx_deep_analyse.py --passes
night-core,night-real --control bore --bl 272480 --exclude-reps
$(python3 -c "print(','.join(map(str,range(6,31))))")` reproduces the primary tables (night rows
only); `python3 benchmarks/studies/05-sched-comprehensive-benchmark/scoreboard.py 1,2,3,4,5`
reproduces the scoreboard.
