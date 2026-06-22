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
| tracepoints | `0017` | scaffolded | RFC/POC tracepoint layer: 9 tracepoints covering classification, scheduler decisions, dispatch, demotion, merge, semantic flags, placement metadata, and backend mapping; bpftrace scripts; trace experiment harness; trace parser |
| real classification | `0010` | implemented | Real ioprio-to-class mapping at request init time; replaces deferred classification from 0002 |
| write anti-starvation | `0011` | implemented | Per-write expiry deadline preventing indefinite deferral; sysfs tunable |
| tag reservation | `0012` | implemented | Reserve 1/8 of blk-mq tags for decode reads; prevents tag starvation upstream of scheduler |
| O(1) dispatch FIFO | `0013` | implemented | Dedicated decode/prefetch FIFOs replacing O(n) spinlock scan |
| io_uring SQE hint | `0014` | implemented | IORING_SQE_KAIRO_CLASS for per-IO classification |
| real merge bias | `0015` | implemented | kairo_attempt_forced_merge() with safety checks; fills empty body from 0004 |
| BPF dispatch hook | `0016` | conceptual | BPF_PROG_TYPE_KAIRO_SCHED for programmable I/O scheduling |

## Stage 6.5 Status

| Area | Status | Notes |
|------|--------|-------|
| Placement experiment harness | implemented | Hardened `run_stage6_placement_experiment.sh` with `<file-path> <block-device>`, structured results, counter deltas, CSV output |
| Summary parser | implemented | `parse_stage6_placement_summary.py` with `--csv` and `--pretty` output, counter delta columns |
| Counter coverage | updated | `collect_kairo_counters.sh` includes both naming sets for Stage 6 counters |

## Supernova Patch Status (0010–0016)

| Area | Patch | Status | Notes |
|------|-------|--------|-------|
| Real request classification | 0010 | implemented | `kairo_classify_request()` called at request init time; stores io_class for request lifetime |
| Write anti-starvation deadline | 0011 | implemented | `kairo_write_force_deadline_ns` prevents indefinite write deferral under decode pressure |
| NVMe tag reservation | 0012 | implemented | `kairo_tag_reserve_allowed()` reserves 1/8 of blk-mq tags for decode reads |
| O(1) decode dispatch | 0013 | implemented | `per_prio->kairo_decode_head` dedicated FIFO with O(1) pop |
| io_uring SQE hint flag | 0014 | implemented | `IORING_SQE_KAIRO_CLASS` for per-IO classification in io_uring SQE |
| Real merge bias | 0015 | implemented | `kairo_attempt_forced_merge()` with integrity, sector, and class checks |
| BPF dispatch hook | 0016 | conceptual | `BPF_PROG_TYPE_KAIRO_SCHED` — BPF verifier integration is kernel-version-specific |

## Stage 8 Status

| Area | Status | Notes |
|------|--------|-------|
| Tracepoint header | scaffolded | `include/trace/events/kairo.h` with 9 TRACE_EVENT definitions |
| Classification tracepoint | scaffolded | `kairo_request_classified` — io_class, hint_source, flags |
| Scheduler decision tracepoint | scaffolded | `kairo_scheduler_decision` — decision, reason, budget, deadline_ns |
| Decode/prefetch dispatch tracepoints | scaffolded | `kairo_decode_dispatch`, `kairo_prefetch_dispatch` — budget, latency/deadline |
| Demotion tracepoint | scaffolded | `kairo_write_demoted` — io_class, reason, starvation_escape |
| Merge decision tracepoint | conceptual | `kairo_merge_decision` — depends on Stage 3 merge instrumentation |
| Semantic classified tracepoint | conceptual | `kairo_semantic_classified` — depends on Stage 5 metadata plumbing |
| Placement classified tracepoint | scaffolded | `kairo_placement_classified` — model/session/cache-pool/lifetime |
| Backend mapped tracepoint | scaffolded | `kairo_backend_mapped` — backend_class, stream/fdp/zone hints |
| bpftrace latency script | implemented | `scripts/bpftrace/kairo_latency.bt` |
| bpftrace dispatch script | implemented | `scripts/bpftrace/kairo_dispatch.bt` |
| bpftrace backend script | implemented | `scripts/bpftrace/kairo_backend.bt` |
| Trace experiment script | implemented | `scripts/run_stage8_trace_experiment.sh` |
| Trace log parser | implemented | `scripts/parse_stage8_trace_log.py` with `--csv` and `--pretty` |
| Tracepoint audit script | implemented | `kernel/integration/linux-6.8/audit_tracepoints.sh` |
| Stage 8 documentation | implemented | `docs/stage8_kernel_observability.md` |

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

## Stage 9 Status

| Area | Status | Notes |
|------|--------|-------|
| WSL validation snapshot | implemented | `scripts/run_wsl_validation_snapshot.sh` packages local WSL validation evidence and writes `docs/validation_snapshot.md` without overclaiming patched-kernel behavior |
| WSL environment check | implemented | `scripts/check_wsl_environment.sh` reports environment and tool availability without requiring root |
| Snapshot parser | implemented | `scripts/parse_validation_snapshot.py` renders Markdown and CSV from `summary.log` |

## Current Read

The repo now has the shape of the full Kairo architecture, but the maturity is
intentionally uneven:

- `0001`, `0002`, `0005`, and `0009` form the Linux 6.8.x compile-targeted foundation stack
- `kernel/patches/foundation/0001` through `0004` are the preferred local apply/compile target
- `0003`, `0006`, and `0007` remain scaffold-heavy earlier stages
- `0004` remains an aggressive kernel RFC/POC path that still needs its own implement-then-validate cycle
- `0008` is now a generic backend mapping scaffold with benchmark-visible output
- Stage 9 packages local WSL validation evidence without claiming patched-kernel runtime behavior
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
