# Kernel Attribution: 2026-10-17 Boot `dynamic`-EPP D-State Wedge (Lock-Order Inversion)

- **Date:** 2026-10-17
- **Kernel:** `7.3.0-rc6-1-cachyos-bore-lto` (CachyOS build of mainline 7.3-rc6 + BORE scheduler patch + LTO)
- **Scope:** primary sources only — upstream kernel trees (torvalds/linux @ master 2026-10-17, GitHub API for history), CachyOS/kernel-patches, on-machine `vmlinux`, MARC (linux-kernel archive), kernel bugzilla REST. lore.kernel.org was unreachable from this host (anti-bot gate); MARC and commit-message `Link:` URLs were used instead.
- **Companion evidence:** `docs/research/2026-10-17-boot-epp-deadlock-report.md` (boot journals + first vmlinux pass). This report corrects that report's proposed lock cycle (see §2.2) while confirming its Order A.

---

## 1. Verdict

**Kernel-blamed: YES — but the owning component differs from the forensic report's hypothesis.** The deadlock is a lock-order inversion inside the **platform_profile core (`drivers/acpi/platform_profile.c`)**: `platform_profile_register()`/`platform_profile_remove()` hold the global `profile_lock` mutex across `device_register()`/`device_unregister()` and `sysfs_update_group()`, and those operations remove sysfs attributes and **wait for their in-flight sysfs callbacks to drain** — while the sysfs callbacks (`platform_profile_show/store`, `profile_show/store`) acquire `profile_lock` **while holding the kernfs active reference**. Classic ABBA: registration/removal holds `profile_lock` and waits for active refs; a concurrent reader/writer of `/sys/firmware/acpi/platform_profile` (or `/sys/class/platform-profile/*/profile`) holds an active ref and waits for `profile_lock`. The mainline amd-pstate "dynamic EPP" feature (merged for 7.2/7.3, commits `e30ca6dd5345`, `798c47593cca`, `b7294b627598`) is the in-tree path that triggers register/remove from a cpufreq sysfs store **while `policy->rwsem` is held**, which is why every cpufreq sysfs consumer wedges in `D` state behind the frozen store. The specific ABBA proposed by the sibling forensic report — `profile_lock → policy->rwsem` via `amd_pstate_profile_set` — is **refuted** by both mainline source and the local `vmlinux` (§2.2); the real inversion is `profile_lock` ↔ kernfs active-ref/drain lifetime, and it was independently identified and patched upstream by Daniel Lezcano on **2026-10-14** (`[PATCH v1 1/4] platform profile: Separate handler locking from sysfs lifetime`), three days before these boots — not yet merged (§5). No userspace arrangement can remove this inversion; it can only shrink the race window.

---

## 2. The two lock orders

### 2.1 Order A — `policy->rwsem` → `profile_lock` (VERIFIED, as claimed)

Writing `dynamic` to `policyX/energy_performance_preference`:

1. **cpufreq core takes `down_write(&policy->rwsem)` before the driver store callback.**
   - `torvalds/linux:drivers/cpufreq/cpufreq.c:976-1007` — kobj `show()`/`store()` for policy attributes; `store()` at `:992-1001` does `guard(cpufreq_policy_write)(policy)` then `data->store(policy, buf, count)`.
   - `torvalds/linux:include/linux/cpufreq.h:175-179` — `DEFINE_GUARD(cpufreq_policy_write, struct cpufreq_policy *, down_write(&_T->rwsem), up_write(&_T->rwsem))`.
   - URLs: https://github.com/torvalds/linux/blob/master/drivers/cpufreq/cpufreq.c#L976-L1007 , https://github.com/torvalds/linux/blob/master/include/linux/cpufreq.h#L175-L179
2. **amd-pstate's `store_energy_performance_preference` performs the `dynamic` transition while still under that rwsem.**
   - `torvalds/linux:drivers/cpufreq/amd-pstate.c:1410-1473` (`store_energy_performance_preference`, exported via `EXPORT_SYMBOL_FOR_PSTATE_UT`): `EPP_INDEX_DYNAMIC` branch at `:1426-1445` hardcodes `cpudata->current_profile = PLATFORM_PROFILE_BALANCED;` (`:1439`) and calls `amd_pstate_set_dynamic_epp(policy)` (`:1440`). The dynamic→static path calls `amd_pstate_clear_dynamic_epp(policy)` (`:1455-1463`).
   - `torvalds/linux:drivers/cpufreq/amd-pstate.c:1278-1326` (`amd_pstate_set_dynamic_epp`): `kasprintf(GFP_KERNEL, "amd-pstate-epp-cpu%d", ...)` (`:1294`), `platform_profile_register(get_cpu_device(policy->cpu), cpudata->profile_name, ..., &amd_pstate_profile_ops)` (`:1298-1301`), `power_supply_reg_notifier(&cpudata->power_nb)` (`:1309-1310`, inline → `blocking_notifier_chain_register(&power_supply_notifier, ...)`).
   - `torvalds/linux:drivers/cpufreq/amd-pstate.c:1263-1276` (`amd_pstate_clear_dynamic_epp`): `platform_profile_remove(cpudata->ppdev)` (`:1270`).
