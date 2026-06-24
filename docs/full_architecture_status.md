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
| controller feedback wiring | `0024` | conceptual | Wires decode latency observations into the Stage 10 adaptive controller; timestamp metadata in request hints; classify/dispatch time recording; missing timestamp handling; histogram-based controller update; 5 feedback counters; 5 canonical experiment cases; `kairo_controller_sample` tracepoint (documented only) |
| fairness accounting and sysfs wiring | `0025` | conceptual | Wires Stage 12 fairness counters into sysfs boilerplate with DD_RO_ATTR macros; adds show/store for 5 tunables with bounds checking; adds show for 7 counters; counters wired into fairness hooks as event observations; LINUX-6.8-CHECK annotations |
| blk-cgroup AI I/O controller | `0026` | conceptual | blk-cgroup policy scaffold mapping Kairo request classes to cgroup-level I/O budgets; `enum kairo_blkg_policy_class`, `struct kairo_blkg_policy`, `struct kairo_blkg_stats`; 5 conceptual hooks; blkcg audit script; cgroup interface files documented only |
| io_uring KV region hints | `0027` | conceptual | io_uring KV region hint scaffold modeling AI runtime memory regions as registered buffer/file tags; `enum kairo_kv_region_type`, `struct kairo_kv_region_hint`; 2 conceptual hooks; io_uring audit script; user-space region hint structs and benchmark flags |
| Recompute-aware eviction scheduler | `0028` | conceptual | Eviction-class model and scoring scaffold for AI KV-cache data; `enum kairo_eviction_class`, `struct kairo_eviction_decision`; 5 conceptual helpers; 10 sysfs eviction counters; recompute-aware eviction scoring; benchmark eviction policy modeling |
| KV residency heatmap | `0029` | conceptual | KV-cache residency heatmap tracking per-region access frequency and recency; `enum kairo_kv_heat_class`, `struct kairo_kv_heatmap_entry`, `struct kairo_kv_heatmap`; 8 conceptual helpers; heat scoring model; 9 sysfs heatmap counters; benchmark heatmap modeling |
| Flash-backed KV admission control | `0030` | conceptual | KV-cache admission control scaffold deciding which objects deserve flash storage; `enum kairo_admission_decision`, `struct kairo_admission_policy`, `struct kairo_admission_request`; 3 conceptual helpers; 10 sysfs admission counters; policy rules (lifetime, recompute cost, decode pressure, model-local, shared) |

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

## Stage 14 Status

| Area | Status | Notes |
|------|--------|-------|
| Timestamp metadata in request hints | scaffolded | `classify_time_ns`, `dispatch_time_ns`, `decode_queue_latency_us` in `kairo_request_hints` |
| `kairo_mark_classify_time()` | compile-targeted | Inline helper in blk-mq.h |
| `kairo_mark_dispatch_time()` | compile-targeted | Inline helper in blk-mq.h |
| `kairo_decode_queue_latency_us()` | compile-targeted | Computes queue delay from timestamps |
| Dispatch call site | conceptual | `dd_kairo_dispatch_decode_request()` records dispatch and feeds controller |
| Controller histogram integration | conceptual | `dd_kairo_controller_update()` uses Stage 13 histogram for p95/p99 |
| Missing timestamp handling | conceptual | Zero classify_time increments `controller_missing_timestamp` |
| Feedback sysfs counters | scaffolded | 5 counters defined in patch |
| `kairo_controller_sample` tracepoint | documented | TRACE_EVENT documented in patch comments; not wired |
| Experiment harness | implemented | `run_stage14_controller_feedback_experiment.sh` with five canonical cases |
| Summary parser | implemented | `parse_stage14_controller_feedback_summary.py` with CSV and pretty output, counter delta columns |
| Counter coverage | updated | `collect_kairo_counters.sh` includes Stage 14 counters |
| Stage 14 documentation | implemented | `docs/stage14_controller_feedback_wiring.md` |

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
| Fairness sysfs counters | wired | 7 counters wired via Stage 15 (0025) |
| Fairness sysfs tunables | wired | 5 tunables wired via Stage 15 (0025) with show/store and bounds checking |
| Experiment harness | implemented | `run_stage12_fairness_experiment.sh` with five canonical cases |
| Summary parser | implemented | `parse_stage12_fairness_summary.py` with CSV and pretty-printed output |
| Benchmark noisy flags | implemented | `--noisy-session`, `--noisy-model`, `--noisy-multiplier` in kairo_bench.c |
| Counter coverage | updated | `collect_kairo_counters.sh` includes Stage 12 fairness counters |
| Stage 12 documentation | implemented | `docs/stage12_model_session_fairness.md` |

