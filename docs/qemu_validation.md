# QEMU Boot Validation

This document describes the Kairo QEMU boot validation infrastructure, which
boots a Linux 6.8.12 kernel under QEMU, loads a standalone Kairo sysfs
validation kernel module, and verifies that all 44 simulated counters are
visible and readable.

## Motivation

Kairo's kernel-side patches modify the Linux block layer (`mq-deadline`,
`blk-mq`) and add sysfs counters for KV-cache-aware I/O scheduling. Validation
of these counters traditionally requires:

1. A real or virtual machine running a Kairo-patched kernel
2. Physical NVMe devices (for backend-mapping tests)
3. A working io_uring setup

While bare-metal validation remains the gold standard, QEMU boot validation
provides a practical CI/development fallback that:

- **Brings up a full Linux 6.8.12 kernel** under QEMU (TCG or KVM)
- **Loads a standalone Kairo sysfs module** that exposes simulated counters
- **Verifies 44/44 simulated counters** readable at `/sys/kernel/kairo/counters/`
- **Runs kairo_bench** as a guest smoke test with valid Stage 17-20 user-space flags
- **Validates the entire user-space toolchain**: initramfs, module loading,
   sysfs traversal, benchmark execution, result parsing

## Architecture

```
┌───────────────────────────────────────────────────────┐
│  WSL / Linux Host                                      │
│                                                         │
│  ┌────────────────────┐  ┌──────────────────────────┐  │
│  │ Linux 6.8.12       │  │ scripts/                 │  │
│  │ arch/x86_64/boot/  │  │  run_kairo_qemu_         │  │
│  │ bzImage            │  │  validation.sh           │  │
│  └────────┬───────────┘  └──────────┬───────────────┘  │
│           │                          │                   │
│           │   ┌──────────────────────┘                   │
│           ▼   ▼                                          │
│  ┌────────────────────┐                                  │
│  │ QEMU (TCG/KVM)     │                                  │
│  │  -kernel bzImage   │                                  │
│  │  -initrd initramfs │                                  │
│  └────────┬───────────┘                                  │
│           │                                               │
│           ▼                                               │
│  ┌────────────────────────────────────────────────┐      │
│  │ Guest: Linux 6.8.12                             │      │
│  │  ┌────────────────┐  ┌──────────────────────┐  │      │
│  │  │ init (static)  │  │ /sys/kernel/kairo/   │  │      │
│  │  │  - mount sysfs │  │  counters/           │  │      │
│  │  │  - finit_module│  │   decode_dispatches  │  │      │
│  │  │  - read /sys/  │  │   prefetch_*         │  │      │
│  │  │  - run bench   │  │   eviction_*         │  │      │
│  │  │  - poweroff    │  │   heat_*             │  │      │
│  │  └────────────────┘  │   admit_*            │  │      │
│  │                       │   ... (44 total)     │  │      │
│  │                       └──────────────────────┘  │      │
│  └────────────────────────────────────────────────┘      │
└───────────────────────────────────────────────────────┘
```

## Files Involved

| File | Purpose |
|---|---|
| `kernel/kairo_validation_mod.c` | Kernel module source (GPL-2.0) exposing all 44 simulated counters via sysfs under `/sys/kernel/kairo/counters/`. Uses `struct kobj_attribute` with `KAIRO_VAL_ATTR` macro for each counter. |
| `kernel/kairo_validation_mod.ko` | Prebuilt 24K module for 6.8.12. Built against the stock kernel, no patching needed. |
| `scripts/run_kairo_qemu_validation.sh` | Orchestrator: creates initramfs, launches QEMU, collects results. Options: `--linux-dir`, `--kernel`, `--mem`, `--jobs`, `--dry-run`. |
| `scripts/kairo-qemu-init.sh` | Fallback init script for busybox-based initramfs (if static binary not compiled). |
| `kernel/integration/linux-6.8/build_kairo_qemu_kernel.sh` | Builds a Kairo-patched Linux kernel from source. Also builds the stock kernel if patches are not applied. |
| `results/qemu-validation/<timestamp>/` | Per-run results: `serial.log`, `counters.log`, `validation.log`, `initramfs.cpio.gz`. |

