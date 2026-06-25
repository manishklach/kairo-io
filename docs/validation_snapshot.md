# Kairo Validation Snapshot

Date: 20260624-132410
Environment: WSL2 + QEMU (TCG)
Host Kernel: 6.6.87.2-microsoft-standard-WSL2+
Guest Kernel: Linux 6.8.12 (stock)
WSL: true
QEMU: 8.2.2 (Debian 1:8.2.2+ds-0ubuntu1.16)

## Summary

| Check | Result |
|---|---|
| validate_patch_stack | pass |
| make | pass |
| fallback_gcc_build | not_needed |
| benchmark_exists | true |
| stage6_dryrun | pass |
| stage7_dryrun | pass |
| stage8_dryrun | pass |
| stage13_dryrun | pass |
| stage14_dryrun | pass |
| stage15_dryrun | pass |
| stage16_dryrun | pass |
| stage17_dryrun | pass |
| stage18_dryrun | pass |
| stage19_dryrun | pass |
| stage20_dryrun | pass |
| user_bench_baseline | skipped |
| user_bench_mixed | skipped |
| **qemu_boot** | **pass** |
| **qemu_module_load** | **pass** |
| **qemu_counters_found** | **44/44** |
| **qemu_bench_smoke** | **pass** |

## What This Validates

- repository consistency
- benchmark build
- experiment harness dry-run path
- WSL user-space benchmark smoke path
- **QEMU guest kernel boot (Linux 6.8.12 on x86_64)**
- **kairo_validation_mod.ko load and sysfs registration on a stock kernel**
- **44 simulated Kairo sysfs counters exposed by the standalone validation module**
- **kairo_bench guest smoke test execution** (exit code 0; not proof of patched-kernel Stage 17-20 behavior)

## What This Does Not Validate

- custom Kairo-patched kernel boot (patches do not apply cleanly to 6.8.12)
- mq-deadline patched-kernel behavior
- physical NVMe placement
- tracepoint availability on patched kernel

## QEMU Boot Details

| Metric | Value |
|---|---|
| Boot time | ~10s (TCG) |
| Kernel version | 6.8.12 #2 SMP PREEMPT_DYNAMIC |
| GCC version | 13.3.0 (Ubuntu 13.3.0-6ubuntu2~24.04.1) |
| Init type | Static C binary (kairo_qemu_init_static) |
| Module load method | finit_module syscall |
| Sysfs path | `/sys/kernel/kairo/counters/` |

## Counter Results

Found 44/44 counters (0 missing):

| Group | Counters | Status |
|---|---|---|
| Stage 1-9: Dispatch | decode_dispatches, prefetch_dispatches, prefetch_deadline_hits, prefetch_budget_skips, prefill_dispatches, evict_dispatches, normal_dispatches, starvation_escapes, hinted_requests, unhinted_requests | ✅ 10/10 |
| Stage 25: Fairness | fairness_decode_budget_used, fairness_prefetch_budget_used, fairness_epoch_cycles | ✅ 3/3 |
| Stage 26: blkcg | blkcg_iops_read, blkcg_iops_write, blkcg_latency_avg_us, blkcg_token_deficit | ✅ 4/4 |
| Stage 17: KV Region | kv_region_hints, kv_region_hits, kv_region_misses | ✅ 3/3 |
| Stage 18: Eviction | eviction_total, eviction_recomputed, eviction_kv_cache, eviction_model_local, eviction_decode_hot, eviction_session_private, eviction_persistent, eviction_other | ✅ 8/8 |
| Stage 19: Heatmap | heat_scan_regions, heat_active_regions, heat_cold_regions, heat_frozen_regions, heat_reheat_count, heat_age_decay_count, heat_promotions, heat_demotions | ✅ 8/8 |
| Stage 20: Admission | admit_accepted, admit_rejected_recompute, admit_rejected_lifetime, admit_rejected_flash_pressure, admit_rejected_reuse, admit_rejected_policy, admit_promoted, admit_demoted | ✅ 8/8 |

## Benchmark Smoke Test (guest)

```
decode_total_reads=2178    decode_avg_us=2259.33  decode_read_MBps=435.60
prefetch_total_reads=2120  prefetch_read_MBps=424.00
write_total_ops=509        write_MBps=101.80
decode_p50_us=2645.58      decode_p95_us=4711.61  decode_p99_us=6525.74
```

## Artifacts

- environment.log
- validate_patch_stack.log
- make.log
- stage6_dryrun.log through stage20_dryrun.log
- **qemu_validation/<timestamp>/initramfs.cpio.gz**
- **qemu_validation/<timestamp>/serial.log**
- **qemu_validation/<timestamp>/validation.log**
- **qemu_validation/<timestamp>/build_kernel.log**

Results directories:
- `results/validation/20260624-102820` (WSL dry-run)
- `results/qemu-validation/20260624-132410` (QEMU boot + sysfs + bench)

Notes: QEMU validation uses stock Linux 6.8.12 + kairo_validation_mod.ko kernel module;
      patched-kernel validation requires real Linux hardware.
