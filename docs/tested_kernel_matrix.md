# Tested Kernel Matrix

| Kernel version | Foundation apply check | Foundation apply | Foundation symbol validation | `block/mq-deadline.o` build | `block/blk-mq.o` build | Boot tested | Sysfs visible | Counter movement | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Linux 6.8.12 | passed | passed | passed | passed | failed | pending | pending | pending | `scripts/validate_patch_stack.sh`, `apply_foundation_stack.sh`, and `validate_foundation_stack.sh` passed on the local `linux-6.8.12-min` tree. The direct patched `block/mq-deadline.o` build passed. The combined `block/blk-mq.o block/mq-deadline.o` path failed on local `blk-mq.o` `struct blk_plug` member errors that also reproduced outside the Kairo foundation path. Boot and runtime validation remain unrun. |
| Linux 6.8.x (additional trees) | pending | not run | not run | not run | not run | pending | pending | pending | add rows as local validation expands |

## WSL Validation Scope

- Environment: WSL
- Kernel: detected dynamically
- Scope: repo validation + benchmark build + dry-run harness + optional user-space smoke benchmark
- Custom kernel boot: not applicable / not run
- Kairo sysfs counters: not available unless a patched kernel is running
- Physical NVMe placement: not validated

## Stage 7.5 Status

Stage 7.5 (NVMe hook audit and mapping hardening) is a metadata-level
verification pass:

- `docs/stage7_5_nvme_hook_audit.md` — analyzes each 0008 hook point
  against Linux 6.8 real kernel symbols
- `kernel/integration/linux-6.8/audit_nvme_hooks.sh` — programmatic
  audit checking candidate symbol presence
- `scripts/validate_stage7_backend_mapping.py` — validates 0008 sections,
  docs, and benchmark against required patterns
- Integrated into `scripts/validate_patch_stack.sh`
- Benchmark refactored: `kairo_compute_backend_model()` consolidation
- 0008 rewritten with `kairo_backend_caps` abstraction and compile-risk
  annotations

Stage 7.5 does not change foundation status or kernel compilation targets.

## Patch 0010 Stage 8 Tracepoint Status

Stage 8 (kernel observability and tracepoints) is an RFC/POC scaffold:

- `kernel/patches/0010-rfc-kairo-tracepoints-observability.patch`
  defines 9 tracepoints in `include/trace/events/kairo.h`
- Conceptual call sites in block and NVMe layers (not compile-validated)
- bpftrace scripts, experiment harness, trace parser, and audit script
  exist as proof-of-concept tooling
- Not foundation-integrated; requires the full Kairo patch stack for
  tracepoint activation
- Not LKML-ready or stable ABI

## Patch 0008/0009 Stage 7 Mapping Status

Stage 7 (`0008`, `0009`) adds a generic backend mapping scaffold with
feature-detected NVMe hooks. These patches are:

- Metadata-level: `enum kairo_backend_class`, `struct kairo_backend_hint`,
  helpers, and 10 scaffold counters
- Feature-detected: NVMe Streams/FDP/ZNS detection hooks return `false`
  until real detection is wired
- No-op safe: all hooks degrade gracefully when backend support is absent
- Not yet foundation-integrated: Stage 7 remains in the broad RFC/POC patch
  series, not in `kernel/patches/foundation/`

## Stage 10 Adaptive Controller Status

Stage 10 (`0018`) adds a conceptual adaptive decode tail-latency controller:

- **Controller structure**: `enum kairo_controller_mode`, `struct kairo_latency_controller`
  defined in `block/mq-deadline.c` with conceptual annotations
- **Policy**: Adjusts decode/prefetch budgets based on observed decode p99 vs target
- **Sysfs**: Tunables (`kairo_controller_enable`, `kairo_controller_mode`,
  `kairo_target_decode_p99_us`, `kairo_control_window_ms`) and counters
  (`kairo_controller_updates`, `kairo_controller_*_events`, etc.)
- **Decode latency measurement**: CONCEPTUAL-HOOK — no completion path call site wired
- **p95/p99 computation**: Coarse avg/max heuristic; real implementation needs
  exponential latency buckets
- **Tracepoint**: `kairo_controller_update` documented in 0018 but not wired into
  Stage 8 tracepoint set
- **Experiment harness**: Six canonical cases with structured results under
  `results/stage10/<timestamp>/`
- **Summary parser**: `parse_stage10_latency_controller_summary.py` with CSV and
  pretty-printed output, controller counter delta columns

Stage 10 is **not** foundation-integrated, **not** LKML-ready, and **not**
boot-validated. It is an RFC/POC adaptive scheduling policy scaffold.

