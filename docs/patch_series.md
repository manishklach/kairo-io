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
| `0010` | classification | `blk-mq`, `blk_types` | Real ioprio-to-class request classification at bio-to-request conversion time; replaces deferred classification from 0002 |
| `0011` | anti-starvation | `mq-deadline` | Per-write expiry deadline preventing indefinite deferral under decode pressure; `kairo_write_deadline_ms` sysfs tunable |
| `0012` | tag reservation | `blk-mq-tag` | Reserve 1/8 of hardware queue tags for Kairo decode reads; prevents tag starvation upstream of the scheduler |
| `0013` | dispatch | `mq-deadline` | O(1) decode dispatch FIFO replacing O(n) FIFO scan under spinlock; per-priority dedicated decode/prefetch lists |
| `0014` | io_uring | `io_uring`, `uapi` | `IORING_SQE_KAIRO_CLASS` SQE flag for per-IO classification; propagates through existing hint infrastructure |
| `0015` | merge | `blk-merge` | Real merge bias implementation filling in the empty body from 0004; `kairo_attempt_forced_merge()` with safety checks |
| `0016` | BPF hook | `bpf`, `mq-deadline` | BPF_PROG_TYPE_KAIRO_SCHED for programmable I/O dispatch arbitration; additive fallback to static logic |
| `0017` | tracepoints | `block/blk-mq`, `block/mq-deadline`, `block/blk-merge`, `drivers/nvme/host` | RFC/POC Kairo tracepoint scaffold: 9 TRACE_EVENT definitions in `include/trace/events/kairo.h`; conceptual call sites across block and NVMe layers; bpftrace scripts; trace experiment harness; trace log parser |
| `0018` | adaptive latency controller | `block/mq-deadline` | Adjusts decode and prefetch budgets based on observed decode p99 tail latency; three modes (OFF/OBSERVE/ADAPTIVE); sysfs knobs and counters; six canonical experiment cases |
| `0020` | model/session fairness | `block/mq-deadline` | Per-model and per-session fairness scheduling for multi-tenant AI inference; credit-based decode scheduling; per-entity decode credits with periodic refill; prefetch throttling and write demotion under fairness pressure; noisy session detection; seven sysfs counters and five tunables; five canonical experiment cases |
| `0022` / foundation `0005` | foundation tracepoints | `include/trace/events/kairo.h`, `block/blk-mq.c`, `block/mq-deadline.c` | Compile-targeted foundation tracepoint subset (4 tracepoints: classify, decode dispatch, prefetch dispatch, write demoted); optional apply via `--with-tracepoints`; LINUX-6.8-CHECK annotations; distinct from Stage 8 broad scaffold |
| `0023` | decode latency histogram | `block/mq-deadline.c` | Bucketed decode latency histogram with p95/p99 tail estimator; replaces coarse avg/max heuristic in Stage 10 adaptive controller; 10 histogram buckets from 0-10us to >5ms; enum, struct, helpers, sysfs counters; CONCEPTUAL-HOOK; user-space benchmark histogram output; five canonical experiment cases |
| `0024` | controller feedback wiring | `block/mq-deadline.c`, `include/linux/blk-mq.h` | Wires decode latency observations into the Stage 10 adaptive controller; `kairo_mark_classify_time()`, `kairo_mark_dispatch_time()`, `kairo_decode_queue_latency_us()` helpers; timestamp metadata in `kairo_request_hints`; dispatch call site feeds histogram; missing timestamp handling; 5 feedback counters; `kairo_controller_sample` tracepoint (documented only); 5 canonical experiment cases |
| `0025` | fairness accounting sysfs | `block/mq-deadline.c` | Wires Stage 12 fairness counters into sysfs boilerplate; 5 tunables with bounds-checked show/store; 7 counters with read-only show; counter increment wiring in fairness hooks; LINUX-6.8-CHECK annotations |
| `0026` | blk-cgroup AI I/O controller | `block/blk-kairo-blkcg.c`, `include/linux/blk-cgroup.h` | blk-cgroup policy scaffold for AI inference containers; `enum kairo_blkg_policy_class`; `struct kairo_blkg_policy` with per-class weights; `struct kairo_blkg_stats`; 5 conceptual hooks; blkcg audit script; cgroup interface files documented but implementation deferred |
| `0027` | io_uring KV region hints | `include/linux/blk-mq.h`, `include/uapi/linux/io_uring.h`, `block/blk-mq.c` | io_uring KV region hint scaffold for AI runtime memory regions; `enum kairo_kv_region_type`; `struct kairo_kv_region_hint`; `IORING_REGISTER_KAIRO_KV_REGION` (42) and `IORING_REGISTER_KAIRO_KV_REGIONS` (43) opcodes; 2 conceptual hooks; io_uring audit script; user-space region hint header |
| `0028` | Recompute-aware eviction scheduler | `include/linux/blk-mq.h`, `block/blk-mq.c` | Eviction-class model for AI KV-cache data; `enum kairo_eviction_class`; `struct kairo_eviction_decision`; 5 conceptual helpers (class from request, score, should_prioritize, should_defer, account decision); 10 sysfs eviction counters; eviction score policy with recompute/lifetime/decode-hot penalties |
| `0029` | KV residency heatmap | `include/linux/blk-mq.h`, `block/blk-mq.c` | KV-cache residency heatmap tracking per-region access frequency and recency; `enum kairo_kv_heat_class`; `struct kairo_kv_heatmap_entry`; `struct kairo_kv_heatmap` (fixed-array, 1024 entries); 8 conceptual helpers (lookup, account_decode/prefetch/write/eviction, decay, classify, region_evictable); heat scoring model with 4 weights + age decay; 9 sysfs heatmap counters |
| `0030` | Flash-backed KV admission control | `include/linux/blk-mq.h`, `block/blk-mq.c` | KV-cache admission control scaffold deciding which objects deserve flash storage; `enum kairo_admission_decision` (9 decisions); `struct kairo_admission_policy` (8 config fields); `struct kairo_admission_request` (13 metadata fields); 3 conceptual helpers (decide, accepts, account); 7 priority-ordered policy rules; 10 sysfs admission counters |

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

