# Kairo

Kernel AI Runtime I/O for KV-cache-aware Linux storage

Kairo is an internal Linux-kernel RFC/POC exploring AI KV-cache-aware block I/O for generic NVMe SSDs.

This project is not intended for LKML submission at this stage.

## Scope

Kairo explores whether Linux block-layer changes can improve generic NVMe SSD behavior for AI inference-like KV-cache workloads. The current proof point is decode-read prioritization under mixed read and write pressure, but the architecture remains broader than a single scheduler tweak.

## Current Status

- internal RFC/POC
- experimental kernel path
- benchmark-driven validation
- local patch scaffolds targeting `mq-deadline`

## Problem

AI KV-cache traffic behaves differently from ordinary storage I/O:

- decode reads are latency-critical
- prefetch reads are important but less urgent
- prefill writes are background relative to decode
- eviction and discard are lowest priority
- KV cache is large-block, read-dominant, session scoped, and often recomputable

## Architecture

```text
+---------------------------------------------------------+
| AI Runtime / Synthetic Benchmark                        |
| - decode reads                                          |
| - prefetch reads                                        |
| - prefill writes                                        |
| - eviction/discard                                      |
+---------------------------------------------------------+
| User-Space Hint Path                                    |
| - io_uring                                              |
| - O_DIRECT                                              |
| - registered buffers                                    |
| - ioprio / model / session / lifetime hints             |
+---------------------------------------------------------+
| Kairo Block Layer                                       |
| - request classification                                |
| - decode-critical read priority                         |
| - prefetch-aware scheduling                             |
| - prefill-write demotion                                |
| - large-block coalescing                                |
+---------------------------------------------------------+
| Generic NVMe Backend                                    |
| - mq-deadline extensions                                |
| - blk-mq metadata                                       |
| - optional ZNS / Streams / FDP mapping                  |
+---------------------------------------------------------+
```

## Current Benchmark Strategy

The current benchmark is [bench/kairo_bench.c](bench/kairo_bench.c). It uses:

- pthread workers
- `pread()` and `pwrite()`
- `O_DIRECT` when available
- aligned buffers via `posix_memalign()`
- per-thread `ioprio` classification

Temporary worker mapping:

```text
RT prio 0 read  -> KAIRO_DECODE_READ
RT prio 1 read  -> KAIRO_PREFETCH_READ
BE prio 7 write -> KAIRO_PREFILL_WRITE
discard         -> KAIRO_EVICT
```

## Current Kernel Patch Path

Primary patch scaffold:

- [kernel/patches/0001-rfc-kairo-mq-deadline-decode-priority.patch](kernel/patches/0001-rfc-kairo-mq-deadline-decode-priority.patch)

Supporting scaffolds:

- [kernel/patches/0002-rfc-kairo-block-request-classification.patch](kernel/patches/0002-rfc-kairo-block-request-classification.patch)
- [kernel/patches/0003-rfc-kairo-debugfs-scheduler-stats.patch](kernel/patches/0003-rfc-kairo-debugfs-scheduler-stats.patch)

## Success Metric

Primary metric:

- `decode_p99_us` under mixed prefill-write pressure

Secondary metrics:

- `decode_p95_us`
- `decode_avg_us`
- `decode_read_MBps`
- `write_MBps`
- starvation behavior

## Build

```bash
gcc -O2 -Wall -pthread -Iinclude -o kairo_bench bench/kairo_bench.c
```

Or:

```bash
./scripts/build_bench.sh
```

## Run Baseline

```bash
./scripts/run_baseline.sh /mnt/nvme/kairo.test nvme0n1
```

## Run Kairo POC

```bash
./scripts/set_mq_deadline.sh nvme0n1
./scripts/run_kairo_poc.sh /mnt/nvme/kairo.test nvme0n1
```

## Validation Path

Use the runtime validator to confirm the experimental kernel path is live and
that Kairo counters move under the AI inference-like KV-cache workload:

```bash
./scripts/validate_kairo_runtime.sh /mnt/nvme/kairo.test nvme0n1
```

Use the A/B runner to compare baseline vs Kairo on the same generic NVMe SSD:

```bash
./scripts/run_ab_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

Track local validation status in:

- [docs/tested_kernel_matrix.md](docs/tested_kernel_matrix.md)

## Repository Layout

- [docs/architecture.md](docs/architecture.md)
- [docs/aggressive_poc_plan.md](docs/aggressive_poc_plan.md)
- [docs/kernel_patch_plan.md](docs/kernel_patch_plan.md)
- [docs/benchmark_plan.md](docs/benchmark_plan.md)
- [include/kairo_hints.h](include/kairo_hints.h)
- [bench/README.md](bench/README.md)
- [scripts/build_bench.sh](scripts/build_bench.sh)