## Stage 15 Status

| Area | Status | Notes |
|------|--------|-------|
| Fairness sysfs tunable show/store | implemented | 5 tunables with DD_ATTR, bounds-checked kstrto* store functions |
| Fairness sysfs counter show | implemented | 7 counters with DD_RO_ATTR, sysfs_emit |
| Counter wiring audit | documented | All 7 counters wired into Stage 12 fairness hooks as event observations |
| Experiment harness | implemented | `run_stage15_fairness_accounting_experiment.sh` with five canonical cases |
| Summary parser | implemented | `parse_stage15_fairness_accounting_summary.py` with CSV and pretty-printed output |
| Counter coverage | updated | `collect_kairo_counters.sh` includes all fairness counters |
| Stage 15 documentation | implemented | `docs/stage15_fairness_accounting_sysfs.md` |

## Stage 16 Status

| Area | Status | Notes |
|------|--------|-------|
| blk-cgroup policy enum | scaffolded | `enum kairo_blkg_policy_class` with 6 classes in blk-cgroup.h |
| Policy data structure | scaffolded | `struct kairo_blkg_policy` with weights, flags, target p99 |
| Stats structure | scaffolded | `struct kairo_blkg_stats` with 7 per-cgroup counters |
| Conceptual hooks | scaffolded | 5 hooks defined, all return conservative defaults |
| cgroup interface files | documented | 7 cgroupfs knobs documented but not implemented |
| blkcg audit script | implemented | `audit_blkcg_hooks.sh` checks Linux 6.8 for candidate hook points |
| Experiment harness | implemented | `run_stage16_blkcg_experiment.sh` with five canonical cases |
| Summary parser | implemented | `parse_stage16_blkcg_summary.py` with CSV and pretty-printed output |
| Counter coverage | updated | `collect_kairo_counters.sh` includes blkcg counters |
| Stage 16 documentation | implemented | `docs/stage16_blkcg_ai_io_controller.md` |

## Stage 17 Status

| Area | Status | Notes |
|------|--------|-------|
| KV region type enum | scaffolded | `enum kairo_kv_region_type` with 6 types in blk-mq.h |
| Region hint struct | scaffolded | `struct kairo_kv_region_hint` with region_id, type, offset, length, model/session, lifetime, recompute |
| Conceptual hooks | scaffolded | `kairo_request_has_kv_region()`, `kairo_apply_kv_region_hint()` — both no-ops |
| io_uring opcodes | defined | `IORING_REGISTER_KAIRO_KV_REGION` (42), `IORING_REGISTER_KAIRO_KV_REGIONS` (43) — no handler |
| io_uring audit script | implemented | `audit_io_uring_hooks.sh` checks Linux 6.8 for candidate hook points |
| User-space header | implemented | `kairo_hints.h`: `enum kairo_user_kv_region_type`, `struct kairo_user_kv_region_hint`, flags, name helper |
| Benchmark KV region flags | implemented | `--kv-region-id`, `--kv-region-type`, `--kv-region-count`, `--kv-region-size`, `--registered-buffer-mode` |
| Experiment harness | implemented | `run_stage17_io_uring_region_experiment.sh` with five canonical cases |
| Summary parser | implemented | `parse_stage17_io_uring_region_summary.py` with CSV and pretty-printed output |
| Stage 17 documentation | implemented | `docs/stage17_io_uring_kv_region_hints.md` |

## Stage 18 Status