## Stage 7.5: NVMe Hook Audit and Mapping Hardening

Stage 7.5 is a hardening pass over the Stage 7 backend mapping scaffold:

- **0008 rewritten into sections A–H**: Each section covers one file or
  abstraction layer, with explicit compile-risk annotations.
- **`struct kairo_backend_caps` introduced**: A unified capability
  abstraction replacing the three per-feature `_supported()` helpers.
  Single `nvme_kairo_get_backend_caps()` replaces
  `nvme_kairo_streams_supported()`, `nvme_kairo_fdp_supported()`, and
  `nvme_kairo_zns_supported()`.
- **`kairo_backend_hint_apply_caps()` helper**: Populates hint fields
  from caps in a single call, shared between kernel and (future)
  user-space emulation.
- **Compile-risk annotations**: Every hook point is annotated as
  `COMPILE-TARGET`, `CONCEPTUAL-HOOK`, or `VERSION-SENSITIVE` with
  rationale in comments.
- **Benchmark refactor**: `kairo_compute_backend_model()` consolidates
  the 5 individual backend helpers into a single function returning a
  `struct kairo_backend_model`.
- **Hook-point audit document**: `docs/stage7_5_nvme_hook_audit.md`
  analyzes each hook point against real Linux 6.8 kernel symbols.
- **Hook-point audit script**: `kernel/integration/linux-6.8/audit_nvme_hooks.sh`
  checks a real Linux 6.8 tree for candidate symbols.
- **Python validator**: `scripts/validate_stage7_backend_mapping.py`
  checks 0008, docs, and benchmark for required patterns. Integrated
  into `scripts/validate_patch_stack.sh`.

Stage 7.5 does not add physical placement or NVMe command programming.
It hardens the existing scaffold and documents the hook-point landscape.

## Stage 8: Kernel Observability and Tracepoints

Stage 8 adds an RFC/POC tracepoint scaffolding layer for the full Kairo
request lifecycle:

- **`kernel/patches/0010`** introduces `include/trace/events/kairo.h`
  with 9 TRACE_EVENT definitions covering classification, scheduler
  decisions, dispatch, demotion, merge, semantic flags, placement
  metadata, and backend mapping.
- **Conceptual call sites** in `block/blk-mq.c`, `block/mq-deadline.c`,
  `block/blk-merge.c`, and `drivers/nvme/host/core.c` show where each
  tracepoint would be emitted.
- **bpftrace scripts** (`scripts/bpftrace/kairo_*.bt`) provide
  ready-to-use observability for dispatch latency, scheduler decisions,
  and backend mapping outcomes.
- **Trace experiment script** (`scripts/run_stage8_trace_experiment.sh`)
  runs benchmarks with ftrace or bpftrace capture and saves structured
  results under `results/stage8/<timestamp>/`.
- **Trace log parser** (`scripts/parse_stage8_trace_log.py`) parses
  ftrace/bpftrace logs into CSV or pretty-printed summaries.
- **Tracepoint audit script** (`kernel/integration/linux-6.8/audit_tracepoints.sh`)
  checks a Linux 6.8 tree for tracepoint infrastructure and Kairo
  tracepoint symbols.

Stage 8 does **not** claim stable tracing ABI, LKML readiness, or
production instrumentation. Tracepoints are RFC/POC and may change.

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