## Stage 12 Model/Session Fairness Status

Stage 12 (`0020`) adds a conceptual per-model/per-session fairness scheduler:

- **Fairness data structures**: `struct kairo_fair_entity` and `struct kairo_fairness_state`
  defined in `block/mq-deadline.c` with conceptual annotations
- **Credit model**: Per-entity decode credits refilled periodically; decode dispatch
  consumes credits; entities with zero credits have prefetch throttled and writes demoted
- **Entity lookup**: Linear scan of fixed-size arrays (64 models, 256 sessions)
- **Noisy session detection**: Configurable threshold; flagged sessions get prefetch
  throttled even if credits remain
- **Sysfs**: Tunables (`kairo_fairness_enable`, `kairo_model_decode_credit`,
  `kairo_session_decode_credit`, `kairo_fairness_refill_ms`,
  `kairo_noisy_session_threshold`) and counters (`kairo_fairness_refills`,
  `kairo_fairness_model_throttles`, `kairo_fairness_session_throttles`,
  `kairo_noisy_session_events`, `kairo_protected_decode_dispatches`,
  `kairo_prefetch_fairness_throttles`, `kairo_write_fairness_demotions`)
- **Hook points**: `kairo_fairness_allow_decode`, `kairo_fairness_throttle_prefetch`,
  `kairo_fairness_demote_write`, `kairo_fairness_account_dispatch`,
  `kairo_fairness_refill_if_needed` -- all CONCEPTUAL-HOOK
- **Experiment harness**: Five canonical cases with structured results under
  `results/stage12/<timestamp>/`
- **Summary parser**: `parse_stage12_fairness_summary.py` with CSV and pretty-printed
  output, fairness counter delta columns

Stage 12 is **not** foundation-integrated, **not** LKML-ready, and **not**
boot-validated. It is an RFC/POC fairness scheduling policy scaffold for
multi-tenant AI inference workloads.

## Stage 13 Decode Latency Histogram Status

Stage 13 (`0023`) adds a bucketed decode latency histogram with tail estimator:

- **Histogram data structures**: `enum kairo_decode_latency_bucket` (10 buckets)
  and `struct kairo_latency_histogram` with counting, sum, max, and samples
- **Helpers**: `kairo_latency_bucket_for_us()`, `kairo_latency_histogram_add()`,
  `kairo_latency_histogram_estimate_percentile()`, `kairo_latency_histogram_reset()`
- **Controller integration**: `dd_kairo_controller_update_from_hist()` replaces
  avg/max heuristic with histogram-based p95/p99 estimation; observe-only when
  samples < `KAIRO_CTRL_MIN_SAMPLES`
- **Sysfs counters**: 10 histogram bucket counters (`kairo_decode_lat_*`),
  `kairo_decode_latency_samples`, `kairo_decode_latency_max_us`
- **User-space benchmark**: Histogram bucket output from user-space decode
  latency samples (`decode_lat_0_10us=` through `decode_lat_gt_5ms=`)
- **Experiment harness**: Five canonical cases with structured results under
  `results/stage13/<timestamp>/`
- **Summary parser**: `parse_stage13_latency_histogram_summary.py` with CSV and
  pretty-printed output, all 10 bucket columns plus p95/p99/avg

Stage 13 is **not** foundation-integrated, **not** LKML-ready, and **not**
boot-validated. It is an RFC/POC histogram scaffold. Completion-path call sites
are CONCEPTUAL-HOOK. Kernel-side histogram movement is not claimed unless
tested on a patched kernel.

## Stage 14 Controller Feedback Wiring Status

Stage 14 (`0024`) wires decode latency observations into the Stage 10 controller:

- **Timestamp metadata**: `classify_time_ns`, `dispatch_time_ns`, `decode_queue_latency_us`
  added to `struct kairo_request_hints` in `include/linux/blk-mq.h`
- **Helpers**: `kairo_mark_classify_time()`, `kairo_mark_dispatch_time()`,
  `kairo_decode_queue_latency_us()` — compile-targeted inline functions
- **Dispatch call site**: `dd_kairo_dispatch_decode_request()` records dispatch time
  and feeds decode queue latency into the controller (CONCEPTUAL-HOOK)
- **Missing timestamp handling**: Zero classify_time increments
  `kairo_controller_missing_timestamp` and skips the sample
- **Histogram integration**: Controller update uses Stage 13 histogram for
  p95/p99 estimation instead of avg/max heuristic; histogram reset on window expiry
- **Sysfs counters**: `kairo_controller_latency_samples`,
  `kairo_controller_missing_timestamp`, `kairo_controller_latency_updates`,
  `kairo_controller_histogram_resets`, `kairo_controller_decode_latency_gt_target`
