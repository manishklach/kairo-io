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
| adaptive latency controller | `0018` | conceptual | Adjusts decode/prefetch budgets based on observed decode p99 latency; sysfs knobs and counters; six canonical experiment cases |
| foundation tracepoints | `0022` / foundation `0005` | compile-targeted | Four compile-targeted tracepoints (classify, decode dispatch, prefetch dispatch, write demoted) for Linux 6.8.x foundation; optional apply via `--with-tracepoints`; `LINUX-6.8-CHECK` annotations |
| model/session fairness | `0020` | conceptual | Per-model and per-session fairness scheduler for multi-tenant AI inference; credit-based decode scheduling; prefetch throttling and write demotion under fairness pressure; noisy session detection; seven sysfs counters; five canonical experiment cases |
| decode latency histogram | `0023` | conceptual | Bucketed decode latency histogram with p95/p99 tail estimator; replaces avg/max heuristic in Stage 10 controller; 10 histogram buckets; 12 sysfs counters; five canonical experiment cases; user-space benchmark histogram output |

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

## Stage 10 Status

| Area | Status | Notes |
|------|--------|-------|
| Controller data structure | implemented | `enum kairo_controller_mode`, `struct kairo_latency_controller` in mq-deadline.c |
| Controller init/update logic | implemented | `dd_kairo_controller_init()`, `dd_kairo_controller_update()`, `dd_kairo_controller_apply()` |
| Decode latency sampling | conceptual | `dd_kairo_controller_note_decode_latency()` defined but no call site wired |
| p95/p99 computation | conceptual | Coarse avg/max heuristic; real implementation needs exponential latency buckets |
| Budget adjustment policy | implemented | Boost/relax decode budget, throttle/restore prefetch based on decode p99 vs target |
| Write demotion pressure signal | conceptual | `controller_release_write_events` counter tracks pressure; demotion helpers reference controller state |
| Controller sysfs knobs | implemented | `kairo_controller_enable`, `kairo_controller_mode`, `kairo_target_decode_p99_us`, `kairo_control_window_ms` |
| Controller sysfs counters | implemented | `kairo_controller_updates`, `kairo_controller_*_events`, `kairo_controller_insufficient_samples` |
| Controller observed state | implemented | `kairo_observed_decode_p99_us`, `kairo_observed_decode_p95_us`, `kairo_observed_decode_avg_us`, `kairo_adaptive_decode_budget`, `kairo_adaptive_prefetch_budget` |
| Demotion pressure integration | conceptual | `dd_kairo_should_demote_prefill/evict` reference controller decode pressure signal |
| Controller update call site | implemented | Call in `dd_dispatch_request()` after kairo_enable check |
| Controller update tracepoint | documented | `kairo_controller_update` TRACE_EVENT described in 0018 but not wired; add to patch 0017 after validation |
| Experiment harness | implemented | `run_stage10_latency_controller_experiment.sh` with six canonical cases, structured output, counter collection |
| Summary parser | implemented | `parse_stage10_latency_controller_summary.py` with CSV and pretty-printed output, counter delta columns |
| Counter coverage | updated | `collect_kairo_counters.sh` includes Stage 10 controller counters |
| Stage 10 documentation | implemented | `docs/stage10_adaptive_latency_controller.md` |

## Stage 9 Status

| Area | Status | Notes |
|------|--------|-------|
| WSL validation snapshot | implemented | `scripts/run_wsl_validation_snapshot.sh` packages local WSL validation evidence and writes `docs/validation_snapshot.md` without overclaiming patched-kernel behavior |
| WSL environment check | implemented | `scripts/check_wsl_environment.sh` reports environment and tool availability without requiring root |
| Snapshot parser | implemented | `scripts/parse_validation_snapshot.py` renders Markdown and CSV from `summary.log` |

## Stage 11 Status

