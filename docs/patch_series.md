# Kairo Patch Series

Kairo is an internal Linux-kernel RFC/POC exploring whether AI KV-cache-aware
block-layer behavior can improve generic NVMe SSD performance for inference-like
workloads. The patch series under [kernel/patches](../kernel/patches) is a
local research prototype, not an upstream submission plan.

## Series Overview

| Patch | Area | Primary subsystem | Kairo concept |
| --- | --- | --- | --- |
| `0001` | decode priority | `block/mq-deadline.c` | decode-read fast path |
| `0002` | request classification | `blk-mq` headers/core | internal Kairo I/O classes |
| `0003` | io_uring hint plumbing | `io_uring`, `fs` | experimental intent propagation |
| `0004` | large-block coalescing | `blk-merge` | larger merged KV reads |
| `0005` | prefetch deadlines | `mq-deadline` | separate prefetch urgency |
| `0006` | ephemeral semantics | `fs`, `mm`, `block` | recomputable KV-cache behavior |
| `0007` | placement/lifetime | `blk-mq`, `nvme` | model/session/lifetime metadata |
| `0008` | NVMe mapping | `drivers/nvme/host` | generic Streams/FDP/ZNS mapping hooks |
| `0009` | observability | `mq-deadline`, `debugfs` | counters proving Kairo code paths |

## Design Themes

- decode reads are latency-critical and should dispatch ahead of background traffic
- prefetch reads should be deadline-sensitive without being treated identically to decode
- prefill writes should remain throughput-oriented and yield to urgent reads
- eviction/discard should be lowest priority
- large-block KV-cache access should avoid unnecessary fragmentation
- model/session/lifetime hints should map to software grouping first and hardware features opportunistically
- all feature-specific backends should degrade to safe no-op behavior on unsupported hardware

## Temporary Implementation Strategy

- current benchmark signaling relies on `ioprio`
- `0003` sketches an experimental `RWF_KAIRO_*` flow for future `io_uring` use
- later patches intentionally add local-only request metadata to show where Kairo semantics would live
- NVMe backend mapping remains feature-detected and optional

## Validation Focus

Immediate validation remains centered on:

- `0001` applicability and build status on Linux 6.8.x
- visible sysfs counters when `mq-deadline` is active
- `decode_p99_us`, `decode_p95_us`, and `decode_avg_us` under mixed pressure
- proving counter movement via `scripts/validate_kairo_runtime.sh`

## What Remains Open

- exact request lifetime for extra metadata inside `struct request`
- whether merge bias belongs in generic `blk-merge` or only in Kairo-classified paths
- whether `RWF_KAIRO_*` should stay RFC-only or move to a different local hint path
- how much value generic NVMe Streams/FDP/ZNS mapping provides without workload-specific placement control