3. **`platform_profile_register` takes `profile_lock` and, under it, does blocking device/sysfs work.**
   - `torvalds/linux:drivers/acpi/platform_profile.c:550-625`: `guard(mutex)(&profile_lock)` at `:586`; `ida_alloc_range` (`:589`), `device_register(ppdev)` (`:602`), `sysfs_notify(acpi_kobj, NULL, "platform_profile")` (`:608`), `sysfs_update_group(acpi_kobj, &platform_profile_group)` (`:610`). `platform_profile_remove` (`:627-647`) repeats the pattern: `guard(mutex)(&profile_lock)` (`:639`), `device_unregister` (immediately after `:640`), `sysfs_notify` (`:644`), `sysfs_update_group` (`:645`).
   - `static DEFINE_MUTEX(profile_lock)` — `drivers/acpi/platform_profile.c:17`.
   - URL: https://github.com/torvalds/linux/blob/master/drivers/acpi/platform_profile.c#L550-L647

**Local `vmlinux` mapping** (`/usr/lib/modules/7.3.0-rc6-1-cachyos-bore-lto/build/vmlinux`, read-only `nm`/`objdump`/`strings`):

| Construct | Local evidence |
|---|---|
| `store_energy_performance_preference` | `0xffffffff823de900`; `movl $0x3,0x110(%r12)` @ `0xffffffff823de9bd` (`current_profile = PLATFORM_PROFILE_BALANCED`); calls `power_supply_is_system_supplied` @ `0xffffffff823de9f7`, `platform_profile_remove` @ `0xffffffff823deab6`, `kasprintf` @ `0xffffffff823deb49`, `get_cpu_device` @ `0xffffffff823deb63`, `platform_profile_register` @ `0xffffffff823deb81`, `blocking_notifier_chain_register` @ `0xffffffff823debc8`, `blocking_notifier_chain_unregister` @ `0xffffffff823deaa5`, `__SCT__amd_pstate_set_epp` @ `0xffffffff823deae5`/`0xffffffff823deb30`/`0xffffffff823dec35`. `amd_pstate_set_dynamic_epp`/`clear_dynamic_epp` are LTO-inlined into the store, matching the source call sequence 1:1. |
| `platform_profile_register` | `0xffffffff8209ed40`: `mutex_lock` @ `0xffffffff8209ee1b` (= `profile_lock`, `.bss` `profile_lock` @ `0xffffffff8487c9b0`), `ida_alloc_range` @ `0xffffffff8209ee33`, `device_add` @ `0xffffffff8209eea4`, `sysfs_notify` @ `0xffffffff8209eefb`, **`internal_create_group` @ `0xffffffff8209ef13`** (= `sysfs_update_group()`, inlined), `mutex_unlock` @ `0xffffffff8209ef4e`. |
| `platform_profile_remove` | `0xffffffff8209efe0`: `mutex_lock` @ `0xffffffff8209f00e`, `device_unregister` @ `0xffffffff8209f028`, `sysfs_notify` @ `0xffffffff8209f03d`, `internal_create_group` @ `0xffffffff8209f055`. |
| `amd-pstate-epp-cpu%d` format string | present in `vmlinux` (`.rodata`), tying the local binary to the `kasprintf` hunk of commit `798c47593cca`. |

### 2.2 Order B — the claimed `profile_lock → policy->rwsem` is REFUTED; the real inversion is `profile_lock` ↔ kernfs active-ref/drain

**Refutation of the sibling report's Order B (checked in both mainline source and the local binary):**

