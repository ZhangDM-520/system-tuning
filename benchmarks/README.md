# System Tuning Benchmarks

Four measurement campaigns run on one laptop, published with their raw data so the results can be
checked and repeated rather than believed.

The machine is an **ASUS Zenbook S 16 (UM5606WA)** — AMD Ryzen AI 9 HX 370, a hybrid Zen 5 / Zen 5c
part with 12 cores and 24 threads — running **CachyOS** on a **`PREEMPT_RT`** kernel with the **BORE**
scheduler. Full specification: [`TEST-BED.md`](TEST-BED.md).

The point of publishing this is not that the conclusions are universal. It is that the **method** is
transferable, and that a lot of the value is in what measurement **refused to approve**. Across 21
tuning levers, roughly half were actively disproved; a scheduler that everybody uses turned out to
carry a 1.9× penalty; and one confidently-recommended setting turned out to make things measurably
worse.

---

## The four studies

| Study | Question | Headline result |
|---|---|---|
| [**01 — Scheduler selection**](studies/01-scheduler-selection/README.md) | Which `sched_ext` CPU scheduler is worth running? | No `sched_ext` scheduler beats the kernel's own BORE on latency. `scx_pandemonium` beats BORE on **power in every under-saturated class** (−11% idle, −35% I/O burst, −30% reclaim energy) while **tying it exactly on throughput**. `scx_cake` carries a **1.9× context-switch penalty** and `scx_cosmos` **cannot attach at all** on `PREEMPT_RT`. |
| [**02 — Boot and power audit**](studies/02-boot-and-power/README.md) | How much of the standard performance checklist is actually true here? | **7 levers adopted, 12 refused by measurement**, for **−5.65 s of boot time** and a large cut in memory-reclaim stalls. Includes a hazard that silently destroys the NVMe APST table. |
| [**03 — Filesystem latency**](studies/03-filesystem-latency/README.md) | Can filesystem latency be cut without spending power? | Mostly **no**. One silently-dead setting was found and made live; `rm -r` is bounded by serial metadata round trips, and a browser launch is only ~70–90 ms of filesystem out of ~530 ms. |
| [**04 — XFS tuning**](studies/04-xfs-tuning/README.md) | Which XFS mount-option and timer-policy changes earn their complexity? | **Nothing adopted.** AB1 filestreams is a Pareto trade (rejected); AB2 phase A failed arm identity and phase B stayed screen-confounded and inconclusive; AB3's boot-cmdline `allocsize=1m` measured no difference and was rolled back. |

Studies 01–03 account for 326 measured scheduler slots and 315 tuning rows, **every one passing its
own identity check**.

## Results worth reading even on different hardware

These transfer because they are about how systems behave, not about this CPU. Each lesson lives in
full at its deep home — the table is the map.