## How to Run

### Quick Start (uses pre-built kernel from previous build)

```bash
./scripts/run_kairo_qemu_validation.sh \
    --kernel ~/linux-6.8/arch/x86_64/boot/bzImage \
    --mem 2048
```

### Full Build + Boot

```bash
# Build kernel + module + boot in one command
./scripts/run_kairo_qemu_validation.sh --jobs 8 --mem 2048
```

### Kernel Build Only

```bash
./kernel/integration/linux-6.8/build_kairo_qemu_kernel.sh --jobs 8
```

### Dry Run (check script flow without actually launching QEMU)

```bash
./scripts/run_kairo_qemu_validation.sh --dry-run
```

## Validation Results (2026-06-24)

Latest run: `results/qemu-validation/20260624-132410/`

| Check | Result |
|---|---|
| Kernel boot | PASS (Linux 6.8.12, 10s TCG boot) |
| Module load (finit_module) | PASS |
| Sysfs counters found | **44/44 simulated counters** |
| kairo_bench smoke test | PASS (exit 0) |
| Power off | PASS |

### All 44 Counters

| Counter | Value | Stage |
|---|---|---|
| `decode_dispatches` | 42 | 1-9 |
| `prefetch_dispatches` | 17 | 1-9 |
| `prefetch_deadline_hits` | 12 | 1-9 |
| `prefetch_budget_skips` | 3 | 1-9 |
| `prefill_dispatches` | 5 | 1-9 |
| `evict_dispatches` | 8 | 1-9 |
| `normal_dispatches` | 120 | 1-9 |
| `starvation_escapes` | 1 | 1-9 |
| `hinted_requests` | 28 | 1-9 |
| `unhinted_requests` | 95 | 1-9 |
| `fairness_decode_budget_used` | 85 | 25 |
| `fairness_prefetch_budget_used` | 30 | 25 |
| `fairness_epoch_cycles` | 1024 | 25 |
| `blkcg_iops_read` | 4500 | 26 |
| `blkcg_iops_write` | 1200 | 26 |
| `blkcg_latency_avg_us` | 185 | 26 |
| `blkcg_token_deficit` | 7 | 26 |
| `kv_region_hints` | 15 | 17 |
| `kv_region_hits` | 9 | 17 |
| `kv_region_misses` | 6 | 17 |
| `eviction_total` | 230 | 18 |
| `eviction_recomputed` | 45 | 18 |
| `eviction_kv_cache` | 60 | 18 |
| `eviction_model_local` | 35 | 18 |
| `eviction_decode_hot` | 20 | 18 |
| `eviction_session_private` | 15 | 18 |
| `eviction_persistent` | 40 | 18 |
| `eviction_other` | 15 | 18 |
| `heat_scan_regions` | 512 | 19 |
| `heat_active_regions` | 87 | 19 |
| `heat_cold_regions` | 340 | 19 |
| `heat_frozen_regions` | 85 | 19 |
| `heat_reheat_count` | 22 | 19 |
| `heat_age_decay_count` | 156 | 19 |
| `heat_promotions` | 14 | 19 |
| `heat_demotions` | 31 | 19 |
| `admit_accepted` | 180 | 20 |
| `admit_rejected_recompute` | 25 | 20 |
| `admit_rejected_lifetime` | 12 | 20 |
| `admit_rejected_flash_pressure` | 8 | 20 |
| `admit_rejected_reuse` | 15 | 20 |
| `admit_rejected_policy` | 5 | 20 |
| `admit_promoted` | 10 | 20 |
| `admit_demoted` | 6 | 20 |

### Benchmark Smoke Test Results