- `amd_pstate_profile_set` (`torvalds/linux:drivers/cpufreq/amd-pstate.c:1232-1256`) — the `platform_profile_ops.profile_set` callback invoked under `profile_lock` — does exactly: `cpufreq_cpu_get(cpudata->cpu)` (`:1236`), map profile→EPP, `amd_pstate_set_epp(policy, epp)` (`:1248`), `cpudata->current_profile = profile`. It contains **no** `down_write`/`down_read`/`lock_policy_rwsem_*`.
- `amd_pstate_set_epp` is a static-call trampoline to `msr_set_epp`/`shmem_set_epp` (`amd-pstate.c:329-334`) — MSR write or `cppc_set_epp`; no `policy->rwsem`.
- `cpufreq_cpu_get` does not take `policy->rwsem`: mainline `cpufreq.c:195-227` (kobj ref / policy usage ref only); local `vmlinux` `cpufreq_cpu_get` @ `0xffffffff823d48e0` takes only `_raw_read_lock_irqsave` on the `cpufreq_driver_lock` rwlock (`0xffffffff848901e8`) + `kobject_get` @ `0xffffffff823d4932` — no rwsem op anywhere in the function.
- Local `amd_pstate_profile_set` @ `0xffffffff823df6c0` (full disassembly, 0x110 bytes): calls `cpufreq_cpu_get` @ `0xffffffff823df6d8`, `power_supply_is_system_supplied` @ `0xffffffff823df6fa` (inlined `amd_pstate_get_balanced_epp`), `__SCT__amd_pstate_set_epp` @ `0xffffffff823df723`, `kobject_put` @ `0xffffffff823df743`; the only state store is `mov %ebp,0x110(%r15)` @ `0xffffffff823df732` (`current_profile = profile`). **No `lock cmpxchg`, no `rwsem_*slowpath` call, no lockdep hook** — the function acquires zero locks.
- Conclusion: under `profile_lock`, the amd-pstate ops path takes no `policy->rwsem`. The claimed ABBA (`policy->rwsem ↔ profile_lock`) does not exist in this code, on either tree.

**The inversion that IS present (both trees), and that upstream is now fixing:**

- The legacy sysfs file `/sys/firmware/acpi/platform_profile` is `attr_platform_profile` in `platform_profile_group` on `acpi_kobj` (`drivers/acpi/platform_profile.c:444-472`, created at `:700`). Its handlers `platform_profile_show`/`platform_profile_store` (`:379-441`) acquire `profile_lock` (`scoped_cond_guard(mutex_intr, ..., &profile_lock)` at `:386`/`:425`) **while kernfs holds their active reference** for the duration of the callback (`fs/kernfs/file.c:304-349`: `kernfs_fop_write_iter` → `kernfs_get_active_of()` at `:337`, `kernfs_put_active_of()` at `:349`). Per-device class files `profile_show`/`profile_store` (`:171-221`, guard at `:185`/`:213`, `DEVICE_ATTR_RW(profile)` at `:223`) behave identically.
- `sysfs_update_group()` re-creates the group by **removing and re-adding each attribute**: `fs/sysfs/group.c:295-297` → `internal_create_group(kobj, 1, grp)`; `create_files()` in update mode calls `kernfs_remove_by_name(parent, (*attr)->name)` (`fs/sysfs/group.c:48-66, 98-99`).
- `kernfs_remove_by_name` → `__kernfs_remove` → `kernfs_drain()` **waits for all active references to finish**: `fs/kernfs/dir.c:508-538`, `wait_event(root->deactivate_waitq, atomic_read(&kn->active) == KN_DEACTIVATED_BIAS)` at `:537-538`; invoked from `__kernfs_remove` at `:1499-1500`.
- Therefore:

  ```
  Thread A (EPP store → dynamic transition)        Thread B (any reader/writer of
                                                   /sys/firmware/acpi/platform_profile)
  down_write(&policy->rwsem)          [cpufreq.c:1001]
  mutex_lock(&profile_lock)           [platform_profile.c:586]
  device_register / sysfs_notify
  sysfs_update_group(acpi_kobj)       [platform_profile.c:610]
    → kernfs_remove_by_name("platform_profile")
    → kernfs_drain: wait for B's active ref  ─────┐
                                                  │
                                        kernfs_get_active (write_iter)   [kernfs/file.c:337]
                                        platform_profile_store
                                        mutex_lock(&profile_lock)  ← blocked on A ──┐
                                                  │                                │
                                                  └──── cycle: A waits for B, B waits for A
  ```

- The same cycle exists on teardown: `platform_profile_remove` (`:639-645`) holds `profile_lock` across `device_unregister` (which drains the per-device `profile` file) and `sysfs_update_group` (which drains the legacy file).
- Because Thread A never returns, `policy->rwsem` stays write-held forever; every cpufreq sysfs user (tlp, scxtop, further `energy_performance_preference` writes, `reboot` paths touching these sysfs nodes) piles up in `TASK_UNINTERRUPTIBLE` — exactly the journal signature of boots `-3/-2/-1` (sibling report §2), including SIGKILL immunity.

### 2.3 Why the sibling report's cycle was plausible but wrong

