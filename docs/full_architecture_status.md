# Full Architecture Status

| Architecture Area | Patch | Status | Notes |
| --- | --- | --- | --- |
| decode read priority | `0001` | implemented | compile-targeted for Linux 6.8.x in the foundation subset and retained in the broader RFC/POC series |
| request classification | `0002` | implemented | compile-targeted for Linux 6.8.x in the foundation subset |
| io_uring hints | `0003` | scaffolded | local RFC path from `RWF_KAIRO_*` into `kiocb`, then conceptual `bio/request` metadata |
| large-block coalescing | `0004` | implemented | merge-bias helpers, per-request flags, blk-merge instrumentation hooks |
| prefetch deadlines | `0005` | implemented | compile-targeted Linux 6.8.x policy for decode, prefetch, prefill, and evict scheduling |
| ephemeral semantics | `0006` | scaffolded | local RFC semantic flags for recomputable, ephemeral, avoid-pagecache, and cleanup intent |
| placement/lifetime | `0007` | implemented | model/session/lifetime metadata with helpers and synthetic defaults |
| NVMe/ZNS/FDP mapping | `0008` | scaffolded | feature-detected mapping hooks with no-op fallback |
| debug counters | `0009` | implemented | compile-targeted Linux 6.8.x sysfs counters and tunables; Stage 6 scaffold placement/lifetime counters |

## Stage 6.5 Status

| Area | Status | Notes |
|------|--------|-------|
| Placement experiment harness | implemented | Hardened `run_stage6_placement_experiment.sh` with `<file-path> <block-device>`, structured results, counter deltas, CSV output |
| Summary parser | implemented | `parse_stage6_placement_summary.py` with `--csv` and `--pretty` output, counter delta columns |
| Counter coverage | updated | `collect_kairo_counters.sh` includes both naming sets for Stage 6 counters |

## Current Read

The repo now has the shape of the full Kairo architecture, but the maturity is
intentionally uneven:

- `0001`, `0002`, `0005`, and `0009` form the Linux 6.8.x compile-targeted foundation stack
- `kernel/patches/foundation/0001` through `0004` are the preferred local apply/compile target
- `0003`, `0006`, `0007`, and `0008` remain scaffold-heavy later stages
- `0004` remains an aggressive kernel RFC/POC path that still needs its own implement-then-validate cycle
- the user-space harness can approximate decode, prefetch, prefill, eviction, and multisession pressure
- the benchmark now supports merge-friendly and merge-hostile access patterns
- the benchmark now also supports `--hint-mode ioprio|rwf|both` for Stage 4 experiments
- the benchmark now also supports `--semantic-mode` for Stage 5 cache-semantic experiments
- the benchmark now also supports `--model-id`, `--session-id`, `--cache-pool-id`,
  `--placement-group`, `--lifetime`, `--recompute-ok`, `--cache-pools`, and
  `--placement-groups` for Stage 6 placement/lifetime experiments

## What We Can Measure Today

- `decode_avg_us`, `decode_p50_us`, `decode_p95_us`, `decode_p99_us`
- `write_MBps`, `prefetch_read_MBps`, `evict_MBps`
- `ioprio_*_{ok,fail}`
- `rwf_*_{attempts,fail}`
- `rwf_ephemeral_*`, `rwf_recompute_*`, `rwf_no_durability_*`, `rwf_avoid_pagecache_*`
- Kairo sysfs counters: dispatch, starvation escape, merge instrumentation, request-size histogram
- Stage 5 semantic counters: ephemeral, recomputable, no-durability, avoid-pagecache, evict-cleanup
- Stage 6 placement/lifetime scaffold counters: `kairo_placement_hints`, `kairo_lifetime_*_count`, `kairo_has_*_count`
- counter deltas via `scripts/collect_kairo_counters.sh`

## What Needs Real Kernel Validation Next

- foundation stack boot validation and runtime counter movement on Linux 6.8.x
- `0004` merge-bias interaction with real blk-merge decisions on Linux 6.8.x
- `0003` end-to-end hint propagation from `kiocb` into block-layer metadata
- `0006` semantics around direct I/O preference, cleanup, and page-cache pollution
- `0008` feature detection and graceful fallback on generic NVMe SSDs
- Stage 6 placement/lifetime scaffold counter movement in a patched kernel