- **Tracepoint**: `kairo_controller_sample` documented but not wired
- **Experiment harness**: Five canonical cases with structured results under
  `results/stage14/<timestamp>/`

Stage 14 is **not** foundation-integrated, **not** LKML-ready, and **not**
boot-validated. The dispatch call site is CONCEPTUAL-HOOK with LINUX-6.8-CHECK
annotations. Kernel-side feedback loop movement is not claimed unless tested
on a patched kernel.

## Stage 15 Fairness Accounting and Sysfs Wiring Status

Stage 15 (`0025`) wires Stage 12 fairness counters into sysfs boilerplate:

- **Sysfs tunables**: `kairo_fairness_enable`, `kairo_model_decode_credit`,
  `kairo_session_decode_credit`, `kairo_fairness_refill_ms`,
  `kairo_noisy_session_threshold` -- all with show/store and bounds checking
- **Sysfs counters**: `kairo_fairness_refills`, `kairo_fairness_model_throttles`,
  `kairo_fairness_session_throttles`, `kairo_noisy_session_events`,
  `kairo_protected_decode_dispatches`, `kairo_prefetch_fairness_throttles`,
  `kairo_write_fairness_demotions` -- all read-only with sysfs_emit
- **Accounting wiring**: All 7 counters wired into Stage 12 fairness hooks
  (CONCEPTUAL-HOOK); each counter is an event observation, not a unique
  request count
- **Experiment harness**: `run_stage15_fairness_accounting_experiment.sh` with
  five canonical cases under `results/stage15/<timestamp>/`
- **Summary parser**: `parse_stage15_fairness_accounting_summary.py` with CSV
  and pretty-printed output, fairness counter delta columns
- **Collector coverage**: `collect_kairo_counters.sh` already includes fairness
  counters before Stage 15

Stage 15 is **not** foundation-integrated, **not** LKML-ready, and **not**
boot-validated. The dispatch-path integration of fairness hooks remains
CONCEPTUAL-HOOK. Kernel-side fairness counter movement is not claimed unless
tested on a patched kernel.

## Stage 16 blk-cgroup AI I/O Controller Status

Stage 16 (`0026`) adds a conceptual blk-cgroup AI I/O controller scaffold:

- **Policy model**: `enum kairo_blkg_policy_class` with 6 classes
  (DEFAULT, PRODUCTION_DECODE, BATCH_PREFILL, PREFETCH, EVICTION, BACKGROUND)
  mapping Kairo request classes to cgroup-level I/O policy
- **Data structures**: `struct kairo_blkg_policy` (per-cgroup policy with
  weights, target p99, and flags) and `struct kairo_blkg_stats` (per-cgroup
  counters)
- **Conceptual hooks**: `kairo_blkg_policy_from_request`, `kairo_blkg_allow_decode`,
  `kairo_blkg_throttle_prefetch`, `kairo_blkg_demote_write`,
  `kairo_blkg_account_dispatch` -- all defined but never called from dispatch path
- **cgroup interface**: 7 cgroupfs knobs documented
  (`kairo.policy_class`, `kairo.decode_weight`, etc.) but not implemented;
  `blkcg_policy` struct is guarded by `#if 0`
- **blkcg audit script**: `kernel/integration/linux-6.8/audit_blkcg_hooks.sh`
  checks Linux 6.8 for candidate hook points (`blkg_lookup`, `blkcg_policy_register`,
  `bio_blkcg`, etc.)
- **Experiment harness**: `run_stage16_blkcg_experiment.sh` with five canonical
  cases under `results/stage16/<timestamp>/`
- **Summary parser**: `parse_stage16_blkcg_summary.py` with CSV and pretty-printed
  output, blkcg counter delta columns

Stage 16 is **not** foundation-integrated, **not** LKML-ready, and **not**
boot-validated. The `blkcg_policy_register()` call is not executed. The cgroup
interface files are not mounted. Dispatch-path integration of blkcg hooks
remains CONCEPTUAL-HOOK. Kernel-side blkcg counter movement is not claimed
unless tested on a patched kernel with `CONFIG_BLK_CGROUP` enabled and
`CONFIG_BLK_CGROUP_KAIRO` present.

## Stage 17 io_uring KV Region Hints Status

Stage 17 (`0027`) adds a conceptual io_uring KV region hint scaffold:

- **Region type enum**: `enum kairo_kv_region_type` with 6 types
  (NONE, DECODE_CACHE, PREFETCH_CACHE, SESSION_CACHE, MODEL_CACHE,
  RECOMPUTABLE_CACHE) in `include/linux/blk-mq.h`