The sibling report inferred `amd_pstate_profile_set` "takes `policy->rwsem`" from the function name and from Order A's shape. Source and binary both show it doesn't (§2.2). Its inner instruction addresses also drift from the binary (`devm_kasprintf` @ `0xffffffff823deadf` / `platform_profile_register` @ `0xffffffff823deb0b` / `movl $0x3` @ `0xffffffff823deab9` are not what `objdump` shows; the real calls are `kasprintf` (plain, paired with `kfree` in `clear_dynamic_epp`) @ `0xffffffff823deb49`, `platform_profile_register` @ `0xffffffff823deb81`, `movl $0x3` @ `0xffffffff823de9bd`). The call *sequence* it described is correct; the lock analysis is not. The repo mitigation commit `735d392` (`system-tuning` git history) repeats the same ABBA claim in its message; the mitigation remains useful (§4) but its stated mechanism should be updated to §2.2.

---

## 3. Version scope

**Everything implicated is mainline, not a CachyOS patch.**

- `e30ca6dd5345` ("cpufreq/amd-pstate: Add dynamic energy performance preference", Mario Limonciello, 2026-03-29) — introduced dynamic EPP + `power_supply_reg_notifier` under the EPP store. https://github.com/torvalds/linux/commit/e30ca6dd5345c5b8ba05f346a8e81105352fe571
- `798c47593cca` ("cpufreq/amd-pstate: Add support for platform profile class", 2026-03-29) — added `amd_pstate_profile_{probe,get,set}`, `amd_pstate_profile_ops`, per-CPU `platform_profile_register(get_cpu_device(policy->cpu), "amd-pstate-epp-cpu%d", ...)` inside `amd_pstate_set_dynamic_epp()`, and `platform_profile_remove()` in `amd_pstate_clear_dynamic_epp()`. https://github.com/torvalds/linux/commit/798c47593ccae7dd36c033e557f3f364a2056b9e
- `9228169d2ae0` ("Grab `amd_pstate_driver_lock` when toggling dynamic_epp", K Prateek Nayak, 2026-05-08) — upstream fix for a *different* hang in the same feature (concurrent `amd_pstate/status` + `dynamic_epp` writes, `static_key_disable_cpuslocked()` WARN + system hang). https://github.com/torvalds/linux/commit/9228169d2ae055ed09a163887fc59a710a5eb73b ; thread linked from the commit: https://lore.kernel.org/r/20260508051748.10484-2-kprateek.nayak@amd.com
- `b7294b627598` ("cpufreq/amd-pstate: Add dynamic EPP as an `energy_performance_preference` mode", 2026-07-27) — converted the global toggle into the per-policy `dynamic` EPP string; `store_energy_performance_preference` gained the `EPP_INDEX_DYNAMIC` branch (`current_profile = PLATFORM_PROFILE_BALANCED; amd_pstate_set_dynamic_epp()`) and dynamic→static cleanup. This is the exact code the boot wedge exercises. https://github.com/torvalds/linux/commit/b7294b627598d2c709715be422c0b77e491d82f1 ; thread: https://lore.kernel.org/r/20260727072056.1248-5-kprateek.nayak@amd.com (in `Link:` of the commit). Follow-up `32692fcf61ed` removed the old `dynamic_epp` sysfs file.
- Feature lineage merged via `pm-cpufreq` pulls `amd-pstate-v7.1-*` / `amd-pstate-v7.3-*` (merge commits `5cdfedf68e6e`, `7f464fb22975`, `eb49643e66e0`); local kernel is 7.3.0-rc6 and contains the post-`b7294b627598` code shape (verified in `vmlinux` §2.1).
- **CachyOS patch scope (checked):** `CachyOS/kernel-patches` dir `7.3/` contains only `misc/` (`0001-acpi-call.patch`, `0001-aufs-7.3-merge-v20260914.patch`, `dkms-clang.patch`, `nvidia/`) and `sched/` (`0001-bore-cachy.patch`). `grep` of `0001-bore-cachy.patch` and `0001-acpi-call.patch` for `amd-pstate|platform_profile|cpufreq|drivers/acpi` → zero hits. Repo-wide code search for `amd-pstate` in `CachyOS/kernel-patches` hits only `5.18/`–`6.15/` era patches. So the amd-pstate/platform_profile code in `7.3.0-rc6-1-cachyos-bore-lto` is stock mainline; "bore-lto" = BORE scheduler + LTO build only.
- **Verified on the local kernel vs from upstream trees:** lock-taking behavior of `store_energy_performance_preference`, `amd_pstate_profile_set`, `cpufreq_cpu_get`, `platform_profile_register/remove`, `platform_profile_show`, `profile_store` was verified directly in local `vmlinux` disassembly (§2, §7); source line numbers are from torvalds/linux master fetched 2026-10-17. Caveats: master may be 7.4-rc-era while the local kernel is 7.3-rc6 + possible stable backports — where they could differ (e.g. exact `cpufreq_cpu_get` internals: local uses `cpufreq_driver_lock`+`kobject_get`, current master uses a policy usage ref), both versions were checked and both lack any `policy->rwsem` acquisition in the ops path. Local config: `CONFIG_X86_AMD_PSTATE=y`, `CONFIG_ACPI_PLATFORM_PROFILE=y`; `PROVE_LOCKING`/`DEBUG_LOCK_ALLOC`/`DEBUG_RWSEMS` are **off** (only `CONFIG_LOCKDEP_SUPPORT=y`, an arch capability), which is why the deadlock produced no lockdep splat — a silent wedge was inevitable.

