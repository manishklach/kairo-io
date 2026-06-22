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
| NVMe/ZNS/FDP mapping | `0008` | implemented | generic backend mapping scaffold: `kairo_backend_class`, `kairo_backend_hint`, feature-detected NVMe hooks with no-op fallback; benchmark-visible via `--backend-mode` |
| debug counters | `0009` | implemented | compile-targeted Linux 6.8.x sysfs counters and tunables; Stage 6 scaffold placement/lifetime counters |

## Stage 6.5 Status

| Area | Status | Notes |
|------|--------|-------|
| Placement experiment harness | implemented | Hardened `run_stage6_placement_experiment.sh` with `<file-path> <block-device>`, structured results, counter deltas, CSV output |
| Summary parser | implemented | `parse_stage6_placement_summary.py` with `--csv` and `--pretty` output, counter delta columns |
| Counter coverage | updated | `collect_kairo_counters.sh` includes both naming sets for Stage 6 counters |

## Stage 7 Status

| Area | Status | Notes |
|------|--------|-------|
| Generic backend mapping scaffold | implemented | `enum kairo_backend_class`, `struct kairo_backend_hint`, helpers, mapping from Stage 6 lifetime metadata |
| NVMe feature-detected hooks | scaffolded | `nvme_kairo_streams_supported`, `nvme_kairo_fdp_supported`, `nvme_kairo_zns_supported` — all return false; `nvme_kairo_prepare_backend_hint` and `nvme_kairo_apply_backend_hint` are no-op safe |
| Backend mapping counters | implemented | 10 scaffold counters in `mq-deadline.c` via `0009` |
| Benchmark backend mode | implemented | `--backend-mode none|generic|streams|fdp|zns` with mapping output fields |
| Experiment harness | implemented | `run_stage7_backend_mapping_experiment.sh` with five canonical cases |
| Summary parser | implemented | `parse_stage7_backend_summary.py` with `--csv` and `--pretty` |
| Counter coverage | updated | `collect_kairo_counters.sh` includes Stage 7 counters |

## Stage 7.5 Status

| Area | Status | Notes |
|------|--------|-------|
| NVMe hook-point audit document | implemented | `docs/stage7_5_nvme_hook_audit.md` — classifies each hook as compile-target or conceptual, with compile risk analysis |
| 0008 section A–H rewrite | implemented | Reorganized with `kairo_backend_caps` abstraction, compile-risk annotations per section |
| Backend capability abstraction | implemented | `struct kairo_backend_caps` replaces per-feature `_supported()` helpers |
| Compile-risk annotation convention | implemented | `COMPILE-TARGET` / `CONCEPTUAL-HOOK` / `VERSION-SENSITIVE` annotations across all hook points |
| Benchmark backend model refactor | implemented | `kairo_compute_backend_model()` consolidates 5 individual helpers |
| Hook-point audit script | implemented | `kernel/integration/linux-6.8/audit_nvme_hooks.sh` — checks real kernel tree for candidate symbols |
| Python validator | implemented | `scripts/validate_stage7_backend_mapping.py` — checks 0008, docs, benchmark for required patterns |
| Validator integration | implemented | `validate_patch_stack.sh` calls Python validator and checks Stage 7.5 files |

## Current Read

The repo now has the shape of the full Kairo architecture, but the maturity is
intentionally uneven:

- `0001`, `0002`, `0005`, and `0009` form the Linux 6.8.x compile-targeted foundation stack
- `kernel/patches/foundation/0001` through `0004` are the preferred local apply/compile target
- `0003`, `0006`, and `0007` remain scaffold-heavy earlier stages
- `0004` remains an aggressive kernel RFC/POC path that still needs its own implement-then-validate cycle
- `0008` is now a generic backend mapping scaffold with benchmark-visible output
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
- Stage 7 backend mapping counters: `kairo_backend_mapping_attempts`, `kairo_backend_*_hints`, `kairo_backend_*_lived`/`_local`/`_persistent`
- Stage 7 benchmark output: `backend_mode`, `backend_class`, `stream_id`, `fdp_placement_id`, `zone_hint`, `backend_noop_fallback`
- counter deltas via `scripts/collect_kairo_counters.sh`

## What Needs Real Kernel Validation Next

- foundation stack boot validation and runtime counter movement on Linux 6.8.x
- `0004` merge-bias interaction with real blk-merge decisions on Linux 6.8.x
- `0003` end-to-end hint propagation from `kiocb` into block-layer metadata
- `0006` semantics around direct I/O preference, cleanup, and page-cache pollution
- `0008` feature detection, backend class mapping, and graceful fallback on generic NVMe SSDs
- Stage 6 placement/lifetime scaffold counter movement in a patched kernel
- Stage 7 backend mapping scaffold counter movement in a patched kernel