| Area | Status | Notes |
|------|--------|-------|
| Eviction class enum | scaffolded | `enum kairo_eviction_class` with 7 classes in blk-mq.h |
| Eviction decision struct | scaffolded | `struct kairo_eviction_decision` with score, reason_flags, metadata |
| Conceptual helpers | scaffolded | 5 helpers — all no-ops, not called from dispatch path |
| Eviction score policy | scaffolded | 8 score constants, base score by class, conceptual penalties |
| Sysfs counters | documented | 10 counters in `collect_kairo_counters.sh`, no kobject |
| User-space header | implemented | `kairo_hints.h`: `enum kairo_eviction_policy_mode`, name helper |
| Benchmark eviction flags | implemented | `--eviction-policy`, `--eviction-pressure` |
| Experiment harness | implemented | `run_stage18_recompute_eviction_experiment.sh` with six canonical cases |
| Summary parser | implemented | `parse_stage18_recompute_eviction_summary.py` with CSV/pretty output |
| Stage 18 documentation | implemented | `docs/stage18_recompute_aware_eviction.md` |

## Stage 19 Status

| Area | Status | Notes |
|------|--------|-------|
| Heat class enum | scaffolded | `enum kairo_kv_heat_class` with 6 classes in blk-mq.h |
| Heatmap entry struct | scaffolded | `struct kairo_kv_heatmap_entry` with access counters, timestamps, score |
| Heatmap struct | scaffolded | `struct kairo_kv_heatmap` with fixed-array, decay timing, aggregation |
| Conceptual helpers | scaffolded | 8 helpers — all no-ops, not called from dispatch path |
| Heat scoring policy | scaffolded | 4 weights (decode +20, prefetch +5, write +2, evict -5), decay -10/interval |
| Classification thresholds | scaffolded | HOT >= 100, WARM >= 40, COLD >= 1, EVICTABLE <= 0 + recompute, PROTECTED = persistent |
| Sysfs counters | documented | 9 counters in `collect_kairo_counters.sh`, no kobject |
| User-space header | implemented | `kairo_hints.h`: `enum kairo_heatmap_mode`, name helper |
| Benchmark heatmap flags | implemented | `--heatmap-mode`, `--hot-region-ratio`, `--region-reuse-ratio`, `--cold-region-ratio` |
| Experiment harness | implemented | `run_stage19_kv_heatmap_experiment.sh` with six canonical cases |
| Summary parser | implemented | `parse_stage19_kv_heatmap_summary.py` with CSV/pretty output; 6 heatmap counter delta fields |
| Stage 19 documentation | implemented | `docs/stage19_kv_residency_heatmap.md` |

## Stage 20 Status

| Area | Status | Notes |
|------|--------|-------|
| Admission decision enum | scaffolded | `enum kairo_admission_decision` with 9 decisions in blk-mq.h |
| Admission policy struct | scaffolded | `struct kairo_admission_policy` with 8 fields |
| Admission request struct | scaffolded | `struct kairo_admission_request` with 13 fields |
| Conceptual helpers | scaffolded | 3 helpers — decide, accepts, account — all no-ops |
| Policy rules | scaffolded | 7 priority-ordered conditions (RFC heuristic) |
| Sysfs counters | documented | 10 counters in `collect_kairo_counters.sh`, no kobject |
| User-space header | implemented | `kairo_hints.h`: `enum kairo_admission_mode`, name helper |
| Benchmark admission flags | implemented | `--admission-mode`, `--expected-reuse`, `--expected-lifetime-ms`, `--recompute-cost-us`, `--flash-pressure` |
| Experiment harness | implemented | `run_stage20_kv_admission_experiment.sh` with six canonical cases |
| Summary parser | implemented | `parse_stage20_kv_admission_summary.py` with CSV/pretty output; 10 admission counter delta fields |
| Stage 20 documentation | implemented | `docs/stage20_kv_admission_control.md` |

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
- Stage 14 controller feedback fields from benchmark output

## What Needs Real Kernel Validation Next

- foundation stack boot validation and runtime counter movement on Linux 6.8.x
- `0004` merge-bias interaction with real blk-merge decisions on Linux 6.8.x
- `0003` end-to-end hint propagation from `kiocb` into block-layer metadata
- `0006` semantics around direct I/O preference, cleanup, and page-cache pollution
- `0008` feature detection, backend class mapping, and graceful fallback on generic NVMe SSDs
- Stage 6 placement/lifetime scaffold counter movement in a patched kernel
- Stage 7 backend mapping scaffold counter movement in a patched kernel