---

## 4. Trigger conditions

- The cycle needs exactly **two concurrent sysfs operations**: (a) any path that registers or removes a platform_profile handler — in practice the non-dynamic→`dynamic` EPP transition (or dynamic→static cleanup) on any policy, which runs `platform_profile_register()`/`platform_profile_remove()` and `sysfs_update_group()` under `profile_lock`; and (b) any read or write of `/sys/firmware/acpi/platform_profile` (or `/sys/class/platform-profile/*/profile`) overlapping the drain window of (a). Nothing else is required — no third writer, no ACPI quirk, no specific EPP value.
- The window is not marginal: `platform_profile_register` fires `sysfs_notify(acpi_kobj, NULL, "platform_profile")` at `platform_profile.c:608` **immediately before** `sysfs_update_group()` at `:610`. The notify wakes exactly the watchers (asusd's inotify on `/sys/firmware/acpi/platform_profile`) that will then block on `profile_lock` while pinning the active ref the subsequent drain waits for. The sibling report's journals show `asusd: Platform: watch_platform_profile changed` **0.501–0.586 ms** after the `dynamic` write in all three wedged boots — i.e. the notified thread entered the file within the window, every time. Dock/AC at boot matters only because it puts asusd into active profile management (`set_platform_profile — Setting Performance before EPP`); boot 0 (no dock) had asusd quiescent ~37 ms before the writes and raced nothing.
- **Userspace writer count is exposure, not cause.** eco-power.sh, tlp and asusd are three concurrent triggerers of the same two kernel paths; any two concurrent sysfs operations by any programs (including one shell and one daemon) can hit it. Removing all but one writer serializes the two orders and makes the wedge statistically vanish — it cannot make the kernel code safe.
- The repo mitigation (commit `735d392`: drift-only EPP writes, `eco-power.service` ordered `After=tlp.service asusd.service`, single boot transition writer) correctly reduces exposure: fewer/no redundant non-dynamic→dynamic transitions (each of which is one register/drain attempt per policy) and no concurrent profile-watcher traffic during the boot pass. It **cannot fix** the inversion: the first `dynamic` write still executes `platform_profile_register()` under `policy->rwsem` → `profile_lock`, and any future reader of `/sys/firmware/acpi/platform_profile` racing that register (or any dynamic→static write racing `platform_profile_remove()`) reproduces the deadlock. The same applies to any arrangement of `After=`, write-count reduction, or userspace locking.

---

## 5. Upstream status / prior art

- **Direct prior art for this exact cycle — posted upstream 2026-10-14, not yet merged:** Daniel Lezcano (Qualcomm/OSS), linux-kernel:
  - Cover: `[PATCH v1 0/4] Make platform profiles firmware independent`, 2026-10-14, Message-ID `20261014132500.3817549-1-daniel.lezcano@oss.qualcomm.com` — https://marc.info/?l=linux-kernel&m=179198944246028&w=2 ("The first patch fixes the lock/lifetime boundary before adding another frontend: sysfs teardown must not drain callbacks while holding the mutex those callbacks need.")
  - Fix: `[PATCH v1 1/4] platform profile: Separate handler locking from sysfs lifetime`, Message-ID `20261014132500.3817549-2-daniel.lezcano@oss.qualcomm.com` — https://marc.info/?l=linux-kernel&m=179198879545292&w=2 . Its commit message describes the inversion verbatim: "Registration and removal currently hold `profile_lock` across `device_unregister()` and `sysfs_update_group()` … a concurrent access can deadlock: Removal/update path: acquire `profile_lock` → remove a sysfs attribute → wait for its active references; Active sysfs callback: hold kernfs active reference → wait for `profile_lock`." Fix approach: new `profile_registration_lock` never taken by sysfs callbacks; explicit handler list; unlink under `profile_lock` before `device_unregister()`; release `profile_lock` before draining sysfs.
  - Status at 2026-10-17: **v1 under review, not in torvalds/linux master** (master `drivers/acpi/platform_profile.c` still has `guard(mutex)(&profile_lock)` at `:586`/`:639` with `device_register`/`device_unregister`/`sysfs_update_group` inside, and no `profile_registration_lock`).
- **Same-feature prior hang (different race, fixed):** `9228169d2ae0` (2026-05-08) — "hits the WARN_ON_ONCE() in static_key_disable_cpuslocked() and hangs the system" from concurrent `amd_pstate/status` + `dynamic_epp` writes; fixed by serializing on `amd_pstate_driver_lock`. https://github.com/torvalds/linux/commit/9228169d2ae055ed09a163887fc59a710a5eb73b (commit message links https://lore.kernel.org/r/20260508051748.10484-2-kprateek.nayak@amd.com). Adjacent follow-ups in the same area: `39c0cf62fc78` ("handle missing policy in dynamic EPP callbacks"), `df488cac6140`/`d61c1ad39026` (amd-pstate-ut dynamic EPP tests).
- **lore.kernel.org search:** could not be performed directly from this host — lore is behind an anti-bot gate for this network (HTTP 200 "Making sure you're not a bot" / 403 on query URLs). The two threads above were obtained from primary sources (MARC archive + commit-message `Link:` headers in torvalds/linux). Any further lore search for `platform_profile deadlock`/`amd-pstate deadlock` must be run from an unblocked host before claiming "none found" globally.
- **kernel bugzilla:** REST/CSV quicksearch for `platform_profile`, `"platform profile" lockdep OR deadlock`, `platform_profile deadlock` (https://bugzilla.kernel.org/rest/bug?quicksearch=…) on 2026-10-17 found **no report of this deadlock**. Nearest hits are functional, not locking: #212939 (thinkpad_acpi reports wrong platform_profile value), #212985 (ideapad_acpi interface unavailable), #214113 (hp-wmi platform profile not working). Search is fuzzy/OR-ish; treat as "none found, best-effort".

---

## 6. Recommended kernel fix

**Primary fix (matches upstream v1):** land the lock/lifetime split of `[PATCH v1 1/4] platform profile: Separate handler locking from sysfs lifetime` in `drivers/acpi/platform_profile.c`:

1. Introduce `profile_registration_lock` (never acquired by sysfs callbacks) serializing register/remove and aggregate sysfs updates.
2. Keep `profile_lock` only around profile state/ops; walk an explicit handler list instead of the live class-device list for aggregate ops.
3. Unlink the handler under `profile_lock` **before** `device_unregister()`, and drop `profile_lock` **before** any operation that can drain kernfs active refs (`device_unregister`, `sysfs_update_group`). Rationale: the drain waits for the very callbacks that need `profile_lock`; no ordering of the two locks can coexist with that wait unless the mutex is released first (or the callbacks stop taking it).

**Secondary hardening in amd-pstate (`drivers/cpufreq/amd-pstate.c`):** stop performing blocking device/sysfs registration from inside the cpufreq store path. `amd_pstate_set_dynamic_epp`/`amd_pstate_clear_dynamic_epp` run under `down_write(&policy->rwsem)` (cpufreq core store wrapper) and call `platform_profile_register/remove` + `power_supply_(un)reg_notifier`, i.e. long, lock-heavy, reclaim-capable work under a hot per-policy rwsem. Move register/unregister + notifier (un)registration out of the store callback — e.g. defer to a workqueue (per-CPU `amd_pstate_profile_work`) or register once at `amd_pstate_epp_cpu_init`/remove at `cpu_exit` — and/or define an explicit lock order: `profile_lock` → `policy->rwsem` never violated, and nothing that can block on sysfs/device lifetime under either. This does not by itself remove the platform_profile core cycle, but it removes `policy->rwsem` from the blast radius and shrinks every exposure window to nothing.

**Report-ready block (paste into an upstream thread / CachyOS issue):**

> **platform_profile: deadlock between `profile_lock` and kernfs active-ref drain, triggered from amd-pstate dynamic-EPP registration** (reproduced on 7.3.0-rc6, AMD Zen, CachyOS build of stock 7.3-rc6).
>
> Writing `dynamic` to `policyX/energy_performance_preference` runs `store_energy_performance_preference` under `down_write(&policy->rwsem)` (cpufreq core `store()`, `guard(cpufreq_policy_write)`), and on transition calls `amd_pstate_set_dynamic_epp()` → `platform_profile_register()` (`amd-pstate.c`). `platform_profile_register()` holds `profile_lock` across `device_register()`, `sysfs_notify(acpi_kobj, ..., "platform_profile")` and `sysfs_update_group(acpi_kobj, &platform_profile_group)` (`platform_profile.c:586-610`). `sysfs_update_group()` in update mode removes and recreates the `platform_profile` attribute (`fs/sysfs/group.c:48-66`), and `kernfs_drain()` waits for in-flight sysfs callbacks (`fs/kernfs/dir.c:537-538`) — while those callbacks (`platform_profile_show/store`, `platform_profile.c:386/425`) acquire `profile_lock` under their kernfs active reference (`fs/kernfs/file.c:337`). ABBA: registration waits for the active ref; the callback waits for `profile_lock`. The `sysfs_notify` immediately before the update wakes inotify watchers (e.g. asusd) that enter the file inside the window; the store path never returns, `policy->rwsem` stays write-held, and every cpufreq/platform_profile/power_supply sysfs user wedges in `TASK_UNINTERRUPTIBLE` (SIGKILL-immune). Reproduced 3/3 boots with a concurrent `/sys/firmware/acpi/platform_profile` watcher at register time; 0/1 without. Same cycle exists in `platform_profile_remove()` (`:639-645`). This matches the analysis in `[PATCH v1 1/4] platform profile: Separate handler locking from sysfs lifetime` (daniel.lezcano@oss.qualcomm.com, Message-ID 20261014132500.3817549-2-daniel.lezcano@oss.qualcomm.com), which we believe is the correct fix; we hit this in production three days after that patch was posted. Secondary ask: amd-pstate should not call `platform_profile_register/remove` + `power_supply_(un)reg_notifier` while the cpufreq core holds `policy->rwsem`.
>
> Evidence: local `vmlinux` 7.3.0-rc6-1-cachyos-bore-lto — `store_energy_performance_preference` @ 0xffffffff823de900 (`platform_profile_register` call @ 0xffffffff823deb81), `platform_profile_register` @ 0xffffffff8209ed40 (`mutex_lock(profile_lock)` @ 0xffffffff8209ee1b, `internal_create_group` @ 0xffffffff8209ef13), `profile_store` @ 0xffffffff8209f420 (`mutex_lock_interruptible` @ 0xffffffff8209f45b under active ref). Lockdep off (`CONFIG_PROVE_LOCKING` unset), hence no splat. Full write-up with boot journals: repo `ZhangDM-520/system-tuning`, `docs/research/2026-10-17-boot-epp-deadlock-report.md` (journals) and `docs/research/2026-10-17-epp-deadlock-kernel-attribution.md` (attribution).

---

## 7. Evidence appendix

### 7.1 Commands used (all read-only on the live system)

```
uname -r                                                   # 7.3.0-rc6-1-cachyos-bore-lto
nm --numeric-sort /usr/lib/modules/7.3.0-rc6-1-cachyos-bore-lto/build/vmlinux | grep ...
objdump -d --start-address=0xffffffff823df6c0 --stop-address=0xffffffff823df770 vmlinux   # amd_pstate_profile_set (full)
objdump -d --start-address=0xffffffff823de900 --stop-address=0xffffffff823deca0 vmlinux   # store_energy_performance_preference (calls)
objdump -d --start-address=0xffffffff8209ed40 --stop-address=0xffffffff8209f070 vmlinux   # platform_profile_register / _remove
objdump -d --start-address=0xffffffff8209f7c0 --stop-address=0xffffffff8209f8a0 vmlinux   # platform_profile_show
objdump -d --start-address=0xffffffff8209f420 --stop-address=0xffffffff8209f620 vmlinux   # profile_store
objdump -d --start-address=0xffffffff823d48e0 --stop-address=0xffffffff823d49c0 vmlinux   # cpufreq_cpu_get (full)
strings -a vmlinux | grep "amd-pstate-epp-cpu"                                            # format string present
grep CONFIG_{PROVE_LOCKING,DEBUG_LOCK_ALLOC,LOCKDEP,DEBUG_RWSEMS,...} .../build/include/config/auto.conf
```

Upstream source fetched to `/tmp` (scratch) from raw.githubusercontent.com torvalds/linux@master on 2026-10-17: `drivers/cpufreq/amd-pstate.c`, `drivers/cpufreq/amd-pstate.h`, `drivers/cpufreq/cpufreq.c`, `include/linux/cpufreq.h`, `drivers/acpi/platform_profile.c`, `fs/sysfs/group.c`, `fs/sysfs/file.c`, `fs/kernfs/dir.c`, `fs/kernfs/file.c`. History via GitHub API (`list_commits`, `get_commit` with full patches): commits `e30ca6dd5345`, `798c47593cca`, `b7294b627598`, `9228169d2ae0`, `39c0cf62fc78`, `32692fcf61ed`, merges `5cdfedf68e6e`/`7f464fb22975`/`eb49643e66e0`. CachyOS scope: `CachyOS/kernel-patches` tree + `7.3/misc`, `7.3/sched` listings + grep of `0001-bore-cachy.patch`, `0001-acpi-call.patch`. Prior art: MARC search/listing + message fetch (msg ids `179198944246028`, `179198879545292`); bugzilla REST quicksearch. Repo mitigation: `git show 735d392` (read-only).

### 7.2 Addresses ↔ source map (local `vmlinux`)

| Address | Symbol / construct | Source |
|---|---|---|
| `0xffffffff823de900` | `store_energy_performance_preference` (amd-pstate, inlines `amd_pstate_set_dynamic_epp`/`clear_dynamic_epp`) | `amd-pstate.c:1410-1473`, `:1278-1326`, `:1263-1276` |
| `0xffffffff823de9bd` | `movl $0x3,0x110(%r12)` — `current_profile = PLATFORM_PROFILE_BALANCED` | `amd-pstate.c:1439` |
| `0xffffffff823de9f7` | `power_supply_is_system_supplied` | `amd-pstate.c` `amd_pstate_get_balanced_epp` |
| `0xffffffff823deab6` / `0xffffffff823dec08` | `platform_profile_remove` (clear + error cleanup) | `amd-pstate.c:1270` |
| `0xffffffff823deb49` | `kasprintf` (not `devm_kasprintf`) | `amd-pstate.c:1294` |
| `0xffffffff823deb81` | `platform_profile_register` | `amd-pstate.c:1298-1301` |
| `0xffffffff823debc8` | `blocking_notifier_chain_register` = `power_supply_reg_notifier` inline | `amd-pstate.c:1309-1310` |
| `0xffffffff823df6c0` | `amd_pstate_profile_set` — **no locks taken** | `amd-pstate.c:1232-1256` |
| `0xffffffff823d48e0` | `cpufreq_cpu_get` — `cpufreq_driver_lock` rwlock + `kobject_get` only | `cpufreq.c:195-227` |
| `0xffffffff8209ed40` | `platform_profile_register` | `platform_profile.c:550-625` |
| `0xffffffff8209ee1b` | `mutex_lock(&profile_lock)` | `platform_profile.c:586` (`profile_lock` bss @ `0xffffffff8487c9b0`) |
| `0xffffffff8209eea4` | `device_register` | `platform_profile.c:602` |
| `0xffffffff8209eefb` | `sysfs_notify(acpi_kobj, ...)` | `platform_profile.c:608` |
| `0xffffffff8209ef13` | `internal_create_group` = `sysfs_update_group` | `platform_profile.c:610`; `fs/sysfs/group.c:295-297` |
| `0xffffffff8209f028` / `0xffffffff8209f055` | `platform_profile_remove`: `device_unregister` / `sysfs_update_group` under `profile_lock` | `platform_profile.c:639-645` |
| `0xffffffff8209f7c0` | `platform_profile_show` — `mutex_lock_interruptible(&profile_lock)` @ `0xffffffff8209f7f9`, `class_for_each_device` @ `0xffffffff8209f830` | `platform_profile.c:379-399` |
| `0xffffffff8209f420` | `profile_store` — `mutex_lock_interruptible` @ `0xffffffff8209f45b`, indirect `ops->profile_set` @ `0xffffffff8209f4b8` | `platform_profile.c:203-221` |

### 7.3 Explicit unknowns / UNVERIFIED

- **No task stacks or lockdep output exist for the three wedged boots** (config has lockdep off; no `sysrq-t`/`/proc/*/stack` capture before power-cycle). The kernel-side cycle is proven from source + binary and matches the journal timeline with high confidence, but the per-thread blocking chain of the incident itself is inferred, not dumped. A future repro with `CONFIG_PROVE_LOCKING=y` or a hung-task stack capture would close this.
- **lore.kernel.org could not be searched directly** (anti-bot gate from this network). "No report of this exact deadlock found" is established only for kernel bugzilla + MARC + commit messages + the two lore URLs cited via commits. Run lore searches (`platform_profile deadlock`, `profile_lock kernfs`, `amd-pstate dynamic epp hang`) from an unblocked host before stating a global "none found".
- Whether the Lezcano v1 series has a v2 or has landed in linux-next at the time of reading is UNVERIFIED (only master was checked: not merged as of 2026-10-17).
- The second `store_energy_performance_preference` copy at `0xffffffff823decb0` (intel_pstate or cppc_cpufreq TU) was not disassembled; irrelevant to the cycle but noted so the two symbols are not confused.
- Local `cpufreq_cpu_get` internals differ from current master (rwlock-based vs usage-ref-based); both were shown to take no `policy->rwsem`, but other unexamined 7.3-rc6 vs master drift is possible. All structural claims above were re-verified in the local binary wherever a lock is involved.
- Interaction with other platform_profile providers on this machine (asus-wmi registers one) could add further lock orders (e.g. `asus->mutex`/ACPI under `profile_lock`); not analyzed here and not needed for the proven cycle. If the boot wedge is ever shown to be a different chain than §2.2, this is the first place to look.
