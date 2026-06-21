# Full Architecture Status

| Architecture Area | Patch | Status | Notes |
| --- | --- | --- | --- |
| decode read priority | `0001` | implemented | `mq-deadline` decode-first dispatch path with sysfs knobs |
| request classification | `0002` | implemented | internal enum, helpers, merge-instrumentation flags |
| io_uring hints | `0003` | scaffolded | local RFC path from `RWF_KAIRO_*` into `kiocb`, then conceptual `bio/request` metadata |
| large-block coalescing | `0004` | implemented | merge-bias helpers, per-request flags, blk-merge instrumentation hooks |
| prefetch deadlines | `0005` | scaffolded | separate prefetch metadata and dispatch treatment |
| ephemeral semantics | `0006` | scaffolded | local RFC semantic flags for recomputable, ephemeral, avoid-pagecache, and cleanup intent |
| placement/lifetime | `0007` | scaffolded | model/session/cache-pool metadata |
| NVMe/ZNS/FDP mapping | `0008` | scaffolded | feature-detected mapping hooks with no-op fallback |
| debug counters | `0009` | implemented | sysfs counters for dispatch, merge, and request-size histogram |

## Current Read

The repo now has the shape of the full Kairo architecture, but the maturity is
intentionally uneven:

- `0001` and `0004` are the main kernel proof points
- `0002` and `0009` are technically meaningful RFC/POC scaffolds with concrete instrumentation
- `0003`, `0005`, `0006`, `0007`, `0008` remain scaffold-heavy later stages
- the user-space harness can approximate decode, prefetch, prefill, eviction, and multisession pressure
- the benchmark now supports merge-friendly and merge-hostile access patterns
- the benchmark now also supports `--hint-mode ioprio|rwf|both` for Stage 4 experiments
- the benchmark now also supports `--semantic-mode` for Stage 5 cache-semantic experiments

## What We Can Measure Today

- `decode_avg_us`, `decode_p50_us`, `decode_p95_us`, `decode_p99_us`
- `write_MBps`, `prefetch_read_MBps`, `evict_MBps`
- `ioprio_*_{ok,fail}`
- `rwf_*_{attempts,fail}`
- `rwf_ephemeral_*`, `rwf_recompute_*`, `rwf_no_durability_*`, `rwf_avoid_pagecache_*`
- Kairo sysfs counters: dispatch, starvation escape, merge instrumentation, request-size histogram
- Stage 5 semantic counters: ephemeral, recomputable, no-durability, avoid-pagecache, evict-cleanup
- counter deltas via `scripts/collect_kairo_counters.sh`

## What Needs Real Kernel Validation Next

- `0004` merge-bias interaction with real blk-merge decisions on Linux 6.8.x
- `0003` end-to-end hint propagation from `kiocb` into block-layer metadata
- `0005` interaction between prefetch urgency and existing `mq-deadline` starvation logic
- `0006` semantics around direct I/O preference, cleanup, and page-cache pollution
- `0008` feature detection and graceful fallback on generic NVMe SSDs