| Lesson | Deep home |
|---|---|
| A setting in a config file is not a setting in effect — read every setting back from where its consumer reads it (`logbsize` asked 256k while the kernel ran 32k; `vm.swappiness = 195` was overwritten with 150 at every boot). | [`studies/03-filesystem-latency/README.md#3-the-one-real-finding-a-setting-that-was-never-in-effect`](studies/03-filesystem-latency/README.md#3-the-one-real-finding-a-setting-that-was-never-in-effect) · [`studies/02-boot-and-power/README.md#2-method`](studies/02-boot-and-power/README.md#2-method) |
| Two daemons writing one sysfs attribute is a silent race — `power-profiles-daemon` and `asusd` both wrote `platform_profile` unconditionally, each correct alone, so the bug is invisible until you look for a second writer. | [`studies/02-boot-and-power/README.md#5-power-profiles-daemon-vs-asusd--a-general-lesson-about-duplicate-writers`](studies/02-boot-and-power/README.md#5-power-profiles-daemon-vs-asusd--a-general-lesson-about-duplicate-writers) |
| Some "tuning" is load-bearing — disabling writeback throttling (`wbt_lat_usec = 0`) made browser launch under write load 30% slower with queue latency 12–24× worse, so the standard advice is worth checking before it is followed. | [`studies/02-boot-and-power/README.md#3-refused-by-measurement`](studies/02-boot-and-power/README.md#3-refused-by-measurement) |
| A flat platform signal can hide a 1.57× clock difference — `cpu_capacity` reads 1024 on all 24 CPUs here, while the real ranking is only visible in `acpi_cppc/highest_perf` and `cpufreq/cpuinfo_max_freq`. | [`TEST-BED.md#11-the-hybrid-split--and-the-trap-in-it`](TEST-BED.md#11-the-hybrid-split--and-the-trap-in-it) |
| A scheduler's shipped default may be a no-op — `scx_bpfland`'s `-m auto` resolves to all 24 CPUs (its domain logic disabled) while `-m performance` resolves to exactly the fast cluster. | [`studies/01-scheduler-selection/README.md#5-arms-versions-and-receipts`](studies/01-scheduler-selection/README.md#5-arms-versions-and-receipts) |
| Watching your own benchmark can cost more than the effect — a display blanking mid-run moves package power by ~13 W, larger than any scheduler or sysctl effect measured in this repository. | [`METHODOLOGY.md#81-display-blanking--13-w`](METHODOLOGY.md#81-display-blanking--13-w) · [`studies/01-scheduler-selection/README.md#11-threats-to-validity`](studies/01-scheduler-selection/README.md#11-threats-to-validity) |
| An adaptive system can act and still not matter — `scx_pandemonium` demonstrably retunes (slice 999 → 1398 → 1114 µs, nine retunes recorded) yet is measurably identical to its own `--no-adaptive` build across six workload classes at n = 11–12. | [`studies/01-scheduler-selection/README.md#9-the-learning-layer-real-observable--and-inert-here`](studies/01-scheduler-selection/README.md#9-the-learning-layer-real-observable--and-inert-here) |
| `systemd-analyze blame` reports activation, not cost — the five `dev-ttyS*.device` entries at ~5.5 s are device units activating at the initramfs→rootfs handoff, and `8250.nr_uarts=0` would have fixed nothing. | [`studies/02-boot-and-power/README.md#6-a-systemd-analyze-blame-misreading-worth-passing-on`](studies/02-boot-and-power/README.md#6-a-systemd-analyze-blame-misreading-worth-passing-on) |

## How to read this repository

```
README.md            you are here
METHODOLOGY.md       the protocol, and the catalogue of ways it has already been fooled
TEST-BED.md          the exact hardware and software — and whether yours resembles it
studies/             01 scheduler selection · 02 boot and power · 03 filesystem latency · 04 XFS tuning
data/                raw rows, traces, logs, probes  →  data/README.md is the dictionary
tools/               the harness  →  tools/README.md has the invocation recipes
```

**Read in that order if you want to judge the work rather than just the results.** The studies assume
[`METHODOLOGY.md`](METHODOLOGY.md); most of the objections a careful reader would raise — why
Mann-Whitney and not a t-test, why medians, why the first repetition is discarded, why the control's
own spread comes first — are answered there.

Studies 01–03 end with what they do **not** claim. The largest open item is stated plainly: the power
advantage of `scx_pandemonium` is established for light, bursty and reclaim-heavy work, and **not**
for sustained load, because the longest saturating phase was 8 seconds and that is nowhere near
thermal equilibrium.

## Reproduce it

The commands are deliberately not repeated here: each study's **Reproduce this** section is its own
reproduction contract — [01 §12](studies/01-scheduler-selection/README.md#12-reproduce-this),
[02 §11](studies/02-boot-and-power/README.md#11-reproduce-this),
[03 §8](studies/03-filesystem-latency/README.md#8-reproduce-this) — and
[study 04's file catalogue](studies/04-xfs-tuning/README.md#files) indexes the XFS campaign rows.
[`tools/README.md`](tools/README.md) documents how to invoke each tool and what recording new
measurements needs (hardware, root, about an hour per pass).

## Caveats

- **One machine, one operator, three days.** Nothing here is a claim about your hardware.
- **Power figures come from RAPL package counters.** The battery cannot be used on this laptop (AC
  with an 80% charge cap, so `power_now` reads zero).
- **The kernel's "stock" scheduler is BORE, not vanilla EEVDF.** Every comparison against "the
  kernel" means against BORE on this specific kernel build.
- **`PREEMPT_RT` × `sched_ext` is thinly tested upstream**, and this repository contains direct
  evidence of that in the form of a scheduler that cannot start.
- **Kernel, tool and scheduler versions matter.** Binary SHA-256 hashes are pinned in study 01 §5 so a
  reader can tell whether they are comparing like with like.

## Licence

Reports and data are licensed **[CC BY 4.0](LICENSE)** — use them, quote them, build on them, with
attribution. The code in [`tools/`](tools/) is **[MIT](LICENSE-MIT)**.

Corrections and replications are the point of publishing this. If a number here does not reproduce on
your machine, that is a more interesting result than agreement.