- **Region hint struct**: `struct kairo_kv_region_hint` with region_id, type,
  model_id, session_id, file_offset, length, lifetime_class, recompute_ok
- **Conceptual hooks**: `kairo_request_has_kv_region()` (always returns false),
  `kairo_apply_kv_region_hint()` (no-op)
- **io_uring opcodes**: `IORING_REGISTER_KAIRO_KV_REGION` (42) and
  `IORING_REGISTER_KAIRO_KV_REGIONS` (43) in `include/uapi/linux/io_uring.h`
  — no handler wired
- **io_uring audit script**: `kernel/integration/linux-6.8/audit_io_uring_hooks.sh`
  checks Linux 6.8 for candidate hook points (`io_init_req`, `io_issue_sqe`,
  `io_read`, `io_write`, etc.)
- **User-space header**: `include/kairo_hints.h` with `enum kairo_user_kv_region_type`,
  `struct kairo_user_kv_region_hint`, `KAIRO_USER_KV_REGION_*` flags, and
  `kairo_user_kv_region_type_name()` helper
- **Benchmark flags**: `--kv-region-id`, `--kv-region-type`, `--kv-region-count`,
  `--kv-region-size`, `--registered-buffer-mode` with output fields
- **Experiment harness**: `run_stage17_io_uring_region_experiment.sh` with five
  canonical cases under `results/stage17/<timestamp>/`
- **Summary parser**: `parse_stage17_io_uring_region_summary.py` with CSV and
  pretty-printed output

Stage 17 is **not** foundation-integrated, **not** LKML-ready, and **not**
boot-validated. The `IORING_REGISTER_KAIRO_KV_REGION` opcode has no handler.
The kernel region store does not exist. Dispatch-path integration of KV region
hints remains CONCEPTUAL-HOOK. The benchmark uses `pread`/`pwrite`, not io_uring.
Kernel-side KV region hint application is not claimed unless tested on a patched
kernel with io_uring KV region registration.

## Stage 18 Recompute-Aware Eviction Scheduler Status

Stage 18 (`0028`) adds a conceptual recompute-aware eviction scheduler scaffold:

- **Eviction class enum**: `enum kairo_eviction_class` with 7 classes
  (NONE, RECOMPUTABLE_SHORT, RECOMPUTABLE_SESSION, EPHEMERAL_PREFETCH,
  SESSION_CACHE, MODEL_CACHE, PERSISTENT_AVOID) in `include/linux/blk-mq.h`
- **Eviction decision struct**: `struct kairo_eviction_decision` with
  eviction_class, model_id, session_id, cache_pool_id, placement_group,
  recompute_ok, ephemeral, persistent_avoid, discard_preferred,
  writeback_required, score, reason_flags
- **Conceptual helpers**: 5 helpers — `kairo_eviction_class_from_request`,
  `kairo_eviction_score_request`, `kairo_should_prioritize_eviction`,
  `kairo_should_defer_eviction`, `kairo_account_eviction_decision` — all
  no-ops, not called from any dispatch path
- **Eviction score policy**: Base scores by class (recomputable_short +100,
  ephemeral_prefetch +90, recomputable_session +80, session_cache +50,
  model_cache +20, persistent -1000); conceptual penalties for decode-hot
  (-500) and recently accessed (-100)
- **Sysfs counters**: 10 counters documented in `collect_kairo_counters.sh`
  — no kobject registration wired
- **User-space header**: `include/kairo_hints.h` with
  `enum kairo_eviction_policy_mode` and `kairo_eviction_policy_name()` helper
- **Benchmark flags**: `--eviction-policy none|recompute-aware|lifetime|mixed`,
  `--eviction-pressure N` with output fields `eviction_policy`,
  `eviction_recompute_ok`, `eviction_lifetime`, `eviction_score_model`,
  `eviction_pressure`
- **Experiment harness**: `run_stage18_recompute_eviction_experiment.sh` with
  six canonical cases under `results/stage18/<timestamp>/`
- **Summary parser**: `parse_stage18_recompute_eviction_summary.py` with CSV
  and pretty-printed output; 11 eviction counter delta fields

Stage 18 is **not** foundation-integrated, **not** LKML-ready, and **not**
boot-validated.  No dispatch path calls the eviction helpers.  Sysfs eviction
counters have no kobject registration.  Decode-latency feedback to eviction
policy is documented but not wired.  Per-request access tracking does not
exist.  Kernel-side eviction scoring is not claimed unless tested on a
patched kernel with eviction counter collection.