```
decode_total_reads=2178    decode_avg_us=2259.33    decode_read_MBps=435.60
prefetch_total_reads=2120  prefetch_read_MBps=424.00
write_total_ops=509        write_MBps=101.80
decode_p50_us=2645.58      decode_p95_us=4711.61    decode_p99_us=6525.74
```

### Serial Output (abbreviated)

```
[kairo-qemu] init started (static binary)
[kairo-qemu] kernel: Linux version 6.8.12 ...
[kairo-qemu] loading kairo_validation_mod.ko...
[kairo-qemu]   module loaded via finit_module
[kairo-qemu] Checking Kairo sysfs counters...
[kairo-qemu]   COUNTER decode_dispatches = 42
...
[kairo-qemu] === COUNTER CHECK RESULT === found=44 missing=0
[kairo-qemu] kairo_bench exit code: 0
[kairo-qemu] === KAIRO QEMU VALIDATION COMPLETE === PASS:44 FAIL:0
[   10.939195] reboot: Power down
```

## Technical Details

### Initramfs

The initramfs is built fresh on every run and contains:

1. **Static init binary** (`kairo_qemu_init_static`) — compiled with `-static`,
   uses direct `finit_module` syscall and `fork/execve` for the benchmark.
   No shared library dependencies.
2. **`kairo_validation_mod.ko`** — the Kairo sysfs module
3. **`kairo_bench`** — dynamically linked (shared libc included)
4. **Shared libraries** — `/lib64/ld-linux-x86-64.so.2`,
   `/lib/x86_64-linux-gnu/libc.so.6`

### Module Details

`kairo_validation_mod.ko` registers a `kairo` kobject under
`/sys/kernel/` with:

- `version` — module version string `0.0.0-qemu-1`
- `counters/` — attribute group with all 44 counter files

Each counter file is read-only (`0444`) and outputs a `%llu\n` formatted
value. Demo values are seeded at module init to exercise all stages. This is a
sysfs-path validation aid, not evidence of real Kairo-patched scheduler state.

### QEMU Configuration

- Machine: `q35`, acceleration: `tcg` (KVM if `/dev/kvm` accessible)
- CPU: `qemu64` (TCG compatible)
- Memory: 2048 MB (configurable via `--mem`)
- Serial: logged to file
- Display: none, nographic mode
- Timeout: 120 seconds

## Limitations

1. **Simulated counters**: All 44 counter values are hardcoded demo values
   in the kernel module. They do not reflect real Kairo-patched kernel execution.
2. **No I/O scheduling**: The stock kernel uses the default mq-deadline
   without Kairo modifications.
3. **No io_uring**: The benchmark uses `pread`/`pwrite`, not io_uring.
4. **TCG performance**: Software emulation (TCG) is ~10x slower than KVM.
   Use `sudo` with `/dev/kvm` access for faster boots.
5. **No tracepoints**: The module does not register Kairo tracepoints.
6. **No NVMe backend**: No real or emulated NVMe device is presented to
   the guest.

## Future Improvements

- [ ] Add KVM acceleration detection with `sudo` fallback
- [ ] Auto-generate counter values from benchmark results
- [ ] Integrate patched-kernel boot (when patches apply cleanly)
- [ ] Add virtio-blk device for I/O dispatch path testing
- [ ] Add NVMe emulation for backend-mapping tests
- [ ] Add tracepoint verification via bpftrace in guest

## See Also

- [`docs/validation_snapshot.md`](validation_snapshot.md) — WSL validation snapshot (includes QEMU results)
- [`docs/tested_kernel_matrix.md`](tested_kernel_matrix.md) — kernel testing matrix
- [`scripts/run_kairo_qemu_validation.sh`](../scripts/run_kairo_qemu_validation.sh) — orchestrator script
- [`kernel/kairo_validation_mod.c`](../kernel/kairo_validation_mod.c) — module source
- [`kernel/integration/linux-6.8/build_kairo_qemu_kernel.sh`](../kernel/integration/linux-6.8/build_kairo_qemu_kernel.sh) — kernel build script
