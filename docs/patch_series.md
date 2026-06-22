# Kairo Patch Series

Kairo is an internal Linux-kernel RFC/POC exploring whether AI KV-cache-aware
block-layer behavior can improve generic NVMe SSD performance for inference-like
workloads. The patch series under [kernel/patches](../kernel/patches) is a
local research prototype, not an upstream submission plan.

The repository now also carries a compile-targeted Linux 6.8.x subset under
[kernel/patches/foundation](../kernel/patches/foundation). That subset is the
local apply/build target for Stage 1 and Stage 2 validation.

## Series Overview

| Patch | Area | Primary subsystem | Kairo concept |
| --- | --- | --- | --- |
| `0001` | decode priority | `block/mq-deadline.c` | decode-read fast path |
| `0002` | request classification | `blk-mq` headers/core | internal Kairo I/O classes and merge-instrumentation flags |
| `0003` | io_uring hint plumbing | `io_uring`, `fs`, `blk-mq` metadata | experimental intent propagation from userspace to `kiocb` and conceptual `bio/request` metadata |
| `0004` | large-block coalescing | `blk-merge`, `blk-mq` | merge-bias helpers, per-request merge flags, request-size observability |
| `0005` | prefetch deadlines | `mq-deadline` | separate prefetch urgency |
| `0006` | ephemeral semantics | `fs`, `mm`, `block` | recomputable, ephemeral, avoid-pagecache, and cleanup semantics |
| `0007` | placement/lifetime | `blk-mq`, `blk_types` | model/session/lifetime metadata with helpers and synthetic defaults |
| `0008` | NVMe mapping | `blk_types`, `blk-mq`, `drivers/nvme/host` | generic backend mapping scaffold: `enum kairo_backend_class`, `struct kairo_backend_hint`, feature-detected NVMe hooks with no-op fallback; benchmark-visible via `--backend-mode` |
| `0009` | observability | `mq-deadline`, `debugfs` | counters proving Kairo code paths: dispatch, merge instrumentation, request-size histogram; Stage 6 placement/lifetime counters; Stage 7 backend mapping counters |

## Design Themes

- decode reads are latency-critical and should dispatch ahead of background traffic
- prefetch reads should be deadline-sensitive without being treated identically to decode
- prefill writes should remain throughput-oriented and yield to urgent reads
- eviction/discard should be lowest priority
- large-block KV-cache access should avoid unnecessary fragmentation
- merge instrumentation should reveal whether decode/prefetch reads are coalescing successfully
- model/session/lifetime hints should map to software grouping first and hardware features opportunistically
- all feature-specific backends should degrade to safe no-op behavior on unsupported hardware
- backend mapping (Stage 7) is a neutral class-based layer; NVMe-specific hooks are feature-detected and no-op unless detection succeeds

## Temporary Implementation Strategy

- current benchmark signaling still relies on `ioprio` by default
- `0003` strengthens the local `RWF_KAIRO_*` flow for future `io_uring` use
- Stage 4 benchmark runs can switch between `--hint-mode ioprio|rwf|both`
- Stage 5 benchmark runs can switch between `--semantic-mode normal|ephemeral|recomputable|ephemeral-recomputable`
- later patches intentionally add local-only request metadata to show where Kairo semantics would live
- NVMe backend mapping remains feature-detected and optional
- merge instrumentation uses per-request flags (`KAIRO_HINT_MERGE_ATTEMPTED`, `KAIRO_HINT_MERGE_SUCCESS`)
  set during `attempt_merge` and consumed by the scheduler at dispatch time

## Stage 6.5: Placement Experiment Harness

The repo now also carries a hardened Stage 6.5 harness:

- `scripts/run_stage6_placement_experiment.sh` accepts `<file-path>` and
  `<block-device>`, runs five canonical cases, and saves structured results
  under `results/stage6/<timestamp>/`.
- `scripts/parse_stage6_placement_summary.py` parses `summary.log` files
  and emits CSV or pretty-printed tables with counter delta columns.
- Counter deltas distinguish `NA` (counter not present) from `0` (no change).

Stage 6.5 does not modify the foundation stack or add NVMe/FDP/ZNS mapping.
It is a benchmark/experiment harness hardening pass.

## Stage 7: Generic Backend Mapping Scaffold

The repo now also carries a Stage 7 generic backend mapping layer:

- `kernel/patches/0008` introduces `enum kairo_backend_class`,
  `struct kairo_backend_hint`, and helper functions that convert Stage 6
  placement/lifetime metadata into neutral backend classes.
- Feature-detected NVMe hooks (`nvme_kairo_streams_supported()`,
  `nvme_kairo_fdp_supported()`, `nvme_kairo_zns_supported()`) exist as
  scaffold only — all return `false` until real detection is wired.
- `nvme_kairo_prepare_backend_hint()` and `nvme_kairo_apply_backend_hint()`
  prepare and apply backend hints; the apply function is currently a no-op.
- `kernel/patches/0009` adds 10 backend mapping scaffold counters.
- The benchmark supports `--backend-mode none|generic|streams|fdp|zns` and
  prints mapping output fields (`backend_class`, `stream_id`, etc.).
- `scripts/run_stage7_backend_mapping_experiment.sh` runs five canonical
  backend mapping cases with structured `results/stage7/<timestamp>/` output.
- `scripts/parse_stage7_backend_summary.py` parses summary logs with full
  counter delta column support.

Stage 7 does **not** claim physical data placement, stable UAPI, or
LKML readiness. It is an RFC/POC scaffold for future backend wiring.

## Validation Focus

Immediate validation remains centered on:

- `0001` applicability and build status on Linux 6.8.x
- `0004` merge-bias interaction with existing blk-merge safety checks
- visible sysfs counters when `mq-deadline` is active
- `decode_p99_us`, `decode_p95_us`, and `decode_avg_us` under merge-friendly vs merge-hostile patterns
- proving counter movement via `scripts/validate_kairo_runtime.sh`

## What Remains Open

- exact request lifetime for extra metadata inside `struct request`
- whether merge bias belongs in generic `blk-merge` or only in Kairo-classified paths
- whether `RWF_KAIRO_*` should stay RFC-only or move to a different local hint path
- how much of the Stage 4 scaffold should live in `kiocb` versus direct `bio` metadata
- where Stage 5 semantic intent should be interpreted without undermining explicit durability operations
- whether the request-size histogram is better served by debugfs snapshots
- whether the generic `kairo_backend_class` abstraction maps usefully to real NVMe Streams/FDP/ZNS device capabilities
- how backend detection via `nvme_kairo_streams_supported()` etc. should be wired (identify commands, feature bits)
- whether physical placement through backend hooks provides measurable improvement over software-only grouping (Stage 6)
- whether lifetime class should influence scheduler demotion priority
- whether the scaffold placement/lifetime counters are useful without NVMe backend mapping
