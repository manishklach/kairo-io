# Kairo

**Kernel AI Runtime I/O for KV-cache-aware Linux storage**

**Status:** Internal RFC/POC  
**Scope:** Linux block-layer, io_uring, NVMe, and benchmark-driven storage scheduling research  
**Important:** This project is not intended for LKML submission at this stage.

Kairo is an internal Linux-kernel RFC/POC exploring AI KV-cache-aware block I/O for generic NVMe SSDs.

KV cache is neither ordinary file data nor ordinary memory. It is large-block, read-dominant, latency-sensitive, session-scoped, and often recomputable inference state. Kairo explores whether Linux can schedule, classify, prioritize, and place this traffic more intelligently on generic NVMe SSDs.

## Problem Statement

Modern long-context and agentic AI inference creates a storage workload that Linux does not currently treat as first-class. Decode reads are latency-critical. Prefetch reads are important but not immediately blocking. Prefill writes are background relative to decode. Eviction and discard are lowest priority. When this inference state spills onto SSD-backed tiers, decode-critical reads can compete with background writes, cleanup traffic, filesystem activity, and unrelated storage work.

Kairo asks a direct systems question:

> Can Linux block-layer changes reduce p99 decode-read latency and improve mixed prefill/decode behavior for AI inference-like KV-cache workloads on generic NVMe SSDs?

## Why AI KV-Cache I/O Is Different

AI KV-cache traffic has a distinctive shape:

```text
large-block reads
read-dominant decode phase
append-heavy prefill writes
deadline-aware prefetch
session/model scoping
immutable-after-write cache objects
large-chunk eviction
recomputable inference state
```

Traditional Linux block scheduling does not explicitly recognize that combination of urgency, mutability, reuse, and recomputability.

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
| - ioprio / placement / lifetime hints                   |
+---------------------------------------------------------+
| Kairo Block Layer                                       |
| - request classification                                |
| - decode-critical priority lane                         |
| - prefetch-aware scheduling                             |
| - large-block coalescing                                |
| - ephemeral/recomputable semantics                      |
| - model/session/lifetime propagation                    |
+---------------------------------------------------------+
| Generic NVMe Backend                                    |
| - mq-deadline extensions                                |
| - blk-mq metadata                                       |
| - optional ZNS / Streams / FDP mapping                  |
| - fallback to generic behavior                          |
+---------------------------------------------------------+
```

## Full Architecture Scope

Kairo is intentionally broader than a single scheduler tweak. The repository explores:

- KV-cache I/O classification
- `mq-deadline` decode-critical read priority
- prefill/background write demotion
- prefetch-aware scheduling
- large-block I/O coalescing
- `io_uring` and `O_DIRECT` benchmark paths
- model/session/lifetime placement hints
- ephemeral/recomputable cache semantics
- optional ZNS, NVMe Streams, and FDP backend mapping
- benchmark-driven validation

## Initial Kernel Patch Strategy

The first working patch starts in `mq-deadline` and uses existing `ioprio` metadata as a temporary local classification mechanism:

```text
RT prio 0 read  -> KAIO_DECODE_READ
RT prio 1 read  -> KAIO_PREFETCH_READ
BE prio 7 write -> KAIO_PREFILL_WRITE
discard         -> KAIO_EVICT
```

This is an internal RFC/POC mechanism only. It is not a permanent UAPI proposal.

Initial patch artifacts:

- [`kernel/patches/0001-rfc-kairo-mq-deadline-decode-priority.patch`](kernel/patches/0001-rfc-kairo-mq-deadline-decode-priority.patch)
- [`kernel/patches/0002-rfc-kairo-block-request-classification.patch`](kernel/patches/0002-rfc-kairo-block-request-classification.patch)
- [`kernel/patches/0003-rfc-kairo-debugfs-scheduler-stats.patch`](kernel/patches/0003-rfc-kairo-debugfs-scheduler-stats.patch)

## Benchmark Strategy

The primary benchmark path is [`bench/kairo_bench.c`](bench/kairo_bench.c), a compilable pthreads benchmark that models:

- decode reader threads
- prefetch reader threads
- prefill writer threads
- large-block reads and writes
- direct I/O where available
- per-thread `ioprio` assignment

`fio` profiles in [`bench/fio`](bench/fio) provide quick workload variants for decode-heavy, mixed interference, multi-model, and eviction-pressure scenarios.

## Success Metrics

Primary metric:

- p99 decode-read latency under mixed prefill-write pressure

Secondary metrics:

- p95 decode-read latency
- average decode-read latency
- write throughput
- aggregate throughput
- starvation behavior
- multi-model interference

## Non-Goals

- vendor-specific SSD, GPU, DPU, or inference dependencies
- permanent UAPI design at this stage
- production-readiness claims
- guaranteed speedup claims
- LKML submission at this stage

## Build Benchmark

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

## Repository Layout

- [`docs/architecture.md`](docs/architecture.md)
- [`docs/aggressive_poc_plan.md`](docs/aggressive_poc_plan.md)
- [`docs/kernel_patch_plan.md`](docs/kernel_patch_plan.md)
- [`docs/benchmark_plan.md`](docs/benchmark_plan.md)
- [`docs/api_hints.md`](docs/api_hints.md)
- [`docs/storage_semantics.md`](docs/storage_semantics.md)
- [`docs/placement_lifetime_hints.md`](docs/placement_lifetime_hints.md)
- [`include/kairo_hints.h`](include/kairo_hints.h)
- [`kernel/patches/README.md`](kernel/patches/README.md)
- [`bench/README.md`](bench/README.md)

## Current Project Description

**Kairo is an internal Linux-kernel RFC/POC for AI KV-cache-aware block I/O, prioritizing decode-critical reads and shaping generic NVMe SSD traffic for inference-like workloads.**
