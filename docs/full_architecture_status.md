# Full Architecture Status

| Architecture Area | Patch | Status | Notes |
| --- | --- | --- | --- |
| decode read priority | `0001` | implemented | `mq-deadline` decode-first dispatch path with sysfs knobs |
| request classification | `0002` | scaffolded | internal enum and helper, derived from `ioprio` |
| io_uring hints | `0003` | scaffolded | experimental `RWF_KAIRO_*` path into `kiocb` |
| large-block coalescing | `0004` | scaffolded | conservative merge bias for Kairo reads |
| prefetch deadlines | `0005` | scaffolded | separate prefetch metadata and dispatch treatment |
| ephemeral semantics | `0006` | scaffolded | recomputable and ephemeral cache semantics |
| placement/lifetime | `0007` | scaffolded | model/session/cache-pool metadata |
| NVMe/ZNS/FDP mapping | `0008` | scaffolded | feature-detected mapping hooks with no-op fallback |
| debug counters | `0009` | scaffolded | sysfs and debugfs observability for Kairo code paths |

## Current Read

The repo now has the shape of the full Kairo architecture, but the maturity is
intentionally uneven:

- `0001` is the main kernel proof point
- `0002` through `0009` are technically meaningful RFC/POC scaffolds
- the user-space harness can now approximate decode, prefetch, prefill, eviction, and multisession pressure

## What We Can Measure Today

- `decode_avg_us`
- `decode_p50_us`
- `decode_p95_us`
- `decode_p99_us`
- `write_MBps`
- `ioprio_*_{ok,fail}`
- Kairo sysfs counters when the patched `mq-deadline` path is present

## What Needs Real Kernel Validation Next

- `0002` integration with the real Linux 6.8.x request model
- `0005` interaction between prefetch urgency and existing `mq-deadline` starvation logic
- `0006` semantics around direct I/O preference and page-cache pollution
- `0008` feature detection and graceful fallback on generic NVMe SSDs
