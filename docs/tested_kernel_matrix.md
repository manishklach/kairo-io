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