| Area | Status | Notes |
|------|--------|-------|
| Foundation tracepoint header | implemented | `include/trace/events/kairo.h` with 4 TRACE_EVENT definitions in foundation patch 0005 |
| Classification tracepoint | compile-targeted | `kairo_request_classified` — dev, sector, nr_bytes, op, ioprio, io_class, flags |
| Decode dispatch tracepoint | compile-targeted | `kairo_decode_dispatch` — dev, sector, nr_bytes, budget_used; trace call in `dd_kairo_dispatch_decode_request()` |
| Prefetch dispatch tracepoint | compile-targeted | `kairo_prefetch_dispatch` — dev, sector, nr_bytes, budget_used, deadline_ns, deadline_near; LINUX-6.8-CHECK annotation |
| Write demoted tracepoint | compile-targeted | `kairo_write_demoted` — dev, sector, nr_bytes, io_class, reason, starvation_escape; LINUX-6.8-CHECK annotation |
| Header includes | implemented | `#include <trace/events/kairo.h>` in both `block/blk-mq.c` and `block/mq-deadline.c` |
| Optional apply | implemented | `apply_foundation_stack.sh --with-tracepoints` applies patch 0005; default is patches 0001-0004 only |
| Broad RFC mirror | implemented | `0022-rfc-kairo-foundation-tracepoints-linux-6.8.patch` with RFC/POC header |
| Foundation validation script | implemented | `validate_foundation_tracepoints.sh` checks header, TRACE_EVENTs, includes, and LINUX-6.8-CHECK annotations |
| Experiment harness | implemented | `run_stage11_foundation_trace_experiment.sh` with trace detection, ftrace capture, and structured results |
| Summary parser | implemented | `parse_stage11_foundation_trace_summary.py` with CSV and pretty-printed output |
| Stage 11 documentation | implemented | `docs/stage11_foundation_tracepoints.md` |

## Stage 13 Status

| Area | Status | Notes |
|------|--------|-------|
| Decode latency histogram | scaffolded | `enum kairo_decode_latency_bucket`, `struct kairo_latency_histogram` in mq-deadline.c |
| Bucket mapping helper | scaffolded | `kairo_latency_bucket_for_us()` maps latency to bucket index |
| Histogram add | conceptual | `kairo_latency_histogram_add()` defined but no completion-path call site wired |
| Percentile estimation | conceptual | `kairo_latency_histogram_estimate_percentile()` bucket-based cumulative search |
| Histogram reset | scaffolded | `kairo_latency_histogram_reset()` clears histogram state |
| Controller integration | conceptual | `dd_kairo_controller_update_from_hist()` populates observed p95/p99 from histogram |
| Histogram sysfs counters | scaffolded | 10 bucket counters + samples + max_us |
| Experiment harness | implemented | `run_stage13_latency_histogram_experiment.sh` with five canonical cases |
| Summary parser | implemented | `parse_stage13_latency_histogram_summary.py` with CSV and pretty-printed output |
| Benchmark histogram output | implemented | 10 decode latency bucket fields printed from user-space samples |
| Counter coverage | updated | `collect_kairo_counters.sh` includes Stage 13 histogram bucket counters |
| Stage 13 documentation | implemented | `docs/stage13_decode_latency_histogram.md` |

## Stage 12 Status

| Area | Status | Notes |
|------|--------|-------|
| Fairness data structures | scaffolded | `struct kairo_fair_entity`, `struct kairo_fairness_state` in mq-deadline.c |
| Entity lookup | conceptual | Linear scan of fixed-size arrays (up to 64 models, 256 sessions) |
| Credit refill mechanism | conceptual | Called from dispatch path; needs timer-based refill for production |
| Noisy session detection | conceptual | Threshold-based detection with counter |
| Fairness dispatch gating | conceptual | `kairo_fairness_allow_decode` hook defined |
| Prefetch throttling | conceptual | `kairo_fairness_throttle_prefetch` hook defined |
| Write demotion pressure | conceptual | `kairo_fairness_demote_write` hook defined |
| Entity accounting | conceptual | `kairo_fairness_account_dispatch` hook defined |
| Fairness sysfs counters | scaffolded | 7 counters defined in patch but not wired in sysfs boilerplate |
| Fairness sysfs tunables | scaffolded | 5 tunables defined in patch but not wired in sysfs boilerplate |
| Experiment harness | implemented | `run_stage12_fairness_experiment.sh` with five canonical cases |
| Summary parser | implemented | `parse_stage12_fairness_summary.py` with CSV and pretty-printed output |
| Benchmark noisy flags | implemented | `--noisy-session`, `--noisy-model`, `--noisy-multiplier` in kairo_bench.c |
| Counter coverage | updated | `collect_kairo_counters.sh` includes Stage 12 fairness counters |
| Stage 12 documentation | implemented | `docs/stage12_model_session_fairness.md` |

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
- Stage 13 histogram bucket counts from user-space benchmark samples

## What Needs Real Kernel Validation Next

- foundation stack boot validation and runtime counter movement on Linux 6.8.x
- `0004` merge-bias interaction with real blk-merge decisions on Linux 6.8.x
- `0003` end-to-end hint propagation from `kiocb` into block-layer metadata
- `0006` semantics around direct I/O preference, cleanup, and page-cache pollution
- `0008` feature detection, backend class mapping, and graceful fallback on generic NVMe SSDs
- Stage 6 placement/lifetime scaffold counter movement in a patched kernel
- Stage 7 backend mapping scaffold counter movement in a patched kernel
